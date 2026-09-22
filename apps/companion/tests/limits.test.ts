import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import {
	COMPANION_LIMITS_STORE_FILE,
	type CompanionLimitStore,
	isEpochSeconds,
	LIMIT_ACCOUNTS_STORE_KEY,
	type LimitAccount,
	limitAccountDisplayLabel,
	loadCompanionLimitStore,
	MAX_LIMIT_ACCOUNTS,
	newLimitAccount,
	readLimitAccounts,
	sanitizeLimitAccounts,
	shouldRestoreFailedAccountsUpdate,
	writeLimitAccounts,
} from "../src/application/limits";
import {
	addLocalDays,
	axisRatio,
	formatDateTimeLocal,
	formatMonthDay,
	formatRemaining,
	formatResetDate,
	formatResetPoint,
	LIMIT_AXIS_HALF_SPAN_SECONDS,
	limitAxisDays,
	limitWindowAt,
	parseDateTimeLocal,
	resolveNextReset,
} from "../src/domain/limits";

const storeLoad = vi.hoisted(() => vi.fn());

vi.mock("@tauri-apps/plugin-store", () => ({ load: storeLoad }));

const DAY = 24 * 60 * 60;

function fakeLimitStore(stored: unknown): {
	readonly calls: string[];
	readonly store: CompanionLimitStore;
} {
	const calls: string[] = [];
	return {
		calls,
		store: {
			get: async <T>(key: string) => {
				calls.push(`get:${key}`);
				return (key === LIMIT_ACCOUNTS_STORE_KEY ? stored : undefined) as
					| T
					| undefined;
			},
			set: async (key, value) => {
				calls.push(`set:${key}:${JSON.stringify(value)}`);
			},
			save: async () => {
				calls.push("save");
			},
		},
	};
}

function withTimeZone<Result>(timeZone: string, run: () => Result): Result {
	const previousTimeZone = process.env["TZ"];
	process.env["TZ"] = timeZone;
	try {
		return run();
	} finally {
		if (previousTimeZone === undefined) {
			delete process.env["TZ"];
		} else {
			process.env["TZ"] = previousTimeZone;
		}
	}
}

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

