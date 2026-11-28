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
		recentCommits: [],
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
	return [...model.layout.rings, ...model.layout.overflow].map((ring) => [
		ring.state,
		ring.title,
	]);
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
		);
		expect(titles(model)).toEqual([
			["waiting", "asking"],
			["running", "busy"],
			["finished", "done"],
		]);
		expect(model.layout.mode).toBe("large");
		expect(model.layout.rings[0]?.waitReason).toBe("permission");
	});

	it("places live tasks most recent first and turns four or more into a grid", () => {
		const tasks = ["a", "b", "c", "d", "e"].map((name) => task(name));
		const model = buildDashboardModel(
			state([...tasks, task("done")]),
			[
				...tasks.map((t, index) =>
					session(t.name, "running", { stateChangedAt: 100 + index }),
				),
				session("done", "finished"),
			],
			NOW,
		);
		expect(model.layout.mode).toBe("grid");
		expect(model.layout.columns).toBe(3);
		expect(model.layout.rings.map((ring) => ring.title)).toEqual([
			"e",
			"d",
			"c",
			"b",
			"a",
		]);
		expect(model.layout.overflow.map((ring) => ring.title)).toEqual(["done"]);
	});

	it("never carries session ids or turn text", () => {
		const sessions = [
			session("busy", "running", {
				sessionId: "sess-secret-id",
				activity: "Bash: deploy --prod",
				messages: [{ kind: "prompt", text: "secret prompt text", at: NOW }],
			}),
		];
		const json = JSON.stringify(
			buildDashboardModel(state([task("busy")]), sessions, NOW),
		);
		expect(json).not.toContain("sess-secret-id");
		expect(json).not.toContain("secret prompt text");
		expect(json).not.toContain("deploy --prod");
	});

	it("carries file names, activity and the newest message only with work details", () => {
		const sessions = [
			session("busy", "running", {
				activity: "Edit: /work/busy/src/store.rs",
				messages: [{ kind: "prompt", text: "fix the store", at: NOW - 5 }],
				calls: [{ tool: "Edit", files: ["store.rs"], at: NOW - 10 }],
			}),
		];
		const hidden = buildDashboardModel(state([task("busy")]), sessions, NOW);
		const json = JSON.stringify(hidden);
		expect(json).not.toContain("store.rs");
		expect(json).not.toContain("fix the store");
		const ring = hidden.layout.rings[0];
		expect(ring?.calls).toHaveLength(1);
		expect(ring?.files).toEqual([]);
		expect(ring?.activity).toBeUndefined();
		expect(ring?.message).toBeUndefined();

		const shown = buildDashboardModel(
			state([task("busy")]),
			sessions,
			NOW,
			true,
		).layout.rings[0];
		expect(shown?.files.map((file) => file.name)).toEqual(["store.rs"]);
		expect(shown?.calls[0]?.files).toEqual(["store.rs"]);
		expect(shown?.activity).toBe("Edit: /work/busy/src/store.rs");
		expect(shown?.message).toEqual({
			kind: "prompt",
			text: "fix the store",
			at: NOW - 5,
		});
		expect(JSON.stringify(shown)).not.toContain("busy-s");
	});

	it("scrubs a credential-looking activity even with work details on", () => {
		const shown = buildDashboardModel(
			state([task("busy")]),
			[
				session("busy", "running", {
					activity: "Bash: curl -H 'Authorization: x'",
				}),
			],
			NOW,
			true,
		).layout.rings[0];
		expect(shown?.activity).toBe("[sensitive content omitted]");
	});

	it("titles a ring by its worktree branch and names extra repos by count", () => {
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
		);
		const rings = model.layout.rings;
		expect(rings.find((ring) => ring.key === "/work:multi")).toMatchObject({
			title: "feat/x",
			repo: "workbranch",
			moreRepos: 1,
			agents: ["claude"],
		});
		expect(rings.find((ring) => ring.key === "/work:bare")).toMatchObject({
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
		);
		expect(model.counts).toEqual({ waiting: 1, running: 1, finished: 0 });
		expect(model.active).toBe(2);
	});

	it("counts every live task in the active total, beyond the rings shown", () => {
		const names = ["a", "b", "c", "d", "e", "f", "g"];
		const model = buildDashboardModel(
			state([...names.map((name) => task(name)), task("done")]),
			[
				...names.map((name) => session(name, "running")),
				session("done", "finished"),
			],
			NOW,
		);
		expect(model.layout.rings).toHaveLength(6);
		expect(model.layout.overflow).toHaveLength(2);
		expect(model.active).toBe(8);
	});

	it("has no active tasks when nothing is in play", () => {
		const model = buildDashboardModel(state([]), [], NOW);
		expect(model.active).toBe(0);
		expect(model.layout.rings).toEqual([]);
		expect(model.layout.overflow).toEqual([]);
	});
});
