import { useEffect, useRef, useState } from "react";
import { type RepoNotes, repoNoteKey } from "../application/notes";
import type {
	MainBaseRow,
	MainStageGroup,
	MainTaskRow,
} from "../application/state";
import type { BaseRepoAction, MatrixColumn, Repo } from "../domain/model";
import {
	baseRepoAction,
	baseRepoHealth,
	runtimeLabels,
	sessionKey,
} from "../domain/model";
import {
	baseRepoFacts,
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

function StageRepoRow({
	note,
	nowSeconds,
	onSaveNote,
	repo,
}: {
	readonly note: string | undefined;
	readonly nowSeconds: number;
	readonly onSaveNote: (key: string, text: string) => void;
	readonly repo: Repo;
}) {
	const key = repoNoteKey(repo.name, repo.branch);
	const [editing, setEditing] = useState(false);
	const [draft, setDraft] = useState(note ?? "");
	const textareaRef = useRef<HTMLTextAreaElement>(null);
	const relativeTime = formatRelativeTime(repo.lastCommitAt, nowSeconds);
	const commit =
		repo.lastCommitSubject === ""
			? ""
			: repo.lastCommitSubject +
				(relativeTime === "" ? "" : " · " + relativeTime);

	const saveAndClose = (): void => {
		onSaveNote(key, draft);
		setEditing(false);
	};

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
					{repo.dirty ? (
						<span aria-label="dirty" className="stage-repo-dot" role="img">
							●
						</span>
					) : null}
				</span>
				<span className="stage-repo-branch" title={repo.branch}>
					{repo.branch}
				</span>
				<span className="stage-repo-facts">{repoFacts(repo)}</span>
				<button
					aria-expanded={editing}
					aria-label={"edit note for " + repo.name + " " + repo.branch}
					className="stage-note-button"
					data-has-note={note === undefined ? "false" : "true"}
					onClick={() => {
						setDraft(note ?? "");
						setEditing(true);
					}}
					type="button"
				>
					✎
				</button>
			</div>
			{commit === "" ? null : (
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
						onBlur={saveAndClose}
						onChange={(event) => setDraft(event.currentTarget.value)}
						onKeyDown={(event) => {
							if (event.key === "Escape") {
								event.preventDefault();
								setDraft(note ?? "");
								setEditing(false);
								return;
							}
							if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
								event.preventDefault();
								saveAndClose();
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
function RuntimeTask({
	row,
	props,
	now,
}: {
	readonly row: MainTaskRow;
	readonly props: StageBoardProps;
	readonly now: number;
}) {
	const [expanded, setExpanded] = useState(false);
	const lead = row.sessions[0];
	const counts = (["waiting", "running", "finished"] as const).map((state) => ({
		state,
		count: row.sessions.filter(
			(s) => s.state === state && s.observation === "observed",
		).length,
	}));
	const unknown = row.sessions.filter(
		(s) => s.observation !== "observed",
	).length;
	return (
		<article
			className="runtime-task"
			data-state={row.role}
			data-selected={props.selectedKey === row.key}
		>
			<button
				className="runtime-task-heading"
				type="button"
				aria-expanded={expanded}
				onClick={() => {
					setExpanded(!expanded);
					props.onSelect(row.key);
				}}
			>
				<span className="runtime-identity">
					{row.project} / {row.task.name}
					<span>{expanded ? "−" : "+"}</span>
				</span>
				<strong className="runtime-title">
					{lead?.prompt || row.task.name}
				</strong>
				<span className="runtime-counts">
					{row.task.notiCount > 0 ? (
						<span>알림 {row.task.notiCount}</span>
					) : null}
					{counts
						.filter((c) => c.count > 0)
						.map((c) => (
							<span key={c.state}>
								{c.state === "waiting"
									? "대기"
									: c.state === "running"
										? "실행 중"
										: "턴 종료"}{" "}
								{c.count}
							</span>
						))}
					{unknown > 0 ? <span>관측 불명 {unknown}</span> : null}
					{row.sessions.length === 0 ? (
						<span>아직 수집된 session이 없습니다</span>
					) : null}
				</span>
			</button>
			{lead ? (
				<div className="runtime-activity">
					<span className="runtime-provider">{lead.provider}</span>
					<span>
						{lead.observation !== "observed"
							? "상태 확인 불가"
							: lead.reason || runtimeLabels[lead.state]}{" "}
						· {formatRelativeTime(lead.updatedAt, now)} 전
					</span>
					<code title={lead.activity}>{lead.activity}</code>
				</div>
			) : null}
			{expanded ? (
				<div className="runtime-details">
					{row.sessions.map((s) => (
						<section
							className="runtime-session"
							key={sessionKey(s)}
							aria-label={`${s.provider} session`}
						>
							<header>
								<b>{s.provider}</b>
								<span>
									{s.observation === "observed"
										? runtimeLabels[s.state]
										: "상태 확인 불가"}
									{s.reason ? ` · ${s.reason}` : ""}
								</span>
							</header>
							<small>
								마지막 관측 {formatRelativeTime(s.updatedAt, now)} 전 ·{" "}
								{s.sessionId.slice(0, 12)}
							</small>
							{s.prompt ? <p>{s.prompt}</p> : null}
							{s.activity ? <code>{s.activity}</code> : null}
							{s.response ? (
								<div className="runtime-response">
									<small>마지막 응답 · 발췌</small>
									<p>{s.response}</p>
								</div>
							) : null}
							{s.outcome === "error" || s.outcome === "interrupted" ? (
								<span className="runtime-outcome">{s.outcome}</span>
							) : null}
						</section>
					))}
					<div className="stage-actions">
						{taskActionsFor(row.task).map((action) => (
							<button
								key={action.kind}
								type="button"
								aria-label={action.ariaLabel}
								className="task-action"
								title={action.label}
								disabled={action.disabled}
								onClick={() => props.onAction(row.root, row.task, action.kind)}
							>
								<TaskActionIcon kind={action.kind} />
							</button>
						))}
					</div>
					{row.repos.map((repo) => (
						<StageRepoRow
							key={repo.name}
							repo={repo}
							nowSeconds={now}
							note={props.notes[repoNoteKey(repo.name, repo.branch)]}
							onSaveNote={props.onSaveNote}
						/>
					))}
				</div>
			) : null}
		</article>
	);
}
export function StageBoard(props: StageBoardProps) {
	const now = useCurrentEpochSeconds();
	const sessions = [
		...props.groups.flatMap((g) => g.rows),
		...props.idleRows,
	].flatMap((r) => r.sessions);
	return (
		<section className="runtime-board" aria-label="Agent runtime">
			<div className="runtime-summary">
				{["waiting", "running", "finished", "unknown"].map((state) => (
					<span key={state} data-state={state}>
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
			<div className="runtime-group">
				{[...props.groups, { column: "idle" as const, rows: props.idleRows }]
					.filter((g) => g.rows.length > 0)
					.flatMap((group) => [
						<h2 key={`header:${group.column}`}>
							<i data-state={group.column} />
							{runtimeLabels[group.column]}
							<small>{group.rows.length} workspaces</small>
						</h2>,
						...group.rows.map((row) => (
							<RuntimeTask key={row.key} row={row} props={props} now={now} />
						)),
					])}
			</div>
			{props.baseRows.length > 0 ? (
				<details className="runtime-bases">
					<summary>Base repositories · {props.baseRows.length}</summary>
					{props.baseRows.map((row) => (
						<BaseRepoRow key={row.key} row={row} />
					))}
				</details>
			) : null}
		</section>
	);
}
