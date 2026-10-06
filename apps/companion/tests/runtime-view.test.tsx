import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { buildMainViewModel } from "../src/application/state";
import type {
	AgentSession,
	GlobalState,
	Repo,
	Task,
} from "../src/domain/model";
import {
	parseGlobalDocument,
	parseRuntimeDocument,
} from "../src/infrastructure/parseContract";
import { StageBoard } from "../src/ui/StageBoard";

const state: GlobalState = {
	projects: [
		{
			name: "project",
			root: "/p",
			baseRepos: [],
			tasks: [
				{
					name: "task",
					path: "/p/task",
					notiCount: 0,
					repos: [],
					updatedAt: 0,
				},
			],
		},
	],
	errors: [],
};
const session: AgentSession = {
	workspace: "/p/task",
	provider: "claude",
	sessionId: "s",
	agentId: "",
	turnId: "t",
	state: "waiting",
	observation: "observed",
	reason: "permission",
	prompt: "Fix login",
	activity: "Bash: pnpm test",
	response: "",
	updatedAt: 100,
	stateChangedAt: 100,
	outcome: "",
};
const repo: Repo = {
	name: "backend",
	branch: "feature/cpq-task-b",
	dirty: true,
	activityAvailable: true,
	ahead: 0,
	behind: 1,
	changedFiles: 3,
	lastCommitSubject: "refactor(cpq): RFQ 물량 단위 검증",
	lastCommitAt: 50,
};

function task(name: string, repos: readonly Repo[] = []): Task {
	return { name, path: `/p/${name}`, notiCount: 0, repos, updatedAt: 0 };
}

function stateWith(tasks: readonly Task[]): GlobalState {
	return {
		projects: [{ name: "project", root: "/p", baseRepos: [], tasks }],
		errors: [],
	};
}

function renderBoard(
	globalState: GlobalState,
	sessions: readonly AgentSession[],
): string {
	const model = buildMainViewModel(globalState, sessions);
	return renderToStaticMarkup(
		<StageBoard
			baseRows={[]}
			groups={model.stageGroups}
			idleRows={model.idleRows}
			idleCount={model.idleCount}
			activeCount={model.activeCount}
			notes={{}}
			onSaveNote={() => {}}
			onAction={() => {}}
			onSelect={() => {}}
			selectedKey={undefined}
		/>,
	);
}

