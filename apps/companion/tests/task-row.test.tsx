import { readFileSync } from "node:fs";
import { Children, isValidElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { type BoardCard, buildBoardModel } from "../src/application/state";
import type { GlobalState, Task } from "../src/domain/model";
import { StageBoard, StageCard } from "../src/ui/StageBoard";
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
	readonly onKeyDown?: unknown;
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

const planningCard: BoardCard = {
	blocked: false,
	derived: false,
	project: "acme",
	root: "/tmp/acme",
	stage: "plan",
	task: planningTask,
};

const legacyDirtyCard: BoardCard = {
	blocked: false,
	derived: false,
	project: "legacy-project",
	root: "/tmp/legacy",
	stage: "execution",
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
	it("renders the full lifecycle with the current stage on every task", () => {
		const html = renderToStaticMarkup(
			<StageBoard
				board={buildBoardModel(state)}
				nowSeconds={3_600}
				onOpenIde={() => undefined}
			/>,
		);

		expect(html).not.toContain('class="stage-section-header"');
		expect(html.match(/class="stage-lifecycle"/g)).toHaveLength(6);
		expect(html.match(/class="stage-lifecycle-heading"/g)).toHaveLength(6);
		expect(html.match(/class="stage-lifecycle-caption">STAGE/g)).toHaveLength(
			6,
		);
		expect(
			html.match(/class="stage-lifecycle-current-label">PLAN/g),
		).toHaveLength(2);
		expect(
			html.match(/class="stage-lifecycle-current-label">EXECUTION/g),
		).toHaveLength(3);
		expect(
			html.match(/class="stage-lifecycle-current-label">REVIEW/g),
		).toHaveLength(1);
		expect(html.match(/class="stage-lifecycle-node"/g)).toHaveLength(18);
		expect(html.match(/class="stage-lifecycle-connector"/g)).toHaveLength(12);
		expect(html.match(/data-current="true" data-stage="plan"/g)).toHaveLength(
			2,
		);
		expect(
			html.match(/data-current="true" data-stage="execution"/g),
		).toHaveLength(3);
		expect(html.match(/data-current="true" data-stage="review"/g)).toHaveLength(
			1,
		);
		expect(html).not.toContain("[PLAN]");
		expect(html).not.toContain("[EXECUTION]");
		expect(html).not.toContain("[REVIEW]");
		expect(html).toContain("PLAN");
		expect(html).toContain("EXECUTION");
		expect(html).toContain("REVIEW");
	});

	it("retains clean todo and done tasks in an OTHER disclosure", () => {
		const html = renderToStaticMarkup(
			<StageBoard
				board={buildBoardModel(state)}
				nowSeconds={3_600}
				onOpenIde={() => undefined}
			/>,
		);

		expect(html).toContain('class="stage-other"');
		expect(html).toContain('class="stage-other-label">OTHER</span>');
		expect(html).toContain('class="stage-other-count">2</span>');
		expect(html).toContain("todo-task");
		expect(html).toContain("no-plan-task");
		expect(html).toContain("done-task");
		expect(html).toContain('class="stage-task-derived">DERIVED</span>');
	});

	it("keeps OTHER task launchers on the double-click interaction contract", () => {
		const html = renderToStaticMarkup(
			<StageBoard
				board={buildBoardModel(state)}
				nowSeconds={3_600}
				onOpenIde={() => undefined}
			/>,
		);

		expect(html).toContain('title="Double-click to open todo-task in IDE"');
		expect(html).toContain('title="Double-click to open done-task in IDE"');
	});

	it("renders a native IDE launcher over each active task row", () => {
		const html = renderToStaticMarkup(
			<StageBoard
				board={buildBoardModel(state)}
				nowSeconds={3_600}
				onOpenIde={() => undefined}
			/>,
		);

		expect(html.match(/class="stage-task-open"/g)).toHaveLength(6);
		expect(html).toContain('type="button"');
		expect(html).toContain('aria-label="open planning-task in IDE"');
	});

	it("opens the task in the IDE on pointer double-click", () => {
		const calls: string[] = [];
		const element = StageCard({
			card: planningCard,
			nowSeconds: 3_600,
			onOpenIde: (root, task) => calls.push(`${root}:${task.name}`),
		});
		const button = collectButtonProps(element).find(
			(candidate) => candidate["aria-label"] === "open planning-task in IDE",
		);

		button?.onDoubleClick?.();

		expect(calls).toEqual(["/tmp/acme:planning-task"]);
	});

	it("uses native click activation without opening on pointer clicks", () => {
		const calls: string[] = [];
		const element = StageCard({
			card: planningCard,
			nowSeconds: 3_600,
			onOpenIde: (root, task) => calls.push(`${root}:${task.name}`),
		});
		const button = collectButtonProps(element).find(
			(candidate) => candidate["aria-label"] === "open planning-task in IDE",
		);

		button?.onClick?.({ detail: 0 });
		button?.onClick?.({ detail: 1 });
		button?.onClick?.({ detail: 2 });

		expect(calls).toEqual(["/tmp/acme:planning-task"]);
		expect(button?.onKeyDown).toBeUndefined();
	});

	it("renders repository branch facts and last commit context", () => {
		const html = renderToStaticMarkup(
			<StageBoard
				board={buildBoardModel(state)}
				nowSeconds={3_600}
				onOpenIde={() => undefined}
			/>,
		);

		expect(html).toContain(
			'class="stage-repo-name stage-repo-dirty">workbranch',
		);
		expect(html).toContain('class="stage-repo-label">REPO</span>');
		expect(html).toContain('class="stage-repo-label">BRANCH</span>');
		expect(html).toContain('class="stage-repo-label">COMMIT</span>');
		expect(html).toContain(
			'class="stage-repo-branch" title="feat/update-0617">feat/update-0617</span>',
		);
		expect(html).toContain(
			'class="stage-repo-facts">DIRTY 7 FILES · AHEAD 2</span>',
		);
		expect(html).toContain("implement companion activity feed · 1m");
		expect(html).toContain('class="stage-repo-facts">CLEAN · BEHIND 1</span>');
		expect(html).toContain('title="implement companion activity feed"');
	});

	it("does not render dirty zero for a mixed-version legacy CLI payload", () => {
		const html = renderToStaticMarkup(
			<StageCard
				card={legacyDirtyCard}
				nowSeconds={3_600}
				onOpenIde={() => undefined}
			/>,
		);

		expect(html).toContain('class="stage-repo-facts">DIRTY</span>');
		expect(html).not.toContain("DIRTY 0");
	});

	it("keeps task, plan, blocked, progress, and notification metadata", () => {
		const html = renderToStaticMarkup(
			<StageBoard
				board={buildBoardModel(state)}
				nowSeconds={3_600}
				onOpenIde={() => undefined}
			/>,
		);

		expect(html).toContain('class="stage-task-project-label">PROJECT</span>');
		expect(html).toContain('class="stage-task-project-name">acme</span>');
		expect(html).toContain('class="stage-task-blocked">BLOCKED</span>');
		expect(html).toContain('class="stage-task-progress">0/2</span>');
		expect(html).toContain('class="stage-task-notification"');
		expect(html).toContain("+2");
		expect(html).toContain('class="stage-task-plan" title="Generated Plan"');
	});

	it("uses a full-width grouped feed CSS contract", () => {
		const css = readFileSync("src/styles/stage-board.css", "utf8");
		const boardRule = css.match(/\.stage-board\s*\{([^}]*)\}/s);
		const rowRule = css.match(/\.stage-task-row\s*\{([^}]*)\}/s);
		const branchRule = css.match(/\.stage-repo-branch\s*\{([^}]*)\}/s);
		const headingRule = css.match(/\.stage-task-heading\s*\{([^}]*)\}/s);

		expect(boardRule?.[1]).toMatch(/display:\s*grid/);
		expect(boardRule?.[1]).not.toMatch(/grid-template-columns:\s*repeat\(3/);
		expect(css).toMatch(/\.stage-feed\s*\{[^}]*min-width:\s*0/s);
		expect(rowRule?.[1]).toMatch(/position:\s*relative/);
		expect(rowRule?.[1]).toMatch(/min-width:\s*0/);
		expect(headingRule?.[1]).toMatch(/display:\s*grid/);
		expect(branchRule?.[1]).toMatch(/text-overflow:\s*ellipsis/);
		expect(branchRule?.[1]).toMatch(/display:\s*block/);
		expect(css).toMatch(
			/\.stage-repo-row\s*\{[^}]*grid-template-columns:\s*48px minmax\(0, 1fr\)/s,
		);
		expect(css).toMatch(
			/\.stage-lifecycle\s*\{[^}]*background:\s*var\(--surface-1\)[^}]*border:\s*1px solid var\(--line-strong\)[^}]*border-radius:\s*4px/s,
		);
		expect(css).toMatch(/\.stage-lifecycle\s*\{[^}]*padding:\s*6px 8px 7px/s);
		expect(css).toMatch(
			/\.stage-lifecycle-track\s*\{[^}]*grid-template-columns:\s*auto 1fr auto 1fr auto/s,
		);
		expect(css).toMatch(
			/\.stage-lifecycle-stage\s*\{[^}]*color:\s*var\(--muted\)/s,
		);
		expect(css).toMatch(
			/\.stage-lifecycle-node\s*\{[^}]*border-radius:\s*50%/s,
		);
		expect(css).toMatch(
			/\.stage-lifecycle-current \.stage-lifecycle-node\s*\{[^}]*background:\s*var\(--emphasis\)[^}]*box-shadow:\s*0 0 0 3px var\(--emphasis-soft\)/s,
		);
		expect(css).toMatch(
			/\.stage-task-project-label\s*\{[^}]*color:\s*var\(--muted\)/s,
		);
		expect(css).toMatch(/\.stage-repo-label\s*\{[^}]*color:\s*var\(--muted\)/s);
		expect(css).toMatch(
			/\.stage-task-open:focus-visible\s*\{[^}]*outline:\s*2px solid var\(--accent\)[^}]*outline-offset:\s*-2px/s,
		);
		expect(css).toMatch(
			/\.stage-other\s*\{[^}]*border-top:\s*1px solid var\(--line\)/s,
		);
	});

	it("frames the feed as the primary Main surface", () => {
		const css = readFileSync("src/styles/stage-board.css", "utf8");

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
