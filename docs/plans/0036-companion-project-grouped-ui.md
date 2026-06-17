# 0036 Companion Project-Grouped UI and Header Summary Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` or `$plan-execute auto` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. For `.ts`/`.tsx` edits, follow TypeScript guidance and lock semantics with Vitest before markup changes. For visual changes, drive the built app (`pnpm --filter @workbranch/companion tauri dev`) and confirm the popover hierarchy before claiming completion. Scope is the companion presentation layer only — do not touch the CLI, `list --json` contract, Rust ports, activity store, or watcher.

**Goal:** Restructure the Workbranch Companion popover so the scan hierarchy reads **Project → Task → Branch → Plan**: group task rows under a prominent project header, replace the cryptic `⎇ 0` rollup title with an inventory + status summary, reorder each task's body to put branch state above the plan, and reduce the per-task action bar to **IDE | Terminal | Finder**.

**Architecture:** Keep the existing React 18 + TypeScript + plain-CSS architecture and the `DESIGN.md` contract. Reshape the view model in `application/state.ts` from a flat `{ title, rows }` into `{ summary, groups }`, add one small `ui/ProjectGroup.tsx` view part, and adjust `App.tsx`, `ui/TaskRow.tsx`, and `style.css`. No changes to the domain model, ACL/DTO mapping, CLI contract, Rust side, or runtime Tauri command implementation. The presentation-facing `CompanionCommand` union may be narrowed to remove deleted row actions.

**Tech Stack:** Tauri v2, React 18, TypeScript, Vite, Vitest, Biome, plain CSS. No new runtime dependencies.

---

## Product framing

Workbranch Companion is a macOS menu bar popover (420×680, always-on-top) that answers, at a glance, for developers running git-worktree tasks through `workbranch`:

1. Which **project** owns which **tasks**?
2. What task is active/blocked, and how far along?
3. What **branch / dirty** state matters?
4. What **plan** and current step is progressing?
5. What immediate action can I take?

Today the popover flattens every task into one recency-sorted list (`buildMenuModel` in `application/state.ts`), shows the project only as a small faint label *inside* the expanded row (`.project-line`, `TaskRow.tsx:193`), and leads with a cryptic header (`⎇ 0`) that is actually a global status fallback, not a name. The result inverts the intended hierarchy: the task name (13px/620) dominates the project (11px/faint). This plan makes **project** the primary grouping and gives the header a legible job.

## Current repo evidence

- `apps/workbranch-companion/src/application/state.ts:17-48` — `buildMenuModel` flat-maps `projects → tasks`, sorts by `updatedAt`, and computes a `title` string whose idle fallback is the literal `"⎇ 0"` (`⎇` = branch glyph, `0` = nothing active). `MenuModel = { title, rows, errors }`.
- `apps/workbranch-companion/src/App.tsx:133` renders `<h1>{model.title}</h1>`; `:143,:146` consume `model.rows`.
- `apps/workbranch-companion/src/ui/TaskRow.tsx:15-23` defines 7 action kinds (`memoEdit, memoClear, notiClear, finder, ide, terminal, copyPath`); `:76-83` `taskActionsFor` renders all 7; `:192-211` body order is `project-line → current-step → repo-chips → actions → steps`.
- `apps/workbranch-companion/src/style.css:67` styles a bare `header` selector (so any nested `<header>` would inherit it — use a `div` for the group header); `:182-189` `.task-name` 13px/620; `:216-221` `.project-line, footer` faint/11px.
- The action command plumbing (`commandForTaskAction` in `App.tsx:22-46`, the `CompanionCommand` union in `infrastructure/tauriClient.ts:36-43`) currently handles all 7 kinds. Because the decision is full removal rather than hide-only, the TypeScript presentation command surface should be narrowed, while Rust command handling remains untouched.
- **Direct consumers of the model shape that must change with it:** `App.tsx` (`model.title`, `model.rows`) and `tests/acl.test.ts:53-55` (`model.title`, `model.rows[0]?.expanded`). No other file references `buildMenuModel`/`MenuModel`/`.project-line`.
- Window title "Workbranch Companion" already lives in the OS title bar (`src-tauri/tauri.conf.json:16`, `index.html:6`), so the in-content header does not need to repeat the app name.

