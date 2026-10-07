import {
	formatTokens,
	type ProviderSummary,
	summarizeProvider,
	USAGE_DAYS,
	USAGE_PROVIDERS,
	type UsageSnapshot,
} from "../domain/usage";
import {
	USAGE_PROVIDER_LABELS,
	UsageDailyComparison,
	UsageHeading,
	UsageLimits,
	UsageUnavailable,
} from "./UsageParts";
import { useCurrentEpochSeconds } from "./useCurrentEpochSeconds";

export type UsageViewProps = {
	readonly snapshot: UsageSnapshot | undefined;
	readonly error: string | undefined;
	readonly nowSeconds?: number;
};

const TABLE_DAYS = 7;

function TodayBreakdown({ summary }: { readonly summary: ProviderSummary }) {
	const today = summary.today;
	const yesterday = summary.days.at(-2);
	return (
		<div className="usage-today">
			<span className="usage-today-total">
				<span className="usage-label">TODAY</span>
				<b>{formatTokens(today?.total ?? 0)}</b>
			</span>
			<span className="usage-today-parts">
				{today && today.total > 0 ? (
					<>
						<span>
							in {formatTokens(today.tokens.input)} · out{" "}
							{formatTokens(today.tokens.output)}
						</span>
						<span>
							cache r {formatTokens(today.tokens.cacheRead)} · w{" "}
							{formatTokens(today.tokens.cacheWrite)}
						</span>
					</>
				) : (
					<>
						<span>오늘 사용 없음</span>
						<span>어제 {formatTokens(yesterday?.total ?? 0)}</span>
					</>
				)}
				<span>7d {formatTokens(summary.total7)}</span>
			</span>
		</div>
	);
}

function RecentDays({
	summaries,
}: {
	readonly summaries: readonly ProviderSummary[];
}) {
	const days = summaries[0]?.days ?? [];
	const rows = days
		.map((day, index) => ({ day, index }))
		.slice(-TABLE_DAYS)
		.reverse();
	const last = days.length - 1;
	return (
		<section aria-label={`Last ${TABLE_DAYS} days`} className="usage-panel">
			<div className="usage-panel-caption">
				<span>LAST {TABLE_DAYS} DAYS</span>
				<span className="usage-panel-meta">total tokens</span>
			</div>
			<table className="usage-table">
				<thead>
					<tr>
						<th scope="col">date</th>
						{summaries.map((summary) => (
							<th key={summary.provider} scope="col">
								{USAGE_PROVIDER_LABELS[summary.provider].toLowerCase()}
							</th>
						))}
						<th scope="col">total</th>
					</tr>
				</thead>
				<tbody>
					{rows.map(({ day, index }) => {
						const totals = summaries.map(
							(summary) => summary.days[index]?.total ?? 0,
						);
						return (
							<tr
								data-today={index === last ? "true" : undefined}
								key={day.start}
							>
								<th scope="row">{day.label}</th>
								{totals.map((total, column) => (
									<td key={summaries[column]?.provider}>
										{total > 0 ? formatTokens(total) : "—"}
									</td>
								))}
								<td>
									{formatTokens(totals.reduce((sum, total) => sum + total, 0))}
								</td>
							</tr>
						);
					})}
				</tbody>
			</table>
		</section>
	);
}

export function UsageView({ snapshot, error, nowSeconds }: UsageViewProps) {
	const now = useCurrentEpochSeconds(nowSeconds);
	if (snapshot === undefined) {
		return (
			<section aria-label="Usage View" className="usage-view view-panel">
				{error ? (
					<p className="error">{error}</p>
				) : (
					<p className="empty">사용량을 읽는 중…</p>
				)}
			</section>
		);
	}
	const summaries = USAGE_PROVIDERS.map((provider) =>
		summarizeProvider(provider, snapshot[provider], now),
	);
	const fileErrors = summaries.flatMap((summary) => summary.errors);
	return (
		<section aria-label="Usage View" className="usage-view view-panel">
			<div className="usage-columns">
				{summaries.map((summary) => (
					<section
						aria-label={`${USAGE_PROVIDER_LABELS[summary.provider]} usage details`}
						className="usage-column"
						data-provider={summary.provider}
						key={summary.provider}
					>
						<UsageHeading nowSeconds={now} summary={summary} />
						{summary.available ? (
							<>
								<UsageLimits
									nowSeconds={now}
									summary={summary}
									variant="detail"
								/>
								<TodayBreakdown summary={summary} />
							</>
						) : (
							<UsageUnavailable provider={summary.provider} />
						)}
					</section>
				))}
			</div>
			<UsageDailyComparison
				dayCount={USAGE_DAYS}
				showValues={false}
				summaries={summaries}
				title={`DAILY TOKENS · ${USAGE_DAYS}d`}
			/>
			<RecentDays summaries={summaries} />
			<p className="usage-footnote">
				Claude Code·Codex가 이 Mac에 남긴 로컬 파일만 읽습니다. 한도는 각
				agent가 마지막으로 받은 값이라 늦을 수 있습니다.
			</p>
			{error ? <p className="error">{error}</p> : null}
			{fileErrors.map((message) => (
				<p className="error" key={message}>
					{message}
				</p>
			))}
		</section>
	);
}
