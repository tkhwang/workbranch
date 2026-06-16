export const PLAN_STATUSES = [
	"todo",
	"planning",
	"in-progress",
	"review",
	"blocked",
	"done",
] as const;
export type PlanStatus = (typeof PLAN_STATUSES)[number];

export type Step = {
	readonly text: string;
	readonly checked: boolean;
	readonly depth: number;
	readonly children: readonly Step[];
};

export type Plan = {
	readonly title: string;
	readonly index: number;
	readonly status: PlanStatus;
	readonly steps: readonly Step[];
	readonly progressDone: number;
	readonly progressTotal: number;
	readonly currentItem: string;
};

export type Repo = {
	readonly name: string;
	readonly branch: string;
	readonly dirty: boolean;
};

export type Task = {
	readonly name: string;
	readonly path: string;
	readonly memoTitle: string;
	readonly notiCount: number;
	readonly plans: readonly Plan[];
	readonly repos: readonly Repo[];
	readonly updatedAt: number;
};

export type Project = {
	readonly name: string;
	readonly root: string;
	readonly tasks: readonly Task[];
};

export type GlobalError = {
	readonly root: string;
	readonly message: string;
};

export type GlobalState = {
	readonly projects: readonly Project[];
	readonly errors: readonly GlobalError[];
};

export function isPlanStatus(value: string): value is PlanStatus {
	switch (value) {
		case "todo":
		case "planning":
		case "in-progress":
		case "review":
		case "blocked":
		case "done":
			return true;
		default:
			return false;
	}
}

export function activePlan(task: Task): Plan | undefined {
	return task.plans.find((plan) => plan.status !== "done") ?? task.plans[0];
}

export function taskStatus(task: Task): PlanStatus {
	return activePlan(task)?.status ?? "todo";
}

export function taskProgress(task: Task): {
	readonly done: number;
	readonly total: number;
} {
	const plan = activePlan(task);
	return { done: plan?.progressDone ?? 0, total: plan?.progressTotal ?? 0 };
}
