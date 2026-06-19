import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { App } from "../src/App";

function readCssContract(path: string): string {
	const css = readFileSync(path, "utf8");
	const importedCss = Array.from(css.matchAll(/@import "(.+)";/g))
		.map((match) => readCssContract(join(dirname(path), match[1] ?? "")))
		.join("\n");
	return `${css}\n${importedCss}`;
}

describe("App shell settings wiring", () => {
	it("renders terminal preference data attributes, icon refresh, bottom view nav, and live status footer", () => {
		// Given the companion app shell at its initial render
		// When static markup is rendered
		const html = renderToStaticMarkup(<App />);

		// Then the settings-capable shell contract is present before effects run
		expect(html).toContain('data-theme="dracula-dark"');
		expect(html).toContain('data-font="system-mono"');
		expect(html).toContain('aria-label="Refresh tasks"');
		expect(html).toContain('aria-label="Quit Companion"');
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

	it("lays out task launch actions as equal full-width thirds", () => {
		// Given the task action stylesheet
		// When the action bar CSS contract is inspected
		const css = readCssContract("src/style.css");

		// Then IDE, Terminal, and Finder divide the row evenly
		expect(css).toMatch(
			/\.task-actions\s*\{[^}]*display:\s*grid[^}]*grid-template-columns:\s*repeat\(3,\s*minmax\(0,\s*1fr\)\)/s,
		);
		expect(css).toMatch(/\.task-action\s*\{[^}]*width:\s*100%/s);
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
