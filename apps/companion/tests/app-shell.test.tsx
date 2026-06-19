import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { App } from "../src/App";

describe("App shell settings wiring", () => {
	it("renders terminal preference data attributes, icon refresh, bottom view nav, and live status footer", () => {
		// Given the companion app shell at its initial render
		// When static markup is rendered
		const html = renderToStaticMarkup(<App />);

		// Then the settings-capable shell contract is present before effects run
		expect(html).toContain('data-theme="terminal-dark"');
		expect(html).toContain('data-font="system-mono"');
		expect(html).toContain('aria-label="Refresh tasks"');
		expect(html).not.toContain(">Refresh</button>");
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
		const css = readFileSync("src/style.css", "utf8");

		// Then the app shell font follows the selected monospace setting
		expect(css).toMatch(
			/main\s*\{[^}]*font-family:\s*var\(--app-font-family\)/s,
		);
		expect(css).toContain('main[data-font="menlo"]');
		expect(css).toContain('--app-font-family: "Menlo"');
	});
});
