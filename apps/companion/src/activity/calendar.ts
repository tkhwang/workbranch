import { IDLE_GAP_SECONDS, LEAD_PAD_SECONDS } from "../application/activity";

export type CalendarEventInput = {
	readonly observedAt: number;
	readonly root: string;
	readonly project: string;
	readonly task: string;
	readonly status?: string;
	readonly planTitle?: string;
	readonly planStatus?: string;
};

export type CalendarSession = {
	readonly key: string;
	readonly root: string;
	readonly project: string;
	readonly task: string;
	readonly start: number;
	readonly end: number;
	readonly status: string;
	readonly planTitles: readonly string[];
};

export type LaneSession = CalendarSession & {
	readonly lane: number;
	readonly laneCount: number;
};

export const MIN_SESSION_SECONDS = 5 * 60;

const SECONDS_PER_DAY = 24 * 60 * 60;
const SECONDS_PER_HOUR = 60 * 60;
const DEFAULT_START_HOUR = 9;
const DEFAULT_END_HOUR = 19;

export type HourRange = {
	readonly startHour: number;
	readonly endHour: number;
};

type CalendarEventRecord = {
	readonly observedAt: unknown;
	readonly root: unknown;
	readonly project: unknown;
	readonly task: unknown;
	readonly status?: unknown;
	readonly planTitle?: unknown;
	readonly plan?: unknown;
	readonly planStatus?: unknown;
};

function hasCalendarEventFields(value: unknown): value is CalendarEventRecord {
	return (
		typeof value === "object" &&
		value !== null &&
		"observedAt" in value &&
		"root" in value &&
		"project" in value &&
		"task" in value
	);
}

function optionalString(value: unknown): string | undefined {
	return typeof value === "string" && value !== "" ? value : undefined;
}

export function calendarEventFromUnknown(
	value: unknown,
): CalendarEventInput | undefined {
	if (!hasCalendarEventFields(value)) {
		return undefined;
	}
	if (
		typeof value.observedAt !== "number" ||
		typeof value.root !== "string" ||
		typeof value.project !== "string" ||
		typeof value.task !== "string"
	) {
		return undefined;
	}
	const status = optionalString(value.status);
	const planTitle =
		optionalString(value.planTitle) ?? optionalString(value.plan);
	const planStatus = optionalString(value.planStatus);
	return {
		observedAt: value.observedAt,
		root: value.root,
		project: value.project,
		task: value.task,
		...(status === undefined ? {} : { status }),
		...(planTitle === undefined ? {} : { planTitle }),
		...(planStatus === undefined ? {} : { planStatus }),
	};
}

function eventBucketKey(event: CalendarEventInput): string {
	return [event.root, event.project, event.task].join("\u0000");
}

function sessionKey(event: CalendarEventInput, start: number): string {
	return [event.root, event.task, String(start)].join("\u0000");
}

function sessionFromEvents(
	events: readonly CalendarEventInput[],
): CalendarSession | undefined {
	const first = events[0];
	const last = events[events.length - 1];
	if (first === undefined || last === undefined) {
		return undefined;
	}
	const start = first.observedAt - LEAD_PAD_SECONDS;
	const end = Math.max(last.observedAt, first.observedAt + MIN_SESSION_SECONDS);
	const planTitles: string[] = [];
	const seenPlanTitles = new Set<string>();
	for (const event of events) {
		if (
			event.planTitle !== undefined &&
			event.planTitle !== "" &&
			!seenPlanTitles.has(event.planTitle)
		) {
			seenPlanTitles.add(event.planTitle);
			planTitles.push(event.planTitle);
		}
	}
	return {
		key: sessionKey(first, start),
		root: first.root,
		project: first.project,
		task: first.task,
		start,
		end,
		status: last.status ?? "in-progress",
		planTitles,
	};
}

function appendSession(
	sessions: CalendarSession[],
	events: readonly CalendarEventInput[],
): void {
	const session = sessionFromEvents(events);
	if (session !== undefined) {
		sessions.push(session);
	}
}

