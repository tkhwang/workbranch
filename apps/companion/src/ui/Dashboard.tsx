// The full-screen dashboard (COMP001, design D with the detailed cards of E):
// a clock and the live counts on top, the board's three columns below.
// View-only: any input locks the Mac before this page could act on it, so it
// renders no controls.
import {
	DASHBOARD_COLUMNS,
	type DashboardCard,
	type DashboardChanges,
	type DashboardColumnKey,
	type DashboardModel,
} from "../application/dashboard";
import type { CompanionFont, CompanionTheme } from "../application/preferences";
import { COLUMN_COPY, OUTCOME_LABELS, WAIT_REASON_LABELS } from "./boardCopy";
import { SegmentClock } from "./SegmentClock";
import { formatRelativeTime } from "./TaskRow";

/**
 * Cards per column. Card lines are clamped and sized to the screen height
 * (dashboard.css), so three of the tallest cards fit under the header on any
 * display and the count needs no measuring.
 */
export const DASHBOARD_CARDS_PER_COLUMN = 3;

const COUNT_LABELS: Readonly<Record<DashboardColumnKey, string>> = {
	waiting: "내 응답 대기",
	running: "실행 중",
	finished: "턴 종료",
};

const WEEKDAYS = "일월화수목금토";

function dateLabel(now: Date): string {
	return `${now.getMonth() + 1}월 ${now.getDate()}일 ${WEEKDAYS.charAt(now.getDay())}요일`;
}

function LockIcon() {
	return (
		<svg
			aria-hidden="true"
			className="dashboard-lock-icon"
			fill="none"
			stroke="currentColor"
			strokeLinecap="round"
			strokeLinejoin="round"
			strokeWidth="2"
			viewBox="0 0 24 24"
		>
			<rect height="10" rx="2" width="14" x="5" y="11" />
			<path d="M8 11V7a4 4 0 0 1 8 0v4" />
		</svg>
	);
}

type ChangeFact = {
	readonly tone: "dirty" | "ahead" | "behind";
	readonly label: string;
};

// The menu bar's compact facts, summed over the task's repos. A clean task
// shows none: on a screen read from afar, only what changed is worth a glyph.
function changeFacts(changes: DashboardChanges): readonly ChangeFact[] {
	const facts: ChangeFact[] = [];
	if (changes.dirty)
		facts.push({
			tone: "dirty",
			label: changes.files > 0 ? `●${changes.files}` : "●",
		});
	if (changes.ahead > 0)
		facts.push({ tone: "ahead", label: `↑${changes.ahead}` });
	if (changes.behind > 0)
		facts.push({ tone: "behind", label: `↓${changes.behind}` });
	return facts;
}

function detailLabel(
	card: DashboardCard,
	column: DashboardColumnKey,
): string | undefined {
	if (column === "waiting")
		return card.reason === undefined
			? undefined
			: (WAIT_REASON_LABELS[card.reason] ?? COLUMN_COPY.waiting.label);
	if (column === "finished") {
		if (card.outcome !== undefined) return OUTCOME_LABELS[card.outcome];
		if (card.detail?.kind === "response") return "마지막 응답";
	}
	return undefined;
}

// What the lead session waits on, runs, or answered last. The inner paragraph
// is clamped in CSS so a long excerpt never makes the card taller than its
// budget; the outer box carries the padding, which a clamp would not clip.
function CardDetail({
	card,
	column,
}: {
	readonly card: DashboardCard;
	readonly column: DashboardColumnKey;
}) {
	const label = detailLabel(card, column);
	if (label === undefined && card.detail === undefined) return null;
	return (
		<div
			className="dashboard-card-detail"
			data-state={column}
			data-kind={card.detail?.kind}
			data-outcome={card.outcome}
		>
			<p className="dashboard-card-detail-text">
				{label === undefined ? null : (
					<span className="dashboard-card-label">{label}</span>
				)}
				{card.detail?.text}
			</p>
		</div>
	);
}

