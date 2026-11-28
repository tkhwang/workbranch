import { describe, expect, it } from "vitest";
import {
	buildRing,
	hubAngle,
	RING_FILES,
	RING_GAP_DEGREES,
	RING_WINDOW_SECONDS,
	ringAngle,
	toolGroup,
} from "../src/application/ring";
import type { MainTaskRow } from "../src/application/state";
import type { AgentSession, Repo } from "../src/domain/model";

const NOW = 100_000;
const HOUR = 3_600;
// Now sits at the top (-90°) behind half the gap; the window's start just
// past it on the other side, so the ring reads clockwise from old to new.
const NOW_ANGLE = -90 + RING_GAP_DEGREES / 2 + (360 - RING_GAP_DEGREES);
const START_ANGLE = -90 + RING_GAP_DEGREES / 2;
const DEGREES_PER_HOUR = (360 - RING_GAP_DEGREES) / 3;

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
		stateChangedAt: NOW - HOUR,
		...fields,
	};
}

function repo(name: string, branch: string): Repo {
	return {
		name,
		branch,
		dirty: false,
		activityAvailable: true,
		ahead: 0,
		behind: 0,
		changedFiles: 0,
		lastCommitSubject: "",
		lastCommitAt: 0,
		recentCommits: [],
	};
}

function row(
	sessions: readonly AgentSession[],
	fields: Partial<MainTaskRow> = {},
): MainTaskRow {
	return {
		key: "/work:t",
		root: "/work",
		project: "workbranch",
		task: { name: "t", path: "/work/t", notiCount: 0, repos: [], updatedAt: 1 },
		repos: [],
		role: "running",
		sessions,
		latestActivityAt: 42,
		...fields,
	} as MainTaskRow;
}

describe("ringAngle", () => {
	it("puts now at the top and the window's start just past it", () => {
		expect(RING_WINDOW_SECONDS).toBe(3 * HOUR);
		expect(ringAngle(NOW, NOW)).toBeCloseTo(NOW_ANGLE);
		expect(ringAngle(NOW - 3 * HOUR, NOW)).toBeCloseTo(START_ANGLE);
		expect(ringAngle(NOW - 1.5 * HOUR, NOW)).toBeCloseTo(90);
	});

	it("clamps what is older than the window or in the future", () => {
		expect(ringAngle(NOW - 10 * HOUR, NOW)).toBeCloseTo(START_ANGLE);
		expect(ringAngle(NOW + 60, NOW)).toBeCloseTo(NOW_ANGLE);
	});
});

