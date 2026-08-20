import { Fragment } from "react";
import type {
	BoardCard,
	BoardModel,
	OtherTaskCard,
} from "../application/state";
import {
	activePlan,
	type Repo,
	type Task,
	type TaskStage,
	taskProgress,
} from "../domain/model";

export type StageCardOpenIde = (root: string, task: Task) => void;

const LIFECYCLE_STAGES: readonly {
	readonly stage: TaskStage;
	readonly label: string;
}[] = [
	{ stage: "plan", label: "PLAN" },
	{ stage: "execution", label: "EXECUTION" },
	{ stage: "review", label: "REVIEW" },
];

export function formatRelativeTime(
	timestamp: number,
	nowSeconds: number,
): string {
	if (timestamp <= 0) return "";
	const elapsed = Math.max(0, nowSeconds - timestamp);
	if (elapsed < 60) return "now";
	if (elapsed < 60 * 60) return `${Math.floor(elapsed / 60)}m`;
	if (elapsed < 24 * 60 * 60) return `${Math.floor(elapsed / (60 * 60))}h`;
	return `${Math.floor(elapsed / (24 * 60 * 60))}d`;
}

function repoFacts(repo: Repo): string {
	const dirtyFact = repo.dirty
		? repo.activityAvailable
			? `DIRTY ${repo.changedFiles} ${repo.changedFiles === 1 ? "FILE" : "FILES"}`
			: "DIRTY"
		: "CLEAN";
	const facts = [dirtyFact];
	if (repo.ahead > 0) facts.push(`AHEAD ${repo.ahead}`);
	if (repo.behind > 0) facts.push(`BEHIND ${repo.behind}`);
	return facts.join(" · ");
}

function StageRepoActivity({
	repo,
	nowSeconds,
}: {
	readonly repo: Repo;
	readonly nowSeconds: number;
}) {
	const relativeTime = formatRelativeTime(repo.lastCommitAt, nowSeconds);
	const commitContext =
		repo.lastCommitSubject === ""
			? ""
			: `${repo.lastCommitSubject}${relativeTime === "" ? "" : ` · ${relativeTime}`}`;
	return (
		<li className="stage-repo-activity">
			<div className="stage-repo-row">
				<span className="stage-repo-label">REPO</span>
				<div className="stage-repo-identity">
					<span
						className={`stage-repo-name${repo.dirty ? " stage-repo-dirty" : ""}`}
					>
						{repo.name}
						{repo.dirty ? " ●" : ""}
					</span>
					<span className="stage-repo-facts">{repoFacts(repo)}</span>
				</div>
			</div>
			<div className="stage-repo-row">
				<span className="stage-repo-label">BRANCH</span>
				<div className="stage-repo-detail">
					<span className="stage-repo-branch" title={repo.branch}>
						{repo.branch}
					</span>
				</div>
			</div>
			{commitContext === "" ? null : (
				<div className="stage-repo-row">
					<span className="stage-repo-label">COMMIT</span>
					<span className="stage-repo-commit" title={repo.lastCommitSubject}>
						{commitContext}
					</span>
				</div>
			)}
		</li>
	);
}

function StageLifecycle({ stage }: { readonly stage: TaskStage }) {
	const currentStage = LIFECYCLE_STAGES.find((item) => item.stage === stage);
	return (
		<fieldset
			aria-label={`Current stage: ${currentStage?.label ?? stage}`}
			className="stage-lifecycle"
		>
			<div className="stage-lifecycle-heading">
				<span className="stage-lifecycle-caption">STAGE</span>
				<span className="stage-lifecycle-current-label">
					{currentStage?.label ?? stage}
				</span>
			</div>
			<div className="stage-lifecycle-track">
				{LIFECYCLE_STAGES.map((item, index) => (
					<Fragment key={item.stage}>
						{index === 0 ? null : (
							<span aria-hidden="true" className="stage-lifecycle-connector" />
						)}
						<span
							className={`stage-lifecycle-stage${item.stage === stage ? " stage-lifecycle-current" : ""}`}
							data-current={item.stage === stage ? "true" : "false"}
							data-stage={item.stage}
						>
							<span aria-hidden="true" className="stage-lifecycle-node" />
							<span className="stage-lifecycle-label">{item.label}</span>
						</span>
					</Fragment>
				))}
			</div>
		</fieldset>
	);
}

