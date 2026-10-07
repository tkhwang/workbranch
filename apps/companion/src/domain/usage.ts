// Token usage and subscription limits read from the agents' local files.
// Every figure can lag: limits carry the time they were observed, and the
// views below decide how stale is too stale instead of presenting them as live.

export const USAGE_PROVIDERS = ["claude", "codex"] as const;
export type UsageProvider = (typeof USAGE_PROVIDERS)[number];

export const USAGE_DAYS = 14;

export type TokenCounts = {
	readonly input: number;
	readonly output: number;
	readonly cacheRead: number;
	readonly cacheWrite: number;
};

export type UsageBucket = TokenCounts & { readonly start: number };

export type LimitWindow = {
	readonly windowMinutes: number;
	readonly usedPercent: number;
	readonly resetsAt: number | null;
};

export type ProviderLimits = {
	readonly observedAt: number;
	readonly plan: string | null;
	readonly windows: readonly LimitWindow[];
};

export type ProviderUsage = {
	readonly available: boolean;
	readonly limits: ProviderLimits | null;
	readonly buckets: readonly UsageBucket[];
	readonly errors: readonly string[];
};

export type UsageSnapshot = {
	readonly generatedAt: number;
	readonly since: number;
	readonly claude: ProviderUsage;
	readonly codex: ProviderUsage;
};

export const EMPTY_TOKENS: TokenCounts = {
	input: 0,
	output: 0,
	cacheRead: 0,
	cacheWrite: 0,
};

const FIVE_HOUR_MINUTES = 5 * 60;
const WEEK_MINUTES = 7 * 24 * 60;
// A 5h window moves too fast to trust an hour-old reading; weekly ones drift slowly.
const SHORT_WINDOW_STALE_SECONDS = 60 * 60;
const LONG_WINDOW_STALE_SECONDS = 6 * 60 * 60;
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] as const;

export function tokenTotal(tokens: TokenCounts): number {
	return tokens.input + tokens.output + tokens.cacheRead + tokens.cacheWrite;
}

function addTokens(left: TokenCounts, right: TokenCounts): TokenCounts {
	return {
		input: left.input + right.input,
		output: left.output + right.output,
		cacheRead: left.cacheRead + right.cacheRead,
		cacheWrite: left.cacheWrite + right.cacheWrite,
	};
}

function localMidnight(epochSeconds: number, dayOffset = 0): number {
	const date = new Date(epochSeconds * 1000);
	// setDate keeps local wall time across DST, unlike adding 86400 seconds.
	date.setHours(0, 0, 0, 0);
	date.setDate(date.getDate() + dayOffset);
	return Math.floor(date.getTime() / 1000);
}

export type DailyUsage = {
	readonly start: number;
	readonly dayOfMonth: string;
	/** `10/1`: used where the axis needs the month (first day, month change). */
	readonly monthDay: string;
	/** 0 = Sunday, matching `Date.getDay`. */
	readonly weekday: number;
	readonly label: string;
	readonly tokens: TokenCounts;
	readonly total: number;
};

/** Local calendar days, oldest first, ending with today. */
export function dailyUsage(
	buckets: readonly UsageBucket[],
	nowSeconds: number,
	days = USAGE_DAYS,
): readonly DailyUsage[] {
	const starts = Array.from({ length: days }, (_, index) =>
		localMidnight(nowSeconds, index - days + 1),
	);
	const tokens = starts.map(() => EMPTY_TOKENS);
	const end = localMidnight(nowSeconds, 1);
	for (const bucket of buckets) {
		if (bucket.start < (starts[0] ?? end) || bucket.start >= end) continue;
		let index = starts.length - 1;
		while (index > 0 && bucket.start < (starts[index] ?? 0)) index -= 1;
		tokens[index] = addTokens(tokens[index] ?? EMPTY_TOKENS, bucket);
	}
	return starts.map((start, index) => {
		const date = new Date(start * 1000);
		const dayTokens = tokens[index] ?? EMPTY_TOKENS;
		return {
			start,
			dayOfMonth: String(date.getDate()),
			monthDay: `${date.getMonth() + 1}/${date.getDate()}`,
			weekday: date.getDay(),
			label: `${date.getMonth() + 1}/${date.getDate()} ${WEEKDAYS[date.getDay()]}`,
			tokens: dayTokens,
			total: tokenTotal(dayTokens),
		};
	});
}

export type LimitState = "active" | "idle" | "reset";

export type LimitView = {
	readonly label: string;
	readonly windowMinutes: number;
	readonly usedPercent: number;
	readonly resetsAt: number | null;
	readonly state: LimitState;
	readonly stale: boolean;
};

