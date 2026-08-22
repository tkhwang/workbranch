import { readFileSync } from "node:fs";
import { Children, isValidElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { buildMatrixModel, type MatrixRow } from "../src/application/state";
import type { GlobalState, Task } from "../src/domain/model";
import {
	DetailPanel,
	MatrixTaskRow,
	StageBoard,
	selectedMatrixRow,
} from "../src/ui/StageBoard";
import {
	type TaskActionKind,
	TaskMetaRow,
	taskActionsFor,
} from "../src/ui/TaskRow";

type ButtonProps = {
	readonly children?: ReactNode;
	readonly "aria-label"?: string;
	readonly "aria-expanded"?: boolean;
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
		{
			name: "workbranch",
			branch: "feat/update-0617",
			dirty: true,
			activityAvailable: true,
			ahead: 2,
			behind: 0,
			changedFiles: 7,
			lastCommitSubject: "implement companion activity feed",
			lastCommitAt: 3_500,
		},
		{
			name: "docs",
			branch: "main",
			dirty: false,
			activityAvailable: true,
			ahead: 0,
			behind: 1,
			changedFiles: 0,
			lastCommitSubject: "document stage board",
			lastCommitAt: 400,
		},
		{
			name: "companion-repository-with-a-name-that-exceeds-stage-card-width",
			branch: "feat/long-repository-name",
			dirty: true,
			activityAvailable: true,
			ahead: 0,
			behind: 0,
			changedFiles: 1,
			lastCommitSubject: "long repository activity",
			lastCommitAt: 0,
		},
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

const todoTask: Task = {
	...planningTask,
	name: "todo-task",
	updatedAt: 5,
	plans: planningTask.plans.map((plan) => ({ ...plan, status: "todo" })),
};

const freshTask: Task = {
	...planningTask,
	name: "fresh-task",
	updatedAt: 15,
	plans: planningTask.plans.map((plan) => ({
		...plan,
		title: "fresh-task",
	})),
};

const noPlanTask: Task = {
	...todoTask,
	name: "no-plan-task",
	updatedAt: 4,
	plans: [],
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
			tasks: [
				planningTask,
				freshTask,
				executionTask,
				blockedTask,
				reviewTask,
				todoTask,
				noPlanTask,
				doneTask,
			],
		},
	],
	errors: [],
};

const planningRow: MatrixRow = {
	blocked: false,
	column: "plan",
	derived: false,
	project: "acme",
	root: "/tmp/acme",
	task: planningTask,
};

const legacyDirtyRow: MatrixRow = {
	blocked: false,
	column: "execution",
	derived: false,
	project: "legacy-project",
	root: "/tmp/legacy",
	task: {
		...executionTask,
		name: "legacy-task",
		repos: [
			{
				name: "legacy-repo",
				branch: "feature/legacy-task",
				dirty: true,
				ahead: 0,
				behind: 0,
				changedFiles: 0,
				lastCommitSubject: "",
				lastCommitAt: 0,
				activityAvailable: false,
			},
		],
	},
};

function renderBoard(selectedKey?: string): string {
	return renderToStaticMarkup(
		<StageBoard
			matrix={buildMatrixModel(state)}
			nowSeconds={3_600}
			onOpenIde={() => undefined}
			onSelect={() => undefined}
			selectedKey={selectedKey}
		/>,
	);
}

