import type { WorkbranchListGlobalDocument } from "@workbranch/contract";
import { describe, expect, it } from "vitest";
import {
	type ActivityEvent,
	buildPlanReport,
} from "../src/application/activity";
import { buildMenuModel } from "../src/application/state";
import { mapGlobalDocumentToState } from "../src/infrastructure/acl";

const document: WorkbranchListGlobalDocument = {
	schemaVersion: 1,
	projects: [
		{
			schemaVersion: 1,
			project: "fullstack",
			root: "/tmp/fullstack",
			tasks: [
				{
					name: "feat-login",
					path: "/tmp/fullstack/feat-login",
					memoTitle: "Login",
					planTitle: "Backend",
					status: "in-progress",
					progressDone: 1,
					progressTotal: 2,
					currentItem: "wire API",
					updatedAt: 10,
					items: [
						{ text: "Backend", checked: true, depth: 0 },
						{ text: "wire API", checked: false, depth: 1 },
					],
					plans: [],
					notiCount: 2,
					repos: [{ name: "backend", branch: "feature/login", dirty: true }],
				},
			],
		},
	],
	errors: [{ root: "/tmp/missing", message: "missing" }],
};

describe("ACL", () => {
	it("maps global CLI DTOs into companion domain tasks", () => {
		const state = mapGlobalDocumentToState(document);
		expect(
			state.projects[0]?.tasks[0]?.plans[0]?.steps[0]?.children[0]?.text,
		).toBe("wire API");
		expect(state.projects[0]?.tasks[0]?.repos[0]?.dirty).toBe(true);
		expect(state.errors[0]?.root).toBe("/tmp/missing");
	});

	it("builds a compact menu rollup", () => {
		const model = buildMenuModel(mapGlobalDocumentToState(document));
		expect(model.title).toBe("▶1 🔔2");
		expect(model.rows[0]?.expanded).toBe(true);
	});
});

describe("activity reports", () => {
	it("uses the latest empty item snapshot to clear older step rows", () => {
		const base: Omit<ActivityEvent, "observedAt" | "items"> = {
			v: 1,
			editedAt: 1,
			root: "/tmp/fullstack",
			project: "fullstack",
			task: "feat-login",
			plan: "Backend",
			planIndex: 0,
			planTitle: "Backend",
			planStatus: "in-progress",
			status: "in-progress",
			taskProgressDone: 1,
			taskProgressTotal: 2,
			progressDone: 1,
			progressTotal: 2,
		};
		const report = buildPlanReport([
			{
				...base,
				observedAt: 10,
				items: [{ text: "wire API", checked: false, depth: 0 }],
			},
			{ ...base, observedAt: 70, items: [] },
		]);
		expect(report[0]?.seconds).toBe(60);
		expect(report[0]?.latestItems).toEqual([]);
	});
});
