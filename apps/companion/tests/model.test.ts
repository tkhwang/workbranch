import { describe, expect, it } from "vitest";
import { buildBoardModel } from "../src/application/state";
import type { GlobalState, PlanStatus, Task } from "../src/domain/model";
import {
	activePlan,
	taskProgress,
	taskStage,
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
): Task {
	return {
		name,
		path: `/tmp/workbranch/${name}`,
		notiCount,
		updatedAt,
		repos: [],
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

describe("activePlan", () => {
	it("falls back to the last plan when every plan is done", () => {
		expect(activePlan(completedMultiPlanTask)?.title).toBe(
			"Latest completed plan",
		);
		expect(taskStatus(completedMultiPlanTask)).toBe("done");
		expect(taskProgress(completedMultiPlanTask)).toEqual({ done: 3, total: 3 });
	});
});

describe("taskStage", () => {
	it.each([
		["todo", undefined],
		["planning", "plan"],
		["in-progress", "execution"],
		["review", "review"],
		["done", undefined],
	] as const)("maps %s to %s", (status, stage) => {
		expect(taskStage(taskWithStatus(status, status, 1))).toBe(stage);
	});

	it("treats blocked as an execution-only pause", () => {
		expect(taskStage(taskWithStatus("blocked", "blocked", 1))).toBe(
			"execution",
		);
	});
});

describe("buildBoardModel", () => {
	it("groups active tasks by stage, newest first, while excluding todo and done", () => {
		const state: GlobalState = {
			projects: [
				{
					name: "alpha",
					root: "/tmp/alpha",
					tasks: [
						taskWithStatus("todo-old", "todo", 10),
						taskWithStatus("planning-new", "planning", 40, 3),
						taskWithStatus("blocked", "blocked", 30),
						taskWithStatus("done", "done", 100),
					],
				},
				{
					name: "beta",
					root: "/tmp/beta",
					tasks: [
						taskWithStatus("executing", "in-progress", 80),
						taskWithStatus("reviewing", "review", 70),
					],
				},
			],
			errors: [],
		};

		const board = buildBoardModel(state);

		expect(board.columns.map((column) => column.stage)).toEqual([
			"plan",
			"execution",
			"review",
		]);
		expect(board.columns[0]?.cards.map((card) => card.task.name)).toEqual([
			"planning-new",
		]);
		expect(board.columns[0]?.cards[0]).toMatchObject({
			project: "alpha",
			root: "/tmp/alpha",
			stage: "plan",
			blocked: false,
			task: { notiCount: 3 },
		});
		expect(board.columns[1]?.cards.map((card) => card.task.name)).toEqual([
			"executing",
			"blocked",
		]);
		expect(board.columns[1]?.cards[1]?.blocked).toBe(true);
		expect(board.columns[2]?.cards.map((card) => card.task.name)).toEqual([
			"reviewing",
		]);
		expect(
			board.columns
				.flatMap((column) => column.cards)
				.map((card) => card.task.name),
		).not.toContain("done");
	});
});
