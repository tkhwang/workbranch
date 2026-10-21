// The dashboard's timeline: who is doing what, and how the work has flowed.
// Running is a thin continuous line, waiting on me a tall block on it, a turn
// end a dot (a crossed one when it failed), and review waiting a dotted line.
// Positions are percentages of the window, so the strip scales with the screen.
import type {
	TimelineMessage,
	TimelineModel,
	TimelineRow,
	TimelineState,
	TimelineTotals,
} from "../application/timeline";
import { ProviderIcon } from "./ProviderIcon";

const STATE_LABELS: Readonly<Record<TimelineState, string>> = {
	running: "실행 중",
	waiting: "내 응답 대기",
	finished: "턴 종료",
};

/** The time columns follow the header's flow order. */
const TOTAL_ORDER: readonly TimelineState[] = [
	"running",
	"waiting",
	"finished",
];
const TOTAL_LABELS: Readonly<Record<TimelineState, string>> = {
	running: "실행",
	waiting: "대기",
	finished: "종료",
};

const TICK_SECONDS = 30 * 60;
/** A waiting block this long or longer carries its duration. */
const LABEL_MIN_SECONDS = 9 * 60;
/** Ticks this close to now would collide with the "지금" label. */
const NOW_CLEARANCE_SECONDS = 10 * 60;

/** Repo tints in the theme (`--repo-1` … `--repo-4`). */
const REPO_TONES = 4;

/**
 * A repo's tint, 1 to REPO_TONES. Taken from its name, so a repo keeps its
 * color on every row and across restarts, whatever else is on screen.
 */
export function repoTone(name: string): number {
	let hash = 0;
	for (const char of name)
		hash = (hash * 31 + (char.codePointAt(0) ?? 0)) >>> 0;
	return (hash % REPO_TONES) + 1;
}

/** Seconds as h:mm, for the time columns; "–" when none or unknown. */
export function formatClock(seconds: number | undefined): string {
	if (seconds === undefined || seconds < 60) return "–";
	const minutes = Math.floor(seconds / 60);
	return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")}`;
}

/** Seconds as "12m" or "1h 05m", for time in state. */
export function formatElapsed(seconds: number): string {
	const minutes = Math.max(0, Math.floor(seconds / 60));
	if (minutes < 60) return `${minutes}m`;
	return `${Math.floor(minutes / 60)}h ${String(minutes % 60).padStart(2, "0")}m`;
}

const MESSAGE_LABELS: Readonly<Record<TimelineMessage["kind"], string>> = {
	prompt: "요청",
	response: "응답",
	commit: "커밋",
};

/** How long ago, for a message: "방금", "12분 전", "3시간 전", "2일 전". */
export function formatAgo(at: number, now: number): string {
	const minutes = Math.floor(Math.max(0, now - at) / 60);
	if (minutes < 1) return "방금";
	if (minutes < 60) return `${minutes}분 전`;
	const hours = Math.floor(minutes / 60);
	if (hours < 24) return `${hours}시간 전`;
	return `${Math.floor(hours / 24)}일 전`;
}

// Indented under the row's name behind a thin rule, so the details read as
// belonging to that task. The newest message leads in larger, brighter type.
function Messages({
	messages,
	now,
}: {
	readonly messages: readonly TimelineMessage[];
	readonly now: number;
}) {
	if (messages.length === 0)
		return <p className="timeline-messages-empty">최근 메시지 없음</p>;
	return (
		<ol aria-label="최근 메시지" className="timeline-messages">
			{messages.map((message, index) => (
				<li
					className="timeline-message"
					data-latest={index === 0 ? "true" : undefined}
					key={`${message.kind}:${message.at}:${message.text}`}
				>
					<span className="timeline-message-kind" data-kind={message.kind}>
						{MESSAGE_LABELS[message.kind]}
					</span>
					<span className="timeline-message-text">{message.text}</span>
					<span className="timeline-message-ago">
						{formatAgo(message.at, now)}
					</span>
				</li>
			))}
		</ol>
	);
}

function ratio(model: TimelineModel, at: number): number {
	const span = model.end - model.start;
	return span > 0 ? Math.min(1, Math.max(0, (at - model.start) / span)) : 0;
}

function percent(value: number): string {
	return `${(value * 100).toFixed(3)}%`;
}

function position(model: TimelineModel, at: number): string {
	return percent(ratio(model, at));
}

function extent(model: TimelineModel, start: number, end: number): string {
	return percent(ratio(model, end) - ratio(model, start));
}

function ticks(model: TimelineModel): readonly number[] {
	const result: number[] = [];
	const first = Math.ceil(model.start / TICK_SECONDS) * TICK_SECONDS;
	for (let at = first; at <= model.end; at += TICK_SECONDS) result.push(at);
	return result;
}

