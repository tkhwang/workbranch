import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { ProviderUsage, UsageSnapshot } from "../src/domain/usage";
import { UsageSummary } from "../src/ui/UsageSummary";
import { UsageView } from "../src/ui/UsageView";

function localEpoch(
	year: number,
	month: number,
	day: number,
	hour = 0,
	minute = 0,
): number {
	return Math.floor(
		new Date(year, month - 1, day, hour, minute, 0, 0).getTime() / 1000,
	);
}

function column(html: string, label: string): string {
	const start = html.indexOf(`aria-label="${label}"`);
	const end = html.indexOf("</section>", start);
	return html.slice(start, end);
}

describe("usage surfaces", () => {
	let previousTimeZone: string | undefined;
	let now = 0;
	let snapshot: UsageSnapshot;

	beforeAll(() => {
		previousTimeZone = process.env["TZ"];
		process.env["TZ"] = "Asia/Seoul";
		// 2026-10-07 (Wed) 07:18 Asia/Seoul
		now = localEpoch(2026, 10, 7, 7, 18);
		const claude: ProviderUsage = {
			available: true,
			limits: {
				observedAt: now - 21 * 3600,
				plan: "default_claude_max_20x",
				windows: [
					{ windowMinutes: 300, usedPercent: 0, resetsAt: null },
					{
						windowMinutes: 10080,
						usedPercent: 6,
						resetsAt: localEpoch(2026, 10, 11, 23),
					},
				],
			},
			buckets: [
				{
					start: localEpoch(2026, 10, 7, 6, 0),
					input: 182,
					output: 85_344,
					cacheRead: 16_111_510,
					cacheWrite: 762_980,
				},
				{
					start: localEpoch(2026, 10, 6, 12, 0),
					input: 1_934,
					output: 843_712,
					cacheRead: 333_926_423,
					cacheWrite: 3_638_755,
				},
			],
			errors: [],
		};
		const codex: ProviderUsage = {
			available: true,
			limits: {
				observedAt: now - 13 * 3600,
				plan: "pro",
				windows: [
					{
						windowMinutes: 10080,
						usedPercent: 32,
						resetsAt: localEpoch(2026, 10, 10, 12, 59),
					},
				],
			},
			buckets: [
				{
					start: localEpoch(2026, 10, 6, 17, 30),
					input: 89_493,
					output: 3_903,
					cacheRead: 493_568,
					cacheWrite: 0,
				},
			],
			errors: [],
		};
		snapshot = { generatedAt: now, since: now - 15 * 86_400, claude, codex };
	});

	afterAll(() => {
		if (previousTimeZone === undefined) {
			delete process.env["TZ"];
		} else {
			process.env["TZ"] = previousTimeZone;
		}
	});

	it("pairs each agent's limits on Main without per-agent charts", () => {
		const html = renderToStaticMarkup(
			<UsageSummary
				nowSeconds={now}
				onOpenDetails={() => undefined}
				snapshot={snapshot}
			/>,
		);
		const claude = column(html, "Claude usage");
		const codex = column(html, "Codex usage");

		expect(claude).toContain("max 20x");
		expect(claude).toMatch(
			/data-state="idle"[^>]*><span class="usage-limit-label">5h<\/span>.*?>0%<.*?>미시작</,
		);
		expect(claude).toMatch(
			/usage-limit-label">weekly<\/span>.*?>6%<.*?>4d 15h · Sun 23:00</,
		);
		expect(claude).toContain('data-stale="true"');
		expect(claude).toContain("21h 전 관측");
		expect(claude).toContain("today <b>17.0M</b>");
		// Codex has no 5h window on this plan, so it shows weekly only.
		expect(codex).not.toContain(">5h<");
		expect(codex).toMatch(
			/usage-limit-label">weekly<\/span>.*?>32%<.*?>3d 5h · Sat 12:59</,
		);
		expect(codex).toContain("today <b>0</b>");
		expect(html).toContain("Usage 탭에서 자세히 ›");
		expect(claude).not.toContain("usage-compare");
	});

	it("charts the last 7 days by day for both agents with each day's totals", () => {
		const html = renderToStaticMarkup(
			<UsageSummary
				nowSeconds={now}
				onOpenDetails={() => undefined}
				snapshot={snapshot}
			/>,
		);
		const week = html.slice(html.indexOf('aria-label="DAILY TOKENS · 7d"'));

		expect(week).toContain("--usage-days:7");
		expect(week.match(/class="usage-compare-day"/g)).toHaveLength(7);
		expect(week.match(/class="usage-compare-bar"/g)).toHaveLength(14);
		// The window starts on 10/1, so that day carries the month.
		expect(week).toContain('<span class="usage-axis-date">10/1</span>');
		expect(week).toContain('<span class="usage-axis-date">7</span>');
		expect(week).not.toContain(">9/30<");
		// 10/3 (Sat) and 10/4 (Sun) are the weekend slots in this week.
		expect(
			week.match(/class="usage-axis-day" data-weekend="true"/g),
		).toHaveLength(2);
		// Each day lists both agents' totals; empty days read as a dash.
		expect(week.match(/class="usage-values-day"/g)).toHaveLength(7);
		expect(week).toMatch(
			/data-provider="claude"><span class="usage-sr">claude <\/span>338M<\/span><span data-provider="codex"><span class="usage-sr">codex <\/span>587k</,
		);
		expect(week).toMatch(
			/class="usage-values-day" data-today="true">.*?claude <\/span>17.0M<.*?codex <\/span>—</,
		);
	});

	it("explains an agent that left no files instead of drawing empty bars", () => {
		const html = renderToStaticMarkup(
			<UsageSummary
				nowSeconds={now}
				onOpenDetails={() => undefined}
				snapshot={{
					...snapshot,
					codex: { available: false, limits: null, buckets: [], errors: [] },
				}}
			/>,
		);

		expect(column(html, "Codex usage")).toContain("Codex 기록이 없습니다");
		expect(column(html, "Codex usage")).not.toContain("usage-limit");
	});

	it("details today's token mix, a shared daily chart, and a 7-day table", () => {
		const html = renderToStaticMarkup(
			<UsageView error={undefined} nowSeconds={now} snapshot={snapshot} />,
		);

		expect(html).toContain('aria-label="Usage View"');
		expect(html).toContain("cache r 16.1M · w 763k");
		expect(column(html, "Codex usage details")).toContain("어제 587k");
		expect(html.match(/class="usage-compare-day"/g)?.length).toBe(14);
		expect(html.match(/<tbody>.*<\/tbody>/s)?.[0].match(/<tr/g)).toHaveLength(
			7,
		);
		expect(html).toContain('<tr data-today="true"><th scope="row">10/7 Wed');
		expect(html).toContain("로컬 파일만 읽습니다");
	});

	it("shows a loading line, then keeps errors visible", () => {
		expect(
			renderToStaticMarkup(
				<UsageView error={undefined} nowSeconds={now} snapshot={undefined} />,
			),
		).toContain("사용량을 읽는 중…");
		expect(
			renderToStaticMarkup(
				<UsageView
					error="disk read failed"
					nowSeconds={now}
					snapshot={snapshot}
				/>,
			),
		).toContain('<p class="error">disk read failed</p>');
	});

	it("lays the agents out side by side only from 720px", () => {
		const css = readFileSync("src/styles/usage.css", "utf8");

		expect(css).toMatch(
			/\.usage-summary,\s*\.usage-view\s*\{[^}]*container:\s*usage \/ inline-size/s,
		);
		expect(css).toMatch(
			/@container usage \(min-width: 720px\)\s*\{\s*\.usage-columns\s*\{[^}]*repeat\(2, minmax\(0, 1fr\)\)/s,
		);
	});
});
