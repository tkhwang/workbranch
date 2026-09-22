export const WEEKDAY_LABELS: readonly string[] = [
	"Sun",
	"Mon",
	"Tue",
	"Wed",
	"Thu",
	"Fri",
	"Sat",
];

export const LIMIT_WINDOW_DAYS = 7;
export const LIMIT_PHASE_BOUNDARY_SECONDS = 24 * 60 * 60;
// The shared axis spans [now - 7d, now + 7d]; every weekly window fits inside.
export const LIMIT_AXIS_HALF_SPAN_SECONDS = 7 * 24 * 60 * 60;

const DAY_SECONDS = 24 * 60 * 60;
const WEEK_SECONDS = LIMIT_WINDOW_DAYS * DAY_SECONDS;
const AXIS_SPAN_SECONDS = 2 * LIMIT_AXIS_HALF_SPAN_SECONDS;
// Partial cells at the axis edges narrower than half a day stay unlabeled.
const MIN_LABELED_CELL_RATIO = DAY_SECONDS / 2 / AXIS_SPAN_SECONDS;

export type LimitPhase = "fresh" | "mid" | "soon";

export type LimitWindow = {
	readonly startAt: number;
	readonly endAt: number;
	readonly elapsedRatio: number;
	readonly remainingSeconds: number;
	readonly phase: LimitPhase;
};

export type LimitAxisDay = {
	readonly startRatio: number;
	readonly endRatio: number;
	readonly label: string;
	readonly today: boolean;
};

function toDate(epochSeconds: number): Date {
	return new Date(epochSeconds * 1000);
}

function toEpochSeconds(date: Date): number {
	return Math.floor(date.getTime() / 1000);
}

function clampRatio(value: number): number {
	return Math.min(1, Math.max(0, value));
}

function pad2(value: number): string {
	return String(value).padStart(2, "0");
}

function localDateKey(date: Date): string {
	return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
}

// Calendar-day arithmetic keeps the wall-clock time across DST transitions,
// which plain 86400-second multiples would not.
export function addLocalDays(epochSeconds: number, days: number): number {
	const date = toDate(epochSeconds);
	const hours = date.getHours();
	const minutes = date.getMinutes();
	const seconds = date.getSeconds();
	date.setDate(date.getDate() + days);
	date.setHours(hours, minutes, seconds, 0);
	return toEpochSeconds(date);
}

// Normalizes a user-entered anchor onto its weekly cadence so that
// now < next <= now + 7 calendar days.
export function resolveNextReset(
	anchorEpochSeconds: number,
	nowEpochSeconds: number,
): number {
	const weeksBehind = Math.floor(
		(nowEpochSeconds - anchorEpochSeconds) / WEEK_SECONDS,
	);
	let next =
		weeksBehind === 0
			? anchorEpochSeconds
			: addLocalDays(anchorEpochSeconds, weeksBehind * LIMIT_WINDOW_DAYS);
	while (next <= nowEpochSeconds) {
		next = addLocalDays(next, LIMIT_WINDOW_DAYS);
	}
	while (addLocalDays(next, -LIMIT_WINDOW_DAYS) > nowEpochSeconds) {
		next = addLocalDays(next, -LIMIT_WINDOW_DAYS);
	}
	return next;
}

export function limitWindowAt(
	account: { readonly nextResetAt: number },
	nowEpochSeconds: number,
): LimitWindow {
	const endAt = resolveNextReset(account.nextResetAt, nowEpochSeconds);
	const startAt = addLocalDays(endAt, -LIMIT_WINDOW_DAYS);
	const elapsedSeconds = nowEpochSeconds - startAt;
	const remainingSeconds = endAt - nowEpochSeconds;
	const phase: LimitPhase =
		elapsedSeconds < LIMIT_PHASE_BOUNDARY_SECONDS
			? "fresh"
			: remainingSeconds < LIMIT_PHASE_BOUNDARY_SECONDS
				? "soon"
				: "mid";
	return {
		startAt,
		endAt,
		elapsedRatio: clampRatio(elapsedSeconds / (endAt - startAt)),
		remainingSeconds,
		phase,
	};
}

