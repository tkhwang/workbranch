const COMPANION_THEME_VALUES = ["claude", "codex"] as const;

export type CompanionTheme = (typeof COMPANION_THEME_VALUES)[number];

export type CompanionThemeOption = {
	readonly value: CompanionTheme;
	readonly label: string;
};

export const COMPANION_THEME_OPTIONS: readonly CompanionThemeOption[] = [
	{ value: "claude", label: "Claude Code" },
	{ value: "codex", label: "Codex" },
];

const COMPANION_THEME_SET = new Set<unknown>(COMPANION_THEME_VALUES);

export function isCompanionTheme(value: unknown): value is CompanionTheme {
	return COMPANION_THEME_SET.has(value);
}
