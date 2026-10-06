import { type MouseEvent, useEffect, useRef, useState } from "react";
import { type RepoNotes, repoNoteKey } from "../application/notes";
import {
	compareMainTaskRows,
	type MainBaseRow,
	type MainStageGroup,
	type MainTaskRow,
} from "../application/state";
import type {
	AgentSession,
	BaseRepoAction,
	MatrixColumn,
	Repo,
} from "../domain/model";
import {
	baseRepoAction,
	baseRepoHealth,
	runtimeLabels,
	sessionKey,
} from "../domain/model";
import { PROVIDER_NAMES, ProviderIcon, sessionProviders } from "./ProviderIcon";
import {
	baseRepoFacts,
	compactRepoFacts,
	formatObservedAgo,
	formatRelativeTime,
	repoFacts,
	type TaskActionHandler,
	type TaskActionKind,
	taskActionsFor,
} from "./TaskRow";
import { useCurrentEpochSeconds } from "./useCurrentEpochSeconds";

function TaskActionIcon({ kind }: { readonly kind: TaskActionKind }) {
	const common = {
		"aria-hidden": true,
		className: "task-action-icon",
		"data-action-icon": kind,
		fill: "none",
		stroke: "currentColor",
		strokeLinecap: "round",
		strokeLinejoin: "round",
		strokeWidth: 1.6,
		viewBox: "0 0 20 20",
	} as const;
	switch (kind) {
		case "ide":
			return (
				<svg {...common}>
					<title>IDE / Editor</title>
					<rect height="15" rx="2" width="16" x="2" y="2.5" />
					<path d="M2 6h16" />
					<path d="M6.5 6v11.5" />
					<path d="M9 9h5" />
					<path d="M9 12h4" />
					<path d="M9 15h6" />
				</svg>
			);
		case "terminal":
			return (
				<svg {...common}>
					<title>Terminal</title>
					<rect height="14" rx="2" width="16" x="2" y="3" />
					<path d="m5 7 3 3-3 3" />
					<path d="M10 13h4" />
				</svg>
			);
		case "finder":
			return (
				<svg {...common}>
					<title>Finder</title>
					<path d="M2.5 6.5h5l1.6 2h8.4v7.5h-15z" />
					<path d="M2.5 6.5V5h6l1.5 1.5" />
				</svg>
			);
	}
}

const ACTION_LABELS = {
	pull: "PULL",
	push: "PUSH",
	check: "CHECK",
} as const satisfies Record<BaseRepoAction, string>;

function BaseRepoRow({ row }: { readonly row: MainBaseRow }) {
	const { project, repo, showProject } = row;
	const health = baseRepoHealth(repo);
	const action = baseRepoAction(repo);
	const facts = baseRepoFacts(repo);
	const branchLabel =
		repo.inspectionError !== null
			? "branch unavailable"
			: repo.branch || "no branch";
	const guidance =
		repo.inspectionError === "invalid-worktree"
			? "Invalid base worktree"
			: repo.inspectionError === "git-read-failed"
				? "Git status could not be read"
				: repo.dirty && repo.behind > 0
					? "Clean working tree before pulling"
					: "";
	const description = `${project} ${repo.name}, ${branchLabel}, ${facts}${action === undefined ? "" : `, next ${ACTION_LABELS[action]}`}${guidance === "" ? "" : `, ${guidance}`}`;
	const factsTitle = facts + (guidance === "" ? "" : ` · ${guidance}`);

	return (
		/* biome-ignore lint/a11y/useSemanticElements: The approved contract requires a non-focusable div listitem. */
		<div
			aria-label={description}
			className="stage-base-row"
			data-health={health}
			role="listitem"
			title={description}
		>
			<span aria-hidden="true" className="stage-base-dot" />
			<span className="stage-base-name" title={`${project}/${repo.name}`}>
				{showProject ? (
					<span className="stage-base-project">{project}/</span>
				) : null}
				{repo.name}
			</span>
			<span className="stage-base-branch" title={branchLabel}>
				{repo.inspectionError !== null || repo.branch === ""
					? "—"
					: repo.branch}
			</span>
			<span className="stage-base-facts" title={factsTitle}>
				{facts}
			</span>
			{action === undefined ? null : (
				<span className="stage-base-action" data-action={action}>
					{ACTION_LABELS[action]}
				</span>
			)}
		</div>
	);
}

