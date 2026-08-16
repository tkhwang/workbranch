import type { GlobalState, Task, TaskStage } from "../domain/model";
import { activePlan, taskStage, taskStatus } from "../domain/model";

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

export type BoardCard = {
	readonly project: string;
	readonly root: string;
	readonly task: Task;
	readonly stage: TaskStage;
	readonly blocked: boolean;
};

export type StageColumn = {
	readonly stage: TaskStage;
	readonly label: "PLAN" | "EXECUTION" | "REVIEW";
	readonly cards: readonly BoardCard[];
};

export type BoardModel = {
	readonly columns: readonly StageColumn[];
};

const STAGE_COLUMNS: readonly Pick<StageColumn, "stage" | "label">[] = [
	{ stage: "plan", label: "PLAN" },
	{ stage: "execution", label: "EXECUTION" },
	{ stage: "review", label: "REVIEW" },
];

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

export function buildBoardModel(state: GlobalState): BoardModel {
	const cards: BoardCard[] = [];
	for (const project of state.projects) {
		for (const task of project.tasks) {
			const stage = taskStage(task);
			if (stage === undefined) continue;
			cards.push({
				project: project.name,
				root: project.root,
				task,
				stage,
				blocked: taskStatus(task) === "blocked",
			});
		}
	}

	return {
		columns: STAGE_COLUMNS.map(({ stage, label }) => ({
			stage,
			label,
			cards: cards
				.filter((card) => card.stage === stage)
				.sort((left, right) => right.task.updatedAt - left.task.updatedAt),
		})),
	};
}

export function currentItem(task: Task): string {
	return activePlan(task)?.currentItem ?? "";
}
