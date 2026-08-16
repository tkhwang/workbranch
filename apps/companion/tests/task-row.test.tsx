import { readFileSync } from "node:fs";
import { Children, isValidElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { buildBoardModel } from "../src/application/state";
import type { GlobalState, Task } from "../src/domain/model";
import { StageBoard } from "../src/ui/StageBoard";
import {
	type TaskActionKind,
	TaskMetaRow,
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
		if (!isValidElement<ButtonProps>(child)) return;
		if (child.type === "button") buttons.push(child.props);
		Children.forEach(child.props.children, visit);
	};
	visit(node);
	return buttons;
}

const executionTask: Task = {
	name: "generated-task-with-a-very-long-name",
	path: "/tmp/workbranch/generated-task-with-a-very-long-name",
	notiCount: 2,
	updatedAt: 30,
	repos: [],
	plans: [
		{
			title: "Generated Plan",
			index: 0,
			status: "in-progress",
			progressDone: 0,
			progressTotal: 2,
			currentItem: "Implement change",
			steps: [],
		},
	],
};

const reviewTask: Task = {
	name: "feat-update-0617-part2",
	path: "/tmp/workbranch/feat-update-0617-part2",
	notiCount: 1,
	updatedAt: 20,
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
			steps: [],
		},
	],
};

const blockedTask: Task = {
	...executionTask,
	name: "blocked-task",
	notiCount: 0,
	updatedAt: 40,
	plans: executionTask.plans.map((plan) => ({ ...plan, status: "blocked" })),
};

const planningTask: Task = {
	...executionTask,
	name: "planning-task",
	notiCount: 0,
	updatedAt: 10,
	plans: executionTask.plans.map((plan) => ({ ...plan, status: "planning" })),
};

const doneTask: Task = {
	...reviewTask,
	name: "done-task",
	updatedAt: 50,
	plans: reviewTask.plans.map((plan) => ({
		...plan,
		status: "done",
		progressDone: 4,
	})),
};

const state: GlobalState = {
	projects: [
		{
			name: "acme",
			root: "/tmp/acme",
			tasks: [planningTask, executionTask, blockedTask, reviewTask, doneTask],
		},
	],
	errors: [],
};

function renderTaskMetaRow(
	task: Task,
	theme: "claude" | "codex" = "claude",
): string {
	return renderToStaticMarkup(
		<TaskMetaRow
			root="/tmp/workbranch"
			task={task}
			theme={theme}
			onAction={() => undefined}
		/>,
	);
}

describe("StageBoard", () => {
	it("renders three stage columns with compact active task cards", () => {
		const html = renderToStaticMarkup(
			<StageBoard board={buildBoardModel(state)} />,
		);

		expect(html).toContain('aria-label="Task stage board"');
		expect(html).toContain('data-stage="plan"');
		expect(html).toContain('data-stage="execution"');
		expect(html).toContain('data-stage="review"');
		expect(html).toContain("PLAN");
		expect(html).toContain("EXECUTION");
		expect(html).toContain("REVIEW");
		expect(html).toContain("planning-task");
		expect(html).toContain("blocked-task");
		expect(html).toContain("feat-update-0617-part2");
		expect(html).not.toContain("done-task");
	});

	it("keeps project, blocked, progress, notification, and title metadata on cards", () => {
		const html = renderToStaticMarkup(
			<StageBoard board={buildBoardModel(state)} />,
		);

		expect(html).toContain('class="stage-card-project">acme</span>');
		expect(html).toContain('class="stage-card-blocked">BLOCKED</span>');
		expect(html).toContain('class="stage-card-progress">0/2</span>');
		expect(html).toContain('class="stage-card-notification"');
		expect(html).toContain("+2");
		expect(html).toContain('title="generated-task-with-a-very-long-name"');
	});

	it("uses a fixed three-column narrow-window CSS contract", () => {
		const css = readFileSync("src/styles/stage-board.css", "utf8");
		const taskNameRule = css.match(/\.stage-card-name\s*\{([^}]*)\}/s);

		expect(css).toMatch(
			/\.stage-board\s*\{[^}]*grid-template-columns:\s*repeat\(3, minmax\(0, 1fr\)\)/s,
		);
		expect(css).toMatch(/\.stage-column\s*\{[^}]*min-width:\s*0/s);
		expect(taskNameRule?.[1]).toMatch(/overflow-wrap:\s*anywhere/);
		expect(taskNameRule?.[1]).toMatch(/white-space:\s*normal/);
		expect(taskNameRule?.[1]).not.toMatch(/text-overflow:\s*ellipsis/);
		expect(taskNameRule?.[1]).not.toMatch(/overflow:\s*hidden/);
	});

	it("frames the board as the primary Main surface", () => {
		const css = readFileSync("src/styles/stage-board.css", "utf8");

		expect(css).toMatch(
			/\.stage-board\s*\{[^}]*border:\s*1px solid var\(--line-strong\)/s,
		);
		expect(css).toMatch(
			/\.stage-board\s*\{[^}]*border-top:\s*2px solid var\(--emphasis\)/s,
		);
		expect(css).toMatch(/\.stage-board\s*\{[^}]*padding:\s*6px/s);
	});
});