## Decision gates

- [x] **Header content** (was `⎇ 0`): resolved to **inventory + status summary** — `N projects · M tasks` plus `▶active ⚠blocked 🔔noti` badges (each shown only when > 0). Idle shows inventory with no badges; zero tasks shows `No tasks`. Rationale: an always-on-top HUD benefits most from a glanceable rollup, and the app name is already in the OS title bar, so repeating it is redundant.
- [x] **Project → Task hierarchy:** resolved to a **project group header** (`▌ project · n tasks`) with that project's task rows nested beneath it, instead of a flat list with a faint inline project label. Rationale: expresses Project > Task even when a project has multiple tasks, and removes per-row project duplication.
- [x] **Per-task body order:** resolved to **task name → branch (repo chips) → Plan (current step + steps) → actions**. Branch/dirty state moves above the plan; actions move to the bottom of the row.
- [x] **Action bar:** resolved to **IDE | Terminal | Finder only**, in that order.
- [x] **Memo/clear/noti/copy actions:** resolved to **fully remove from the companion presentation command surface**. Remove the deleted kinds from `TaskActionKind`, labels, aria-label switch, `taskActionsFor`, `commandForTaskAction`, and the `CompanionCommand` union. Consequence: the popover no longer offers memo edit/clear, notification clear, or copy-path actions; notifications remain visible as status only. Rationale: once the product direction is a focused three-action row, leaving hidden plumbing creates ambiguous dead surface and makes future behavior less clear.

## File structure

Modify:
- `DESIGN.md` — update Information Architecture / Content hierarchy / Components / Content voice to the project-grouped structure (keep it the source of truth).
- `apps/workbranch-companion/src/application/state.ts` — reshape `MenuModel` to `{ summary, groups, errors }`; add `MenuSummary` and `ProjectGroup` types; group + sort.
- `apps/workbranch-companion/src/App.tsx` — header inventory+status summary; render `groups.map(<ProjectGroup>)`; empty state on `groups.length === 0`.
- `apps/workbranch-companion/src/ui/TaskRow.tsx` — remove memo/clear/noti/copy action kinds; keep only IDE/Terminal/Finder; reorder body; drop `project` prop and `.project-line`.
- `apps/workbranch-companion/src/style.css` — `.app-summary`/badges, `.project-group`/`.project-group-header`, row nesting, action bar at bottom; remove `.project-line`; ensure project header reads stronger than task name.
- `apps/workbranch-companion/tests/acl.test.ts` — assert the new `summary`/`groups` shape.
- `apps/workbranch-companion/tests/task-row.test.tsx` — assert exactly the three remaining actions in order; drop `project=` prop.
- `apps/workbranch-companion/src/infrastructure/tauriClient.ts` — narrow `CompanionCommand` to the three remaining presentation actions.
- `TASK-WORKBRANCH.md` — task progress updates only.

Create:
- `apps/workbranch-companion/src/ui/ProjectGroup.tsx` — project header + nested `TaskRow`s.
- `apps/workbranch-companion/tests/project-group.test.tsx` — header/count/order coverage.

Do not modify:
- `apps/workbranch-cli/**`, `packages/contract/**`, `apps/workbranch-companion/src-tauri/**`, `apps/workbranch-companion/src/domain/**`, and `apps/workbranch-companion/src/infrastructure/**` except the explicit `tauriClient.ts` `CompanionCommand` type narrowing above.

## Task 1: Update the design contract

**Files:** Modify `DESIGN.md`, `../TASK-WORKBRANCH.md`

- [x] In `DESIGN.md`, update **Information architecture → Content hierarchy** to:
  1. Global inventory + status rollup and refresh.
  2. Project group header (name + task count).
  3. Task name + status dot + progress + notification.
  4. Repo branch/dirty state.
  5. Active plan / current step, then nested plan steps.
  6. Actions (IDE, Terminal, Finder).
- [x] Update **Personas and jobs** to remove memo/notification clearing from current-slice user jobs; notifications remain visible status only.
- [x] Update **Components** to add "project group header" and note the action bar is limited to IDE/Terminal/Finder; update variants/states to remove disabled notification-clear action as a current component state.
- [x] Update **Content voice → Microcopy** to drop `Copy`/`Memo`/`Noti`/`Clear` from the row label vocabulary because those companion row actions are being removed, not hidden.
- [x] Update `Last refreshed:` to the implementation date.
- [x] Verify no placeholders: `rg -n "TBD|TODO|placeholder|fill in" DESIGN.md` → no matches.