function BranchIcon() {
	return (
		<svg
			aria-hidden="true"
			className="runtime-branch-icon"
			fill="none"
			stroke="currentColor"
			strokeLinecap="round"
			strokeWidth="1.6"
			viewBox="0 0 20 20"
		>
			<circle cx="6" cy="4.5" r="2" />
			<circle cx="6" cy="15.5" r="2" />
			<circle cx="14" cy="6.5" r="2" />
			<path d="M6 6.5v7" />
			<path d="M14 8.5c0 3.5-8 2.5-8 5" />
		</svg>
	);
}

type NoteEdit = { readonly id: string; readonly draft: string };

function StageRepoRow({
	draft,
	editing,
	note,
	nowSeconds,
	onCancelEdit,
	onDraftChange,
	onSaveEdit,
	onStartEdit,
	repo,
	showBranch,
	showCommit,
}: {
	readonly draft: string;
	readonly editing: boolean;
	readonly note: string | undefined;
	readonly nowSeconds: number;
	readonly onCancelEdit: () => void;
	readonly onDraftChange: (text: string) => void;
	readonly onSaveEdit: () => void;
	readonly onStartEdit: () => void;
	readonly repo: Repo;
	readonly showBranch: boolean;
	readonly showCommit: boolean;
}) {
	const textareaRef = useRef<HTMLTextAreaElement>(null);
	const relativeTime = formatRelativeTime(repo.lastCommitAt, nowSeconds);
	const commit =
		repo.lastCommitSubject === ""
			? ""
			: repo.lastCommitSubject +
				(relativeTime === "" ? "" : " · " + relativeTime);
	const facts = repoFacts(repo);

	useEffect(() => {
		if (editing) textareaRef.current?.focus();
	}, [editing]);

	return (
		<div className="stage-repo-row">
			<div className="stage-repo-facts-line">
				<span
					className={
						repo.dirty
							? "stage-repo-name stage-repo-name-dirty"
							: "stage-repo-name"
					}
					title={repo.name}
				>
					{repo.name}
				</span>
				<span
					aria-label={facts}
					className="stage-repo-facts"
					role="img"
					title={facts}
				>
					{compactRepoFacts(repo).map((fact) => (
						<span
							aria-hidden="true"
							className="repo-fact"
							data-tone={fact.tone}
							key={fact.tone}
						>
							{fact.label}
						</span>
					))}
				</span>
				<button
					aria-expanded={editing}
					aria-label={"edit note for " + repo.name + " " + repo.branch}
					className="stage-note-button"
					data-has-note={note === undefined ? "false" : "true"}
					onClick={onStartEdit}
					type="button"
				>
					✎
				</button>
			</div>
			{showBranch ? (
				<div className="runtime-branch" title={`branch: ${repo.branch}`}>
					<BranchIcon />
					<span>{repo.branch}</span>
				</div>
			) : null}
			{!showCommit || commit === "" ? null : (
				<div
					aria-label={"last commit: " + commit}
					className="stage-repo-commit"
					role="note"
					title={"last commit: " + repo.lastCommitSubject}
				>
					<svg
						aria-hidden="true"
						className="stage-repo-commit-icon"
						data-icon="commit"
						fill="none"
						stroke="currentColor"
						strokeWidth="1.6"
						viewBox="0 0 20 20"
					>
						<circle cx="10" cy="10" r="3.2" />
						<path d="M1.5 10h5.3" />
						<path d="M13.2 10h5.3" />
					</svg>
					<span>{commit}</span>
				</div>
			)}
			{editing ? (
				<div className="stage-note-editor">
					<textarea
						aria-label={"note for " + repo.name + " " + repo.branch}
						onBlur={onSaveEdit}
						onChange={(event) => onDraftChange(event.currentTarget.value)}
						onKeyDown={(event) => {
							if (event.key === "Escape") {
								event.preventDefault();
								onCancelEdit();
								return;
							}
							if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
								event.preventDefault();
								onSaveEdit();
							}
						}}
						value={draft}
						ref={textareaRef}
					/>
					<span>⌘Enter 저장 · Esc 취소 · 비우고 저장하면 삭제</span>
				</div>
			) : note === undefined ? null : (
				<div className="stage-note-line" title={note}>
					✎ {note}
				</div>
			)}
		</div>
	);
}

