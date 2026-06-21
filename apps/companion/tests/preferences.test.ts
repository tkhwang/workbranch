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
	it("defaults to Solarized with system mode and system-mono", () => {
		// Given no stored preference values
		// When the default preference contract is read
		// Then the Solarized HUD follows the OS theme until the user chooses a mode
		expect(DEFAULT_COMPANION_PREFERENCES).toEqual({
			font: "system-mono",
			themeFamily: "solarized",
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

	it("migrates a legacy concrete theme value into family and mode preferences", () => {
		// Given a previous settings file stored one concrete dark/light theme value
		const stored = { font: "menlo", theme: "nord-light" };

		// When preferences are sanitized at the store boundary
		const result = sanitizeCompanionPreferences(stored);

		// Then the legacy value is preserved as the new family and mode pair
		expect(result).toEqual({
			preferences: {
				font: "menlo",
				themeFamily: "solarized",
				themeMode: "light",
			},
			sanitized: true,
		});
	});

	it("migrates previous theme enum values before falling back to defaults", () => {
		// Given settings files stored the original companion theme enum values
		const migrations = [
			{
				theme: "terminal-dark",
				themeFamily: "github",
			},
			{
				theme: "amber-crt",
				themeFamily: "dracula",
			},
			{
				theme: "green-mono",
				themeFamily: "solarized",
			},
			{
				theme: "high-contrast",
				themeFamily: "github",
			},
		] as const;

		for (const migration of migrations) {
			// When preferences are sanitized at the store boundary
			const result = sanitizeCompanionPreferences({
				font: "monaco",
				theme: migration.theme,
			});

			// Then the user's prior theme choice is preserved as a dark family choice
			expect(result).toEqual({
				preferences: {
					font: "monaco",
					themeFamily: migration.themeFamily,
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
		// Then removed families migrate to nearest surviving families and preserve mode
		expect(gruvboxResult).toEqual({
			preferences: {
				font: "sf-mono",
				themeFamily: "dracula",
				themeMode: "dark",
			},
			sanitized: true,
		});
		expect(nordResult).toEqual({
			preferences: {
				font: "sf-mono",
				themeFamily: "solarized",
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

	it("exposes four famous theme families in dark and light variants", () => {
		// Given the theme option list used by the settings panel
		// When option values are read
		// Then each famous family has both dark and light variants
		expect(COMPANION_THEME_OPTIONS.map((option) => option.value)).toEqual([
			"solarized-dark",
			"dracula-dark",
			"catppuccin-dark",
			"github-dark",
			"solarized-light",
			"dracula-light",
			"catppuccin-light",
			"github-light",
		]);
		expect(COMPANION_THEME_OPTIONS.map((option) => option.family)).toContain(
			"dracula",
		);
		expect(
			COMPANION_THEME_OPTIONS.map((option) => option.family),
		).not.toContain("gruvbox");
		expect(
			COMPANION_THEME_OPTIONS.map((option) => option.family),
		).not.toContain("nord");
		expect(
			COMPANION_THEME_OPTIONS.filter((option) => option.mode === "dark"),
		).toHaveLength(4);
		expect(
			COMPANION_THEME_OPTIONS.filter((option) => option.mode === "light"),
		).toHaveLength(4);
	});

	it("resolves system theme mode using the current OS color scheme", () => {
		// Given preferences in explicit and system modes
		const explicitLight = {
			font: "system-mono",
			themeFamily: "dracula",
			themeMode: "light",
		} as const;
		const systemGitHub = {
			font: "system-mono",
			themeFamily: "github",
			themeMode: "system",
		} as const;

		// When concrete data-theme values are resolved
		// Then system mode follows the supplied system mode while explicit mode wins
		expect(resolvedCompanionTheme(explicitLight, "dark")).toBe("dracula-light");
		expect(resolvedCompanionTheme(systemGitHub, "light")).toBe("github-light");
		expect(resolvedCompanionTheme(systemGitHub, "dark")).toBe("github-dark");
	});

	it("restores a failed optimistic preference update only when no newer update won", () => {
		// Given one failed optimistic update and a later successful update
		const failedAttempt = {
			font: "menlo",
			themeFamily: "catppuccin",
			themeMode: "system",
		} as const;
		const newerCurrent = {
			font: "menlo",
			themeFamily: "github",
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
			themeFamily: "github",
			themeMode: "light",
		});

		// Then launch-at-login and other app state are excluded from the store contract
		expect(entries).toEqual({
			font: "menlo",
			themeFamily: "github",
			themeMode: "light",
		});
		expect(Object.keys(entries)).toEqual(["font", "themeFamily", "themeMode"]);
	});
});
