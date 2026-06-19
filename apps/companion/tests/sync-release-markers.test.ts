import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";

const scriptPath = resolve("scripts/sync-release-markers.mjs");

describe("sync release markers", () => {
	it("adds the release marker to a CRLF Cargo.lock package entry", () => {
		// Given a Cargo.lock package entry written with Windows CRLF line endings
		const workspace = mkdtempSync(join(tmpdir(), "workbranch-release-marker-"));
		const lockfilePath = join(workspace, "Cargo.lock");
		writeFileSync(
			lockfilePath,
			[
				"[[package]]",
				'name = "workbranch-companion"',
				'version = "2.1.0"',
				"",
			].join("\r\n"),
		);

		// When the release marker sync script runs against that lockfile
		execFileSync("node", [scriptPath, "--file", lockfilePath]);

		// Then the package version marker is added without requiring LF-only input
		expect(readFileSync(lockfilePath, "utf8")).toContain(
			'version = "2.1.0" # x-release-please-version',
		);
	});
});
