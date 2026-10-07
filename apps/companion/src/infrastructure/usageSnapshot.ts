import type {
	LimitWindow,
	ProviderLimits,
	ProviderUsage,
	UsageBucket,
	UsageSnapshot,
} from "../domain/usage";

type Fields = Readonly<Record<string, unknown>>;

function isFields(value: unknown): value is Fields {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function count(value: unknown, field: string): number {
	if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
		throw new Error(`Invalid usage snapshot: ${field}`);
	}
	return value;
}

function optionalCount(value: unknown, field: string): number | null {
	return value === null || value === undefined ? null : count(value, field);
}

function parseBucket(value: unknown): UsageBucket {
	if (!isFields(value)) throw new Error("Invalid usage snapshot: bucket");
	return {
		start: count(value["start"], "bucket.start"),
		input: count(value["input"], "bucket.input"),
		output: count(value["output"], "bucket.output"),
		cacheRead: count(value["cacheRead"], "bucket.cacheRead"),
		cacheWrite: count(value["cacheWrite"], "bucket.cacheWrite"),
	};
}

function parseWindow(value: unknown): LimitWindow {
	if (!isFields(value)) throw new Error("Invalid usage snapshot: window");
	return {
		windowMinutes: count(value["windowMinutes"], "window.windowMinutes"),
		usedPercent: count(value["usedPercent"], "window.usedPercent"),
		resetsAt: optionalCount(value["resetsAt"], "window.resetsAt"),
	};
}

function parseLimits(value: unknown): ProviderLimits | null {
	if (value === null || value === undefined) return null;
	if (!isFields(value) || !Array.isArray(value["windows"])) {
		throw new Error("Invalid usage snapshot: limits");
	}
	const plan = value["plan"];
	return {
		observedAt: count(value["observedAt"], "limits.observedAt"),
		plan: typeof plan === "string" ? plan : null,
		windows: value["windows"].map(parseWindow),
	};
}

function parseProvider(value: unknown, name: string): ProviderUsage {
	if (
		!isFields(value) ||
		typeof value["available"] !== "boolean" ||
		!Array.isArray(value["buckets"]) ||
		!Array.isArray(value["errors"])
	) {
		throw new Error(`Invalid usage snapshot: ${name}`);
	}
	return {
		available: value["available"],
		limits: parseLimits(value["limits"]),
		buckets: value["buckets"].map(parseBucket),
		errors: value["errors"].filter(
			(error): error is string => typeof error === "string",
		),
	};
}

export function parseUsageSnapshot(value: unknown): UsageSnapshot {
	if (!isFields(value)) throw new Error("Invalid usage snapshot");
	return {
		generatedAt: count(value["generatedAt"], "generatedAt"),
		since: count(value["since"], "since"),
		claude: parseProvider(value["claude"], "claude"),
		codex: parseProvider(value["codex"], "codex"),
	};
}
