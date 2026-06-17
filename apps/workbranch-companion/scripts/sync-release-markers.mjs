#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const companionRoot = resolve(scriptDirectory, "..");
const defaultCargoLockPath = resolve(companionRoot, "src-tauri", "Cargo.lock");

function parseArgs(argv) {
	let check = false;
	let filePath = defaultCargoLockPath;
	for (let index = 0; index < argv.length; index += 1) {
		const arg = argv[index];
		if (arg === "--check") {
			check = true;
			continue;
		}
		if (arg === "--file") {
			const value = argv[index + 1];
			if (!value) {
				throw new Error("--file requires a path");
			}
			filePath = resolve(value);
			index += 1;
			continue;
		}
		throw new Error(`unknown argument: ${arg}`);
	}
	return { check, filePath };
}

function syncCargoLockMarker(cargoLock) {
	const packageEntry = /(^\[\[package\]\]\nname = "workbranch-companion"\nversion = "([^"]+)")(?: # x-release-please-version)?/m;
	if (!packageEntry.test(cargoLock)) {
		throw new Error(
			"Cargo.lock must include the workbranch-companion package entry",
		);
	}
	return cargoLock.replace(packageEntry, '$1 # x-release-please-version');
}

function main() {
	const { check, filePath } = parseArgs(process.argv.slice(2));
	const before = readFileSync(filePath, "utf8");
	const after = syncCargoLockMarker(before);
	if (before === after) {
		return;
	}
	if (check) {
		throw new Error(
			`${filePath} is missing the workbranch-companion x-release-please-version marker. Run pnpm --filter @workbranch/companion sync:release-markers.`,
		);
	}
	writeFileSync(filePath, after);
}

try {
	main();
} catch (error) {
	const message = error instanceof Error ? error.message : String(error);
	console.error(`[-] Error: ${message}`);
	process.exit(1);
}