describe("TaskMetaRow", () => {
	it("renders status, repositories, and launch actions without board-only metadata", () => {
		const html = renderTaskMetaRow(reviewTask);

		expect(html).toContain("❯");
		expect(html).toContain("REVIEW");
		expect(html).toContain('class="repo-pair"');
		expect(html).toContain('class="repo-name repo-dirty"');
		expect(html).toContain('class="repo-branch-name">feat/update-0617</span>');
		expect(html).not.toContain("repo-branch-chip");
		expect(html).toContain('aria-label="open feat-update-0617-part2 in IDE"');
		expect(html).toContain(
			'aria-label="open feat-update-0617-part2 in terminal"',
		);
		expect(html).toContain(
			'aria-label="open feat-update-0617-part2 in Finder"',
		);
		expect(html).not.toContain("task-notification");
		expect(html).not.toContain("task-progress");
		expect(html).not.toContain("Review screenshot");
		expect(html).not.toContain("<details");
		expect(html).not.toContain('class="steps"');
	});

	it("keeps done tasks visible in the project meta rows", () => {
		const html = renderTaskMetaRow(doneTask);

		expect(html).toContain("done-task");
		expect(html).toContain('data-status="done"');
		expect(html).toContain('class="status-token-label">DONE</span>');
	});

	it("uses the selected theme prompt anatomy", () => {
		const html = renderTaskMetaRow(reviewTask, "codex");

		expect(html).toContain('data-prompt-theme="codex"');
		expect(html).toContain("›");
		expect(html).not.toContain("❯");
	});

	it("exposes only IDE, Terminal, and Finder actions", () => {
		expect(taskActionsFor(executionTask).map((action) => action.label)).toEqual(
			["IDE", "Terminal", "Finder"],
		);
	});

	it("gives repository metadata and launch tools separate full-width rows", () => {
		const detailsCss = readFileSync("src/styles/task-details.css", "utf8");
		const actionsCss = readFileSync("src/styles/task-actions.css", "utf8");

		expect(detailsCss).toMatch(
			/\.task-meta-secondary\s*\{[^}]*display:\s*grid[^}]*width:\s*100%/s,
		);
		expect(detailsCss).toMatch(
			/\.repo-chips\s*\{[^}]*display:\s*grid[^}]*width:\s*100%/s,
		);
		expect(detailsCss).toMatch(
			/\.repo-pair\s*\{[^}]*grid-template-columns:\s*auto minmax\(0, 1fr\)[^}]*width:\s*100%/s,
		);
		expect(actionsCss).toMatch(
			/\.task-actions\s*\{[^}]*display:\s*grid[^}]*grid-template-columns:\s*repeat\(3, minmax\(0, 1fr\)\)[^}]*width:\s*100%/s,
		);
		expect(actionsCss).toMatch(
			/\.task-action\s*\{[^}]*min-width:\s*0[^}]*width:\s*100%/s,
		);
	});

	it("renders the branch name as full-width plain text without another box", () => {
		const detailsCss = readFileSync("src/styles/task-details.css", "utf8");
		const branchRule = detailsCss.match(/\.repo-branch-name\s*\{([^}]*)\}/s);

		expect(branchRule?.[1]).toMatch(/color:\s*var\(--muted\)/);
		expect(branchRule?.[1]).toMatch(/text-overflow:\s*ellipsis/);
		expect(branchRule?.[1]).toMatch(/width:\s*100%/);
		expect(branchRule?.[1]).not.toMatch(/border(?:-radius)?:/);
		expect(branchRule?.[1]).not.toMatch(/background:/);
		expect(branchRule?.[1]).not.toMatch(/padding:/);
	});

	it("passes the project root, task, and action kind when clicked", () => {
		const calls: ActionCall[] = [];
		const element = TaskMetaRow({
			root: "/tmp/workbranch",
			task: executionTask,
			theme: "claude",
			onAction: (root, task, kind) => {
				calls.push({ root, taskName: task.name, kind });
			},
		});
		const ideButton = collectButtonProps(element).find(
			(button) =>
				button["aria-label"] ===
				"open generated-task-with-a-very-long-name in IDE",
		);

		ideButton?.onClick?.();

		expect(calls).toEqual([
			{
				root: "/tmp/workbranch",
				taskName: "generated-task-with-a-very-long-name",
				kind: "ide",
			},
		]);
	});
});
