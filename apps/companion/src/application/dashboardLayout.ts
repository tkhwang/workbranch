// How the lock screen places task rings (COMP004 R6). Live tasks
// (running, or waiting on the user) decide the layout: up to three are drawn
// large, with ended tasks taking any free place; four to six become a
// compact grid of live tasks only. Whatever has no ring joins one line below.
import type { HistoryState } from "./taskHistory";

/** Large rings side by side, at most. */
export const MAX_LARGE_RINGS = 3;
/** Compact rings in the grid, at most. */
export const MAX_GRID_RINGS = 6;

export type DashboardLayout<T> = {
	readonly mode: "large" | "grid";
	/** Rings per row. */
	readonly columns: number;
	readonly rings: readonly T[];
	/** Tasks without a ring, in the input's order. */
	readonly overflow: readonly T[];
};

/**
 * `ordered` comes in the board's order (waiting, running, finished; most
 * recent first within each), so the most urgent task always leads.
 */
export function dashboardLayout<T extends { readonly state: HistoryState }>(
	ordered: readonly T[],
): DashboardLayout<T> {
	const live = ordered.filter((task) => task.state !== "finished");
	const grid = live.length > MAX_LARGE_RINGS;
	const rings = grid
		? live.slice(0, MAX_GRID_RINGS)
		: ordered.slice(0, MAX_LARGE_RINGS);
	const drawn = new Set(rings);
	return {
		mode: grid ? "grid" : "large",
		columns: grid ? (rings.length <= 4 ? 2 : 3) : rings.length,
		rings,
		overflow: ordered.filter((task) => !drawn.has(task)),
	};
}