export type StageBoardProps = {
	readonly baseRows: readonly MainBaseRow[];
	readonly groups: readonly MainStageGroup[];
	readonly idleRows: readonly MainTaskRow[];
	readonly activeCount: number;
	readonly idleCount: number;
	readonly notes: RepoNotes;
	readonly onSaveNote: (key: string, text: string) => void;
	readonly onAction: TaskActionHandler;
	readonly onSelect: (key: string) => void;
	readonly selectedKey: string | undefined;
};

const BOARD_COLUMNS = ["waiting", "running", "finished"] as const;
type BoardColumn = (typeof BOARD_COLUMNS)[number];

const COLUMN_COPY = {
	waiting: { label: "내 응답 대기", code: "WAITING" },
	running: { label: "실행 중", code: "RUNNING" },
	finished: { label: "턴 종료 · 검토", code: "REVIEW" },
} as const satisfies Record<BoardColumn, { label: string; code: string }>;

const WAIT_REASON_LABELS: Readonly<Record<string, string>> = {
	permission: "권한 승인 대기",
	question: "질문 대기",
	plan: "plan 승인 대기",
	elicitation: "입력 대기",
};

type ChipTone = BoardColumn | "error" | "notify" | "neutral";
type Chip = { readonly tone: ChipTone; readonly label: string };

function isBoardColumn(role: MainTaskRow["role"]): role is BoardColumn {
	return (BOARD_COLUMNS as readonly string[]).includes(role);
}

function observedCount(
	sessions: readonly AgentSession[],
	state: BoardColumn,
): number {
	return sessions.filter(
		(s) => s.observation === "observed" && s.state === state,
	).length;
}

function leadChip(role: BoardColumn, lead: AgentSession | undefined): Chip {
	if (role === "waiting")
		return {
			tone: "waiting",
			label: WAIT_REASON_LABELS[lead?.reason ?? ""] ?? runtimeLabels.waiting,
		};
	if (role === "finished" && lead?.outcome === "interrupted")
		return { tone: "error", label: "중단됨" };
	if (role === "finished" && lead?.outcome === "error")
		return { tone: "error", label: "오류로 종료" };
	return { tone: role, label: runtimeLabels[role] };
}

export function inventoryTag(row: MainTaskRow): string {
	if (row.role === "idle") return runtimeLabels.idle;
	return row.sessions.length === 0 ? "세션 없음" : runtimeLabels.unknown;
}

