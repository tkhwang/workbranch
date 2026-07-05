import { describe, expect, it } from "vitest";
import { sessionsFromEvents, startOfDayEpoch } from "../src/activity/calendar";
import { assignDisplayLanes } from "../src/activity/displaySessions";

const DAY = startOfDayEpoch(new Date(2026, 6, 4));

function event(observedAt: number, task: string) {
	return {
		observedAt,
		root: "/r",
		project: "workbranch",
		task,
		status: "in-progress",
	};
}

describe("assignDisplayLanes", () => {
	it("unifies close non-overlapping sessions for the same task", () => {
		const lanes = assignDisplayLanes(
			sessionsFromEvents([
				event(DAY + 7 * 3600 + 34 * 60, "feat-calendar-workflow"),
				event(DAY + 8 * 3600 + 10 * 60, "feat-calendar-workflow"),
				event(DAY + 8 * 3600 + 58 * 60, "feat-calendar-workflow"),
			]),
		);

		expect(lanes).toHaveLength(1);
		expect(lanes[0]).toMatchObject({
			lane: 0,
			laneCount: 1,
			task: "feat-calendar-workflow",
			start: DAY + 7 * 3600 + 29 * 60,
			end: DAY + 9 * 3600 + 3 * 60,
		});
	});

	it("keeps close different-task sessions separated", () => {
		const lanes = assignDisplayLanes(
			sessionsFromEvents([
				event(DAY + 8 * 3600 + 5 * 60, "feat-calendar-workflow"),
				event(DAY + 8 * 3600 + 20 * 60, "feat-calendar-followup"),
			]),
		);

		expect(lanes).toHaveLength(2);
		expect(new Set(lanes.map((session) => session.lane))).toEqual(
			new Set([0, 1]),
		);
		expect(lanes.every((session) => session.laneCount === 2)).toBe(true);
	});
});
