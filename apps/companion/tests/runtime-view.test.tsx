import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { buildMainViewModel } from "../src/application/state";
import type { AgentSession, GlobalState } from "../src/domain/model";
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
		const html = renderToStaticMarkup(
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
		expect(html).toContain("Fix login");
		expect(html).toContain("Bash: pnpm test");
		expect(html).toContain("대기 1");
		expect(html).not.toContain("PLAN");
	});
	it("does not count stale running as confirmed running", () => {
		expect(
			buildMainViewModel(state, [
				{ ...session, state: "running", observation: "stale" },
			]).stageGroups.find((g) => g.column === "unknown")?.rows,
		).toHaveLength(1);
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
