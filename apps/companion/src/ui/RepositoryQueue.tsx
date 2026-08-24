import { useEffect } from "react";
import type { CompanionTheme } from "../application/preferences";
import type { MainTaskRow } from "../application/state";
import { type TaskActionHandler, TaskMetaRow } from "./TaskRow";
import { useCurrentEpochSeconds } from "./useCurrentEpochSeconds";

export type RepositoryQueueProps = {
	readonly nowSeconds?: number;
	readonly onAction: TaskActionHandler;
	readonly rows: readonly MainTaskRow[];
	readonly selectedKey: string | undefined;
	readonly theme: CompanionTheme;
};

export function RepositoryQueue({
	nowSeconds,
	onAction,
	rows,
	selectedKey,
	theme,
}: RepositoryQueueProps) {
	const currentNowSeconds = useCurrentEpochSeconds(nowSeconds);
	useEffect(() => {
		if (selectedKey === undefined) return;
		document
			.getElementById(`repository-${encodeURIComponent(selectedKey)}`)
			?.scrollIntoView({ block: "nearest" });
	}, [selectedKey]);
	const repositoryCount = rows.reduce(
		(count, row) => count + row.repos.length,
		0,
	);

	return (
		<section aria-label="All repositories" className="repository-queue">
			<h2 className="repository-queue-heading">
				ALL REPOSITORIES {repositoryCount}
			</h2>
			<div className="repository-queue-list">
				{rows.map((row) => (
					<TaskMetaRow
						highlighted={row.key === selectedKey}
						key={row.key}
						nowSeconds={currentNowSeconds}
						onAction={onAction}
						repos={row.repos}
						root={row.root}
						task={row.task}
						taskKey={row.key}
						theme={theme}
					/>
				))}
			</div>
		</section>
	);
}