export function axisRatio(
	epochSeconds: number,
	nowEpochSeconds: number,
): number {
	const axisStart = nowEpochSeconds - LIMIT_AXIS_HALF_SPAN_SECONDS;
	return clampRatio((epochSeconds - axisStart) / AXIS_SPAN_SECONDS);
}

export function limitAxisDays(
	nowEpochSeconds: number,
): readonly LimitAxisDay[] {
	const axisEnd = nowEpochSeconds + LIMIT_AXIS_HALF_SPAN_SECONDS;
	const first = toDate(nowEpochSeconds - LIMIT_AXIS_HALF_SPAN_SECONDS);
	const todayKey = localDateKey(toDate(nowEpochSeconds));
	const days: LimitAxisDay[] = [];
	let cellStart = new Date(
		first.getFullYear(),
		first.getMonth(),
		first.getDate(),
	);
	while (toEpochSeconds(cellStart) < axisEnd) {
		const cellEnd = new Date(
			cellStart.getFullYear(),
			cellStart.getMonth(),
			cellStart.getDate() + 1,
		);
		const startRatio = axisRatio(toEpochSeconds(cellStart), nowEpochSeconds);
		const endRatio = axisRatio(toEpochSeconds(cellEnd), nowEpochSeconds);
		// Day-of-month only: uniform label widths keep the thinning tiers
		// honest, and the caption carries the month context for both ends.
		const label =
			endRatio - startRatio >= MIN_LABELED_CELL_RATIO
				? String(cellStart.getDate())
				: "";
		days.push({
			startRatio,
			endRatio,
			label,
			today: localDateKey(cellStart) === todayKey,
		});
		cellStart = cellEnd;
	}
	return days;
}

export function formatRemaining(seconds: number): string {
	const days = Math.floor(seconds / DAY_SECONDS);
	const hours = Math.floor((seconds % DAY_SECONDS) / 3600);
	const minutes = Math.floor((seconds % 3600) / 60);
	if (days > 0) return `${days}d ${hours}h`;
	if (hours > 0) return `${hours}h ${minutes}m`;
	if (minutes > 0) return `${minutes}m`;
	return "<1m";
}

export function formatMonthDay(epochSeconds: number): string {
	const date = toDate(epochSeconds);
	return `${date.getMonth() + 1}/${date.getDate()}`;
}

export function formatResetPoint(epochSeconds: number): string {
	const date = toDate(epochSeconds);
	return `${WEEKDAY_LABELS[date.getDay()]} ${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
}

export function formatResetDate(epochSeconds: number): string {
	return formatDateTimeLocal(epochSeconds).replace("T", " ");
}

export function formatDateTimeLocal(epochSeconds: number): string {
	const date = toDate(epochSeconds);
	return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}T${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
}

const DATE_TIME_LOCAL_PATTERN =
	/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::\d{2})?$/;

// Parses an <input type="datetime-local"> value as local time; seconds are
// dropped and calendar overflow such as 2026-02-30 is rejected.
export function parseDateTimeLocal(value: string): number | undefined {
	const match = DATE_TIME_LOCAL_PATTERN.exec(value);
	if (match === null) return undefined;
	const [year, month, day, hours, minutes] = match
		.slice(1, 6)
		.map((part) => Number(part));
	if (
		year === undefined ||
		month === undefined ||
		day === undefined ||
		hours === undefined ||
		minutes === undefined ||
		hours > 23 ||
		minutes > 59
	) {
		return undefined;
	}
	const date = new Date(year, month - 1, day, hours, minutes, 0, 0);
	// Any field that Date normalized away (calendar overflow, or a wall-clock
	// time inside a DST gap) means the input named no real local instant.
	if (
		Number.isNaN(date.getTime()) ||
		date.getFullYear() !== year ||
		date.getMonth() !== month - 1 ||
		date.getDate() !== day ||
		date.getHours() !== hours ||
		date.getMinutes() !== minutes
	) {
		return undefined;
	}
	return toEpochSeconds(date);
}
