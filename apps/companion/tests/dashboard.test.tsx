import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type { DashboardModel } from "../src/application/dashboard";
import { Dashboard } from "../src/ui/Dashboard";
import {
	formatClock,
	formatElapsed,
	repoTone,
} from "../src/ui/DashboardTimeline";
import { SegmentClock, segmentsFor } from "../src/ui/SegmentClock";

// 2026-10-16 (Fri) 09:05:30 local time.
const NOW = new Date(2026, 9, 16, 9, 5, 30);
const NOW_SECONDS = Math.floor(NOW.getTime() / 1000);
const HOUR = 3600;

const MODEL: DashboardModel = {
	counts: { waiting: 1, running: 6, finished: 0 },
	active: 7,
	timeline: {
		start: NOW_SECONDS - 3 * HOUR,
		end: NOW_SECONDS,
		more: 2,
		logged: true,
		totals: { running: 3720, waiting: 960, finished: 0 },
		rows: [
			{
				key: "/work:fix-sync",
				title: "fix/sync",
				repo: "workbranch",
				moreRepos: 0,
				agent: "codex",
				state: "waiting",
				since: NOW_SECONDS - 6 * 60,
				segments: [
					{
						state: "running",
						start: NOW_SECONDS - HOUR,
						end: NOW_SECONDS - 1800,
					},
					{
						state: "waiting",
						start: NOW_SECONDS - 1800,
						end: NOW_SECONDS - 1200,
					},
					{
						state: "running",
						start: NOW_SECONDS - 1200,
						end: NOW_SECONDS - 360,
					},
					{ state: "waiting", start: NOW_SECONDS - 360, end: NOW_SECONDS },
				],
				turnEnds: [],
				totals: { running: 3720, waiting: 960, finished: 0 },
			},
			{
				key: "/work:release",
				title: "release/0.9",
				repo: "backend",
				moreRepos: 1,
				agent: "claude",
				state: "finished",
				since: NOW_SECONDS - 1500,
				segments: [
					{
						state: "running",
						start: NOW_SECONDS - 1.5 * HOUR,
						end: NOW_SECONDS - 1500,
					},
					{ state: "finished", start: NOW_SECONDS - 1500, end: NOW_SECONDS },
				],
				turnEnds: [{ at: NOW_SECONDS - 1500, error: true }],
				totals: undefined,
			},
		],
	},
};

const QUIET_MODEL: DashboardModel = {
	counts: { waiting: 0, running: 0, finished: 2 },
	active: 2,
	timeline: {
		start: NOW_SECONDS - 3 * HOUR,
		end: NOW_SECONDS,
		more: 0,
		logged: false,
		totals: undefined,
		rows: [],
	},
};

function render(lockAvailable = true, model = MODEL): string {
	return renderToStaticMarkup(
		<Dashboard
			lockAvailable={lockAvailable}
			model={model}
			now={NOW}
			theme="claude"
		/>,
	);
}

function css(): string {
	return readFileSync(
		new URL("../src/styles/dashboard.css", import.meta.url),
		"utf8",
	);
}

/** The markup of the row whose title is `title`. */
function rowOf(html: string, title: string): string {
	const at = html.indexOf(`>${title}<`);
	return html.slice(html.lastIndexOf("<li", at), html.indexOf("</li>", at));
}

