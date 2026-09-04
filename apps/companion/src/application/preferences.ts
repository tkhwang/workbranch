import { load } from "@tauri-apps/plugin-store";
import {
	COMPANION_THEME_OPTIONS,
	type CompanionTheme,
	isCompanionTheme,
} from "./themePreferences";

export type {
	CompanionTheme,
	CompanionThemeOption,
} from "./themePreferences";
export { COMPANION_THEME_OPTIONS };

export const COMPANION_PREFERENCES_STORE_FILE = "companion-preferences.json";

const COMPANION_FONT_VALUES = [
	"system-mono",
	"sf-mono",
	"menlo",
	"monaco",
	"jetbrains-mono",
] as const;

export type CompanionFont = (typeof COMPANION_FONT_VALUES)[number];

const COMPANION_FONT_SIZE_VALUES = [
	"small",
	"medium",
	"large",
	"extra-large",
] as const;

export type CompanionFontSize = (typeof COMPANION_FONT_SIZE_VALUES)[number];

export type CompanionPreferences = {
	readonly font: CompanionFont;
	readonly fontSize: CompanionFontSize;
	readonly theme: CompanionTheme;
};

export type CompanionFontOption = {
	readonly value: CompanionFont;
	readonly label: string;
	readonly cssFamily: string;
};

export type CompanionFontSizeOption = {
	readonly value: CompanionFontSize;
	readonly label: string;
};

export type PreferenceSanitizationResult = {
	readonly preferences: CompanionPreferences;
	readonly sanitized: boolean;
};

export type PreferenceStoreEntries = {
	readonly font: CompanionFont;
	readonly fontSize: CompanionFontSize;
	readonly theme: CompanionTheme;
};

export type CompanionPreferenceStore = {
	readonly get: <T>(key: string) => Promise<T | undefined>;
	readonly set: (key: string, value: unknown) => Promise<void>;
	readonly save: () => Promise<void>;
};

export const DEFAULT_COMPANION_PREFERENCES: CompanionPreferences = {
	font: "system-mono",
	fontSize: "medium",
	theme: "claude",
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

// Each value drives main[data-font-size="..."] in styles/themes.css, which
// owns the matching --font-scale step.
export const COMPANION_FONT_SIZE_OPTIONS: readonly CompanionFontSizeOption[] = [
	{ value: "small", label: "Small" },
	{ value: "medium", label: "Medium" },
	{ value: "large", label: "Large" },
	{ value: "extra-large", label: "Extra Large" },
];

export function isCompanionFontSize(
	value: unknown,
): value is CompanionFontSize {
	switch (value) {
		case "small":
		case "medium":
		case "large":
		case "extra-large":
			return true;
		default:
			return false;
	}
}

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

export function sanitizeCompanionPreferences(input: {
	readonly font?: unknown;
	readonly fontSize?: unknown;
	readonly theme?: unknown;
	readonly themeFamily?: unknown;
	readonly themeMode?: unknown;
}): PreferenceSanitizationResult {
	const font = isCompanionFont(input.font)
		? input.font
		: DEFAULT_COMPANION_PREFERENCES.font;
	const fontSize = isCompanionFontSize(input.fontSize)
		? input.fontSize
		: DEFAULT_COMPANION_PREFERENCES.fontSize;
	const theme = isCompanionTheme(input.theme)
		? input.theme
		: isCompanionTheme(input.themeFamily)
			? input.themeFamily
			: DEFAULT_COMPANION_PREFERENCES.theme;
	return {
		preferences: { font, fontSize, theme },
		sanitized:
			font !== input.font ||
			fontSize !== input.fontSize ||
			theme !== input.theme,
	};
}

export function shouldRestoreFailedPreferenceUpdate(
	current: CompanionPreferences,
	attempted: CompanionPreferences,
): boolean {
	return (
		current.font === attempted.font &&
		current.fontSize === attempted.fontSize &&
		current.theme === attempted.theme
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
		fontSize: preferences.fontSize,
		theme: preferences.theme,
	};
}

export async function loadCompanionPreferenceStore(): Promise<CompanionPreferenceStore> {
	return load(COMPANION_PREFERENCES_STORE_FILE, {
		autoSave: false,
		defaults: {},
	});
}

export async function readCompanionPreferences(
	store: CompanionPreferenceStore,
): Promise<PreferenceSanitizationResult> {
	return sanitizeCompanionPreferences({
		font: await store.get<unknown>("font"),
		fontSize: await store.get<unknown>("fontSize"),
		theme: await store.get<unknown>("theme"),
		themeFamily: await store.get<unknown>("themeFamily"),
		themeMode: await store.get<unknown>("themeMode"),
	});
}

export async function writeCompanionPreferences(
	store: CompanionPreferenceStore,
	preferences: CompanionPreferences,
): Promise<void> {
	const entries = preferencesToStoreEntries(preferences);
	await store.set("font", entries.font);
	await store.set("fontSize", entries.fontSize);
	await store.set("theme", entries.theme);
	await store.save();
}
