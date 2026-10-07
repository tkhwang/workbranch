import type { CSSProperties } from "react";
import {
	type DailyUsage,
	formatAge,
	formatTokens,
	type LimitView,
	limitDetail,
	type ProviderSummary,
	planLabel,
	type UsageProvider,
} from "../domain/usage";
import { ProviderIcon } from "./ProviderIcon";

export const USAGE_PROVIDER_LABELS = {
	claude: "Claude",
	codex: "Codex",
} as const satisfies Record<UsageProvider, string>;

const LIMIT_HINTS = {
	claude: "Claude Code에서 /usage를 열면 표시됩니다",
	codex: "Codex가 다음 응답을 마치면 표시됩니다",
} as const satisfies Record<UsageProvider, string>;

function percentStyle(percent: number): CSSProperties {
	return { width: `${percent.toFixed(1)}%` };
}

export function UsageHeading({
	summary,
	nowSeconds,
}: {
	readonly summary: ProviderSummary;
	readonly nowSeconds: number;
}) {
	const plan = planLabel(summary.plan);
	return (
		<div className="usage-heading">
			<span className="usage-name">
				<ProviderIcon provider={summary.provider} />
				{USAGE_PROVIDER_LABELS[summary.provider]}
				{plan ? <span className="usage-plan">{plan}</span> : null}
			</span>
			{summary.observedAt !== null ? (
				<span
					className="usage-age"
					data-stale={summary.stale ? "true" : undefined}
					title="한도 값을 마지막으로 관측한 시각"
				>
					{formatAge(Math.max(0, nowSeconds - summary.observedAt))} 관측
				</span>
			) : null}
		</div>
	);
}

export function UsageLimitRow({
	limit,
	nowSeconds,
	variant,
}: {
	readonly limit: LimitView;
	readonly nowSeconds: number;
	readonly variant: "compact" | "detail";
}) {
	const percent = `${Math.round(limit.usedPercent)}%`;
	const detail = limitDetail(limit, nowSeconds);
	const bar = (
		<span className="usage-track">
			<span className="usage-fill" style={percentStyle(limit.usedPercent)} />
		</span>
	);
	return (
		<div
			className="usage-limit"
			data-stale={limit.stale ? "true" : undefined}
			data-state={limit.state}
			data-variant={variant}
			title={limit.stale ? "오래된 관측값" : undefined}
		>
			<span className="usage-limit-label">{limit.label}</span>
			{variant === "compact" ? bar : null}
			<span className="usage-limit-percent">{percent}</span>
			{variant === "detail" ? bar : null}
			<span className="usage-limit-detail">{detail}</span>
		</div>
	);
}

export function UsageLimits({
	summary,
	nowSeconds,
	variant,
}: {
	readonly summary: ProviderSummary;
	readonly nowSeconds: number;
	readonly variant: "compact" | "detail";
}) {
	if (summary.limits.length === 0) {
		return (
			<p className="usage-note">
				한도 정보 없음 · {LIMIT_HINTS[summary.provider]}
			</p>
		);
	}
	return (
		<>
			{summary.limits.map((limit) => (
				<UsageLimitRow
					key={limit.windowMinutes}
					limit={limit}
					nowSeconds={nowSeconds}
					variant={variant}
				/>
			))}
		</>
	);
}

function barHeight(value: number, peak: number): CSSProperties {
	const ratio = peak > 0 ? value / peak : 0;
	return { height: `${Math.max(value > 0 ? 3 : 1, Math.round(ratio * 100))}%` };
}

const WEEKDAY_SHORT = ["일", "월", "화", "수", "목", "금", "토"] as const;

/** Day of month, with the month on the first day and wherever a month starts. */
export function dayLabel(day: DailyUsage, index: number): string {
	return index === 0 || day.dayOfMonth === "1" ? day.monthDay : day.dayOfMonth;
}

