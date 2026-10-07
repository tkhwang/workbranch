import { describe, expect, it } from "vitest";
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
