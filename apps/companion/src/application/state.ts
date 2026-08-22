import type { GlobalState, MatrixColumn, Task } from "../domain/model";
import { matrixPlacement, taskStatus } from "../domain/model";

export type TaskRow = {
	readonly project: string;
	readonly root: string;
	readonly task: Task;
	readonly expanded: boolean;
};

export type ProjectGroup = {
	readonly project: string;
	readonly root: string;
	readonly rows: readonly TaskRow[];
};

export type MenuSummary = {
	readonly projectCount: number;
	readonly taskCount: number;
	readonly active: number;
	readonly blocked: number;
	readonly notifications: number;
};

export type MenuModel = {
	readonly summary: MenuSummary;
	readonly groups: readonly ProjectGroup[];
	readonly errors: GlobalState["errors"];
};

export type MatrixRow = {
	readonly project: string;
	readonly root: string;
	readonly task: Task;
	readonly column: MatrixColumn;
	readonly blocked: boolean;
	readonly derived: boolean;
};

export type MatrixLane = {
	readonly project: string;
	readonly root: string;
	readonly rows: readonly MatrixRow[];
};

export type OtherRow = {
	readonly project: string;
	readonly root: string;
	readonly task: Task;
};

export type MatrixModel = {
	readonly lanes: readonly MatrixLane[];
	readonly others: readonly OtherRow[];
	readonly activeCount: number;
};

function latestUpdate(group: ProjectGroup): number {
	return group.rows.reduce((max, row) => Math.max(max, row.task.updatedAt), 0);
}

function latestTaskActivity(task: Task): number {
	return task.repos.reduce(
		(latest, repo) => Math.max(latest, repo.lastCommitAt),
		task.updatedAt,
	);
}

export function buildMenuModel(state: GlobalState): MenuModel {
	const groups = state.projects
		.map((project) => ({
			project: project.name,
			root: project.root,
			rows: project.tasks
				.map((task) => ({
					project: project.name,
					root: project.root,
					task,
					expanded: true,
				}))
				.sort((left, right) => right.task.updatedAt - left.task.updatedAt),
		}))
		.filter((group) => group.rows.length > 0)
		.sort((left, right) => latestUpdate(right) - latestUpdate(left));

	const rows = groups.flatMap((group) => group.rows);
	return {
		summary: {
			projectCount: groups.length,
			taskCount: rows.length,
			active: rows.filter((row) => taskStatus(row.task) === "in-progress")
				.length,
			blocked: rows.filter((row) => taskStatus(row.task) === "blocked").length,
			notifications: rows.reduce((count, row) => count + row.task.notiCount, 0),
		},
		groups,
		errors: state.errors,
	};
}

const MATRIX_COLUMN_ORDER: Record<MatrixColumn, number> = {
	execution: 0,
	review: 1,
	plan: 2,
};

function latestLaneActivity(lane: MatrixLane): number {
	return lane.rows.reduce(
		(latest, row) => Math.max(latest, latestTaskActivity(row.task)),
		0,
	);
}

export function buildMatrixModel(state: GlobalState): MatrixModel {
	const others: OtherRow[] = [];
	const lanes = state.projects
		.map((project) => {
			const rows: MatrixRow[] = [];
			for (const task of project.tasks) {
				const placement = matrixPlacement(task);
				if (placement === undefined) {
					others.push({ project: project.name, root: project.root, task });
					continue;
				}
				rows.push({
					project: project.name,
					root: project.root,
					task,
					...placement,
				});
			}
			return {
				project: project.name,
				root: project.root,
				rows: rows.sort(
					(left, right) =>
						MATRIX_COLUMN_ORDER[left.column] -
							MATRIX_COLUMN_ORDER[right.column] ||
						latestTaskActivity(right.task) - latestTaskActivity(left.task),
				),
			};
		})
		.filter((lane) => lane.rows.length > 0)
		.sort(
			(left, right) => latestLaneActivity(right) - latestLaneActivity(left),
		);

	return {
		lanes,
		others: others.sort(
			(left, right) => right.task.updatedAt - left.task.updatedAt,
		),
		activeCount: lanes.reduce((count, lane) => count + lane.rows.length, 0),
	};
}
