import assert from "node:assert/strict";
import { load } from "@tauri-apps/plugin-store";
import { describe, expect, it, vi } from "vitest";
import {
	COMPANION_FONT_OPTIONS,
	COMPANION_PREFERENCES_STORE_FILE,
	COMPANION_THEME_OPTIONS,
	type CompanionPreferenceStore,
	DEFAULT_COMPANION_PREFERENCES,
	enqueuePreferenceSave,
	loadCompanionPreferenceStore,
	preferencesToStoreEntries,
	sanitizeCompanionPreferences,
	shouldRestoreFailedPreferenceUpdate,
	writeCompanionPreferences,
} from "../src/application/preferences";

vi.mock("@tauri-apps/plugin-store", () => ({ load: vi.fn() }));

describe("companion preferences", () => {
	it("defaults to the Claude Code theme with system-mono", () => {
		expect(DEFAULT_COMPANION_PREFERENCES).toEqual({
			font: "system-mono",
			theme: "claude",
		});
	});

	it("sanitizes invalid stored values to the fixed-dark defaults", () => {
		expect(
			sanitizeCompanionPreferences({
				font: "comic-sans",
				theme: "rainbow",
			}),
		).toEqual({
			preferences: DEFAULT_COMPANION_PREFERENCES,
			sanitized: true,
		});
	});

	it("migrates legacy appearance fields to Claude Code", () => {
		expect(
			sanitizeCompanionPreferences({
				font: "menlo",
				themeFamily: "companion",
				themeMode: "light",
			}),
		).toEqual({
			preferences: { font: "menlo", theme: "claude" },
			sanitized: true,
		});
	});

	it("loads raw stored values so missing theme keys trigger migration", async () => {
		await loadCompanionPreferenceStore();

		expect(load).toHaveBeenCalledWith(COMPANION_PREFERENCES_STORE_FILE, {
			autoSave: false,
			defaults: {},
		});
	});

	it("migrates every former concrete theme to Claude Code", () => {
		const legacyThemes = [
			"terminal-dark",
			"amber-crt",
			"nord-light",
			"catppuccin-dark",
			"breakfast-light",
		] as const;

		for (const theme of legacyThemes) {
			expect(sanitizeCompanionPreferences({ font: "monaco", theme })).toEqual({
				preferences: { font: "monaco", theme: "claude" },
				sanitized: true,
			});
		}
	});

	it("preserves a valid Codex theme without sanitization", () => {
		expect(
			sanitizeCompanionPreferences({ font: "menlo", theme: "codex" }),
		).toEqual({
			preferences: { font: "menlo", theme: "codex" },
			sanitized: false,
		});
	});

	it("exposes only Claude Code and Codex themes", () => {
		expect(COMPANION_THEME_OPTIONS).toEqual([
			{ value: "claude", label: "Claude Code" },
			{ value: "codex", label: "Codex" },
		]);
	});

	it("exposes only fixed-width font choices", () => {
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

	it("restores a failed optimistic update only while it is current", () => {
		const failedAttempt = { font: "menlo", theme: "claude" } as const;
		const newerCurrent = { font: "menlo", theme: "codex" } as const;

		expect(
			shouldRestoreFailedPreferenceUpdate(newerCurrent, failedAttempt),
		).toBe(false);
		expect(
			shouldRestoreFailedPreferenceUpdate(failedAttempt, failedAttempt),
		).toBe(true);
	});

	it("runs preference saves sequentially so the latest write lands last", async () => {
		const writes: string[] = [];
		let releaseFirstWrite: (() => void) | undefined;
		const firstWrite = new Promise<void>((resolve) => {
			releaseFirstWrite = resolve;
		});
		let saveQueue = Promise.resolve();

		saveQueue = enqueuePreferenceSave(saveQueue, async () => {
			writes.push("font");
			await firstWrite;
		});
		saveQueue = enqueuePreferenceSave(saveQueue, async () => {
			writes.push("theme");
		});
		await Promise.resolve();
		await Promise.resolve();

		expect(writes).toEqual(["font"]);
		assert.ok(releaseFirstWrite, "releaseFirstWrite must be initialized");
		releaseFirstWrite();
		await saveQueue;
		expect(writes).toEqual(["font", "theme"]);
	});

	it("serializes only font and theme store keys", () => {
		const entries = preferencesToStoreEntries({
			font: "menlo",
			theme: "codex",
		});

		expect(entries).toEqual({ font: "menlo", theme: "codex" });
		expect(Object.keys(entries)).toEqual(["font", "theme"]);
	});

	it("writes only font and theme to the preference store", async () => {
		const writes: Array<readonly [string, unknown]> = [];
		let saveCount = 0;
		const store: CompanionPreferenceStore = {
			get: async <T>(_key: string): Promise<T | undefined> => undefined,
			set: async (key, value) => {
				writes.push([key, value]);
			},
			save: async () => {
				saveCount += 1;
			},
		};

		await writeCompanionPreferences(store, {
			font: "sf-mono",
			theme: "claude",
		});

		expect(writes).toEqual([
			["font", "sf-mono"],
			["theme", "claude"],
		]);
		expect(saveCount).toBe(1);
	});
});