describe("runtime UI", () => {
	it("keeps one task with waiting and running session counts", () => {
		const model = buildMainViewModel(state, [
			session,
			{
				...session,
				sessionId: "other",
				provider: "codex",
				state: "running",
				reason: "",
			},
		]);
		expect(model.matrixRows).toHaveLength(1);
		expect(model.stageGroups[0]?.rows).toHaveLength(1);
		expect(model.matrixRows[0]?.sessions).toHaveLength(2);
		const html = renderBoard(state, [
			session,
			{
				...session,
				sessionId: "other",
				provider: "codex",
				state: "running",
				reason: "",
			},
		]);
		expect(html).toContain("Fix login");
		expect(html).toContain("Bash: pnpm test");
		expect(html).toContain("권한 승인 대기");
		expect(html).toContain("+1 실행 중");
		// Providers collapse to one icon each, lead session first.
		const meta = html.slice(html.indexOf('class="runtime-meta"'));
		expect(meta.indexOf('aria-label="Claude Code"')).toBeGreaterThan(-1);
		expect(meta.indexOf('aria-label="Codex"')).toBeGreaterThan(
			meta.indexOf('aria-label="Claude Code"'),
		);
		expect(html).not.toMatch(/>claude</i);
		expect(html.match(/class="runtime-card"/g)).toHaveLength(1);
		expect(html).not.toContain("PLAN");
	});
	it("lays out waiting, running and review as ordered kanban columns", () => {
		const html = renderBoard(state, [session]);
		const order = ["WAITING", "RUNNING", "REVIEW"].map((code) =>
			html.indexOf(`>${code}<`),
		);
		expect(order.every((index) => index >= 0)).toBe(true);
		expect([...order].sort((a, b) => a - b)).toEqual(order);
		expect(html).toContain('class="runtime-column-empty"');
	});
	it("shows launchers and repo facts without expanding the card", () => {
		const html = renderBoard(stateWith([task("task-b", [repo])]), [
			{ ...session, workspace: "/p/task-b", state: "running", reason: "" },
		]);
		expect(html).toContain('aria-expanded="false"');
		expect(html).toContain('aria-label="open task-b in IDE"');
		expect(html).toContain('aria-label="open task-b in terminal"');
		expect(html).toContain('aria-label="open task-b in Finder"');
		expect(html).not.toMatch(/aria-label="open task-b in IDE"[^>]*disabled/);
		expect(html).toContain("feature/cpq-task-b");
		expect(html).toContain('aria-label="DIRTY 3 FILES · BEHIND 1"');
		expect(html).toContain("●3");
		expect(html).toContain("↓1");
		// Commit history belongs to the expanded details.
		expect(html).not.toContain("last commit:");
		// The card itself carries no hover tooltip that would cover its content.
		expect(html).not.toMatch(/class="runtime-card-toggle"[^>]*title=/);
	});
	it("gives the task name its own line and names a shared branch once", () => {
		const html = renderBoard(
			stateWith([
				task("task-b", [repo, { ...repo, name: "frontend", dirty: false }]),
			]),
			[{ ...session, workspace: "/p/task-b", state: "running", reason: "" }],
		);
		expect(html).toContain(
			'<span class="runtime-project" title="project">project</span>',
		);
		expect(html).toContain('<span class="runtime-task-name">task-b</span>');
		expect(html.match(/feature\/cpq-task-b<\/span>/g)).toHaveLength(1);
		expect(html).toContain('title="branch: feature/cpq-task-b"');
		expect(html).not.toContain('class="stage-repo-branch"');
		expect(html).toContain('class="runtime-meta"');
	});
	it("shows each branch under its repo when worktree branches differ", () => {
		const html = renderBoard(
			stateWith([
				task("task-b", [repo, { ...repo, name: "frontend", branch: "main" }]),
			]),
			[{ ...session, workspace: "/p/task-b", state: "running", reason: "" }],
		);
		expect(html.match(/class="runtime-branch"/g)).toHaveLength(2);
		// No shared caption: the first branch line sits inside the first repo row.
		expect(html.indexOf('class="runtime-branch"')).toBeGreaterThan(
			html.indexOf('class="stage-repo-row"'),
		);
		expect(html).toContain('title="branch: feature/cpq-task-b"');
		expect(html).toContain('title="branch: main"');
	});
	it("prints CLEAN only when a repo has no other fact", () => {
		const html = renderBoard(
			stateWith([
				task("task-b", [
					{ ...repo, dirty: false, behind: 0 },
					{ ...repo, name: "frontend", dirty: false, behind: 0, ahead: 2 },
				]),
			]),
			[{ ...session, workspace: "/p/task-b", state: "running", reason: "" }],
		);
		expect(html.match(/>CLEAN</g)).toHaveLength(1);
		expect(html).toContain('aria-label="CLEAN · AHEAD 2"');
		expect(html).toContain(">↑2<");
	});
	it("keeps repo-less tasks launchable from the root while disabling IDE", () => {
		const html = renderBoard(state, [session]);
		expect(html).toContain("NO REPOSITORIES");
		expect(html).toMatch(/aria-label="open task in IDE"[^>]*disabled/);
		expect(html).not.toMatch(/aria-label="open task in terminal"[^>]*disabled/);
		expect(html).not.toContain('class="runtime-branch"');
	});
	it("surfaces the last response and interruption on review cards", () => {
		const html = renderBoard(state, [
			{
				...session,
				state: "finished",
				reason: "",
				outcome: "interrupted",
				response: "migration을 적용하기 전에 확인이 필요합니다",
			},
		]);
		expect(html).toContain("중단됨");
		expect(html).toContain('data-kind="response"');
		expect(html).toContain("migration을 적용하기 전에 확인이 필요합니다");
	});
	it("lists session-less, unknown and idle tasks under launchable workspaces", () => {
		const html = renderBoard(
			stateWith([task("fresh", [repo]), task("stale"), task("ended")]),
			[
				{
					...session,
					workspace: "/p/stale",
					state: "running",
					observation: "stale",
				},
				{ ...session, workspace: "/p/ended", state: "idle", reason: "" },
			],
		);
		const inventory = html.slice(html.indexOf('aria-label="Workspaces"'));
		expect(inventory).toContain("세션 없음");
		expect(inventory).toContain("관측 불명");
		expect(inventory).toContain("비활성");
		expect(inventory).toContain('data-variant="row"');
		expect(inventory).toContain('aria-label="open fresh in IDE"');
		expect(
			html.slice(0, html.indexOf('aria-label="Workspaces"')),
		).not.toContain('class="runtime-card"');
	});
	it("tints each card border by its lead provider and rings waiting cards", () => {
		const html = renderBoard(state, [
			{ ...session, provider: "codex" },
			{ ...session, sessionId: "other", state: "running", reason: "" },
		]);
		expect(html).toMatch(
			/class="runtime-card"[^>]*data-provider="codex"[^>]*data-state="waiting"/,
		);
		const css = readFileSync("src/styles/stage-board.css", "utf8");
		for (const provider of ["claude", "codex", "grok"]) {
			expect(css).toMatch(
				new RegExp(
					`\\.runtime-card\\[data-provider="${provider}"\\]\\s*\\{[^}]*border-color:\\s*var\\(--provider-${provider}-line\\)`,
				),
			);
		}
		expect(css).toMatch(
			/\.runtime-card\[data-state="waiting"\]\s*\{\s*box-shadow:\s*0 0 0 3px var\(--runtime-waiting-ring\);\s*\}/,
		);
	});
	it("switches to three columns only when the board is wide enough", () => {
		const css = readFileSync("src/styles/stage-board.css", "utf8");
		expect(css).toMatch(
			/\.runtime-board\s*\{[^}]*container:\s*runtime-board \/ inline-size/s,
		);
		expect(css).toMatch(
			/@container runtime-board \(min-width: 720px\)\s*\{\s*\.runtime-columns\s*\{[^}]*grid-template-columns:\s*repeat\(3, minmax\(0, 1fr\)\)/s,
		);
		expect(css).toMatch(
			/\.runtime-card-toggle,\s*\.runtime-card-head > \.stage-actions\s*\{[^}]*grid-area:\s*1 \/ 1/s,
		);
	});
	it("does not count stale running as confirmed running", () => {
		expect(
			buildMainViewModel(state, [
				{ ...session, state: "running", observation: "stale" },
			]).stageGroups.find((g) => g.column === "unknown")?.rows,
		).toHaveLength(1);
	});
	it("orders session rows by activity, then session-less rows alphabetically", () => {
		const model = buildMainViewModel(
			stateWith([
				{ ...task("zeta"), updatedAt: 900 },
				task("alpha"),
				task("older"),
				task("newer"),
			]),
			[
				{ ...session, workspace: "/p/older", stateChangedAt: 100 },
				{ ...session, workspace: "/p/newer", stateChangedAt: 200 },
			],
		);
		expect(model.matrixRows.map((r) => r.task.name)).toEqual([
			"newer",
			"older",
			"alpha",
			"zeta",
		]);
	});
	it("interleaves unknown and idle workspaces in the same order", () => {
		const html = renderBoard(stateWith([task("beta"), task("alpha")]), [
			{ ...session, workspace: "/p/beta", state: "idle", reason: "" },
		]);
		const inventory = html.slice(html.indexOf('aria-label="Workspaces"'));
		expect(inventory.indexOf("open beta in IDE")).toBeLessThan(
			inventory.indexOf("open alpha in IDE"),
		);
	});
	it("orders base repositories by project, then repo name", () => {
		const base = (name: string) => ({
			name,
			baseBranch: "main",
			branch: "main",
			present: true,
			dirty: false,
			changedFiles: 0,
			remoteAvailable: true,
			ahead: 0,
			behind: 0,
			inspectionError: null,
		});
		const model = buildMainViewModel({
			projects: [
				{
					name: "workbranch",
					root: "/w",
					baseRepos: [base("workbranch")],
					tasks: [],
				},
				{
					name: "monask",
					root: "/m",
					baseRepos: [base("frontend"), base("backend")],
					tasks: [],
				},
			],
			errors: [],
		});
		expect(model.baseRows.map((r) => `${r.project}/${r.repo.name}`)).toEqual([
			"monask/backend",
			"monask/frontend",
			"workbranch/workbranch",
		]);
	});
	it("rejects old CLI versions with an actionable message", () => {
		expect(() =>
			parseGlobalDocument('{"schemaVersion":1,"projects":[],"errors":[]}'),
		).toThrow(/update/i);
	});
	it("rejects malformed runtime enum", () => {
		expect(() =>
			parseRuntimeDocument(
				JSON.stringify({
					schemaVersion: 1,
					sessions: [{ ...session, state: "complete" }],
				}),
			),
		).toThrow();
	});
});
