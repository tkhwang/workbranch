import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type {
	DashboardCard,
	DashboardModel,
} from "../src/application/dashboard";
import { Dashboard } from "../src/ui/Dashboard";
import { SegmentClock, segmentsFor } from "../src/ui/SegmentClock";

// 2026-10-16 (Fri) 09:05:30 local time.
const NOW = new Date(2026, 9, 16, 9, 5, 30);
const NOW_SECONDS = Math.floor(NOW.getTime() / 1000);

const CLEAN = { dirty: false, files: 0, ahead: 0, behind: 0 };

function card(
	fields: Partial<DashboardCard> & { readonly task: string },
): DashboardCard {
	return {
		key: `/work:${fields.task}`,
		repo: "workbranch",
		branch: `feat/${fields.task}`,
		agent: "claude",
		since: NOW_SECONDS - 60,
		reason: undefined,
		prompt: undefined,
		detail: undefined,
		outcome: undefined,
		changes: CLEAN,
		notifications: 0,
		...fields,
	};
}

const MODEL: DashboardModel = {
	counts: { waiting: 1, running: 6, finished: 0 },
	columns: [
		{
			key: "waiting",
			count: 1,
			more: 0,
			cards: [
				card({
					task: "fix-sync",
					branch: "fix/sync",
					agent: "codex",
					since: NOW_SECONDS - 6 * 60,
					reason: "permission",
					prompt: "retry sync with backoff",
					detail: { kind: "activity", text: "Bash: git push origin fix/sync" },
					changes: { dirty: true, files: 2, ahead: 3, behind: 0 },
					notifications: 1,
				}),
			],
		},
		{
			key: "running",
			count: 6,
			more: 2,
			cards: ["a", "b", "c", "d"].map((name) =>
				card({
					task: `task-${name}`,
					since: NOW_SECONDS - 12 * 60,
					prompt: `work on ${name}`,
					detail: { kind: "activity", text: `Edit: src/${name}.ts` },
				}),
			),
		},
		{ key: "finished", count: 0, more: 0, cards: [] },
	],
};

const FINISHED_MODEL: DashboardModel = {
	counts: { waiting: 0, running: 0, finished: 2 },
	columns: [
		{ key: "waiting", count: 0, more: 0, cards: [] },
		{ key: "running", count: 0, more: 0, cards: [] },
		{
			key: "finished",
			count: 2,
			more: 0,
			cards: [
				card({
					task: "release-notes",
					detail: { kind: "response", text: "Release notes are ready." },
				}),
				card({
					task: "hook-timeout",
					detail: { kind: "response", text: "stop_after_timeout failed." },
					outcome: "error",
				}),
			],
		},
	],
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
});

describe("Dashboard", () => {
	it("fills the screen with the clock, date and lock hint on top", () => {
		const html = render();
		expect(html).toMatch(/<main[^>]*class="dashboard"[^>]*data-theme="claude"/);
		expect(html).toContain('aria-label="09:05"');
		expect(html).toContain("10월 16일 금요일");
		expect(html).toContain("입력 시 잠금");
	});

	it("hides the lock hint where input cannot lock the Mac", () => {
		const html = render(false);
		expect(html).not.toContain("입력 시 잠금");
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
		expect(html).not.toContain("입력 시 잠금");
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

	it("lays out the three board columns with the board's names", () => {
		const html = render();
		for (const label of ["내 응답 대기", "실행 중", "턴 종료 · 검토"]) {
			expect(html).toContain(label);
		}
		expect(html.match(/class="dashboard-column"/g)).toHaveLength(3);
	});

	it("describes each card by task, agent, repo, branch and time in state", () => {
		const html = render();
		expect(html).toContain("fix-sync");
		expect(html).toContain("codex");
		expect(html).toContain("workbranch · fix/sync");
		expect(html).toContain("6m");
		expect(html).toContain("권한 승인 대기");
		expect(html).toContain("12m");
	});

	it("puts the turn's prompt on each card", () => {
		const html = render();
		expect(html).toMatch(
			/class="dashboard-card-prompt">retry sync with backoff</,
		);
		expect(html).toContain("work on a");
	});

	it("shows what a waiting card waits on next to the wait reason", () => {
		const html = render();
		expect(html).toMatch(
			/class="dashboard-card-detail" data-state="waiting"[^>]*><p class="dashboard-card-detail-text"><span class="dashboard-card-label">권한 승인 대기<\/span>Bash: git push origin fix\/sync</,
		);
	});

	it("shows the tool a running card is using", () => {
		const html = render();
		expect(html).toMatch(
			/class="dashboard-card-detail" data-state="running"[^>]*><p class="dashboard-card-detail-text">Edit: src\/a\.ts</,
		);
	});

	it("shows a finished turn's last answer, and how it ended when not normally", () => {
		const html = render(true, FINISHED_MODEL);
		expect(html).toMatch(
			/<span class="dashboard-card-label">마지막 응답<\/span>Release notes are ready\./,
		);
		expect(html).toMatch(
			/data-outcome="error"[^>]*><p class="dashboard-card-detail-text"><span class="dashboard-card-label">오류로 종료<\/span>stop_after_timeout failed\./,
		);
	});

	it("shows repo changes and notifications, and nothing for a clean repo", () => {
		const html = render();
		expect(html).toContain(">●2<");
		expect(html).toContain(">↑3<");
		expect(html).toContain("알림 1");
		expect(html).not.toContain("CLEAN");
		// The running cards are clean: no change facts at all.
		expect(html.match(/class="dashboard-card-changes"/g)).toHaveLength(1);
	});

	it("caps a card's height: one prompt line and clamped detail lines", () => {
		const style = css();
		expect(style).toMatch(
			/\.dashboard-card-prompt\s*\{[^}]*white-space:\s*nowrap/,
		);
		expect(style).toMatch(
			/\.dashboard-card-detail-text\s*\{[^}]*-webkit-line-clamp:\s*2/,
		);
		expect(style).toMatch(
			/\.dashboard-card-detail\[data-state="running"\] \.dashboard-card-detail-text\s*\{[^}]*-webkit-line-clamp:\s*1/,
		);
	});

	it("folds what does not fit into +n more and marks empty columns", () => {
		const html = render();
		expect(html).toContain("+2 more");
		expect(html).toContain("없음");
		expect(html).not.toContain("overflow-y: auto");
	});

	it("is view-only: no buttons, links or inputs", () => {
		const html = render();
		expect(html).not.toMatch(/<(button|a|input|select|textarea)\b/);
	});

	it("never scrolls the page", () => {
		expect(css()).toMatch(/\.dashboard\s*\{[^}]*overflow:\s*hidden/);
	});
});
