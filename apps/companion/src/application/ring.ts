// A task on the lock screen as a clock face: the last three hours make one
// turn with now at the top, and the task's states run around it clockwise
// from old to new. Angles are SVG degrees (clockwise from three o'clock), so
// the view only maps them to points.
import type { AgentSession } from "../domain/model";
import type { MainTaskRow } from "./state";
import {
	type HistoryState,
	mergeIntervals,
	recentMessages,
	scrubMessage,
	sessionIntervals,
	type TaskMessage,
	turnEnds,
} from "./taskHistory";

/** One turn of the ring. */
export const RING_WINDOW_SECONDS = 3 * 60 * 60;
/** The gap at the top that separates now from three hours ago. */
export const RING_GAP_DEGREES = 8;

const TOP = -90;
const SWEEP = 360 - RING_GAP_DEGREES;

/** Calls this recent are linked to their tool and files, and counted. */
export const RECENT_CALL_SECONDS = 30 * 60;
/**
 * A call this new travels from now to its tool once. The dashboard redraws
 * every second, so each new call is drawn fresh for a few frames, then rests.
 */
export const FRESH_CALL_SECONDS = 3;
/** Files shown around a ring, at most. */
export const RING_FILES = 6;
/** Files closer than this on the ring would overlap; later ones step back. */
const FILE_SPACING_DEGREES = 16;

/**
 * Tools as the ring groups them (COMP004 R8): the providers name the same kind
 * of work differently, and one node per raw name would crowd the ring.
 */
export const TOOL_GROUPS = [
	"Bash",
	"Read",
	"Edit",
	"Write",
	"Search",
	"Web",
	"Agent",
	"Todo",
	"Ask",
	"MCP",
	"Other",
] as const;
export type ToolGroup = (typeof TOOL_GROUPS)[number];

const GROUP_OF: Readonly<Record<string, ToolGroup>> = {
	Bash: "Bash",
	shell: "Bash",
	exec_command: "Bash",
	local_shell: "Bash",
	run_terminal_command: "Bash",
	Read: "Read",
	NotebookRead: "Read",
	Edit: "Edit",
	MultiEdit: "Edit",
	NotebookEdit: "Edit",
	apply_patch: "Edit",
	Write: "Write",
	Grep: "Search",
	Glob: "Search",
	LS: "Search",
	WebSearch: "Web",
	WebFetch: "Web",
	Agent: "Agent",
	Task: "Agent",
	TodoWrite: "Todo",
	TaskCreate: "Todo",
	TaskUpdate: "Todo",
	TaskList: "Todo",
	TaskGet: "Todo",
	update_plan: "Todo",
	AskUserQuestion: "Ask",
	ExitPlanMode: "Ask",
	request_user_input: "Ask",
};

/** The ring's group for a provider's tool name; unknown names are Other. */
export function toolGroup(tool: string): ToolGroup {
	if (tool.startsWith("mcp__")) return "MCP";
	// Own keys only: a name like "constructor" is a tool we do not know.
	return Object.hasOwn(GROUP_OF, tool) ? (GROUP_OF[tool] ?? "Other") : "Other";
}

/** Where each group's node sits inside the ring, spread evenly from the top. */
export function hubAngle(group: ToolGroup): number {
	return TOP + (360 / TOOL_GROUPS.length) * TOOL_GROUPS.indexOf(group);
}

/** Why a task waits on the user, as the collector names it; "" when not waiting. */
export type WaitReason = AgentSession["reason"];

/** A span of the task's history between two angles, `from` < `to`. */
export type RingArc = {
	readonly state: HistoryState;
	readonly from: number;
	readonly to: number;
};

export type RingTurnEnd = {
	readonly angle: number;
	readonly error: boolean;
};

/** Where a turn began: the user's request, or a subagent's report. */
export type RingTurnStart = {
	readonly angle: number;
	readonly kind: "prompt" | "agent";
};

/** A tool call, placed by when it started. */
export type RingCall = {
	readonly angle: number;
	readonly group: ToolGroup;
	readonly failed: boolean;
	/** Within `RECENT_CALL_SECONDS`: linked to its tool and files. */
	readonly recent: boolean;
	/** Within `FRESH_CALL_SECONDS`: shown arriving at its tool. */
	readonly fresh: boolean;
	/** Epoch seconds the call started, which tells calls apart. */
	readonly at: number;
	/** File names the call touched. */
	readonly files: readonly string[];
};

