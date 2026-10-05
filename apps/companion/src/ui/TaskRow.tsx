import type { BaseRepo, Repo, Task } from "../domain/model";

const TASK_ACTION_KINDS = ["ide", "terminal", "finder"] as const;

export type TaskActionKind = (typeof TASK_ACTION_KINDS)[number];

export type TaskRowAction = {
	readonly kind: TaskActionKind;
	readonly label: string;
	readonly ariaLabel: string;
	readonly disabled: boolean;
};

const TASK_ACTION_LABELS: Record<TaskActionKind, string> = {
	ide: "IDE",
	terminal: "Terminal",
	finder: "Finder",
};

export type TaskActionHandler = (
	root: string,
	task: Task,
	kind: TaskActionKind,
) => void;

function actionAriaLabel(kind: TaskActionKind, taskName: string): string {
	switch (kind) {
		case "ide":
			return "open " + taskName + " in IDE";
		case "terminal":
			return "open " + taskName + " in terminal";
		case "finder":
			return "open " + taskName + " in Finder";
	}
}

export function taskActionsFor(task: Task): readonly TaskRowAction[] {
	return TASK_ACTION_KINDS.map((kind) => ({
		kind,
		label: TASK_ACTION_LABELS[kind],
		ariaLabel: actionAriaLabel(kind, task.name),
		disabled: kind === "ide" && task.repos.length === 0,
	}));
}

export function repoFacts(repo: Repo): string {
	const dirtyFact = repo.dirty
		? repo.activityAvailable
			? "DIRTY " +
				repo.changedFiles +
				" " +
				(repo.changedFiles === 1 ? "FILE" : "FILES")
			: "DIRTY"
		: "CLEAN";
	const facts = [dirtyFact];
	if (repo.ahead > 0) facts.push("AHEAD " + repo.ahead);
	if (repo.behind > 0) facts.push("BEHIND " + repo.behind);
	return facts.join(" · ");
}

export type CompactRepoFact = {
	readonly tone: "clean" | "dirty" | "ahead" | "behind";
	readonly label: string;
};

// Narrow kanban cards keep the full repoFacts text in title/aria-label.
// CLEAN appears only when nothing else does; a missing ● already means clean.
export function compactRepoFacts(repo: Repo): readonly CompactRepoFact[] {
	const facts: CompactRepoFact[] = [];
	if (repo.dirty)
		facts.push({
			tone: "dirty",
			label: repo.activityAvailable ? "●" + repo.changedFiles : "●",
		});
	if (repo.ahead > 0) facts.push({ tone: "ahead", label: "↑" + repo.ahead });
	if (repo.behind > 0) facts.push({ tone: "behind", label: "↓" + repo.behind });
	return facts.length > 0 ? facts : [{ tone: "clean", label: "CLEAN" }];
}

export function baseRepoFacts(repo: BaseRepo): string {
	if (repo.inspectionError !== null) return "UNAVAILABLE";
	if (!repo.present) return "MISSING";

	const facts = [
		repo.dirty
			? `DIRTY ${repo.changedFiles} ${repo.changedFiles === 1 ? "FILE" : "FILES"}`
			: "CLEAN",
	];
	if (repo.ahead > 0) facts.push(`AHEAD ${repo.ahead}`);
	if (repo.behind > 0) facts.push(`BEHIND ${repo.behind}`);
	if (!repo.remoteAvailable) facts.push("NO REMOTE");
	if (repo.branch !== repo.baseBranch) {
		facts.push(`EXPECTED ${repo.baseBranch}`);
	}
	return facts.join(" · ");
}

export function formatRelativeTime(
	timestamp: number,
	nowSeconds: number,
): string {
	if (timestamp <= 0) return "";
	const elapsed = Math.max(0, nowSeconds - timestamp);
	if (elapsed < 60) return "now";
	if (elapsed < 60 * 60) return Math.floor(elapsed / 60) + "m";
	if (elapsed < 24 * 60 * 60) return Math.floor(elapsed / (60 * 60)) + "h";
	return Math.floor(elapsed / (24 * 60 * 60)) + "d";
}

export function formatObservedAgo(
	timestamp: number,
	nowSeconds: number,
): string {
	const relative = formatRelativeTime(timestamp, nowSeconds);
	if (relative === "") return "";
	return relative === "now" ? "방금" : relative + " 전";
}
