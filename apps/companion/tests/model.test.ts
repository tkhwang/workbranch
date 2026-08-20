import { describe, expect, it } from "vitest";
import { buildBoardModel } from "../src/application/state";
import type { GlobalState, PlanStatus, Task } from "../src/domain/model";
import {
	activePlan,
	deriveStage,
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

	it.each([
		["todo", DIRTY_REPO, "execution", true],
		["done", AHEAD_REPO, "execution", true],
		[
			"todo",
			{ ...DIRTY_REPO, dirty: false, changedFiles: 0 },
			undefined,
			false,
		],
		["done", { ...AHEAD_REPO, ahead: 0 }, undefined, false],
		["review", DIRTY_REPO, "review", false],
	] as const)("derives %s with repository evidence as %s", (status, repo, stage, derived) => {
		expect(deriveStage(taskWithStatus(status, status, 1, 0, [repo]))).toEqual({
			stage,
			derived,
		});
	});
});

describe("buildBoardModel", () => {
	it("sorts active lifecycle cards by recency with other tasks retained", () => {
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

		expect(board.cards.map((card) => card.task.name)).toEqual([
			"done-active",
			"executing",
			"reviewing",
			"planning-new",
			"blocked",
		]);
		expect(board.cards[0]).toMatchObject({
			project: "alpha",
			root: "/tmp/alpha",
			stage: "execution",
			derived: true,
		});
		expect(board.cards[2]?.stage).toBe("review");
		expect(board.cards[3]).toMatchObject({
			stage: "plan",
			blocked: false,
			derived: false,
			task: { notiCount: 3 },
		});
		expect(board.cards[4]?.blocked).toBe(true);
		expect(board.otherTasks.map((card) => card.task.name)).toEqual([
			"todo-old",
		]);
	});
});
