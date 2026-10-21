import { describe, expect, it } from "vitest";
import { buildDashboardModel } from "../src/application/dashboard";
import type {
	AgentSession,
	GlobalState,
	Repo,
	Task,
} from "../src/domain/model";

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
	};
}

function task(name: string, repos: readonly Repo[] = []): Task {
	return {
		name,
		path: `/work/${name}`,
		notiCount: 0,
		repos,
		updatedAt: 1,
	};
}

function session(
	taskName: string,
	state: AgentSession["state"],
	fields: Partial<AgentSession> = {},
): AgentSession {
	return {
		workspace: `/work/${taskName}`,
		provider: "claude",
		sessionId: `${taskName}-s`,
		agentId: "",
		turnId: "t",
		state,
		observation: "observed",
		reason: "",
		prompt: "secret prompt text",
		activity: "",
		response: "",
		outcome: "",
		updatedAt: 100,
		stateChangedAt: 100,
		...fields,
	};
}

function state(tasks: readonly Task[]): GlobalState {
	return {
		projects: [{ name: "workbranch", root: "/work", tasks, baseRepos: [] }],
		errors: [],
	};
}

// Epoch seconds for "now" in these tests; sessions changed state at 100.
const NOW = 200;

function titles(model: ReturnType<typeof buildDashboardModel>) {
	return model.timeline.rows.map((row) => [row.state, row.title]);
}

describe("buildDashboardModel", () => {
	it("shows only tasks with a waiting, running or finished session, in board order", () => {
		const model = buildDashboardModel(
			state([
				task("busy"),
				task("asking"),
				task("done"),
				task("quiet"),
				task("unseen"),
				task("bare"),
			]),
			[
				session("done", "finished"),
				session("busy", "running"),
				session("asking", "waiting", { reason: "permission" }),
				session("quiet", "idle"),
				session("unseen", "running", { observation: "stale" }),
			],
			NOW,
			8,
		);
		expect(titles(model)).toEqual([
			["waiting", "asking"],
			["running", "busy"],
			["finished", "done"],
		]);
	});

	it("caps the rows, most recent first, and counts the rest", () => {
		const tasks = ["a", "b", "c", "d", "e", "f"].map((name) => task(name));
		const model = buildDashboardModel(
			state(tasks),
			tasks.map((t, index) =>
				session(t.name, "running", { stateChangedAt: 100 + index }),
			),
			NOW,
			4,
		);
		expect(model.timeline.rows.map((row) => row.title)).toEqual([
			"f",
			"e",
			"d",
			"c",
		]);
		expect(model.timeline.more).toBe(2);
	});

	it("never carries session ids or the agent's turn text", () => {
		const model = buildDashboardModel(
			state([task("busy")]),
			[session("busy", "running", { sessionId: "sess-secret-id" })],
			NOW,
			8,
		);
		const json = JSON.stringify(model);
		expect(json).not.toContain("sess-secret-id");
		expect(json).not.toContain("secret prompt text");
	});

	it("titles a row by its worktree branch and names extra repos by count", () => {
		const model = buildDashboardModel(
			state([
				task("multi", [
					repo("workbranch", "feat/x"),
					repo("homebrew-tap", "feat/x"),
				]),
				task("bare"),
			]),
			[session("multi", "running"), session("bare", "running")],
			NOW,
			8,
		);
		const rows = model.timeline.rows;
		expect(rows.find((row) => row.key === "/work:multi")).toMatchObject({
			title: "feat/x",
			repo: "workbranch",
			moreRepos: 1,
			agent: "claude",
		});
		expect(rows.find((row) => row.key === "/work:bare")).toMatchObject({
			title: "bare",
			repo: undefined,
			moreRepos: 0,
		});
	});

	it("tells the counts and the active total", () => {
		const model = buildDashboardModel(
			state([task("busy"), task("asking")]),
			[session("busy", "running"), session("asking", "waiting")],
			NOW,
			8,
		);
		expect(model.counts).toEqual({ waiting: 1, running: 1, finished: 0 });
		expect(model.active).toBe(2);
	});

	it("counts every live task in the active total, beyond the rows shown", () => {
		const names = ["a", "b", "c", "d", "e", "f"];
		const model = buildDashboardModel(
			state([...names.map((name) => task(name)), task("done")]),
			[
				...names.map((name) => session(name, "running")),
				session("done", "finished"),
			],
			NOW,
			4,
		);
		expect(model.timeline.rows).toHaveLength(4);
		expect(model.active).toBe(7);
	});

	it("has no active tasks when nothing is in play", () => {
		const model = buildDashboardModel(state([]), [], NOW, 8);
		expect(model.active).toBe(0);
		expect(model.timeline.rows).toEqual([]);
	});
});