/** A tool group's node: how many calls in the window used it. */
export type RingHub = {
	readonly group: ToolGroup;
	readonly count: number;
	readonly angle: number;
};

/** How far the task's todo list has come. */
export type RingProgress = {
	readonly total: number;
	readonly done: number;
	/** The todo in progress; only with work details on. */
	readonly active: string | undefined;
};

/** What the task's last ended turn left (runtime `lastTurn`). */
export type RingSummary = {
	readonly filesChanged: number;
	readonly linesAdded: number;
	readonly linesRemoved: number;
	readonly tests: "passed" | "failed" | "unknown" | "none";
	readonly commits: number;
};

/** A recently touched file, placed near its last touch. */
export type RingFile = {
	readonly name: string;
	readonly angle: number;
};

export type RingModel = {
	readonly key: string;
	/** The worktree branch (the first repo's), else the task name. */
	readonly title: string;
	readonly repo: string | undefined;
	readonly moreRepos: number;
	/** Every agent working on the task, each once, the lead session's first. */
	readonly agents: readonly AgentSession["provider"][];
	readonly state: HistoryState;
	/** Epoch seconds the lead session entered its state. */
	readonly since: number;
	readonly waitReason: WaitReason;
	readonly arcs: readonly RingArc[];
	readonly turnEnds: readonly RingTurnEnd[];
	readonly turnStarts: readonly RingTurnStart[];
	readonly calls: readonly RingCall[];
	readonly hubs: readonly RingHub[];
	readonly files: readonly RingFile[];
	/** Calls started within `RECENT_CALL_SECONDS`. */
	readonly recentCalls: number;
	/**
	 * What the lead session is doing now (its tool and target), and the task's
	 * newest request, reply or commit. Both only with work details on; file
	 * names likewise, so no work text reaches the lock screen unless asked.
	 */
	readonly activity: string | undefined;
	readonly message: TaskMessage | undefined;
	/** The todo list of the task's most recently updated session that has one. */
	readonly progress: RingProgress | undefined;
	/** The summary of the turn that ended last among the task's sessions. */
	readonly summary: RingSummary | undefined;
	/**
	 * Whether the task's turn ended in an error: the lead session's own
	 * outcome, which every collector records, else the log's last turn end.
	 */
	readonly failed: boolean;
	readonly nowAngle: number;
	/** Whether any session carries a transition log, or only its current state. */
	readonly logged: boolean;
};

/** Where `at` (epoch seconds) falls on the ring; outside the window clamps to its ends. */
export function ringAngle(
	at: number,
	now: number,
	windowSeconds = RING_WINDOW_SECONDS,
): number {
	const age = Math.min(Math.max(now - at, 0), windowSeconds);
	return TOP + RING_GAP_DEGREES / 2 + SWEEP * (1 - age / windowSeconds);
}

// Repos of a task normally share its branch; the first repo's names it.
function title(row: MainTaskRow): string {
	return row.repos[0]?.branch || row.task.name;
}

// The session that explains the task's state: an observed one in that state,
// else the board's first.
function leadSession(
	row: MainTaskRow,
	state: HistoryState,
): AgentSession | undefined {
	return (
		row.sessions.find(
			(s) => s.state === state && s.observation === "observed",
		) ?? row.sessions[0]
	);
}

type TimedCall = {
	readonly tool: string;
	readonly files: readonly string[];
	readonly failed: boolean;
	readonly at: number;
};

function taskCalls(row: MainTaskRow, from: number): readonly TimedCall[] {
	return row.sessions
		.flatMap((session) => session.calls ?? [])
		.filter((call) => call.at >= from)
		.map((call) => ({
			tool: call.tool,
			files: call.files ?? [],
			failed: call.failed === true,
			at: call.at,
		}))
		.sort((a, b) => a.at - b.at);
}

// The newest distinct files of the recent calls, newest first, each placed
// at its last touch and stepped back where it would overlap a newer one.
function recentFiles(
	calls: readonly TimedCall[],
	angle: (at: number) => number,
): readonly RingFile[] {
	const lastTouch = new Map<string, number>();
	for (const call of calls)
		for (const name of call.files) lastTouch.set(name, call.at);
	const newest = [...lastTouch.entries()]
		.sort((a, b) => b[1] - a[1])
		.slice(0, RING_FILES);
	let previous = Number.POSITIVE_INFINITY;
	return newest.map(([name, at]) => {
		const placed = Math.min(angle(at), previous - FILE_SPACING_DEGREES);
		previous = placed;
		return { name, angle: placed };
	});
}

