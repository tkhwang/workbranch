import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const companionRoot = resolve(import.meta.dirname, "..");
const repoRoot = resolve(companionRoot, "..", "..");

describe("release marker contract", () => {
	it("keeps Cargo.lock markerless and delegates release updates to TOML JSONPath", () => {
		// Given release-please manages the generated Cargo.lock structurally
		const releasePleaseConfig = JSON.parse(
			readFileSync(resolve(repoRoot, "release-please-config.json"), "utf8"),
		);
		const packageJson = JSON.parse(
			readFileSync(resolve(companionRoot, "package.json"), "utf8"),
		);
		const rootPackageJson = JSON.parse(
			readFileSync(resolve(repoRoot, "package.json"), "utf8"),
		);
		const cargoLock = readFileSync(
			resolve(companionRoot, "src-tauri", "Cargo.lock"),
			"utf8",
		);

		// When companion release metadata is inspected
		const cargoLockUpdater = releasePleaseConfig.packages["apps/companion"][
			"extra-files"
		].find(
			(file: { readonly path: string }) => file.path === "src-tauri/Cargo.lock",
		);
		const markerScripts = [
			...Object.entries(packageJson.scripts).map(([name, command]) => ({
				name: `companion:${name}`,
				command,
			})),
			...Object.entries(rootPackageJson.scripts).map(([name, command]) => ({
				name: `root:${name}`,
				command,
			})),
		].filter(
			({ name, command }) =>
				name.includes("release-markers") ||
				String(command).includes("release-markers"),
		);

		// Then no local script needs to rewrite comments into Cargo.lock
		expect(cargoLockUpdater).toEqual({
			type: "toml",
			path: "src-tauri/Cargo.lock",
			jsonpath: '$.package[?(@.name.value=="workbranch-companion")].version',
		});
		expect(cargoLock).not.toContain("x-release-please-version");
		expect(markerScripts).toEqual([]);
	});
});
