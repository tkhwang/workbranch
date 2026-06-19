import type { GlobalState, Task } from "../domain/model";
import { activePlan, taskStatus } from "../domain/model";

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

function latestUpdate(group: ProjectGroup): number {
	return group.rows.reduce((max, row) => Math.max(max, row.task.updatedAt), 0);
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

export function currentItem(task: Task): string {
	return activePlan(task)?.currentItem ?? "";
}
