import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type { ProjectGroup as ProjectGroupModel } from "../src/application/state";
import type { Task } from "../src/domain/model";
import { ProjectGroup } from "../src/ui/ProjectGroup";

const task = (name: string, updatedAt: number): Task => ({
	name,
	path: `/tmp/acme/${name}`,
	memoTitle: "",
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
	it("renders the project header with task count above its task rows", () => {
		const html = renderToStaticMarkup(
			<ProjectGroup group={group} onAction={() => {}} />,
		);
		expect(html).toContain("project-group-header");
		expect(html).toContain("acme");
		expect(html).toContain("2 tasks");
		expect(html).toContain("feat-a");
		expect(html.indexOf("project-group-header")).toBeLessThan(
			html.indexOf("feat-a"),
		);
	});
});
