import { renderToStaticMarkup } from "react-dom/server";
import { expect, it } from "vitest";
import { StageBoard } from "../src/ui/StageBoard";

it("keeps base repository diagnostics available under runtime view", () => {
	const html = renderToStaticMarkup(
		<StageBoard
			baseRows={[
				{
					key: "p:r",
					project: "p",
					root: "/p",
					showProject: false,
					repo: {
						name: "repo",
						baseBranch: "main",
						branch: "main",
						present: true,
						dirty: true,
						changedFiles: 3,
						remoteAvailable: true,
						ahead: 0,
						behind: 2,
						inspectionError: null,
					},
				},
			]}
			groups={[]}
			idleRows={[]}
			idleCount={0}
			activeCount={0}
			notes={{}}
			onSaveNote={() => {}}
			onAction={() => {}}
			onSelect={() => {}}
			selectedKey={undefined}
		/>,
	);
	expect(html).toContain("CHECK");
	expect(html).toContain("DIRTY 3 FILES");
	expect(html).toContain("BASE REPOSITORIES · 새 workspace의 기준");
	const summary = html.slice(
		html.indexOf("<summary"),
		html.indexOf("</summary>"),
	);
	expect(summary).toContain('data-health="warn"');
	expect(summary).toContain('class="runtime-bases-issues"');
});
