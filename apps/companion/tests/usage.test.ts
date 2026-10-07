import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
	dailyUsage,
	formatAge,
	formatTokens,
	limitDetail,
	limitViews,
	planLabel,
	summarizeProvider,
	type UsageBucket,
	windowLabel,
} from "../src/domain/usage";

function localEpoch(
	year: number,
	month: number,
	day: number,
	hour = 0,
	minute = 0,
): number {
	return Math.floor(
		new Date(year, month - 1, day, hour, minute, 0, 0).getTime() / 1000,
	);
}

function bucket(start: number, output: number): UsageBucket {
	return { start, input: 0, output, cacheRead: 0, cacheWrite: 0 };
}

describe("usage domain", () => {
	let previousTimeZone: string | undefined;
	// 2026-10-07 (Wed) 07:18 Asia/Seoul
	let now = 0;

	beforeAll(() => {
		previousTimeZone = process.env["TZ"];
		process.env["TZ"] = "Asia/Seoul";
		now = localEpoch(2026, 10, 7, 7, 18);
	});

	afterAll(() => {
		if (previousTimeZone === undefined) {
			delete process.env["TZ"];
		} else {
			process.env["TZ"] = previousTimeZone;
		}
	});

	it("groups 15-minute buckets into local days ending today", () => {
		const days = dailyUsage(
			[
				// 23:45 and 00:00 local fall on either side of midnight.
				bucket(localEpoch(2026, 10, 6, 23, 45), 5),
				bucket(localEpoch(2026, 10, 7, 0, 0), 7),
				bucket(localEpoch(2026, 10, 7, 6, 0), 1),
				// Outside the 14-day window on both ends.
				bucket(localEpoch(2026, 9, 23, 23, 45), 100),
				bucket(localEpoch(2026, 10, 8, 0, 0), 100),
			],
			now,
		);

		expect(days).toHaveLength(14);
		expect(days[0]?.label).toBe("9/24 Thu");
		expect(days.at(-1)?.label).toBe("10/7 Wed");
		expect(days.at(-2)?.total).toBe(5);
		expect(days.at(-1)?.total).toBe(8);
		expect(days.reduce((sum, day) => sum + day.total, 0)).toBe(13);
	});

	it("orders windows shortest first and reads passed resets as 0%", () => {
		const views = limitViews(
			{
				observedAt: now - 30 * 60,
				plan: null,
				windows: [
					{ windowMinutes: 10080, usedPercent: 6, resetsAt: now + 3600 },
					{ windowMinutes: 300, usedPercent: 40, resetsAt: now - 60 },
				],
			},
			now,
		);

		expect(views.map((view) => view.label)).toEqual(["5h", "weekly"]);
		expect(views[0]).toMatchObject({
			usedPercent: 0,
			state: "reset",
			resetsAt: null,
			stale: false,
		});
		expect(views[1]).toMatchObject({ usedPercent: 6, state: "active" });
	});

	it("marks a 5h reading stale after an hour and a weekly one after six", () => {
		const windows = [
			{ windowMinutes: 300, usedPercent: 0, resetsAt: null },
			{ windowMinutes: 10080, usedPercent: 6, resetsAt: now + 86_400 },
		];
		const twoHoursOld = limitViews(
			{ observedAt: now - 2 * 3600, plan: null, windows },
			now,
		);
		const dayOld = limitViews(
			{ observedAt: now - 21 * 3600, plan: null, windows },
			now,
		);

		expect(twoHoursOld.map((view) => view.stale)).toEqual([true, false]);
		expect(twoHoursOld[0]?.state).toBe("idle");
		expect(dayOld.map((view) => view.stale)).toEqual([true, true]);
	});

	it("summarizes a provider with no files as unavailable", () => {
		const summary = summarizeProvider(
			"codex",
			{ available: false, limits: null, buckets: [], errors: [] },
			now,
		);

		expect(summary.available).toBe(false);
		expect(summary.limits).toEqual([]);
		expect(summary.total14).toBe(0);
	});

	it("describes what happens next to each window", () => {
		const [idle, weekly] = limitViews(
			{
				observedAt: now,
				plan: null,
				windows: [
					{ windowMinutes: 300, usedPercent: 0, resetsAt: null },
					{
						windowMinutes: 10080,
						usedPercent: 6,
						resetsAt: localEpoch(2026, 10, 11, 23),
					},
				],
			},
			now,
		);

		expect(idle && limitDetail(idle, now)).toBe("미시작");
		expect(weekly && limitDetail(weekly, now)).toBe("4d 15h · Sun 23:00");
	});

	it("formats tokens, plans, ages, and window lengths compactly", () => {
		expect(
			[0, 182, 1_234, 85_344, 16_111_510, 338_400_000, 7_310_000_000].map(
				formatTokens,
			),
		).toEqual(["0", "182", "1.2k", "85k", "16.1M", "338M", "7.31B"]);
		expect(planLabel("default_claude_max_20x")).toBe("max 20x");
		expect(planLabel("pro")).toBe("pro");
		expect(planLabel(null)).toBeNull();
		expect([30, 300, 21 * 3600, 3 * 86_400].map(formatAge)).toEqual([
			"방금",
			"5m 전",
			"21h 전",
			"3d 전",
		]);
		expect([300, 10080, 60 * 24 * 30, 120].map(windowLabel)).toEqual([
			"5h",
			"weekly",
			"30d",
			"2h",
		]);
	});
});
