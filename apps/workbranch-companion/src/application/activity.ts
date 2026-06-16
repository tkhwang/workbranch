import type { WorkbranchChecklistItem } from "@workbranch/contract";

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

const IDLE_GAP_SECONDS = 25 * 60;
const LEAD_PAD_SECONDS = 5 * 60;

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
