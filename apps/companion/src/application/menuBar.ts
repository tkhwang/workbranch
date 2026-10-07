// What the tray shows beside its icon. The Rust side (src-tauri/src/menu_bar.rs)
// reads this from the `menuBar` preference key and draws the real title; this
// module owns the setting and the sample shown in Settings.

export type MenuBarPercent = "used" | "remaining";

export type MenuBarItem =
	| "claude5h"
	| "claudeWeekly"
	| "codexWeekly"
	| "todayTokens";

export type MenuBarConfig = {
	readonly [item in MenuBarItem]: boolean;
} & {
	readonly percent: MenuBarPercent;
};

export type MenuBarItemOption = {
	readonly item: MenuBarItem;
	readonly label: string;
	readonly detail: string;
};

export type MenuBarPercentOption = {
	readonly value: MenuBarPercent;
	readonly label: string;
};

export const DEFAULT_MENU_BAR: MenuBarConfig = {
	claude5h: true,
	claudeWeekly: true,
	codexWeekly: true,
	todayTokens: true,
	percent: "used",
};

export const MENU_BAR_ITEM_OPTIONS: readonly MenuBarItemOption[] = [
	{ item: "claude5h", label: "Claude 5h", detail: "5-hour limit, CL 5h" },
	{
		item: "claudeWeekly",
		label: "Claude weekly",
		detail: "7-day limit, CL W",
	},
	{
		item: "codexWeekly",
		label: "Codex weekly",
		detail: "7-day limit, CO W",
	},
	{
		item: "todayTokens",
		label: "Today's tokens",
		detail: "Both agents since midnight",
	},
];

export const MENU_BAR_PERCENT_OPTIONS: readonly MenuBarPercentOption[] = [
	{ value: "used", label: "Used %" },
	{ value: "remaining", label: "Remaining %" },
];

const MENU_BAR_ITEMS = MENU_BAR_ITEM_OPTIONS.map((option) => option.item);

/** Unknown or missing fields fall back to their default, one at a time. */
export function sanitizeMenuBarConfig(value: unknown): {
	readonly config: MenuBarConfig;
	readonly sanitized: boolean;
} {
	const input =
		typeof value === "object" && value !== null
			? (value as Readonly<Record<string, unknown>>)
			: {};
	const config: MenuBarConfig = {
		claude5h: booleanOr(input["claude5h"], DEFAULT_MENU_BAR.claude5h),
		claudeWeekly: booleanOr(
			input["claudeWeekly"],
			DEFAULT_MENU_BAR.claudeWeekly,
		),
		codexWeekly: booleanOr(input["codexWeekly"], DEFAULT_MENU_BAR.codexWeekly),
		todayTokens: booleanOr(input["todayTokens"], DEFAULT_MENU_BAR.todayTokens),
		percent:
			input["percent"] === "used" || input["percent"] === "remaining"
				? input["percent"]
				: DEFAULT_MENU_BAR.percent,
	};
	return {
		config,
		sanitized:
			MENU_BAR_ITEMS.some((item) => config[item] !== input[item]) ||
			config.percent !== input["percent"],
	};
}

function booleanOr(value: unknown, fallback: boolean): boolean {
	return typeof value === "boolean" ? value : fallback;
}

export function sameMenuBarConfig(
	left: MenuBarConfig,
	right: MenuBarConfig,
): boolean {
	return (
		MENU_BAR_ITEMS.every((item) => left[item] === right[item]) &&
		left.percent === right.percent
	);
}

export function isIconOnly(config: MenuBarConfig): boolean {
	return MENU_BAR_ITEMS.every((item) => !config[item]);
}

/** Used percents for the Settings preview; the tray uses live readings. */
export const MENU_BAR_SAMPLE = {
	claude5h: 42,
	claudeWeekly: 63,
	codexWeekly: 18,
	todayTokens: "31.0M",
} as const;

/** Same layout as `menu_bar_title` in Rust: `CL 5h 42% · W 63%  CO W 18% · 31.0M`. */
export function menuBarSampleTitle(config: MenuBarConfig): string {
	const percent = (used: number) =>
		`${config.percent === "used" ? used : 100 - used}%`;
	const claude = [
		config.claude5h ? `5h ${percent(MENU_BAR_SAMPLE.claude5h)}` : undefined,
		config.claudeWeekly
			? `W ${percent(MENU_BAR_SAMPLE.claudeWeekly)}`
			: undefined,
	].filter((value) => value !== undefined);
	const limits = [
		claude.length > 0 ? `CL ${claude.join(" · ")}` : undefined,
		config.codexWeekly
			? `CO W ${percent(MENU_BAR_SAMPLE.codexWeekly)}`
			: undefined,
	].filter((value) => value !== undefined);
	const parts = [
		limits.length > 0 ? limits.join("  ") : undefined,
		config.todayTokens ? MENU_BAR_SAMPLE.todayTokens : undefined,
	].filter((value) => value !== undefined);
	return parts.join(" · ");
}
