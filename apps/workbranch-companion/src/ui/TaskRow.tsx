import { currentItem } from "../application/state";
import type { Task } from "../domain/model";
import { activePlan, taskProgress, taskStatus } from "../domain/model";

const STATUS_ICON = {
	todo: "·",
	planning: "○",
	"in-progress": "●",
	review: "◐",
	blocked: "⚠",
	done: "✓",
} as const;

type Props = {
	readonly project: string;
	readonly task: Task;
	readonly expanded: boolean;
};

export function TaskRow({ project, task, expanded }: Props) {
	const status = taskStatus(task);
	const progress = taskProgress(task);
	const now = currentItem(task);
	const plan = activePlan(task);
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
					{plan.steps.map((step) => (
						<li
							key={`${step.depth}-${step.text}`}
							style={{ paddingLeft: `${step.depth * 14}px` }}
						>
							{step.checked ? "✓" : "☐"} {step.text}
						</li>
					))}
				</ul>
			) : null}
		</details>
	);
}
