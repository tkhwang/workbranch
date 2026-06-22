import assert from "node:assert/strict";
import { describe, expect, it } from "vitest";
import {
	COMPANION_FONT_OPTIONS,
	COMPANION_THEME_OPTIONS,
	DEFAULT_COMPANION_PREFERENCES,
	enqueuePreferenceSave,
	preferencesToStoreEntries,
	resolvedCompanionTheme,
	sanitizeCompanionPreferences,
	shouldRestoreFailedPreferenceUpdate,
} from "../src/application/preferences";

describe("companion preferences", () => {
	it("defaults to the Companion palette with system mode and system-mono", () => {
		// Given no stored preference values
		// When the default preference contract is read
		// Then the HUD follows the OS theme with one curated palette
		expect(DEFAULT_COMPANION_PREFERENCES).toEqual({
			font: "system-mono",
			themeFamily: "companion",
			themeMode: "system",
		});
	});

	it("sanitizes invalid stored font, theme family, and theme mode values to defaults", () => {
		// Given corrupted persisted preference values
		const stored = {
			font: "comic-sans",
			themeFamily: "rainbow",
			themeMode: "sepia",
		};

		// When preferences are sanitized at the store boundary
		const result = sanitizeCompanionPreferences(stored);

		// Then defaults are applied and sanitization is reported
		expect(result).toEqual({
			preferences: DEFAULT_COMPANION_PREFERENCES,
			sanitized: true,
		});
	});

	it("migrates a legacy concrete theme value into Companion family and mode preferences", () => {
		// Given a previous settings file stored one concrete dark/light theme value
		const stored = { font: "menlo", theme: "nord-light" };

		// When preferences are sanitized at the store boundary
		const result = sanitizeCompanionPreferences(stored);

		// Then the legacy color family collapses to Companion while preserving mode
		expect(result).toEqual({
			preferences: {
				font: "menlo",
				themeFamily: "companion",
				themeMode: "light",
			},
			sanitized: true,
		});
	});

	it("migrates previous theme enum values before falling back to defaults", () => {
		// Given settings files stored earlier companion theme enum values
		const migrations = [
			"terminal-dark",
			"amber-crt",
			"green-mono",
			"high-contrast",
		] as const;

		for (const theme of migrations) {
			// When preferences are sanitized at the store boundary
			const result = sanitizeCompanionPreferences({
				font: "monaco",
				theme,
			});

			// Then previous dark choices converge to the Companion dark palette
			expect(result).toEqual({
				preferences: {
					font: "monaco",
					themeFamily: "companion",
					themeMode: "dark",
				},
				sanitized: true,
			});
		}
	});

	it("migrates removed stored theme families before falling back to defaults", () => {
		// Given stored family values from removed themes
		const gruvboxResult = sanitizeCompanionPreferences({
			font: "sf-mono",
			themeFamily: "gruvbox",
			themeMode: "dark",
		});
		const nordResult = sanitizeCompanionPreferences({
			font: "sf-mono",
			themeFamily: "nord",
			themeMode: "light",
		});

		// When preferences are sanitized at the store boundary
		// Then removed families collapse to Companion and preserve mode
		expect(gruvboxResult).toEqual({
			preferences: {
				font: "sf-mono",
				themeFamily: "companion",
				themeMode: "dark",
			},
			sanitized: true,
		});
		expect(nordResult).toEqual({
			preferences: {
				font: "sf-mono",
				themeFamily: "companion",
				themeMode: "light",
			},
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

	it("exposes only Catppuccin Dark and White Light theme variants", () => {
		// Given the active theme option list
		// When option values are read
		// Then Settings has one curated dark/light palette instead of multiple families
		expect(COMPANION_THEME_OPTIONS).toEqual([
			{
				value: "catppuccin-dark",
				family: "companion",
				familyLabel: "Companion",
				label: "Catppuccin Dark",
				mode: "dark",
			},
			{
				value: "breakfast-light",
				family: "companion",
				familyLabel: "Companion",
				label: "White Light",
				mode: "light",
			},
		]);
	});

	it("resolves system theme mode using the current OS color scheme", () => {
		// Given preferences in explicit and system modes
		const explicitLight = {
			font: "system-mono",
			themeFamily: "companion",
			themeMode: "light",
		} as const;
		const systemCompanion = {
			font: "system-mono",
			themeFamily: "companion",
			themeMode: "system",
		} as const;

		// When concrete data-theme values are resolved
		// Then system mode follows the supplied system mode while explicit mode wins
		expect(resolvedCompanionTheme(explicitLight, "dark")).toBe(
			"breakfast-light",
		);
		expect(resolvedCompanionTheme(systemCompanion, "light")).toBe(
			"breakfast-light",
		);
		expect(resolvedCompanionTheme(systemCompanion, "dark")).toBe(
			"catppuccin-dark",
		);
	});

	it("restores a failed optimistic preference update only when no newer update won", () => {
		// Given one failed optimistic update and a later successful update
		const failedAttempt = {
			font: "menlo",
			themeFamily: "companion",
			themeMode: "system",
		} as const;
		const newerCurrent = {
			font: "menlo",
			themeFamily: "companion",
			themeMode: "light",
		} as const;

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

	it("serializes only font, theme family, and theme mode store keys", () => {
		// Given a sanitized preference pair
		// When the pair is converted for persistence
		const entries = preferencesToStoreEntries({
			font: "menlo",
			themeFamily: "companion",
			themeMode: "light",
		});

		// Then launch-at-login and other app state are excluded from the store contract
		expect(entries).toEqual({
			font: "menlo",
			themeFamily: "companion",
			themeMode: "light",
		});
		expect(Object.keys(entries)).toEqual(["font", "themeFamily", "themeMode"]);
	});
});
