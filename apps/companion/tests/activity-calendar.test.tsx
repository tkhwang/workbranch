import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import {
	assignDisplayLanes,
	CALENDAR_MODES,
	CalendarTimeline,
} from "../src/activity/ActivityCalendarView";
import {
	addDays,
	assignLanes,
	calendarEventFromUnknown,
	clipToRange,
	hourRange,
	projectColorIndex,
	sessionsFromEvents,
	startOfDayEpoch,
} from "../src/activity/calendar";

describe("calendarEventFromUnknown", () => {
	it("accepts a modern event and keeps optional plan fields", () => {
		const event = calendarEventFromUnknown({
			v: 1,
			observedAt: 100,
			root: "/r",
			project: "workbranch",
			task: "feat-x",
			status: "in-progress",
			planTitle: "Plan A",
			planStatus: "in-progress",
		});

		expect(event).toEqual({
			observedAt: 100,
			root: "/r",
			project: "workbranch",
			task: "feat-x",
			status: "in-progress",
			planTitle: "Plan A",
			planStatus: "in-progress",
		});
	});

	it("accepts a legacy event without plan fields", () => {
		const event = calendarEventFromUnknown({
			v: 1,
			observedAt: 100,
			root: "/r",
			project: "workbranch",
			task: "feat-x",
			status: "done",
		});

		expect(event?.planTitle).toBeUndefined();
	});

	it("rejects records missing observedAt, root, project, or task", () => {
		expect(
			calendarEventFromUnknown({ project: "a", task: "t" }),
		).toBeUndefined();
		expect(
			calendarEventFromUnknown({ observedAt: 100, project: "a", task: "t" }),
		).toBeUndefined();
		expect(calendarEventFromUnknown("junk")).toBeUndefined();
		expect(calendarEventFromUnknown(null)).toBeUndefined();
	});
});

const BASE = 1_781_400_000;

function event(observedAt: number, task = "feat-x", planTitle?: string) {
	return {
		observedAt,
		root: "/r",
		project: "workbranch",
		task,
		status: "in-progress",
		...(planTitle === undefined ? {} : { planTitle }),
	};
}

describe("sessionsFromEvents", () => {
	it("merges consecutive events of one task within the idle gap", () => {
		const sessions = sessionsFromEvents([
			event(BASE),
			event(BASE + 600),
			event(BASE + 1200),
		]);

		expect(sessions).toHaveLength(1);
		expect(sessions[0]?.start).toBe(BASE - 300);
		expect(sessions[0]?.end).toBe(BASE + 1200);
	});

	it("splits into two sessions when the gap exceeds 25 minutes", () => {
		const sessions = sessionsFromEvents([event(BASE), event(BASE + 26 * 60)]);

		expect(sessions).toHaveLength(2);
	});

	it("keeps different tasks in separate sessions", () => {
		const sessions = sessionsFromEvents([
			event(BASE, "a"),
			event(BASE + 60, "b"),
		]);

		expect(sessions).toHaveLength(2);
	});

	it("guarantees a minimum block length for single-event sessions", () => {
		const sessions = sessionsFromEvents([event(BASE)]);

		expect((sessions[0]?.end ?? 0) - (sessions[0]?.start ?? 0)).toBe(600);
	});

	it("collects plan titles in order without duplicates", () => {
		const sessions = sessionsFromEvents([
			event(BASE, "a", "P1"),
			event(BASE + 60, "a", "P2"),
			event(BASE + 120, "a", "P1"),
		]);

		expect(sessions[0]?.planTitles).toEqual(["P1", "P2"]);
	});
});