describe("domain/limits", () => {
	let previousTimeZone: string | undefined;
	// 2026-09-22 (Tue) 14:37 Asia/Seoul
	let now = 0;

	beforeAll(() => {
		previousTimeZone = process.env["TZ"];
		process.env["TZ"] = "Asia/Seoul";
		now = localEpoch(2026, 9, 22, 14, 37);
	});

	afterAll(() => {
		if (previousTimeZone === undefined) {
			delete process.env["TZ"];
		} else {
			process.env["TZ"] = previousTimeZone;
		}
	});

	describe("addLocalDays", () => {
		it("moves by calendar days while keeping the wall-clock time", () => {
			expect(addLocalDays(now, 7)).toBe(localEpoch(2026, 9, 29, 14, 37));
			expect(addLocalDays(now, -7)).toBe(localEpoch(2026, 9, 15, 14, 37));
			expect(addLocalDays(now, 0)).toBe(now);
		});

		it("keeps the wall-clock time across DST transitions", () => {
			withTimeZone("America/New_York", () => {
				const beforeSpringForward = localEpoch(2026, 3, 5, 15, 0);
				expect(addLocalDays(beforeSpringForward, 7) - beforeSpringForward).toBe(
					7 * DAY - 3600,
				);
				const beforeFallBack = localEpoch(2026, 10, 29, 15, 0);
				expect(addLocalDays(beforeFallBack, 7) - beforeFallBack).toBe(
					7 * DAY + 3600,
				);
			});
		});
	});

	describe("resolveNextReset", () => {
		it("keeps an anchor that already lies inside the coming week", () => {
			const anchor = localEpoch(2026, 9, 24, 15, 0);
			expect(resolveNextReset(anchor, now)).toBe(anchor);
		});

		it("rolls a past anchor forward by whole calendar weeks", () => {
			const expected = localEpoch(2026, 9, 24, 15, 0);
			expect(resolveNextReset(localEpoch(2026, 9, 17, 15, 0), now)).toBe(
				expected,
			);
			expect(resolveNextReset(localEpoch(2026, 6, 4, 15, 0), now)).toBe(
				expected,
			);
		});

		it("rolls a far-future anchor back into the coming week", () => {
			expect(resolveNextReset(localEpoch(2026, 10, 8, 15, 0), now)).toBe(
				localEpoch(2026, 9, 24, 15, 0),
			);
		});

		it("starts a new window when the anchor equals now", () => {
			expect(resolveNextReset(now, now)).toBe(addLocalDays(now, 7));
		});

		it("keeps an anchor exactly one calendar week ahead", () => {
			const anchor = addLocalDays(now, 7);
			expect(resolveNextReset(anchor, now)).toBe(anchor);
		});
	});

	describe("limitWindowAt", () => {
		it("derives the current window from a normalized anchor", () => {
			const window = limitWindowAt(
				{ nextResetAt: localEpoch(2026, 9, 17, 15, 0) },
				now,
			);

			expect(window.startAt).toBe(localEpoch(2026, 9, 17, 15, 0));
			expect(window.endAt).toBe(localEpoch(2026, 9, 24, 15, 0));
			expect(window.startAt).toBe(addLocalDays(window.endAt, -7));
			expect(window.remainingSeconds).toBe(window.endAt - now);
			expect(window.elapsedRatio).toBeCloseTo(
				(now - window.startAt) / (7 * DAY),
				6,
			);
			expect(window.phase).toBe("mid");
		});

		it("reports the reset instant as the start of a fresh window", () => {
			const window = limitWindowAt({ nextResetAt: now }, now);

			expect(window.startAt).toBe(now);
			expect(window.elapsedRatio).toBe(0);
			expect(window.remainingSeconds).toBe(7 * DAY);
			expect(window.phase).toBe("fresh");
		});

		it("reports half elapsed in the middle of the window", () => {
			const window = limitWindowAt({ nextResetAt: now + 3.5 * DAY }, now);

			expect(window.elapsedRatio).toBeCloseTo(0.5, 6);
			expect(window.phase).toBe("mid");
		});

		it("uses exclusive 24 hour boundaries for fresh and soon", () => {
			const weekAhead = addLocalDays(now, 7);

			expect(
				limitWindowAt({ nextResetAt: weekAhead - (DAY - 1) }, now).phase,
			).toBe("fresh");
			expect(limitWindowAt({ nextResetAt: weekAhead - DAY }, now).phase).toBe(
				"mid",
			);
			expect(limitWindowAt({ nextResetAt: now + DAY }, now).phase).toBe("mid");
			expect(limitWindowAt({ nextResetAt: now + DAY - 1 }, now).phase).toBe(
				"soon",
			);
		});
	});

	describe("axisRatio", () => {
		it("maps now to the axis center and clamps outside the axis", () => {
			expect(axisRatio(now, now)).toBe(0.5);
			expect(axisRatio(now - LIMIT_AXIS_HALF_SPAN_SECONDS, now)).toBe(0);
			expect(axisRatio(now + LIMIT_AXIS_HALF_SPAN_SECONDS, now)).toBe(1);
			expect(axisRatio(now - 8 * DAY, now)).toBe(0);
			expect(axisRatio(now + 8 * DAY, now)).toBe(1);
		});

		it("places the sample window on the axis", () => {
			const window = limitWindowAt(
				{ nextResetAt: localEpoch(2026, 9, 24, 15, 0) },
				now,
			);

			expect(axisRatio(window.endAt, now)).toBeCloseTo(0.644, 3);
			expect(axisRatio(window.startAt, now)).toBeCloseTo(0.144, 3);
		});
	});

	describe("limitAxisDays", () => {
		it("splits the axis into local calendar cells with date labels", () => {
			const days = limitAxisDays(now);

			expect(days).toHaveLength(15);
			expect(days.map((day) => day.label)).toEqual([
				"",
				...Array.from({ length: 14 }, (_, index) => String(16 + index)),
			]);
			expect(days.filter((day) => day.today).map((day) => day.label)).toEqual([
				"22",
			]);
			expect(days[0]?.startRatio).toBe(0);
			expect(days[days.length - 1]?.endRatio).toBe(1);
			for (let index = 1; index < days.length; index += 1) {
				const previous = days[index - 1];
				const current = days[index];
				expect(current?.startRatio).toBe(previous?.endRatio);
				expect(current?.startRatio ?? 0).toBeGreaterThan(
					previous?.startRatio ?? 0,
				);
			}
		});

		it("labels a wide leading cell and leaves a narrow trailing cell blank", () => {
			const days = limitAxisDays(localEpoch(2026, 9, 22, 5, 0));

			expect(days[0]?.label).toBe("15");
			expect(days[days.length - 1]?.label).toBe("");
		});

		it("numbers cells by day of month straight across a month boundary", () => {
			const labels = limitAxisDays(localEpoch(2026, 9, 28, 14, 37)).map(
				(day) => day.label,
			);

			expect(labels.join(",")).toContain("29,30,1,2");
			expect(labels.filter((label) => label !== "")[0]).toBe("22");
		});

		it("formats the axis ends as month/day for the caption", () => {
			expect(formatMonthDay(now - LIMIT_AXIS_HALF_SPAN_SECONDS)).toBe("9/15");
			expect(formatMonthDay(now + LIMIT_AXIS_HALF_SPAN_SECONDS)).toBe("9/29");
		});

		it("keeps a 25 hour cell on the DST fall-back day", () => {
			withTimeZone("America/New_York", () => {
				const days = limitAxisDays(localEpoch(2026, 11, 3, 12, 0));
				const fallBackDay = days.find((day) => day.label === "1");

				expect(fallBackDay).toBeDefined();
				expect(
					((fallBackDay?.endRatio ?? 0) - (fallBackDay?.startRatio ?? 0)) *
						(14 * 24),
				).toBeCloseTo(25, 6);
			});
		});
	});

	describe("formatting", () => {
		it("formats remaining time at day, hour, and minute granularity", () => {
			expect(formatRemaining(3 * DAY + 4 * 3600 + 5 * 60)).toBe("3d 4h");
			expect(formatRemaining(DAY)).toBe("1d 0h");
			expect(formatRemaining(4 * 3600 + 12 * 60 + 59)).toBe("4h 12m");
			expect(formatRemaining(12 * 60 + 30)).toBe("12m");
			expect(formatRemaining(45)).toBe("<1m");
			expect(formatRemaining(0)).toBe("<1m");
		});

		it("formats a reset instant for the row, the title, and the date input", () => {
			const reset = localEpoch(2026, 9, 24, 15, 0);

			expect(formatResetPoint(reset)).toBe("Thu 15:00");
			expect(formatResetDate(reset)).toBe("2026-09-24 15:00");
			expect(formatDateTimeLocal(reset)).toBe("2026-09-24T15:00");
		});

		it("parses datetime-local values as local time and rejects invalid input", () => {
			const reset = localEpoch(2026, 9, 24, 15, 0);

			expect(parseDateTimeLocal("2026-09-24T15:00")).toBe(reset);
			expect(parseDateTimeLocal("2026-09-24T15:00:30")).toBe(reset);
			expect(parseDateTimeLocal("")).toBeUndefined();
			expect(parseDateTimeLocal("abc")).toBeUndefined();
			expect(parseDateTimeLocal("2026-13-01T00:00")).toBeUndefined();
			expect(parseDateTimeLocal("2026-02-30T10:00")).toBeUndefined();
			expect(parseDateTimeLocal("2026-09-24T24:00")).toBeUndefined();
		});
	});
});

