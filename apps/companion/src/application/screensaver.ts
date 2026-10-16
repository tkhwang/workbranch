// The screensaver setting (COMP001). The Rust side reads it from the
// `screensaver` preference key (src-tauri/src/screensaver/machine.rs mirrors
// this shape and its bounds) after Settings asks it to refresh.

export type ScreensaverConfig = {
	readonly enabled: boolean;
	/** Minutes without keyboard or mouse input before the dashboard shows. */
	readonly idleMinutes: number;
};

export const SCREENSAVER_IDLE_MINUTES = { min: 1, max: 60 } as const;

export const DEFAULT_SCREENSAVER: ScreensaverConfig = {
	enabled: false,
	idleMinutes: 5,
};

/** Unknown or missing fields fall back to their default, one at a time. */
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
		idleMinutes: idleMinutesOr(input["idleMinutes"]),
	};
	return {
		config,
		sanitized:
			config.enabled !== input["enabled"] ||
			config.idleMinutes !== input["idleMinutes"],
	};
}

function idleMinutesOr(value: unknown): number {
	if (typeof value !== "number" || !Number.isFinite(value))
		return DEFAULT_SCREENSAVER.idleMinutes;
	return Math.min(
		SCREENSAVER_IDLE_MINUTES.max,
		Math.max(SCREENSAVER_IDLE_MINUTES.min, Math.round(value)),
	);
}

export function sameScreensaverConfig(
	left: ScreensaverConfig,
	right: ScreensaverConfig,
): boolean {
	return (
		left.enabled === right.enabled && left.idleMinutes === right.idleMinutes
	);
}