/** Marks a day slot as today or a weekend so the axis and bars share one rhythm. */
export function daySlot(
	day: DailyUsage,
	index: number,
	days: readonly DailyUsage[],
): { "data-today"?: "true"; "data-weekend"?: "true" } {
	return {
		...(index === days.length - 1 ? { "data-today": "true" } : {}),
		...(day.weekday === 0 || day.weekday === 6
			? { "data-weekend": "true" }
			: {}),
	};
}

export function UsageDayAxis({
	days,
}: {
	readonly days: readonly DailyUsage[];
}) {
	return (
		<div aria-hidden="true" className="usage-axis">
			{days.map((day, index) => (
				<span
					className="usage-axis-day"
					key={day.start}
					{...daySlot(day, index, days)}
				>
					<span className="usage-axis-date">{dayLabel(day, index)}</span>
					<span className="usage-axis-weekday">
						{WEEKDAY_SHORT[day.weekday]}
					</span>
				</span>
			))}
		</div>
	);
}

/**
 * Both agents per day on one scale, so each day's split reads directly.
 * The last `dayCount` days end with today; `showValues` prints each agent's
 * total under its day for the short Main window.
 */
export function UsageDailyComparison({
	summaries,
	dayCount,
	showValues,
	title,
}: {
	readonly summaries: readonly ProviderSummary[];
	readonly dayCount: number;
	readonly showValues: boolean;
	readonly title: string;
}) {
	const series = summaries.map((summary) => ({
		provider: summary.provider,
		days: summary.days.slice(-dayCount),
	}));
	const days = series[0]?.days ?? [];
	const peak = Math.max(
		0,
		...series.flatMap((entry) => entry.days.map((day) => day.total)),
	);
	const name = (provider: UsageProvider) =>
		USAGE_PROVIDER_LABELS[provider].toLowerCase();
	const columns = { "--usage-days": String(days.length) } as CSSProperties;
	return (
		<section aria-label={title} className="usage-panel" style={columns}>
			<div className="usage-panel-caption">
				<span>{title}</span>
				<span className="usage-legend">
					{series.map((entry) => (
						<span data-provider={entry.provider} key={entry.provider}>
							<i aria-hidden="true" />
							{name(entry.provider)}
						</span>
					))}
				</span>
			</div>
			<div
				aria-label={`Daily tokens by agent, last ${days.length} days`}
				className="usage-compare"
				data-size={showValues ? "short" : "tall"}
				role="img"
			>
				{days.map((day, index) => (
					<span
						className="usage-compare-day"
						key={day.start}
						{...daySlot(day, index, days)}
						title={`${day.label} · ${series
							.map(
								(entry) =>
									`${name(entry.provider)} ${formatTokens(entry.days[index]?.total ?? 0)}`,
							)
							.join(" · ")}`}
					>
						{series.map((entry) => (
							<span
								className="usage-compare-bar"
								data-provider={entry.provider}
								key={entry.provider}
								style={barHeight(entry.days[index]?.total ?? 0, peak)}
							/>
						))}
					</span>
				))}
			</div>
			<UsageDayAxis days={days} />
			{showValues ? (
				<div className="usage-values">
					{days.map((day, index) => (
						<span
							className="usage-values-day"
							key={day.start}
							{...daySlot(day, index, days)}
						>
							{series.map((entry) => {
								const total = entry.days[index]?.total ?? 0;
								return (
									<span data-provider={entry.provider} key={entry.provider}>
										<span className="usage-sr">{name(entry.provider)} </span>
										{total > 0 ? formatTokens(total) : "—"}
									</span>
								);
							})}
						</span>
					))}
				</div>
			) : null}
		</section>
	);
}

export function UsageUnavailable({
	provider,
}: {
	readonly provider: UsageProvider;
}) {
	return (
		<p className="usage-note">
			{USAGE_PROVIDER_LABELS[provider]} 기록이 없습니다 · 이 Mac에서 실행하면
			표시됩니다
		</p>
	);
}
