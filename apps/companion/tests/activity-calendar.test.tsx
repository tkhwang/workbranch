import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import {
	activityLoadRange,
	assignDisplayLanes,
	CALENDAR_MODES,
	CalendarTimeline,
	shouldShowLoading,
	validateProjectFilter,
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
import { IDLE_GAP_SECONDS } from "../src/application/activity";

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

function withTimeZone<Result>(timeZone: string, run: () => Result): Result {
	const previousTimeZone = process.env.TZ;
	process.env.TZ = timeZone;
	try {
		return run();
	} finally {
		if (previousTimeZone === undefined) {
			delete process.env.TZ;
		} else {
			process.env.TZ = previousTimeZone;
		}
	}
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

	it("keeps the session key stable when a reload extends an ongoing session", () => {
		const [before] = sessionsFromEvents([event(BASE), event(BASE + 600)]);
		const [after] = sessionsFromEvents([
			event(BASE),
			event(BASE + 600),
			event(BASE + 1200),
		]);

		expect(before?.key).toBeDefined();
		expect(after?.key).toBe(before?.key);
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

	it("clips a session reconstructed with end-boundary lookahead to the day end", () => {
		const day = startOfDayEpoch(new Date(2026, 6, 4));
		const [session] = sessionsFromEvents([
			event(day + 23 * 3600 + 50 * 60, "a"),
			event(addDays(day, 1) + 10 * 60, "a"),
		]);
		if (session === undefined) {
			throw new Error("expected a session");
		}

		const clipped = clipToRange([session], day, addDays(day, 1));

		expect(clipped[0]?.start).toBe(day + 23 * 3600 + 45 * 60);
		expect(clipped[0]?.end).toBe(addDays(day, 1));
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

		const range = hourRange([early]);

		expect(range.startHour).toBeLessThanOrEqual(5);
		expect(range.endHour).toBe(19);
		expect(hourRange([])).toEqual({ startHour: 9, endHour: 19 });
	});

	it("hashes project names to a stable palette index", () => {
		expect(projectColorIndex("workbranch", 6)).toBe(
			projectColorIndex("workbranch", 6),
		);
		expect(projectColorIndex("workbranch", 6)).toBeGreaterThanOrEqual(0);
		expect(projectColorIndex("workbranch", 6)).toBeLessThan(6);
	});

	it("advances to the next local midnight across DST start", () => {
		withTimeZone("America/New_York", () => {
			const day = startOfDayEpoch(new Date(2026, 2, 8));
			const nextDay = addDays(day, 1);
			const nextDate = new Date(nextDay * 1000);

			expect(nextDate.getFullYear()).toBe(2026);
			expect(nextDate.getMonth()).toBe(2);
			expect(nextDate.getDate()).toBe(9);
			expect(nextDate.getHours()).toBe(0);
			expect(nextDate.getMinutes()).toBe(0);
			expect(nextDay - day).toBe(23 * 3600);
		});
	});

	it("keeps hour ranges relative to local days across DST start", () => {
		withTimeZone("America/New_York", () => {
			const nextDay = startOfDayEpoch(new Date(2026, 2, 9));
			const [early] = sessionsFromEvents([event(nextDay + 30 * 60, "a")]);
			if (early === undefined) {
				throw new Error("expected a session");
			}

			const range = hourRange([early]);

			expect(range.startHour).toBe(0);
			expect(range.endHour).toBe(19);
		});
	});
});

const DAY = startOfDayEpoch(new Date(2026, 6, 4));

describe("activityLoadRange", () => {
	it("loads one idle gap past the visible end for boundary-crossing sessions", () => {
		const range = activityLoadRange(DAY, addDays(DAY, 1));

		expect(range).toEqual({
			from: DAY - IDLE_GAP_SECONDS,
			to: addDays(DAY, 1) + IDLE_GAP_SECONDS,
		});
	});
});

describe("shouldShowLoading", () => {
	it("shows the loading placeholder for the first load", () => {
		expect(
			shouldShowLoading(undefined, { from: DAY, to: addDays(DAY, 1) }),
		).toBe(true);
	});

	it("shows the loading placeholder when the visible range changes", () => {
		expect(
			shouldShowLoading(
				{ from: DAY, to: addDays(DAY, 1) },
				{ from: addDays(DAY, 1), to: addDays(DAY, 2) },
			),
		).toBe(true);
	});

	it("reloads silently when only the reload token changed for the same range", () => {
		expect(
			shouldShowLoading(
				{ from: DAY, to: addDays(DAY, 1) },
				{ from: DAY, to: addDays(DAY, 1) },
			),
		).toBe(false);
	});
});

describe("validateProjectFilter", () => {
	it("clears a selected project that is absent from freshly loaded events", () => {
		const nextEvents = [
			{
				observedAt: DAY + 10 * 3600,
				root: "/r",
				project: "project-b",
				task: "task-b",
				status: "in-progress",
			},
		];

		expect(validateProjectFilter(nextEvents, "project-a")).toBeUndefined();
	});

	it("keeps a selected project that is still present after loading events", () => {
		const nextEvents = [
			{
				observedAt: DAY + 10 * 3600,
				root: "/r",
				project: "project-a",
				task: "task-a",
				status: "in-progress",
			},
		];

		expect(validateProjectFilter(nextEvents, "project-a")).toBe("project-a");
	});
});

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

	it("renders one hour row per visible time interval", () => {
		const html = renderToStaticMarkup(
			<CalendarTimeline
				days={[DAY]}
				mode="day"
				selectedKey={undefined}
				onSelect={() => {}}
				sessions={[]}
			/>,
		);

		expect(html.match(/cal-hour-label/g)?.length).toBe(10);
		expect(html.match(/cal-hour-rule/g)?.length).toBe(10);
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

	it("provides static project-colored fallbacks before color-mix session colors", () => {
		const css = readFileSync("src/activity/activity-calendar.css", "utf8");
		const sessionBlock = css.match(/\.cal-session\s*\{(?<body>[^}]*)\}/)?.groups
			?.body;

		if (sessionBlock === undefined) {
			throw new Error("expected .cal-session CSS block");
		}

		expect(css).toMatch(
			/\.cal-session\[data-color="0"\]\s*\{[^}]*--cal-bg:\s*rgba/s,
		);
		expect(sessionBlock).toMatch(/background:\s*var\(--cal-bg\)/);
		expect(sessionBlock).toMatch(
			/border-color:\s*var\(--cal-color,\s*var\(--accent\)\)/,
		);
		expect(sessionBlock).not.toContain("color-mix(");
		expect(css).toMatch(
			/@supports\s*\(background:\s*color-mix\(in srgb,\s*black,\s*white\)\)\s*\{[\s\S]*\.cal-session\s*\{[\s\S]*background:\s*color-mix/s,
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

	it("keeps early three-day hour bounds relative to each visible day", () => {
		const html = renderToStaticMarkup(
			<CalendarTimeline
				days={[DAY, addDays(DAY, 1), addDays(DAY, 2)]}
				mode="three-day"
				selectedKey={undefined}
				onSelect={() => {}}
				sessions={assignLanes(
					sessionsFromEvents([
						{
							observedAt: addDays(DAY, 1) + 8 * 3600,
							root: "/r",
							project: "workbranch",
							task: "feat-next-day",
							status: "in-progress",
						},
					]),
				)}
			/>,
		);

		expect(html).toContain("8 AM");
		expect(html).not.toContain("12 AM");
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
