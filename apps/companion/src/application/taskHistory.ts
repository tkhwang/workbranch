// A task's history on the lock screen: the spans its sessions spent running,
// waiting or finished, where turns ended, and its recent requests, replies and
// commits. The dashboard's views draw from these rules, so every view and the
// board agree on what a task was doing and what text may reach the screen.
import type { WorkbranchRuntimeTransition } from "@workbranch/contract";
import type { AgentSession } from "../domain/model";
import type { MainTaskRow } from "./state";

/** Recent messages kept for a task. */
export const TASK_MESSAGES = 3;

export type HistoryState = "running" | "waiting" | "finished";

/** A span in epoch seconds, already clipped to the window. */
export type HistorySegment = {
	readonly state: HistoryState;
	readonly start: number;
	readonly end: number;
};

/** Where a turn ended: the flow stops and review waiting begins. */
export type TurnEnd = {
	readonly at: number;
	readonly error: boolean;
};

/** A request or reply from one of the task's sessions, or a commit. */
export type TaskMessage = {
	readonly kind: "prompt" | "response" | "commit";
	readonly text: string;
	/** Epoch seconds. */
	readonly at: number;
};

// When sessions of one task overlap, the board's rule decides what the task
// is doing: waiting on me beats running beats finished.
const PRIORITY: Readonly<Record<HistoryState, number>> = {
	waiting: 3,
	running: 2,
	finished: 1,
};

// The collector logs a turn's end as `turn-ended`, `interrupted` or `error`
// (StopFailure). A tool that failed mid-turn is not a failed turn: the agent
// reads the failure and carries on, so only `error` crosses the end marker.
const ERROR_OUTCOME = "error";

/** A session's span with how its turn ended, before tasks are merged. */
export type HistoryInterval = HistorySegment & { readonly outcome: string };

function isHistoryState(state: string): state is HistoryState {
	return state === "running" || state === "waiting" || state === "finished";
}

/**
 * A session's spans. Without a log only the current state is known, from when
 * it was entered. Like the board, which counts only observed sessions, no
 * view draws an unconfirmed present: a stale session's last state stops
 * at its last event, and an uncertain session's current state is not drawn at
 * all, so it can never outrank what an observed session of the task is doing.
 */
export function sessionIntervals(
	session: AgentSession,
	now: number,
): readonly HistoryInterval[] {
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
	return log.flatMap((change, index): HistoryInterval[] => {
		const until = Math.min(log[index + 1]?.at ?? end, end);
		if (!isHistoryState(change.state) || until <= change.at) return [];
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
	intervals: readonly HistorySegment[],
	from: number,
	to: number,
): readonly HistorySegment[] {
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
	const segments: HistorySegment[] = [];
	for (let i = 0; i + 1 < points.length; i += 1) {
		const start = points[i] as number;
		const end = points[i + 1] as number;
		let best: HistoryState | undefined;
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
	segments: readonly HistorySegment[],
	intervals: readonly HistoryInterval[],
): readonly TurnEnd[] {
	return segments.flatMap((segment, index): TurnEnd[] => {
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

/** A dashboard line needs only the start of a message (the collector's cap). */
export const MESSAGE_CHARS = 300;
const SENSITIVE = "[sensitive content omitted]";
// The collector's markers (agent-runtime `clipped`): any of them, or URI
// userinfo, withholds the whole text, since piecewise redaction can leak.
const SENSITIVE_MARKERS: readonly string[] = [
	"authorization",
	"bearer ",
	"password",
	"--token",
	"token=",
	"api_key",
	"api-key",
	"secret",
	"token",
	"sk-",
	"ghp_",
];

function hasUriCredentials(text: string): boolean {
	return text
		.split("://")
		.slice(1)
		.some((tail) => (tail.split(/[/?#\s]/)[0] ?? "").includes("@"));
}

/**
 * Text bound for the lock screen, cleaned by the collector's rule: whitespace
 * folded, credential-looking text withheld whole, at most `limit` characters.
 * Commit subjects come from the CLI unscrubbed, so they pass through here.
 */
export function scrubMessage(text: string, limit = MESSAGE_CHARS): string {
	const clean = text.split(/\s+/).filter(Boolean).join(" ");
	const lower = clean.toLowerCase();
	if (
		hasUriCredentials(clean) ||
		SENSITIVE_MARKERS.some((marker) => lower.includes(marker))
	)
		return SENSITIVE;
	const chars = Array.from(clean);
	return chars.length > limit ? `${chars.slice(0, limit).join("")}…` : clean;
}

// The collector clips a kept message shorter than the latest prompt and
// response it also keeps; a clipped message still stands for the full text.
function sameText(full: string, kept: string): boolean {
	return (
		full === kept || (kept.endsWith("…") && full.startsWith(kept.slice(0, -1)))
	);
}

/**
 * A session's requests and replies, oldest first. The collector's kept
 * messages lead; the latest request and reply, which every collector stores,
 * fill in what they lack: all of it for a session from before messages were
 * kept, and the request of a turn that was under way when the collector was
 * upgraded. The reply is dated when the turn ended; the request when the turn
 * began, and never after its reply.
 */
export function sessionMessages(session: AgentSession): readonly TaskMessage[] {
	const kept = session.messages ?? [];
	const replied = session.state === "finished" && session.response !== "";
	const repliedAt = session.stateChangedAt;
	const askedAt = Math.min(
		turnStart(session),
		replied ? repliedAt - 1 : Number.POSITIVE_INFINITY,
	);
	const latest: TaskMessage[] = [
		...(session.prompt === ""
			? []
			: [{ kind: "prompt" as const, text: session.prompt, at: askedAt }]),
		...(replied
			? [{ kind: "response" as const, text: session.response, at: repliedAt }]
			: []),
	];
	const missing = latest.filter(
		(fallback) =>
			!kept.some(
				(message) =>
					message.kind === fallback.kind &&
					sameText(fallback.text, message.text),
			),
	);
	// Stable: on a tie a stand-in, the older record, stays first.
	return [...missing, ...kept].sort((a, b) => a.at - b.at);
}

/**
 * The task's last few requests, replies and commits, newest first. Every
 * session and repo of the task contributes; a commit made in several repos
 * under the same subject at the same time is listed once. Times are whole
 * seconds, so a tie keeps each source's own order: a reply recorded in the
 * same second as its request still comes first.
 */
export function recentMessages(
	row: MainTaskRow,
	limit = TASK_MESSAGES,
): readonly TaskMessage[] {
	const entries = [
		// Sessions keep messages oldest first: later ones rank higher.
		...row.sessions.flatMap((session) =>
			sessionMessages(session).map((message, order) => ({ message, order })),
		),
		// The CLI lists commits newest first.
		...row.repos.flatMap((repo) =>
			repo.recentCommits.map((commit, index, all) => ({
				message: {
					kind: "commit" as const,
					text: scrubMessage(commit.subject),
					at: commit.at,
				},
				order: all.length - 1 - index,
			})),
		),
	];
	const seen = new Set<string>();
	return entries
		.filter(({ message }) => message.text !== "")
		.sort((a, b) => b.message.at - a.message.at || b.order - a.order)
		.map(({ message }) => message)
		.filter((message) => {
			const key = `${message.kind}\u0000${message.at}\u0000${message.text}`;
			if (seen.has(key)) return false;
			seen.add(key);
			return true;
		})
		.slice(0, limit);
}