## Task 2: Reshape the view model with tests (TDD)

**Files:** Modify `apps/workbranch-companion/tests/acl.test.ts`; Modify `apps/workbranch-companion/src/application/state.ts`

- [x] **Step 1 (RED):** Rewrite the "builds a compact menu rollup" test in `acl.test.ts` to the new shape:

  ```ts
  it("builds a compact menu rollup", () => {
  	const model = buildMenuModel(mapGlobalDocumentToState(document));
  	expect(model.summary.projectCount).toBe(1);
  	expect(model.summary.taskCount).toBe(1);
  	expect(model.summary.active).toBe(1);
  	expect(model.summary.notifications).toBe(2);
  	expect(model.groups[0]?.rows[0]?.expanded).toBe(true);
  });
  ```

  Run `pnpm --filter @workbranch/companion test -- tests/acl.test.ts` → expect FAIL/typecheck error (no `summary`/`groups` yet).

- [x] Add one multi-project view-model test that locks grouping semantics: at least two non-empty projects and one empty project; assert empty projects are filtered, groups sort by latest task `updatedAt`, rows within each group sort by `updatedAt`, and `summary.projectCount` counts rendered non-empty groups.

- [x] **Step 2 (GREEN):** Replace the model + builder in `state.ts`:

  ```ts
  import type { GlobalState, Task } from "../domain/model";
  import { activePlan, taskStatus } from "../domain/model";

  export type TaskRow = {
  	readonly project: string;
  	readonly root: string;
  	readonly task: Task;
  	readonly expanded: boolean;
  };

  export type ProjectGroup = {
  	readonly project: string;
  	readonly root: string;
  	readonly rows: readonly TaskRow[];
  };

  export type MenuSummary = {
  	readonly projectCount: number;
  	readonly taskCount: number;
  	readonly active: number;
  	readonly blocked: number;
  	readonly notifications: number;
  };

  export type MenuModel = {
  	readonly summary: MenuSummary;
  	readonly groups: readonly ProjectGroup[];
  	readonly errors: GlobalState["errors"];
  };

  function latestUpdate(group: ProjectGroup): number {
  	return group.rows.reduce((max, row) => Math.max(max, row.task.updatedAt), 0);
  }

  export function buildMenuModel(state: GlobalState): MenuModel {
  	const groups = state.projects
  		.map((project) => ({
  			project: project.name,
  			root: project.root,
  			rows: project.tasks
  				.map((task) => ({
  					project: project.name,
  					root: project.root,
  					task,
  					expanded: task.notiCount > 0 || taskStatus(task) === "blocked",
  				}))
  				.sort((left, right) => right.task.updatedAt - left.task.updatedAt),
  		}))
  		.filter((group) => group.rows.length > 0)
  		.sort((left, right) => latestUpdate(right) - latestUpdate(left));

  	const rows = groups.flatMap((group) => group.rows);
  	return {
  		summary: {
  			projectCount: groups.length,
  			taskCount: rows.length,
  			active: rows.filter((row) => taskStatus(row.task) === "in-progress").length,
  			blocked: rows.filter((row) => taskStatus(row.task) === "blocked").length,
  			notifications: rows.reduce((count, row) => count + row.task.notiCount, 0),
  		},
  		groups,
  		errors: state.errors,
  	};
  }

  export function currentItem(task: Task): string {
  	return activePlan(task)?.currentItem ?? "";
  }
  ```

  Run `pnpm --filter @workbranch/companion test -- tests/acl.test.ts` → expect PASS.

## Task 3: Add the ProjectGroup view part with tests (TDD)

**Files:** Create `apps/workbranch-companion/tests/project-group.test.tsx`, `apps/workbranch-companion/src/ui/ProjectGroup.tsx`

