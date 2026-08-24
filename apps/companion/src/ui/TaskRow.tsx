import type { CompanionTheme } from "../application/preferences";
import type { Repo, Task } from "../domain/model";
import { activePlan, taskProgress, taskStatus } from "../domain/model";
import { PromptLine } from "./PromptLine";
import { StatusToken } from "./StatusToken";

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

type TaskMetaRowProps = {
	readonly highlighted: boolean;
	readonly nowSeconds: number;
	readonly repos: readonly Repo[];
	readonly root: string;
	readonly task: Task;
	readonly taskKey: string;
	readonly theme: CompanionTheme;
	readonly onAction: TaskActionHandler;
};

function actionAriaLabel(kind: TaskActionKind, taskName: string): string {
	switch (kind) {
		case "ide":
			return `open ${taskName} in IDE`;
		case "terminal":
			return `open ${taskName} in terminal`;
		case "finder":
			return `open ${taskName} in Finder`;
	}
}

export function taskActionsFor(task: Task): readonly TaskRowAction[] {
	return TASK_ACTION_KINDS.map((kind) => ({
		kind,
		label: TASK_ACTION_LABELS[kind],
		ariaLabel: actionAriaLabel(kind, task.name),
		disabled: false,
	}));
}

function repoFacts(repo: Repo): string {
	const dirtyFact = repo.dirty
		? repo.activityAvailable
			? `DIRTY ${repo.changedFiles} ${repo.changedFiles === 1 ? "FILE" : "FILES"}`
			: "DIRTY"
		: "CLEAN";
	const facts = [dirtyFact];
	if (repo.ahead > 0) facts.push(`AHEAD ${repo.ahead}`);
	if (repo.behind > 0) facts.push(`BEHIND ${repo.behind}`);
	return facts.join(" · ");
}

function formatRelativeTime(timestamp: number, nowSeconds: number): string {
	if (timestamp <= 0) return "";
	const elapsed = Math.max(0, nowSeconds - timestamp);
	if (elapsed < 60) return "now";
	if (elapsed < 60 * 60) return `${Math.floor(elapsed / 60)}m`;
	if (elapsed < 24 * 60 * 60) return `${Math.floor(elapsed / (60 * 60))}h`;
	return `${Math.floor(elapsed / (24 * 60 * 60))}d`;
}

function currentWorkText(task: Task): string {
	const plan = activePlan(task);
	if (plan === undefined) return "";
	if (plan.currentItem !== "") return plan.currentItem;
	return plan.title === task.name ? "" : plan.title;
}

function RepoActivityRow({
	nowSeconds,
	repo,
}: {
	readonly nowSeconds: number;
	readonly repo: Repo;
}) {
	const relativeTime = formatRelativeTime(repo.lastCommitAt, nowSeconds);
	const commit =
		repo.lastCommitSubject === ""
			? ""
			: `last commit: ${repo.lastCommitSubject}${relativeTime === "" ? "" : ` · ${relativeTime}`}`;
	return (
		<li className="repo-activity-row">
			<div className="repo-identity">
				<span className={`repo-name${repo.dirty ? " repo-dirty" : ""}`}>
					{repo.name}
					{repo.dirty ? (
						<span aria-label="dirty" className="repo-dot" role="img">
							●
						</span>
					) : null}
				</span>
				<span className="repo-branch-name" title={repo.branch}>
					{repo.branch}
				</span>
			</div>
			<span className="repo-facts">{repoFacts(repo)}</span>
			{commit === "" ? null : (
				<span className="repo-commit" title={repo.lastCommitSubject}>
					{commit}
				</span>
			)}
		</li>
	);
}

export function TaskMetaRow({
	highlighted,
	nowSeconds,
	repos,
	root,
	task,
	taskKey,
	theme,
	onAction,
}: TaskMetaRowProps) {
	const status = taskStatus(task);
	const currentWork = currentWorkText(task);
	const progress = taskProgress(task);
	return (
		<article
			aria-current={highlighted ? "true" : undefined}
			className={`task-meta-row task-${status}`}
			data-highlighted={highlighted ? "true" : "false"}
			data-repository-task={taskKey}
			id={`repository-${encodeURIComponent(taskKey)}`}
		>
			<div className="task-meta-header">
				<div className="task-meta-primary">
					<PromptLine theme={theme}>
						<span className="task-name" title={task.name}>
							{task.name}
						</span>
						<StatusToken status={status} />
					</PromptLine>
					{progress.total > 0 ? (
						<span className="task-progress-summary">
							{progress.done}/{progress.total}
						</span>
					) : null}
				</div>
				{currentWork === "" ? null : (
					<div className="task-current-work">
						<span className="task-current-label">CURRENT</span>
						<span title={currentWork}>{currentWork}</span>
					</div>
				)}
				<div className="task-actions">
					{taskActionsFor(task).map((action) => (
						<button
							aria-label={action.ariaLabel}
							className="task-action"
							disabled={action.disabled}
							key={action.kind}
							onClick={() => onAction(root, task, action.kind)}
							type="button"
						>
							{action.label}
						</button>
					))}
				</div>
			</div>
			<ul
				aria-label={`${task.name} repositories`}
				className="repo-activity-list"
			>
				{repos.map((repo) => (
					<RepoActivityRow
						key={`${repo.name}:${repo.branch}`}
						nowSeconds={nowSeconds}
						repo={repo}
					/>
				))}
			</ul>
		</article>
	);
}
