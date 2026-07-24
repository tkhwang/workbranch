import { readFileSync } from "node:fs";
import { Children, isValidElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type { Task } from "../src/domain/model";
import {
	type TaskActionKind,
	TaskRow,
	taskActionsFor,
} from "../src/ui/TaskRow";

type ButtonProps = {
	readonly children?: ReactNode;
	readonly "aria-label"?: string;
	readonly onClick?: () => void;
};

type ActionCall = {
	readonly root: string;
	readonly taskName: string;
	readonly kind: TaskActionKind;
};

function collectButtonProps(node: ReactNode): readonly ButtonProps[] {
	const buttons: ButtonProps[] = [];
	const visit = (child: ReactNode): void => {
		if (!isValidElement<ButtonProps>(child)) {
			return;
		}
		if (child.type === "button") {
			buttons.push(child.props);
		}
		Children.forEach(child.props.children, visit);
	};
	visit(node);
	return buttons;
}

const nestedChecklistTask: Task = {
	name: "generated-task",
	path: "/tmp/workbranch/generated-task",
	memoTitle: "",
	notiCount: 2,
	updatedAt: 10,
	repos: [],
	plans: [
		{
			title: "Generated Plan",
			index: 0,
			status: "in-progress",
			progressDone: 0,
			progressTotal: 2,
			currentItem: "Implement change",
			steps: [
				{
					text: "Generated Plan",
					checked: false,
					depth: 0,
					children: [
						{
							text: "Implement change",
							checked: false,
							depth: 1,
							children: [
								{
									text: "Wire depth-specific marker",
									checked: false,
									depth: 2,
									children: [],
								},
							],
						},
						{
							text: "Run verification",
							checked: false,
							depth: 1,
							children: [],
						},
					],
				},
			],
		},
	],
};

const linearFixtureTask: Task = {
	name: "feat-update-0617-part2",
	path: "/tmp/workbranch/feat-update-0617-part2",
	memoTitle: "Review companion UI",
	notiCount: 1,
	updatedAt: 30,
	repos: [
		{ name: "workbranch", branch: "feat/update-0617", dirty: true },
		{ name: "docs", branch: "main", dirty: false },
	],
	plans: [
		{
			title: "Companion UI refresh",
			index: 0,
			status: "review",
			progressDone: 2,
			progressTotal: 4,
			currentItem: "Review screenshot",
			steps: [
				{
					text: "Companion UI refresh",
					checked: true,
					depth: 0,
					children: [
						{
							text: "Write design contract",
							checked: true,
							depth: 1,
							children: [],
						},
						{
							text: "Review screenshot",
							checked: false,
							depth: 1,
							children: [],
						},
					],
				},
			],
		},
	],
};

const doneFixtureTask: Task = {
	...linearFixtureTask,
	plans: [
		{
			title: "Companion UI refresh",
			index: 0,
			status: "done",
			progressDone: 4,
			progressTotal: 4,
			currentItem: "Done",
			steps: [],
		},
	],
};

function renderTaskRow(
	task: Task,
	theme: "claude" | "codex" = "claude",
): string {
	return renderToStaticMarkup(
		<TaskRow
			root="/tmp/workbranch"
			task={task}
			theme={theme}
			expanded={true}
			onAction={() => {}}
		/>,
	);
}

describe("TaskRow", () => {
	it("renders nested checklist children for generated task briefs", () => {
		const html = renderTaskRow(nestedChecklistTask);

		expect(html).toContain("Generated Plan");
		expect(html).toContain("Implement change");
		expect(html).toContain("Run verification");
		expect(html).toContain("Wire depth-specific marker");
		expect(html).toContain('class="step-item step-item-todo step-depth-0"');
		expect(html).toContain('class="step-item step-item-todo step-depth-1"');
		expect(html).toContain('class="step-item step-item-todo step-depth-2"');
		expect(html).toContain('class="step-marker step-marker-todo"');
		expect(html).toContain('class="step-text"');
		expect(html.indexOf("Generated Plan")).toBeLessThan(
			html.indexOf("Implement change"),
		);
		expect(html).not.toContain("☐ Generated Plan");
		expect(html).not.toContain("☐ Implement change");
	});
	it("renders a terminal task summary with current step and repo state", () => {
		const html = renderTaskRow(linearFixtureTask);

		expect(html).toContain("❯");
		expect(html).toContain("REVIEW");
		expect(html).toContain("Companion UI refresh");
		expect(html).toContain("Review screenshot");
		expect(html).toContain("2/4");
		expect(html).toContain('class="repo-pair"');
		expect(html).toContain('class="repo-name repo-dirty"');
		expect(html).toContain('class="repo-branch-chip">feat/update-0617</span>');
		expect(html).not.toContain('class="repo-chip"');
		expect(html).not.toContain('class="repo-chip repo-dirty"');
		expect(html).not.toContain('class="repo-separator"');
		expect(html).not.toContain(" | ");
	});
	it("highlights the expanded task and renders progress as a compact pill", () => {
		const html = renderTaskRow(linearFixtureTask);
		const inProgressHtml = renderTaskRow(nestedChecklistTask);
		const baseCss = readFileSync("src/styles/base.css", "utf8");
		const css = readFileSync("src/styles/task-details.css", "utf8");
		const themeCss = readFileSync("src/styles/themes.css", "utf8");

		expect(html).toContain('<details class="task task-review" open="">');
		expect(html).toContain('<span class="task-progress">2/4</span>');
		expect(inProgressHtml).toMatch(
			/task-summary-line[\s\S]*?data-current="false"/,
		);
		expect(inProgressHtml).toMatch(
			/current-step-strip[\s\S]*?data-current="true"/,
		);
		expect(css).toMatch(
			/\.task\[open\]\s*\{[^}]*background:\s*var\(--surface-2\)/s,
		);
		expect(baseCss).toContain("--task-selected-accent-width: 2px");
		expect(themeCss).toMatch(
			/main\[data-theme="claude"\]\s*\{[^}]*--task-selected-summary-bg:\s*rgba\(192,\s*202,\s*245,\s*0\.06\)/s,
		);
		expect(themeCss).toMatch(
			/main\[data-theme="codex"\]\s*\{[^}]*--task-selected-summary-bg:\s*rgba\(237,\s*237,\s*237,\s*0\.06\)/s,
		);
		expect(css).toMatch(
			/\.task\[open\] > summary\s*\{[^}]*background:\s*var\(--task-selected-summary-bg\)[^}]*border-inline-start:\s*var\(--task-selected-accent-width\) solid var\(--emphasis\)/s,
		);
		expect(css).not.toMatch(
			/\.task\[open\] > summary\s*\{[^}]*background:\s*var\(--emphasis-soft\)/s,
		);
		expect(css).not.toMatch(
			/\.task-in-progress\s*\{[^}]*border-color:\s*var\(--emphasis\)/s,
		);
		expect(css).toMatch(
			/\.task-progress\s*\{[^}]*border-radius:\s*var\(--progress-pill-radius\)[^}]*font-size:\s*var\(--progress-pill-font-size\)[^}]*padding:\s*var\(--progress-pill-padding\)/s,
		);
	});
	it("balances narrow CJK checklist lines to preserve semantic phrases", () => {
		const css = readFileSync("src/styles/task-details.css", "utf8");

		expect(css).toMatch(/\.step-text\s*\{[^}]*text-wrap:\s*balance/s);
	});
	it("renders task status as visible text with a quiet marker", () => {
		const html = renderTaskRow(doneFixtureTask);

		expect(html).toContain('data-status="done"');
		expect(html).toContain('class="status-token-marker"');
		expect(html).toContain('class="status-token-label">DONE</span>');
	});
	it("exposes only IDE, Terminal, and Finder actions", () => {
		const html = renderTaskRow(nestedChecklistTask);

		expect(html).toContain("RUN");
		expect(html).toContain('aria-label="open generated-task in IDE"');
		expect(html).toContain('aria-label="open generated-task in terminal"');
		expect(html).toContain('aria-label="open generated-task in Finder"');
		expect(html).toContain(">IDE</button>");
		expect(html).toContain(">Terminal</button>");
		expect(html).toContain(">Finder</button>");
		expect(html).not.toContain("<svg");
		expect(html).not.toContain("task-action-separator");
		expect(html).not.toContain("edit memo for generated-task");
		expect(html).not.toContain("clear memo for generated-task");
		expect(html).not.toContain("clear notifications for generated-task");
		expect(html).not.toContain("copy path for generated-task");
		expect(
			taskActionsFor(nestedChecklistTask).map((action) => action.label),
		).toEqual(["IDE", "Terminal", "Finder"]);
	});
	it("renders launch actions in the detail header before checklist steps", () => {
		// Given a task with repo chips and checklist steps
		const html = renderTaskRow(linearFixtureTask);

		// When the expanded detail markup is rendered
		const actionIndex = html.indexOf('class="task-actions"');
		const stepsIndex = html.indexOf('class="steps"');

		// Then launch actions stay in the top detail header before long steps
		expect(html).toContain('class="task-detail-header"');
		expect(actionIndex).toBeGreaterThan(-1);
		expect(stepsIndex).toBeGreaterThan(-1);
		expect(actionIndex).toBeLessThan(stepsIndex);
	});

	it("renders the Codex prompt marker through semantic markup", () => {
		const html = renderTaskRow(linearFixtureTask, "codex");

		expect(html).toContain('data-prompt-theme="codex"');
		expect(html).toContain("›");
		expect(html).not.toContain("❯");
	});

	it("renders checklist status as visual markers outside the step text", () => {
		// Given a task with completed and pending checklist rows
		const html = renderTaskRow(linearFixtureTask);

		// When the expanded checklist is rendered
		// Then checked/pending state is a marker, not a loose text glyph prefix
		expect(html).toContain('class="step-item step-item-done step-depth-0"');
		expect(html).toContain('class="step-marker step-marker-done"');
		expect(html).toContain('aria-label="completed step"');
		expect(html).toContain('class="step-item step-item-todo step-depth-1"');
		expect(html).toContain('class="step-marker step-marker-todo"');
		expect(html).toContain('aria-label="pending step"');
		expect(html).not.toContain("✓ Companion UI refresh");
		expect(html).not.toContain("☐ Review screenshot");
	});

	it("marks checklist hierarchy with stronger classes for higher levels", () => {
		// Given nested plan, step, and sub-step checklist rows
		const html = renderTaskRow(nestedChecklistTask);

		// When the expanded checklist is rendered
		// Then each depth gets a separate visual marker class, capped at sub-step level
		expect(html).toContain('class="step-item step-item-todo step-depth-0"');
		expect(html).toContain('class="step-item step-item-todo step-depth-1"');
		expect(html).toContain('class="step-item step-item-todo step-depth-2"');
		expect(html.indexOf("step-depth-0")).toBeLessThan(
			html.indexOf("step-depth-1"),
		);
		expect(html.indexOf("step-depth-1")).toBeLessThan(
			html.indexOf("step-depth-2"),
		);
	});

	it("passes the project root, task, and action kind when a row action is clicked", () => {
		const calls: ActionCall[] = [];
		const element = TaskRow({
			root: "/tmp/workbranch",
			task: nestedChecklistTask,
			theme: "claude",
			expanded: true,
			onAction: (root, task, kind) => {
				calls.push({ root, taskName: task.name, kind });
			},
		});
		const ideButton = collectButtonProps(element).find(
			(button) => button["aria-label"] === "open generated-task in IDE",
		);

		ideButton?.onClick?.();

		expect(calls).toEqual([
			{ root: "/tmp/workbranch", taskName: "generated-task", kind: "ide" },
		]);
	});
});