describe("buildRing", () => {
	it("draws the task's states as arcs, oldest first, and marks turn ends", () => {
		const ring = buildRing(
			row([
				session({
					state: "finished",
					stateChangedAt: NOW - HOUR / 6,
					transitions: [
						{ state: "running", at: NOW - HOUR },
						{ state: "waiting", at: NOW - HOUR / 2 },
						{ state: "running", at: NOW - HOUR / 3 },
						{ state: "finished", at: NOW - HOUR / 6, outcome: "error" },
					],
				}),
			]),
			"finished",
			NOW,
		);
		const at = (secondsAgo: number) =>
			NOW_ANGLE - (secondsAgo / HOUR) * DEGREES_PER_HOUR;
		expect(ring.arcs.map((arc) => arc.state)).toEqual([
			"running",
			"waiting",
			"running",
			"finished",
		]);
		expect(ring.arcs[0]?.from).toBeCloseTo(at(HOUR));
		expect(ring.arcs[1]?.from).toBeCloseTo(at(HOUR / 2));
		expect(ring.arcs[3]?.to).toBeCloseTo(NOW_ANGLE);
		expect(ring.turnEnds).toHaveLength(1);
		expect(ring.turnEnds[0]?.angle).toBeCloseTo(at(HOUR / 6));
		expect(ring.turnEnds[0]?.error).toBe(true);
		expect(ring.nowAngle).toBeCloseTo(NOW_ANGLE);
		expect(ring.logged).toBe(true);
	});

	it("keeps only the window: a span that began before it starts at its edge", () => {
		const ring = buildRing(
			row([
				session({ transitions: [{ state: "running", at: NOW - 5 * HOUR }] }),
			]),
			"running",
			NOW,
		);
		expect(ring.arcs).toHaveLength(1);
		expect(ring.arcs[0]?.from).toBeCloseTo(START_ANGLE);
		expect(ring.arcs[0]?.to).toBeCloseTo(NOW_ANGLE);
	});

	it("draws no unconfirmed present: stale stops at its last event, uncertain is left out", () => {
		const stale = buildRing(
			row([
				session({
					observation: "stale",
					updatedAt: NOW - HOUR / 2,
					transitions: [{ state: "running", at: NOW - HOUR }],
				}),
			]),
			"running",
			NOW,
		);
		expect(stale.arcs[0]?.to).toBeCloseTo(NOW_ANGLE - 0.5 * DEGREES_PER_HOUR);
		const uncertain = buildRing(
			row([session({ observation: "uncertain", state: "waiting" })]),
			"waiting",
			NOW,
		);
		expect(uncertain.arcs).toEqual([]);
	});

	it("without a log, draws the current state from when it was entered", () => {
		const ring = buildRing(row([session()]), "running", NOW);
		expect(ring.logged).toBe(false);
		expect(ring.arcs).toEqual([expect.objectContaining({ state: "running" })]);
		expect(ring.arcs[0]?.from).toBeCloseTo(NOW_ANGLE - DEGREES_PER_HOUR);
	});

	it("names the task by its branch and leads with the session in the task's state", () => {
		const ring = buildRing(
			row(
				[
					session({ sessionId: "a", stateChangedAt: NOW - 50 }),
					session({
						sessionId: "b",
						provider: "codex",
						state: "waiting",
						reason: "question",
						stateChangedAt: NOW - 240,
					}),
				],
				{
					repos: [repo("app", "feat/ring"), repo("docs", "feat/ring")],
				},
			),
			"waiting",
			NOW,
		);
		expect(ring.title).toBe("feat/ring");
		expect(ring.repo).toBe("app");
		expect(ring.moreRepos).toBe(1);
		expect(ring.agents).toEqual(["codex", "claude"]);
		expect(ring.since).toBe(NOW - 240);
		expect(ring.waitReason).toBe("question");
	});

	it("is an empty ring for a task without sessions", () => {
		const ring = buildRing(row([]), "finished", NOW);
		expect(ring.arcs).toEqual([]);
		expect(ring.turnEnds).toEqual([]);
		expect(ring.agents).toEqual([]);
		expect(ring.since).toBe(42);
		expect(ring.title).toBe("t");
		expect(ring.waitReason).toBe("");
	});
});

describe("toolGroup", () => {
	it("groups the providers' names for the same kind of work", () => {
		expect(toolGroup("Bash")).toBe("Bash");
		expect(toolGroup("Edit")).toBe("Edit");
		expect(toolGroup("MultiEdit")).toBe("Edit");
		expect(toolGroup("apply_patch")).toBe("Edit");
		expect(toolGroup("Grep")).toBe("Search");
		expect(toolGroup("WebFetch")).toBe("Web");
		expect(toolGroup("TaskCreate")).toBe("Todo");
		expect(toolGroup("TodoWrite")).toBe("Todo");
		expect(toolGroup("AskUserQuestion")).toBe("Ask");
		expect(toolGroup("mcp__github__create_issue")).toBe("MCP");
		expect(toolGroup("SomethingNew")).toBe("Other");
	});

	it("gives every group its own place inside the ring", () => {
		const angles = (
			[
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
			] as const
		).map(hubAngle);
		expect(new Set(angles).size).toBe(11);
		expect(hubAngle("Bash")).toBe(-90);
	});
});

