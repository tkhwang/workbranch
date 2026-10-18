// The IDE window setting. When it is on and macOS granted the Accessibility
// permission, a window that Zed, VS Code, Cursor or Antigravity IDE opens for
// the IDE action moves to the screen Companion is on. The Rust side reads the
// `ideWindow` preference key each time the IDE action runs
// (src-tauri/src/ide_window.rs mirrors this shape).

export type IdeWindowConfig = {
	readonly enabled: boolean;
};

export const DEFAULT_IDE_WINDOW: IdeWindowConfig = {
	enabled: false,
};

/** An unknown switch falls back to off. */
export function sanitizeIdeWindowConfig(value: unknown): {
	readonly config: IdeWindowConfig;
	readonly sanitized: boolean;
} {
	const input =
		typeof value === "object" && value !== null
			? (value as Readonly<Record<string, unknown>>)
			: {};
	const config: IdeWindowConfig = {
		enabled:
			typeof input["enabled"] === "boolean"
				? input["enabled"]
				: DEFAULT_IDE_WINDOW.enabled,
	};
	return {
		config,
		sanitized:
			config.enabled !== input["enabled"] ||
			Object.keys(input).some((key) => key !== "enabled"),
	};
}

export function sameIdeWindowConfig(
	left: IdeWindowConfig,
	right: IdeWindowConfig,
): boolean {
	return left.enabled === right.enabled;
}
