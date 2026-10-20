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

describe("buildDashboardModel", () => {
	it("keeps the three board columns in board order", () => {
		const model = buildDashboardModel(state([]), [], 4);
		expect(model.columns.map((column) => column.key)).toEqual([
			"waiting",
			"running",
			"finished",
		]);
		expect(model.columns.every((column) => column.count === 0)).toBe(true);
	});

	it("shows only tasks with a waiting, running or finished session", () => {
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
				session("busy", "running"),
				session("asking", "waiting", { reason: "permission" }),
				session("done", "finished"),
				session("quiet", "idle"),
				session("unseen", "running", { observation: "stale" }),
			],
			4,
		);
		const names = Object.fromEntries(
			model.columns.map((column) => [
				column.key,
				column.cards.map((card) => card.task),
			]),
		);
		expect(names).toEqual({
			waiting: ["asking"],
			running: ["busy"],
			finished: ["done"],
		});
	});

	it("caps each column and counts the rest", () => {
		const tasks = ["a", "b", "c", "d", "e", "f"].map((name) => task(name));
		const model = buildDashboardModel(
			state(tasks),
			tasks.map((t, index) =>
				session(t.name, "running", { stateChangedAt: 100 + index }),
			),
			4,
		);
		const running = model.columns.find((column) => column.key === "running");
		expect(running?.count).toBe(6);
		expect(running?.cards).toHaveLength(4);
		expect(running?.more).toBe(2);
		// Most recent activity first, as on the board.
		expect(running?.cards[0]?.task).toBe("f");
	});

	it("describes a card as the menu bar card does: task, prompt, what it waits on, repo state", () => {
		const model = buildDashboardModel(
			state([
				task("fix-sync", [
					{
						...repo("workbranch", "fix/sync"),
						dirty: true,
						changedFiles: 2,
						ahead: 3,
					},
				]),
			]),
			[
				session("fix-sync", "waiting", {
					provider: "codex",
					reason: "permission",
					stateChangedAt: 500,
					prompt: "retry sync with backoff",
					activity: "Bash: git push origin fix/sync",
				}),
			],
			4,
		);
		expect(model.columns[0]?.cards[0]).toEqual({
			key: "/work:fix-sync",
			task: "fix-sync",
			repo: "workbranch",
			branch: "fix/sync",
			agent: "codex",
			since: 500,
			reason: "permission",
			prompt: "retry sync with backoff",
			detail: { kind: "activity", text: "Bash: git push origin fix/sync" },
			outcome: undefined,
			changes: { dirty: true, files: 2, ahead: 3, behind: 0 },
			notifications: 0,
		});
	});

	it("shows the live tool while running and the last answer once the turn ends", () => {
		const model = buildDashboardModel(
			state([task("busy"), task("done"), task("quiet-end")]),
			[
				session("busy", "running", {
					activity: "Edit: src/ui/Dashboard.tsx",
					response: "stale answer",
				}),
				session("done", "finished", {
					activity: "Bash: pnpm test",
					response: "All 227 tests pass.",
				}),
				session("quiet-end", "finished", { activity: "Read: README.md" }),
			],
			4,
		);
		const cards = model.columns.flatMap((column) => column.cards);
		const detail = (name: string) =>
			cards.find((card) => card.task === name)?.detail;
		expect(detail("busy")).toEqual({
			kind: "activity",
			text: "Edit: src/ui/Dashboard.tsx",
		});
		expect(detail("done")).toEqual({
			kind: "response",
			text: "All 227 tests pass.",
		});
		// Without an answer the card falls back to the last tool, as on the board.
		expect(detail("quiet-end")).toEqual({
			kind: "activity",
			text: "Read: README.md",
		});
	});

	it("leaves out empty session text", () => {
		const model = buildDashboardModel(
			state([task("fresh")]),
			[session("fresh", "running", { prompt: "", activity: "" })],
			4,
		);
		expect(model.columns[1]?.cards[0]).toMatchObject({
			prompt: undefined,
			detail: undefined,
		});
	});

	it("marks a turn that ended in an error or an interrupt", () => {
		const model = buildDashboardModel(
			state([task("broke"), task("stopped"), task("fine")]),
			[
				session("broke", "finished", { outcome: "error" }),
				session("stopped", "finished", { outcome: "interrupted" }),
				session("fine", "finished", { outcome: "turn-ended" }),
			],
			4,
		);
		const outcomes = Object.fromEntries(
			(model.columns[2]?.cards ?? []).map((card) => [card.task, card.outcome]),
		);
		expect(outcomes).toEqual({
			broke: "error",
			stopped: "interrupted",
			fine: undefined,
		});
	});

	it("sums repo state over the task's repos and carries its notifications", () => {
		const model = buildDashboardModel(
			state([
				{
					...task("multi", [
						{ ...repo("a", "x"), dirty: true, changedFiles: 4, ahead: 1 },
						{ ...repo("b", "x"), dirty: true, changedFiles: 3, behind: 2 },
						// A dirty repo whose files could not be counted adds no number.
						{
							...repo("c", "x"),
							dirty: true,
							activityAvailable: false,
							changedFiles: 9,
						},
					]),
					notiCount: 2,
				},
			]),
			[session("multi", "running")],
			4,
		);
		expect(model.columns[1]?.cards[0]).toMatchObject({
			changes: { dirty: true, files: 7, ahead: 1, behind: 2 },
			notifications: 2,
		});
	});

	it("never carries session ids or the agent's raw turn data", () => {
		const model = buildDashboardModel(
			state([task("busy")]),
			[session("busy", "running", { sessionId: "sess-secret-id" })],
			4,
		);
		expect(JSON.stringify(model)).not.toContain("sess-secret-id");
	});

	it("names extra repos by count and the shared branch once", () => {
		const model = buildDashboardModel(
			state([
				task("multi", [
					repo("workbranch", "feat/x"),
					repo("homebrew-tap", "feat/x"),
				]),
				task("split", [repo("a", "one"), repo("b", "two")]),
			]),
			[session("multi", "running"), session("split", "running")],
			4,
		);
		const cards = model.columns[1]?.cards ?? [];
		expect(cards.find((card) => card.task === "multi")).toMatchObject({
			repo: "workbranch +1",
			branch: "feat/x",
		});
		expect(cards.find((card) => card.task === "split")).toMatchObject({
			repo: "a +1",
			branch: "one",
		});
	});

	it("tells the counts and whether anything is in play", () => {
		const model = buildDashboardModel(
			state([task("busy"), task("asking")]),
			[session("busy", "running"), session("asking", "waiting")],
			4,
		);
		expect(model.counts).toEqual({ waiting: 1, running: 1, finished: 0 });
		expect(model.active).toBe(2);
	});

	it("counts every live task in the active total, beyond the cards shown", () => {
		const names = ["a", "b", "c", "d", "e", "f"];
		const model = buildDashboardModel(
			state([...names.map((name) => task(name)), task("done")]),
			[
				...names.map((name) => session(name, "running")),
				session("done", "finished"),
			],
			4,
		);
		expect(model.columns[1]?.cards).toHaveLength(4);
		expect(model.active).toBe(7);
	});

	it("has no active tasks when nothing is in play", () => {
		expect(buildDashboardModel(state([]), [], 3).active).toBe(0);
	});
});