export function windowLabel(minutes: number): string {
	if (minutes === FIVE_HOUR_MINUTES) return "5h";
	if (minutes === WEEK_MINUTES) return "weekly";
	if (minutes % (24 * 60) === 0) return `${minutes / (24 * 60)}d`;
	if (minutes % 60 === 0) return `${minutes / 60}h`;
	return `${minutes}m`;
}

/** Shortest window first; a window whose reset already passed reads as 0%. */
export function limitViews(
	limits: ProviderLimits | null,
	nowSeconds: number,
): readonly LimitView[] {
	if (limits === null) return [];
	const age = Math.max(0, nowSeconds - limits.observedAt);
	return [...limits.windows]
		.sort((left, right) => left.windowMinutes - right.windowMinutes)
		.map((window) => {
			const reset = window.resetsAt !== null && window.resetsAt <= nowSeconds;
			const usedPercent = reset
				? 0
				: Math.min(100, Math.max(0, window.usedPercent));
			const state: LimitState = reset
				? "reset"
				: window.resetsAt === null && usedPercent === 0
					? "idle"
					: "active";
			const staleAfter =
				window.windowMinutes <= FIVE_HOUR_MINUTES
					? SHORT_WINDOW_STALE_SECONDS
					: LONG_WINDOW_STALE_SECONDS;
			return {
				label: windowLabel(window.windowMinutes),
				windowMinutes: window.windowMinutes,
				usedPercent,
				resetsAt: reset ? null : window.resetsAt,
				state,
				stale: !reset && age > staleAfter,
			};
		});
}

export type ProviderSummary = {
	readonly provider: UsageProvider;
	readonly available: boolean;
	readonly plan: string | null;
	readonly observedAt: number | null;
	readonly stale: boolean;
	readonly limits: readonly LimitView[];
	readonly days: readonly DailyUsage[];
	readonly today: DailyUsage | undefined;
	readonly total7: number;
	readonly total14: number;
	readonly errors: readonly string[];
};

export function summarizeProvider(
	provider: UsageProvider,
	usage: ProviderUsage,
	nowSeconds: number,
): ProviderSummary {
	const days = dailyUsage(usage.buckets, nowSeconds);
	const limits = limitViews(usage.limits, nowSeconds);
	const sum = (items: readonly DailyUsage[]) =>
		items.reduce((total, day) => total + day.total, 0);
	return {
		provider,
		available: usage.available || usage.limits !== null,
		plan: usage.limits?.plan ?? null,
		observedAt: usage.limits?.observedAt ?? null,
		stale: limits.some((limit) => limit.stale),
		limits,
		days,
		today: days.at(-1),
		total7: sum(days.slice(-7)),
		total14: sum(days),
		errors: usage.errors,
	};
}

/** `default_claude_max_20x` → `max 20x`; Codex plan types pass through. */
export function planLabel(plan: string | null): string | null {
	if (plan === null || plan.trim() === "") return null;
	return plan
		.replace(/^default_/, "")
		.replace(/^claude_/, "")
		.replaceAll("_", " ");
}

export function formatTokens(count: number): string {
	if (count <= 0) return "0";
	if (count < 1_000) return String(Math.round(count));
	if (count < 10_000) return `${(count / 1_000).toFixed(1)}k`;
	if (count < 1_000_000) return `${Math.round(count / 1_000)}k`;
	if (count < 100_000_000) return `${(count / 1_000_000).toFixed(1)}M`;
	if (count < 1_000_000_000) return `${Math.round(count / 1_000_000)}M`;
	return `${(count / 1_000_000_000).toFixed(2)}B`;
}

export function formatRemaining(seconds: number): string {
	const days = Math.floor(seconds / 86_400);
	const hours = Math.floor((seconds % 86_400) / 3_600);
	const minutes = Math.floor((seconds % 3_600) / 60);
	if (days > 0) return `${days}d ${hours}h`;
	if (hours > 0) return `${hours}h ${minutes}m`;
	if (minutes > 0) return `${minutes}m`;
	return "<1m";
}

export function formatResetPoint(epochSeconds: number): string {
	const date = new Date(epochSeconds * 1000);
	const pad = (value: number) => String(value).padStart(2, "0");
	return `${WEEKDAYS[date.getDay()]} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function formatAge(seconds: number): string {
	if (seconds < 60) return "방금";
	if (seconds < 3_600) return `${Math.floor(seconds / 60)}m 전`;
	if (seconds < 48 * 3_600) return `${Math.floor(seconds / 3_600)}h 전`;
	return `${Math.floor(seconds / 86_400)}d 전`;
}

/** The short line under a limit bar: what happens next to this window. */
export function limitDetail(limit: LimitView, nowSeconds: number): string {
	if (limit.state === "idle") return "미시작";
	if (limit.state === "reset") return "reset됨";
	if (limit.resetsAt === null) return "reset 시각 없음";
	return `${formatRemaining(limit.resetsAt - nowSeconds)} · ${formatResetPoint(limit.resetsAt)}`;
}
