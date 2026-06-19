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
							children: [],
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

describe("TaskRow", () => {
	it("renders nested checklist children for generated task briefs", () => {
		const html = renderToStaticMarkup(
			<TaskRow
				root="/tmp/workbranch"
				task={nestedChecklistTask}
				expanded={true}
				onAction={() => {}}
			/>,
		);

		expect(html).toContain("Generated Plan");
		expect(html).toContain("Implement change");
		expect(html).toContain("Run verification");
		expect(html.indexOf("☐ Generated Plan")).toBeLessThan(
			html.indexOf("☐ Implement change"),
		);
	});
	it("renders a Raycast-style task summary with current step and repo state", () => {
		const html = renderToStaticMarkup(
			<TaskRow
				root="/tmp/workbranch"
				task={linearFixtureTask}
				expanded={true}
				onAction={() => {}}
			/>,
		);

		expect(html).toContain("task-status-rail");
		expect(html).toContain("Companion UI refresh");
		expect(html).toContain("Review screenshot");
		expect(html).toContain("2/4");
		expect(html).toContain("repo-chip repo-dirty");
		expect(html).toContain("workbranch");
		expect(html).toContain("feat/update-0617");
	});
	it("renders task status as a quiet dot without a check glyph", () => {
		const html = renderToStaticMarkup(
			<TaskRow
				root="/tmp/workbranch"
				task={doneFixtureTask}
				expanded={true}
				onAction={() => {}}
			/>,
		);

		expect(html).toContain('aria-label="Done"');
		expect(html).toContain('class="task-status-dot"');
		expect(html).not.toContain('class="task-status-rail">✓</span>');
	});
	it("exposes only IDE, Terminal, and Finder actions", () => {
		const html = renderToStaticMarkup(
			<TaskRow
				root="/tmp/workbranch"
				task={nestedChecklistTask}
				expanded={true}
				onAction={() => {}}
			/>,
		);

		expect(html).toContain('aria-label="open generated-task in IDE"');
		expect(html).toContain('aria-label="open generated-task in terminal"');
		expect(html).toContain('aria-label="open generated-task in Finder"');
		expect(html).not.toContain("edit memo for generated-task");
		expect(html).not.toContain("clear memo for generated-task");
		expect(html).not.toContain("clear notifications for generated-task");
		expect(html).not.toContain("copy path for generated-task");
		expect(
			taskActionsFor(nestedChecklistTask).map((action) => action.label),
		).toEqual(["IDE", "Terminal", "Finder"]);
	});
	it("passes the project root, task, and action kind when a row action is clicked", () => {
		const calls: ActionCall[] = [];
		const element = TaskRow({
			root: "/tmp/workbranch",
			task: nestedChecklistTask,
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
