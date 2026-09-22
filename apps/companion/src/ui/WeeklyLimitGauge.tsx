import {
	type LimitAccount,
	type LimitAccounts,
	limitAccountDisplayLabel,
} from "../application/limits";
import {
	axisRatio,
	formatMonthDay,
	formatRemaining,
	formatResetDate,
	formatResetPoint,
	LIMIT_AXIS_HALF_SPAN_SECONDS,
	limitAxisDays,
	limitWindowAt,
} from "../domain/limits";
import { useCurrentEpochSeconds } from "./useCurrentEpochSeconds";

export type WeeklyLimitGaugeProps = {
	readonly accounts: LimitAccounts;
	readonly nowSeconds?: number;
};

const SCALE_HEIGHT = 24;
const BAR_TOP = 8;
const BAR_HEIGHT = 8;
const NOW_X = "50.000%";

function percent(ratio: number): string {
	return `${(ratio * 100).toFixed(3)}%`;
}

function LimitRow({
	account,
	gridLines,
	index,
	nowSeconds,
}: {
	readonly account: LimitAccount;
	readonly gridLines: readonly string[];
	readonly index: number;
	readonly nowSeconds: number;
}) {
	const window = limitWindowAt(account, nowSeconds);
	const label = limitAccountDisplayLabel(account, index);
	const startRatio = axisRatio(window.startAt, nowSeconds);
	const endRatio = axisRatio(window.endAt, nowSeconds);
	const start = percent(startRatio);
	const end = percent(endRatio);
	const remaining = formatRemaining(window.remainingSeconds);
	const resetPoint = formatResetPoint(window.endAt);
	const elapsedPercent = Math.round(window.elapsedRatio * 100);

	return (
		<li
			aria-label={`${label}: ${remaining} until reset, ${resetPoint}, ${elapsedPercent}% elapsed`}
			className="limit-row"
			data-phase={window.phase}
			title={`Resets ${formatResetDate(window.endAt)}`}
		>
			<span className="limit-label" title={label}>
				{label}
			</span>
			<svg
				aria-hidden="true"
				className="limit-scale"
				height={SCALE_HEIGHT}
				width="100%"
			>
				{gridLines.map((x) => (
					<line
						className="limit-grid"
						key={x}
						x1={x}
						x2={x}
						y1={0}
						y2={SCALE_HEIGHT}
					/>
				))}
				<rect
					className="limit-rest"
					height={BAR_HEIGHT}
					width={percent(endRatio - 0.5)}
					x={NOW_X}
					y={BAR_TOP}
				/>
				<rect
					className="limit-fill"
					height={BAR_HEIGHT}
					width={percent(0.5 - startRatio)}
					x={start}
					y={BAR_TOP}
				/>
				<line
					className="limit-reset-mark"
					x1={start}
					x2={start}
					y1={5}
					y2={19}
				/>
				<line className="limit-reset-mark" x1={end} x2={end} y1={5} y2={19} />
				<line
					className="limit-now"
					x1={NOW_X}
					x2={NOW_X}
					y1={0}
					y2={SCALE_HEIGHT}
				/>
			</svg>
			<span className="limit-facts">
				<span className="limit-remaining">{remaining}</span>
				<span aria-hidden="true" className="limit-sep">
					·
				</span>
				<span className="limit-reset">{resetPoint}</span>
				{window.phase === "fresh" ? (
					<span className="limit-token">FRESH</span>
				) : null}
				{window.phase === "soon" ? (
					<span className="limit-token">SOON</span>
				) : null}
			</span>
		</li>
	);
}

export function WeeklyLimitGauge({
	accounts,
	nowSeconds,
}: WeeklyLimitGaugeProps) {
	const currentNowSeconds = useCurrentEpochSeconds(nowSeconds);
	if (accounts.length === 0) return null;
	const days = limitAxisDays(currentNowSeconds);
	const gridLines = days.slice(1).map((day) => percent(day.startRatio));
	// Label thinning tiers count from today so the always-visible today label
	// never collides with a neighbour: every 4th day, every 2nd, the rest.
	const todayIndex = Math.max(
		0,
		days.findIndex((day) => day.today),
	);
	const tierFor = (index: number): string => {
		const distance = index - todayIndex;
		return distance % 4 === 0 ? "0" : distance % 2 === 0 ? "1" : "2";
	};
	// Labels near either end anchor inward instead of centring, so a wide
	// "9/16" style label is not clipped by the axis edge.
	const edgeFor = (center: number): "start" | "end" | undefined =>
		center < 0.08 ? "start" : center > 0.92 ? "end" : undefined;

	return (
		<section aria-label="Weekly limits" className="limit-board">
			<h2 className="limit-caption">
				<span>
					WEEKLY LIMITS <span className="limit-count">{accounts.length}</span>
				</span>
				<span className="limit-axis-range">
					{formatMonthDay(currentNowSeconds - LIMIT_AXIS_HALF_SPAN_SECONDS)} –{" "}
					{formatMonthDay(currentNowSeconds + LIMIT_AXIS_HALF_SPAN_SECONDS)}
				</span>
			</h2>
			<div className="limit-table">
				<div aria-hidden="true" className="limit-axis-row">
					<span className="limit-axis-gutter" />
					<div className="limit-axis">
						{days.map((day, index) => {
							const center = (day.startRatio + day.endRatio) / 2;
							return (
								<span
									className="limit-axis-day"
									data-edge={edgeFor(center)}
									data-tier={tierFor(index)}
									data-today={day.today ? "true" : undefined}
									key={percent(day.startRatio)}
									style={{ left: percent(center) }}
								>
									{day.label}
								</span>
							);
						})}
						<span className="limit-axis-now" style={{ left: NOW_X }} />
					</div>
					<span className="limit-axis-gutter" />
				</div>
				<ul className="limit-list">
					{accounts.map((account, index) => (
						<LimitRow
							account={account}
							gridLines={gridLines}
							index={index}
							key={account.id}
							nowSeconds={currentNowSeconds}
						/>
					))}
				</ul>
			</div>
		</section>
	);
}