// The summary of the turn that ended last: sessions carry one only while
// finished, and a finished session's state changed when its turn ended.
function summaryOf(row: MainTaskRow): RingSummary | undefined {
	const latest = row.sessions
		.filter((s) => s.lastTurn !== undefined)
		.sort((a, b) => b.stateChangedAt - a.stateChangedAt)[0]?.lastTurn;
	if (latest === undefined) return undefined;
	return {
		filesChanged: latest.filesChanged,
		linesAdded: latest.linesAdded,
		linesRemoved: latest.linesRemoved,
		tests: latest.tests,
		commits: latest.commits,
	};
}

function progressOf(
	row: MainTaskRow,
	details: boolean,
): RingProgress | undefined {
	const latest = row.sessions
		.filter((s) => s.todos !== undefined && s.todos.total > 0)
		.sort((a, b) => b.updatedAt - a.updatedAt)[0]?.todos;
	if (latest === undefined) return undefined;
	return {
		total: latest.total,
		done: Math.min(latest.done, latest.total),
		active:
			details && latest.active !== undefined && latest.active !== ""
				? scrubMessage(latest.active)
				: undefined,
	};
}

export function buildRing(
	row: MainTaskRow,
	state: HistoryState,
	now: number,
	details = false,
	windowSeconds = RING_WINDOW_SECONDS,
): RingModel {
	const angle = (at: number) => ringAngle(at, now, windowSeconds);
	const intervals = row.sessions.flatMap((s) => sessionIntervals(s, now));
	const segments = mergeIntervals(intervals, now - windowSeconds, now);
	const lead = leadSession(row, state);
	const turnEndsOf = turnEnds(segments, intervals);
	const calls = taskCalls(row, now - windowSeconds).map((call) =>
		details ? call : { ...call, files: [] },
	);
	const recentFrom = now - RECENT_CALL_SECONDS;
	const recent = calls.filter((call) => call.at >= recentFrom);
	const counts = new Map<ToolGroup, number>();
	for (const call of calls) {
		const group = toolGroup(call.tool);
		counts.set(group, (counts.get(group) ?? 0) + 1);
	}
	return {
		key: row.key,
		title: title(row),
		repo: row.repos[0]?.name,
		moreRepos: Math.max(0, row.repos.length - 1),
		agents: [
			...new Set(
				[lead, ...row.sessions].flatMap((s) =>
					s === undefined ? [] : [s.provider],
				),
			),
		],
		state,
		since: lead?.stateChangedAt ?? row.latestActivityAt,
		waitReason: state === "waiting" ? (lead?.reason ?? "") : "",
		arcs: segments.map((segment) => ({
			state: segment.state,
			from: angle(segment.start),
			to: angle(segment.end),
		})),
		turnEnds: turnEndsOf.map((end) => ({
			angle: angle(end.at),
			error: end.error,
		})),
		turnStarts: row.sessions
			.flatMap((s) => s.turns ?? [])
			.filter((turn) => turn.at >= now - windowSeconds)
			.sort((a, b) => a.at - b.at)
			.map((turn) => ({ angle: angle(turn.at), kind: turn.kind })),
		calls: calls.map((call) => ({
			angle: angle(call.at),
			group: toolGroup(call.tool),
			failed: call.failed,
			recent: call.at >= recentFrom,
			fresh: call.at >= now - FRESH_CALL_SECONDS,
			at: call.at,
			files: call.files,
		})),
		hubs: TOOL_GROUPS.filter((group) => counts.has(group)).map((group) => ({
			group,
			count: counts.get(group) ?? 0,
			angle: hubAngle(group),
		})),
		files: recentFiles(recent, angle),
		recentCalls: recent.length,
		activity:
			details && lead !== undefined && lead.activity !== ""
				? scrubMessage(lead.activity)
				: undefined,
		message: details ? recentMessages(row, 1)[0] : undefined,
		progress: progressOf(row, details),
		summary: summaryOf(row),
		// The lead's own outcome decides; the log's last turn end only when the
		// lead has none, so another session's old error cannot override it.
		failed:
			state === "finished" &&
			(lead !== undefined && lead.outcome !== ""
				? lead.outcome === "error"
				: turnEndsOf.at(-1)?.error === true),
		nowAngle: angle(now),
		logged: row.sessions.some(
			(s) => s.transitions !== undefined && s.transitions.length > 0,
		),
	};
}
