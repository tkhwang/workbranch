import { Fragment } from "react";
import type { MatrixModel, MatrixRow, OtherRow } from "../application/state";
import {
	activePlan,
	MATRIX_COLUMNS,
	type MatrixColumn,
	type Repo,
	type Task,
	taskProgress,
	taskStatus,
} from "../domain/model";
import { StatusToken } from "./StatusToken";
import { useCurrentEpochSeconds } from "./useCurrentEpochSeconds";

export type StageOpenIde = (root: string, task: Task) => void;

const COLUMN_LABELS: Record<MatrixColumn, string> = {
	plan: "PLAN",
	execution: "EXEC",
	review: "REVIEW",
};

const MATRIX_HEADER = MATRIX_COLUMNS.map((column, index) => ({
	column,
	index: `0${index + 1}`,
	label: COLUMN_LABELS[column],
}));

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

export function matrixRowKey(row: MatrixRow): string {
	return `${row.root}:${row.task.name}`;
}

export function selectedMatrixRow(
	matrix: MatrixModel,
	selectedKey: string | undefined,
): MatrixRow | undefined {
	const rows = matrix.lanes.flatMap((lane) => lane.rows);
	return rows.find((row) => matrixRowKey(row) === selectedKey) ?? rows[0];
}

function currentStepText(task: Task): string {
	const plan = activePlan(task);
	if (plan === undefined) return "";
	if (plan.currentItem !== "") return plan.currentItem;
	return plan.title === task.name ? "" : plan.title;
}

function MatrixHead({
	activeCount,
	hasExecution,
}: {
	readonly activeCount: number;
	readonly hasExecution: boolean;
}) {
	return (
		<div className="stage-matrix-head">
			<h2 className="stage-matrix-caption">
				ACTIVE <span className="stage-matrix-count">{activeCount}</span>
			</h2>
			{MATRIX_HEADER.map((item) => (
				<span
					className="stage-matrix-col"
					data-hot={
						item.column === "execution" && hasExecution ? "true" : "false"
					}
					key={item.column}
				>
					<span className="stage-matrix-col-num">{item.index}</span>
					<span className="stage-matrix-col-label">{item.label}</span>
				</span>
			))}
		</div>
	);
}

function MatrixCell({
	currentIndex,
	position,
	row,
}: {
	readonly currentIndex: number;
	readonly position: number;
	readonly row: MatrixRow;
}) {
	const state =
		position === currentIndex
			? "current"
			: position < currentIndex
				? "past"
				: "future";
	const edge =
		position === 0
			? "first"
			: position === MATRIX_HEADER.length - 1
				? "last"
				: "middle";
	return (
		<span
			aria-hidden="true"
			className="stage-cell"
			data-cell={state}
			data-edge={edge}
		>
			{state === "current" ? (
				<span
					className="stage-node"
					data-blocked={row.blocked ? "true" : "false"}
					data-column={row.column}
				/>
			) : (
				<span className="stage-dot" />
			)}
		</span>
	);
}

export function MatrixTaskRow({
	onOpenIde,
	onSelect,
	row,
	selected,
}: {
	readonly onOpenIde: StageOpenIde;
	readonly onSelect: () => void;
	readonly row: MatrixRow;
	readonly selected: boolean;
}) {
	const progress = taskProgress(row.task);
	const currentIndex = MATRIX_HEADER.findIndex(
		(item) => item.column === row.column,
	);
	return (
		<article
			className="stage-matrix-row"
			data-blocked={row.blocked ? "true" : "false"}
			data-column={row.column}
			data-derived={row.derived ? "true" : "false"}
			data-selected={selected ? "true" : "false"}
		>
			<button
				aria-label={`${row.task.name}, ${COLUMN_LABELS[row.column]}${row.blocked ? ", blocked" : ""}, show details`}
				aria-pressed={selected}
				className="stage-matrix-line"
				onClick={(event) => {
					if (event.detail > 2) return;
					onSelect();
				}}
				onDoubleClick={() => onOpenIde(row.root, row.task)}
				onKeyDown={(event) => {
					if (event.key !== "Enter") return;
					if (!event.metaKey && !event.ctrlKey) return;
					event.preventDefault();
					onOpenIde(row.root, row.task);
				}}
				title={`Double-click or ⌘Enter to open ${row.task.name} in IDE`}
				type="button"
			>
				<span className="stage-matrix-left">
					<span className="stage-task-name" title={row.task.name}>
						{row.task.name}
					</span>
					{row.blocked ? (
						<span className="stage-task-blocked">BLOCKED</span>
					) : null}
					{row.derived ? (
						<span className="stage-task-derived">DERIVED</span>
					) : null}
					{progress.total > 0 ? (
						<span className="stage-task-progress">
							{progress.done}/{progress.total}
						</span>
					) : null}
					{row.task.notiCount > 0 ? (
						<span className="stage-task-notification">
							+{row.task.notiCount}
						</span>
					) : null}
				</span>
				{MATRIX_HEADER.map((item, position) => (
					<MatrixCell
						currentIndex={currentIndex}
						key={item.column}
						position={position}
						row={row}
					/>
				))}
			</button>
		</article>
	);
}