function planningRowButton(
	openCalls: string[],
	selectCalls: number[],
): ButtonProps | undefined {
	const element = MatrixTaskRow({
		onOpenIde: (root, task) => openCalls.push(`${root}:${task.name}`),
		onSelect: () => selectCalls.push(1),
		row: planningRow,
		selected: false,
	});
	return collectButtonProps(element).find(
		(candidate) =>
			candidate["aria-label"] === "planning-task, PLAN, show details",
	);
}

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
	it("renders the numbered three-stage header with a hot execution column", () => {
		const html = renderBoard();

		expect(html).toContain('aria-label="Task stage board"');
		expect(html).toContain('class="stage-matrix-caption">ACTIVE');
		expect(html).toContain('class="stage-matrix-count">6</span>');
		expect(html).toContain('class="stage-matrix-col-num">01</span>');
		expect(html).toContain('class="stage-matrix-col-num">03</span>');
		expect(html).not.toContain('class="stage-matrix-col-num">04');
		expect(html).toContain('class="stage-matrix-col-label">PLAN</span>');
		expect(html).toContain('class="stage-matrix-col-label">EXEC</span>');
		expect(html).toContain('class="stage-matrix-col-label">REVIEW</span>');
		expect(html).not.toContain('class="stage-matrix-col-label">TODO');
		expect(html).not.toContain('class="stage-matrix-col-label">DONE');
		expect(html.match(/data-hot="true"/g)).toHaveLength(1);
		expect(html).not.toContain("<fieldset");
		expect(html).not.toContain("<svg");
		expect(html).not.toContain("aria-expanded");
	});

	it("places active tasks on the matrix grouped by project lane", () => {
		const html = renderBoard();

		expect(html).toContain('class="stage-lane-label">PROJECT</span>');
		expect(html).toContain('class="stage-lane-name">acme</span>');
		expect(html.match(/class="stage-matrix-row"/g)).toHaveLength(6);
		expect(html.match(/data-cell="current"/g)).toHaveLength(6);
		const order = [
			"done-task",
			"blocked-task",
			"generated-task-with-a-very-long-name",
			"feat-update-0617-part2",
			"fresh-task",
			"planning-task",
		].map((name) => html.indexOf(`title="${name}"`));
		expect(order.every((position) => position >= 0)).toBe(true);
		expect([...order].sort((left, right) => left - right)).toEqual(order);
	});

	it("marks current stage nodes by column with blocked and derived cues", () => {
		const html = renderBoard();

		expect(html.match(/article[^>]*data-column="execution"/g)).toHaveLength(3);
		expect(html).toContain(
			'class="stage-node" data-blocked="true" data-column="execution"',
		);
		expect(html.match(/article[^>]*data-column="review"/g)).toHaveLength(1);
		expect(html.match(/article[^>]*data-column="plan"/g)).toHaveLength(2);
		expect(html).toContain('class="stage-task-derived">DERIVED</span>');
		expect(html).toContain('class="stage-task-blocked">BLOCKED</span>');
	});

	it("shows the most active task in the detail panel by default", () => {
		const html = renderBoard();

		expect(html.match(/aria-pressed="true"/g)).toHaveLength(1);
		expect(html.match(/class="stage-detail-panel"/g)).toHaveLength(1);
		expect(html).toContain('class="stage-detail-caption">DETAIL</span>');
		expect(html).toContain('class="stage-detail-task" title="done-task"');
		expect(html).toContain('data-status="done"');
		expect(html).toContain("▸ Review screenshot");
		expect(html).toContain(
			'class="stage-repo-name stage-repo-dirty">workbranch',
		);
		expect(html).toContain(
			'class="stage-repo-branch" title="feat/update-0617">feat/update-0617</span>',
		);
		expect(html).toContain(
			'class="stage-repo-facts">DIRTY 7 FILES · AHEAD 2</span>',
		);
		expect(html).toContain('class="stage-repo-facts">CLEAN · BEHIND 1</span>');
		expect(html).toContain("implement companion activity feed · 1m");
		expect(html).toContain('title="implement companion activity feed"');
	});

	it("shows the selected task in the detail panel", () => {
		const html = renderBoard("/tmp/acme:planning-task");

		expect(html).toContain('class="stage-detail-task" title="planning-task"');
		expect(html).toContain('data-status="planning"');
		expect(html).toContain("▸ Implement change");
		expect(html.match(/class="stage-detail-panel"/g)).toHaveLength(1);
	});

	it("falls back to the first row when the selected key is stale", () => {
		const matrix = buildMatrixModel(state);

		expect(selectedMatrixRow(matrix, undefined)?.task.name).toBe("done-task");
		expect(selectedMatrixRow(matrix, "/tmp/acme:gone")?.task.name).toBe(
			"done-task",
		);
		expect(
			selectedMatrixRow(matrix, "/tmp/acme:planning-task")?.task.name,
		).toBe("planning-task");
		expect(
			selectedMatrixRow({ lanes: [], others: [], activeCount: 0 }, undefined),
		).toBeUndefined();
	});

	it("retains clean todo and done tasks in an OTHER disclosure", () => {
		const html = renderBoard();

		expect(html).toContain('class="stage-other"');
		expect(html).toContain('class="stage-other-label">OTHER</span>');
		expect(html).toContain('class="stage-other-count">2</span>');
		expect(html).toContain("todo-task");
		expect(html).toContain("no-plan-task");
		expect(html).toContain('title="Double-click to open todo-task in IDE"');
	});

	it("keeps IDE hints on matrix rows", () => {
		const html = renderBoard();

		expect(html).toContain(
			'title="Double-click or ⌘Enter to open done-task in IDE"',
		);
		expect(html).toContain(
			'title="Double-click or ⌘Enter to open planning-task in IDE"',
		);
	});

	it("opens the task in the IDE on double-click without selecting twice mattering", () => {
		const openCalls: string[] = [];
		const selectCalls: number[] = [];
		const button = planningRowButton(openCalls, selectCalls);

		// a real double-click delivers click(detail 1), click(detail 2), dblclick
		button?.onClick?.({ detail: 1 });
		button?.onClick?.({ detail: 2 });
		button?.onDoubleClick?.();

		expect(openCalls).toEqual(["/tmp/acme:planning-task"]);
		// selection is idempotent, so re-selecting the same row is harmless
		expect(selectCalls).toHaveLength(2);
	});

	it("selects on single click and keyboard activation", () => {
		const openCalls: string[] = [];
		const selectCalls: number[] = [];
		const button = planningRowButton(openCalls, selectCalls);

		button?.onClick?.({ detail: 0 });
		button?.onClick?.({ detail: 1 });
		button?.onClick?.({ detail: 3 });

		expect(selectCalls).toHaveLength(2);
		expect(openCalls).toEqual([]);
	});

	it("opens the IDE from the keyboard with cmd/ctrl+enter", () => {
		const openCalls: string[] = [];
		const selectCalls: number[] = [];
		const button = planningRowButton(openCalls, selectCalls);

		button?.onKeyDown?.({
			key: "Enter",
			metaKey: false,
			ctrlKey: false,
			preventDefault: () => undefined,
		});
		expect(openCalls).toEqual([]);

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
		]);
		expect(selectCalls).toEqual([]);
	});

	it("opens OTHER tasks in the IDE on keyboard activation", () => {
		const calls: string[] = [];
		const html = renderToStaticMarkup(
			<StageBoard
				matrix={buildMatrixModel(state)}
				nowSeconds={3_600}
				onOpenIde={(root, task) => calls.push(`${root}:${task.name}`)}
				onSelect={() => undefined}
				selectedKey={undefined}
			/>,
		);
		expect(html).toContain('aria-label="open todo-task in IDE"');
	});

	it("does not render dirty zero for a mixed-version legacy CLI payload", () => {
		const html = renderToStaticMarkup(
			<DetailPanel nowSeconds={3_600} row={legacyDirtyRow} />,
		);

		expect(html).toContain('class="stage-repo-facts">DIRTY</span>');
		expect(html).not.toContain("DIRTY 0");
	});

	it("uses the shared three-column grid and node color contract", () => {
		const css = readFileSync("src/styles/stage-board.css", "utf8");

		expect(css).toMatch(
			/\.stage-board\s*\{[^}]*--stage-grid:\s*minmax\(0, 1fr\) repeat\(3, 48px\)/s,
		);
		expect(css).toMatch(
			/\.stage-matrix-head\s*\{[^}]*grid-template-columns:\s*var\(--stage-grid\)/s,
		);
		expect(css).toMatch(
			/\.stage-matrix-line\s*\{[^}]*grid-template-columns:\s*var\(--stage-grid\)[^}]*min-width:\s*0/s,
		);
		expect(css).toMatch(
			/\.stage-node\[data-column="execution"\]\s*\{[^}]*background:\s*var\(--emphasis\)[^}]*box-shadow:\s*0 0 0 3px var\(--emphasis-soft\)/s,
		);
		expect(css).toMatch(
			/\.stage-node\[data-column="execution"\]\[data-blocked="true"\]\s*\{[^}]*background:\s*var\(--blocked\)/s,
		);
		expect(css).toMatch(
			/\.stage-node\[data-column="plan"\]\s*\{[^}]*background:\s*transparent[^}]*border:\s*2px solid var\(--accent\)/s,
		);
		expect(css).toMatch(
			/\.stage-node\[data-column="review"\]\s*\{[^}]*background:\s*var\(--review\)/s,
		);
		expect(css).not.toMatch(/\.stage-node\[data-column="(?:todo|done)"\]/);
		expect(css).toMatch(
			/\.stage-matrix-row\[data-selected="true"\] \.stage-matrix-line\s*\{[^}]*background:\s*var\(--task-selected-summary-bg\)/s,
		);
		expect(css).toMatch(
			/\.stage-matrix-line:focus-visible\s*\{[^}]*outline:\s*2px solid var\(--accent\)[^}]*outline-offset:\s*-2px/s,
		);
	});

	it("frames the detail panel as a separate zone below the matrix", () => {
		const css = readFileSync("src/styles/stage-board.css", "utf8");

		expect(css).toMatch(
			/\.stage-detail-panel\s*\{[^}]*background:\s*var\(--surface-1\)[^}]*border:\s*1px solid var\(--line\)[^}]*border-left:\s*2px solid var\(--accent\)/s,
		);
		expect(css).toMatch(
			/\.stage-detail-panel\[data-blocked="true"\]\s*\{[^}]*border-left-color:\s*var\(--blocked\)/s,
		);
		expect(css).toMatch(
			/\.stage-repo-branch\s*\{[^}]*overflow:\s*hidden[^}]*text-overflow:\s*ellipsis/s,
		);
		expect(css).toMatch(
			/\.stage-detail-step\s*\{[^}]*text-overflow:\s*ellipsis/s,
		);
		expect(css).toMatch(
			/\.stage-other\s*\{[^}]*border-top:\s*1px solid var\(--line\)/s,
		);
		expect(css).toMatch(
			/\.stage-board\s*\{[^}]*border:\s*1px solid var\(--line-strong\)/s,
		);
		expect(css).toMatch(
			/\.stage-board\s*\{[^}]*border-top:\s*2px solid var\(--emphasis\)/s,
		);
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
			/\.repo-pair\s*\{[^}]*grid-template-columns:\s*fit-content\(50%\) minmax\(0, 1fr\)[^}]*width:\s*100%/s,
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
		expect(branchRule?.[1]).toMatch(/text-align:\s*right/);
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

		ideButton?.onClick?.({ detail: 1 });

		expect(calls).toEqual([
			{
				root: "/tmp/workbranch",
				taskName: "generated-task-with-a-very-long-name",
				kind: "ide",
			},
		]);
	});
});