export function sessionsFromEvents(
	events: readonly CalendarEventInput[],
): readonly CalendarSession[] {
	const buckets = new Map<string, CalendarEventInput[]>();
	for (const event of events) {
		const key = eventBucketKey(event);
		const bucket = buckets.get(key) ?? [];
		bucket.push(event);
		buckets.set(key, bucket);
	}

	const sessions: CalendarSession[] = [];
	for (const bucket of buckets.values()) {
		const sorted = [...bucket].sort(
			(left, right) => left.observedAt - right.observedAt,
		);
		let current: CalendarEventInput[] = [];
		let previous: CalendarEventInput | undefined;
		for (const event of sorted) {
			const gap =
				previous === undefined ? 0 : event.observedAt - previous.observedAt;
			if (previous !== undefined && gap > IDLE_GAP_SECONDS) {
				appendSession(sessions, current);
				current = [];
			}
			current.push(event);
			previous = event;
		}
		appendSession(sessions, current);
	}

	return sessions.sort((left, right) => left.start - right.start);
}

export function clipToRange(
	sessions: readonly CalendarSession[],
	from: number,
	to: number,
): readonly CalendarSession[] {
	return sessions
		.filter((session) => session.end > from && session.start < to)
		.map((session) => ({
			...session,
			start: Math.max(session.start, from),
			end: Math.min(session.end, to),
		}));
}

function firstAvailableLane(
	laneEnds: readonly number[],
	start: number,
): number | undefined {
	for (let index = 0; index < laneEnds.length; index += 1) {
		const end = laneEnds[index];
		if (end !== undefined && end <= start) {
			return index;
		}
	}
	return undefined;
}

function assignClusterLanes(
	cluster: readonly CalendarSession[],
): readonly LaneSession[] {
	const laneEnds: number[] = [];
	const assigned: LaneSession[] = [];
	for (const session of cluster) {
		const reusableLane = firstAvailableLane(laneEnds, session.start);
		const lane = reusableLane ?? laneEnds.length;
		laneEnds[lane] = session.end;
		assigned.push({
			...session,
			lane,
			laneCount: 1,
		});
	}
	const laneCount = Math.max(1, laneEnds.length);
	return assigned.map((session) => ({
		...session,
		laneCount,
	}));
}

function flushCluster(
	lanes: LaneSession[],
	cluster: readonly CalendarSession[],
): void {
	lanes.push(...assignClusterLanes(cluster));
}

export function assignLanes(
	sessions: readonly CalendarSession[],
): readonly LaneSession[] {
	const sorted = [...sessions].sort(
		(left, right) => left.start - right.start || left.end - right.end,
	);
	const lanes: LaneSession[] = [];
	let cluster: CalendarSession[] = [];
	let clusterEnd = Number.NEGATIVE_INFINITY;
	for (const session of sorted) {
		if (cluster.length > 0 && session.start >= clusterEnd) {
			flushCluster(lanes, cluster);
			cluster = [];
			clusterEnd = Number.NEGATIVE_INFINITY;
		}
		cluster.push(session);
		clusterEnd = Math.max(clusterEnd, session.end);
	}
	flushCluster(lanes, cluster);
	return lanes;
}

function clampHour(hour: number): number {
	return Math.max(0, Math.min(24, hour));
}

export function hourRange(
	sessions: readonly CalendarSession[],
	dayStart: number,
): HourRange {
	let startHour = DEFAULT_START_HOUR;
	let endHour = DEFAULT_END_HOUR;
	for (const session of sessions) {
		const sessionStartHour = Math.floor(
			(session.start - dayStart) / SECONDS_PER_HOUR,
		);
		const sessionEndHour = Math.ceil(
			(session.end - dayStart) / SECONDS_PER_HOUR,
		);
		startHour = Math.min(startHour, sessionStartHour);
		endHour = Math.max(endHour, sessionEndHour);
	}
	return {
		startHour: clampHour(startHour),
		endHour: clampHour(endHour),
	};
}

export function startOfDayEpoch(anchor: Date): number {
	return Math.floor(
		new Date(
			anchor.getFullYear(),
			anchor.getMonth(),
			anchor.getDate(),
		).getTime() / 1000,
	);
}

export function addDays(epoch: number, days: number): number {
	return epoch + days * SECONDS_PER_DAY;
}

export function projectColorIndex(
	project: string,
	paletteSize: number,
): number {
	if (paletteSize <= 0) {
		return 0;
	}
	let hash = 0;
	for (const character of project) {
		hash = (hash * 31 + character.charCodeAt(0)) >>> 0;
	}
	return hash % paletteSize;
}
