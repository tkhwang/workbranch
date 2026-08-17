import type { BoardCard, BoardModel } from "../application/state";
import {
	activePlan,
	type Repo,
	type TaskStage,
	taskProgress,
} from "../domain/model";

const STAGE_ROLES: Record<TaskStage, string> = {
	plan: "AI·ME",
	execution: "AI",
	review: "ME",
};

function StageCardRepos({ repos }: { readonly repos: readonly Repo[] }) {
	if (repos.length === 0) return null;
	return (
		<ul aria-label="repositories" className="stage-card-repos">
			{repos.map((repo) => (
				<li
					className={`stage-card-repo${repo.dirty ? " stage-card-repo-dirty" : ""}`}
					key={repo.name}
					title={`${repo.name} ${repo.branch} ${repo.dirty ? "dirty" : "clean"}`}
				>
					<span className="stage-card-repo-name">{repo.name}</span>
					{repo.dirty ? (
						<span className="stage-card-repo-dot" aria-label="dirty" role="img">
							●
						</span>
					) : null}
				</li>
			))}
		</ul>
	);
}

function StageCard({ card }: { readonly card: BoardCard }) {
	const plan = activePlan(card.task);
	const progress = taskProgress(card.task);
	return (
		<article
			className="stage-card"
			data-blocked={card.blocked ? "true" : "false"}
		>
			<span className="stage-card-project">{card.project}</span>
			<span className="stage-card-name" title={card.task.name}>
				{card.task.name}
			</span>
			{plan !== undefined && plan.title !== card.task.name ? (
				<span className="stage-card-plan" title={plan.title}>
					{plan.title}
				</span>
			) : null}
			<StageCardRepos repos={card.task.repos} />
			<div className="stage-card-meta">
				{card.blocked ? (
					<span className="stage-card-blocked">BLOCKED</span>
				) : null}
				{progress.total > 0 ? (
					<span className="stage-card-progress">
						{progress.done}/{progress.total}
					</span>
				) : null}
				{card.task.notiCount > 0 ? (
					<span
						className="stage-card-notification"
						title={`${card.task.notiCount} notifications`}
					>
						+{card.task.notiCount}
					</span>
				) : null}
			</div>
		</article>
	);
}

export function StageBoard({ board }: { readonly board: BoardModel }) {
	return (
		<section className="stage-board" aria-label="Task stage board">
			<header className="stage-board-header">
				{board.columns.map((column) => (
					<div
						className="stage-board-heading"
						id={`stage-heading-${column.stage}`}
						key={column.stage}
					>
						<h2>{column.label}</h2>
						<div className="stage-board-heading-meta">
							<span className="stage-board-role">
								{STAGE_ROLES[column.stage]}
							</span>
							<span className="stage-board-count">{column.cards.length}</span>
						</div>
					</div>
				))}
			</header>
			{board.columns.map((column) => (
				<section
					className="stage-column"
					data-stage={column.stage}
					aria-labelledby={`stage-heading-${column.stage}`}
					key={column.stage}
				>
					<div className="stage-card-list">
						{column.cards.map((card) => (
							<StageCard card={card} key={`${card.root}:${card.task.name}`} />
						))}
					</div>
				</section>
			))}
		</section>
	);
}
