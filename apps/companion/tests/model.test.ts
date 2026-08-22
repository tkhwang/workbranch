import { describe, expect, it } from "vitest";
import { buildMatrixModel } from "../src/application/state";
import type { GlobalState, PlanStatus, Task } from "../src/domain/model";
import {
	activePlan,
	matrixPlacement,
	taskProgress,
	taskStatus,
} from "../src/domain/model";

const completedMultiPlanTask: Task = {
	name: "completed-task",
	path: "/tmp/workbranch/completed-task",
	notiCount: 0,
	updatedAt: 10,
	repos: [],
	plans: [
		{
			title: "Old completed plan",
			index: 0,
			status: "done",
			steps: [],
			progressDone: 1,
			progressTotal: 1,
			currentItem: "",
		},
		{
			title: "Latest completed plan",
			index: 1,
			status: "done",
			steps: [],
			progressDone: 3,
			progressTotal: 3,
			currentItem: "",
		},
	],
};

function taskWithStatus(
	name: string,
	status: PlanStatus,
	updatedAt: number,
	notiCount = 0,
	repos: Task["repos"] = [],
): Task {
	return {
		name,
		path: `/tmp/workbranch/${name}`,
		notiCount,
		updatedAt,
		repos,
		plans: [
			{
				title: name,
				index: 0,
				status,
				steps: [],
				progressDone: status === "done" ? 1 : 0,
				progressTotal: 1,
				currentItem: "",
			},
		],
	};
}

const DIRTY_REPO: Task["repos"][number] = {
	name: "backend",
	branch: "feature/task",
	dirty: true,
	activityAvailable: true,
	ahead: 0,
	behind: 0,
	changedFiles: 2,
	lastCommitSubject: "implement task",
	lastCommitAt: 20,
};

const AHEAD_REPO: Task["repos"][number] = {
	...DIRTY_REPO,
	dirty: false,
	ahead: 1,
	changedFiles: 0,
};

describe("activePlan", () => {
	it("falls back to the last plan when every plan is done", () => {
		expect(activePlan(completedMultiPlanTask)?.title).toBe(
			"Latest completed plan",
		);
		expect(taskStatus(completedMultiPlanTask)).toBe("done");
		expect(taskProgress(completedMultiPlanTask)).toEqual({ done: 3, total: 3 });
	});
});

describe("matrixPlacement", () => {
	it.each([
		["planning", "plan"],
		["in-progress", "execution"],
		["review", "review"],
	] as const)("places %s in the %s column", (status, column) => {
		expect(matrixPlacement(taskWithStatus(status, status, 1))).toEqual({
			column,
			blocked: false,
			derived: false,
		});
	});

	it("returns no placement for clean todo and done tasks", () => {
		expect(matrixPlacement(taskWithStatus("todo", "todo", 1))).toBeUndefined();
		expect(matrixPlacement(taskWithStatus("done", "done", 1))).toBeUndefined();
		expect(
			matrixPlacement(
				taskWithStatus("todo", "todo", 1, 0, [
					{ ...DIRTY_REPO, dirty: false, changedFiles: 0 },
				]),
			),
		).toBeUndefined();
		expect(
			matrixPlacement(
				taskWithStatus("done", "done", 1, 0, [{ ...AHEAD_REPO, ahead: 0 }]),
			),
		).toBeUndefined();
	});

	it("keeps declared review in place despite repository activity", () => {
		expect(
			matrixPlacement(taskWithStatus("review", "review", 1, 0, [DIRTY_REPO])),
		).toEqual({ column: "review", blocked: false, derived: false });
	});

	it("places blocked in execution with the blocked flag", () => {
		expect(matrixPlacement(taskWithStatus("blocked", "blocked", 1))).toEqual({
			column: "execution",
			blocked: true,
			derived: false,
		});
	});

	it("derives execution placement from repository evidence", () => {
		expect(
			matrixPlacement(taskWithStatus("todo", "todo", 1, 0, [DIRTY_REPO])),
		).toEqual({ column: "execution", blocked: false, derived: true });
		expect(
			matrixPlacement(taskWithStatus("done", "done", 1, 0, [AHEAD_REPO])),
		).toEqual({ column: "execution", blocked: false, derived: true });
	});
});

describe("buildMatrixModel", () => {
	it("orders lane rows execution → review → plan, then by recency", () => {
		const state: GlobalState = {
			projects: [
				{
					name: "alpha",
					root: "/tmp/alpha",
					tasks: [
						taskWithStatus("todo-old", "todo", 10),
						taskWithStatus("planning-new", "planning", 40, 3),
						taskWithStatus("blocked", "blocked", 30),
						taskWithStatus("done-active", "done", 100, 0, [DIRTY_REPO]),
						taskWithStatus("executing", "in-progress", 80),
						taskWithStatus("reviewing", "review", 70),
						taskWithStatus("done-clean", "done", 5),
					],
				},
			],
			errors: [],
		};

		const matrix = buildMatrixModel(state);

		expect(matrix.lanes).toHaveLength(1);
		expect(matrix.activeCount).toBe(5);
		expect(matrix.lanes[0]?.rows.map((row) => row.task.name)).toEqual([
			"done-active",
			"executing",
			"blocked",
			"reviewing",
			"planning-new",
		]);
		expect(matrix.others.map((other) => other.task.name)).toEqual([
			"todo-old",
			"done-clean",
		]);
		expect(matrix.lanes[0]?.rows[0]).toMatchObject({
			project: "alpha",
			root: "/tmp/alpha",
			column: "execution",
			derived: true,
		});
		expect(matrix.lanes[0]?.rows[2]).toMatchObject({
			column: "execution",
			blocked: true,
		});
		expect(matrix.lanes[0]?.rows[4]).toMatchObject({
			column: "plan",
			task: { notiCount: 3 },
		});
	});

	it("orders lanes by the latest task or repository activity", () => {
		const recentRepositoryActivity = {
			...DIRTY_REPO,
			dirty: false,
			changedFiles: 0,
			lastCommitAt: 300,
		};
		const state: GlobalState = {
			projects: [
				{
					name: "beta",
					root: "/tmp/beta",
					tasks: [taskWithStatus("recent-brief", "in-progress", 200)],
				},
				{
					name: "alpha",
					root: "/tmp/alpha",
					tasks: [
						taskWithStatus("recent-repository", "planning", 10, 0, [
							recentRepositoryActivity,
						]),
					],
				},
				{ name: "empty", root: "/tmp/empty", tasks: [] },
			],
			errors: [],
		};

		const matrix = buildMatrixModel(state);

		expect(matrix.lanes.map((lane) => lane.project)).toEqual(["alpha", "beta"]);
	});
});
