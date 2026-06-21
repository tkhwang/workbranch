const COMPANION_THEME_VALUES = [
	"solarized-dark",
	"dracula-dark",
	"catppuccin-dark",
	"github-dark",
	"solarized-light",
	"dracula-light",
	"catppuccin-light",
	"github-light",
] as const;

const PREVIOUS_COMPANION_THEME_VALUES = [
	"terminal-dark",
	"amber-crt",
	"green-mono",
	"high-contrast",
	"gruvbox-dark",
	"gruvbox-light",
	"nord-dark",
	"nord-light",
] as const;

const COMPANION_THEME_FAMILY_VALUES = [
	"solarized",
	"dracula",
	"catppuccin",
	"github",
] as const;

const COMPANION_THEME_MODE_VALUES = ["light", "dark", "system"] as const;

export type CompanionTheme = (typeof COMPANION_THEME_VALUES)[number];
type PreviousCompanionTheme = (typeof PREVIOUS_COMPANION_THEME_VALUES)[number];
type LegacyCompanionTheme = CompanionTheme | PreviousCompanionTheme;
export type CompanionThemeFamily =
	(typeof COMPANION_THEME_FAMILY_VALUES)[number];
export type CompanionThemeMode = (typeof COMPANION_THEME_MODE_VALUES)[number];
export type CompanionResolvedThemeMode = "light" | "dark";

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
	solarized: {
		dark: "solarized-dark",
		light: "solarized-light",
	},
	dracula: {
		dark: "dracula-dark",
		light: "dracula-light",
	},
	catppuccin: {
		dark: "catppuccin-dark",
		light: "catppuccin-light",
	},
	github: {
		dark: "github-dark",
		light: "github-light",
	},
};

export const COMPANION_THEME_OPTIONS: readonly CompanionThemeOption[] = [
	{
		value: "solarized-dark",
		family: "solarized",
		familyLabel: "Solarized",
		label: "Solarized Dark",
		mode: "dark",
	},
	{
		value: "dracula-dark",
		family: "dracula",
		familyLabel: "Dracula",
		label: "Dracula Dark",
		mode: "dark",
	},
	{
		value: "catppuccin-dark",
		family: "catppuccin",
		familyLabel: "Catppuccin",
		label: "Catppuccin Dark",
		mode: "dark",
	},
	{
		value: "github-dark",
		family: "github",
		familyLabel: "GitHub",
		label: "GitHub Dark",
		mode: "dark",
	},
	{
		value: "solarized-light",
		family: "solarized",
		familyLabel: "Solarized",
		label: "Solarized Light",
		mode: "light",
	},
	{
		value: "dracula-light",
		family: "dracula",
		familyLabel: "Dracula",
		label: "Dracula Light",
		mode: "light",
	},
	{
		value: "catppuccin-light",
		family: "catppuccin",
		familyLabel: "Catppuccin",
		label: "Catppuccin Light",
		mode: "light",
	},
	{
		value: "github-light",
		family: "github",
		familyLabel: "GitHub",
		label: "GitHub Light",
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
		case "solarized-dark":
		case "dracula-dark":
		case "catppuccin-dark":
		case "github-dark":
		case "solarized-light":
		case "dracula-light":
		case "catppuccin-light":
		case "github-light":
			return true;
		default:
			return false;
	}
}

function isPreviousCompanionTheme(
	value: unknown,
): value is PreviousCompanionTheme {
	switch (value) {
		case "terminal-dark":
		case "amber-crt":
		case "green-mono":
		case "high-contrast":
		case "gruvbox-dark":
		case "gruvbox-light":
		case "nord-dark":
		case "nord-light":
			return true;
		default:
			return false;
	}
}

export function isLegacyCompanionTheme(
	value: unknown,
): value is LegacyCompanionTheme {
	return isCompanionTheme(value) || isPreviousCompanionTheme(value);
}

export function isCompanionThemeFamily(
	value: unknown,
): value is CompanionThemeFamily {
	switch (value) {
		case "solarized":
		case "dracula":
		case "catppuccin":
		case "github":
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
	theme: LegacyCompanionTheme,
): CompanionThemeFamily {
	switch (theme) {
		case "terminal-dark":
		case "high-contrast":
			return "github";
		case "amber-crt":
		case "gruvbox-dark":
		case "gruvbox-light":
		case "dracula-dark":
		case "dracula-light":
			return "dracula";
		case "green-mono":
		case "nord-dark":
		case "nord-light":
			return "solarized";
		case "solarized-dark":
		case "solarized-light":
			return "solarized";
		case "catppuccin-dark":
		case "catppuccin-light":
			return "catppuccin";
		case "github-dark":
		case "github-light":
			return "github";
	}
}

export function themeModeFromLegacyTheme(
	theme: LegacyCompanionTheme,
): CompanionResolvedThemeMode {
	switch (theme) {
		case "terminal-dark":
		case "amber-crt":
		case "green-mono":
		case "high-contrast":
		case "gruvbox-dark":
		case "nord-dark":
		case "solarized-dark":
		case "dracula-dark":
		case "catppuccin-dark":
		case "github-dark":
			return "dark";
		case "gruvbox-light":
		case "nord-light":
		case "solarized-light":
		case "dracula-light":
		case "catppuccin-light":
		case "github-light":
			return "light";
	}
}

export function resolvedThemeValue(
	family: CompanionThemeFamily,
	mode: CompanionResolvedThemeMode,
): CompanionTheme {
	return THEME_BY_FAMILY_AND_MODE[family][mode];
}
