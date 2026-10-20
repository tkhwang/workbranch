// The dashboard timeline: one row per live task, its last few hours drawn as
// running / waiting / finished spans from the runtime's transition log.
import type {
	WorkbranchRuntimeTotals,
	WorkbranchRuntimeTransition,
} from "@workbranch/contract";
import type { AgentSession } from "../domain/model";
import type { MainTaskRow } from "./state";

/** How far back the timeline reaches. */
export const TIMELINE_WINDOW_SECONDS = 3 * 60 * 60;

export type TimelineState = "running" | "waiting" | "finished";
export type TimelineTotals = WorkbranchRuntimeTotals;

/** A span in epoch seconds, already clipped to the window. */
export type TimelineSegment = {
	readonly state: TimelineState;
	readonly start: number;
	readonly end: number;
};

/** Where a turn ended: the flow stops and review waiting begins. */
export type TimelineTurnEnd = {
	readonly at: number;
	readonly error: boolean;
};

export type TimelineRow = {
	readonly key: string;
	/** The worktree branch (the first repo's), else the task name. */
	readonly title: string;
	/** The first repo's name; `moreRepos` counts the task's other repos. */
	readonly repo: string | undefined;
	readonly moreRepos: number;
	readonly agent: AgentSession["provider"] | undefined;
	readonly state: TimelineState;
	/** Epoch seconds the lead session entered its state. */
	readonly since: number;
	readonly segments: readonly TimelineSegment[];
	readonly turnEnds: readonly TimelineTurnEnd[];
	/** Session time per state across the retained log; unknown without one. */
	readonly totals: TimelineTotals | undefined;
};

export type TimelineModel = {
	readonly start: number;
	readonly end: number;
	readonly rows: readonly TimelineRow[];
	/** Live tasks beyond the rows shown. */
	readonly more: number;
	/** Every live task's totals summed; unknown when none has a log. */
	readonly totals: TimelineTotals | undefined;
	/** Whether any live session carries a transition log yet. */
	readonly logged: boolean;
};

// When sessions of one task overlap, the board's rule decides what the task
// is doing: waiting on me beats running beats finished.
const PRIORITY: Readonly<Record<TimelineState, number>> = {
	waiting: 3,
	running: 2,
	finished: 1,
};

const ERROR_OUTCOMES: ReadonlySet<string> = new Set(["error", "tool-error"]);

type Interval = TimelineSegment & { readonly outcome: string };

function isTimelineState(state: string): state is TimelineState {
	return state === "running" || state === "waiting" || state === "finished";
}

/**
 * A session's spans. Without a log only the current state is known, from when
 * it was entered. A stale session's last state is unconfirmed after its last
 * event, so its span stops there.
 */
export function sessionIntervals(
	session: AgentSession,
	now: number,
): readonly Interval[] {
	const end =
		session.observation === "stale" ? Math.min(session.updatedAt, now) : now;
	const log: readonly WorkbranchRuntimeTransition[] =
		session.transitions !== undefined && session.transitions.length > 0
			? session.transitions
			: [
					{
						state: session.state,
						at: session.stateChangedAt,
						outcome: session.state === "finished" ? session.outcome : "",
					},
				];
	return log.flatMap((change, index): Interval[] => {
		const until = Math.min(log[index + 1]?.at ?? end, end);
		if (!isTimelineState(change.state) || until <= change.at) return [];
		return [
			{
				state: change.state,
				start: change.at,
				end: until,
				outcome: change.outcome ?? "",
			},
		];
	});
}

