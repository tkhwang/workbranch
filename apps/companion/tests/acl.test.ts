import { describe, expect, it } from "vitest";
import {
	type ActivityEvent,
	buildPlanReport,
} from "../src/application/activity";
import { mapGlobalDocumentToState } from "../src/infrastructure/acl";
import { parseGlobalDocument } from "../src/infrastructure/parseContract";

describe("schema 2 ACL", () => {
	it("maps identity and Git facts without brief fallback", () => {
		const dto = parseGlobalDocument(
			JSON.stringify({
				schemaVersion: 2,
				projects: [
					{
						schemaVersion: 2,
						project: "p",
						root: "/p",
						tasks: [{ name: "t", path: "/p/t", notiCount: 0, repos: [] }],
					},
				],
				errors: [],
			}),
		);
		const state = mapGlobalDocumentToState(dto);
		expect(state.projects[0]?.tasks[0]).toEqual({
			name: "t",
			path: "/p/t",
			notiCount: 0,
			repos: [],
			updatedAt: 0,
		});
	});
	it("preserves partial project errors", () => {
		const dto = parseGlobalDocument(
			'{"schemaVersion":2,"projects":[],"errors":[{"root":"/missing","message":"unavailable"}]}',
		);
		expect(mapGlobalDocumentToState(dto).errors).toEqual(dto.errors);
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
