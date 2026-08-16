import type { BoardCard, BoardModel } from "../application/state";
import { taskProgress } from "../domain/model";

function StageCard({ card }: { readonly card: BoardCard }) {
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
			{board.columns.map((column) => (
				<section
					className="stage-column"
					data-stage={column.stage}
					key={column.stage}
				>
					<header className="stage-column-header">
						<h2>{column.label}</h2>
						<span>{column.cards.length}</span>
					</header>
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
