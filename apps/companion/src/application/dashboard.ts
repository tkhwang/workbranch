// What the full-screen dashboard shows (COMP001 R8, R9, R11): the board's
// three live columns, built by the same view model as the menu bar board, with
// the same session text the menu bar card shows. That text is what the agent
// runtime stored: clipped, with credential-like excerpts already omitted.
import type { AgentSession, GlobalState, Repo } from "../domain/model";
import { buildMainViewModel, type MainTaskRow } from "./state";

export const DASHBOARD_COLUMNS = ["waiting", "running", "finished"] as const;
export type DashboardColumnKey = (typeof DASHBOARD_COLUMNS)[number];

/** The lead session's latest words, as on the menu bar card. */
export type DashboardDetail = {
	/** "activity": the tool it runs or waits on; "response": its last answer. */
	readonly kind: "activity" | "response";
	readonly text: string;
};

/** Working-tree state summed over a task's repos. */
export type DashboardChanges = {
	readonly dirty: boolean;
	/** Changed files in the dirty repos that could count them. */
	readonly files: number;
	readonly ahead: number;
	readonly behind: number;
};

/** How a finished turn ended, when it did not end normally. */
export type DashboardOutcome = "error" | "interrupted";

export type DashboardCard = {
	readonly key: string;
	readonly task: string;
	/** The first repo, with "+n" when the task spans more. */
	readonly repo: string | undefined;
	/** The branch the task's repos share, else the first repo's. */
	readonly branch: string | undefined;
	readonly agent: AgentSession["provider"] | undefined;
	/** Epoch seconds when the lead session entered its state. */
	readonly since: number;
	/** The wait reason code of a waiting session, e.g. "permission". */
	readonly reason: string | undefined;
	/** The prompt that started the lead session's turn. */
	readonly prompt: string | undefined;
	readonly detail: DashboardDetail | undefined;
	readonly outcome: DashboardOutcome | undefined;
	readonly changes: DashboardChanges;
	readonly notifications: number;
};

export type DashboardColumn = {
	readonly key: DashboardColumnKey;
	readonly count: number;
	readonly cards: readonly DashboardCard[];
	/** Tasks in this column beyond the cards shown. */
	readonly more: number;
};

export type DashboardModel = {
	readonly columns: readonly DashboardColumn[];
	readonly counts: Readonly<Record<DashboardColumnKey, number>>;
	/** Tasks in any live column: the header's "활성 세션" total. */
	readonly active: number;
};

function detailOf(
	lead: AgentSession | undefined,
	column: DashboardColumnKey,
): DashboardDetail | undefined {
	if (lead === undefined) return undefined;
	// A finished turn shows its last answer; otherwise the tool, as on the board.
	if (column === "finished" && lead.response !== "")
		return { kind: "response", text: lead.response };
	return lead.activity === ""
		? undefined
		: { kind: "activity", text: lead.activity };
}

function outcomeOf(
	lead: AgentSession | undefined,
	column: DashboardColumnKey,
): DashboardOutcome | undefined {
	if (column !== "finished") return undefined;
	return lead?.outcome === "error" || lead?.outcome === "interrupted"
		? lead.outcome
		: undefined;
}

function changesOf(repos: readonly Repo[]): DashboardChanges {
	return repos.reduce<DashboardChanges>(
		(sum, repo) => ({
			dirty: sum.dirty || repo.dirty,
			files:
				sum.files +
				(repo.dirty && repo.activityAvailable ? repo.changedFiles : 0),
			ahead: sum.ahead + repo.ahead,
			behind: sum.behind + repo.behind,
		}),
		{ dirty: false, files: 0, ahead: 0, behind: 0 },
	);
}

function toCard(row: MainTaskRow, column: DashboardColumnKey): DashboardCard {
	const lead = row.sessions[0];
	const [first, ...rest] = row.repos;
	const shared =
		first !== undefined && rest.every((repo) => repo.branch === first.branch);
	return {
		key: row.key,
		task: row.task.name,
		repo:
			first === undefined
				? undefined
				: rest.length === 0
					? first.name
					: `${first.name} +${rest.length}`,
		branch: shared ? first.branch : first?.branch,
		agent: lead?.provider,
		since: lead?.stateChangedAt ?? row.latestActivityAt,
		reason: column === "waiting" && lead?.reason ? lead.reason : undefined,
		prompt: lead?.prompt ? lead.prompt : undefined,
		detail: detailOf(lead, column),
		outcome: outcomeOf(lead, column),
		changes: changesOf(row.repos),
		notifications: row.task.notiCount,
	};
}

export function buildDashboardModel(
	state: GlobalState,
	sessions: readonly AgentSession[],
	cardsPerColumn: number,
): DashboardModel {
	const { stageGroups } = buildMainViewModel(state, sessions);
	const columns = DASHBOARD_COLUMNS.map((key): DashboardColumn => {
		const rows = stageGroups.find((group) => group.column === key)?.rows ?? [];
		return {
			key,
			count: rows.length,
			cards: rows.slice(0, cardsPerColumn).map((row) => toCard(row, key)),
			more: Math.max(0, rows.length - cardsPerColumn),
		};
	});
	return {
		columns,
		counts: {
			waiting: columns[0]?.count ?? 0,
			running: columns[1]?.count ?? 0,
			finished: columns[2]?.count ?? 0,
		},
		active: columns.reduce((sum, column) => sum + column.count, 0),
	};
}
