import type { WorkbranchChecklistItem } from "@workbranch/contract";
import type { GlobalState, Plan, Project, Step, Task } from "../domain/model";
import { taskProgress, taskStatus } from "../domain/model";

export type ActivityEvent = {
	readonly v: 1;
	readonly editedAt: number;
	readonly observedAt: number;
	readonly root: string;
	readonly project: string;
	readonly task: string;
	readonly plan: string;
	readonly planIndex: number;
	readonly planTitle: string;
	readonly planStatus: string;
	readonly status: string;
	readonly taskProgressDone: number;
	readonly taskProgressTotal: number;
	readonly progressDone: number;
	readonly progressTotal: number;
	readonly items?: readonly WorkbranchChecklistItem[];
};

export type PlanReport = {
	readonly key: string;
	readonly project: string;
	readonly task: string;
	readonly plan: string;
	readonly seconds: number;
	readonly latestItems: readonly WorkbranchChecklistItem[];
};

export type ActivityRefreshDeps = {
	readonly refresh: () => Promise<GlobalState>;
	readonly append: (events: readonly ActivityEvent[]) => Promise<void>;
	readonly now: () => number;
};

export const IDLE_GAP_SECONDS = 25 * 60;
export const LEAD_PAD_SECONDS = 5 * 60;

function eventKey(event: ActivityEvent): string {
	return [
		event.root,
		event.project,
		event.task,
		event.plan,
		String(event.planIndex),
	].join("\u0000");
}

function reportKey(event: ActivityEvent): string {
	return [event.project, event.task, event.plan].join(" / ");
}

function nextSeconds(previous: ActivityEvent, current: ActivityEvent): number {
	const gap = Math.max(0, current.observedAt - previous.observedAt);
	return gap <= IDLE_GAP_SECONDS ? gap : LEAD_PAD_SECONDS;
}

function projectsByRoot(projects: readonly Project[]): Map<string, Project> {
	return new Map(projects.map((project) => [project.root, project]));
}

function tasksByName(tasks: readonly Task[]): Map<string, Task> {
	return new Map(tasks.map((task) => [task.name, task]));
}

function planIdentity(plan: Plan): string {
	return `${plan.index}\u0000${plan.title}`;
}

function plansByIdentity(plans: readonly Plan[]): Map<string, Plan> {
	return new Map(plans.map((plan) => [planIdentity(plan), plan]));
}

function flattenStepItems(
	steps: readonly Step[],
): readonly WorkbranchChecklistItem[] {
	const items: WorkbranchChecklistItem[] = [];
	const visit = (step: Step): void => {
		items.push({ text: step.text, checked: step.checked, depth: step.depth });
		for (const child of step.children) {
			visit(child);
		}
	};
	for (const step of steps) {
		visit(step);
	}
	return items;
}

function planSignature(plan: Plan): string {
	return JSON.stringify({
		title: plan.title,
		index: plan.index,
		status: plan.status,
		progressDone: plan.progressDone,
		progressTotal: plan.progressTotal,
		currentItem: plan.currentItem,
		items: flattenStepItems(plan.steps),
	});
}

function planChanged(current: Plan, previous: Plan | undefined): boolean {
	return (
		previous === undefined || planSignature(current) !== planSignature(previous)
	);
}

function activityEventForPlan(
	project: Project,
	task: Task,
	plan: Plan,
	observedAt: number,
): ActivityEvent {
	const progress = taskProgress(task);
	return {
		v: 1,
		editedAt: task.updatedAt,
		observedAt,
		root: project.root,
		project: project.name,
		task: task.name,
		plan: plan.title,
		planIndex: plan.index,
		planTitle: plan.title,
		planStatus: plan.status,
		status: taskStatus(task),
		taskProgressDone: progress.done,
		taskProgressTotal: progress.total,
		progressDone: plan.progressDone,
		progressTotal: plan.progressTotal,
		items: flattenStepItems(plan.steps),
	};
}

export function activityEventsForRefresh(
	previousProjects: readonly Project[],
	nextProjects: readonly Project[],
	observedAt: number,
): readonly ActivityEvent[] {
	const previousByRoot = projectsByRoot(previousProjects);
	const events: ActivityEvent[] = [];
	for (const project of nextProjects) {
		const previousProject = previousByRoot.get(project.root);
		if (previousProject === undefined) {
			continue;
		}
		const previousTasks = tasksByName(previousProject.tasks);
		for (const task of project.tasks) {
			const previousTask = previousTasks.get(task.name);
			const previousPlans = plansByIdentity(previousTask?.plans ?? []);
			for (const plan of task.plans) {
				const previousPlan = previousPlans.get(planIdentity(plan));
				if (planChanged(plan, previousPlan)) {
					events.push(activityEventForPlan(project, task, plan, observedAt));
				}
			}
		}
	}
	return events;
}

function mergeProjectsByRoot(
	previous: Map<string, Project>,
	projects: readonly Project[],
): Map<string, Project> {
	const merged = new Map(previous);
	for (const project of projects) {
		merged.set(project.root, project);
	}
	return merged;
}

export function createActivityRefresh(
	deps: ActivityRefreshDeps,
): () => Promise<GlobalState> {
	let previousByRoot = new Map<string, Project>();
	let queue = Promise.resolve();
	const runRefresh = async (): Promise<GlobalState> => {
		const state = await deps.refresh();
		const previousProjects = [...previousByRoot.values()];
		const events = activityEventsForRefresh(
			previousProjects,
			state.projects,
			deps.now(),
		);
		if (events.length > 0) {
			await deps.append(events);
		}
		previousByRoot = mergeProjectsByRoot(previousByRoot, state.projects);
		return state;
	};
	return () => {
		const result = queue.then(runRefresh);
		queue = result.then(
			() => undefined,
			() => undefined,
		);
		return result;
	};
}

export function buildPlanReport(
	events: readonly ActivityEvent[],
): readonly PlanReport[] {
	const sorted = [...events].sort(
		(left, right) => left.observedAt - right.observedAt,
	);
	const secondsByKey = new Map<string, number>();
	const latestByKey = new Map<string, ActivityEvent>();
	let previous: ActivityEvent | undefined;

	for (const event of sorted) {
		const key = eventKey(event);
		latestByKey.set(key, event);
		if (previous && eventKey(previous) === key) {
			secondsByKey.set(
				key,
				(secondsByKey.get(key) ?? 0) + nextSeconds(previous, event),
			);
		}
		previous = event;
	}

	return [...latestByKey.entries()].map(([key, event]) => ({
		key,
		project: event.project,
		task: event.task,
		plan: reportKey(event),
		seconds: secondsByKey.get(key) ?? 0,
		latestItems: event.items ?? [],
	}));
}