describe("application/limits", () => {
	let previousTimeZone: string | undefined;
	let now = new Date(0);
	const account = (id: string, nextResetAt = 1_800_000_000): LimitAccount => ({
		id,
		label: `Account ${id}`,
		nextResetAt,
	});

	beforeAll(() => {
		previousTimeZone = process.env["TZ"];
		process.env["TZ"] = "Asia/Seoul";
		now = new Date(2026, 8, 22, 14, 37, 0, 0);
	});

	afterAll(() => {
		if (previousTimeZone === undefined) {
			delete process.env["TZ"];
		} else {
			process.env["TZ"] = previousTimeZone;
		}
	});

	describe("isEpochSeconds", () => {
		it("accepts positive safe integers only", () => {
			expect(isEpochSeconds(1_800_000_000)).toBe(true);
			expect(isEpochSeconds(0)).toBe(false);
			expect(isEpochSeconds(-1)).toBe(false);
			expect(isEpochSeconds(1.5)).toBe(false);
			expect(isEpochSeconds(Number.NaN)).toBe(false);
			expect(isEpochSeconds("1800000000")).toBe(false);
			expect(isEpochSeconds(undefined)).toBe(false);
		});
	});

	describe("sanitizeLimitAccounts", () => {
		it("returns an empty list for anything that is not an array", () => {
			expect(sanitizeLimitAccounts(undefined)).toEqual([]);
			expect(sanitizeLimitAccounts({ accounts: [] })).toEqual([]);
			expect(sanitizeLimitAccounts("[]")).toEqual([]);
		});

		it("keeps valid entries and drops corrupt siblings", () => {
			const stored = [
				{ id: "a", label: "Main", nextResetAt: 1_800_000_000 },
				{ label: "no id", nextResetAt: 1_800_000_000 },
				{ id: "", label: "blank id", nextResetAt: 1_800_000_000 },
				{ id: "b", label: "string reset", nextResetAt: "1800000000" },
				{ id: "c", label: "nan reset", nextResetAt: Number.NaN },
				{ id: "d", label: "zero reset", nextResetAt: 0 },
				{ id: "e", label: "fractional reset", nextResetAt: 1.5 },
				null,
				"text",
				{ id: "f", nextResetAt: 1_800_000_000, extra: true },
			];

			expect(sanitizeLimitAccounts(stored)).toEqual([
				{ id: "a", label: "Main", nextResetAt: 1_800_000_000 },
				{ id: "f", label: "", nextResetAt: 1_800_000_000 },
			]);
		});

		it("normalizes labels without dropping the account", () => {
			const longLabel = `${"x".repeat(41)}`;

			expect(
				sanitizeLimitAccounts([
					{ id: "a", label: 42, nextResetAt: 1_800_000_000 },
					{ id: "b", label: "  padded  ", nextResetAt: 1_800_000_000 },
					{ id: "c", label: longLabel, nextResetAt: 1_800_000_000 },
				]).map((entry) => entry.label),
			).toEqual(["", "padded", "x".repeat(40)]);
		});

		it("keeps the first of duplicate ids and caps the list at the maximum", () => {
			const duplicates = sanitizeLimitAccounts([
				account("a", 1_800_000_000),
				{ ...account("a", 1_900_000_000), label: "later" },
			]);
			expect(duplicates).toEqual([account("a", 1_800_000_000)]);

			const many = Array.from({ length: MAX_LIMIT_ACCOUNTS + 1 }, (_, index) =>
				account(`id-${index}`),
			);
			const capped = sanitizeLimitAccounts(many);
			expect(capped).toHaveLength(MAX_LIMIT_ACCOUNTS);
			expect(capped[capped.length - 1]?.id).toBe(
				`id-${MAX_LIMIT_ACCOUNTS - 1}`,
			);
		});
	});

	describe("newLimitAccount", () => {
		it("numbers the label after the existing accounts", () => {
			expect(newLimitAccount([], now, () => "id-1").label).toBe("Account 1");
			expect(
				newLimitAccount([account("a"), account("b")], now, () => "id-3").label,
			).toBe("Account 3");
		});

		it("starts a fresh window one calendar week after the current hour", () => {
			const created = newLimitAccount([], now, () => "id-1");

			expect(created.id).toBe("id-1");
			expect(created.nextResetAt).toBe(localEpoch(2026, 9, 29, 14, 0));
		});
	});

	describe("limitAccountDisplayLabel", () => {
		it("falls back to the account number for a blank label", () => {
			expect(limitAccountDisplayLabel({ ...account("a"), label: "" }, 2)).toBe(
				"Account 3",
			);
			expect(
				limitAccountDisplayLabel({ ...account("a"), label: "Work" }, 2),
			).toBe("Work");
		});
	});

	describe("shouldRestoreFailedAccountsUpdate", () => {
		it("restores only when the attempted list is still current", () => {
			const attempted = [account("a")];

			expect(shouldRestoreFailedAccountsUpdate(attempted, attempted)).toBe(
				true,
			);
			expect(shouldRestoreFailedAccountsUpdate([account("a")], attempted)).toBe(
				false,
			);
		});
	});

	describe("store", () => {
		it("loads the dedicated companion-limits store without autosave", async () => {
			storeLoad.mockReset();
			const { store } = fakeLimitStore(undefined);
			storeLoad.mockResolvedValue(store);

			await expect(loadCompanionLimitStore()).resolves.toBe(store);
			expect(storeLoad).toHaveBeenCalledWith(COMPANION_LIMITS_STORE_FILE, {
				autoSave: false,
				defaults: {},
			});
		});

		it("reads and sanitizes the accounts key", async () => {
			const { calls, store } = fakeLimitStore([account("a"), { id: "broken" }]);

			await expect(readLimitAccounts(store)).resolves.toEqual([account("a")]);
			expect(calls).toEqual([`get:${LIMIT_ACCOUNTS_STORE_KEY}`]);
		});

		it("writes the whole list under the accounts key and saves", async () => {
			const { calls, store } = fakeLimitStore(undefined);
			const accounts = [account("a"), account("b")];

			await writeLimitAccounts(store, accounts);
			expect(calls).toEqual([
				`set:${LIMIT_ACCOUNTS_STORE_KEY}:${JSON.stringify(accounts)}`,
				"save",
			]);
		});
	});
});
