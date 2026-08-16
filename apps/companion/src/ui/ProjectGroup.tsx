import type { CompanionTheme } from "../application/preferences";
import type { ProjectGroup as ProjectGroupModel } from "../application/state";
import { type TaskActionHandler, TaskMetaRow } from "./TaskRow";
import { TerminalPanel } from "./TerminalPanel";

type ProjectGroupProps = {
	readonly group: ProjectGroupModel;
	readonly theme: CompanionTheme;
	readonly onAction: TaskActionHandler;
};

export function ProjectGroup({ group, theme, onAction }: ProjectGroupProps) {
	const count = group.rows.length;
	return (
		<TerminalPanel
			className="project-group"
			label={`${group.project} · ${count} ${count === 1 ? "task" : "tasks"}`}
			theme={theme}
		>
			{group.rows.map((row) => (
				<TaskMetaRow
					key={`${row.root}-${row.task.name}`}
					root={row.root}
					task={row.task}
					theme={theme}
					onAction={onAction}
				/>
			))}
		</TerminalPanel>
	);
}