describe("buildRing calls", () => {
	const MIN = 60;

	it("places every task session's calls in the window by time, oldest first", () => {
		const ring = buildRing(
			row([
				session({
					sessionId: "a",
					calls: [
						{ tool: "Read", files: ["old.rs"], at: NOW - 4 * HOUR },
						{ tool: "Edit", files: ["store.rs"], at: NOW - 10 * MIN },
					],
				}),
				session({
					sessionId: "b",
					calls: [{ tool: "Bash", failed: true, at: NOW - 50 * MIN }],
				}),
			]),
			"running",
			NOW,
		);
		expect(
			ring.calls.map((call) => [call.group, call.failed, call.recent]),
		).toEqual([
			["Bash", true, false],
			["Edit", false, true],
		]);
		expect(ring.calls[1]?.angle).toBeCloseTo(ringAngle(NOW - 10 * MIN, NOW));
		expect(ring.calls.map((call) => call.fresh)).toEqual([false, false]);
		const fresh = buildRing(
			row([session({ calls: [{ tool: "Bash", at: NOW - 2 }] })]),
			"running",
			NOW,
		);
		expect(fresh.calls[0]?.fresh).toBe(true);
		expect(fresh.calls[0]?.at).toBe(NOW - 2);
		expect(ring.recentCalls).toBe(1);
	});

	it("counts calls per tool group for the nodes, in a stable order", () => {
		const ring = buildRing(
			row([
				session({
					calls: [
						{ tool: "Edit", at: NOW - 3 * MIN },
						{ tool: "apply_patch", at: NOW - 2 * MIN },
						{ tool: "Bash", at: NOW - MIN },
					],
				}),
			]),
			"running",
			NOW,
		);
		expect(ring.hubs.map((hub) => [hub.group, hub.count])).toEqual([
			["Bash", 1],
			["Edit", 2],
		]);
		expect(ring.hubs[1]?.angle).toBe(hubAngle("Edit"));
	});

	it("with work details, names the newest recent files, each once, spaced apart", () => {
		const names = ["a", "b", "c", "d", "e", "f", "g", "h"];
		const ring = buildRing(
			row([
				session({
					calls: [
						{ tool: "Read", files: ["stale.rs"], at: NOW - 40 * MIN },
						...names.map((name, i) => ({
							tool: "Edit",
							files: [`${name}.rs`],
							at: NOW - 10 * MIN + i,
						})),
						{ tool: "Edit", files: ["a.rs"], at: NOW - MIN },
					],
				}),
			]),
			"running",
			NOW,
			true,
		);
		expect(ring.files).toHaveLength(RING_FILES);
		expect(ring.files.map((file) => file.name)).toEqual([
			"a.rs",
			"h.rs",
			"g.rs",
			"f.rs",
			"e.rs",
			"d.rs",
		]);
		for (let i = 1; i < ring.files.length; i += 1)
			expect(
				(ring.files[i - 1]?.angle ?? 0) - (ring.files[i]?.angle ?? 0),
			).toBeGreaterThanOrEqual(16);
		expect(ring.files[0]?.angle).toBeCloseTo(ringAngle(NOW - MIN, NOW));
	});

	it("marks where turns began in the window", () => {
		const ring = buildRing(
			row([
				session({
					turns: [
						{ kind: "prompt", at: NOW - 5 * HOUR },
						{ kind: "prompt", at: NOW - HOUR },
						{ kind: "agent", at: NOW - 30 * MIN },
					],
				}),
			]),
			"running",
			NOW,
		);
		expect(ring.turnStarts.map((turn) => turn.kind)).toEqual([
			"prompt",
			"agent",
		]);
		expect(ring.turnStarts[0]?.angle).toBeCloseTo(ringAngle(NOW - HOUR, NOW));
	});

	it("has no calls, nodes or files when the collector sends none", () => {
		const ring = buildRing(row([session()]), "running", NOW);
		expect(ring.calls).toEqual([]);
		expect(ring.hubs).toEqual([]);
		expect(ring.files).toEqual([]);
		expect(ring.turnStarts).toEqual([]);
		expect(ring.recentCalls).toBe(0);
	});
});

