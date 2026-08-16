import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type { ProjectGroup as ProjectGroupModel } from "../src/application/state";
import type { Task } from "../src/domain/model";
import { ProjectGroup } from "../src/ui/ProjectGroup";

const task = (name: string, updatedAt: number): Task => ({
	name,
	path: `/tmp/acme/${name}`,
	notiCount: 0,
	updatedAt,
	repos: [],
	plans: [],
});

const group: ProjectGroupModel = {
	project: "acme",
	root: "/tmp/acme",
	rows: [
		{
			project: "acme",
			root: "/tmp/acme",
			task: task("feat-a", 20),
			expanded: false,
		},
		{
			project: "acme",
			root: "/tmp/acme",
			task: task("feat-b", 10),
			expanded: false,
		},
	],
};

describe("ProjectGroup", () => {
	it("renders theme-specific terminal panels around project tasks", () => {
		const claudeHtml = renderToStaticMarkup(
			<ProjectGroup theme="claude" group={group} onAction={() => undefined} />,
		);
		const codexHtml = renderToStaticMarkup(
			<ProjectGroup theme="codex" group={group} onAction={() => undefined} />,
		);

		expect(claudeHtml).toContain('data-terminal-panel="claude"');
		expect(claudeHtml).toContain("<fieldset");
		expect(claudeHtml).toContain("❯");
		expect(codexHtml).toContain('data-terminal-panel="codex"');
		expect(codexHtml).toContain("<section");
		expect(codexHtml).toContain("›");
		expect(claudeHtml).toContain("acme · 2 tasks");
		expect(claudeHtml).toContain("feat-a");
		expect(claudeHtml.indexOf("acme · 2 tasks")).toBeLessThan(
			claudeHtml.indexOf("feat-a"),
		);
	});
});
