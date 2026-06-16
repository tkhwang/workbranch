import { Children, isValidElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type { Task } from "../src/domain/model";
import { type TaskActionKind, TaskRow } from "../src/ui/TaskRow";

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

describe("TaskRow", () => {
	it("renders nested checklist children for generated task briefs", () => {
		const html = renderToStaticMarkup(
			<TaskRow
				project="workbranch"
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
	it("exposes the allowed task actions from each row", () => {
		const html = renderToStaticMarkup(
			<TaskRow
				project="workbranch"
				root="/tmp/workbranch"
				task={nestedChecklistTask}
				expanded={true}
				onAction={() => {}}
			/>,
		);

		expect(html).toContain('aria-label="edit memo for generated-task"');
		expect(html).toContain('aria-label="clear memo for generated-task"');
		expect(html).toContain(
			'aria-label="clear notifications for generated-task"',
		);
		expect(html).toContain('aria-label="open generated-task in Finder"');
		expect(html).toContain('aria-label="open generated-task in IDE"');
		expect(html).toContain('aria-label="open generated-task in terminal"');
		expect(html).toContain('aria-label="copy path for generated-task"');
	});
	it("passes the project root, task, and action kind when a row action is clicked", () => {
		const calls: ActionCall[] = [];
		const element = TaskRow({
			project: "workbranch",
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
