import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type { DashboardModel } from "../src/application/dashboard";
import type { RingModel } from "../src/application/ring";
import { Dashboard } from "../src/ui/Dashboard";
import {
	arcPath,
	DashboardRing,
	formatAgo,
	formatElapsed,
	hubRadius,
	pillState,
	repoTone,
	summaryLine,
} from "../src/ui/DashboardRing";
import { SegmentClock, segmentsFor } from "../src/ui/SegmentClock";

// 2026-10-16 (Fri) 09:05:30 local time.
const NOW = new Date(2026, 9, 16, 9, 5, 30);
const NOW_SECONDS = Math.floor(NOW.getTime() / 1000);
const HOUR = 3600;

function ring(
	fields: Partial<RingModel> & Pick<RingModel, "key" | "title">,
): RingModel {
	return {
		repo: "workbranch",
		moreRepos: 0,
		agents: ["claude"],
		state: "running",
		since: NOW_SECONDS - 10 * 60,
		waitReason: "",
		arcs: [{ state: "running", from: 150, to: 266 }],
		turnEnds: [],
		turnStarts: [],
		calls: [],
		hubs: [],
		files: [],
		recentCalls: 0,
		activity: undefined,
		message: undefined,
		progress: undefined,
		summary: undefined,
		nowAngle: 266,
		logged: true,
		...fields,
	};
}

const MODEL: DashboardModel = {
	counts: { waiting: 1, running: 6, finished: 0 },
	active: 7,
	layout: {
		mode: "large",
		columns: 3,
		rings: [
			ring({
				key: "/work:fix-sync",
				title: "fix/sync",
				agents: ["codex"],
				state: "waiting",
				waitReason: "question",
				since: NOW_SECONDS - 6 * 60,
			}),
			ring({ key: "/work:ring", title: "feat/ring" }),
			ring({
				key: "/work:release",
				title: "release/0.9",
				repo: "backend",
				moreRepos: 1,
				state: "finished",
				since: NOW_SECONDS - 1500,
				turnEnds: [{ angle: 230, error: true }],
			}),
		],
		overflow: [
			ring({
				key: "/work:docs",
				title: "docs/spec",
				state: "finished",
				since: NOW_SECONDS - 2 * HOUR,
				summary: {
					filesChanged: 3,
					linesAdded: 96,
					linesRemoved: 21,
					tests: "none",
					commits: 1,
				},
			}),
		],
	},
};

const GRID_MODEL: DashboardModel = {
	counts: { waiting: 0, running: 4, finished: 0 },
	active: 4,
	layout: {
		mode: "grid",
		columns: 2,
		rings: ["a", "b", "c", "d"].map((name) =>
			ring({ key: `/work:${name}`, title: `feat/${name}` }),
		),
		overflow: [],
	},
};

const QUIET_MODEL: DashboardModel = {
	counts: { waiting: 0, running: 0, finished: 2 },
	active: 2,
	layout: { mode: "large", columns: 0, rings: [], overflow: [] },
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

	it("draws the tasks as large rings, the most urgent first", () => {
		const html = render();
		expect(html).toContain('class="rings" data-columns="3" data-mode="large"');
		expect(html.match(/data-size="large"/g)).toHaveLength(3);
		expect(html.indexOf("fix/sync")).toBeLessThan(html.indexOf("feat/ring"));
		expect(html.indexOf("feat/ring")).toBeLessThan(html.indexOf("release/0.9"));
	});

	it("draws a full grid as compact rings", () => {
		const html = render(true, GRID_MODEL);
		expect(html).toContain('data-columns="2" data-mode="grid"');
		expect(html.match(/data-size="compact"/g)).toHaveLength(4);
		expect(html).not.toContain("rings-more");
	});

	it("folds tasks without a ring into one line under the rings", () => {
		const html = render();
		expect(html).toContain('class="rings-more">+1 more<');
		expect(html).toContain('class="rings-more-name">docs/spec<');
		expect(html).toContain(
			">턴 종료 2h 00m · 3 files · +96 −21 · tests – · 1 commit<",
		);
	});

	it("says when nothing is in play", () => {
		const html = render(true, QUIET_MODEL);
		expect(html).toContain("진행 중인 작업 없음");
		expect(html).not.toContain('class="rings"');
	});

	it("is view-only: no buttons, links or inputs", () => {
		const html = render();
		expect(html).not.toMatch(/<(button|a|input|select|textarea)\b/);
	});

	it("never scrolls the page", () => {
		expect(css()).toMatch(/\.dashboard\s*\{[^}]*overflow:\s*hidden/);
	});
});

