import type { MainRole, MainTaskRow } from "../application/state";
import {
	MATRIX_COLUMNS,
	type MatrixColumn,
	type Task,
	taskProgress,
} from "../domain/model";

export type StageOpenIde = (root: string, task: Task) => void;

const COLUMN_LABELS: Record<MatrixColumn, string> = {
	plan: "PLAN",
	execution: "EXECUTION",
	review: "REVIEW",
};

const MATRIX_HEADER = MATRIX_COLUMNS.map((column, index) => ({
	column,
	index: `0${index + 1}`,
	label: COLUMN_LABELS[column],
}));

function matrixColumn(role: MainRole): MatrixColumn | undefined {
	switch (role) {
		case "plan":
		case "execution":
		case "review":
			return role;
		case "idle":
			return undefined;
	}
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
				WORKTREE STATUS{" "}
				<span className="stage-matrix-count">{activeCount}</span>
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
	readonly row: MainTaskRow;
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
	const column = matrixColumn(row.role);
	return (
		<span
			aria-hidden="true"
			className="stage-cell"
			data-cell={state}
			data-edge={edge}
		>
			{state === "current" && column !== undefined ? (
				<span
					className="stage-node"
					data-blocked={row.blocked ? "true" : "false"}
					data-column={column}
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
	readonly row: MainTaskRow;
	readonly selected: boolean;
}) {
	const column = matrixColumn(row.role);
	if (column === undefined) return null;
	const progress = taskProgress(row.task);
	const currentIndex = MATRIX_COLUMNS.indexOf(column);
	const stateLabel = `${COLUMN_LABELS[column]}${row.blocked ? ", blocked" : ""}`;
	return (
		<article
			className="stage-matrix-row"
			data-blocked={row.blocked ? "true" : "false"}
			data-column={column}
			data-derived={row.derived ? "true" : "false"}
			data-selected={selected ? "true" : "false"}
		>
			<button
				aria-label={`${row.project}, ${row.task.name}, ${stateLabel}, select; double-click or command-enter to open in IDE`}
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
				title={`Select ${row.task.name}; double-click or ⌘Enter to open in IDE`}
				type="button"
			>
				<span className="stage-matrix-identity">
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
					<span className="stage-project-name">{row.project}</span>
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

export function StageBoard({
	activeCount,
	idleCount,
	onOpenIde,
	onSelect,
	rows,
	selectedKey,
}: {
	readonly activeCount: number;
	readonly idleCount: number;
	readonly onOpenIde: StageOpenIde;
	readonly onSelect: (key: string) => void;
	readonly rows: readonly MainTaskRow[];
	readonly selectedKey: string | undefined;
}) {
	const hasExecution = rows.some((row) => row.role === "execution");
	return (
		<section aria-label="Worktree status matrix" className="stage-board">
			<MatrixHead activeCount={activeCount} hasExecution={hasExecution} />
			{rows.map((row) => (
				<MatrixTaskRow
					key={row.key}
					onOpenIde={onOpenIde}
					onSelect={() => onSelect(row.key)}
					row={row}
					selected={row.key === selectedKey}
				/>
			))}
			{idleCount > 0 ? (
				<span className="stage-idle-count">IDLE {idleCount} · inactive</span>
			) : null}
		</section>
	);
}