export function runtimeChips(row: MainTaskRow): readonly Chip[] {
	const chips: Chip[] = [];
	const { role, sessions } = row;
	if (isBoardColumn(role)) {
		const lead = leadChip(role, sessions[0]);
		const same = observedCount(sessions, role);
		chips.push(same > 1 ? { ...lead, label: `${lead.label} ${same}` } : lead);
		for (const state of BOARD_COLUMNS) {
			const count = state === role ? 0 : observedCount(sessions, state);
			if (count > 0)
				chips.push({
					tone: "neutral",
					label: `+${count} ${runtimeLabels[state]}`,
				});
		}
		const unknown = sessions.filter((s) => s.observation !== "observed").length;
		if (unknown > 0)
			chips.push({
				tone: "neutral",
				label: `${runtimeLabels.unknown} ${unknown}`,
			});
	} else {
		chips.push({ tone: "neutral", label: inventoryTag(row) });
	}
	if (row.task.notiCount > 0)
		chips.push({ tone: "notify", label: `알림 ${row.task.notiCount}` });
	return chips;
}

type BoardContext = {
	readonly now: number;
	readonly notes: RepoNotes;
	readonly expandedKeys: ReadonlySet<string>;
	readonly toggleExpanded: (key: string) => void;
	readonly noteEdit: NoteEdit | undefined;
	readonly startNote: (id: string, text: string) => void;
	readonly changeNote: (id: string, text: string) => void;
	readonly finishNote: (id: string, key: string, save: boolean) => void;
	readonly onAction: TaskActionHandler;
	readonly onSelect: (key: string) => void;
	readonly selectedKey: string | undefined;
};

function TaskLaunchers({
	row,
	onAction,
}: {
	readonly row: MainTaskRow;
	readonly onAction: TaskActionHandler;
}) {
	return (
		<div className="stage-actions">
			{taskActionsFor(row.task).map((action) => (
				<button
					key={action.kind}
					type="button"
					aria-label={action.ariaLabel}
					className="task-action"
					title={action.label}
					disabled={action.disabled}
					onClick={() => onAction(row.root, row.task, action.kind)}
				>
					<TaskActionIcon kind={action.kind} />
				</button>
			))}
		</div>
	);
}

function SessionDetail({
	session,
	now,
}: {
	readonly session: AgentSession;
	readonly now: number;
}) {
	return (
		<section
			className="runtime-session"
			aria-label={`${PROVIDER_NAMES[session.provider]} session`}
		>
			<header>
				<ProviderIcon provider={session.provider} />
				<span>
					{session.observation === "observed"
						? runtimeLabels[session.state]
						: "상태 확인 불가"}
					{session.reason ? ` · ${session.reason}` : ""}
				</span>
			</header>
			<small>
				마지막 관측 {formatObservedAgo(session.updatedAt, now)} ·{" "}
				{session.sessionId.slice(0, 12)}
			</small>
			{session.prompt ? <p>{session.prompt}</p> : null}
			{session.activity ? <code>{session.activity}</code> : null}
			{session.response ? (
				<div className="runtime-response">
					<small>마지막 응답 · 발췌</small>
					<p>{session.response}</p>
				</div>
			) : null}
			{session.outcome === "error" || session.outcome === "interrupted" ? (
				<span className="runtime-outcome">{session.outcome}</span>
			) : null}
		</section>
	);
}

