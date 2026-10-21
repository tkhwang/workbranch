// The screensaver setting (COMP001, COMP002). The Rust side reads it from the
// `screensaver` preference key (src-tauri/src/screensaver/machine.rs mirrors
// this shape) after Settings asks it to refresh. When the dashboard shows is
// up to macOS: its screen saver and lock screen bring it on.

export type ScreensaverConfig = {
	readonly enabled: boolean;
	/**
	 * Whether the dashboard shows each task's last requests, replies and
	 * commits. Off by default: the dashboard sits over the lock screen, where
	 * anyone at the desk can read it.
	 */
	readonly showMessages: boolean;
};

export const DEFAULT_SCREENSAVER: ScreensaverConfig = {
	enabled: false,
	showMessages: false,
};

const SCREENSAVER_KEYS: readonly string[] = ["enabled", "showMessages"];

/**
 * An unknown switch falls back to its default (off). Stores from before COMP002 also carry
 * `idleMinutes`; it counts as needing a rewrite so the stale key goes away.
 */
export function sanitizeScreensaverConfig(value: unknown): {
	readonly config: ScreensaverConfig;
	readonly sanitized: boolean;
} {
	const input =
		typeof value === "object" && value !== null
			? (value as Readonly<Record<string, unknown>>)
			: {};
	const config: ScreensaverConfig = {
		enabled:
			typeof input["enabled"] === "boolean"
				? input["enabled"]
				: DEFAULT_SCREENSAVER.enabled,
		showMessages:
			typeof input["showMessages"] === "boolean"
				? input["showMessages"]
				: DEFAULT_SCREENSAVER.showMessages,
	};
	return {
		config,
		sanitized:
			config.enabled !== input["enabled"] ||
			config.showMessages !== input["showMessages"] ||
			Object.keys(input).some((key) => !SCREENSAVER_KEYS.includes(key)),
	};
}

export function sameScreensaverConfig(
	left: ScreensaverConfig,
	right: ScreensaverConfig,
): boolean {
	return (
		left.enabled === right.enabled && left.showMessages === right.showMessages
	);
}