describe("assignLanes", () => {
	it("places overlapping sessions in separate lanes with a shared lane count", () => {
		const sessions = sessionsFromEvents([
			event(BASE, "a"),
			event(BASE + 60, "b"),
		]);
		expect(sessions).toHaveLength(2);
		const [a, b] = sessions;
		if (a === undefined || b === undefined) {
			throw new Error("expected two sessions");
		}

		const lanes = assignLanes([a, b]);

		expect(new Set(lanes.map((session) => session.lane))).toEqual(
			new Set([0, 1]),
		);
		expect(lanes.every((session) => session.laneCount === 2)).toBe(true);
	});

	it("reuses lane 0 for non-overlapping sessions", () => {
		const sessions = sessionsFromEvents([
			event(BASE, "a"),
			event(BASE + 7200, "b"),
		]);

		const lanes = assignLanes(sessions);

		expect(
			lanes.every((session) => session.lane === 0 && session.laneCount === 1),
		).toBe(true);
	});

	it("separates close sessions when a display minimum would overlap", () => {
		const sessions = sessionsFromEvents([
			event(BASE, "a"),
			event(BASE + 15 * 60, "b"),
		]);

		const lanes = assignLanes(sessions, 30 * 60);

		expect(new Set(lanes.map((session) => session.lane))).toEqual(
			new Set([0, 1]),
		);
		expect(lanes.every((session) => session.laneCount === 2)).toBe(true);
	});
});

describe("clipToRange / hourRange / date helpers", () => {
	it("clips a session crossing midnight to the day range", () => {
		const day = startOfDayEpoch(new Date(2026, 6, 4));
		const [session] = sessionsFromEvents([
			event(day - 600, "a"),
			event(day + 600, "a"),
		]);
		if (session === undefined) {
			throw new Error("expected a session");
		}

		const clipped = clipToRange([session], day, addDays(day, 1));

		expect(clipped[0]?.start).toBe(day);
		expect(clipped[0]?.end).toBe(day + 600);
	});

	it("drops sessions fully outside the range", () => {
		const day = startOfDayEpoch(new Date(2026, 6, 4));
		const [session] = sessionsFromEvents([event(day - 7200, "a")]);
		if (session === undefined) {
			throw new Error("expected a session");
		}

		expect(clipToRange([session], day, addDays(day, 1))).toHaveLength(0);
	});

	it("expands the default 9-19 hour range to include sessions", () => {
		const day = startOfDayEpoch(new Date(2026, 6, 4));
		const [early] = sessionsFromEvents([event(day + 6 * 3600, "a")]);
		if (early === undefined) {
			throw new Error("expected a session");
		}

		const range = hourRange([early], day);

		expect(range.startHour).toBeLessThanOrEqual(5);
		expect(range.endHour).toBe(19);
		expect(hourRange([], day)).toEqual({ startHour: 9, endHour: 19 });
	});

	it("hashes project names to a stable palette index", () => {
		expect(projectColorIndex("workbranch", 6)).toBe(
			projectColorIndex("workbranch", 6),
		);
		expect(projectColorIndex("workbranch", 6)).toBeGreaterThanOrEqual(0);
		expect(projectColorIndex("workbranch", 6)).toBeLessThan(6);
	});
});

const DAY = startOfDayEpoch(new Date(2026, 6, 4));

function laneSessions(observedAts: readonly number[], task = "feat-x") {
	return assignLanes(
		sessionsFromEvents(
			observedAts.map((observedAt) => ({
				observedAt,
				root: "/r",
				project: "workbranch",
				task,
				status: "in-progress",
			})),
		),
	);
}