function RuntimeCard({
	board,
	row,
	variant,
}: {
	readonly board: BoardContext;
	readonly row: MainTaskRow;
	readonly variant: "card" | "row";
}) {
	const expanded = board.expandedKeys.has(row.key);
	const lead = row.sessions[0];
	const ideEnabled = row.task.repos.length > 0;
	// Review cards surface the agent's last answer; live cards surface the tool.
	const excerpt =
		row.role === "finished" && lead?.response ? lead.response : lead?.activity;
	// Worktree repos usually share the task branch; name it once per card.
	const sharedBranch =
		row.repos.length > 0 &&
		row.repos.every((r) => r.branch === row.repos[0]?.branch)
			? row.repos[0]?.branch
			: undefined;
	const handleClick = (event: MouseEvent<HTMLButtonElement>): void => {
		// The second click of a double-click belongs to the IDE gesture.
		if (event.detail > 1) return;
		board.toggleExpanded(row.key);
		board.onSelect(row.key);
	};
	const handleDoubleClick = (): void => {
		board.toggleExpanded(row.key);
		if (ideEnabled) board.onAction(row.root, row.task, "ide");
	};

	return (
		<article
			className="runtime-card"
			data-selected={board.selectedKey === row.key}
			data-provider={lead?.provider}
			data-state={row.role}
			data-variant={variant}
		>
			<div className="runtime-card-head">
				<button
					aria-expanded={expanded}
					className="runtime-card-toggle"
					onClick={handleClick}
					onDoubleClick={handleDoubleClick}
					type="button"
				>
					<span className="runtime-project" title={row.project}>
						{row.project}
					</span>
					<span className="runtime-task-name">{row.task.name}</span>
					{lead?.prompt ? (
						<span className="runtime-title">{lead.prompt}</span>
					) : null}
					<span className="runtime-live">
						{runtimeChips(row).map((chip) => (
							<span
								className="runtime-chip"
								data-tone={chip.tone}
								key={chip.label}
							>
								{chip.label}
							</span>
						))}
						{lead ? (
							<span className="runtime-meta">
								{sessionProviders(row.sessions).map((provider) => (
									<ProviderIcon key={provider} provider={provider} />
								))}
								<span>{formatObservedAgo(lead.updatedAt, board.now)}</span>
							</span>
						) : null}
					</span>
					{excerpt ? (
						<code
							className="runtime-excerpt"
							data-kind={excerpt === lead?.activity ? "activity" : "response"}
							title={excerpt}
						>
							{excerpt}
						</code>
					) : null}
				</button>
				<TaskLaunchers row={row} onAction={board.onAction} />
			</div>
			{row.repos.length === 0 ? (
				<p className="stage-repo-empty">NO REPOSITORIES</p>
			) : (
				<div className="stage-repo-list">
					{sharedBranch === undefined ? null : (
						<div className="runtime-branch" title={`branch: ${sharedBranch}`}>
							<BranchIcon />
							<span>{sharedBranch}</span>
						</div>
					)}
					{row.repos.map((repo) => {
						const key = repoNoteKey(repo.name, repo.branch);
						const id = `${row.key}|${key}`;
						const editing = board.noteEdit?.id === id;
						const note = board.notes[key];
						return (
							<StageRepoRow
								key={repo.name}
								draft={editing ? (board.noteEdit?.draft ?? "") : ""}
								editing={editing}
								note={note}
								nowSeconds={board.now}
								onCancelEdit={() => board.finishNote(id, key, false)}
								onDraftChange={(text) => board.changeNote(id, text)}
								onSaveEdit={() => board.finishNote(id, key, true)}
								onStartEdit={() => board.startNote(id, note ?? "")}
								repo={repo}
								showBranch={sharedBranch === undefined}
								showCommit={expanded}
							/>
						);
					})}
				</div>
			)}
			{expanded && row.sessions.length > 0 ? (
				<div className="runtime-details">
					{row.sessions.map((s) => (
						<SessionDetail key={sessionKey(s)} session={s} now={board.now} />
					))}
				</div>
			) : null}
		</article>
	);
}

