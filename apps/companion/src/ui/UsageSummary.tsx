import {
	formatTokens,
	summarizeProvider,
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

export const SUMMARY_DAYS = 7;

export type UsageSummaryProps = {
	readonly snapshot: UsageSnapshot;
	readonly nowSeconds?: number;
	readonly onOpenDetails: () => void;
};

/** Main-view digest: each agent's limits side by side, then the last week by day. */
export function UsageSummary({
	snapshot,
	nowSeconds,
	onOpenDetails,
}: UsageSummaryProps) {
	const now = useCurrentEpochSeconds(nowSeconds);
	const summaries = USAGE_PROVIDERS.map((provider) =>
		summarizeProvider(provider, snapshot[provider], now),
	);
	return (
		<section aria-label="Usage summary" className="usage-summary">
			<div className="usage-columns">
				{summaries.map((summary) => (
					<section
						aria-label={`${USAGE_PROVIDER_LABELS[summary.provider]} usage`}
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
									variant="compact"
								/>
								<div className="usage-column-foot">
									<span>
										today <b>{formatTokens(summary.today?.total ?? 0)}</b>
									</span>
									<span>7d {formatTokens(summary.total7)}</span>
								</div>
							</>
						) : (
							<UsageUnavailable provider={summary.provider} />
						)}
					</section>
				))}
			</div>
			<UsageDailyComparison
				dayCount={SUMMARY_DAYS}
				showValues
				summaries={summaries}
				title={`DAILY TOKENS · ${SUMMARY_DAYS}d`}
			/>
			<button className="usage-more" onClick={onOpenDetails} type="button">
				Usage 탭에서 자세히 ›
			</button>
		</section>
	);
}
