import { describe, expect, it } from "vitest";
import type { MainTaskRow } from "../src/application/state";
import {
	buildTimeline,
	buildTimelineRow,
	mergeIntervals,
	sessionIntervals,
	turnEnds,
} from "../src/application/timeline";
import type { AgentSession } from "../src/domain/model";

const NOW = 10_000;

function session(fields: Partial<AgentSession> = {}): AgentSession {
	return {
		workspace: "/work/t",
		provider: "claude",
		sessionId: "s",
		agentId: "",
		turnId: "t",
		state: "running",
		observation: "observed",
		reason: "",
		prompt: "",
		activity: "",
		response: "",
		outcome: "",
		updatedAt: NOW,
		stateChangedAt: 1_000,
		...fields,
	};
}

function row(sessions: readonly AgentSession[], name = "t"): MainTaskRow {
	return {
		key: `/work:${name}`,
		root: "/work",
		project: "workbranch",
		task: {
			name,
			path: `/work/${name}`,
			notiCount: 0,
			repos: [],
			updatedAt: 1,
		},
		repos: [],
		role: sessions[0]?.state ?? "unknown",
		sessions,
		latestActivityAt: 1,
	} as MainTaskRow;
}

describe("sessionIntervals", () => {
	it("draws each logged change until the next one, the last until now", () => {
		const s = session({
			state: "finished",
			transitions: [
				{ state: "running", at: 1_000 },
				{ state: "waiting", at: 2_000 },
				{ state: "running", at: 2_600 },
				{ state: "finished", at: 4_000, outcome: "turn-ended" },
			],
		});
		expect(sessionIntervals(s, NOW)).toEqual([
			{ state: "running", start: 1_000, end: 2_000, outcome: "" },
			{ state: "waiting", start: 2_000, end: 2_600, outcome: "" },
			{ state: "running", start: 2_600, end: 4_000, outcome: "" },
			{ state: "finished", start: 4_000, end: NOW, outcome: "turn-ended" },
		]);
	});

	it("without a log, draws the current state from when it was entered", () => {
		expect(
			sessionIntervals(
				session({ state: "finished", stateChangedAt: 5_000, outcome: "error" }),
				NOW,
			),
		).toEqual([
			{ state: "finished", start: 5_000, end: NOW, outcome: "error" },
		]);
	});

	it("stops a stale session at its last event and skips idle spans", () => {
		const s = session({
			observation: "stale",
			updatedAt: 3_000,
			transitions: [
				{ state: "idle", at: 500 },
				{ state: "running", at: 1_000 },
			],
		});
		expect(sessionIntervals(s, NOW)).toEqual([
			{ state: "running", start: 1_000, end: 3_000, outcome: "" },
		]);
	});
});

describe("mergeIntervals", () => {
	it("lets waiting beat running beat finished where sessions overlap", () => {
		const merged = mergeIntervals(
			[
				{ state: "finished", start: 0, end: 100 },
				{ state: "running", start: 20, end: 80 },
				{ state: "waiting", start: 40, end: 50 },
			],
			0,
			100,
		);
		expect(merged).toEqual([
			{ state: "finished", start: 0, end: 20 },
			{ state: "running", start: 20, end: 40 },
			{ state: "waiting", start: 40, end: 50 },
			{ state: "running", start: 50, end: 80 },
			{ state: "finished", start: 80, end: 100 },
		]);
	});

	it("clips to the window, joins touching spans and leaves gaps empty", () => {
		const merged = mergeIntervals(
			[
				{ state: "running", start: -50, end: 10 },
				{ state: "running", start: 10, end: 30 },
				{ state: "running", start: 60, end: 200 },
			],
			0,
			100,
		);
		expect(merged).toEqual([
			{ state: "running", start: 0, end: 30 },
			{ state: "running", start: 60, end: 100 },
		]);
	});
});

describe("turnEnds", () => {
	const flowThenDone = [
		{ state: "running", start: 0, end: 40 },
		{ state: "finished", start: 40, end: 100 },
	] as const;

	it("marks where the flow gives way to finished", () => {
		expect(
			turnEnds(flowThenDone, [
				{ state: "finished", start: 40, end: 100, outcome: "turn-ended" },
			]),
		).toEqual([{ at: 40, error: false }]);
	});

	it("marks a failed turn as an error, an interrupted one as a plain end", () => {
		expect(
			turnEnds(flowThenDone, [
				{ state: "finished", start: 40, end: 100, outcome: "error" },
			]),
		).toEqual([{ at: 40, error: true }]);
		expect(
			turnEnds(flowThenDone, [
				{ state: "finished", start: 40, end: 100, outcome: "interrupted" },
			]),
		).toEqual([{ at: 40, error: false }]);
	});

	it("does not mark finished that follows a gap or opens the window", () => {
		expect(
			turnEnds(
				[
					{ state: "finished", start: 0, end: 20 },
					{ state: "running", start: 30, end: 50 },
					{ state: "finished", start: 60, end: 100 },
				],
				[],
			),
		).toEqual([]);
	});
});

