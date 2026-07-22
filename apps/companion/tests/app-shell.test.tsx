import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { App, nextActivityReloadToken } from "../src/App";
import { StatusAlert } from "../src/ui/StatusAlert";

function readCssContract(path: string, visited = new Set<string>()): string {
	const absolutePath = resolve(path);
	if (visited.has(absolutePath)) {
		return "";
	}
	visited.add(absolutePath);
	const css = readFileSync(absolutePath, "utf8");
	const importedCss = Array.from(css.matchAll(/@import "(.+)";/g))
		.map((match) => {
			const importPath = match[1];
			if (importPath === undefined) {
				return "";
			}
			return readCssContract(
				resolve(dirname(absolutePath), importPath),
				visited,
			);
		})
		.join("\n");
	return `${css}\n${importedCss}`;
}

describe("App shell settings wiring", () => {
	it("advances the activity reload token after successful app refreshes", () => {
		expect(nextActivityReloadToken(0)).toBe(1);
		expect(nextActivityReloadToken(41)).toBe(42);
	});

	it("skips already-read CSS imports to avoid import cycles", () => {
		// Given two CSS files import each other
		const directory = mkdtempSync(join(tmpdir(), "workbranch-css-cycle-"));
		const rootCss = join(directory, "root.css");
		const childCss = join(directory, "child.css");
		writeFileSync(rootCss, '@import "./child.css";\n.root { color: red; }\n');
		writeFileSync(childCss, '@import "./root.css";\n.child { color: blue; }\n');

		try {
			// When the CSS contract reader follows imports
			const css = readCssContract(rootCss);

			// Then each file is read once and the recursive cycle is skipped
			expect(css.match(/\.root/g)).toHaveLength(1);
			expect(css.match(/\.child/g)).toHaveLength(1);
		} finally {
			rmSync(directory, { recursive: true, force: true });
		}
	});

	it("renders the shared text-only agent header and terminal tabs on Main", () => {
		// Given the companion app shell at its initial render
		// When static markup is rendered
		const html = renderToStaticMarkup(<App />);

		// Then the settings-capable shell contract is present before effects run
		expect(html).toContain('data-theme="claude"');
		expect(html).toContain('data-font="system-mono"');
		expect(html).toContain('data-agent-header="claude"');
		expect(html).toContain("<h1>Workbranch Companion</h1>");
		expect(html).not.toContain("<fieldset");
		expect(html).not.toContain("<svg");
		expect(html).toContain('aria-label="Refresh tasks"');
		expect(html).toContain('aria-label="Quit Companion"');
		expect(html).toContain('class="toolbar-status-sr"');
		expect(html).toContain(">Ready</span>");
		expect(html).not.toContain("<footer");
		expect(html).toContain('aria-label="Companion views"');
		expect(html).toContain(">Main</button>");
		expect(html).toContain(">Activity</button>");
		expect(html).toContain(">Settings</button>");
		expect(html).toContain('role="status"');
		expect(html).toContain('aria-live="polite"');
		expect(html).not.toContain('class="app-error"');
		expect(html).not.toContain('role="alert"');
	});

	it("uses the expanded agent header across every view without legacy theme or navigation code", () => {
		const source = readFileSync("src/App.tsx", "utf8");
		const tabsIndex = source.indexOf("<AgentTabs");
		const alertIndex = source.indexOf("<StatusAlert");
		const errorsIndex = source.indexOf("{model.errors.map");

		expect(source).toContain("const activeTheme = preferences.theme");
		expect(source).toContain("<AgentHeader");
		expect(source).not.toContain("AgentBar");
		expect(source).toContain("theme={activeTheme}");
		expect(tabsIndex).toBeGreaterThan(0);
		expect(alertIndex).toBeLessThan(tabsIndex);
		expect(tabsIndex).toBeGreaterThan(errorsIndex);
		expect(source).not.toContain("useSystemThemeMode");
		expect(source).not.toContain("resolvedCompanionTheme");
		expect(source).not.toContain("ViewNav");
		expect(source).not.toContain("HintBar");
		expect(source).not.toContain("onKeyDown");
		expect(source).not.toContain("⌘1");
	});

	it("renders operation failures as a visible alert instead of only screen-reader status", () => {
		// Given a failed companion operation status
		// When the visible status alert is rendered
		const html = renderToStaticMarkup(
			<StatusAlert message="refresh failed: command stderr" />,
		);

		// Then sighted users get an alert row with the failure text
		expect(html).toContain('class="app-error"');
		expect(html).toContain('role="alert"');
		expect(html).toContain("refresh failed: command stderr");
	});

	it("omits the visible status alert for routine status updates", () => {
		// Given no visible error is active
		// When the status alert is rendered
		const html = renderToStaticMarkup(<StatusAlert message={undefined} />);

		// Then routine Ready/Updated text can stay in the screen-reader-only toolbar
		expect(html).toBe("");
	});

	it("styles visible operation errors without restoring the routine toolbar chip", () => {
		// Given the companion toolbar stylesheet
		// When status CSS is inspected
		const css = readCssContract("src/style.css");

		// Then only operation failures have a visible status surface
		expect(css).toMatch(
			/\.app-error\s*\{[^}]*background:\s*var\(--blocked-soft\)/s,
		);
		expect(css).toMatch(
			/\.app-error\s*\{[^}]*border:\s*1px solid var\(--blocked\)/s,
		);
		expect(css).toMatch(/\.app-error\s*\{[^}]*color:\s*var\(--blocked\)/s);
		expect(css).not.toMatch(/\.toolbar-status\s*\{/s);
	});

	it("keeps agent status available to assistive tech without a visible chip", () => {
		// Given the companion toolbar stylesheet
		// When the status chip CSS contract is inspected
		const css = readCssContract("src/style.css");

		// Then status updates remain announced while the visible top line stays focused on controls
		expect(css).toMatch(/\.agent-controls\s*\{[^}]*display:\s*flex/s);
		expect(css).toMatch(
			/\.agent-controls\s*\{[^}]*justify-content:\s*flex-end/s,
		);
		expect(css).toMatch(/\.toolbar-status-sr\s*\{[^}]*position:\s*absolute/s);
		expect(css).toMatch(
			/\.toolbar-status-sr\s*\{[^}]*clip-path:\s*inset\(50%\)/s,
		);
		expect(css).toMatch(/\.toolbar-status-sr\s*\{[^}]*white-space:\s*nowrap/s);
		expect(css).not.toMatch(/\.toolbar-status\s*\{/s);
	});

	it("uses the configured fixed-width font as the app shell font family", () => {
		// Given the companion stylesheet and font preference data attributes
		// When the CSS contract is inspected
		const css = readCssContract("src/style.css");

		// Then the app shell font follows the selected monospace setting
		expect(css).toMatch(
			/main\s*\{[^}]*font-family:\s*var\(--app-font-family\)/s,
		);
		expect(css).toContain('main[data-font="menlo"]');
		expect(css).toContain('--app-font-family: "Menlo"');
	});

	it("keeps fixed dark button backgrounds in each theme contract", () => {
		// Given the companion stylesheet is built for chrome105 and safari13 WebViews
		// When the button background token contract is inspected
		const css = readCssContract("src/style.css");
		expect(css).toMatch(
			/main\[data-theme="claude"\]\s*\{[^}]*--button-bg:\s*rgba\(192,\s*202,\s*245,\s*0\.06\);[^}]*--button-bg-hover:\s*rgba\(192,\s*202,\s*245,\s*0\.12\);/s,
		);
		expect(css).toMatch(
			/main\[data-theme="codex"\]\s*\{[^}]*--button-bg:\s*rgba\(237,\s*237,\s*237,\s*0\.06\);[^}]*--button-bg-hover:\s*rgba\(237,\s*237,\s*237,\s*0\.12\);/s,
		);
	});

	it("keeps Claude structural surfaces neutral and reserves orange for accents", () => {
		const css = readCssContract("src/style.css");

		expect(css).toMatch(
			/main\[data-theme="claude"\]\s*\{[^}]*--line:\s*#3a3a3a;[^}]*--line-strong:\s*#565656;/s,
		);
		expect(css).toMatch(
			/main\[data-theme="claude"\]\s*\{[^}]*--emphasis-soft:\s*rgba\(192,\s*202,\s*245,\s*0\.08\);[^}]*--task-selected-summary-bg:\s*rgba\(192,\s*202,\s*245,\s*0\.06\);/s,
		);
		expect(css).toMatch(
			/main\[data-theme="claude"\]\s*\{[^}]*--current-step-bg:\s*rgba\(192,\s*202,\s*245,\s*0\.08\);/s,
		);
	});

	it("keeps both theme headers on the same compact row at narrow widths", () => {
		const css = readCssContract("src/style.css");

		expect(css).not.toContain("fieldset.agent-header");
		expect(css).not.toContain(".workbranch-mark");
		expect(css).toMatch(/\.agent-header-copy\s*\{[^}]*flex:\s*1 1 auto/s);
		expect(css).toMatch(
			/@media \(max-width: 400px\)\s*\{[\s\S]*?\.agent-header-row\s*\{[^}]*flex-wrap:\s*nowrap/s,
		);
		expect(css).toMatch(
			/@media \(max-width: 400px\)\s*\{[\s\S]*?\.agent-header h1\s*\{[^}]*font-size:\s*13px[^}]*text-overflow:\s*ellipsis[^}]*white-space:\s*nowrap/s,
		);
	});

	it("right-aligns the settings font select without letting the chevron take layout space", () => {
		// Given the settings stylesheet
		// When the font select row CSS contract is inspected
		const css = readCssContract("src/style.css");

		// Then the select owns the right edge and the chevron is only an overlay
		expect(css).toMatch(/\.settings-row-select\s*\{[^}]*position:\s*relative/s);
		expect(css).toMatch(
			/\.settings-row-select\s+select\s*\{[^}]*margin-left:\s*auto/s,
		);
		expect(css).toMatch(
			/\.settings-row-select::after\s*\{[^}]*position:\s*absolute[^}]*right:\s*10px/s,
		);
		expect(css).not.toMatch(
			/\.settings-row-select::after\s*\{[^}]*margin-left:\s*-32px/s,
		);
	});

	it("keeps the current step strip visually flat instead of card-like", () => {
		// Given the task detail stylesheet
		// When the current-step CSS contract is inspected
		const css = readCssContract("src/style.css");

		// Then the current step reads as a low-profile status strip, not a nested card
		expect(css).toMatch(
			/\.current-step-strip\s*\{[^}]*border-block:\s*1px solid var\(--line\)/s,
		);
		expect(css).toMatch(
			/\.current-step-strip\s+\.prompt-content\s*\{[^}]*display:\s*grid/s,
		);
		expect(css).toMatch(
			/\.prompt-line\[data-current="true"\]\s*\{[^}]*background:\s*var\(--current-step-bg\)/s,
		);
		expect(css).not.toMatch(
			/\.current-step-strip\s*\{[^}]*(?:background|box-shadow|border-radius):/s,
		);
		expect(css).not.toMatch(
			/\.current-step-strip\s*\{[^}]*var\(--shadow-card\)/s,
		);
		expect(css).not.toMatch(
			/\.current-step-strip\s*\{[^}]*var\(--current-step-bg\)/s,
		);
	});

	it("lays out task launch actions as a full-width thirds command bar", () => {
		// Given the task action stylesheet
		// When the action bar CSS contract is inspected
		const css = readCssContract("src/style.css");

		// Then IDE, Terminal, and Finder each occupy one third of the row.
		expect(css).toMatch(/\.task-actions\s*\{[^}]*display:\s*flex/s);
		expect(css).toMatch(/\.task-actions\s*\{[^}]*flex:\s*1 1 100%/s);
		expect(css).toMatch(/\.task-actions\s*\{[^}]*width:\s*100%/s);
		expect(css).toMatch(/\.task-actions\s*\{[^}]*overflow:\s*visible/s);
		expect(css).toMatch(/\.task-action\s*\{[^}]*display:\s*inline-flex/s);
		expect(css).toMatch(/\.task-action\s*\{[^}]*flex:\s*1 1 0/s);
		expect(css).toMatch(/\.task-action\s*\{[^}]*min-width:\s*0/s);
		expect(css).not.toContain(".task-action-separator");
		expect(css).not.toMatch(/\.task-actions\s*\{[^}]*grid-template-columns/s);
	});

	it("renders checklist status markers as aligned dots instead of text glyphs", () => {
		// Given the task detail stylesheet
		// When checklist marker CSS is inspected
		const css = readCssContract("src/style.css");

		// Then marker layout separates status from readable step text
		expect(css).toMatch(/\.step-item\s*\{[^}]*display:\s*grid/s);
		expect(css).toMatch(
			/\.step-item\s*\{[^}]*grid-template-columns:\s*12px minmax\(0, 1fr\)/s,
		);
		expect(css).toMatch(/\.step-marker\s*\{[^}]*border-radius:\s*999px/s);
		expect(css).toMatch(
			/\.step-depth-0\s+\.step-marker\s*\{[^}]*border-radius:\s*2px[^}]*height:\s*8px[^}]*width:\s*8px/s,
		);
		expect(css).toMatch(
			/\.step-depth-1\s+\.step-marker\s*\{[^}]*height:\s*7px[^}]*width:\s*7px/s,
		);
		expect(css).toMatch(
			/\.step-depth-2\s+\.step-marker\s*\{[^}]*height:\s*5px[^}]*width:\s*5px/s,
		);
		expect(css).toMatch(
			/\.step-marker-done,\s*\.step-depth-0\.step-item-done\s+\.step-marker\s*\{[^}]*background:\s*var\(--faint\)/s,
		);
		expect(css).toMatch(
			/\.step-depth-0\.step-item-done\s+\.step-marker\s*\{[^}]*background:\s*var\(--faint\)/s,
		);
		expect(css).not.toMatch(/\.step-marker[^}]*box-shadow:/s);
		expect(css).not.toMatch(
			/\.step-marker-done\s*\{[^}]*background:\s*var\(--done\)/s,
		);
		expect(css).toMatch(
			/\.step-marker-todo\s*\{[^}]*border-color:\s*var\(--line-strong\)/s,
		);
	});

	it("keeps Korean checklist words intact while allowing long paths to wrap", () => {
		const css = readCssContract("src/style.css");

		expect(css).toMatch(
			/\.step-text\s*\{[^}]*overflow-wrap:\s*break-word[^}]*word-break:\s*keep-all/s,
		);
		expect(css).not.toMatch(/\.step-text\s*\{[^}]*overflow-wrap:\s*anywhere/s);
	});

	it("uses a readable text token for small secondary copy", () => {
		const css = readCssContract("src/style.css");

		expect(css).toContain("--muted: #949494");
		expect(css).toMatch(
			/\.settings-panel p,\s*\.settings-hint\s*\{[^}]*color:\s*var\(--muted\)/s,
		);
		expect(css).toMatch(
			/\.font-preview-label\s*\{[^}]*color:\s*var\(--muted\)/s,
		);
		expect(css).toMatch(/\.cal-hour-label\s*\{[^}]*color:\s*var\(--muted\)/s);
		expect(css).toMatch(/\.repo-branch\s*\{[^}]*color:\s*var\(--muted\)/s);
	});

	it("keeps theme tokens in the theme contract and calendar fills theme-aware", () => {
		const baseCss = readFileSync("src/styles/base.css", "utf8");
		const themeCss = readFileSync("src/styles/themes.css", "utf8");
		const activityCss = readFileSync(
			"src/activity/activity-calendar.css",
			"utf8",
		);

		expect(baseCss).not.toContain("--surface-0:");
		expect(themeCss).toContain("--cal-bg-1:");
		expect(themeCss).toContain("--cal-bg-6:");
		expect(activityCss).toContain("--cal-bg: var(--cal-bg-1)");
		expect(activityCss).toContain("--cal-bg: var(--cal-bg-6)");
		expect(activityCss).not.toMatch(/--cal-bg:\s*rgba\(/);
	});

	it("renders settings inside the flexible view panel so bottom nav stays at the shell bottom", () => {
		// Given the app shell source owns view-level layout wrappers
		// When the settings branch is inspected
		const source = readFileSync("src/ui/SettingsView.tsx", "utf8");

		// Then SettingsView uses the same flexing view-panel contract as Main and Activity
		expect(source).toContain('className="settings-view view-panel"');
		expect(source).toContain('aria-label="Settings View"');
		expect(source).toMatch(
			/className="settings-view view-panel"[\s\S]*<SettingsPanel[\s\S]*<\/section>/,
		);
	});

	it("lays out a floating bottom terminal tab row without obscuring content", () => {
		// Given the companion shell stylesheet
		// When the bottom navigation CSS contract is inspected
		const css = readCssContract("src/style.css");

		expect(css).toMatch(/main\s*\{[^}]*padding:\s*12px/s);
		expect(css).toMatch(/main\s*\{[^}]*max-width:\s*100%/s);
		expect(css).toMatch(/main\s*\{[^}]*width:\s*100vw/s);
		expect(css).toMatch(/main\s*\{[^}]*display:\s*flex/s);
		expect(css).toMatch(/main\s*\{[^}]*flex-direction:\s*column/s);
		expect(css).toMatch(/\.view-panel\s*\{[^}]*flex:\s*1 1 auto/s);
		expect(css).toMatch(/main\s*\{[^}]*padding-bottom:\s*[^;]+/s);
		expect(css).toMatch(
			/\.agent-tabs\s*\{[^}]*grid-template-columns:\s*repeat\(3,\s*minmax\(0,\s*1fr\)\)/s,
		);
		expect(css).toMatch(/\.agent-tabs\s*\{[^}]*position:\s*fixed/s);
		expect(css).toMatch(/\.agent-tabs\s*\{[^}]*bottom:\s*[^;]+/s);
		expect(css).not.toContain(".view-nav");
		expect(css).toMatch(/\.agent-tabs\s*\{[^}]*box-shadow/s);
	});

	it("gives the active agent tab an unmistakable terminal selection state", () => {
		const css = readCssContract("src/style.css");

		expect(css).toMatch(
			/\.agent-tabs\s*\{[^}]*background:\s*var\(--surface-0\)[^}]*border:\s*1px solid var\(--line\)[^}]*border-radius:\s*var\(--floating-tabs-radius\)[^}]*overflow:\s*hidden/s,
		);
		expect(css).toMatch(
			/\.agent-tab\s*\{[^}]*border-bottom:\s*2px solid transparent[^}]*min-height:\s*var\(--floating-tabs-height\)/s,
		);
		expect(css).toMatch(
			/\.agent-tab\[data-active="true"\]\s*\{[^}]*background:\s*var\(--surface-2\)[^}]*border-bottom-color:\s*var\(--emphasis\)[^}]*color:\s*var\(--emphasis\)[^}]*font-weight:\s*700/s,
		);
	});

	it("does not force horizontal overflow when the 360px window gains a scrollbar", () => {
		const baseCss = readFileSync("src/styles/base.css", "utf8");

		expect(baseCss).not.toMatch(/body\s*\{[^}]*min-width:/s);
		expect(baseCss).toMatch(/main\s*\{[^}]*max-width:\s*100%/s);
	});

	it("defines only the fixed-dark Claude Code and Codex theme tokens", () => {
		// Given the companion stylesheet
		// When theme selector contracts are inspected
		const css = readCssContract("src/style.css");

		expect(css).toContain('main[data-theme="claude"]');
		expect(css).toContain('main[data-theme="codex"]');
		expect(css).toContain("--accent: #cd694a");
		expect(css).toContain("--emphasis: #cd694a");
		expect(css).toContain("--text: #c0caf5");
		expect(css).toContain("--accent: #5cc2e0");
		expect(css).toContain("--emphasis: #ededed");
		expect(css).toContain("--text: #ededed");
		expect(css).not.toContain('data-theme$="-light"');
		expect(css).not.toMatch(/gradient\(/);
	});
});
