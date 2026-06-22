import { load } from "@tauri-apps/plugin-store";
import {
	COMPANION_THEME_MODE_OPTIONS,
	COMPANION_THEME_OPTIONS,
	type CompanionResolvedThemeMode,
	type CompanionTheme,
	type CompanionThemeFamily,
	type CompanionThemeMode,
	isCompanionThemeFamily,
	isCompanionThemeMode,
	isLegacyCompanionTheme,
	resolvedThemeValue,
	themeFamilyFromLegacyTheme,
	themeModeFromLegacyTheme,
} from "./themePreferences";

export type {
	CompanionResolvedThemeMode,
	CompanionTheme,
	CompanionThemeFamily,
	CompanionThemeMode,
	CompanionThemeModeOption,
	CompanionThemeOption,
} from "./themePreferences";
export {
	COMPANION_THEME_MODE_OPTIONS,
	COMPANION_THEME_OPTIONS,
	resolvedThemeValue,
};

export const COMPANION_PREFERENCES_STORE_FILE = "companion-preferences.json";

const COMPANION_FONT_VALUES = [
	"system-mono",
	"sf-mono",
	"menlo",
	"monaco",
	"jetbrains-mono",
] as const;

export type CompanionFont = (typeof COMPANION_FONT_VALUES)[number];

export type CompanionPreferences = {
	readonly font: CompanionFont;
	readonly themeFamily: CompanionThemeFamily;
	readonly themeMode: CompanionThemeMode;
};

export type CompanionFontOption = {
	readonly value: CompanionFont;
	readonly label: string;
	readonly cssFamily: string;
};

export type PreferenceSanitizationResult = {
	readonly preferences: CompanionPreferences;
	readonly sanitized: boolean;
};

export type PreferenceStoreEntries = {
	readonly font: CompanionFont;
	readonly themeFamily: CompanionThemeFamily;
	readonly themeMode: CompanionThemeMode;
};

export type CompanionPreferenceStore = {
	readonly get: <T>(key: string) => Promise<T | undefined>;
	readonly set: (key: string, value: unknown) => Promise<void>;
	readonly save: () => Promise<void>;
};

export const DEFAULT_COMPANION_PREFERENCES: CompanionPreferences = {
	font: "system-mono",
	themeFamily: "companion",
	themeMode: "system",
};

export const COMPANION_FONT_OPTIONS: readonly CompanionFontOption[] = [
	{
		value: "system-mono",
		label: "System Mono",
		cssFamily:
			'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace',
	},
	{
		value: "sf-mono",
		label: "SF Mono",
		cssFamily:
			"SFMono-Regular, ui-monospace, Menlo, Monaco, Consolas, monospace",
	},
	{
		value: "menlo",
		label: "Menlo",
		cssFamily: "Menlo, ui-monospace, Monaco, Consolas, monospace",
	},
	{
		value: "monaco",
		label: "Monaco",
		cssFamily: "Monaco, ui-monospace, Menlo, Consolas, monospace",
	},
	{
		value: "jetbrains-mono",
		label: "JetBrains Mono",
		cssFamily:
			'"JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
	},
];

export function isCompanionFont(value: unknown): value is CompanionFont {
	switch (value) {
		case "system-mono":
		case "sf-mono":
		case "menlo":
		case "monaco":
		case "jetbrains-mono":
			return true;
		default:
			return false;
	}
}

function migrateRemovedThemeFamily(
	value: unknown,
): CompanionThemeFamily | undefined {
	switch (value) {
		case "breakfast":
		case "solarized":
		case "dracula":
		case "catppuccin":
		case "github":
		case "gruvbox":
		case "nord":
			return "companion";
		default:
			return undefined;
	}
}

export function sanitizeCompanionPreferences(input: {
	readonly font?: unknown;
	readonly themeFamily?: unknown;
	readonly themeMode?: unknown;
	readonly theme?: unknown;
}): PreferenceSanitizationResult {
	const font = isCompanionFont(input.font)
		? input.font
		: DEFAULT_COMPANION_PREFERENCES.font;
	const legacyTheme = isLegacyCompanionTheme(input.theme)
		? input.theme
		: undefined;
	const removedThemeFamily = migrateRemovedThemeFamily(input.themeFamily);
	const themeFamily = isCompanionThemeFamily(input.themeFamily)
		? input.themeFamily
		: removedThemeFamily
			? removedThemeFamily
			: legacyTheme
				? themeFamilyFromLegacyTheme(legacyTheme)
				: DEFAULT_COMPANION_PREFERENCES.themeFamily;
	const themeMode = isCompanionThemeMode(input.themeMode)
		? input.themeMode
		: legacyTheme
			? themeModeFromLegacyTheme(legacyTheme)
			: DEFAULT_COMPANION_PREFERENCES.themeMode;
	return {
		preferences: { font, themeFamily, themeMode },
		sanitized:
			font !== input.font ||
			themeFamily !== input.themeFamily ||
			themeMode !== input.themeMode,
	};
}

export function shouldRestoreFailedPreferenceUpdate(
	current: CompanionPreferences,
	attempted: CompanionPreferences,
): boolean {
	return (
		current.font === attempted.font &&
		current.themeFamily === attempted.themeFamily &&
		current.themeMode === attempted.themeMode
	);
}

export type PreferenceSaveOperation = () => Promise<void>;

export function enqueuePreferenceSave(
	currentQueue: Promise<void>,
	save: PreferenceSaveOperation,
): Promise<void> {
	return currentQueue.catch(() => undefined).then(save);
}

export function preferencesToStoreEntries(
	preferences: CompanionPreferences,
): PreferenceStoreEntries {
	return {
		font: preferences.font,
		themeFamily: preferences.themeFamily,
		themeMode: preferences.themeMode,
	};
}

export async function loadCompanionPreferenceStore(): Promise<CompanionPreferenceStore> {
	return load(COMPANION_PREFERENCES_STORE_FILE, {
		autoSave: false,
		defaults: preferencesToStoreEntries(DEFAULT_COMPANION_PREFERENCES),
	});
}

export async function readCompanionPreferences(
	store: CompanionPreferenceStore,
): Promise<PreferenceSanitizationResult> {
	return sanitizeCompanionPreferences({
		font: await store.get<unknown>("font"),
		themeFamily: await store.get<unknown>("themeFamily"),
		themeMode: await store.get<unknown>("themeMode"),
		theme: await store.get<unknown>("theme"),
	});
}

export async function writeCompanionPreferences(
	store: CompanionPreferenceStore,
	preferences: CompanionPreferences,
): Promise<void> {
	const entries = preferencesToStoreEntries(preferences);
	await store.set("font", entries.font);
	await store.set("themeFamily", entries.themeFamily);
	await store.set("themeMode", entries.themeMode);
	await store.save();
}

export function resolvedCompanionTheme(
	preferences: CompanionPreferences,
	systemMode: CompanionResolvedThemeMode,
): CompanionTheme {
	const mode =
		preferences.themeMode === "system" ? systemMode : preferences.themeMode;
	return resolvedThemeValue(preferences.themeFamily, mode);
}
