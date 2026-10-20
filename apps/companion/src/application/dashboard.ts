// What the full-screen dashboard shows (COMP001 R8, R9, R11): the board's
// three live columns as counts, and those same tasks on a timeline built from
// the runtime's transition log. The board's view model decides which tasks are
// live and in which column, so the dashboard and the menu bar always agree.
import type { AgentSession, GlobalState } from "../domain/model";
import { buildMainViewModel } from "./state";
import { buildTimeline, type TimelineModel } from "./timeline";

export const DASHBOARD_COLUMNS = ["waiting", "running", "finished"] as const;
export type DashboardColumnKey = (typeof DASHBOARD_COLUMNS)[number];

export type DashboardModel = {
	readonly counts: Readonly<Record<DashboardColumnKey, number>>;
	/** Tasks in any live column: the header's "활성 세션" total. */
	readonly active: number;
	readonly timeline: TimelineModel;
};

/** `now` is epoch seconds; `maxRows` caps the timeline, the rest is "+n". */
export function buildDashboardModel(
	state: GlobalState,
	sessions: readonly AgentSession[],
	now: number,
	maxRows: number,
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
		timeline: buildTimeline(groups, now, maxRows),
	};
}
