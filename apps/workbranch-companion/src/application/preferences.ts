import { load } from "@tauri-apps/plugin-store";

export const COMPANION_PREFERENCES_STORE_FILE = "companion-preferences.json";

const COMPANION_FONT_VALUES = [
	"system-mono",
	"sf-mono",
	"menlo",
	"monaco",
	"jetbrains-mono",
] as const;

const COMPANION_THEME_VALUES = [
	"terminal-dark",
	"amber-crt",
	"green-mono",
	"high-contrast",
] as const;

export type CompanionFont = (typeof COMPANION_FONT_VALUES)[number];
export type CompanionTheme = (typeof COMPANION_THEME_VALUES)[number];

export type CompanionPreferences = {
	readonly font: CompanionFont;
	readonly theme: CompanionTheme;
};

export type CompanionFontOption = {
	readonly value: CompanionFont;
	readonly label: string;
	readonly cssFamily: string;
};

export type CompanionThemeOption = {
	readonly value: CompanionTheme;
	readonly label: string;
};

export type PreferenceSanitizationResult = {
	readonly preferences: CompanionPreferences;
	readonly sanitized: boolean;
};

export type PreferenceStoreEntries = {
	readonly font: CompanionFont;
	readonly theme: CompanionTheme;
};

export type CompanionPreferenceStore = {
	readonly get: <T>(key: string) => Promise<T | undefined>;
	readonly set: (key: string, value: unknown) => Promise<void>;
	readonly save: () => Promise<void>;
};

export const DEFAULT_COMPANION_PREFERENCES: CompanionPreferences = {
	font: "system-mono",
	theme: "terminal-dark",
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

export const COMPANION_THEME_OPTIONS: readonly CompanionThemeOption[] = [
	{ value: "terminal-dark", label: "Terminal Dark" },
	{ value: "amber-crt", label: "Amber CRT" },
	{ value: "green-mono", label: "Green Mono" },
	{ value: "high-contrast", label: "High Contrast" },
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

export function isCompanionTheme(value: unknown): value is CompanionTheme {
	switch (value) {
		case "terminal-dark":
		case "amber-crt":
		case "green-mono":
		case "high-contrast":
			return true;
		default:
			return false;
	}
}

export function sanitizeCompanionPreferences(input: {
	readonly font?: unknown;
	readonly theme?: unknown;
}): PreferenceSanitizationResult {
	const font = isCompanionFont(input.font)
		? input.font
		: DEFAULT_COMPANION_PREFERENCES.font;
	const theme = isCompanionTheme(input.theme)
		? input.theme
		: DEFAULT_COMPANION_PREFERENCES.theme;
	return {
		preferences: { font, theme },
		sanitized: font !== input.font || theme !== input.theme,
	};
}

export function preferencesToStoreEntries(
	preferences: CompanionPreferences,
): PreferenceStoreEntries {
	return {
		font: preferences.font,
		theme: preferences.theme,
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
		theme: await store.get<unknown>("theme"),
	});
}

export async function writeCompanionPreferences(
	store: CompanionPreferenceStore,
	preferences: CompanionPreferences,
): Promise<void> {
	const entries = preferencesToStoreEntries(preferences);
	await store.set("font", entries.font);
	await store.set("theme", entries.theme);
	await store.save();
}
