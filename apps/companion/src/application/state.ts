import type {
	AgentSession,
	BaseRepo,
	GlobalState,
	MatrixColumn,
	Repo,
	Task,
} from "../domain/model";
import { MATRIX_COLUMNS } from "../domain/model";
export type MenuSummary = {
	readonly projectCount: number;
	readonly taskCount: number;
	readonly active: number;
	readonly blocked: number;
	readonly notifications: number;
};
export type MenuModel = {
	readonly summary: MenuSummary;
	readonly errors: GlobalState["errors"];
};
export type MainRole = MatrixColumn | "idle";
export type MainTaskRow = {
	readonly key: string;
	readonly project: string;
	readonly root: string;
	readonly task: Task;
	readonly repos: readonly Repo[];
	readonly role: MainRole;
	readonly sessions: readonly AgentSession[];
	readonly latestActivityAt: number;
};
export type MainBaseRow = {
	readonly key: string;
	readonly project: string;
	readonly root: string;
	readonly repo: BaseRepo;
	readonly showProject: boolean;
};
export type MainStageGroup = {
	readonly column: MatrixColumn;
	readonly rows: readonly MainTaskRow[];
};
export type MainViewModel = {
	readonly baseRows: readonly MainBaseRow[];
	readonly matrixRows: readonly MainTaskRow[];
	readonly stageGroups: readonly MainStageGroup[];
	readonly idleRows: readonly MainTaskRow[];
	readonly activeCount: number;
	readonly idleCount: number;
};
export function mainTaskKey(root: string, taskName: string): string {
	return `${root}:${taskName}`;
}
export function runtimeRole(sessions: readonly AgentSession[]): MainRole {
	for (const state of ["waiting", "running", "finished"] as const)
		if (sessions.some((s) => s.observation === "observed" && s.state === state))
			return state;
	if (
		sessions.length === 0 ||
		sessions.some((s) => s.observation !== "observed")
	)
		return "unknown";
	return "idle";
}
// Rows with sessions come first, most recent activity first; session-less
// rows have no runtime signal, so they follow in alphabetical order.
export function compareMainTaskRows(a: MainTaskRow, b: MainTaskRow): number {
	const aHasSession = a.sessions.length > 0;
	const bHasSession = b.sessions.length > 0;
	if (aHasSession !== bHasSession) return aHasSession ? -1 : 1;
	if (aHasSession && a.latestActivityAt !== b.latestActivityAt)
		return b.latestActivityAt - a.latestActivityAt;
	return a.task.name.localeCompare(b.task.name) || a.key.localeCompare(b.key);
}
export function buildMainViewModel(
	state: GlobalState,
	sessions: readonly AgentSession[] = [],
): MainViewModel {
	const rows: MainTaskRow[] = state.projects.flatMap((p) =>
		p.tasks.map((task) => {
			const owned = sessions.filter((s) => s.workspace === task.path);
			const role = runtimeRole(owned);
			const ordered = [...owned].sort(
				(a, b) =>
					Number(b.observation === "observed" && b.state === role) -
						Number(a.observation === "observed" && a.state === role) ||
					b.stateChangedAt - a.stateChangedAt ||
					a.sessionId.localeCompare(b.sessionId),
			);
			return {
				key: mainTaskKey(p.root, task.name),
				root: p.root,
				project: p.name,
				task,
				repos: task.repos,
				role,
				sessions: ordered,
				latestActivityAt: Math.max(
					task.updatedAt,
					...owned.map((s) => s.stateChangedAt),
				),
			};
		}),
	);
	rows.sort(compareMainTaskRows);
	const matrixRows = rows.filter((r) => r.role !== "idle");
	const idleRows = rows.filter((r) => r.role === "idle");
	return {
		baseRows: state.projects
			.flatMap((p) =>
				p.baseRepos.map((repo) => ({
					key: `${p.root}:${repo.name}`,
					project: p.name,
					root: p.root,
					repo,
					showProject: state.projects.length > 1,
				})),
			)
			.sort(
				(a, b) =>
					a.project.localeCompare(b.project) ||
					a.repo.name.localeCompare(b.repo.name) ||
					a.key.localeCompare(b.key),
			),
		matrixRows,
		stageGroups: MATRIX_COLUMNS.map((column) => ({
			column,
			rows: matrixRows.filter((r) => r.role === column),
		})),
		idleRows,
		activeCount: matrixRows.length,
		idleCount: idleRows.length,
	};
}
export function buildMenuModel(state: GlobalState): MenuModel {
	const tasks = state.projects.flatMap((p) => p.tasks);
	return {
		summary: {
			projectCount: state.projects.length,
			taskCount: tasks.length,
			active: tasks.length,
			blocked: 0,
			notifications: tasks.reduce((n, t) => n + t.notiCount, 0),
		},
		errors: state.errors,
	};
}
