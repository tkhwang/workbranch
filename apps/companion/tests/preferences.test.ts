import assert from "node:assert/strict";
import { load } from "@tauri-apps/plugin-store";
import { describe, expect, it, vi } from "vitest";
import {
	DEFAULT_IDE_WINDOW,
	type IdeWindowConfig,
	sameIdeWindowConfig,
	sanitizeIdeWindowConfig,
} from "../src/application/ideWindow";
import {
	DEFAULT_MENU_BAR,
	type MenuBarConfig,
} from "../src/application/menuBar";
import {
	COMPANION_FONT_OPTIONS,
	COMPANION_FONT_SIZE_OPTIONS,
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
import {
	DEFAULT_SCREENSAVER,
	type ScreensaverConfig,
	sameScreensaverConfig,
	sanitizeScreensaverConfig,
} from "../src/application/screensaver";

const CUSTOM_MENU_BAR: MenuBarConfig = {
	claude5h: false,
	claudeWeekly: true,
	codexWeekly: true,
	todayTokens: false,
	percent: "remaining",
};

const CUSTOM_SCREENSAVER: ScreensaverConfig = {
	enabled: true,
	showMessages: true,
};

const CUSTOM_IDE_WINDOW: IdeWindowConfig = {
	enabled: true,
};

vi.mock("@tauri-apps/plugin-store", () => ({ load: vi.fn() }));

describe("companion preferences", () => {
	it("defaults to the Claude Code theme with medium system-mono", () => {
		expect(DEFAULT_COMPANION_PREFERENCES).toEqual({
			font: "system-mono",
			fontSize: "medium",
			theme: "claude",
			menuBar: DEFAULT_MENU_BAR,
			screensaver: DEFAULT_SCREENSAVER,
			ideWindow: DEFAULT_IDE_WINDOW,
		});
	});

	it("sanitizes invalid stored values to the fixed-dark defaults", () => {
		expect(
			sanitizeCompanionPreferences({
				font: "comic-sans",
				fontSize: "gigantic",
				theme: "rainbow",
				menuBar: { claude5h: "yes", percent: "left" },
				screensaver: { enabled: "yes" },
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
			preferences: {
				font: "menlo",
				fontSize: "medium",
				theme: "claude",
				menuBar: DEFAULT_MENU_BAR,
				screensaver: DEFAULT_SCREENSAVER,
				ideWindow: DEFAULT_IDE_WINDOW,
			},
			sanitized: true,
		});
	});

	it("backfills medium on stores written before Text Size existed", () => {
		expect(
			sanitizeCompanionPreferences({ font: "menlo", theme: "codex" }),
		).toEqual({
			preferences: {
				font: "menlo",
				fontSize: "medium",
				theme: "codex",
				menuBar: DEFAULT_MENU_BAR,
				screensaver: DEFAULT_SCREENSAVER,
				ideWindow: DEFAULT_IDE_WINDOW,
			},
			sanitized: true,
		});
	});

	it("backfills every menu bar item on stores written before Menu Bar existed", () => {
		expect(
			sanitizeCompanionPreferences({
				font: "menlo",
				fontSize: "large",
				theme: "codex",
			}),
		).toEqual({
			preferences: {
				font: "menlo",
				fontSize: "large",
				theme: "codex",
				menuBar: DEFAULT_MENU_BAR,
				screensaver: DEFAULT_SCREENSAVER,
				ideWindow: DEFAULT_IDE_WINDOW,
			},
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
			expect(
				sanitizeCompanionPreferences({
					font: "monaco",
					fontSize: "medium",
					theme,
				}),
			).toEqual({
				preferences: {
					font: "monaco",
					fontSize: "medium",
					theme: "claude",
					menuBar: DEFAULT_MENU_BAR,
					screensaver: DEFAULT_SCREENSAVER,
					ideWindow: DEFAULT_IDE_WINDOW,
				},
				sanitized: true,
			});
		}
	});

	it("preserves a valid Codex theme and menu bar config without sanitization", () => {
		expect(
			sanitizeCompanionPreferences({
				font: "menlo",
				fontSize: "large",
				theme: "codex",
				menuBar: CUSTOM_MENU_BAR,
				screensaver: CUSTOM_SCREENSAVER,
				ideWindow: CUSTOM_IDE_WINDOW,
			}),
		).toEqual({
			preferences: {
				font: "menlo",
				fontSize: "large",
				theme: "codex",
				menuBar: CUSTOM_MENU_BAR,
				screensaver: CUSTOM_SCREENSAVER,
				ideWindow: CUSTOM_IDE_WINDOW,
			},
			sanitized: false,
		});
	});

	it("exposes four text sizes ordered from smallest to largest", () => {
		expect(COMPANION_FONT_SIZE_OPTIONS).toEqual([
			{ value: "small", label: "Small" },
			{ value: "medium", label: "Medium" },
			{ value: "large", label: "Large" },
			{ value: "extra-large", label: "Extra Large" },
		]);
		expect(DEFAULT_COMPANION_PREFERENCES.fontSize).toBe("medium");
	});

	it("defaults the menu bar to every item as used percent", () => {
		expect(DEFAULT_COMPANION_PREFERENCES.menuBar).toEqual({
			claude5h: true,
			claudeWeekly: true,
			codexWeekly: true,
			todayTokens: true,
			percent: "used",
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
		const failedAttempt = {
			font: "menlo",
			fontSize: "medium",
			theme: "claude",
			menuBar: DEFAULT_MENU_BAR,
			screensaver: DEFAULT_SCREENSAVER,
			ideWindow: DEFAULT_IDE_WINDOW,
		} as const;
		const newerCurrent = { ...failedAttempt, theme: "codex" } as const;
		const newerSize = { ...failedAttempt, fontSize: "large" } as const;
		const newerMenuBar = {
			...failedAttempt,
			menuBar: CUSTOM_MENU_BAR,
		} as const;
		const newerScreensaver = {
			...failedAttempt,
			screensaver: CUSTOM_SCREENSAVER,
		} as const;
		const newerIdeWindow = {
			...failedAttempt,
			ideWindow: CUSTOM_IDE_WINDOW,
		} as const;

		expect(
			shouldRestoreFailedPreferenceUpdate(newerCurrent, failedAttempt),
		).toBe(false);
		expect(shouldRestoreFailedPreferenceUpdate(newerSize, failedAttempt)).toBe(
			false,
		);
		expect(
			shouldRestoreFailedPreferenceUpdate(newerMenuBar, failedAttempt),
		).toBe(false);
		expect(
			shouldRestoreFailedPreferenceUpdate(newerScreensaver, failedAttempt),
		).toBe(false);
		expect(
			shouldRestoreFailedPreferenceUpdate(newerIdeWindow, failedAttempt),
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

	it("serializes only font, fontSize, theme, menuBar, screensaver, and ideWindow store keys", () => {
		const entries = preferencesToStoreEntries({
			font: "menlo",
			fontSize: "large",
			theme: "codex",
			menuBar: CUSTOM_MENU_BAR,
			screensaver: CUSTOM_SCREENSAVER,
			ideWindow: CUSTOM_IDE_WINDOW,
		});

		expect(entries).toEqual({
			font: "menlo",
			fontSize: "large",
			theme: "codex",
			menuBar: CUSTOM_MENU_BAR,
			screensaver: CUSTOM_SCREENSAVER,
			ideWindow: CUSTOM_IDE_WINDOW,
		});
		expect(Object.keys(entries)).toEqual([
			"font",
			"fontSize",
			"theme",
			"menuBar",
			"screensaver",
			"ideWindow",
		]);
	});

	it("writes every preference key to the preference store", async () => {
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
			fontSize: "extra-large",
			theme: "claude",
			menuBar: CUSTOM_MENU_BAR,
			screensaver: CUSTOM_SCREENSAVER,
			ideWindow: CUSTOM_IDE_WINDOW,
		});

		expect(writes).toEqual([
			["font", "sf-mono"],
			["fontSize", "extra-large"],
			["theme", "claude"],
			["menuBar", CUSTOM_MENU_BAR],
			["screensaver", CUSTOM_SCREENSAVER],
			["ideWindow", CUSTOM_IDE_WINDOW],
		]);
		expect(saveCount).toBe(1);
	});
});

describe("screensaver preference", () => {
	it("defaults to off", () => {
		expect(DEFAULT_SCREENSAVER).toEqual({
			enabled: false,
			showMessages: false,
		});
		expect(DEFAULT_COMPANION_PREFERENCES.screensaver).toEqual(
			DEFAULT_SCREENSAVER,
		);
	});

	it("backfills the default on stores written before the screensaver existed", () => {
		expect(sanitizeScreensaverConfig(undefined)).toEqual({
			config: DEFAULT_SCREENSAVER,
			sanitized: true,
		});
	});

	it("keeps a valid config untouched", () => {
		expect(sanitizeScreensaverConfig(CUSTOM_SCREENSAVER)).toEqual({
			config: CUSTOM_SCREENSAVER,
			sanitized: false,
		});
	});

	it("keeps the switch and drops the idle minutes of older stores", () => {
		expect(
			sanitizeScreensaverConfig({
				enabled: true,
				showMessages: false,
				idleMinutes: 12,
			}),
		).toEqual({
			config: { enabled: true, showMessages: false },
			sanitized: true,
		});
	});

	it("hides messages on stores written before the switch existed", () => {
		expect(sanitizeScreensaverConfig({ enabled: true })).toEqual({
			config: { enabled: true, showMessages: false },
			sanitized: true,
		});
	});

	it("falls back to off for an unusable switch", () => {
		expect(
			sanitizeScreensaverConfig({ enabled: "yes", showMessages: 1 }),
		).toEqual({
			config: { enabled: false, showMessages: false },
			sanitized: true,
		});
		expect(sanitizeScreensaverConfig("on").config).toEqual(DEFAULT_SCREENSAVER);
	});

	it("compares configs by value", () => {
		expect(
			sameScreensaverConfig(CUSTOM_SCREENSAVER, { ...CUSTOM_SCREENSAVER }),
		).toBe(true);
		expect(sameScreensaverConfig(CUSTOM_SCREENSAVER, DEFAULT_SCREENSAVER)).toBe(
			false,
		);
		expect(
			sameScreensaverConfig(CUSTOM_SCREENSAVER, {
				...CUSTOM_SCREENSAVER,
				showMessages: false,
			}),
		).toBe(false);
	});
});

describe("IDE window preference", () => {
	it("defaults to off", () => {
		expect(DEFAULT_IDE_WINDOW).toEqual({ enabled: false });
		expect(DEFAULT_COMPANION_PREFERENCES.ideWindow).toEqual(DEFAULT_IDE_WINDOW);
	});

	it("backfills the default on stores written before the switch existed", () => {
		expect(sanitizeIdeWindowConfig(undefined)).toEqual({
			config: DEFAULT_IDE_WINDOW,
			sanitized: true,
		});
	});

	it("keeps a valid config untouched", () => {
		expect(sanitizeIdeWindowConfig(CUSTOM_IDE_WINDOW)).toEqual({
			config: CUSTOM_IDE_WINDOW,
			sanitized: false,
		});
	});

	it("falls back to off for an unusable switch and drops unknown keys", () => {
		expect(sanitizeIdeWindowConfig({ enabled: "yes" })).toEqual({
			config: { enabled: false },
			sanitized: true,
		});
		expect(sanitizeIdeWindowConfig({ enabled: true, screen: 2 })).toEqual({
			config: { enabled: true },
			sanitized: true,
		});
	});

	it("compares configs by value", () => {
		expect(
			sameIdeWindowConfig(CUSTOM_IDE_WINDOW, { ...CUSTOM_IDE_WINDOW }),
		).toBe(true);
		expect(sameIdeWindowConfig(CUSTOM_IDE_WINDOW, DEFAULT_IDE_WINDOW)).toBe(
			false,
		);
	});
});
