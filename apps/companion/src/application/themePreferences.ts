const COMPANION_THEME_VALUES = ["catppuccin-dark", "breakfast-light"] as const;

const PREVIOUS_COMPANION_THEME_VALUES = [
	"terminal-dark",
	"amber-crt",
	"green-mono",
	"high-contrast",
	"gruvbox-dark",
	"gruvbox-light",
	"nord-dark",
	"nord-light",
	"breakfast-dark",
	"solarized-dark",
	"dracula-dark",
	"github-dark",
	"solarized-light",
	"dracula-light",
	"catppuccin-light",
	"github-light",
] as const;

const COMPANION_THEME_FAMILY_VALUES = ["companion"] as const;
const COMPANION_THEME_MODE_VALUES = ["light", "dark", "system"] as const;
const RESOLVED_THEME_MODE_VALUES = ["dark", "light"] as const;

export type CompanionTheme = (typeof COMPANION_THEME_VALUES)[number];
type PreviousCompanionTheme = (typeof PREVIOUS_COMPANION_THEME_VALUES)[number];
type LegacyCompanionTheme = CompanionTheme | PreviousCompanionTheme;
export type CompanionThemeFamily =
	(typeof COMPANION_THEME_FAMILY_VALUES)[number];
export type CompanionThemeMode = (typeof COMPANION_THEME_MODE_VALUES)[number];
export type CompanionResolvedThemeMode =
	(typeof RESOLVED_THEME_MODE_VALUES)[number];

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

const COMPANION_THEME_SET = new Set<unknown>(COMPANION_THEME_VALUES);
const PREVIOUS_COMPANION_THEME_SET = new Set<unknown>(
	PREVIOUS_COMPANION_THEME_VALUES,
);
const COMPANION_THEME_FAMILY_SET = new Set<unknown>(
	COMPANION_THEME_FAMILY_VALUES,
);
const COMPANION_THEME_MODE_SET = new Set<unknown>(COMPANION_THEME_MODE_VALUES);

const THEME_BY_MODE: Record<CompanionResolvedThemeMode, CompanionTheme> = {
	dark: "catppuccin-dark",
	light: "breakfast-light",
};

const THEME_MODE_BY_LEGACY_THEME: Record<
	LegacyCompanionTheme,
	CompanionResolvedThemeMode
> = {
	"terminal-dark": "dark",
	"amber-crt": "dark",
	"green-mono": "dark",
	"high-contrast": "dark",
	"gruvbox-dark": "dark",
	"gruvbox-light": "light",
	"nord-dark": "dark",
	"nord-light": "light",
	"breakfast-dark": "dark",
	"breakfast-light": "light",
	"solarized-dark": "dark",
	"solarized-light": "light",
	"dracula-dark": "dark",
	"dracula-light": "light",
	"catppuccin-dark": "dark",
	"catppuccin-light": "light",
	"github-dark": "dark",
	"github-light": "light",
};

export const COMPANION_THEME_OPTIONS: readonly CompanionThemeOption[] = [
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
];

export const COMPANION_THEME_MODE_OPTIONS: readonly CompanionThemeModeOption[] =
	[
		{ value: "light", label: "Light" },
		{ value: "dark", label: "Dark" },
		{ value: "system", label: "System" },
	];

export function isCompanionTheme(value: unknown): value is CompanionTheme {
	return COMPANION_THEME_SET.has(value);
}

function isPreviousCompanionTheme(
	value: unknown,
): value is PreviousCompanionTheme {
	return PREVIOUS_COMPANION_THEME_SET.has(value);
}

export function isLegacyCompanionTheme(
	value: unknown,
): value is LegacyCompanionTheme {
	return isCompanionTheme(value) || isPreviousCompanionTheme(value);
}

export function isCompanionThemeFamily(
	value: unknown,
): value is CompanionThemeFamily {
	return COMPANION_THEME_FAMILY_SET.has(value);
}

export function isCompanionThemeMode(
	value: unknown,
): value is CompanionThemeMode {
	return COMPANION_THEME_MODE_SET.has(value);
}

export function themeFamilyFromLegacyTheme(
	_theme: LegacyCompanionTheme,
): CompanionThemeFamily {
	return "companion";
}

export function themeModeFromLegacyTheme(
	theme: LegacyCompanionTheme,
): CompanionResolvedThemeMode {
	return THEME_MODE_BY_LEGACY_THEME[theme];
}

export function resolvedThemeValue(
	_family: CompanionThemeFamily,
	mode: CompanionResolvedThemeMode,
): CompanionTheme {
	return THEME_BY_MODE[mode];
}
