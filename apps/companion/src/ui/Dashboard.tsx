// The full-screen dashboard (COMP001): a clock and the active total with
// per-state counts on top, the tasks as rings below (COMP004 R5, R6).
// View-only: any input locks the Mac before this page could act on it, so it
// renders no controls.
import type {
	DashboardColumnKey,
	DashboardModel,
} from "../application/dashboard";
import type { DashboardLayout } from "../application/dashboardLayout";
import type { CompanionFont, CompanionTheme } from "../application/preferences";
import type { RingModel } from "../application/ring";
import { DashboardRing, formatElapsed, summaryLine } from "./DashboardRing";
import { SegmentClock } from "./SegmentClock";

/** Header counts follow the work's flow: running, then waiting on me, then done. */
const COUNT_ORDER: readonly DashboardColumnKey[] = [
	"running",
	"waiting",
	"finished",
];

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

// Tasks without a ring, in one line under the rings: each by its branch and
// how long it has been in its state.
function More({
	tasks,
	now,
}: {
	readonly tasks: readonly RingModel[];
	readonly now: number;
}) {
	if (tasks.length === 0) return null;
	return (
		<p className="rings-more">
			+{tasks.length} more
			{tasks.map((task) => (
				<span key={task.key}>
					{" · "}
					<span className="rings-more-name">{task.title}</span>{" "}
					<span className="rings-more-status" data-state={task.state}>
						{COUNT_LABELS[task.state]} {formatElapsed(now - task.since)}
						{task.state === "finished" && task.summary !== undefined
							? ` · ${summaryLine(task.summary)}`
							: ""}
					</span>
				</span>
			))}
		</p>
	);
}

function Rings({
	layout,
	now,
}: {
	readonly layout: DashboardLayout<RingModel>;
	readonly now: number;
}) {
	if (layout.rings.length === 0)
		return <p className="rings-empty">진행 중인 작업 없음</p>;
	return (
		<>
			<section
				aria-label="작업"
				className="rings"
				data-columns={layout.columns}
				data-mode={layout.mode}
			>
				{layout.rings.map((ring) => (
					<DashboardRing
						key={ring.key}
						now={now}
						ring={ring}
						size={layout.mode === "large" ? "large" : "compact"}
					/>
				))}
			</section>
			<More now={now} tasks={layout.overflow} />
		</>
	);
}

export function Dashboard({
	model,
	now,
	theme,
	font,
	lockAvailable,
	preview = false,
}: DashboardProps) {
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
					<div className="dashboard-count" data-state="active">
						<dt className="dashboard-count-label">활성 세션</dt>
						<dd className="dashboard-count-value">{model.active}</dd>
					</div>
					{COUNT_ORDER.map((key) => (
						<div className="dashboard-count" data-state={key} key={key}>
							<dt className="dashboard-count-label">{COUNT_LABELS[key]}</dt>
							<dd className="dashboard-count-value">{model.counts[key]}</dd>
						</div>
					))}
				</dl>
			</header>
			<Rings layout={model.layout} now={Math.floor(now.getTime() / 1000)} />
		</main>
	);
}