- [x] **Step 1 (RED):** Add `tests/project-group.test.tsx`:

  ```tsx
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
  		{ project: "acme", root: "/tmp/acme", task: task("feat-a", 20), expanded: false },
  		{ project: "acme", root: "/tmp/acme", task: task("feat-b", 10), expanded: false },
  	],
  };

  describe("ProjectGroup", () => {
  	it("renders the project header with task count above its task rows", () => {
  		const html = renderToStaticMarkup(<ProjectGroup group={group} onAction={() => {}} />);
  		expect(html).toContain("project-group-header");
  		expect(html).toContain("acme");
  		expect(html).toContain("2 tasks");
  		expect(html).toContain("feat-a");
  		expect(html.indexOf("project-group-header")).toBeLessThan(html.indexOf("feat-a"));
  	});
  });
  ```

- [x] **Step 2 (GREEN):** Create `src/ui/ProjectGroup.tsx`:

  ```tsx
  import type { ProjectGroup as ProjectGroupModel } from "../application/state";
  import type { Task } from "../domain/model";
  import { type TaskActionKind, TaskRow } from "./TaskRow";

  type Props = {
  	readonly group: ProjectGroupModel;
  	readonly onAction: (root: string, task: Task, kind: TaskActionKind) => void;
  };

  export function ProjectGroup({ group, onAction }: Props) {
  	const count = group.rows.length;
  	return (
  		<section className="project-group" aria-label={group.project}>
  			<div className="project-group-header">
  				<span className="project-group-name" title={group.project}>
  					{group.project}
  				</span>
  				<span className="project-group-count">
  					{count} {count === 1 ? "task" : "tasks"}
  				</span>
  			</div>
  			{group.rows.map((row) => (
  				<TaskRow
  					key={`${row.root}-${row.task.name}`}
  					root={row.root}
  					task={row.task}
  					expanded={row.expanded}
  					onAction={onAction}
  				/>
  			))}
  		</section>
  	);
  }
  ```

  (Uses a `div`, not `<header>`, to avoid inheriting the global `header` rule in `style.css`.) This will not compile until Task 4 drops `project` from `TaskRow` Props — run the test after Task 4.

## Task 4: TaskRow — three actions + reordered body

**Files:** Modify `apps/workbranch-companion/src/ui/TaskRow.tsx`, `apps/workbranch-companion/tests/task-row.test.tsx`

> Decision resolved: fully remove memo/clear/noti/copy from the companion presentation command surface. Do not leave hidden action kinds or labels behind.

- [x] **Step 1 (RED):** In `task-row.test.tsx`, import `taskActionsFor`, drop `project="workbranch"` from all four `<TaskRow .../>` / `TaskRow({...})` usages, and rewrite the actions test:

  ```ts
  it("exposes only IDE, Terminal, and Finder actions", () => {
  	const html = renderToStaticMarkup(
  		<TaskRow root="/tmp/workbranch" task={nestedChecklistTask} expanded={true} onAction={() => {}} />,
  	);
  	expect(html).toContain('aria-label="open generated-task in IDE"');
  	expect(html).toContain('aria-label="open generated-task in terminal"');
  	expect(html).toContain('aria-label="open generated-task in Finder"');
  	expect(html).not.toContain("edit memo for generated-task");
  	expect(html).not.toContain("clear memo for generated-task");
  	expect(html).not.toContain("clear notifications for generated-task");
  	expect(html).not.toContain("copy path for generated-task");
  	expect(taskActionsFor(nestedChecklistTask).map((action) => action.label)).toEqual([
  		"IDE",
  		"Terminal",
  		"Finder",
  	]);
  });
  ```

  (The other three tests stay valid after the prop drop: the Raycast-summary test still finds `workbranch`/`feat/update-0617` via the repo chip, and the click test still finds the IDE button.)

