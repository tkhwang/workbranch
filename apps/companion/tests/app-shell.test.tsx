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

	it("renders terminal preference data attributes, icon refresh, top status, and bottom view nav", () => {
		// Given the companion app shell at its initial render
		// When static markup is rendered
		const html = renderToStaticMarkup(<App />);

		// Then the settings-capable shell contract is present before effects run
		expect(html).toContain('data-theme="dracula-dark"');
		expect(html).toContain('data-font="system-mono"');
		expect(html).toContain('aria-label="Refresh tasks"');
		expect(html).toContain('aria-label="Quit Companion"');
		expect(html).toContain('class="toolbar-status"');
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

	it("lays out task launch actions as a compact inline command bar", () => {
		// Given the task action stylesheet
		// When the action bar CSS contract is inspected
		const css = readCssContract("src/style.css");

		// Then IDE, Terminal, and Finder stay compact instead of becoming large cards
		expect(css).toMatch(/\.task-actions\s*\{[^}]*display:\s*flex/s);
		expect(css).toMatch(/\.task-actions\s*\{[^}]*align-items:\s*center/s);
		expect(css).toMatch(/\.task-action\s*\{[^}]*display:\s*inline-flex/s);
		expect(css).not.toMatch(/\.task-actions\s*\{[^}]*grid-template-columns/s);
		expect(css).not.toMatch(/\.task-action\s*\{[^}]*width:\s*100%/s);
	});

	it("keeps the bottom view menu in normal flow instead of covering task content", () => {
		// Given the companion shell stylesheet
		// When the bottom navigation CSS contract is inspected
		const css = readCssContract("src/style.css");

		// Then the command bar is part of the popover layout, not a fixed overlay
		expect(css).toMatch(/main\s*\{[^}]*padding:\s*12px/s);
		expect(css).not.toMatch(/main\s*\{[^}]*padding:[^;}]*78px/s);
		expect(css).toMatch(/\.view-nav\s*\{[^}]*position:\s*static/s);
		expect(css).toMatch(
			/\.view-nav\s*\{[^}]*grid-template-columns:\s*repeat\(3,\s*minmax\(0,\s*1fr\)\)/s,
		);
		expect(css).toMatch(/\.view-nav-button\s*\{[^}]*min-width:\s*0/s);
		expect(css).toMatch(/\.view-nav-button\s*\{[^}]*justify-self:\s*stretch/s);
		expect(css).not.toMatch(/\.view-nav-button\s*\{[^}]*width:\s*100%/s);
		expect(css).not.toMatch(/\.view-nav\s*\{[^}]*position:\s*fixed/s);
	});

	it("defines the eight famous dark and light theme token selectors", () => {
		// Given the companion stylesheet
		// When theme selector contracts are inspected
		const css = readCssContract("src/style.css");

		// Then each dark/light family has app tokens and representative swatch chips
		for (const theme of [
			"dracula-dark",
			"nord-dark",
			"solarized-dark",
			"gruvbox-dark",
			"dracula-light",
			"nord-light",
			"solarized-light",
			"gruvbox-light",
		]) {
			expect(css).toContain(`main[data-theme="${theme}"]`);
			expect(css).toContain(`.theme-swatch-${theme}`);
		}
		expect(css).toContain("--theme-swatch-accent");
		expect(css).not.toMatch(/\.theme-swatch-[^{]+\{[^}]*linear-gradient/s);
	});
});
