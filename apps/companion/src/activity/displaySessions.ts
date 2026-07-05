import {
	assignLanes,
	type CalendarSession,
	type LaneSession,
} from "./calendar";

const MIN_DISPLAY_LANE_SECONDS = 90 * 60;

function displayGroupKey(session: CalendarSession): string {
	return [session.root, session.project, session.task].join("\u0000");
}

function displayLaneEnd(session: CalendarSession): number {
	return session.end + MIN_DISPLAY_LANE_SECONDS;
}

function shouldCoalesce(
	current: CalendarSession,
	next: CalendarSession,
): boolean {
	return current.end <= next.start && next.start <= displayLaneEnd(current);
}

function mergePlanTitles(
	current: readonly string[],
	next: readonly string[],
): readonly string[] {
	return [...new Set([...current, ...next])];
}

function mergeDisplaySession(
	current: CalendarSession,
	next: CalendarSession,
): CalendarSession {
	return {
		...current,
		start: Math.min(current.start, next.start),
		end: Math.max(current.end, next.end),
		planTitles: mergePlanTitles(current.planTitles, next.planTitles),
		status: next.status,
	};
}

export function coalesceDisplaySessions(
	sessions: readonly CalendarSession[],
): readonly CalendarSession[] {
	const merged: CalendarSession[] = [];
	const latestByGroup = new Map<string, number>();
	const sorted = [...sessions].sort(
		(left, right) => left.start - right.start || left.end - right.end,
	);

	for (const session of sorted) {
		const groupKey = displayGroupKey(session);
		const latestIndex = latestByGroup.get(groupKey);
		if (latestIndex !== undefined) {
			const latest = merged[latestIndex];
			if (latest !== undefined && shouldCoalesce(latest, session)) {
				merged[latestIndex] = mergeDisplaySession(latest, session);
				continue;
			}
		}

		latestByGroup.set(groupKey, merged.length);
		merged.push(session);
	}

	return merged;
}

export function assignDisplayLanes(
	sessions: readonly CalendarSession[],
): readonly LaneSession[] {
	return assignLanes(
		coalesceDisplaySessions(sessions),
		MIN_DISPLAY_LANE_SECONDS,
	);
}
