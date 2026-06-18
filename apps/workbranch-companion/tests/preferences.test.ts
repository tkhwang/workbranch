import assert from "node:assert/strict";
import { describe, expect, it } from "vitest";
import {
	COMPANION_FONT_OPTIONS,
	COMPANION_THEME_OPTIONS,
	DEFAULT_COMPANION_PREFERENCES,
	enqueuePreferenceSave,
	preferencesToStoreEntries,
	sanitizeCompanionPreferences,
	shouldRestoreFailedPreferenceUpdate,
} from "../src/application/preferences";

describe("companion preferences", () => {
	it("defaults to terminal-dark and system-mono", () => {
		// Given no stored preference values
		// When the default preference contract is read
		// Then the terminal HUD defaults are used
		expect(DEFAULT_COMPANION_PREFERENCES).toEqual({
			font: "system-mono",
			theme: "terminal-dark",
		});
	});

	it("sanitizes invalid stored font and theme values to defaults", () => {
		// Given corrupted persisted preference values
		const stored = { font: "comic-sans", theme: "rainbow" };

		// When preferences are sanitized at the store boundary
		const result = sanitizeCompanionPreferences(stored);

		// Then defaults are applied and sanitization is reported
		expect(result).toEqual({
			preferences: DEFAULT_COMPANION_PREFERENCES,
			sanitized: true,
		});
	});

	it("exposes only fixed-width font choices", () => {
		// Given the font option list used by the settings panel
		// When option CSS stacks are inspected
		// Then each stack ends in a monospace fallback and no arbitrary font input is present
		expect(COMPANION_FONT_OPTIONS.map((option) => option.value)).toEqual([
			"system-mono",
			"sf-mono",
			"menlo",
			"monaco",
			"jetbrains-mono",
		]);
		expect(
			COMPANION_FONT_OPTIONS.every((option) =>
				option.cssFamily.endsWith("monospace"),
			),
		).toBe(true);
	});

	it("exposes the four resolved theme presets", () => {
		// Given the theme option list used by the settings panel
		// When option values are read
		// Then the fixed preset contract is preserved
		expect(COMPANION_THEME_OPTIONS.map((option) => option.value)).toEqual([
			"terminal-dark",
			"amber-crt",
			"green-mono",
			"high-contrast",
		]);
	});

	it("restores a failed optimistic preference update only when no newer update won", () => {
		// Given one failed optimistic update and a later successful update
		const failedAttempt = { font: "menlo", theme: "terminal-dark" } as const;
		const newerCurrent = { font: "menlo", theme: "green-mono" } as const;

		// When deciding whether the failed request may roll back local state
		const staleRollbackAllowed = shouldRestoreFailedPreferenceUpdate(
			newerCurrent,
			failedAttempt,
		);
		const currentRollbackAllowed = shouldRestoreFailedPreferenceUpdate(
			failedAttempt,
			failedAttempt,
		);

		// Then only the still-current failed attempt can restore the previous state
		expect(staleRollbackAllowed).toBe(false);
		expect(currentRollbackAllowed).toBe(true);
	});

	it("runs preference saves sequentially so the latest write lands last", async () => {
		// Given two preference writes where the first write is still pending
		const writes: string[] = [];
		let releaseFirstWrite: (() => void) | undefined;
		const firstWrite = new Promise<void>((resolve) => {
			releaseFirstWrite = resolve;
		});
		let saveQueue = Promise.resolve();

		// When a newer write is enqueued before the first write resolves
		saveQueue = enqueuePreferenceSave(saveQueue, async () => {
			writes.push("font");
			await firstWrite;
		});
		saveQueue = enqueuePreferenceSave(saveQueue, async () => {
			writes.push("theme");
		});
		await Promise.resolve();
		await Promise.resolve();

		// Then the newer write waits and lands after the older write
		expect(writes).toEqual(["font"]);
		assert.ok(releaseFirstWrite, "releaseFirstWrite must be initialized");
		releaseFirstWrite();
		await saveQueue;
		expect(writes).toEqual(["font", "theme"]);
	});

	it("serializes only font and theme store keys", () => {
		// Given a sanitized preference pair
		// When the pair is converted for persistence
		const entries = preferencesToStoreEntries({
			font: "menlo",
			theme: "green-mono",
		});

		// Then launch-at-login and other app state are excluded from the store contract
		expect(entries).toEqual({ font: "menlo", theme: "green-mono" });
		expect(Object.keys(entries)).toEqual(["font", "theme"]);
	});
});
