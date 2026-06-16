import type { GlobalState, Task } from "../domain/model";
import { activePlan, taskStatus } from "../domain/model";

export type TaskRow = {
	readonly project: string;
	readonly root: string;
	readonly task: Task;
	readonly expanded: boolean;
};

export type MenuModel = {
	readonly title: string;
	readonly rows: readonly TaskRow[];
	readonly errors: GlobalState["errors"];
};

export function buildMenuModel(state: GlobalState): MenuModel {
	const rows = state.projects.flatMap((project) =>
		project.tasks.map((task) => ({
			project: project.name,
			root: project.root,
			task,
			expanded: task.notiCount > 0 || taskStatus(task) === "blocked",
		})),
	);
	const active = rows.filter(
		(row) => taskStatus(row.task) === "in-progress",
	).length;
	const blocked = rows.filter(
		(row) => taskStatus(row.task) === "blocked",
	).length;
	const notifications = rows.reduce(
		(count, row) => count + row.task.notiCount,
		0,
	);
	const parts = [
		active > 0 ? `▶${active}` : "",
		blocked > 0 ? `⚠${blocked}` : "",
		notifications > 0 ? `🔔${notifications}` : "",
	].filter(Boolean);
	return {
		title: parts.length > 0 ? parts.join(" ") : "⎇ 0",
		rows: rows.sort(
			(left, right) => right.task.updatedAt - left.task.updatedAt,
		),
		errors: state.errors,
	};
}

export function currentItem(task: Task): string {
	return activePlan(task)?.currentItem ?? "";
}