function clockLabel(at: number): string {
	const date = new Date(at * 1000);
	return `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
}

function totalOf(totals: TimelineTotals | undefined, state: TimelineState) {
	return totals?.[state];
}

function Legend() {
	return (
		<ul aria-label="범례" className="timeline-legend">
			<li>
				<i className="timeline-key" data-key="running" />
				실행 중
			</li>
			<li>
				<i className="timeline-key" data-key="waiting" />내 응답 대기
			</li>
			<li>
				<i className="timeline-key" data-key="end" />턴 종료
			</li>
			<li>
				<i className="timeline-key" data-key="review" />
				검토 대기
			</li>
			<li>
				<i className="timeline-key" data-key="error">
					<ErrorMark />
				</i>
				오류로 끝남
			</li>
		</ul>
	);
}

function ErrorMark() {
	return (
		<svg aria-hidden="true" className="timeline-error-mark" viewBox="0 0 8 8">
			<path d="M1.5 1.5 6.5 6.5M6.5 1.5 1.5 6.5" />
		</svg>
	);
}

function Row({
	row,
	model,
	now,
	showMessages,
}: {
	readonly row: TimelineRow;
	readonly model: TimelineModel;
	readonly now: number;
	readonly showMessages: boolean;
}) {
	return (
		<li className="timeline-grid timeline-row" data-state={row.state}>
			<span className="timeline-agent" data-provider={row.agent}>
				{row.agent === undefined ? null : <ProviderIcon provider={row.agent} />}
			</span>
			<div className="timeline-label">
				<span className="timeline-name">{row.title}</span>
				<span className="timeline-meta">
					<span className="timeline-status" data-state={row.state}>
						{STATE_LABELS[row.state]} {formatElapsed(now - row.since)}
					</span>
					{row.repo === undefined ? null : (
						<span className="timeline-repo">
							<span
								className="timeline-repo-name"
								data-tone={repoTone(row.repo)}
							>
								{row.repo}
							</span>
							{row.moreRepos > 0 ? (
								<span className="timeline-repo-more"> +{row.moreRepos}</span>
							) : null}
						</span>
					)}
				</span>
				{showMessages ? <Messages messages={row.messages} now={now} /> : null}
			</div>
			<div className="timeline-track">
				{row.segments.map((segment) => (
					<span
						className="timeline-segment"
						data-state={segment.state}
						key={`${segment.state}:${segment.start}`}
						style={{
							left: position(model, segment.start),
							width: extent(model, segment.start, segment.end),
						}}
					>
						{segment.state === "waiting" &&
						segment.end - segment.start >= LABEL_MIN_SECONDS
							? formatElapsed(segment.end - segment.start)
							: null}
					</span>
				))}
				{row.turnEnds.map((end) => (
					<span
						className="timeline-end"
						data-error={end.error ? "true" : undefined}
						key={end.at}
						style={{ left: position(model, end.at) }}
					>
						{end.error ? <ErrorMark /> : null}
					</span>
				))}
			</div>
			{TOTAL_ORDER.map((state) => {
				const seconds = totalOf(row.totals, state);
				return (
					<span
						className="timeline-cell"
						data-empty={formatClock(seconds) === "–" ? "true" : undefined}
						data-state={state}
						key={state}
					>
						{formatClock(seconds)}
					</span>
				);
			})}
		</li>
	);
}

export function DashboardTimeline({
	model,
	now,
	showMessages = false,
}: {
	readonly model: TimelineModel;
	/** Epoch seconds. */
	readonly now: number;
	/** Lists each row's recent messages under its name. */
	readonly showMessages?: boolean;
}) {
	const marks = ticks(model);
	return (
		<section
			aria-label="타임라인"
			className="timeline"
			data-messages={showMessages ? "true" : undefined}
		>
			<div className="timeline-grid timeline-head">
				<div className="timeline-heading">
					<h2 className="timeline-title">
						TIMELINE <span className="timeline-window">최근 3시간</span>
					</h2>
					<Legend />
					{model.logged ? null : (
						<p className="timeline-note">
							상태 기록은 workbranch CLI 를 업데이트한 뒤부터 쌓입니다
						</p>
					)}
				</div>
				<span className="timeline-caption">세션 전체</span>
				<dl className="timeline-totals">
					{TOTAL_ORDER.map((state) => (
						<div className="timeline-total" data-state={state} key={state}>
							<dt>{TOTAL_LABELS[state]}</dt>
							<dd>{formatClock(totalOf(model.totals, state))}</dd>
						</div>
					))}
				</dl>
			</div>
			<div className="timeline-body">
				<div aria-hidden="true" className="timeline-grid timeline-guides">
					<div className="timeline-ticks">
						{marks.map((at) => (
							<i
								className="timeline-tick"
								key={at}
								style={{ left: position(model, at) }}
							/>
						))}
						<i className="timeline-now" />
					</div>
					<i className="timeline-guide" data-first="true" />
					<i className="timeline-guide" />
					<i className="timeline-guide" />
				</div>
				{model.rows.length === 0 ? (
					<p className="timeline-empty">진행 중인 작업 없음</p>
				) : (
					<ol className="timeline-rows">
						{model.rows.map((row) => (
							<Row
								key={row.key}
								model={model}
								now={now}
								row={row}
								showMessages={showMessages}
							/>
						))}
					</ol>
				)}
			</div>
			<div aria-hidden="true" className="timeline-grid timeline-axis">
				<span className="timeline-more">
					{model.more > 0 ? `+${model.more} more` : null}
				</span>
				<div className="timeline-axis-track">
					{marks
						.filter((at) => model.end - at >= NOW_CLEARANCE_SECONDS)
						.map((at) => (
							<span
								className="timeline-tick-label"
								key={at}
								style={{ left: position(model, at) }}
							>
								{clockLabel(at)}
							</span>
						))}
					<span className="timeline-now-label">지금</span>
				</div>
			</div>
		</section>
	);
}
