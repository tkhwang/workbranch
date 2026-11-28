// What the full-screen dashboard shows (COMP001 R8, R9, R11; COMP004 R6,
// R12): the board's three live columns as counts, and those same tasks as
// rings placed by how many are live. The board's view model decides which
// tasks are live and in which column, so the dashboard and the menu bar
// always agree.
import type { AgentSession, GlobalState } from "../domain/model";
import { type DashboardLayout, dashboardLayout } from "./dashboardLayout";
import { buildRing, type RingModel } from "./ring";
import { buildMainViewModel } from "./state";

export const DASHBOARD_COLUMNS = ["waiting", "running", "finished"] as const;
export type DashboardColumnKey = (typeof DASHBOARD_COLUMNS)[number];

export type DashboardModel = {
	readonly counts: Readonly<Record<DashboardColumnKey, number>>;
	/** Tasks in any live column: the header's "활성 세션" total. */
	readonly active: number;
	readonly layout: DashboardLayout<RingModel>;
};

/**
 * `now` is epoch seconds. Rings carry file names, the current activity and
 * the newest message only with `showDetails` (Settings › Show work details).
 */
export function buildDashboardModel(
	state: GlobalState,
	sessions: readonly AgentSession[],
	now: number,
	showDetails = false,
): DashboardModel {
	const { stageGroups } = buildMainViewModel(state, sessions);
	const groups = DASHBOARD_COLUMNS.map((key) => ({
		state: key,
		rows: stageGroups.find((group) => group.column === key)?.rows ?? [],
	}));
	const [waiting, running, finished] = groups.map((group) => group.rows.length);
	return {
		counts: {
			waiting: waiting ?? 0,
			running: running ?? 0,
			finished: finished ?? 0,
		},
		active: groups.reduce((sum, group) => sum + group.rows.length, 0),
		layout: dashboardLayout(
			groups.flatMap((group) =>
				group.rows.map((row) => buildRing(row, group.state, now, showDetails)),
			),
		),
	};
}