- [x] **Step 2 (GREEN):** In `TaskRow.tsx`:
  - Replace `TASK_ACTION_KINDS` with `const TASK_ACTION_KINDS = ["ide", "terminal", "finder"] as const;` so `TaskActionKind` is only the three remaining actions.
  - Remove `memoEdit`, `memoClear`, `notiClear`, and `copyPath` from `TASK_ACTION_LABELS` and `actionAriaLabel`.
  - Simplify `taskActionsFor`:

    ```ts
    export function taskActionsFor(task: Task): readonly TaskRowAction[] {
    	return TASK_ACTION_KINDS.map((kind) => ({
    		kind,
    		label: TASK_ACTION_LABELS[kind],
    		ariaLabel: actionAriaLabel(kind, task.name),
    		disabled: false,
    	}));
    }
    ```
  - Add/adjust a direct action-order assertion, e.g. `expect(taskActionsFor(nestedChecklistTask).map((action) => action.label)).toEqual(["IDE", "Terminal", "Finder"]);`.
  - Drop `project` from `Props` and the destructure; delete the `<div className="project-line">{project}</div>` line.
  - Reorder the `.task-detail` children to **repo chips → current step → steps → actions**:

    ```tsx
    <div className="task-detail">
    	<RepoChips repos={task.repos} />
    	{plan && now ? <CurrentStep planTitle={plan.title} currentItem={now} /> : null}
    	{plan ? (
    		<ul className="steps">
    			<StepItems steps={plan.steps} keyPrefix="plan" />
    		</ul>
    	) : null}
    	<div className="task-actions">
    		{actions.map((action) => (
    			<button
    				aria-label={action.ariaLabel}
    				className="task-action"
    				disabled={action.disabled}
    				key={action.kind}
    				onClick={() => onAction(root, task, action.kind)}
    				type="button"
    			>
    				{action.label}
    			</button>
    		))}
    	</div>
    </div>
    ```

- [x] **Step 3:** Run `pnpm --filter @workbranch/companion test -- tests/task-row.test.tsx tests/project-group.test.tsx` → expect PASS.

## Task 5: App shell — header summary + grouped rendering

**Files:** Modify `apps/workbranch-companion/src/App.tsx`, `apps/workbranch-companion/src/infrastructure/tauriClient.ts`

- [x] Update imports: `import { buildMenuModel, type MenuModel, type MenuSummary } from "./application/state";`, add `import { ProjectGroup } from "./ui/ProjectGroup";`, and reduce the TaskRow import to `import type { TaskActionKind } from "./ui/TaskRow";` (App no longer renders `TaskRow` directly; `commandForTaskAction`/`handleTaskAction` still use the type).
- [x] Narrow `commandForTaskAction` to the three remaining `TaskActionKind` cases: `ide`, `terminal`, and `finder`; remove the `window.prompt` memo path and deleted memo/notification/copy cases.
- [x] In `tauriClient.ts`, narrow `CompanionCommand` to `{ kind: "finder" | "ide" | "terminal"; task: string }` variants only. Do not touch Rust command handling in this slice.
- [x] Add an inline header summary helper:

  ```tsx
  function plural(count: number, word: string): string {
  	return count === 1 ? word : `${word}s`;
  }

  function AppSummary({ summary }: { readonly summary: MenuSummary }) {
  	const { projectCount, taskCount, active, blocked, notifications } = summary;
  	return (
  		<div className="app-summary">
  			<span className="app-inventory">
  				{taskCount === 0
  					? "No tasks"
  					: `${projectCount} ${plural(projectCount, "project")} · ${taskCount} ${plural(taskCount, "task")}`}
  			</span>
  			<span className="app-badges">
  				{active > 0 ? (
  					<span className="badge badge-active" title={`${active} in progress`} aria-label={`${active} in progress`}>▶ {active}</span>
  				) : null}
  				{blocked > 0 ? (
  					<span className="badge badge-blocked" title={`${blocked} blocked`} aria-label={`${blocked} blocked`}>⚠ {blocked}</span>
  				) : null}
  				{notifications > 0 ? (
  					<span className="badge badge-noti" title={`${notifications} notifications`} aria-label={`${notifications} notifications`}>🔔 {notifications}</span>
  				) : null}
  			</span>
  		</div>
  	);
  }
  ```

- [x] Replace the header and body JSX:

  ```tsx
  <header>
  	<AppSummary summary={model.summary} />
  	<button type="button" onClick={() => void refresh()} aria-label="refresh">↻</button>
  </header>
  <section>
  	{model.groups.length === 0 ? (
  		<p className="empty">No workbranch tasks registered.</p>
  	) : null}
  	{model.groups.map((group) => (
  		<ProjectGroup
  			key={group.root}
  			group={group}
  			onAction={(root, task, kind) => void handleTaskAction(root, task, kind)}
  		/>
  	))}
  </section>
  ```