describe("buildRing progress", () => {
	it("follows the most recently updated session that has todos", () => {
		const sessions = [
			session({
				sessionId: "old",
				updatedAt: NOW - 600,
				todos: { total: 4, done: 4 },
			}),
			session({
				sessionId: "new",
				updatedAt: NOW - 10,
				todos: { total: 7, done: 3, active: "Ring layout" },
			}),
			session({ sessionId: "none", updatedAt: NOW }),
		];
		const hidden = buildRing(row(sessions), "running", NOW);
		expect(hidden.progress).toEqual({ total: 7, done: 3, active: undefined });
		const shown = buildRing(row(sessions), "running", NOW, true);
		expect(shown.progress?.active).toBe("Ring layout");
	});

	it("has no progress without todos, and never more done than there are", () => {
		expect(
			buildRing(row([session()]), "running", NOW).progress,
		).toBeUndefined();
		expect(
			buildRing(
				row([session({ todos: { total: 0, done: 0 } })]),
				"running",
				NOW,
			).progress,
		).toBeUndefined();
		expect(
			buildRing(
				row([session({ todos: { total: 2, done: 5 } })]),
				"running",
				NOW,
			).progress?.done,
		).toBe(2);
	});

	it("scrubs the todo in progress like any lock screen text", () => {
		const ring = buildRing(
			row([
				session({ todos: { total: 1, done: 0, active: "rotate the api_key" } }),
			]),
			"running",
			NOW,
			true,
		);
		expect(ring.progress?.active).toBe("[sensitive content omitted]");
	});
});

describe("buildRing summary", () => {
	it("takes the summary of the turn that ended last, not the one that began last", () => {
		const turn = (startedAt: number, filesChanged: number) => ({
			startedAt,
			filesChanged,
			linesAdded: 10,
			linesRemoved: 2,
			tests: "passed" as const,
			commits: 0,
		});
		const ring = buildRing(
			row([
				// Began first, ended just now.
				session({
					sessionId: "long",
					state: "finished",
					stateChangedAt: NOW - 30,
					lastTurn: turn(NOW - HOUR, 4),
				}),
				// Began later, ended earlier.
				session({
					sessionId: "short",
					state: "finished",
					stateChangedAt: NOW - 600,
					lastTurn: turn(NOW - 1_200, 1),
				}),
				session({ sessionId: "running" }),
			]),
			"finished",
			NOW,
		);
		expect(ring.summary?.filesChanged).toBe(4);
		expect(buildRing(row([session()]), "running", NOW).summary).toBeUndefined();
	});

	it("knows a turn failed from the session's outcome even without a log", () => {
		const old = session({
			state: "finished",
			outcome: "error",
			stateChangedAt: NOW - 300,
		});
		const ring = buildRing(row([old]), "finished", NOW);
		expect(ring.turnEnds).toEqual([]);
		expect(ring.failed).toBe(true);
		expect(
			buildRing(row([{ ...old, outcome: "turn-ended" }]), "finished", NOW)
				.failed,
		).toBe(false);
		expect(
			buildRing(row([{ ...old, state: "running" }]), "running", NOW).failed,
		).toBe(false);
	});
});

describe("buildRing subagent reports", () => {
	it("marks a subagent's report as a hollow turn at its time on the task's ring", () => {
		const ring = buildRing(
			row([
				session({ turns: [{ kind: "prompt", at: NOW - HOUR }] }),
				session({
					sessionId: "s",
					agentId: "helper",
					state: "finished",
					turns: [{ kind: "agent", at: NOW - HOUR / 2 }],
				}),
			]),
			"running",
			NOW,
		);
		expect(ring.turnStarts.map((turn) => turn.kind)).toEqual([
			"prompt",
			"agent",
		]);
		expect(ring.turnStarts[1]?.angle).toBeCloseTo(
			ringAngle(NOW - HOUR / 2, NOW),
		);
		expect(ring.state).toBe("running");
	});
});

describe("review fixes", () => {
	it("groups Grok's terminal tool as Bash and never reads inherited names", () => {
		expect(toolGroup("run_terminal_command")).toBe("Bash");
		for (const name of [
			"constructor",
			"toString",
			"__proto__",
			"hasOwnProperty",
		])
			expect(toolGroup(name)).toBe("Other");
	});

	it("lets the lead's own successful outcome win over another session's old error", () => {
		const ring = buildRing(
			row([
				session({
					sessionId: "lead",
					state: "finished",
					outcome: "turn-ended",
					stateChangedAt: NOW - 60,
				}),
				session({
					sessionId: "older",
					state: "finished",
					outcome: "error",
					stateChangedAt: NOW - HOUR,
					transitions: [
						{ state: "running", at: NOW - 2 * HOUR },
						{ state: "finished", at: NOW - HOUR, outcome: "error" },
					],
				}),
			]),
			"finished",
			NOW,
		);
		expect(ring.turnEnds.at(-1)?.error).toBe(true);
		expect(ring.failed).toBe(false);
	});
});
