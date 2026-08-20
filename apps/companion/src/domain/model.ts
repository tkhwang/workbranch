export const PLAN_STATUSES = [
	"todo",
	"planning",
	"in-progress",
	"review",
	"blocked",
	"done",
] as const;
export type PlanStatus = (typeof PLAN_STATUSES)[number];

export const TASK_STAGES = ["plan", "execution", "review"] as const;
export type TaskStage = (typeof TASK_STAGES)[number];

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
	readonly activityAvailable: boolean;
	readonly ahead: number;
	readonly behind: number;
	readonly changedFiles: number;
	readonly lastCommitSubject: string;
	readonly lastCommitAt: number;
};

export type Task = {
	readonly name: string;
	readonly path: string;
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
	const firstIncompletePlan = task.plans.find((plan) => plan.status !== "done");
	return firstIncompletePlan ?? task.plans.at(-1);
}

export function taskStatus(task: Task): PlanStatus {
	return activePlan(task)?.status ?? "todo";
}

export function taskStage(task: Task): TaskStage | undefined {
	switch (taskStatus(task)) {
		case "planning":
			return "plan";
		case "in-progress":
		case "blocked":
			return "execution";
		case "review":
			return "review";
		case "todo":
		case "done":
			return undefined;
	}
}

export type DerivedStage = {
	readonly stage: TaskStage | undefined;
	readonly derived: boolean;
};

export function deriveStage(task: Task): DerivedStage {
	const declared = taskStage(task);
	if (declared !== undefined) {
		return { stage: declared, derived: false };
	}
	const status = taskStatus(task);
	const hasActivity = task.repos.some((repo) => repo.dirty || repo.ahead > 0);
	if ((status === "todo" || status === "done") && hasActivity) {
		return { stage: "execution", derived: true };
	}
	return { stage: undefined, derived: false };
}

export function taskProgress(task: Task): {
	readonly done: number;
	readonly total: number;
} {
	const plan = activePlan(task);
	return { done: plan?.progressDone ?? 0, total: plan?.progressTotal ?? 0 };
}