## Task 6: CSS — header summary, project grouping, row order

**Files:** Modify `apps/workbranch-companion/src/style.css`

- [x] Change the `.project-line, footer { ... }` rule (`:216`) to `footer { ... }` only (delete `.project-line`).
- [x] Optionally reduce `.task-name` `font-size` from `13px` to `12px` so the project header reads as the larger element.
- [x] Append:

  ```css
  .app-summary {
  	align-items: baseline;
  	display: flex;
  	flex-wrap: wrap;
  	gap: 8px;
  	min-width: 0;
  }

  .app-inventory {
  	color: var(--muted);
  	font-size: 12px;
  	font-weight: 600;
  }

  .app-badges {
  	display: inline-flex;
  	gap: 6px;
  }

  .badge {
  	border: 1px solid var(--line);
  	border-radius: 999px;
  	font-size: 11px;
  	font-weight: 600;
  	line-height: 1;
  	padding: 3px 7px;
  }

  .badge-active {
  	background: var(--accent-soft);
  	border-color: rgba(124, 92, 255, 0.3);
  	color: var(--accent);
  }

  .badge-blocked {
  	background: rgba(255, 95, 112, 0.14);
  	border-color: rgba(255, 95, 112, 0.28);
  	color: var(--blocked);
  }

  .badge-noti {
  	background: rgba(245, 184, 75, 0.12);
  	border-color: rgba(245, 184, 75, 0.22);
  	color: var(--notify);
  }

  .project-group {
  	margin-bottom: 14px;
  }

  .project-group-header {
  	align-items: baseline;
  	border-left: 2px solid var(--accent);
  	display: flex;
  	gap: 8px;
  	margin-bottom: 8px;
  	padding-left: 8px;
  }

  .project-group-name {
  	color: var(--text);
  	font-size: 13px;
  	font-weight: 700;
  	overflow: hidden;
  	text-overflow: ellipsis;
  	white-space: nowrap;
  }

  .project-group-count {
  	color: var(--faint);
  	font-size: 11px;
  	white-space: nowrap;
  }

  .project-group .task {
  	margin-left: 8px;
  }
  ```

## Task 7: Verification

**Files:** Update `docs/plans/0036-companion-project-grouped-ui.md` (evidence), `../TASK-WORKBRANCH.md`

- [x] Automated (from repo root):

  ```bash
  pnpm --filter @workbranch/companion test
  pnpm --filter @workbranch/companion typecheck
  pnpm --filter @workbranch/companion lint
  pnpm --filter @workbranch/companion build
  git diff --check
  ```

  Expected: Vitest green (incl. new `project-group.test.tsx` and updated `acl`/`task-row`), TypeScript clean, Biome exit 0 (pre-existing `parseContract.ts` info diagnostics may print but no new ones from changed files), `tsc && vite build` succeeds, whitespace clean.

- [ ] Visual gate:

  ```bash
  pnpm --filter @workbranch/companion tauri dev
  ```

  Manual checks:
  - Header shows `N projects · M tasks` + status badges (no `⎇ 0`); idle shows inventory only; zero tasks shows `No tasks`.
  - Tasks are grouped under a project header that reads as the primary level; task rows are visibly subordinate (indent + accent bar).
  - Within a row, order is task name → branch chips → plan/current step → steps → actions.
  - Exactly three actions in order **IDE | Terminal | Finder**.
  - Narrow-width wrapping and keyboard focus rings still work.

  If this session cannot observe the rendered menu bar, record the gap and require a human visual check before release.

- [x] Append a `## 구현 결과` section (files changed, tests pass/fail, visual result or gap, remaining risk) and set `TASK-WORKBRANCH.md` status to `done` (automated + visual confirmed) or `review` (code complete, visual pending).

## Acceptance criteria

