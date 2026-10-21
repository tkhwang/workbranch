import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { App } from "../src/App";
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
	it("opens at 860px for the kanban board while preserving the 460px compact boundary", () => {
		const config = JSON.parse(
			readFileSync("src-tauri/tauri.conf.json", "utf8"),
		) as {
			readonly app: {
				readonly windows: readonly {
					readonly width: number;
					readonly height: number;
					readonly minWidth?: number;
					readonly resizable: boolean;
				}[];
			};
		};

		expect(config.app.windows[0]).toMatchObject({
			width: 860,
			height: 760,
			minWidth: 460,
			resizable: true,
		});
	});

	it("uses the stage-grouped MainViewModel and repo notes without legacy queues", () => {
		const appSource = readFileSync("src/App.tsx", "utf8");

		expect(appSource).toContain("buildMainViewModel");
		expect(appSource).toContain("<StageBoard");
		expect(appSource).toContain("useRepoNotes");
		expect(appSource).toContain("baseRows={main.baseRows}");
		expect(appSource).toContain("groups={main.stageGroups}");
		expect(appSource).toContain("idleRows={main.idleRows}");
		expect(appSource).not.toContain("RepositoryQueue");
		expect(appSource).not.toContain("ProjectGroup");
		expect(appSource).toContain("{model.errors.map");
	});

	it("puts the usage summary above the stage board and usage details in their own tab", () => {
		const appSource = readFileSync("src/App.tsx", "utf8");

		expect(appSource).toContain("useUsage(tauriRuntimeAvailable)");
		expect(appSource.indexOf('aria-label="Main View"')).toBeLessThan(
			appSource.indexOf("<UsageSummary"),
		);
		expect(appSource.indexOf("<UsageSummary")).toBeLessThan(
			appSource.indexOf("connectionPanel(true)"),
		);
		expect(appSource.indexOf("<UsageSummary")).toBeLessThan(
			appSource.indexOf("<StageBoard"),
		);
		expect(appSource).toContain(
			'onOpenDetails={() => setCurrentView("usage")}',
		);
		expect(appSource).toContain('currentView === "usage"');
		expect(appSource).not.toContain("WeeklyLimitGauge");
		expect(appSource).not.toContain("Activity");
		expect(readFileSync("src/style.css", "utf8")).toContain(
			'@import "./styles/usage.css";',
		);
	});

	it("includes the base repository row and action style contracts", () => {
		const css = readCssContract("src/style.css");

		expect(css).toContain(".stage-base-row");
		expect(css).toContain('.stage-base-action[data-action="pull"]');
		expect(css).toMatch(
			/\.stage-base-row\s*\{[^}]*grid-template-columns:\s*10px minmax\(68px, 0\.8fr\) minmax\(0, 1fr\)\s*minmax\(0, 1\.5fr\) auto/s,
		);
		expect(css).toMatch(
			/\.stage-base-facts\s*\{[^}]*min-width:\s*0[^}]*overflow:\s*hidden[^}]*text-overflow:\s*ellipsis[^}]*white-space:\s*nowrap/s,
		);
		expect(css).toMatch(
			/@media \(max-width: 480px\)\s*\{[\s\S]*?\.stage-base-row\s*\{[^}]*grid-template-columns:\s*10px minmax\(64px, 0\.8fr\) minmax\(0, 1fr\) auto[^}]*\}[\s\S]*?\.stage-base-facts\s*\{[^}]*grid-column:\s*2 \/ 4[^}]*grid-row:\s*2[^}]*text-align:\s*left/s,
		);
	});

	it("refreshes when the tray opens the window instead of a refresh button", () => {
		const appSource = readFileSync("src/App.tsx", "utf8");

		expect(appSource).toContain("onWindowFocused(");
		expect(appSource).not.toContain("onRefresh={() => void refresh()}");
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
		expect(html).toContain('data-font-size="medium"');
		expect(html).toContain('data-agent-header="claude"');
		expect(html).toContain("<h1>Workbranch Companion</h1>");
		expect(html).not.toContain("<fieldset");
		expect(html).not.toContain("<svg");
		expect(html).not.toContain('aria-label="Refresh tasks"');
		expect(html).toContain('aria-label="Check for updates"');
		expect(html).toContain('aria-label="Quit Companion"');
		expect(html).toContain('class="toolbar-status-sr"');
		expect(html).toContain(">Ready</span>");
		expect(html).not.toContain("<footer");
		expect(html).toContain('aria-label="Companion views"');
		expect(html).toContain('aria-label="Agent runtime"');
		expect(html).toContain('class="runtime-summary"');
		expect(html).not.toContain("ALL REPOSITORIES");
		expect(html).toContain(">Main</button>");
		expect(html).toContain(">Usage</button>");
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
			/main\[data-theme="claude"\]\s*\{[^}]*--button-bg:\s*rgba\(223,\s*230,\s*233,\s*0\.06\);[^}]*--button-bg-hover:\s*rgba\(223,\s*230,\s*233,\s*0\.12\);/s,
		);
		expect(css).toMatch(
			/main\[data-theme="codex"\]\s*\{[^}]*--button-bg:\s*rgba\(223,\s*230,\s*233,\s*0\.06\);[^}]*--button-bg-hover:\s*rgba\(223,\s*230,\s*233,\s*0\.12\);/s,
		);
	});

	it("reserves the Claude blue accent for compact signals instead of structural backgrounds", () => {
		// Given the fixed-dark Claude theme contract
		// When structural and selected-state tokens are inspected
		const css = readCssContract("src/style.css");

		// Then neutral surfaces own broad areas while blue remains the emphasis signal
		expect(css).toMatch(
			/main\[data-theme="claude"\]\s*\{[^}]*--line:\s*#3d4649;[^}]*--line-strong:\s*#636e72;/s,
		);
		expect(css).toMatch(
			/main\[data-theme="claude"\]\s*\{[^}]*--emphasis-soft:\s*rgba\(9,\s*132,\s*227,\s*0\.16\);[^}]*--task-selected-summary-bg:\s*rgba\(223,\s*230,\s*233,\s*0\.06\);/s,
		);
		expect(css).toMatch(
			/main\[data-theme="claude"\]\s*\{[^}]*--current-step-bg:\s*rgba\(223,\s*230,\s*233,\s*0\.08\);/s,
		);
		expect(css).not.toMatch(
			/main\[data-theme="claude"\]\s*\{[^}]*--line:\s*rgba\(205,\s*105,\s*74/s,
		);
	});

	it("tones up both fixed-dark themes with tinted surfaces and lines", () => {
		// Given the two fixed-dark theme blocks
		// When their structural surfaces and pre-hydration background are inspected
		const css = readCssContract("src/style.css");

		// Then both share Flat UI Dracula Orchid surfaces from first paint
		expect(css).toMatch(
			/main\[data-theme="claude"\]\s*\{[^}]*--surface-0:\s*#131516;[^}]*--surface-1:\s*#1a1f20;[^}]*--surface-2:\s*#22292b;[^}]*--surface-3:\s*#2d3436;/s,
		);
		expect(css).toMatch(
			/main\[data-theme="codex"\]\s*\{[^}]*--surface-0:\s*#131516;[^}]*--surface-1:\s*#1a1f20;[^}]*--surface-2:\s*#22292b;[^}]*--surface-3:\s*#2d3436;/s,
		);
		expect(css).toMatch(
			/main\[data-theme="codex"\]\s*\{[^}]*--line:\s*#3d4649;[^}]*--line-strong:\s*#636e72;/s,
		);
		expect(css).toMatch(/:root\s*\{[^}]*background:\s*#131516/s);
		expect(css).toMatch(/body\s*\{[^}]*background:\s*#131516/s);
	});

	it("colors status token text by state instead of relying on the dot alone", () => {
		// Given visible status labels with state-specific data attributes
		// When the shared status token stylesheet is inspected
		const css = readCssContract("src/style.css");

		// Then active states inherit semantic colors while todo and planning stay muted
		expect(css).toMatch(/\.status-token\s*\{[^}]*color:\s*var\(--muted\)/s);
		expect(css).toMatch(
			/\.status-token\[data-status="in-progress"\]\s*\{[^}]*color:\s*var\(--emphasis\)/s,
		);
		expect(css).toMatch(
			/\.status-token\[data-status="blocked"\]\s*\{[^}]*color:\s*var\(--blocked\)/s,
		);
		expect(css).toMatch(
			/\.status-token\[data-status="review"\]\s*\{[^}]*color:\s*var\(--review\)/s,
		);
		expect(css).toMatch(
			/\.status-token\[data-status="done"\]\s*\{[^}]*color:\s*var\(--done\)/s,
		);
		expect(css).toMatch(
			/\.status-token-marker\s*\{[^}]*height:\s*7px[^}]*width:\s*7px/s,
		);
		expect(css).not.toMatch(
			/\.status-token\[data-status="(?:todo|planning)"\]\s*\{[^}]*color:/s,
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
			/@media \(max-width: 400px\)\s*\{[\s\S]*?\.agent-header h1\s*\{[^}]*font-size:\s*var\(--fs-ui\)[^}]*text-overflow:\s*ellipsis[^}]*white-space:\s*nowrap/s,
		);
	});

	it("keeps the settings select chevron an overlay that takes no layout space", () => {
		// Given the settings stylesheet
		// When the select wrapper CSS contract is inspected
		const css = readCssContract("src/style.css");

		// Then the chevron sits over the select's own right padding
		expect(css).toMatch(/\.settings-select\s*\{[^}]*position:\s*relative/s);
		expect(css).toMatch(
			/\.settings-select select\s*\{[^}]*padding-right:\s*28px/s,
		);
		expect(css).toMatch(
			/\.settings-select::after\s*\{[^}]*pointer-events:\s*none[^}]*position:\s*absolute[^}]*right:\s*10px/s,
		);
	});

	it("draws settings switches from native checkboxes and theme tokens", () => {
		const css = readCssContract("src/style.css");

		expect(css).toMatch(/\.settings-switch\s*\{[^}]*appearance:\s*none/s);
		expect(css).toMatch(
			/\.settings-switch:checked\s*\{[^}]*background:\s*var\(--emphasis\)/s,
		);
		expect(css).toMatch(
			/@media \(prefers-reduced-motion: reduce\)[\s\S]*\.settings-switch,\s*\.settings-switch::before\s*\{[^}]*transition:\s*none/s,
		);
	});

	it("decides Main onboarding from setup state and where an action started", () => {
		const source = readFileSync("src/App.tsx", "utf8");

		expect(source).toContain(
			"needsOnboarding(connections.state, sessions, setupStartedOnMain)",
		);
		expect(source).toContain(
			"onAction={(action) => handleSetupAction(action, onboarding)}",
		);
		expect(source).not.toMatch(/connections\.state\.notice !== null \|\|/);
	});

	it("opens update status on Settings › General from the header control", () => {
		const source = readFileSync("src/App.tsx", "utf8");
		const handler = source.slice(
			source.indexOf("const handleCheckUpdates"),
			source.indexOf("const handleQuit"),
		);

		expect(source).not.toContain("UpdatePanel");
		expect(handler).toContain('setCurrentView("settings")');
		expect(handler).toContain('setSettingsCategory("general")');
		expect(handler).toContain("updates.check()");
	});

	it("keeps the stage board framed and width-safe at the native boundary", () => {
		const css = readCssContract("src/style.css");

		expect(css).toMatch(
			/\.stage-board\s*\{[^}]*border:\s*1px solid var\(--line-strong\)[^}]*border-top:\s*2px solid var\(--emphasis\)/s,
		);
		expect(css).toMatch(/\.stage-group-head\s*\{[^}]*display:\s*flex/s);
		expect(css).not.toContain("--stage-grid");
		expect(css).not.toContain(".current-step-strip");
		expect(css).not.toContain("--shadow-card");
	});

	it("keeps vertical repo facts and notes width-safe at 460px", () => {
		const css = readCssContract("src/style.css");

		expect(css).toMatch(
			/\.stage-repo-facts-line\s*\{[^}]*display:\s*grid[^}]*min-width:\s*0/s,
		);
		expect(css).toMatch(
			/\.stage-repo-branch,[\s\S]*\.stage-note-line\s*\{[^}]*min-width:\s*0[^}]*text-overflow:\s*ellipsis/s,
		);
		expect(css).toMatch(
			/@media \(max-width: 480px\)\s*\{[\s\S]*?\.stage-repo-facts\s*\{[^}]*grid-column:\s*1 \/ 3/s,
		);
		expect(css).toMatch(/\.stage-note-editor textarea\s*\{[^}]*width:\s*100%/s);
	});

	it("uses semantic stage-task cues instead of checklist detail chrome", () => {
		const css = readCssContract("src/style.css");

		expect(css).toMatch(
			/\.stage-task-block\[data-blocked="true"\]\s*\{[^}]*box-shadow:\s*inset 3px 0 0 var\(--blocked\)/s,
		);
		expect(css).toMatch(
			/\.stage-task-blocked\s*\{[^}]*color:\s*var\(--blocked\)/s,
		);
		expect(css).toMatch(
			/\.stage-task-notification\s*\{[^}]*color:\s*var\(--notify\)/s,
		);
		expect(css).not.toContain(".step-marker");
		expect(css).not.toContain(".steps");
	});

	it("truncates grouped task and repo identities", () => {
		const css = readCssContract("src/style.css");

		expect(css).toMatch(
			/\.stage-task-name\s*\{[^}]*overflow:\s*hidden[^}]*text-overflow:\s*ellipsis[^}]*white-space:\s*nowrap/s,
		);
		expect(css).toMatch(
			/\.stage-repo-branch,[\s\S]*text-overflow:\s*ellipsis/s,
		);
	});

	it("uses a readable text token for small secondary copy", () => {
		const css = readCssContract("src/style.css");

		expect(css).toContain("--muted: #b2bec3");
		expect(css).not.toContain("--muted: #949494");
		expect(css).toContain("--faint: #9aa4a8");
		expect(css).not.toContain("--faint: #767c99");
		expect(css).not.toContain("--faint: #6b6b70");
		expect(css).not.toContain("--faint: #626262");
		expect(css).not.toContain("--faint: #5d5d5d");
		expect(css).toMatch(
			/\.settings-page-description,\s*\.settings-hint\s*\{[^}]*color:\s*var\(--muted\)/s,
		);
		expect(css).toMatch(
			/\.settings-row-description\s*\{[^}]*color:\s*var\(--muted\)/s,
		);
		expect(css).toMatch(
			/\.font-preview-label\s*\{[^}]*color:\s*var\(--muted\)/s,
		);
		expect(css).toMatch(
			/\.usage-limit-label\s*\{[^}]*color:\s*var\(--muted\)/s,
		);
		expect(css).toMatch(
			/\.stage-repo-branch\s*\{[^}]*color:\s*var\(--faint\)/s,
		);
	});

	it("routes every typographic selector through the scaled size tokens", () => {
		// Given the role-named type scale that --font-scale multiplies
		// When every production selector in the map is inspected
		const css = readCssContract("src/style.css");
		const expectedTypographyRules = [
			/main\s*\{[^}]*font-size:\s*var\(--fs-body\)/s,
			/button,\s*select,\s*input\s*\{[^}]*font-size:\s*var\(--fs-ui\)/s,
			/\.stage-task-prompt\s*\{[^}]*font-size:\s*var\(--fs-body\)/s,
			/main\s*\{[^}]*--floating-tabs-font-size:\s*var\(--fs-ui\)/s,
			/main\s*\{[^}]*--progress-pill-font-size:\s*var\(--fs-label\)/s,
			/\.terminal-panel legend\s*\{[^}]*font-size:\s*var\(--fs-label\)/s,
			/\.agent-header h1\s*\{[^}]*font-size:\s*var\(--fs-title\)/s,
			/\.agent-inventory\s*\{[^}]*font-size:\s*var\(--fs-body\)/s,
			/\.agent-control\s*\{[^}]*font-size:\s*var\(--fs-title\)/s,
			/\.terminal-panel-heading\s*\{[^}]*font-size:\s*var\(--fs-label\)/s,
			/\.status-token\s*\{[^}]*font-size:\s*var\(--fs-body\)/s,
			/\.stage-matrix-caption\s*\{[^}]*font-size:\s*var\(--fs-label\)/s,
			/\.stage-group-num\s*\{[^}]*font-size:\s*var\(--fs-label\)/s,
			/\.stage-group-label\s*\{[^}]*font-size:\s*var\(--fs-label\)/s,
			/\.stage-group-count\s*\{[^}]*font-size:\s*var\(--fs-label\)/s,
			/\.stage-task-name\s*\{[^}]*font-size:\s*var\(--fs-body\)/s,
			/\.stage-task-derived,\s*\.stage-task-blocked,\s*\.stage-task-progress,\s*\.stage-task-notification\s*\{[^}]*font-size:\s*var\(--fs-label\)/s,
			/\.stage-current-line\s*\{[^}]*font-size:\s*var\(--fs-body\)/s,
			/\.stage-repo-name\s*\{[^}]*font-size:\s*var\(--fs-body\)/s,
			/\.stage-repo-branch\s*\{[^}]*font-size:\s*var\(--fs-body\)/s,
			/\.stage-repo-facts,\s*\.stage-repo-commit,\s*\.stage-note-line\s*\{[^}]*font-size:\s*var\(--fs-meta\)/s,
			/\.stage-note-editor textarea\s*\{[^}]*font-size:\s*var\(--fs-meta\)/s,
			/\.error,\s*\.empty\s*\{[^}]*font-size:\s*var\(--fs-ui\)/s,
			/\.task-action\s*\{[^}]*font-size:\s*var\(--fs-body\)/s,
			/\.app-error\s*\{[^}]*font-size:\s*var\(--fs-ui\)/s,
			/\.settings-nav-tab\s*\{[^}]*font-size:\s*var\(--fs-label\)/s,
			/\.settings-page button,\s*\.settings-page select\s*\{[^}]*font-size:\s*var\(--fs-meta\)/s,
			/\.settings-page-eyebrow\s*\{[^}]*font-size:\s*var\(--fs-meta\)/s,
			/\.settings-page-header h2\s*\{[^}]*font-size:\s*var\(--fs-title\)/s,
			/\.settings-page-description,\s*\.settings-hint\s*\{[^}]*font-size:\s*var\(--fs-meta\)/s,
			/\.settings-group-header h3\s*\{[^}]*font-size:\s*var\(--fs-meta\)/s,
			/\.settings-row-title strong,\s*\.settings-row-title label\s*\{[^}]*font-size:\s*var\(--fs-body\)/s,
			/\.settings-row-description\s*\{[^}]*font-size:\s*var\(--fs-meta\)/s,
			/\.settings-select::after\s*\{[^}]*font-size:\s*var\(--fs-ui\)/s,
			/\.settings-badge\s*\{[^}]*font-size:\s*var\(--fs-label\)/s,
			/\.settings-note\s*\{[^}]*font-size:\s*var\(--fs-meta\)/s,
			/\.font-preview\s*\{[^}]*font-size:\s*var\(--fs-body\)/s,
			/\.font-preview-label\s*\{[^}]*font-size:\s*var\(--fs-label\)/s,
			/\.font-preview-meta\s*\{[^}]*font-size:\s*var\(--fs-meta\)/s,
			/\.usage-name\s*\{[^}]*font-size:\s*var\(--fs-meta\)/s,
			/\.usage-limit\s*\{[^}]*font-size:\s*var\(--fs-meta\)/s,
			/\.usage-limit-detail\s*\{[^}]*font-size:\s*var\(--fs-label\)/s,
			/\.usage-axis\s*\{[^}]*font-size:\s*var\(--fs-label\)/s,
			/\.usage-table\s*\{[^}]*font-size:\s*var\(--fs-meta\)/s,
		] as const;

		// Then native smoothing is used and no selector re-hardcodes a pixel size
		expect(css).not.toContain("-webkit-font-smoothing");
		expect(css).not.toMatch(/font-size:\s*\d+(?:\.\d+)?px/);
		for (const rule of expectedTypographyRules) {
			expect(css).toMatch(rule);
		}
	});

	it("scales the whole shell from one --font-scale with medium unscaled", () => {
		// Given the Text Size contract shared by preferences.ts and themes.css
		// When the base scale and its four steps are inspected
		const css = readCssContract("src/style.css");
		const baseSizes = [
			/main\s*\{[^}]*--font-scale:\s*1;/s,
			/--fs-label:\s*calc\(11px \* var\(--font-scale\)\)/,
			/--fs-meta:\s*calc\(12px \* var\(--font-scale\)\)/,
			/--fs-body:\s*calc\(13px \* var\(--font-scale\)\)/,
			/--fs-ui:\s*calc\(14px \* var\(--font-scale\)\)/,
			/--fs-title:\s*calc\(16px \* var\(--font-scale\)\)/,
		] as const;
		const steps = [
			/main\[data-font-size="small"\]\s*\{[^}]*--font-scale:\s*0\.92/s,
			/main\[data-font-size="medium"\]\s*\{[^}]*--font-scale:\s*1;/s,
			/main\[data-font-size="large"\]\s*\{[^}]*--font-scale:\s*1\.15/s,
			/main\[data-font-size="extra-large"\]\s*\{[^}]*--font-scale:\s*1\.3/s,
		] as const;

		// Then every step resolves through the same tokens, and none drops below 11px
		for (const rule of [...baseSizes, ...steps]) {
			expect(css).toMatch(rule);
		}
		const tokenBaseSizes = [
			...css.matchAll(/--fs-[a-z]+:\s*calc\((\d+)px/g),
		].map(([, size]) => Number(size));
		expect(tokenBaseSizes).toHaveLength(5);
		expect(tokenBaseSizes.every((size) => size >= 11)).toBe(true);
	});

	it("sizes the shell root so nothing falls back to the 16px user-agent default", () => {
		// Given text that carries no font-size of its own, such as the task row
		// prompt glyph and the Settings selects
		// When the inherited baseline is inspected
		const css = readCssContract("src/style.css");
		const mainRule = /main\s*\{([^}]*)\}/s.exec(css);

		// Then main declares a scaled font-size, so every descendant inherits one
		expect(mainRule?.[1]).toMatch(/font-size:\s*var\(--fs-[a-z]+\)/);
		expect(mainRule?.[1]).not.toMatch(/font-size:\s*\d/);
		// And form controls, which reset to `font: inherit`, take an explicit role
		expect(css).toMatch(
			/button,\s*select,\s*input\s*\{[^}]*font:\s*inherit;[^}]*font-size:\s*var\(--fs-ui\)/s,
		);
	});

	it("keeps theme tokens in the theme contract", () => {
		const baseCss = readFileSync("src/styles/base.css", "utf8");
		const themeCss = readFileSync("src/styles/themes.css", "utf8");

		expect(baseCss).not.toContain("--surface-0:");
		expect(themeCss).toContain("--provider-claude:");
		expect(themeCss).toContain("--provider-codex:");
	});

	it("renders settings inside the flexible view panel so bottom nav stays at the shell bottom", () => {
		// Given the app shell source owns view-level layout wrappers
		// When the settings branch is inspected
		const source = readFileSync("src/ui/SettingsView.tsx", "utf8");

		// Then SettingsView uses the same flexing view-panel contract as Main and Usage
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

	it("does not force horizontal overflow when the 460px window gains a scrollbar", () => {
		const baseCss = readFileSync("src/styles/base.css", "utf8");

		expect(baseCss).not.toMatch(/body\s*\{[^}]*min-width:/s);
		expect(baseCss).toMatch(/main\s*\{[^}]*max-width:\s*100%/s);
	});

	it("aligns each daily total under its own bar", () => {
		const css = readCssContract("src/style.css");
		const slot =
			/\.usage-compare-day\s*\{\s*gap:\s*1px;\s*padding:\s*0 2px;\s*\}/s;
		const values =
			/\.usage-values-day\s*\{[^}]*display:\s*flex;[^}]*gap:\s*1px;[^}]*padding:\s*0 2px;/s;

		// The totals row repeats the bar slot's padding and gap in equal parts
		expect(css).toMatch(slot);
		expect(css).toMatch(values);
		expect(css).toMatch(
			/\.usage-values-day > \[data-provider\]\s*\{[^}]*flex:\s*1 1 0/s,
		);
		expect(css).toMatch(/\.usage-compare-bar\s*\{[^}]*flex:\s*1 1 0/s);
		// And stacks under the day once the slots are too narrow for both
		expect(css).toMatch(
			/@container usage \(max-width: 46em\)\s*\{\s*\.usage-values-day\s*\{[^}]*display:\s*grid/s,
		);
	});

	it("defines only the fixed-dark Claude Code and Codex theme tokens", () => {
		// Given the companion stylesheet
		// When theme selector contracts are inspected
		const css = readCssContract("src/style.css");

		expect(css).toContain('main[data-theme="claude"]');
		expect(css).toContain('main[data-theme="codex"]');
		expect(css).toContain("--accent: #0984e3");
		expect(css).toContain("--emphasis: #0984e3");
		expect(css).toContain("--text: #dfe6e9");
		expect(css).toContain("--surface-0: #131516");
		expect(css).toContain("--surface-1: #1a1f20");
		expect(css).toContain("--line: #3d4649");
		expect(css).not.toContain("--line: rgba(205, 105, 74");
		expect(css).toContain("--accent: #00cec9");
		expect(css).toContain("--emphasis: #dfe6e9");
		expect(css).toContain("--text: #dfe6e9");
		expect(css).not.toContain('data-theme$="-light"');
		expect(css).not.toMatch(/gradient\(/);
	});
});