describe("ring formats", () => {
	it("gives each repo one of four tints, the same one every time", () => {
		const names = ["workbranch", "backend", "frontend", "homebrew-tap", "docs"];
		for (const name of names) {
			expect(repoTone(name)).toBe(repoTone(name));
			expect([1, 2, 3, 4]).toContain(repoTone(name));
		}
		expect(new Set(names.map(repoTone)).size).toBeGreaterThan(1);
	});

	it("writes minutes, then hours and minutes, for time in state", () => {
		expect(formatElapsed(30)).toBe("0m");
		expect(formatElapsed(12 * 60)).toBe("12m");
		expect(formatElapsed(HOUR + 120)).toBe("1h 02m");
	});

	it("says how long ago in minutes, hours or days", () => {
		const now = 100_000;
		expect(formatAgo(now - 20, now)).toBe("방금");
		expect(formatAgo(now - 12 * 60, now)).toBe("12분 전");
		expect(formatAgo(now - 3 * HOUR, now)).toBe("3시간 전");
		expect(formatAgo(now - 50 * HOUR, now)).toBe("2일 전");
		expect(formatAgo(now + 60, now)).toBe("방금");
	});
});

describe("DashboardRing", () => {
	const ringBase: RingModel = {
		key: "/work:ring",
		title: "feat/ring",
		repo: "workbranch",
		moreRepos: 1,
		agents: ["claude"],
		state: "running",
		since: NOW_SECONDS - 12 * 60,
		waitReason: "",
		arcs: [
			{ state: "running", from: 100, to: 200 },
			{ state: "waiting", from: 200, to: 230 },
			{ state: "running", from: 230, to: 266 },
		],
		turnEnds: [],
		turnStarts: [],
		calls: [],
		hubs: [],
		files: [],
		recentCalls: 0,
		activity: undefined,
		message: undefined,
		progress: undefined,
		summary: undefined,
		nowAngle: 266,
		logged: true,
	};
	const draw = (ring: RingModel, size: "large" | "compact" = "large") =>
		renderToStaticMarkup(
			<DashboardRing now={NOW_SECONDS} ring={ring} size={size} />,
		);

	it("draws each span of the history as an arc in its state", () => {
		const html = draw(ringBase);
		expect(html.match(/class="ring-arc"/g)).toHaveLength(3);
		expect(html).toContain('data-state="waiting"');
		expect(html).toContain(`d="${arcPath(200, 200, 230)}"`);
	});

	it("shows how long a running task has run, and breathes at now", () => {
		const html = draw(ringBase);
		expect(html).toContain('class="ring-middle" data-state="running"');
		expect(html).toContain(">12m<");
		expect(html).toContain('class="ring-pulse"');
		expect(html).not.toContain('class="ring-halo"');
	});

	it("asks for me when waiting: the reason and how long, with a halo", () => {
		const html = draw({
			...ringBase,
			state: "waiting",
			waitReason: "permission",
			since: NOW_SECONDS - 4 * 60,
		});
		expect(html).toContain(">응답 대기<");
		expect(html).toContain(">권한 요청 · 4m<");
		expect(html).toContain('class="ring-halo"');
		expect(html).not.toContain('class="ring-pulse"');
	});

	it("says when the turn ended, and crosses out one that failed", () => {
		const ended = {
			...ringBase,
			state: "finished" as const,
			since: NOW_SECONDS - 12 * 60,
		};
		const plain = draw({ ...ended, turnEnds: [{ angle: 250, error: false }] });
		expect(plain).toContain(">✓ 턴 종료<");
		expect(plain).toContain(">12분 전<");
		expect(plain).toContain('<circle class="ring-turn-end"');
		const failed = draw({ ...ended, turnEnds: [{ angle: 250, error: true }] });
		expect(failed).toContain(">✕ 오류로 끝남<");
		expect(failed).toContain('class="ring-turn-end" d=');
	});

	it("labels now and whole hours on a large ring only", () => {
		const large = draw(ringBase);
		expect(large).toContain(">지금<");
		expect(large).toContain(">1시간 전<");
		expect(large).toContain(">2시간 전<");
		expect(large).not.toContain(">3시간 전<");
		const compact = draw(ringBase, "compact");
		expect(compact).not.toContain("ring-tick-label");
		expect(compact).toContain('data-size="compact"');
	});

	it("keeps agent and state apart in one pill: names by shape, state by color", () => {
		const html = draw(ringBase);
		expect(html).toContain('class="ring-pill" data-state="running"');
		expect(html).toContain('class="ring-pill-agent"');
		expect(html).toContain('data-provider="claude"');
		expect(html).toContain(">Claude<");
		expect(html).toContain(
			'<span aria-hidden="true" class="ring-pill-dot"></span>실행 중<span class="ring-pill-time">12m</span>',
		);
		expect(html).toContain(
			`class="ring-repo-name" data-tone="${repoTone("workbranch")}">workbranch<`,
		);
		expect(html).toContain("> +1<");
		const team = draw({ ...ringBase, agents: ["claude", "codex"] });
		expect(team.match(/class="provider-icon"/g)).toHaveLength(2);
		expect(team).toContain(">Claude + Codex<");
	});

	it("gives every state its own pill, a failed turn included", () => {
		const waiting = draw({
			...ringBase,
			state: "waiting",
			since: NOW_SECONDS - 4 * 60,
		});
		expect(waiting).toContain('class="ring-pill" data-state="waiting"');
		expect(waiting).toContain('>내 응답 대기<span class="ring-pill-time">4m<');
		const failed = draw({
			...ringBase,
			state: "finished",
			turnEnds: [{ angle: 250, error: true }],
		});
		expect(failed).toContain('class="ring-pill" data-state="error"');
		expect(failed).toContain(">오류로 끝남<");
		expect(pillState({ ...ringBase, state: "finished" })).toBe("finished");
		expect(draw({ ...ringBase, agents: [] })).not.toContain("ring-pill-agent");
	});

	it("keeps lasting motion on opacity and transform only", () => {
		const css = readFileSync(
			new URL("../src/styles/dashboard-ring.css", import.meta.url),
			"utf8",
		);
		const keyframes = css.match(/@keyframes[^{]+\{([\s\S]*?\n)\}/g) ?? [];
		expect(keyframes.length).toBeGreaterThan(0);
		for (const block of keyframes) {
			const properties = [...block.matchAll(/^\s*([a-z-]+):/gm)].map(
				(m) => m[1],
			);
			for (const property of properties)
				expect(["opacity", "transform"]).toContain(property);
		}
	});

	const busy: RingModel = {
		...ringBase,
		turnStarts: [
			{ angle: 120, kind: "prompt" },
			{ angle: 240, kind: "agent" },
		],
		calls: [
			{
				angle: 150,
				group: "Read",
				failed: false,
				recent: false,
				files: ["old.rs"],
			},
			{
				angle: 250,
				group: "Edit",
				failed: false,
				recent: true,
				files: ["store.rs"],
			},
			{
				angle: 255,
				group: "Bash",
				failed: true,
				recent: true,
				fresh: true,
				at: 3,
				files: [],
			},
		],
		hubs: [
			{ group: "Bash", count: 1, angle: -90 },
			{ group: "Read", count: 1, angle: -57 },
			{ group: "Edit", count: 1, angle: -25 },
		],
		files: [{ name: "store.rs", angle: 250 }],
		recentCalls: 2,
	};

	it("draws each call as a dot at its time, a failed one crossed", () => {
		const html = draw(busy);
		expect(html.match(/<circle class="ring-call"/g)).toHaveLength(2);
		expect(html).toContain('class="ring-call" d=');
		expect(html).toContain('data-failed="true"');
	});

	it("links only recent calls to their tool and files, and names both", () => {
		const html = draw(busy);
		expect(html.match(/class="ring-link"/g)).toHaveLength(2);
		expect(html.match(/class="ring-file-link"/g)).toHaveLength(1);
		for (const name of ["Bash", "Read", "Edit"])
			expect(html).toContain(`>${name}</text>`);
		expect(html).toContain(">store.rs</text>");
		expect(html).not.toContain(">old.rs<");
		expect(html).toContain(`r="${hubRadius(1)}"`);
	});

	it("marks where turns began, a subagent's report hollow", () => {
		const html = draw(busy);
		expect(html).toContain('class="ring-turn-start"');
		expect(html).toContain('data-kind="agent"');
	});

	it("counts the last half hour's calls in the middle of a running ring", () => {
		expect(draw(busy)).toContain(">2 calls · 30m<");
	});

	it("keeps a compact ring to its history, turn starts and middle", () => {
		const html = draw(busy, "compact");
		expect(html).not.toContain("ring-call");
		expect(html).not.toContain("ring-link");
		expect(html).not.toContain("ring-hub");
		expect(html).not.toContain("ring-file");
		expect(html).toContain('class="ring-turn-start"');
	});

	it("shows work details under a large ring only when the model carries them", () => {
		const detailed: RingModel = {
			...busy,
			activity: "Edit: store.rs",
			message: { kind: "response", text: "Tests pass.", at: NOW_SECONDS - 120 },
		};
		const large = draw(detailed);
		expect(large).toContain(">▸ Edit: store.rs<");
		expect(large).toContain('data-kind="response">AI<');
		expect(large).toContain(">Tests pass.<");
		expect(large).toContain(">2분 전<");
		const compact = draw(detailed, "compact");
		expect(compact).not.toContain("ring-activity");
		expect(compact).not.toContain("ring-message");
		expect(draw(busy)).not.toContain("ring-activity");
	});

	it("sends only a new call travelling to its tool, once, without scheduling frames", () => {
		const html = draw(busy);
		expect(html.match(/class="ring-comet"/g)).toHaveLength(1);
		expect(html).toContain('<animateMotion dur="1.2s" fill="freeze"');
		const settled: RingModel = {
			...busy,
			calls: busy.calls.map((call) => ({ ...call, fresh: false })),
		};
		expect(draw(settled)).not.toContain("ring-comet");
		expect(draw(busy, "compact")).not.toContain("ring-comet");
		const source = readFileSync(
			new URL("../src/ui/DashboardRing.tsx", import.meta.url),
			"utf8",
		);
		expect(source).not.toMatch(/requestAnimationFrame|setInterval|setTimeout/);
	});

	it("draws the todo list as segments around the ring: done, next, and the rest", () => {
		const html = draw({
			...ringBase,
			progress: { total: 7, done: 3, active: undefined },
		});
		expect(html.match(/class="ring-progress-segment"/g)).toHaveLength(7);
		expect(html.match(/data-status="done"/g)).toHaveLength(3);
		expect(html.match(/data-status="active"/g)).toHaveLength(1);
		expect(html.match(/data-status="todo"/g)).toHaveLength(3);
		expect(draw(ringBase)).not.toContain("ring-progress-segment");
	});

	it("counts todos in the middle of a running ring, and names the next with details", () => {
		const progress = {
			total: 7,
			done: 3,
			active: "Ring layout in DashboardApp",
		};
		const large = draw({ ...ringBase, progress });
		expect(large).toContain('class="ring-middle-of">/7<');
		expect(large).toContain(">TODOS DONE<");
		expect(large).toContain(">▸ Ring layout in Dashboar…<");
		const compact = draw({ ...ringBase, progress }, "compact");
		expect(compact).toContain('class="ring-middle-of">/7<');
		expect(compact).not.toContain("TODOS DONE");
		expect(compact).not.toContain("ring-middle-active");
		const hidden = draw({
			...ringBase,
			progress: { ...progress, active: undefined },
		});
		expect(hidden).not.toContain("ring-middle-active");
	});

	it("keeps a waiting task's todo count under its reason, and lights nothing next", () => {
		const html = draw({
			...ringBase,
			state: "waiting",
			waitReason: "question",
			progress: { total: 5, done: 2, active: undefined },
		});
		expect(html).toContain(">todos 2/5<");
		expect(html).not.toContain('data-status="active"');
	});

	const summary = {
		filesChanged: 4,
		linesAdded: 530,
		linesRemoved: 133,
		tests: "passed" as const,
		commits: 1,
	};

	it("sums up an ended turn in the middle of a large ring", () => {
		const html = draw({
			...ringBase,
			state: "finished",
			since: NOW_SECONDS - 12 * 60,
			summary,
			progress: { total: 4, done: 4, active: undefined },
		});
		expect(html).toContain('class="ring-summary-ground"');
		expect(html).toContain(">✓ 턴 종료<");
		expect(html).toContain(">12분 전 · todos 4/4<");
		expect(html).toContain('class="ring-summary-added">+530<');
		expect(html).toContain('class="ring-summary-removed">−133<');
		expect(html).toContain(">files changed<");
		expect(html).toContain('data-tests="passed"');
		expect(html).toContain(">tests passed<");
		expect(html).toContain(">commit<");
	});

	it("keeps a compact or summary-less ended ring to its title and time", () => {
		const ended = { ...ringBase, state: "finished" as const };
		expect(draw({ ...ended, summary }, "compact")).not.toContain(
			"ring-summary",
		);
		expect(draw(ended)).not.toContain("ring-summary");
		expect(draw(ended)).toContain(">✓ 턴 종료<");
	});

	it("tells every test outcome apart", () => {
		for (const [tests, mark, label] of [
			["failed", "✗", "tests failed"],
			["unknown", "?", "tests ran"],
			["none", "–", "no tests run"],
		] as const) {
			const html = draw({
				...ringBase,
				state: "finished",
				summary: { ...summary, tests },
			});
			expect(html).toContain(`>${mark}<`);
			expect(html).toContain(`>${label}<`);
		}
	});

	it("writes an ended turn as one line for the overflow", () => {
		expect(summaryLine(summary)).toBe(
			"4 files · +530 −133 · tests ✓ · 1 commit",
		);
		expect(
			summaryLine({ ...summary, filesChanged: 1, commits: 0, tests: "none" }),
		).toBe("1 file · +530 −133 · tests – · 0 commits");
	});

	it("puts the pill, branch and repo above the ring and work details below", () => {
		const html = draw({ ...ringBase, activity: "Edit: ring.ts" });
		const face = html.indexOf('class="ring-face"');
		expect(html.indexOf('class="ring-pill"')).toBeLessThan(face);
		expect(html.indexOf('class="ring-name">feat/ring<')).toBeLessThan(face);
		expect(html.indexOf('class="ring-repo-name"')).toBeLessThan(face);
		expect(html.indexOf('class="ring-activity"')).toBeGreaterThan(face);
		const compact = draw({ ...ringBase, activity: "Edit: ring.ts" }, "compact");
		expect(compact).toContain('class="ring-pill"');
		expect(compact).not.toContain("ring-caption");
	});
});
