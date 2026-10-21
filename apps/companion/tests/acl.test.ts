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
	it("maps the task's recent commits, none from an older CLI", () => {
		const repo = {
			name: "app",
			branch: "feat/x",
			dirty: false,
			lastCommitSubject: "second",
			lastCommitAt: 20,
		};
		const dto = parseGlobalDocument(
			JSON.stringify({
				schemaVersion: 2,
				projects: [
					{
						schemaVersion: 2,
						project: "p",
						root: "/p",
						tasks: [
							{
								name: "t",
								path: "/p/t",
								notiCount: 0,
								repos: [
									{
										...repo,
										recentCommits: [
											{ subject: "second", at: 20 },
											{ subject: "first", at: 10 },
										],
									},
									{ ...repo, name: "old" },
								],
							},
						],
					},
				],
				errors: [],
			}),
		);
		const repos = mapGlobalDocumentToState(dto).projects[0]?.tasks[0]?.repos;
		expect(repos?.[0]?.recentCommits).toEqual([
			{ subject: "second", at: 20 },
			{ subject: "first", at: 10 },
		]);
		expect(repos?.[1]?.recentCommits).toEqual([]);
	});
	it("rejects malformed recent commits", () => {
		for (const recentCommits of [
			[{ subject: 1, at: 1 }],
			[{ subject: "x", at: -1 }],
			{ subject: "x", at: 1 },
		])
			expect(() =>
				parseGlobalDocument(
					JSON.stringify({
						schemaVersion: 2,
						projects: [
							{
								schemaVersion: 2,
								project: "p",
								root: "/p",
								tasks: [
									{
										name: "t",
										path: "/p/t",
										notiCount: 0,
										repos: [
											{ name: "a", branch: "b", dirty: false, recentCommits },
										],
									},
								],
							},
						],
						errors: [],
					}),
				),
			).toThrow();
	});
	it("preserves partial project errors", () => {
		const dto = parseGlobalDocument(
			'{"schemaVersion":2,"projects":[],"errors":[{"root":"/missing","message":"unavailable"}]}',
		);
		expect(mapGlobalDocumentToState(dto).errors).toEqual(dto.errors);
	});
});
