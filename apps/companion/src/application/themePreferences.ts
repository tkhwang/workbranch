const COMPANION_THEME_VALUES = [
	"dracula-dark",
	"nord-dark",
	"solarized-dark",
	"gruvbox-dark",
	"dracula-light",
	"nord-light",
	"solarized-light",
	"gruvbox-light",
] as const;

const COMPANION_THEME_FAMILY_VALUES = [
	"dracula",
	"nord",
	"solarized",
	"gruvbox",
] as const;

const COMPANION_THEME_MODE_VALUES = ["light", "dark", "system"] as const;

const COMPANION_RESOLVED_THEME_MODE_VALUES = ["light", "dark"] as const;

export type CompanionTheme = (typeof COMPANION_THEME_VALUES)[number];
export type CompanionThemeFamily =
	(typeof COMPANION_THEME_FAMILY_VALUES)[number];
export type CompanionThemeMode = (typeof COMPANION_THEME_MODE_VALUES)[number];
export type CompanionResolvedThemeMode =
	(typeof COMPANION_RESOLVED_THEME_MODE_VALUES)[number];

export type CompanionThemeOption = {
	readonly value: CompanionTheme;
	readonly family: CompanionThemeFamily;
	readonly familyLabel: string;
	readonly label: string;
	readonly mode: CompanionResolvedThemeMode;
};

export type CompanionThemeModeOption = {
	readonly value: CompanionThemeMode;
	readonly label: string;
};

const THEME_BY_FAMILY_AND_MODE: Record<
	CompanionThemeFamily,
	Record<CompanionResolvedThemeMode, CompanionTheme>
> = {
	dracula: {
		dark: "dracula-dark",
		light: "dracula-light",
	},
	nord: {
		dark: "nord-dark",
		light: "nord-light",
	},
	solarized: {
		dark: "solarized-dark",
		light: "solarized-light",
	},
	gruvbox: {
		dark: "gruvbox-dark",
		light: "gruvbox-light",
	},
};

export const COMPANION_THEME_OPTIONS: readonly CompanionThemeOption[] = [
	{
		value: "dracula-dark",
		family: "dracula",
		familyLabel: "Dracula",
		label: "Dracula Dark",
		mode: "dark",
	},
	{
		value: "nord-dark",
		family: "nord",
		familyLabel: "Nord",
		label: "Nord Dark",
		mode: "dark",
	},
	{
		value: "solarized-dark",
		family: "solarized",
		familyLabel: "Solarized",
		label: "Solarized Dark",
		mode: "dark",
	},
	{
		value: "gruvbox-dark",
		family: "gruvbox",
		familyLabel: "Gruvbox",
		label: "Gruvbox Dark",
		mode: "dark",
	},
	{
		value: "dracula-light",
		family: "dracula",
		familyLabel: "Dracula",
		label: "Dracula Light",
		mode: "light",
	},
	{
		value: "nord-light",
		family: "nord",
		familyLabel: "Nord",
		label: "Nord Light",
		mode: "light",
	},
	{
		value: "solarized-light",
		family: "solarized",
		familyLabel: "Solarized",
		label: "Solarized Light",
		mode: "light",
	},
	{
		value: "gruvbox-light",
		family: "gruvbox",
		familyLabel: "Gruvbox",
		label: "Gruvbox Light",
		mode: "light",
	},
];

export const COMPANION_THEME_MODE_OPTIONS: readonly CompanionThemeModeOption[] =
	[
		{ value: "light", label: "Light" },
		{ value: "dark", label: "Dark" },
		{ value: "system", label: "System" },
	];

export function isCompanionTheme(value: unknown): value is CompanionTheme {
	switch (value) {
		case "dracula-dark":
		case "nord-dark":
		case "solarized-dark":
		case "gruvbox-dark":
		case "dracula-light":
		case "nord-light":
		case "solarized-light":
		case "gruvbox-light":
			return true;
		default:
			return false;
	}
}

export function isCompanionThemeFamily(
	value: unknown,
): value is CompanionThemeFamily {
	switch (value) {
		case "dracula":
		case "nord":
		case "solarized":
		case "gruvbox":
			return true;
		default:
			return false;
	}
}

export function isCompanionThemeMode(
	value: unknown,
): value is CompanionThemeMode {
	switch (value) {
		case "light":
		case "dark":
		case "system":
			return true;
		default:
			return false;
	}
}

export function themeFamilyFromLegacyTheme(
	theme: CompanionTheme,
): CompanionThemeFamily {
	switch (theme) {
		case "dracula-dark":
		case "dracula-light":
			return "dracula";
		case "nord-dark":
		case "nord-light":
			return "nord";
		case "solarized-dark":
		case "solarized-light":
			return "solarized";
		case "gruvbox-dark":
		case "gruvbox-light":
			return "gruvbox";
	}
}

export function themeModeFromLegacyTheme(
	theme: CompanionTheme,
): CompanionResolvedThemeMode {
	switch (theme) {
		case "dracula-dark":
		case "nord-dark":
		case "solarized-dark":
		case "gruvbox-dark":
			return "dark";
		case "dracula-light":
		case "nord-light":
		case "solarized-light":
		case "gruvbox-light":
			return "light";
	}
}

export function resolvedThemeValue(
	family: CompanionThemeFamily,
	mode: CompanionResolvedThemeMode,
): CompanionTheme {
	return THEME_BY_FAMILY_AND_MODE[family][mode];
}