describe("SegmentClock", () => {
	it("lights the classic segments for each digit", () => {
		expect(segmentsFor("8")).toEqual(["a", "b", "c", "d", "e", "f", "g"]);
		expect(segmentsFor("1")).toEqual(["b", "c"]);
		expect(segmentsFor("0")).toEqual(["a", "b", "c", "d", "e", "f"]);
	});

	it("reads as the time for assistive tech", () => {
		const html = renderToStaticMarkup(<SegmentClock now={NOW} />);
		expect(html).toContain('role="img"');
		expect(html).toContain('aria-label="09:05"');
		expect(html.match(/class="segment-digit"/g)).toHaveLength(4);
	});

	it("draws pointed seven-segment hexagons, lit per digit", () => {
		// 09:05 lights 6 + 6 + 6 + 5 segments of the 28 drawn.
		const html = renderToStaticMarkup(<SegmentClock now={NOW} />);
		expect(html.match(/<polygon /g)).toHaveLength(28);
		expect(html).not.toContain("<rect");
		expect(html.match(/<polygon [^>]*data-on="true"/g)).toHaveLength(23);
		for (const polygon of html.match(/points="[^"]+"/g) ?? []) {
			expect(polygon.split(" ")).toHaveLength(6);
		}
	});

	it("sizes the clock smaller and slants it like a classic display", () => {
		expect(css()).toMatch(
			/\.segment-clock\s*\{[^}]*height:\s*8vh;[^}]*transform:\s*skewX\(-6deg\)/s,
		);
	});
});

