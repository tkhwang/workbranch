import { Fragment } from "react";
import { currentItem } from "../application/state";
import type { Step, Task } from "../domain/model";
import { activePlan, taskProgress, taskStatus } from "../domain/model";

const STATUS_META = {
	todo: { icon: "·", label: "Todo" },
	planning: { icon: "○", label: "Planning" },
	"in-progress": { icon: "●", label: "In progress" },
	review: { icon: "◐", label: "Review" },
	blocked: { icon: "!", label: "Blocked" },
	done: { icon: "✓", label: "Done" },
} as const;

const TASK_ACTION_KINDS = [
	"memoEdit",
	"memoClear",
	"notiClear",
	"finder",
	"ide",
	"terminal",
	"copyPath",
] as const;

export type TaskActionKind = (typeof TASK_ACTION_KINDS)[number];

export type TaskRowAction = {
	readonly kind: TaskActionKind;
	readonly label: string;
	readonly ariaLabel: string;
	readonly disabled: boolean;
};

const TASK_ACTION_LABELS: Record<TaskActionKind, string> = {
	memoEdit: "Memo",
	memoClear: "Clear",
	notiClear: "Noti",
	finder: "Finder",
	ide: "IDE",
	terminal: "Terminal",
	copyPath: "Copy",
} as const;

type Props = {
	readonly project: string;
	readonly root: string;
	readonly task: Task;
	readonly expanded: boolean;
	readonly onAction: (root: string, task: Task, kind: TaskActionKind) => void;
};

type StepItemsProps = {
	readonly steps: readonly Step[];
	readonly keyPrefix: string;
};

function actionAriaLabel(kind: TaskActionKind, taskName: string): string {
	switch (kind) {
		case "memoEdit":
			return `edit memo for ${taskName}`;
		case "memoClear":
			return `clear memo for ${taskName}`;
		case "notiClear":
			return `clear notifications for ${taskName}`;
		case "finder":
			return `open ${taskName} in Finder`;
		case "ide":
			return `open ${taskName} in IDE`;
		case "terminal":
			return `open ${taskName} in terminal`;
		case "copyPath":
			return `copy path for ${taskName}`;
	}
}

export function taskActionsFor(task: Task): readonly TaskRowAction[] {
	return TASK_ACTION_KINDS.map((kind) => ({
		kind,
		label: TASK_ACTION_LABELS[kind],
		ariaLabel: actionAriaLabel(kind, task.name),
		disabled: kind === "notiClear" && task.notiCount === 0,
	}));
}

function StepItems({ steps, keyPrefix }: StepItemsProps) {
	return steps.map((step, index) => {
		const key = `${keyPrefix}.${index}`;
		return (
			<Fragment key={key}>
				<li style={{ paddingLeft: `${step.depth * 14}px` }}>
					{step.checked ? "✓" : "☐"} {step.text}
				</li>
				<StepItems steps={step.children} keyPrefix={key} />
			</Fragment>
		);
	});
}

type TaskSummaryProps = {
	readonly task: Task;
	readonly status: ReturnType<typeof taskStatus>;
	readonly progress: ReturnType<typeof taskProgress>;
};

function TaskSummary({ task, status, progress }: TaskSummaryProps) {
	const meta = STATUS_META[status];
	return (
		<div className="task-summary-line">
			<span
				className="task-status-rail"
				aria-label={meta.label}
				role="img"
				title={meta.label}
			>
				{meta.icon}
			</span>
			<span className="task-name" title={task.name}>
				{task.name}
			</span>
			{progress.total > 0 ? (
				<span className="progress-pill">
					{progress.done}/{progress.total}
				</span>
			) : null}
			{task.notiCount > 0 ? (
				<span className="noti-pill" title={`${task.notiCount} notifications`}>
					+{task.notiCount}
				</span>
			) : null}
		</div>
	);
}

type CurrentStepProps = {
	readonly planTitle: string;
	readonly currentItem: string;
};

function CurrentStep({ planTitle, currentItem }: CurrentStepProps) {
	return (
		<div className="current-step-strip">
			<span className="plan-title" title={planTitle}>
				{planTitle}
			</span>
			<span className="current-step" title={currentItem}>
				{currentItem}
			</span>
		</div>
	);
}

type RepoChipsProps = {
	readonly repos: Task["repos"];
};

function RepoChips({ repos }: RepoChipsProps) {
	if (repos.length === 0) {
		return null;
	}
	return (
		<ul className="repo-chips" aria-label="repositories">
			{repos.map((repo) => (
				<li
					className={`repo-chip${repo.dirty ? " repo-dirty" : ""}`}
					key={`${repo.name}:${repo.branch}`}
					title={`${repo.name} ${repo.branch}${repo.dirty ? " dirty" : " clean"}`}
				>
					<span className="repo-name">{repo.name}</span>
					<span className="repo-branch">{repo.branch}</span>
					{repo.dirty ? (
						<span className="repo-dot" aria-label="dirty" role="img">
							●
						</span>
					) : null}
				</li>
			))}
		</ul>
	);
}

export function TaskRow({ project, root, task, expanded, onAction }: Props) {
	const status = taskStatus(task);
	const progress = taskProgress(task);
	const now = currentItem(task);
	const plan = activePlan(task);
	const actions = taskActionsFor(task);
	return (
		<details className={`task task-${status}`} open={expanded}>
			<summary>
				<TaskSummary task={task} status={status} progress={progress} />
			</summary>
			<div className="task-detail">
				<div className="project-line">{project}</div>
				{plan && now ? (
					<CurrentStep planTitle={plan.title} currentItem={now} />
				) : null}
				<RepoChips repos={task.repos} />
				<div className="task-actions">
					{actions.map((action) => (
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
				{plan ? (
					<ul className="steps">
						<StepItems steps={plan.steps} keyPrefix="plan" />
					</ul>
				) : null}
			</div>
		</details>
	);
}