describe("CalendarTimeline", () => {
	it("renders a session block with task name and time range in day mode", () => {
		const html = renderToStaticMarkup(
			<CalendarTimeline
				days={[DAY]}
				mode="day"
				selectedKey={undefined}
				onSelect={() => {}}
				sessions={laneSessions([DAY + 10 * 3600, DAY + 10 * 3600 + 25 * 60])}
			/>,
		);

		expect(html).toContain("feat-x");
		expect(html).toContain("9 AM");
		expect(html).toContain("09:55–10:25");
	});

	it("keeps compact day sessions readable as task and time only", () => {
		const html = renderToStaticMarkup(
			<CalendarTimeline
				days={[DAY]}
				mode="day"
				selectedKey={undefined}
				onSelect={() => {}}
				sessions={assignLanes(
					sessionsFromEvents([
						{
							observedAt: DAY + 10 * 3600,
							root: "/r",
							project: "workbranch",
							task: "feat-calendar-workflow",
							status: "in-progress",
							planTitle: "Companion Activity calendar timeline",
						},
					]),
				)}
			/>,
		);

		expect(html).toContain('data-density="compact"');
		expect(html).toContain("feat-calendar-workflow");
		expect(html).toContain("09:55–10:05");
		expect(html).not.toContain("Companion Activity calendar timeline");
	});

	it("keeps overlapping day lanes readable by hiding activity text in narrow lanes", () => {
		const html = renderToStaticMarkup(
			<CalendarTimeline
				days={[DAY]}
				mode="day"
				selectedKey={undefined}
				onSelect={() => {}}
				sessions={assignLanes(
					sessionsFromEvents([
						{
							observedAt: DAY + 14 * 3600,
							root: "/r",
							project: "monask-fullstack",
							task: "feature-cpq-task1",
							status: "in-progress",
							planTitle: "SCED configure roundtrip",
						},
						{
							observedAt: DAY + 14 * 3600 + 60,
							root: "/r",
							project: "monask-fullstack",
							task: "feature-cpq-task3",
							status: "in-progress",
							planTitle: "RFQ list item count plan",
						},
					]),
				)}
			/>,
		);

		expect(html.match(/data-width="narrow"/g)?.length).toBe(2);
		expect(html).toContain("feature-cpq-task1");
		expect(html).toContain("feature-cpq-task3");
		expect(html).not.toContain("SCED configure roundtrip");
		expect(html).not.toContain("RFQ list item count plan");
		expect(html).toContain("13:55–14:05");
		expect(html).toContain("13:56–14:06");
	});

	it("renders compact narrow overlaps as task and time only", () => {
		const html = renderToStaticMarkup(
			<CalendarTimeline
				days={[DAY]}
				mode="day"
				selectedKey={undefined}
				onSelect={() => {}}
				sessions={assignLanes(
					sessionsFromEvents([
						{
							observedAt: DAY + 8 * 3600 + 5 * 60,
							root: "/r",
							project: "workbranch",
							task: "feat-calendar-workflow",
							status: "in-progress",
						},
						{
							observedAt: DAY + 8 * 3600 + 6 * 60,
							root: "/r",
							project: "workbranch",
							task: "feat-calendar-followup",
							status: "in-progress",
						},
					]),
				)}
			/>,
		);

		expect(html.match(/data-density="compact"/g)?.length).toBe(2);
		expect(html.match(/data-width="narrow"/g)?.length).toBe(2);
		expect(html).toContain("feat-calendar-workflow");
		expect(html).toContain("feat-calendar-followup");
		expect(html).toContain("08:00–08:10");
		expect(html).toContain("08:01–08:11");
	});

	it("sets a taller minimum height for one-day compact readability", () => {
		const css = readFileSync("src/activity/activity-calendar.css", "utf8");

		expect(css).toMatch(
			/\.cal-timeline\[data-mode="day"\] \.cal-session\s*\{[^}]*min-height:\s*36px/s,
		);
		expect(css).toMatch(
			/\.cal-timeline\[data-mode="day"\] \.cal-session\[data-density="compact"\][^}]*\.cal-timeline\[data-mode="day"\] \.cal-session\[data-width="narrow"\]\s*\{[^}]*align-content:\s*center/s,
		);
	});

	it("separates visually overlapping compact blocks before rendering", () => {
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

	it("renders three day columns in three-day mode", () => {
		const html = renderToStaticMarkup(
			<CalendarTimeline
				days={[DAY, addDays(DAY, 1), addDays(DAY, 2)]}
				mode="three-day"
				selectedKey={undefined}
				onSelect={() => {}}
				sessions={[]}
			/>,
		);

		expect(html.match(/cal-day-column/g)?.length).toBe(3);
	});
});

describe("CALENDAR_MODES", () => {
	it("offers exactly day and three-day modes for this slice", () => {
		expect(CALENDAR_MODES.map((item) => item.mode)).toEqual([
			"day",
			"three-day",
		]);
	});
});
