import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type { MenuSummary } from "../src/application/state";
import { AgentHeader } from "../src/ui/AgentHeader";
import { AgentTabs } from "../src/ui/AgentTabs";
import { PromptLine } from "../src/ui/PromptLine";
import { StatusToken } from "../src/ui/StatusToken";
import { TerminalPanel } from "../src/ui/TerminalPanel";

const summary: MenuSummary = {
	projectCount: 2,
	taskCount: 3,
	active: 1,
	blocked: 1,
	notifications: 4,
};

const controls = {
	status: "Ready",
	onRefresh: () => undefined,
	onQuit: () => undefined,
};

describe("agent primitives", () => {
	it("renders the same text-only expanded header anatomy for each theme", () => {
		const claude = renderToStaticMarkup(
			<AgentHeader theme="claude" summary={summary} {...controls} />,
		);
		const codex = renderToStaticMarkup(
			<AgentHeader theme="codex" summary={summary} {...controls} />,
		);

		expect(
			claude.replace('data-agent-header="claude"', 'data-agent-header="theme"'),
		).toBe(
			codex.replace('data-agent-header="codex"', 'data-agent-header="theme"'),
		);
		for (const html of [claude, codex]) {
			expect(html).toContain("<section");
			expect(html).toContain("<h1>Workbranch Companion</h1>");
			expect(html).not.toContain("<fieldset");
			expect(html).not.toContain("<svg");
			expect(html).not.toContain("❯");
			expect(html).not.toContain("&gt;_");
			expect(html).toContain("2 projects · 3 tasks");
			expect(html).not.toContain("1 active");
			expect(html).not.toContain("1 blocked");
			expect(html).not.toContain("4 notifications");
			expect(html).not.toContain("model codex");
			expect(html).not.toContain("directory workbranch");
			expect(html).toContain('aria-label="Refresh tasks"');
			expect(html).toContain('aria-label="Quit Companion"');
			expect(html).toContain('role="status"');
		}
	});

	it("renders three text-only accessible terminal tabs", () => {
		const html = renderToStaticMarkup(
			<AgentTabs currentView="activity" onViewChange={() => undefined} />,
		);

		expect(html.match(/<button/g)).toHaveLength(3);
		expect(html).toContain(">Main</button>");
		expect(html).toContain(">Activity</button>");
		expect(html).toContain(">Settings</button>");
		expect(html.match(/aria-current="page"/g)).toHaveLength(1);
		expect(html).not.toContain("<svg");
	});

	it("renders theme-specific terminal panel semantics", () => {
		const claude = renderToStaticMarkup(
			<TerminalPanel theme="claude" label="Projects">
				Content
			</TerminalPanel>,
		);
		const codex = renderToStaticMarkup(
			<TerminalPanel theme="codex" label="Projects">
				Content
			</TerminalPanel>,
		);

		expect(claude).toContain("<fieldset");
		expect(claude).toContain("<legend>Projects</legend>");
		expect(codex).toContain("<section");
		expect(codex).toContain(">Projects</h2>");
	});

	it("renders theme-specific prompt markers in the markup", () => {
		expect(
			renderToStaticMarkup(
				<PromptLine theme="claude">Current step</PromptLine>,
			),
		).toContain("❯");
		expect(
			renderToStaticMarkup(<PromptLine theme="codex">Current step</PromptLine>),
		).toContain("›");
	});

	it("keeps status text visible alongside its marker", () => {
		const html = renderToStaticMarkup(<StatusToken status="in-progress" />);

		expect(html).toContain("RUN");
		expect(html).toContain('aria-hidden="true"');
	});
});
