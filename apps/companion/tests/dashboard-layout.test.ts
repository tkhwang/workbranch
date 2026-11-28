import { describe, expect, it } from "vitest";
import { dashboardLayout } from "../src/application/dashboardLayout";
import type { HistoryState } from "../src/application/taskHistory";

type Item = { readonly key: string; readonly state: HistoryState };

// Already in the board's order: waiting, running, finished.
function tasks(waiting: number, running: number, finished: number): Item[] {
	return [
		...Array.from({ length: waiting }, (_, i) => ({
			key: `w${i}`,
			state: "waiting" as const,
		})),
		...Array.from({ length: running }, (_, i) => ({
			key: `r${i}`,
			state: "running" as const,
		})),
		...Array.from({ length: finished }, (_, i) => ({
			key: `f${i}`,
			state: "finished" as const,
		})),
	];
}

const keys = (items: readonly Item[]) => items.map((item) => item.key);

describe("dashboardLayout", () => {
	it("is empty without tasks", () => {
		expect(dashboardLayout([])).toEqual({
			mode: "large",
			columns: 0,
			rings: [],
			overflow: [],
		});
	});

	it("fills up to three large rings, ended tasks taking the free places", () => {
		const layout = dashboardLayout(tasks(0, 1, 4));
		expect(layout.mode).toBe("large");
		expect(layout.columns).toBe(3);
		expect(keys(layout.rings)).toEqual(["r0", "f0", "f1"]);
		expect(keys(layout.overflow)).toEqual(["f2", "f3"]);
	});

	it("shows only ended tasks when nothing is live", () => {
		const layout = dashboardLayout(tasks(0, 0, 2));
		expect(layout.mode).toBe("large");
		expect(layout.columns).toBe(2);
		expect(keys(layout.rings)).toEqual(["f0", "f1"]);
	});

	it("keeps three live tasks large and moves every ended one below", () => {
		const layout = dashboardLayout(tasks(1, 2, 2));
		expect(layout.mode).toBe("large");
		expect(keys(layout.rings)).toEqual(["w0", "r0", "r1"]);
		expect(keys(layout.overflow)).toEqual(["f0", "f1"]);
	});

	it("turns four live tasks into a two-by-two grid without ended ones", () => {
		const layout = dashboardLayout(tasks(1, 3, 1));
		expect(layout.mode).toBe("grid");
		expect(layout.columns).toBe(2);
		expect(keys(layout.rings)).toEqual(["w0", "r0", "r1", "r2"]);
		expect(keys(layout.overflow)).toEqual(["f0"]);
	});

	it("uses three columns for five and six live tasks", () => {
		expect(dashboardLayout(tasks(0, 5, 0)).columns).toBe(3);
		const six = dashboardLayout(tasks(2, 4, 2));
		expect(six.mode).toBe("grid");
		expect(six.columns).toBe(3);
		expect(six.rings).toHaveLength(6);
		expect(keys(six.overflow)).toEqual(["f0", "f1"]);
	});

	it("draws six live tasks at most; the rest join the line below, live first", () => {
		const layout = dashboardLayout(tasks(1, 6, 1));
		expect(keys(layout.rings)).toEqual(["w0", "r0", "r1", "r2", "r3", "r4"]);
		expect(keys(layout.overflow)).toEqual(["r5", "f0"]);
	});

	it("keeps a waiting task first in every layout", () => {
		for (const [running, finished] of [
			[0, 0],
			[2, 0],
			[3, 2],
			[6, 3],
		]) {
			expect(
				dashboardLayout(tasks(1, running ?? 0, finished ?? 0)).rings[0]?.key,
			).toBe("w0");
		}
	});
});
