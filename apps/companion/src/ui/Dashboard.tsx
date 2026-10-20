// The full-screen dashboard (COMP001): a clock and the active total with
// per-state counts on top, a timeline of the live tasks below.
// View-only: any input locks the Mac before this page could act on it, so it
// renders no controls.
import type {
	DashboardColumnKey,
	DashboardModel,
} from "../application/dashboard";
import type { CompanionFont, CompanionTheme } from "../application/preferences";
import { DashboardTimeline } from "./DashboardTimeline";
import { SegmentClock } from "./SegmentClock";

/**
 * Timeline rows. Rows are sized to the screen height (dashboard.css), so this
 * many fit under the header on any display and the count needs no measuring.
 */
export const DASHBOARD_TIMELINE_ROWS = 8;

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
			<DashboardTimeline
				model={model.timeline}
				now={Math.floor(now.getTime() / 1000)}
			/>
		</main>
	);
}
