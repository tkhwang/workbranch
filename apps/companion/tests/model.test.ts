import { describe, expect, it } from "vitest";
import type { BaseRepo } from "../src/domain/model";
import { baseRepoAction, baseRepoHealth } from "../src/domain/model";

const CLEAN_BASE_REPO: BaseRepo = {
	name: "backend",
	baseBranch: "main",
	branch: "main",
	present: true,
	dirty: false,
	changedFiles: 0,
	remoteAvailable: true,
	ahead: 0,
	behind: 0,
	inspectionError: null,
};

describe("base repo status", () => {
	it.each([
		["ok", CLEAN_BASE_REPO, "ok", undefined],
		["dirty only", { ...CLEAN_BASE_REPO, dirty: true }, "warn", undefined],
		["clean ahead", { ...CLEAN_BASE_REPO, ahead: 1 }, "warn", "push"],
		[
			"dirty ahead",
			{ ...CLEAN_BASE_REPO, dirty: true, ahead: 1 },
			"warn",
			"push",
		],
		["clean behind", { ...CLEAN_BASE_REPO, behind: 1 }, "warn", "pull"],
		[
			"dirty behind",
			{ ...CLEAN_BASE_REPO, dirty: true, behind: 1 },
			"warn",
			"check",
		],
		["diverged", { ...CLEAN_BASE_REPO, ahead: 1, behind: 1 }, "bad", "check"],
		[
			"branch mismatch",
			{ ...CLEAN_BASE_REPO, branch: "release" },
			"bad",
			"check",
		],
		[
			"no remote",
			{ ...CLEAN_BASE_REPO, remoteAvailable: false },
			"bad",
			"check",
		],
		["missing", { ...CLEAN_BASE_REPO, present: false }, "bad", "check"],
		[
			"invalid worktree",
			{
				...CLEAN_BASE_REPO,
				present: false,
				inspectionError: "invalid-worktree",
			},
			"bad",
			"check",
		],
		[
			"git read failure",
			{
				...CLEAN_BASE_REPO,
				present: false,
				inspectionError: "git-read-failed",
			},
			"bad",
			"check",
		],
	] as const)("derives %s health and action", (_label, repo, expectedHealth, expectedAction) => {
		expect(baseRepoHealth(repo)).toBe(expectedHealth);
		expect(baseRepoAction(repo)).toBe(expectedAction);
	});

	it("changes CHECK to PULL and then no action as a dirty behind repo recovers", () => {
		const dirtyBehind = { ...CLEAN_BASE_REPO, dirty: true, behind: 1 };
		const cleanBehind = { ...dirtyBehind, dirty: false };
		const synchronized = { ...cleanBehind, behind: 0 };

		expect([
			[baseRepoHealth(dirtyBehind), baseRepoAction(dirtyBehind)],
			[baseRepoHealth(cleanBehind), baseRepoAction(cleanBehind)],
			[baseRepoHealth(synchronized), baseRepoAction(synchronized)],
		]).toEqual([
			["warn", "check"],
			["warn", "pull"],
			["ok", undefined],
		]);
	});
});