export function StageBoard(props: StageBoardProps) {
	const now = useCurrentEpochSeconds();
	// Cards move between column parents, so per-card UI state lives here.
	const [expandedKeys, setExpandedKeys] = useState<ReadonlySet<string>>(
		() => new Set(),
	);
	const [noteEdit, setNoteEdit] = useState<NoteEdit>();
	const noteEditRef = useRef<NoteEdit>();
	const updateNoteEdit = (next: NoteEdit | undefined): void => {
		noteEditRef.current = next;
		setNoteEdit(next);
	};
	const board: BoardContext = {
		now,
		notes: props.notes,
		expandedKeys,
		toggleExpanded: (key) =>
			setExpandedKeys((current) => {
				const next = new Set(current);
				if (!next.delete(key)) next.add(key);
				return next;
			}),
		noteEdit,
		startNote: (id, text) => updateNoteEdit({ id, draft: text }),
		changeNote: (id, text) => updateNoteEdit({ id, draft: text }),
		finishNote: (id, key, save) => {
			const current = noteEditRef.current;
			if (current?.id !== id) return;
			updateNoteEdit(undefined);
			if (save) props.onSaveNote(key, current.draft);
		},
		onAction: props.onAction,
		onSelect: props.onSelect,
		selectedKey: props.selectedKey,
	};
	const rowsFor = (column: MatrixColumn): readonly MainTaskRow[] =>
		props.groups.find((g) => g.column === column)?.rows ?? [];
	const inventoryRows = [...rowsFor("unknown"), ...props.idleRows].sort(
		compareMainTaskRows,
	);
	const baseHealths = props.baseRows.map((row) => baseRepoHealth(row.repo));
	const baseIssueCount = baseHealths.filter((h) => h !== "ok").length;
	const baseHealth = baseHealths.includes("bad")
		? "bad"
		: baseIssueCount > 0
			? "warn"
			: "ok";
	const sessions = [
		...props.groups.flatMap((g) => g.rows),
		...props.idleRows,
	].flatMap((r) => r.sessions);
	return (
		<section className="runtime-board" aria-label="Agent runtime">
			<div className="runtime-summary">
				<span className="runtime-summary-label">SESSIONS</span>
				{["waiting", "running", "finished", "unknown"].map((state) => (
					<span key={state} data-state={state}>
						<i className="runtime-dot" data-state={state} />
						{runtimeLabels[state as MatrixColumn]}{" "}
						<b>
							{
								sessions.filter((s) =>
									state === "unknown"
										? s.observation !== "observed"
										: s.observation === "observed" && s.state === state,
								).length
							}
						</b>
					</span>
				))}
			</div>
			<div className="runtime-columns">
				{BOARD_COLUMNS.map((column) => {
					const rows = rowsFor(column);
					return (
						<section
							aria-label={COLUMN_COPY[column].label}
							className="runtime-column"
							data-state={column}
							key={column}
						>
							<h2 className="runtime-column-head">
								<i className="runtime-dot" data-state={column} />
								{COLUMN_COPY[column].label}
								<span className="runtime-column-code">
									{COLUMN_COPY[column].code}
								</span>
								<small title={`${rows.length} workspaces`}>{rows.length}</small>
							</h2>
							{rows.length === 0 ? (
								<p className="runtime-column-empty">없음</p>
							) : (
								rows.map((row) => (
									<RuntimeCard
										board={board}
										key={row.key}
										row={row}
										variant="card"
									/>
								))
							)}
						</section>
					);
				})}
			</div>
			{inventoryRows.length > 0 ? (
				<section className="runtime-inventory" aria-label="Workspaces">
					<h2 className="runtime-inventory-head">
						<span>WORKSPACES · 세션 없음 / 관측 불명 / 비활성</span>
						<small>{inventoryRows.length}</small>
					</h2>
					{inventoryRows.map((row) => (
						<RuntimeCard board={board} key={row.key} row={row} variant="row" />
					))}
				</section>
			) : null}
			{props.baseRows.length > 0 ? (
				<details className="runtime-bases">
					<summary data-health={baseHealth}>
						<span>BASE REPOSITORIES · 새 workspace의 기준</span>
						<span className="runtime-bases-meta">
							{baseIssueCount > 0 ? (
								<span className="runtime-bases-issues">
									{baseIssueCount} {baseIssueCount === 1 ? "issue" : "issues"}
								</span>
							) : null}
							<small>{props.baseRows.length}</small>
							<span aria-hidden="true" className="runtime-bases-chevron" />
						</span>
					</summary>
					{props.baseRows.map((row) => (
						<BaseRepoRow key={row.key} row={row} />
					))}
				</details>
			) : null}
		</section>
	);
}