/** Overlapping spans become one strip, the higher-priority state winning. */
export function mergeIntervals(
	intervals: readonly TimelineSegment[],
	from: number,
	to: number,
): readonly TimelineSegment[] {
	const clipped = intervals
		.map((interval) => ({
			state: interval.state,
			start: Math.max(interval.start, from),
			end: Math.min(interval.end, to),
		}))
		.filter((interval) => interval.start < interval.end);
	const points = [
		...new Set(clipped.flatMap((interval) => [interval.start, interval.end])),
	].sort((a, b) => a - b);
	const segments: TimelineSegment[] = [];
	for (let i = 0; i + 1 < points.length; i += 1) {
		const start = points[i] as number;
		const end = points[i + 1] as number;
		let best: TimelineState | undefined;
		for (const interval of clipped)
			if (
				interval.start <= start &&
				interval.end >= end &&
				(best === undefined || PRIORITY[interval.state] > PRIORITY[best])
			)
				best = interval.state;
		if (best === undefined) continue;
		const last = segments.at(-1);
		if (last !== undefined && last.state === best && last.end === start)
			segments[segments.length - 1] = { ...last, end };
		else segments.push({ state: best, start, end });
	}
	return segments;
}

/**
 * A turn ends where the flow (running or waiting) gives way to finished. It
 * failed when a session's turn ended right there with an error.
 */
export function turnEnds(
	segments: readonly TimelineSegment[],
	intervals: readonly Interval[],
): readonly TimelineTurnEnd[] {
	return segments.flatMap((segment, index): TimelineTurnEnd[] => {
		const previous = segments[index - 1];
		if (
			segment.state !== "finished" ||
			previous === undefined ||
			previous.state === "finished" ||
			previous.end !== segment.start
		)
			return [];
		return [
			{
				at: segment.start,
				error: intervals.some(
					(interval) =>
						interval.state === "finished" &&
						interval.start === segment.start &&
						ERROR_OUTCOMES.has(interval.outcome),
				),
			},
		];
	});
}

function sumTotals(
	all: readonly (TimelineTotals | undefined)[],
): TimelineTotals | undefined {
	const known = all.filter((t): t is TimelineTotals => t !== undefined);
	if (known.length === 0) return undefined;
	return known.reduce((sum, t) => ({
		running: sum.running + t.running,
		waiting: sum.waiting + t.waiting,
		finished: sum.finished + t.finished,
	}));
}

// Repos of a task normally share its branch; the first repo's names it.
function rowTitle(row: MainTaskRow): string {
	return row.repos[0]?.branch || row.task.name;
}

export function buildTimelineRow(
	row: MainTaskRow,
	state: TimelineState,
	now: number,
	windowSeconds = TIMELINE_WINDOW_SECONDS,
): TimelineRow {
	const from = now - windowSeconds;
	const intervals = row.sessions.flatMap((s) => sessionIntervals(s, now));
	const segments = mergeIntervals(intervals, from, now);
	const lead = row.sessions[0];
	return {
		key: row.key,
		title: rowTitle(row),
		repo: row.repos[0]?.name,
		moreRepos: Math.max(0, row.repos.length - 1),
		agent: lead?.provider,
		state,
		since: lead?.stateChangedAt ?? row.latestActivityAt,
		segments,
		turnEnds: turnEnds(segments, intervals),
		totals: sumTotals(row.sessions.map((s) => s.totals)),
	};
}

/**
 * Rows in the board's order (waiting, running, finished; most recent first
 * within each), at most `maxRows`.
 */
export function buildTimeline(
	groups: readonly {
		readonly state: TimelineState;
		readonly rows: readonly MainTaskRow[];
	}[],
	now: number,
	maxRows: number,
	windowSeconds = TIMELINE_WINDOW_SECONDS,
): TimelineModel {
	const live = groups.flatMap((group) =>
		group.rows.map((row) => ({ row, state: group.state })),
	);
	const sessions = live.flatMap(({ row }) => row.sessions);
	return {
		start: now - windowSeconds,
		end: now,
		rows: live
			.slice(0, maxRows)
			.map(({ row, state }) =>
				buildTimelineRow(row, state, now, windowSeconds),
			),
		more: Math.max(0, live.length - maxRows),
		totals: sumTotals(sessions.map((s) => s.totals)),
		logged: sessions.some(
			(s) => s.transitions !== undefined && s.transitions.length > 0,
		),
	};
}
