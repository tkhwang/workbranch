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
/** Recent messages listed under a row. */
export const TIMELINE_MESSAGES = 3;

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

/** A request or reply from one of the task's sessions, or a commit. */
export type TimelineMessage = {
	readonly kind: "prompt" | "response" | "commit";
	readonly text: string;
	/** Epoch seconds. */
	readonly at: number;
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
	/** The task's newest messages across its sessions and repos, newest first. */
	readonly messages: readonly TimelineMessage[];
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

// The collector logs a turn's end as `turn-ended`, `interrupted` or `error`
// (StopFailure). A tool that failed mid-turn is not a failed turn: the agent
// reads the failure and carries on, so only `error` crosses the end marker.
const ERROR_OUTCOME = "error";

type Interval = TimelineSegment & { readonly outcome: string };

function isTimelineState(state: string): state is TimelineState {
	return state === "running" || state === "waiting" || state === "finished";
}

/**
 * A session's spans. Without a log only the current state is known, from when
 * it was entered. Like the board, which counts only observed sessions, the
 * timeline draws no unconfirmed present: a stale session's last state stops
 * at its last event, and an uncertain session's current state is not drawn at
 * all, so it can never outrank what an observed session of the task is doing.
 */
export function sessionIntervals(
	session: AgentSession,
	now: number,
): readonly Interval[] {
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
	// Where the session's record stops being confirmed.
	const end =
		session.observation === "stale"
			? Math.min(session.updatedAt, now)
			: session.observation === "uncertain"
				? Math.min(log.at(-1)?.at ?? now, now)
				: now;
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
						interval.outcome === ERROR_OUTCOME,
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

/** When the session's current turn began: its last start from rest. */
function turnStart(session: AgentSession): number {
	const log = session.transitions ?? [];
	for (let i = log.length - 1; i >= 0; i -= 1) {
		const change = log[i];
		const before = log[i - 1]?.state;
		if (
			change?.state === "running" &&
			(before === undefined || before === "finished" || before === "idle")
		)
			return change.at;
	}
	return session.state === "running"
		? session.stateChangedAt
		: session.updatedAt;
}

/**
 * A session from before the collector kept messages, or one that has sent
 * nothing since, still holds its latest request and reply: those stand in.
 * The reply is dated when the turn ended; the request when the turn began,
 * and never after its reply.
 */
export function sessionMessages(
	session: AgentSession,
): readonly TimelineMessage[] {
	if (session.messages !== undefined && session.messages.length > 0)
		return session.messages;
	const replied = session.state === "finished" && session.response !== "";
	const repliedAt = session.stateChangedAt;
	const askedAt = Math.min(
		turnStart(session),
		replied ? repliedAt - 1 : Number.POSITIVE_INFINITY,
	);
	return [
		...(session.prompt === ""
			? []
			: [{ kind: "prompt" as const, text: session.prompt, at: askedAt }]),
		...(replied
			? [{ kind: "response" as const, text: session.response, at: repliedAt }]
			: []),
	];
}

/**
 * The task's last few requests, replies and commits, newest first. Every
 * session and repo of the task contributes; a commit made in several repos
 * under the same subject at the same time is listed once.
 */
export function recentMessages(
	row: MainTaskRow,
	limit = TIMELINE_MESSAGES,
): readonly TimelineMessage[] {
	const all: TimelineMessage[] = [
		...row.sessions.flatMap(sessionMessages),
		...row.repos.flatMap((repo) =>
			repo.recentCommits.map(
				(commit): TimelineMessage => ({
					kind: "commit",
					text: commit.subject,
					at: commit.at,
				}),
			),
		),
	];
	const seen = new Set<string>();
	return all
		.filter((message) => message.text !== "")
		.sort((a, b) => b.at - a.at)
		.filter((message) => {
			const key = `${message.kind}\u0000${message.at}\u0000${message.text}`;
			if (seen.has(key)) return false;
			seen.add(key);
			return true;
		})
		.slice(0, limit);
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
		messages: recentMessages(row),
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
