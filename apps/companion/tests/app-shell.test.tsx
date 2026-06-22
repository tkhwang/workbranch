import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { App } from "../src/App";

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

	it("renders terminal preference data attributes, icon controls, screen-reader status, and bottom view nav", () => {
		// Given the companion app shell at its initial render
		// When static markup is rendered
		const html = renderToStaticMarkup(<App />);

		// Then the settings-capable shell contract is present before effects run
		expect(html).toContain('data-theme="catppuccin-dark"');
		expect(html).toContain('data-font="system-mono"');
		expect(html).toContain('aria-label="Refresh tasks"');
		expect(html).toContain('aria-label="Quit Companion"');
		expect(html).toContain('class="toolbar-status-sr"');
		expect(html).not.toContain('class="toolbar-status"');
		expect(html).toContain(">Ready</span>");
		expect(html).not.toContain("<footer");
		expect(html).not.toContain(">Refresh</button>");
		expect(html).not.toContain(">Quit</button>");
		expect(html).toContain('class="toolbar-icon"');
		expect(html).toContain('aria-label="Companion views"');
		expect(html).toContain('aria-label="Open Main View"');
		expect(html).toContain('aria-label="Open Activity report"');
		expect(html).toContain('aria-label="Open Settings"');
		expect(html).toContain('role="status"');
		expect(html).toContain('aria-live="polite"');
	});

	it("keeps toolbar status available to assistive tech without a visible top-line chip", () => {
		// Given the companion toolbar stylesheet
		// When the status chip CSS contract is inspected
		const css = readCssContract("src/style.css");

		// Then status updates remain announced while the visible top line stays focused on controls
		expect(css).toMatch(/header\s*\{[^}]*flex-wrap:\s*wrap/s);
		expect(css).toMatch(/\.toolbar\s*\{[^}]*flex:\s*1 1 180px/s);
		expect(css).toMatch(/\.toolbar\s*\{[^}]*justify-content:\s*flex-end/s);
		expect(css).toMatch(/\.toolbar-status-sr\s*\{[^}]*position:\s*absolute/s);
		expect(css).toMatch(
			/\.toolbar-status-sr\s*\{[^}]*clip:\s*rect\(0 0 0 0\)/s,
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

	it("keeps static button background fallbacks outside color-mix supports", () => {
		// Given the companion stylesheet is built for chrome105 and safari13 WebViews
		// When the button background token contract is inspected
		const css = readCssContract("src/style.css");
		const [cssBeforeColorMixSupports = ""] = css.split(
			"@supports (background: color-mix(in srgb, black, white))",
		);

		// Then unsupported color-mix tokens cannot invalidate default button backgrounds
		expect(css).toMatch(
			/main\s*\{[^}]*--button-bg:\s*rgba\(255,\s*215,\s*154,\s*0\.07\);[^}]*--button-bg-hover:\s*rgba\(255,\s*215,\s*154,\s*0\.13\);/s,
		);
		expect(css).toMatch(
			/@supports\s*\(background:\s*color-mix\(in srgb,\s*black,\s*white\)\)\s*\{\s*main\s*\{[^}]*--button-bg:\s*color-mix\(in srgb,\s*var\(--text\) 6%,\s*transparent\);[^}]*--button-bg-hover:\s*color-mix\(in srgb,\s*var\(--text\) 12%,\s*transparent\);/s,
		);
		expect(cssBeforeColorMixSupports).not.toMatch(
			/--button-bg:\s*color-mix\(in srgb,\s*var\(--text\)/,
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
			/\.current-step-strip\s*\{[^}]*background:\s*var\(--surface-2\)/s,
		);
		expect(css).toMatch(
			/\.current-step-strip\s*\{[^}]*box-shadow:\s*inset 1px 0 0 var\(--accent\)/s,
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
		expect(css).toMatch(/\.task-action-separator\s*\{[^}]*display:\s*none/s);
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
			/\.step-depth-1\s+\.step-marker\s*\{[^}]*border-radius:\s*999px[^}]*height:\s*7px[^}]*width:\s*7px/s,
		);
		expect(css).toMatch(
			/\.step-depth-2\s+\.step-marker\s*\{[^}]*height:\s*5px[^}]*width:\s*5px/s,
		);
		expect(css).toMatch(
			/\.step-marker-done\s*\{[^}]*background:\s*var\(--faint\)/s,
		);
		expect(css).toMatch(
			/\.step-depth-0\.step-item-done\s+\.step-marker\s*\{[^}]*background:\s*var\(--faint\)[^}]*box-shadow:\s*0 0 0 2px var\(--line\)/s,
		);
		expect(css).not.toMatch(
			/\.step-marker-done\s*\{[^}]*background:\s*var\(--done\)/s,
		);
		expect(css).toMatch(
			/\.step-marker-todo\s*\{[^}]*border:\s*1px solid var\(--line-strong\)/s,
		);
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

	it("keeps the bottom view menu floating without covering task content", () => {
		// Given the companion shell stylesheet
		// When the bottom navigation CSS contract is inspected
		const css = readCssContract("src/style.css");

		// Then the command bar stays visible as a sticky floating affordance
		expect(css).toMatch(/main\s*\{[^}]*padding:\s*12px/s);
		expect(css).toMatch(/main\s*\{[^}]*max-width:\s*100%/s);
		expect(css).toMatch(/main\s*\{[^}]*width:\s*100vw/s);
		expect(css).toMatch(/main\s*\{[^}]*display:\s*flex/s);
		expect(css).toMatch(/main\s*\{[^}]*flex-direction:\s*column/s);
		expect(css).toMatch(/\.view-panel\s*\{[^}]*flex:\s*1 1 auto/s);
		expect(css).toMatch(/\.view-panel\s*\{[^}]*padding-bottom:\s*52px/s);
		expect(css).not.toMatch(/main\s*\{[^}]*padding:[^;}]*78px/s);
		expect(css).toMatch(/\.view-nav\s*\{[^}]*bottom:\s*10px/s);
		expect(css).toMatch(/\.view-nav\s*\{[^}]*position:\s*sticky/s);
		expect(css).toMatch(/\.view-nav\s*\{[^}]*z-index:\s*3/s);
		expect(css).toMatch(
			/\.view-nav\s*\{[^}]*grid-template-columns:\s*repeat\(3,\s*minmax\(0,\s*1fr\)\)/s,
		);
		expect(css).toMatch(/\.view-nav-button\s*\{[^}]*min-width:\s*0/s);
		expect(css).toMatch(/\.view-nav-button\s*\{[^}]*justify-self:\s*stretch/s);
		expect(css).not.toMatch(/\.view-nav-button\s*\{[^}]*width:\s*100%/s);
		expect(css).not.toMatch(/\.view-nav\s*\{[^}]*position:\s*fixed/s);
		expect(css).not.toMatch(/\.view-nav\s*\{[^}]*position:\s*static/s);
	});

	it("defines only the curated dark and light theme token selectors", () => {
		// Given the companion stylesheet
		// When theme selector contracts are inspected
		const css = readCssContract("src/style.css");

		// Then the app exposes one dark and one light palette with no swatch-card CSS
		expect(css).toContain('main[data-theme="catppuccin-dark"]');
		expect(css).toContain('main[data-theme="breakfast-light"]');
		expect(css).toContain("#1e1e2e");
		expect(css).toContain("#cba6f7");
		expect(css).toContain("#ffffff");
		expect(css).toContain("#7c3aed");
		for (const removedTheme of [
			"breakfast-dark",
			"solarized-dark",
			"dracula-dark",
			"github-dark",
			"solarized-light",
			"dracula-light",
			"catppuccin-light",
			"github-light",
			"nord-dark",
			"gruvbox-dark",
		]) {
			expect(css).not.toContain(`main[data-theme="${removedTheme}"]`);
		}
		expect(css).not.toContain(".theme-swatch-");
		expect(css).not.toContain("--theme-swatch-accent");
	});
});