describe("buildTimelineRow", () => {
	it("sums known totals across a task's sessions", () => {
		const timelineRow = buildTimelineRow(
			row([
				session({ totals: { running: 60, waiting: 30, finished: 0 } }),
				session({
					sessionId: "sub",
					agentId: "a",
					totals: { running: 120, waiting: 0, finished: 5 },
				}),
				session({ sessionId: "old" }),
			]),
			"running",
			NOW,
		);
		expect(timelineRow.totals).toEqual({
			running: 180,
			waiting: 30,
			finished: 5,
		});
	});

	it("leaves totals unknown when no session has a log", () => {
		expect(buildTimelineRow(row([session()]), "running", NOW).totals).toBe(
			undefined,
		);
	});

	it("keeps only the window and reports the lead's time in state", () => {
		const timelineRow = buildTimelineRow(
			row([
				session({
					stateChangedAt: 9_000,
					transitions: [
						{ state: "running", at: 100 },
						{ state: "waiting", at: 9_000 },
					],
				}),
			]),
			"waiting",
			NOW,
			3_600,
		);
		expect(timelineRow.segments).toEqual([
			{ state: "running", start: 6_400, end: 9_000 },
			{ state: "waiting", start: 9_000, end: NOW },
		]);
		expect(timelineRow.since).toBe(9_000);
	});
});

describe("buildTimeline", () => {
	it("totals every live task, shown or not, and says whether anything is logged", () => {
		const logged = session({
			transitions: [{ state: "running", at: 9_000 }],
			totals: { running: 1_000, waiting: 0, finished: 0 },
		});
		const model = buildTimeline(
			[
				{ state: "waiting", rows: [] },
				{
					state: "running",
					rows: [row([logged], "a"), row([logged], "b")],
				},
				{ state: "finished", rows: [] },
			],
			NOW,
			1,
		);
		expect(model.rows).toHaveLength(1);
		expect(model.more).toBe(1);
		expect(model.totals).toEqual({ running: 2_000, waiting: 0, finished: 0 });
		expect(model.logged).toBe(true);
		expect(model.end - model.start).toBe(3 * 60 * 60);
	});

	it("is not logged while sessions come from an older collector", () => {
		const model = buildTimeline(
			[{ state: "running", rows: [row([session()])] }],
			NOW,
			8,
		);
		expect(model.logged).toBe(false);
		expect(model.totals).toBe(undefined);
	});
});

describe("unconfirmed sessions", () => {
	it("does not draw an uncertain session's current state", () => {
		const uncertain = session({
			observation: "uncertain",
			state: "waiting",
			transitions: [
				{ state: "running", at: 1_000 },
				{ state: "waiting", at: 8_000 },
			],
		});
		expect(sessionIntervals(uncertain, NOW)).toEqual([
			{ state: "running", start: 1_000, end: 8_000, outcome: "" },
		]);
		expect(
			sessionIntervals(session({ observation: "uncertain" }), NOW),
		).toEqual([]);
	});

	it("lets an observed running session decide the task, as the board does", () => {
		const timelineRow = buildTimelineRow(
			row([
				session({ transitions: [{ state: "running", at: 9_000 }] }),
				session({
					sessionId: "other",
					observation: "uncertain",
					state: "waiting",
					transitions: [{ state: "waiting", at: 9_500 }],
				}),
			]),
			"running",
			NOW,
		);
		expect(timelineRow.segments).toEqual([
			{ state: "running", start: 9_000, end: NOW },
		]);
	});
});

describe("turn outcomes", () => {
	it("crosses out only a failed turn, not a tool that failed along the way", () => {
		const segments = [
			{ state: "running", start: 0, end: 40 },
			{ state: "finished", start: 40, end: 100 },
		] as const;
		expect(
			turnEnds(segments, [
				{ state: "finished", start: 40, end: 100, outcome: "tool-error" },
			]),
		).toEqual([{ at: 40, error: false }]);
	});
});
