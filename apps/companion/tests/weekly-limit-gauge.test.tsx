import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { LimitAccount } from "../src/application/limits";
import { WeeklyLimitGauge } from "../src/ui/WeeklyLimitGauge";

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

function tagsWithClass(
	html: string,
	tag: string,
	className: string,
): readonly string[] {
	const pattern = new RegExp(`<${tag}\\b[^>]*class="${className}"[^>]*>`, "g");
	return html.match(pattern) ?? [];
}

function attribute(tag: string, name: string): string | undefined {
	return new RegExp(`\\s${name}="([^"]*)"`).exec(tag)?.[1];
}

const LONG_LABEL = "x".repeat(40);

describe("WeeklyLimitGauge", () => {
	let previousTimeZone: string | undefined;
	// 2026-09-22 (Tue) 14:37 Asia/Seoul
	let now = 0;
	let accounts: readonly LimitAccount[] = [];

	beforeAll(() => {
		previousTimeZone = process.env["TZ"];
		process.env["TZ"] = "Asia/Seoul";
		now = localEpoch(2026, 9, 22, 14, 37);
		accounts = [
			{
				id: "a1",
				label: "Max · main",
				nextResetAt: localEpoch(2026, 9, 24, 15),
			},
			{ id: "a2", label: "", nextResetAt: localEpoch(2026, 9, 23, 9) },
			{ id: "a3", label: LONG_LABEL, nextResetAt: localEpoch(2026, 9, 22, 10) },
		];
	});

	afterAll(() => {
		if (previousTimeZone === undefined) {
			delete process.env["TZ"];
		} else {
			process.env["TZ"] = previousTimeZone;
		}
	});

	function render(list: readonly LimitAccount[] = accounts): string {
		return renderToStaticMarkup(
			<WeeklyLimitGauge accounts={list} nowSeconds={now} />,
		);
	}

	it("renders nothing without accounts", () => {
		expect(render([])).toBe("");
	});

	it("renders one row per account in registration order under a caption", () => {
		const html = render();

		expect(html).toContain('aria-label="Weekly limits"');
		expect(html).toContain("WEEKLY LIMITS");
		expect(html).toContain('<span class="limit-count">3</span>');
		expect(tagsWithClass(html, "li", "limit-row")).toHaveLength(3);
		expect(html.indexOf("Max · main")).toBeLessThan(html.indexOf("Account 2"));
		expect(html.indexOf("Account 2")).toBeLessThan(html.indexOf(LONG_LABEL));
	});

	it("draws a hidden two-week axis with local calendar day labels", () => {
		const html = render();
		const axisRow = tagsWithClass(html, "div", "limit-axis-row")[0];
		const dayTags =
			html.match(/<span class="limit-axis-day"[^>]*>[^<]*<\/span>/g) ?? [];
		const labels = dayTags.map(
			(tag) => /^<[^>]*>([^<]*)<\/span>$/.exec(tag)?.[1] ?? "?",
		);
		const todayTags = dayTags.filter((tag) =>
			tag.includes('data-today="true"'),
		);

		expect(axisRow).toContain('aria-hidden="true"');
		expect(dayTags).toHaveLength(15);
		expect(labels).toEqual([
			"",
			...Array.from({ length: 14 }, (_, index) => String(16 + index)),
		]);
		expect(html).toContain('<span class="limit-axis-range">9/15 – 9/29</span>');
		expect(todayTags).toHaveLength(1);
		expect(todayTags[0]).toContain(">22</span>");
		// Tiers count from today (index 7): 3, 7, 11 are tier 0; 1, 5, 9, 13 tier 1.
		expect(dayTags.filter((tag) => tag.includes('data-tier="2"'))).toHaveLength(
			8,
		);
		expect(dayTags.filter((tag) => tag.includes('data-tier="1"'))).toHaveLength(
			4,
		);
		expect(dayTags.filter((tag) => tag.includes('data-tier="0"'))).toHaveLength(
			3,
		);
		expect(todayTags[0]).toContain('data-tier="0"');
		expect(dayTags[3]).toContain('data-tier="0"');
		expect(dayTags[11]).toContain('data-tier="0"');
		expect(dayTags[1]).toContain('data-tier="1"');
		expect(dayTags[2]).toContain('data-tier="2"');
		// Edge cells anchor their labels inward instead of centring.
		expect(dayTags[1]).toContain('data-edge="start"');
		expect(dayTags[14]).toContain('data-edge="end"');
		expect(dayTags[7]).not.toContain("data-edge");
		expect(html).toMatch(
			/<span class="limit-axis-now" style="left:50\.000%"><\/span>/,
		);
	});

	it("places the window bar, reset marks, and now line on the axis", () => {
		const html = render([accounts[0] as LimitAccount]);
		const fill = tagsWithClass(html, "rect", "limit-fill")[0] ?? "";
		const rest = tagsWithClass(html, "rect", "limit-rest")[0] ?? "";
		const resetMarks = tagsWithClass(html, "line", "limit-reset-mark");
		const nowLine = tagsWithClass(html, "line", "limit-now")[0] ?? "";

		expect(attribute(fill, "x")).toBe("14.400%");
		expect(attribute(fill, "width")).toBe("35.600%");
		expect(attribute(rest, "x")).toBe("50.000%");
		expect(attribute(rest, "width")).toBe("14.400%");
		expect(resetMarks.map((mark) => attribute(mark, "x1"))).toEqual([
			"14.400%",
			"64.400%",
		]);
		expect(attribute(nowLine, "x1")).toBe("50.000%");
		expect(tagsWithClass(html, "line", "limit-grid")).toHaveLength(14);
	});

	it("normalizes a stale anchor onto the same bar", () => {
		const stale = render([
			{
				id: "a1",
				label: "Max · main",
				nextResetAt: localEpoch(2026, 9, 17, 15),
			},
		]);
		const fresh = render([accounts[0] as LimitAccount]);

		expect(stale).toBe(fresh);
	});

	it("marks phases with data attributes and tokens", () => {
		const html = render();
		const rows = tagsWithClass(html, "li", "limit-row");

		expect(rows.map((row) => attribute(row, "data-phase"))).toEqual([
			"mid",
			"soon",
			"fresh",
		]);
		expect(html.match(/<span class="limit-token">SOON<\/span>/g)).toHaveLength(
			1,
		);
		expect(html.match(/<span class="limit-token">FRESH<\/span>/g)).toHaveLength(
			1,
		);
		expect(html.match(/class="limit-token"/g)).toHaveLength(2);
	});

	it("shows remaining time with the reset weekday and time, and exposes full text", () => {
		const html = render();
		const firstRow = tagsWithClass(html, "li", "limit-row")[0] ?? "";

		expect(html).toContain(
			'<span class="limit-remaining">2d 0h</span><span aria-hidden="true" class="limit-sep">·</span><span class="limit-reset">Thu 15:00</span>',
		);
		expect(attribute(firstRow, "aria-label")).toBe(
			"Max · main: 2d 0h until reset, Thu 15:00, 71% elapsed",
		);
		expect(attribute(firstRow, "title")).toBe("Resets 2026-09-24 15:00");
		expect(html).toContain('<span class="limit-remaining">18h 23m</span>');
		expect(html).toContain('<span class="limit-remaining">6d 19h</span>');
	});

	it("falls back to numbered labels and keeps long labels in the title", () => {
		const html = render();
		const labels = tagsWithClass(html, "span", "limit-label");

		expect(labels[1]).toContain('title="Account 2"');
		expect(html).toContain(">Account 2</span>");
		expect(labels[2]).toContain(`title="${LONG_LABEL}"`);
	});

	it("keeps the scale free of text and hidden from assistive tech", () => {
		const html = render();
		const scales = tagsWithClass(html, "svg", "limit-scale");

		expect(scales).toHaveLength(3);
		for (const scale of scales) {
			expect(scale).toContain('aria-hidden="true"');
			expect(attribute(scale, "width")).toBe("100%");
			expect(attribute(scale, "height")).toBe("24");
		}
		expect(html).not.toContain("<text");
		expect(html).not.toContain("<button");
	});

	it("owns its layout in limit-gauge.css with subgrid columns and theme tokens only", () => {
		const css = readFileSync("src/styles/limit-gauge.css", "utf8");
		const tokens = `${readFileSync("src/styles/themes.css", "utf8")}\n${readFileSync("src/styles/base.css", "utf8")}`;

		expect(css).toMatch(
			/\.limit-table\s*\{[^}]*grid-template-columns:\s*minmax\(64px, 96px\) minmax\(0, 1fr\) auto/s,
		);
		expect(css).toMatch(
			/\.limit-axis-row,\s*\.limit-list,\s*\.limit-row\s*\{[^}]*grid-template-columns:\s*subgrid/s,
		);
		for (const selector of [
			".limit-board",
			".limit-caption",
			".limit-axis-range",
			".limit-axis",
			'.limit-axis-day[data-today="true"]',
			'.limit-axis-day[data-edge="start"]',
			'.limit-axis-day[data-edge="end"]',
			".limit-axis-now",
			".limit-label",
			".limit-scale",
			".limit-grid",
			".limit-rest",
			".limit-fill",
			'.limit-row[data-phase="fresh"] .limit-fill',
			'.limit-row[data-phase="soon"] .limit-reset-mark',
			".limit-now",
			".limit-facts",
			".limit-remaining",
			".limit-reset",
			".limit-token",
		]) {
			expect(css).toContain(selector);
		}
		expect(css).toMatch(
			/\.limit-axis\s*\{[^}]*container-type:\s*inline-size[^}]*font-size:\s*var\(--fs-label\)/s,
		);
		expect(css).toMatch(
			/@media \(max-width: 480px\)\s*\{[\s\S]*?\.limit-table\s*\{[^}]*grid-template-columns:\s*minmax\(48px, 64px\) minmax\(0, 1fr\) auto/s,
		);
		expect(css).toMatch(
			/@container \(max-width: 25\.5em\)\s*\{\s*\.limit-axis-day\[data-tier="2"\]:not\(\[data-today="true"\]\)\s*\{[^}]*display:\s*none/s,
		);
		expect(css).toMatch(
			/@container \(max-width: 12\.7em\)\s*\{\s*\.limit-axis-day\[data-tier="1"\]:not\(\[data-today="true"\]\)\s*\{[^}]*display:\s*none/s,
		);
		expect(css).not.toMatch(/main\[data-font-size=/);
		expect(css).not.toContain("color-mix(");
		for (const match of css.matchAll(/var\(--([a-z0-9-]+)/g)) {
			expect(tokens).toContain(`--${match[1]}:`);
		}
		expect(readFileSync("src/style.css", "utf8")).toContain(
			'@import "./styles/limit-gauge.css";',
		);
	});
});