function DetailRepo({
	nowSeconds,
	repo,
}: {
	readonly nowSeconds: number;
	readonly repo: Repo;
}) {
	const relativeTime = formatRelativeTime(repo.lastCommitAt, nowSeconds);
	const commitContext =
		repo.lastCommitSubject === ""
			? ""
			: `${repo.lastCommitSubject}${relativeTime === "" ? "" : ` · ${relativeTime}`}`;
	return (
		<li className="stage-repo">
			<div className="stage-repo-head">
				<span
					className={`stage-repo-name${repo.dirty ? " stage-repo-dirty" : ""}`}
				>
					{repo.name}
					{repo.dirty ? " ●" : ""}
				</span>
				<span className="stage-repo-branch" title={repo.branch}>
					{repo.branch}
				</span>
			</div>
			<div className="stage-repo-meta">
				<span className="stage-repo-facts">{repoFacts(repo)}</span>
				{commitContext === "" ? null : (
					<span className="stage-repo-commit" title={repo.lastCommitSubject}>
						{commitContext}
					</span>
				)}
			</div>
		</li>
	);
}

export function DetailPanel({
	nowSeconds,
	row,
}: {
	readonly nowSeconds: number;
	readonly row: MatrixRow;
}) {
	const stepText = currentStepText(row.task);
	return (
		<section
			aria-label={`${row.task.name} detail`}
			className="stage-detail-panel"
			data-blocked={row.blocked ? "true" : "false"}
		>
			<div className="stage-detail-head">
				<span className="stage-detail-caption">DETAIL</span>
				<span className="stage-detail-task" title={row.task.name}>
					{row.task.name}
				</span>
				{row.derived ? (
					<span className="stage-task-derived">DERIVED</span>
				) : null}
				<StatusToken status={taskStatus(row.task)} />
			</div>
			{stepText === "" ? null : (
				<p className="stage-detail-step" title={stepText}>
					▸ {stepText}
				</p>
			)}
			{row.task.repos.length === 0 ? null : (
				<ul aria-label="repository activity" className="stage-detail-repos">
					{row.task.repos.map((repo) => (
						<DetailRepo key={repo.name} nowSeconds={nowSeconds} repo={repo} />
					))}
				</ul>
			)}
		</section>
	);
}

function OtherTaskRow({
	other,
	onOpenIde,
}: {
	readonly other: OtherRow;
	readonly onOpenIde: StageOpenIde;
}) {
	return (
		<li className="stage-other-task">
			<button
				aria-label={`open ${other.task.name} in IDE`}
				onClick={(event) => {
					if (event.detail !== 0) return;
					onOpenIde(other.root, other.task);
				}}
				onDoubleClick={() => onOpenIde(other.root, other.task)}
				title={`Double-click to open ${other.task.name} in IDE`}
				type="button"
			>
				<span>{other.task.name}</span>
				<span>{other.project}</span>
			</button>
		</li>
	);
}

export function StageBoard({
	matrix,
	nowSeconds,
	onOpenIde,
	onSelect,
	selectedKey,
}: {
	readonly matrix: MatrixModel;
	readonly nowSeconds?: number;
	readonly onOpenIde: StageOpenIde;
	readonly onSelect: (key: string) => void;
	readonly selectedKey: string | undefined;
}) {
	const currentNowSeconds = useCurrentEpochSeconds(nowSeconds);
	const hasExecution = matrix.lanes.some((lane) =>
		lane.rows.some((row) => row.column === "execution"),
	);
	const selectedRow = selectedMatrixRow(matrix, selectedKey);
	const selectedRowKey =
		selectedRow === undefined ? undefined : matrixRowKey(selectedRow);
	return (
		<section aria-label="Task stage board" className="stage-board">
			<MatrixHead
				activeCount={matrix.activeCount}
				hasExecution={hasExecution}
			/>
			{matrix.lanes.map((lane) => (
				<Fragment key={lane.root}>
					<h3 className="stage-lane">
						<span className="stage-lane-label">PROJECT</span>
						<span className="stage-lane-name">{lane.project}</span>
					</h3>
					{lane.rows.map((row) => {
						const key = matrixRowKey(row);
						return (
							<MatrixTaskRow
								key={key}
								onOpenIde={onOpenIde}
								onSelect={() => onSelect(key)}
								row={row}
								selected={key === selectedRowKey}
							/>
						);
					})}
				</Fragment>
			))}
			{selectedRow === undefined ? null : (
				<DetailPanel nowSeconds={currentNowSeconds} row={selectedRow} />
			)}
			{matrix.others.length === 0 ? null : (
				<details className="stage-other">
					<summary>
						<span className="stage-other-label">OTHER</span>
						<span className="stage-other-count">{matrix.others.length}</span>
						<span className="stage-other-copy">clean todo / done</span>
					</summary>
					<ul className="stage-other-list">
						{matrix.others.map((other) => (
							<OtherTaskRow
								key={`${other.root}:${other.task.name}`}
								onOpenIde={onOpenIde}
								other={other}
							/>
						))}
					</ul>
				</details>
			)}
			<div className="stage-legend">
				<span className="stage-legend-item">
					<span
						className="stage-node"
						data-blocked="false"
						data-column="plan"
					/>
					PLAN
				</span>
				<span className="stage-legend-item">
					<span
						className="stage-node"
						data-blocked="false"
						data-column="execution"
					/>
					IN PROGRESS
				</span>
				<span className="stage-legend-item">
					<span
						className="stage-node"
						data-blocked="true"
						data-column="execution"
					/>
					BLOCKED
				</span>
				<span className="stage-legend-item">
					<span
						className="stage-node"
						data-blocked="false"
						data-column="review"
					/>
					REVIEW
				</span>
				<span className="stage-legend-hint">DBL-CLICK / ⌘⏎ = IDE</span>
			</div>
		</section>
	);
}
