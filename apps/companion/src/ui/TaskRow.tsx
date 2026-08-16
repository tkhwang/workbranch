import type { CompanionTheme } from "../application/preferences";
import type { Task } from "../domain/model";
import { taskStatus } from "../domain/model";
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
	readonly root: string;
	readonly task: Task;
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

function RepoChips({ repos }: { readonly repos: Task["repos"] }) {
	if (repos.length === 0) return null;
	return (
		<ul className="repo-chips" aria-label="repositories">
			{repos.map((repo) => (
				<li
					className="repo-pair"
					key={`${repo.name}:${repo.branch}`}
					title={`${repo.name} ${repo.branch}${repo.dirty ? " dirty" : " clean"}`}
				>
					<span className={`repo-name${repo.dirty ? " repo-dirty" : ""}`}>
						{repo.name}
						{repo.dirty ? (
							<span className="repo-dot" aria-label="dirty" role="img">
								●
							</span>
						) : null}
					</span>
					<span className="repo-branch-name">{repo.branch}</span>
				</li>
			))}
		</ul>
	);
}

export function TaskMetaRow({ root, task, theme, onAction }: TaskMetaRowProps) {
	const status = taskStatus(task);
	return (
		<article className={`task-meta-row task-${status}`}>
			<div className="task-meta-primary">
				<PromptLine theme={theme}>
					<span className="task-name" title={task.name}>
						{task.name}
					</span>
					<StatusToken status={status} />
				</PromptLine>
			</div>
			<div className="task-meta-secondary">
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
		</article>
	);
}
