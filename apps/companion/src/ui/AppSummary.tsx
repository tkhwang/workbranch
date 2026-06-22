import type { MenuSummary } from "../application/state";

function plural(count: number, word: string): string {
	return count === 1 ? word : `${word}s`;
}

type Props = {
	readonly summary: MenuSummary;
};

export function AppSummary({ summary }: Props) {
	const { projectCount, taskCount, active, blocked, notifications } = summary;
	return (
		<div className="app-summary">
			<span className="app-inventory">
				{taskCount === 0
					? "No tasks"
					: `${projectCount} ${plural(projectCount, "project")} · ${taskCount} ${plural(taskCount, "task")}`}
			</span>
			<span className="app-badges">
				{active > 0 ? (
					<span
						className="badge badge-active"
						title={`${active} in progress`}
						aria-label={`${active} in progress`}
						role="img"
					>
						RUN {active}
					</span>
				) : null}
				{blocked > 0 ? (
					<span
						className="badge badge-blocked"
						title={`${blocked} blocked`}
						aria-label={`${blocked} blocked`}
						role="img"
					>
						BLK {blocked}
					</span>
				) : null}
				{notifications > 0 ? (
					<span
						className="badge badge-noti"
						title={`${notifications} notifications`}
						aria-label={`${notifications} notifications`}
						role="img"
					>
						NOTI {notifications}
					</span>
				) : null}
			</span>
		</div>
	);
}
