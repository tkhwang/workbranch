import type { ProjectGroup as ProjectGroupModel } from "../application/state";
import type { Task } from "../domain/model";
import { type TaskActionKind, TaskRow } from "./TaskRow";

type Props = {
	readonly group: ProjectGroupModel;
	readonly onAction: (root: string, task: Task, kind: TaskActionKind) => void;
};

export function ProjectGroup({ group, onAction }: Props) {
	const count = group.rows.length;
	return (
		<section className="project-group" aria-label={group.project}>
			<div className="project-group-header">
				<span className="project-group-name" title={group.project}>
					{group.project}
				</span>
				<span className="project-group-count">
					{count} {count === 1 ? "task" : "tasks"}
				</span>
			</div>
			{group.rows.map((row) => (
				<TaskRow
					key={`${row.root}-${row.task.name}`}
					root={row.root}
					task={row.task}
					expanded={row.expanded}
					onAction={onAction}
				/>
			))}
		</section>
	);
}
