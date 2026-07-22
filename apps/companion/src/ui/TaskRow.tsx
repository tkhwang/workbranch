import { Fragment } from "react";
import type { CompanionTheme } from "../application/preferences";
import { currentItem } from "../application/state";
import type { Step, Task } from "../domain/model";
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
} as const;

export type TaskActionHandler = (
	root: string,
	task: Task,
	kind: TaskActionKind,
) => void;

type TaskRowProps = {
	readonly root: string;
	readonly task: Task;
	readonly theme: CompanionTheme;
	readonly expanded: boolean;
	readonly onAction: TaskActionHandler;
};

type StepItemsProps = {
	readonly steps: readonly Step[];
	readonly keyPrefix: string;
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

function StepItems({ steps, keyPrefix }: StepItemsProps) {
	return steps.map((step, index) => {
		const key = `${keyPrefix}.${index}`;
		const markerState = step.checked ? "done" : "todo";
		const markerDepth = Math.min(step.depth, 2);
		return (
			<Fragment key={key}>
				<li
					className={`step-item step-item-${markerState} step-depth-${markerDepth}`}
					style={{ paddingLeft: `${step.depth * 14}px` }}
				>
					<span
						aria-label={step.checked ? "completed step" : "pending step"}
						className={`step-marker step-marker-${markerState}`}
						role="img"
					/>
					<span className="step-text">{step.text}</span>
				</li>
				<StepItems steps={step.children} keyPrefix={key} />
			</Fragment>
		);
	});
}

type TaskSummaryProps = {
	readonly task: Task;
	readonly theme: CompanionTheme;
	readonly status: ReturnType<typeof taskStatus>;
	readonly progress: ReturnType<typeof taskProgress>;
};

function TaskSummary({ task, theme, status, progress }: TaskSummaryProps) {
	return (
		<div className="task-summary-line">
			<PromptLine theme={theme}>
				<span className="task-name" title={task.name}>
					{task.name}
				</span>
				<StatusToken status={status} />
				{progress.total > 0 ? (
					<span className="task-progress">
						{progress.done}/{progress.total}
					</span>
				) : null}
				{task.notiCount > 0 ? (
					<span
						className="task-notification"
						title={`${task.notiCount} notifications`}
					>
						+{task.notiCount}
					</span>
				) : null}
			</PromptLine>
		</div>
	);
}

type CurrentStepProps = {
	readonly theme: CompanionTheme;
	readonly planTitle: string;
	readonly currentItem: string;
};

function CurrentStep({ theme, planTitle, currentItem }: CurrentStepProps) {
	return (
		<div className="current-step-strip">
			<PromptLine theme={theme} current={true}>
				<span className="plan-title" title={planTitle}>
					{planTitle}
				</span>
				<span className="current-step" title={currentItem}>
					{currentItem}
				</span>
			</PromptLine>
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

export function TaskRow({
	root,
	task,
	theme,
	expanded,
	onAction,
}: TaskRowProps) {
	const status = taskStatus(task);
	const progress = taskProgress(task);
	const now = currentItem(task);
	const plan = activePlan(task);
	return (
		<details className={`task task-${status}`} open={expanded}>
			<summary>
				<TaskSummary
					task={task}
					theme={theme}
					status={status}
					progress={progress}
				/>
			</summary>
			<div className="task-detail">
				<div className="task-detail-header">
					<RepoChips repos={task.repos} />
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
				{plan && now ? (
					<CurrentStep theme={theme} planTitle={plan.title} currentItem={now} />
				) : null}
				{plan ? (
					<ul className="steps">
						<StepItems steps={plan.steps} keyPrefix="plan" />
					</ul>
				) : null}
			</div>
		</details>
	);
}
