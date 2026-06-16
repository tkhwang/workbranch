import { Fragment } from "react";
import { currentItem } from "../application/state";
import type { Step, Task } from "../domain/model";
import { activePlan, taskProgress, taskStatus } from "../domain/model";

const STATUS_ICON = {
	todo: "·",
	planning: "○",
	"in-progress": "●",
	review: "◐",
	blocked: "⚠",
	done: "✓",
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
	memoClear: "Clear memo",
	notiClear: "Clear noti",
	finder: "Finder",
	ide: "IDE",
	terminal: "Terminal",
	copyPath: "Copy path",
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

export function TaskRow({ project, root, task, expanded, onAction }: Props) {
	const status = taskStatus(task);
	const progress = taskProgress(task);
	const now = currentItem(task);
	const plan = activePlan(task);
	const actions = taskActionsFor(task);
	return (
		<details className={`task task-${status}`} open={expanded}>
			<summary>
				<span className="status">{STATUS_ICON[status]}</span>
				<span className="task-name">{task.name}</span>
				{progress.total > 0 ? (
					<span className="progress">
						{progress.done}/{progress.total}
					</span>
				) : null}
				{task.notiCount > 0 ? (
					<span className="noti">🔔{task.notiCount}</span>
				) : null}
			</summary>
			<div className="meta">{project}</div>
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
			{now ? <div className="now">now ▸ {now}</div> : null}
			<div className="repos">
				{task.repos.map((repo) => (
					<div className="repo" key={repo.name}>
						{repo.name} {repo.branch} {repo.dirty ? "●" : ""}
					</div>
				))}
			</div>
			{plan ? (
				<ul className="steps">
					<StepItems steps={plan.steps} keyPrefix="plan" />
				</ul>
			) : null}
		</details>
	);
}