describe("Dashboard", () => {
	it("fills the screen with the clock, date and lock hint on top", () => {
		const html = render();
		expect(html).toMatch(/<main[^>]*class="dashboard"[^>]*data-theme="claude"/);
		expect(html).toContain('aria-label="09:05"');
		expect(html).toContain("10월 16일 금요일");
		expect(html).toContain("화면 잠김");
	});

	it("hides the lock hint where the Mac cannot lock", () => {
		const html = render(false);
		expect(html).not.toContain("화면 잠김");
		expect(html).not.toContain("dashboard-lock");
	});

	it("says a preview closes on input instead of promising a lock", () => {
		const html = renderToStaticMarkup(
			<Dashboard
				lockAvailable
				model={MODEL}
				now={NOW}
				preview
				theme="claude"
			/>,
		);
		expect(html).toContain("미리 보기 · 입력하면 닫힘");
		expect(html).not.toContain("화면 잠김");
	});

	it("shows a big count per live state", () => {
		const html = render();
		expect(html).toMatch(
			/data-state="waiting"[^>]*>[\s\S]*?class="dashboard-count-value">1</,
		);
		expect(html).toMatch(
			/data-state="running"[^>]*>[\s\S]*?class="dashboard-count-value">6</,
		);
	});

	it("leads with the active total, then running, waiting and finished", () => {
		const html = render();
		const counts = html.slice(
			html.indexOf('class="dashboard-counts"'),
			html.indexOf("</dl>"),
		);
		expect(counts.match(/data-state="(\w+)"/g)).toEqual([
			'data-state="active"',
			'data-state="running"',
			'data-state="waiting"',
			'data-state="finished"',
		]);
		expect(counts).toMatch(
			/data-state="active"[^>]*>[\s\S]*?활성 세션[\s\S]*?class="dashboard-count-value">7</,
		);
		expect(render(true, QUIET_MODEL)).toMatch(
			/data-state="active"[^>]*>[\s\S]*?class="dashboard-count-value">2</,
		);
	});

	it("draws a row per live task: agent, worktree branch, state with its time, repo", () => {
		const row = rowOf(render(), "fix/sync");
		expect(row).toContain('data-provider="codex"');
		expect(row).toContain('aria-label="Codex"');
		expect(row).toContain("내 응답 대기 6m");
		expect(row).toContain(
			`class="timeline-repo-name" data-tone="${repoTone("workbranch")}">workbranch<`,
		);
		expect(row).not.toContain("timeline-repo-more");
		const release = rowOf(render(), "release/0.9");
		expect(release).toContain(`data-tone="${repoTone("backend")}">backend<`);
		expect(release).toMatch(/class="timeline-repo-more">\s*\+1</);
	});

	it("places each span by time within the last three hours", () => {
		const row = rowOf(render(), "fix/sync");
		expect(row).toMatch(
			/data-state="running" style="left:66\.667%;width:16\.667%"/,
		);
	});

	it("labels a long waiting block with its duration, not a short one", () => {
		const row = rowOf(render(), "fix/sync");
		expect(row).toMatch(/data-state="waiting"[^>]*>10m</);
		expect(row).toMatch(
			/data-state="waiting" style="left:96\.667%[^"]*"><\/span>/,
		);
	});

	it("marks turn ends, crossing out a failed one", () => {
		const row = rowOf(render(), "release/0.9");
		expect(row).toMatch(
			/class="timeline-end" data-error="true"[^>]*><svg[^>]*class="timeline-error-mark"/,
		);
	});

	it("fills the time columns in the header's flow order, as h:mm", () => {
		const cells = rowOf(render(), "fix/sync").match(
			/class="timeline-cell"[^>]*data-state="(\w+)"[^>]*>([^<]*)</g,
		);
		expect(
			cells?.map((cell) =>
				cell.replace(/.*data-state="(\w+)".*>([^<]*)<$/, "$1 $2"),
			),
		).toEqual(["running 1:02", "waiting 0:16", "finished –"]);
		expect(rowOf(render(), "release/0.9").match(/>–</g)).toHaveLength(3);
	});

	it("heads the time columns with the session totals and shows the legend", () => {
		const html = render();
		expect(html).toContain("세션 전체");
		expect(html).toMatch(/data-state="running"><dt>실행<\/dt><dd>1:02<\/dd>/);
		expect(html).toMatch(/data-state="waiting"><dt>대기<\/dt><dd>0:16<\/dd>/);
		for (const key of [
			"실행 중",
			"내 응답 대기",
			"턴 종료",
			"검토 대기",
			"오류로 끝남",
		])
			expect(html.slice(html.indexOf("timeline-legend"))).toContain(key);
	});

	it("says history starts with an updated CLI, and when nothing is live", () => {
		expect(render()).not.toContain("timeline-note");
		const quiet = render(true, QUIET_MODEL);
		expect(quiet).toContain("workbranch CLI");
		expect(quiet).toContain("진행 중인 작업 없음");
	});

	it("folds rows that do not fit into +n more", () => {
		expect(render()).toContain("+2 more");
		expect(render(true, QUIET_MODEL)).not.toMatch(/\+\d+ more/);
	});

	it("marks half hours on the axis, leaving room for now", () => {
		const axis = render().slice(render().indexOf("timeline-axis-track"));
		for (const label of ["06:30", "07:00", "08:30", "지금"])
			expect(axis).toContain(label);
		expect(axis).not.toContain(">09:00<");
	});

	it("draws running as a line and waiting as a taller block", () => {
		const styles = css();
		expect(styles).toMatch(
			/\.timeline-segment\[data-state="running"\]\s*\{[^}]*height:\s*1vh/,
		);
		expect(styles).toMatch(
			/\.timeline-segment\[data-state="waiting"\]\s*\{[^}]*height:\s*3vh/,
		);
	});

	it("is view-only: no buttons, links or inputs", () => {
		const html = render();
		expect(html).not.toMatch(/<(button|a|input|select|textarea)\b/);
	});

	it("never scrolls the page", () => {
		expect(css()).toMatch(/\.dashboard\s*\{[^}]*overflow:\s*hidden/);
	});
});

describe("timeline formats", () => {
	it("gives each repo one of four tints, the same one every time", () => {
		const names = ["workbranch", "backend", "frontend", "homebrew-tap", "docs"];
		for (const name of names) {
			expect(repoTone(name)).toBe(repoTone(name));
			expect([1, 2, 3, 4]).toContain(repoTone(name));
		}
		expect(new Set(names.map(repoTone)).size).toBeGreaterThan(1);
	});

	it("writes h:mm for the time columns, a dash for none", () => {
		expect(formatClock(undefined)).toBe("–");
		expect(formatClock(59)).toBe("–");
		expect(formatClock(60)).toBe("0:01");
		expect(formatClock(3 * HOUR + 125)).toBe("3:02");
	});

	it("writes minutes, then hours and minutes, for time in state", () => {
		expect(formatElapsed(30)).toBe("0m");
		expect(formatElapsed(12 * 60)).toBe("12m");
		expect(formatElapsed(HOUR + 120)).toBe("1h 02m");
	});
});