function Card({
	card,
	column,
	nowSeconds,
}: {
	readonly card: DashboardCard;
	readonly column: DashboardColumnKey;
	readonly nowSeconds: number;
}) {
	const where = [card.repo, card.branch]
		.filter((part) => part !== undefined && part !== "")
		.join(" · ");
	const facts = changeFacts(card.changes);
	return (
		<article className="dashboard-card" data-state={column}>
			<div className="dashboard-card-head">
				<span className="dashboard-card-task">{card.task}</span>
				<span className="dashboard-card-time">
					{formatRelativeTime(card.since, nowSeconds)}
				</span>
			</div>
			{card.prompt === undefined ? null : (
				<p className="dashboard-card-prompt">{card.prompt}</p>
			)}
			<CardDetail card={card} column={column} />
			<div className="dashboard-card-meta">
				{card.agent === undefined ? null : (
					<span className="dashboard-card-agent">{card.agent}</span>
				)}
				{where === "" ? null : (
					<span className="dashboard-card-where">{where}</span>
				)}
				{facts.length === 0 ? null : (
					<span className="dashboard-card-changes">
						{facts.map((fact) => (
							<span data-tone={fact.tone} key={fact.tone}>
								{fact.label}
							</span>
						))}
					</span>
				)}
				{card.notifications > 0 ? (
					<span className="dashboard-card-notify">
						알림 {card.notifications}
					</span>
				) : null}
			</div>
		</article>
	);
}

type DashboardProps = {
	readonly model: DashboardModel;
	readonly now: Date;
	readonly theme: CompanionTheme;
	readonly font?: CompanionFont;
	/** Shown only when the Mac really locks under the dashboard (COMP001 R7). */
	readonly lockAvailable: boolean;
	/** Opened from Settings: input closes it, nothing locks (R12). */
	readonly preview?: boolean;
};

export function Dashboard({
	model,
	now,
	theme,
	font,
	lockAvailable,
	preview = false,
}: DashboardProps) {
	const nowSeconds = Math.floor(now.getTime() / 1000);
	return (
		<main className="dashboard" data-font={font} data-theme={theme}>
			<header className="dashboard-top">
				<div className="dashboard-time">
					<SegmentClock now={now} />
					<div className="dashboard-time-meta">
						<span className="dashboard-date">{dateLabel(now)}</span>
						{preview ? (
							<span className="dashboard-lock">미리 보기 · 입력하면 닫힘</span>
						) : lockAvailable ? (
							<span className="dashboard-lock">
								<LockIcon />
								화면 잠김
							</span>
						) : null}
					</div>
				</div>
				<dl className="dashboard-counts">
					{DASHBOARD_COLUMNS.map((key) => (
						<div className="dashboard-count" data-state={key} key={key}>
							<dt className="dashboard-count-label">{COUNT_LABELS[key]}</dt>
							<dd className="dashboard-count-value">{model.counts[key]}</dd>
						</div>
					))}
				</dl>
			</header>
			<section aria-label="진행 중인 작업" className="dashboard-board">
				{model.columns.map((column) => (
					<section
						aria-label={COLUMN_COPY[column.key].label}
						className="dashboard-column"
						data-state={column.key}
						key={column.key}
					>
						<h2 className="dashboard-column-head">
							<i
								aria-hidden="true"
								className="dashboard-dot"
								data-state={column.key}
							/>
							{COLUMN_COPY[column.key].label}
							<span className="dashboard-column-code">
								{COLUMN_COPY[column.key].code}
							</span>
						</h2>
						{column.cards.length === 0 ? (
							<p className="dashboard-empty">없음</p>
						) : (
							column.cards.map((card) => (
								<Card
									card={card}
									column={column.key}
									key={card.key}
									nowSeconds={nowSeconds}
								/>
							))
						)}
						{column.more > 0 ? (
							<p className="dashboard-more">+{column.more} more</p>
						) : null}
					</section>
				))}
			</section>
		</main>
	);
}