export function StageCard({
	card,
	nowSeconds = Math.floor(Date.now() / 1000),
	onOpenIde,
}: {
	readonly card: BoardCard;
	readonly nowSeconds?: number;
	readonly onOpenIde: StageCardOpenIde;
}) {
	const plan = activePlan(card.task);
	const progress = taskProgress(card.task);
	return (
		<article
			className="stage-task-row"
			data-blocked={card.blocked ? "true" : "false"}
			data-derived={card.derived ? "true" : "false"}
		>
			<button
				aria-label={`open ${card.task.name} in IDE`}
				className="stage-task-open"
				onClick={(event) => {
					if (event.detail !== 0) return;
					onOpenIde(card.root, card.task);
				}}
				onDoubleClick={() => onOpenIde(card.root, card.task)}
				title={`Double-click to open ${card.task.name} in IDE`}
				type="button"
			/>
			<StageLifecycle stage={card.stage} />
			<div className="stage-task-header">
				<div className="stage-task-heading">
					<span className="stage-task-project">
						<span className="stage-task-project-label">PROJECT</span>
						<span className="stage-task-project-name">{card.project}</span>
					</span>
					<div className="stage-task-title-line">
						<span className="stage-task-name" title={card.task.name}>
							{card.task.name}
						</span>
						{card.derived ? (
							<span className="stage-task-derived">DERIVED</span>
						) : null}
					</div>
				</div>
				<div className="stage-task-meta">
					{card.blocked ? (
						<span className="stage-task-blocked">BLOCKED</span>
					) : null}
					{progress.total > 0 ? (
						<span className="stage-task-progress">
							{progress.done}/{progress.total}
						</span>
					) : null}
					{card.task.notiCount > 0 ? (
						<span className="stage-task-notification">
							+{card.task.notiCount}
						</span>
					) : null}
				</div>
			</div>
			{plan !== undefined && plan.title !== card.task.name ? (
				<span className="stage-task-plan" title={plan.title}>
					{plan.title}
				</span>
			) : null}
			{card.task.repos.length === 0 ? null : (
				<ul aria-label="repository activity" className="stage-repo-stack">
					{card.task.repos.map((repo) => (
						<StageRepoActivity
							key={repo.name}
							nowSeconds={nowSeconds}
							repo={repo}
						/>
					))}
				</ul>
			)}
		</article>
	);
}

function OtherTaskRow({
	card,
	onOpenIde,
}: {
	readonly card: OtherTaskCard;
	readonly onOpenIde: StageCardOpenIde;
}) {
	return (
		<li className="stage-other-task">
			<button
				aria-label={`open ${card.task.name} in IDE`}
				onClick={() => onOpenIde(card.root, card.task)}
				type="button"
			>
				<span>{card.task.name}</span>
				<span>{card.project}</span>
			</button>
		</li>
	);
}

export function StageBoard({
	board,
	nowSeconds = Math.floor(Date.now() / 1000),
	onOpenIde,
}: {
	readonly board: BoardModel;
	readonly nowSeconds?: number;
	readonly onOpenIde: StageCardOpenIde;
}) {
	return (
		<section className="stage-board" aria-label="Task stage board">
			<header className="stage-feed-header">
				<h2 className="stage-feed-label">ACTIVE</h2>
				<span className="stage-feed-count">{board.cards.length}</span>
			</header>
			<div className="stage-feed">
				{board.cards.map((card) => (
					<StageCard
						card={card}
						key={`${card.root}:${card.task.name}`}
						nowSeconds={nowSeconds}
						onOpenIde={onOpenIde}
					/>
				))}
			</div>
			{board.otherTasks.length === 0 ? null : (
				<details className="stage-other">
					<summary>
						<span className="stage-other-label">OTHER</span>
						<span className="stage-other-count">{board.otherTasks.length}</span>
						<span className="stage-other-copy">clean todo / done</span>
					</summary>
					<ul className="stage-other-list">
						{board.otherTasks.map((card) => (
							<OtherTaskRow
								card={card}
								key={`${card.root}:${card.task.name}`}
								onOpenIde={onOpenIde}
							/>
						))}
					</ul>
				</details>
			)}
		</section>
	);
}
