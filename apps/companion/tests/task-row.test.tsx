import { readFileSync } from "node:fs";
import { Children, isValidElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { buildMainViewModel, type MainTaskRow } from "../src/application/state";
import type { GlobalState, Task } from "../src/domain/model";
import { MatrixTaskRow, StageBoard } from "../src/ui/StageBoard";
import {
	type TaskActionKind,
	TaskMetaRow,
	taskActionsFor,
} from "../src/ui/TaskRow";

type ButtonProps = {
	readonly children?: ReactNode;
	readonly "aria-label"?: string;
	readonly onClick?: (event: { readonly detail: number }) => void;
	readonly onDoubleClick?: () => void;
	readonly onKeyDown?: (event: {
		readonly key: string;
		readonly metaKey: boolean;
		readonly ctrlKey: boolean;
		readonly preventDefault: () => void;
	}) => void;
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

function task(
	name: string,
	status: Task["plans"][number]["status"],
	updatedAt: number,
	repos: Task["repos"] = [],
): Task {
	return {
		name,
		path: `/tmp/acme/${name}`,
		notiCount: name === "execution-task" ? 2 : 0,
		updatedAt,
		repos,
		plans: [
			{
				title: `${name} plan`,
				index: 0,
				status,
				progressDone: status === "review" ? 2 : 0,
				progressTotal: 4,
				currentItem: `${name} current work`,
				steps: [],
			},
		],
	};
}

const dirtyRepo: Task["repos"][number] = {
	name: "workbranch",
	branch: "feat/update-ui-0824",
	dirty: true,
	activityAvailable: true,
	ahead: 2,
	behind: 0,
	changedFiles: 7,
	lastCommitSubject: "implement companion activity feed",
	lastCommitAt: 3_500,
};

const executionTask = task("execution-task", "in-progress", 30);
const planningTask = task("planning-task", "planning", 10);
const state: GlobalState = {
	projects: [
		{
			name: "acme",
			root: "/tmp/acme",
			tasks: [
				planningTask,
				task("fresh-plan", "planning", 15),
				executionTask,
				task("blocked-task", "blocked", 40),
				task("review-task", "review", 20, [dirtyRepo]),
				task("todo-task", "todo", 5),
				task("done-active", "done", 50, [dirtyRepo]),
				task("done-clean", "done", 4),
			],
		},
	],
	errors: [],
};
const main = buildMainViewModel(state);

const planningRow: MainTaskRow = {
	key: "/tmp/acme:planning-task",
	project: "acme",
	root: "/tmp/acme",
	task: planningTask,
	repos: [],
	role: "plan",
	blocked: false,
	derived: false,
	latestActivityAt: 10,
};

function renderBoard(selectedKey?: string): string {
	return renderToStaticMarkup(
		<StageBoard
			activeCount={main.activeCount}
			idleCount={main.idleCount}
			onOpenIde={() => undefined}
			onSelect={() => undefined}
			rows={main.matrixRows}
			selectedKey={selectedKey}
		/>,
	);
}

function planningRowButton(
	openCalls: string[],
	selectCalls: number[],
): ButtonProps | undefined {
	const element = MatrixTaskRow({
		onOpenIde: (root, selectedTask) =>
			openCalls.push(`${root}:${selectedTask.name}`),
		onSelect: () => selectCalls.push(1),
		row: planningRow,
		selected: false,
	});
	return collectButtonProps(element).find((candidate) =>
		candidate["aria-label"]?.includes("planning-task, PLAN"),
	);
}

describe("StageBoard", () => {
	it("renders a flat worktree status matrix without selected-only detail", () => {
		const html = renderBoard();

		expect(html).toContain('aria-label="Worktree status matrix"');
		expect(html).toContain('class="stage-matrix-caption">WORKTREE STATUS');
		expect(html).toContain('class="stage-matrix-count">6</span>');
		expect(html).toContain('class="stage-matrix-col-label">PLAN</span>');
		expect(html).toContain('class="stage-matrix-col-label">EXECUTION</span>');
		expect(html).toContain('class="stage-matrix-col-label">REVIEW</span>');
		expect(html.match(/class="stage-matrix-row"/g)).toHaveLength(6);
		expect(html).toContain('class="stage-idle-count">IDLE 2 · inactive</span>');
		expect(html).not.toContain("DETAIL");
		expect(html).not.toContain("OTHER");
		expect(html).not.toContain('aria-pressed="true"');
	});

	it("orders review, blocked, execution, and plan rows with project identity", () => {
		const html = renderBoard();
		const order = [
			"review-task",
			"blocked-task",
			"done-active",
			"execution-task",
			"fresh-plan",
			"planning-task",
		].map((name) => html.indexOf(`title="${name}"`));

		expect(order.every((position) => position >= 0)).toBe(true);
		expect([...order].sort((left, right) => left - right)).toEqual(order);
		expect(html).toContain('class="stage-project-name">acme</span>');
	});

	it("marks blocked and derived rows without selecting a default", () => {
		const html = renderBoard();

		expect(html).toContain('class="stage-task-blocked">BLOCKED</span>');
		expect(html).toContain('class="stage-task-derived">DERIVED</span>');
		expect(html).toContain(
			'class="stage-node" data-blocked="true" data-column="execution"',
		);
		expect(html).not.toContain('aria-pressed="true"');
	});

	it("marks only the explicit selected task", () => {
		const html = renderBoard("/tmp/acme:planning-task");

		expect(html.match(/aria-pressed="true"/g)).toHaveLength(1);
		expect(html).toContain('data-selected="true"');
	});

	it("selects on native and pointer click without opening the IDE", () => {
		const openCalls: string[] = [];
		const selectCalls: number[] = [];
		const button = planningRowButton(openCalls, selectCalls);

		button?.onClick?.({ detail: 0 });
		button?.onClick?.({ detail: 1 });
		button?.onClick?.({ detail: 3 });

		expect(selectCalls).toHaveLength(2);
		expect(openCalls).toEqual([]);
	});

	it("opens the configured IDE on double-click and command/control-enter", () => {
		const openCalls: string[] = [];
		const selectCalls: number[] = [];
		const button = planningRowButton(openCalls, selectCalls);

		button?.onDoubleClick?.();
		button?.onKeyDown?.({
			key: "Enter",
			metaKey: true,
			ctrlKey: false,
			preventDefault: () => undefined,
		});
		button?.onKeyDown?.({
			key: "Enter",
			metaKey: false,
			ctrlKey: true,
			preventDefault: () => undefined,
		});

		expect(openCalls).toEqual([
			"/tmp/acme:planning-task",
			"/tmp/acme:planning-task",
			"/tmp/acme:planning-task",
		]);
		expect(selectCalls).toEqual([]);
	});

	it("uses a wide matrix with a 460px compact fallback", () => {
		const css = readFileSync("src/styles/stage-board.css", "utf8");

		expect(css).toMatch(
			/\.stage-board\s*\{[^}]*--stage-grid:\s*minmax\(220px, 1\.7fr\) repeat\(3, minmax\(82px, 0\.62fr\)\)/s,
		);
		expect(css).toMatch(
			/@media \(max-width: 520px\)\s*\{[\s\S]*?\.stage-board\s*\{[^}]*--stage-grid:\s*minmax\(0, 1fr\) repeat\(3, 58px\)/s,
		);
		expect(css).not.toContain(".stage-detail-panel");
		expect(css).not.toContain(".stage-other");
	});
});

describe("TaskMetaRow", () => {
	it("renders status, repositories, and configured launch actions", () => {
		const reviewTask = task("review-task", "review", 20, [dirtyRepo]);
		const html = renderToStaticMarkup(
			<TaskMetaRow
				highlighted={false}
				nowSeconds={3_600}
				repos={reviewTask.repos}
				root="/tmp/acme"
				task={reviewTask}
				taskKey="/tmp/acme:review-task"
				theme="claude"
				onAction={() => undefined}
			/>,
		);

		expect(html).toContain("REVIEW");
		expect(html).toContain("workbranch");
		expect(html).toContain("feat/update-ui-0824");
		expect(html).toContain('aria-label="open review-task in IDE"');
		expect(html).toContain('aria-label="open review-task in terminal"');
		expect(html).toContain('aria-label="open review-task in Finder"');
	});

	it("exposes only IDE, Terminal, and Finder actions", () => {
		expect(taskActionsFor(executionTask).map((action) => action.label)).toEqual(
			["IDE", "Terminal", "Finder"],
		);
	});

	it("passes the project root, task, and action kind when clicked", () => {
		const calls: ActionCall[] = [];
		const element = TaskMetaRow({
			highlighted: false,
			nowSeconds: 3_600,
			repos: executionTask.repos,
			root: "/tmp/acme",
			task: executionTask,
			taskKey: "/tmp/acme:execution-task",
			theme: "claude",
			onAction: (root, selectedTask, kind) => {
				calls.push({ root, taskName: selectedTask.name, kind });
			},
		});
		const ideButton = collectButtonProps(element).find(
			(button) => button["aria-label"] === "open execution-task in IDE",
		);

		ideButton?.onClick?.({ detail: 1 });

		expect(calls).toEqual([
			{ root: "/tmp/acme", taskName: "execution-task", kind: "ide" },
		]);
	});
});