- The popover groups tasks under a project header (`project · n tasks`); the project level reads as primary and task rows as subordinate.
- The header shows inventory + status (`N projects · M tasks` + `▶/⚠/🔔` badges when > 0), idle shows inventory only, zero tasks shows `No tasks`; the `⎇ 0` fallback is gone.
- Each task body is ordered task name → branch → plan (current step + steps) → actions.
- Each task row shows exactly IDE, Terminal, Finder, in that order; memo edit/clear, notification clear, and copy-path are removed from the companion presentation command surface.
- `buildMenuModel` returns `{ summary, groups, errors }`; `acl.test.ts`, `task-row.test.tsx`, and new `project-group.test.tsx` pass; typecheck, lint, build, and `git diff --check` pass.
- CLI contract, domain model, ACL mapping, Rust ports, and runtime Tauri command implementation are unchanged; only the presentation-facing `CompanionCommand` union is narrowed to match the remaining UI actions.

## Non-goals

- Do not change `workbranch list --json` / `list --global --json` schemaVersion 1, the domain model, or `infrastructure/acl.ts` mapping.
- Do not add task lifecycle mutations or new UI dependencies (Tailwind/shadcn/Radix).
- Do not add replacement memo/notification/copy UI in this slice; deleted row actions are a deliberate product cut, not a relocation.
- Do not modify the Rust side, activity store, or watcher.
- Do not add settings/preferences, launch-at-login, font selection, or color theme selection in this slice; those are split into `docs/plans/0037-companion-settings-cli-theme.md`.

## Self-review checklist for this plan

- [x] Resolves the header, hierarchy, body-order, and action decisions from the design Q&A.
- [x] Resolves the memo/noti/copy decision as fully removed from the companion presentation command surface.
- [x] Locks model + new component semantics with tests before markup (TDD).
- [x] Lists exact files, code, and the model consumers that must change together (`App.tsx`, `acl.test.ts`).
- [x] Keeps CLI/contract/domain/Rust scope unchanged.
- [x] Includes a visual/manual gate for a UI change.
- [x] No TBD/TODO placeholders.
- [x] Settings/preferences and CLI-like theme work split to 0037 so this plan stays focused on grouping/action hierarchy.

## 구현 결과

- 변경 파일: `DESIGN.md`, companion `state.ts`/`App.tsx`/`TaskRow.tsx`/`ProjectGroup.tsx`/`style.css`/`tauriClient.ts`, `acl.test.ts`, `task-row.test.tsx`, `project-group.test.tsx`, `../TASK-WORKBRANCH.md`.
- 구현 완료: view model이 `{ summary, groups, errors }`로 변경되었고, 빈 프로젝트 필터링/프로젝트 최신 task 기준 정렬/task row 최신순 정렬을 테스트로 잠갔다.
- 구현 완료: popover header는 inventory + status badge를 렌더링하고, body는 `ProjectGroup` 아래 `TaskRow`를 중첩 렌더링한다.
- 구현 완료: companion presentation action surface는 `IDE | Terminal | Finder`로 축소했고, `memoEdit`/`memoClear`/`notiClear`/`copyPath` 및 TS `CompanionCommand` union의 삭제 대상 variants를 제거했다. Rust runtime command implementation은 변경하지 않았다.
- 자동 검증 통과:
  - `pnpm --filter @workbranch/companion test` → 7 files / 20 tests passed.
  - `pnpm --filter @workbranch/companion typecheck` → passed.
  - `pnpm --filter @workbranch/companion lint` → exit 0; 기존 `parseContract.ts` `useLiteralKeys` info diagnostics 출력됨.
  - `pnpm --filter @workbranch/companion build` → `tsc && vite build` passed.
  - `git diff --check` → passed.
  - manual markdown trailing-whitespace check for `../TASK-WORKBRANCH.md`, `0036`, `0037` → passed.
- Visual gate update: installed Rust 1.95.0 and set a local rustup override for this checkout; `pnpm --filter @workbranch/companion tauri dev` built successfully and ran `target/debug/workbranch-companion`. Native menu-bar popover inspection is still not directly observed in this agent session because macOS Assistive Access and screencapture are unavailable. As partial visual evidence, Playwright drove the Vite surface with Tauri IPC mocks and verified inventory/status badges, project grouping, branch-before-plan order, IDE|Terminal|Finder-only actions, and no page errors. Screenshot: `/tmp/workbranch-companion-qa/grouped-ui.png`.
- Remaining risk: native tray popover visual QA is not directly observed; keep task status at `review` until it is manually inspected in a GUI session with accessibility/screen capture available.
