# 0034 Companion Linear-Inspired UI Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` or `$plan-execute auto` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. For `.ts`/`.tsx` edits, use `omo:programming` TypeScript guidance before editing. For visual changes, use the `design` skill and drive the built app through a browser/app screenshot before claiming completion.

**Goal:** Refresh Workbranch Companion into a simple Linear-inspired menu bar task cockpit that shows each task's active plan, current step, progress, repo state, and available actions with strong scan hierarchy.

**Architecture:** Keep the existing React + TypeScript + plain CSS architecture. Add a repo-root `DESIGN.md` as the durable UI contract, then refactor only the companion presentation layer (`TaskRow.tsx`, `App.tsx`, `style.css`) around small semantic view parts. Do not change the CLI, `list --json` contract, Rust ports, activity storage, or watcher behavior.

**Tech Stack:** Tauri v2, React 18, TypeScript, Vite, Vitest, Biome, plain CSS. No Tailwind, Radix, or shadcn in v1; revisit only if this plan cannot satisfy accessibility or interaction needs with existing primitives.

---

## Product framing

Workbranch Companion is not a dashboard or landing page. It is a macOS menu bar utility for developers using git worktrees through `workbranch`. Its job is to answer, in a narrow popover:

1. What task is active or blocked?
2. What plan and step is currently progressing?
3. What repo/branch/dirty state matters?
4. What immediate action can I take?

The chosen visual direction is **Linear-inspired compact issue tracker**:

- compact dark surfaces, crisp typography, low-noise borders;
- purple/indigo accent for active work, red for blocked, green for done;
- row-first information hierarchy, not card-heavy dashboard layout;
- subtle depth through background steps and hairline borders;
- motion limited to press/reveal feedback, not decorative animation.

## Non-goals

- Do not add task lifecycle mutations (`add`, `done`, `land`, `push`, `pull`, `finalize`) to companion.
- Do not change `workbranch list --json` / `list --global --json` schemaVersion 1.
- Do not introduce Tailwind/shadcn/Radix in this v1 UI refresh.
- Do not create a wide dashboard, marketing hero, large cards, or heavy gradients.
- Do not duplicate status text in both task header and status line; keep one compact status line.

## Decision gates

- [x] **Primary design reference:** Linear-inspired compact status hierarchy.
- [x] **UI library:** no shadcn/Tailwind in v1. Current companion has no Tailwind/Radix dependencies and the required UI can be achieved with semantic React and plain CSS.
- [x] **Design source artifact location:** resolved A — create one repo-root `DESIGN.md`. Do not create an app-local `apps/workbranch-companion/DESIGN.md`, and do not keep multiple imported design docs active.
- [x] **Data contract:** UI consumes existing domain `Task`, `Plan`, `Step`, `Repo`; no DTO or CLI contract changes.
- [x] **Conditional TaskRow split path:** resolved A — if `TaskRow.tsx` exceeds 250 pure LOC, split helper view parts into `apps/workbranch-companion/src/ui/taskRowParts.tsx`, not `TaskRowParts.tsx`.

Decision 1 result: `DESIGN.md` lives at the repository root so future UI/UX/frontend work has one discoverable design contract. Companion-local design docs are rejected for v1 because they reduce agent discoverability and create avoidable source-of-truth ambiguity.
Decision 2 result: conditional helper extraction uses `apps/workbranch-companion/src/ui/taskRowParts.tsx`. This keeps the extracted module private-ish and role-based rather than implying a new public React component surface.

## File structure

Create:
- `DESIGN.md` — repo-root canonical design contract for Workbranch Companion. Resolved by Decision 1: use `workbranch/DESIGN.md`, not `apps/workbranch-companion/DESIGN.md`.

Modify:
- `apps/workbranch-companion/src/App.tsx` — app shell copy and structural class names only; keep monitor/action logic intact.
- `apps/workbranch-companion/src/ui/TaskRow.tsx` — split rendering into focused private components inside the same file unless it exceeds 250 pure LOC; preserve public `TaskRow`, `TaskActionKind`, `taskActionsFor` API.
- `apps/workbranch-companion/src/style.css` — Linear-inspired tokens, layout, status colors, action buttons, step tree, responsive/narrow popover behavior.
- `apps/workbranch-companion/tests/task-row.test.tsx` — static markup tests for plan/status/repo/action semantics.
- `TASK-WORKBRANCH.md` — task progress updates only.

Do not modify:
- `apps/workbranch-cli/**`
- `packages/contract/**`
- `apps/workbranch-companion/src-tauri/**`
- `apps/workbranch-companion/src/infrastructure/**` unless a test reveals a UI-only bug cannot be handled in presentation code.

## Task 1: Establish repo design contract

**Files:**
- Create: `DESIGN.md` at repo root
- Modify: `TASK-WORKBRANCH.md`

- [x] **Step 1: Write `DESIGN.md` from the confirmed Linear direction**

Create `DESIGN.md` with this content:

```markdown
# Design

## Source of truth
- Status: Active
- Last refreshed: 2026-06-17
- Primary product surfaces: Workbranch Companion macOS menu bar popover.
- Evidence reviewed:
  - `docs/plans/0032-companion-tauri-react-rewrite.md`
  - `docs/plans/0033-companion-responsiveness-nonblocking-commands-and-watch-scope.md`
  - `apps/workbranch-companion/src/App.tsx`
  - `apps/workbranch-companion/src/ui/TaskRow.tsx`
  - `apps/workbranch-companion/src/style.css`

## Brand
- Personality: precise, quiet, developer-native, task-focused.
- Trust signals: fast refresh, clear current step, visible repo dirty/branch state, restrained UI chrome.
- Avoid: marketing hero layouts, oversized cards, heavy gradients, generic shadcn dashboard look, decorative animation.

## Product goals
- Goals:
  - Show active worktree tasks and their active plan status at a glance.
  - Make the current plan step more prominent than secondary metadata.
  - Keep repo branch/dirty state visible without competing with task progress.
  - Keep actions discoverable but visually secondary.
- Non-goals:
  - Task lifecycle mutation UI.
  - Full project dashboard or report view redesign.
  - New UI dependency stack.
- Success signals:
  - A user can identify active/blocked work in under three seconds.
  - A user can find the current step without expanding every row.
  - The popover remains readable at approximately 360px width.

## Personas and jobs
- Primary personas: developers using `workbranch` task workspaces and AI agents.
- User jobs:
  - Check what is currently in progress.
  - See which repo/branch is dirty.
  - Open task in IDE/terminal/Finder.
  - Clear memo/notifications when no longer needed.
- Key contexts of use: quick menu bar glance while coding, before switching tasks, during AI-agent execution.

## Information architecture
- Primary navigation: single popover list sorted by recent update.
- Core screens: task list, expanded task details, error rows.
- Content hierarchy:
  1. Global rollup title and refresh.
  2. Task name + status dot + progress.
  3. Active plan/current step.
  4. Repo branch/dirty state.
  5. Actions.
  6. Nested plan steps.

## Design principles
- Principle 1: Status is a rail, not a paragraph. Use compact dots, counts, and labels.
- Principle 2: Current work beats historical detail. The active/current step is always above the full checklist.
- Principle 3: Developer metadata should be monospace and subdued until dirty/blocked.
- Tradeoffs: density is preferred over spaciousness, but tap/click targets remain at least 32px high where practical.

## Visual language
- Color: near-black neutral surfaces with indigo/purple active accents, red blocked accent, green done accent, amber notification accent.
- Typography: system UI for labels; monospace only for repo/branch/path-like metadata.
- Spacing/layout rhythm: compact 8px grid, row-first grouping, no large cards.
- Shape/radius/elevation: one fixed radius scale (`6px` controls, `10px` rows, `14px` shell); depth from background steps and hairline borders.
- Motion: 120ms press/reveal feedback only; respect reduced motion.
- Imagery/iconography: text glyphs and status dots only; no decorative illustration.

## Components
- Existing components to reuse: `TaskRow`, action buttons, native `details/summary` disclosure.
- New/changed components:
  - task summary line,
  - current-step strip,
  - repo chips,
  - action bar,
  - nested step tree.
- Variants and states: todo, planning, in-progress, review, blocked, done, notification present, dirty repo, disabled action.
- Token/component ownership: `style.css` owns CSS custom properties and component classes.

## Accessibility
- Target standard: keyboard-operable popover controls and readable contrast.
- Keyboard/focus behavior: buttons and `summary` expose clear focus rings.
- Contrast/readability: status text and current step must pass practical dark-mode contrast; disabled action may be muted but legible.
- Screen-reader semantics: preserve button `aria-label`s; use meaningful text labels for status where visible.
- Reduced motion and sensory considerations: disable transform transitions under `prefers-reduced-motion: reduce`.

## Responsive behavior
- Supported breakpoints/devices: narrow menu popover around 360-460px width.
- Layout adaptations: actions wrap; repo chips wrap; long task/step names truncate with accessible full text via `title`.
- Touch/hover differences: hover is enhancement only; core state is visible without hover.

## Interaction states
- Loading: footer/status line reports refresh status.
- Empty: concise empty message with setup hint.
- Error: root-scoped error row with red accent.
- Success: status footer says `Updated` / `Action complete`.
- Disabled: disabled action has muted text and no press transform.
- Offline/slow network: not applicable; CLI/local filesystem driven.

## Content voice
- Tone: terse, operational, developer-native.
- Terminology: task, plan, step, repo, branch, dirty.
- Microcopy rules: prefer short labels (`IDE`, `Terminal`, `Copy`) over sentences; avoid emoji except where already part of compact rollup.

## Implementation constraints
- Framework/styling system: React 18 + plain CSS; no Tailwind/shadcn in this refresh.
- Design-token constraints: CSS custom properties in `style.css`.
- Performance constraints: no extra runtime package; no animation loops; preserve 0033 responsiveness fixes.
- Compatibility constraints: no CLI/contract/Rust port changes.
- Test/screenshot expectations: Vitest static markup tests plus `pnpm --filter @workbranch/companion tauri build`; run a browser/app screenshot review before final handoff.

## Open questions
- [ ] Whether a later v2 should add shadcn/Radix primitives after the plain CSS refresh proves the needed component gaps.
```

- [x] **Step 2: Verify `DESIGN.md` has no placeholders**

Run:

```bash
rg -n "TBD|TODO|placeholder|fill in" DESIGN.md
```

Expected: no matches.

- [x] **Step 3: Update task brief**

Mark the design contract step complete in `../TASK-WORKBRANCH.md` if executing from `workbranch/`, or `TASK-WORKBRANCH.md` if executing from the task root.

Task 1 evidence: `DESIGN.md` created at repo root; `rg -n "TBD|TODO|placeholder|fill in" DESIGN.md` returned no matches.

## Task 2: Lock TaskRow semantic rendering with tests

**Files:**
- Modify: `apps/workbranch-companion/tests/task-row.test.tsx`
- Read: `apps/workbranch-companion/src/ui/TaskRow.tsx`

- [x] **Step 1: Add a richer fixture with repos and a blocked variant**

Add this fixture near `nestedChecklistTask`:

```ts
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
						{ text: "Write design contract", checked: true, depth: 1, children: [] },
						{ text: "Review screenshot", checked: false, depth: 1, children: [] },
					],
				},
			],
		},
	],
};
```

- [x] **Step 2: Write failing semantic markup test**

Add this test before the action tests:

```ts
it("renders a Linear-style task summary with current step and repo state", () => {
	const html = renderToStaticMarkup(
		<TaskRow
			project="workbranch"
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
```

- [x] **Step 3: Run the test and confirm red**

Run:

```bash
pnpm --filter @workbranch/companion test -- tests/task-row.test.tsx
```

Expected: FAIL because `task-status-rail` and `repo-chip repo-dirty` do not exist yet.

Task 2 evidence: `pnpm --filter @workbranch/companion test -- tests/task-row.test.tsx` failed as expected because current markup does not contain `task-status-rail`.

## Task 3: Refactor TaskRow into Linear-style view parts

**Files:**
- Modify: `apps/workbranch-companion/src/ui/TaskRow.tsx`
- Modify: `apps/workbranch-companion/tests/task-row.test.tsx`

- [x] **Step 1: Replace status icon map with status metadata**

In `TaskRow.tsx`, replace `STATUS_ICON` with:

```ts
const STATUS_META = {
	todo: { icon: "·", label: "Todo" },
	planning: { icon: "○", label: "Planning" },
	"in-progress": { icon: "●", label: "In progress" },
	review: { icon: "◐", label: "Review" },
	blocked: { icon: "!", label: "Blocked" },
	done: { icon: "✓", label: "Done" },
} as const;
```

- [x] **Step 2: Shorten action labels**

Change `TASK_ACTION_LABELS` to:

```ts
const TASK_ACTION_LABELS: Record<TaskActionKind, string> = {
	memoEdit: "Memo",
	memoClear: "Clear",
	notiClear: "Noti",
	finder: "Finder",
	ide: "IDE",
	terminal: "Terminal",
	copyPath: "Copy",
} as const;
```

- [x] **Step 3: Add focused private view helpers**

Add these helper components above `TaskRow`:

```tsx
type TaskSummaryProps = {
	readonly task: Task;
	readonly status: ReturnType<typeof taskStatus>;
	readonly progress: ReturnType<typeof taskProgress>;
};

function TaskSummary({ task, status, progress }: TaskSummaryProps) {
	const meta = STATUS_META[status];
	return (
		<div className="task-summary-line">
			<span className="task-status-rail" aria-label={meta.label} title={meta.label}>
				{meta.icon}
			</span>
			<span className="task-name" title={task.name}>{task.name}</span>
			{progress.total > 0 ? (
				<span className="progress-pill">{progress.done}/{progress.total}</span>
			) : null}
			{task.notiCount > 0 ? (
				<span className="noti-pill" title={`${task.notiCount} notifications`}>+{task.notiCount}</span>
			) : null}
		</div>
	);
}

type CurrentStepProps = {
	readonly planTitle: string;
	readonly currentItem: string;
};

function CurrentStep({ planTitle, currentItem }: CurrentStepProps) {
	return (
		<div className="current-step-strip">
			<span className="plan-title" title={planTitle}>{planTitle}</span>
			<span className="current-step" title={currentItem}>{currentItem}</span>
		</div>
	);
}

type RepoChipsProps = {
	readonly repos: Task["repos"];
};

function RepoChips({ repos }: RepoChipsProps) {
	if (repos.length === 0) {
		return null;
	}
	return (
		<div className="repo-chips" aria-label="repositories">
			{repos.map((repo) => (
				<span
					className={`repo-chip${repo.dirty ? " repo-dirty" : ""}`}
					key={repo.name}
					title={`${repo.name} ${repo.branch}${repo.dirty ? " dirty" : " clean"}`}
				>
					<span className="repo-name">{repo.name}</span>
					<span className="repo-branch">{repo.branch}</span>
					{repo.dirty ? <span className="repo-dot" aria-label="dirty">●</span> : null}
				</span>
			))}
		</div>
	);
}
```

- [x] **Step 4: Rewrite `TaskRow` markup using the helpers**

Replace the return body of `TaskRow` with:

```tsx
return (
	<details className={`task task-${status}`} open={expanded}>
		<summary>
			<TaskSummary task={task} status={status} progress={progress} />
		</summary>
		<div className="task-detail">
			<div className="project-line">{project}</div>
			{plan && now ? (
				<CurrentStep planTitle={plan.title} currentItem={now} />
			) : null}
			<RepoChips repos={task.repos} />
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
			{plan ? (
				<ul className="steps">
					<StepItems steps={plan.steps} keyPrefix="plan" />
				</ul>
			) : null}
		</div>
	</details>
);
```

- [x] **Step 5: Run TaskRow tests and confirm green**

Run:

```bash
pnpm --filter @workbranch/companion test -- tests/task-row.test.tsx
```

Expected: all `TaskRow` tests pass.

- [x] **Step 6: Measure pure LOC**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
for f in ['apps/workbranch-companion/src/ui/TaskRow.tsx']:
    count = 0
    for line in Path(f).read_text().splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith('//'):
            count += 1
    print(f'{f}: {count}')
PY
```

Expected: `TaskRow.tsx` is at or below 250 pure LOC. If it exceeds 250, split helpers into the resolved path `apps/workbranch-companion/src/ui/taskRowParts.tsx` before continuing.

Task 3 evidence: `pnpm --filter @workbranch/companion test -- tests/task-row.test.tsx` passed (6 files / 16 tests reported); `TaskRow.tsx` measured 202 pure LOC, so no `taskRowParts.tsx` split was needed.

## Task 4: Apply Linear-inspired CSS tokens and layout

**Files:**
- Modify: `apps/workbranch-companion/src/style.css`
- Test: `apps/workbranch-companion/tests/task-row.test.tsx`

- [x] **Step 1: Replace global tokens and shell styles**

Replace the top of `style.css` through the `h1` rule with:

```css
:root {
	color: #eef0f8;
	background: #0d0e12;
	font-family:
		Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont,
		"Segoe UI", sans-serif;
	--surface-0: #0d0e12;
	--surface-1: #12131a;
	--surface-2: #181a23;
	--surface-3: #202331;
	--line: rgba(255, 255, 255, 0.08);
	--line-strong: rgba(255, 255, 255, 0.14);
	--text: #eef0f8;
	--muted: #9ca3b5;
	--faint: #697084;
	--accent: #7c5cff;
	--accent-soft: rgba(124, 92, 255, 0.18);
	--blocked: #ff5f70;
	--review: #c084fc;
	--done: #62d083;
	--notify: #f5b84b;
	--radius-row: 10px;
	--radius-shell: 14px;
}

* {
	box-sizing: border-box;
}

body {
	margin: 0;
	min-width: 360px;
	background: var(--surface-0);
}

main {
	background: linear-gradient(180deg, #11131a 0%, var(--surface-0) 100%);
	min-height: 100vh;
	padding: 12px;
}

header {
	align-items: center;
	display: flex;
	gap: 10px;
	justify-content: space-between;
	margin-bottom: 10px;
}

h1 {
	color: var(--text);
	font-size: 13px;
	font-weight: 650;
	letter-spacing: 0.01em;
	line-height: 1;
	margin: 0;
}
```

- [x] **Step 2: Replace button and task row styles**

Replace the existing `button`, `.task`, `summary`, status, metadata, action, and step rules with:

```css
button {
	appearance: none;
	background: var(--surface-2);
	border: 1px solid var(--line);
	border-radius: 7px;
	color: var(--text);
	font: inherit;
	min-height: 32px;
	padding: 6px 10px;
}

button:hover:not(:disabled) {
	background: var(--surface-3);
	border-color: var(--line-strong);
}

button:focus-visible,
summary:focus-visible {
	outline: 2px solid var(--accent);
	outline-offset: 2px;
}

.task {
	background: #141620;
	border: 1px solid var(--line);
	border-radius: var(--radius-row);
	box-shadow: 0 1px 0 rgba(255, 255, 255, 0.03) inset;
	margin-bottom: 8px;
	overflow: hidden;
}

summary {
	cursor: default;
	list-style: none;
	padding: 9px 10px;
}

summary::-webkit-details-marker {
	display: none;
}

.task-summary-line {
	align-items: center;
	display: grid;
	gap: 8px;
	grid-template-columns: 16px minmax(0, 1fr) auto auto;
}

.task-status-rail {
	align-items: center;
	background: var(--surface-2);
	border-radius: 999px;
	color: var(--muted);
	display: inline-flex;
	font-size: 11px;
	height: 16px;
	justify-content: center;
	width: 16px;
}

.task-in-progress .task-status-rail {
	background: var(--accent-soft);
	color: var(--accent);
}

.task-blocked .task-status-rail {
	background: rgba(255, 95, 112, 0.16);
	color: var(--blocked);
}

.task-review .task-status-rail {
	background: rgba(192, 132, 252, 0.15);
	color: var(--review);
}

.task-done .task-status-rail {
	background: rgba(98, 208, 131, 0.14);
	color: var(--done);
}

.task-name {
	color: var(--text);
	font-size: 13px;
	font-weight: 620;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.progress-pill,
.noti-pill {
	border: 1px solid var(--line);
	border-radius: 999px;
	font-size: 11px;
	font-weight: 600;
	line-height: 1;
	padding: 4px 7px;
}

.progress-pill {
	color: var(--muted);
}

.noti-pill {
	background: rgba(245, 184, 75, 0.12);
	border-color: rgba(245, 184, 75, 0.22);
	color: var(--notify);
}

.task-detail {
	border-top: 1px solid var(--line);
	padding: 9px 10px 10px;
}

.project-line,
footer {
	color: var(--faint);
	font-size: 11px;
	margin-top: 6px;
}

.current-step-strip {
	background: var(--surface-2);
	border: 1px solid var(--line);
	border-radius: 8px;
	display: grid;
	gap: 4px;
	margin-top: 8px;
	padding: 8px;
}

.plan-title {
	color: var(--faint);
	font-size: 10px;
	letter-spacing: 0.04em;
	text-transform: uppercase;
}

.current-step {
	color: var(--text);
	font-size: 12px;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.repo-chips {
	display: flex;
	flex-wrap: wrap;
	gap: 6px;
	margin-top: 8px;
}

.repo-chip {
	align-items: center;
	background: rgba(255, 255, 255, 0.035);
	border: 1px solid var(--line);
	border-radius: 7px;
	color: var(--muted);
	display: inline-flex;
	font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
	font-size: 11px;
	gap: 5px;
	max-width: 100%;
	padding: 4px 6px;
}

.repo-dirty {
	border-color: rgba(245, 184, 75, 0.26);
	color: #f3d18a;
}

.repo-name,
.repo-branch {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.repo-branch {
	color: var(--faint);
}

.repo-dot {
	color: var(--notify);
	font-size: 9px;
}

.steps {
	border-left: 1px solid var(--line);
	color: var(--muted);
	font-size: 12px;
	line-height: 1.45;
	list-style: none;
	margin: 9px 0 0 7px;
	padding: 0 0 0 8px;
}

.steps li {
	padding: 2px 0;
}

.error {
	background: rgba(255, 95, 112, 0.1);
	border: 1px solid rgba(255, 95, 112, 0.25);
	border-radius: 8px;
	color: #ffb3bd;
	font-size: 12px;
	padding: 8px;
}

.empty {
	border: 1px dashed var(--line-strong);
	border-radius: var(--radius-row);
	color: var(--muted);
	font-size: 12px;
	padding: 14px;
	text-align: center;
}

.task-actions {
	display: flex;
	flex-wrap: wrap;
	gap: 6px;
	margin-top: 9px;
}

.task-action {
	color: var(--muted);
	font-size: 11px;
	min-height: 32px;
	touch-action: manipulation;
	transition-duration: 120ms;
	transition-property: background-color, border-color, color, transform;
	transition-timing-function: cubic-bezier(0.16, 1, 0.3, 1);
}

.task-action:active:not(:disabled) {
	transform: scale(0.96);
}

.task-action:disabled {
	color: var(--faint);
	cursor: not-allowed;
	opacity: 0.55;
}

@media (prefers-reduced-motion: reduce) {
	.task-action {
		transition: none;
	}

	.task-action:active:not(:disabled) {
		transform: none;
	}
}
```

- [x] **Step 3: Run markup tests**

Run:

```bash
pnpm --filter @workbranch/companion test -- tests/task-row.test.tsx
```

Expected: pass. CSS changes should not alter static semantic tests.

- [x] **Step 4: Run targeted Biome check**

Run:

```bash
pnpm --filter @workbranch/companion exec biome check src/App.tsx src/ui/TaskRow.tsx tests/task-row.test.tsx
```

Expected: no errors.

Task 4 evidence: Linear-inspired CSS tokens/layout applied. `pnpm --filter @workbranch/companion test -- tests/task-row.test.tsx` passed; targeted `biome check src/App.tsx src/ui/TaskRow.tsx tests/task-row.test.tsx` passed after converting repo chips to semantic `ul/li`.

## Task 5: Polish app shell copy and status line

**Files:**
- Modify: `apps/workbranch-companion/src/App.tsx`
- Modify: `apps/workbranch-companion/src/application/state.ts` only if the title rollup needs text shape adjustment.
- Test: `apps/workbranch-companion/tests/acl.test.ts` only if `buildMenuModel` title changes.

- [x] **Step 1: Keep header compact**

In `App.tsx`, keep the existing header structure but ensure the refresh button remains accessible:

```tsx
<header>
	<h1>{model.title}</h1>
	<button type="button" onClick={() => void refresh()} aria-label="refresh">
		↻
	</button>
</header>
```

No logic change is required if this block already matches.

- [x] **Step 2: Improve empty copy**

Change the empty message from:

```tsx
<p className="empty">No workbranch tasks configured.</p>
```

to:

```tsx
<p className="empty">No workbranch tasks registered.</p>
```

- [x] **Step 3: Run typecheck and tests**

Run:

```bash
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion test -- tests/acl.test.ts tests/task-row.test.tsx
```

Expected: both pass. If `buildMenuModel` title is changed, update `acl.test.ts` expected title explicitly; do not remove the assertion.

Task 5 evidence: Empty copy changed to `No workbranch tasks registered.`; header logic unchanged. `pnpm --filter @workbranch/companion typecheck` and `pnpm --filter @workbranch/companion test -- tests/acl.test.ts tests/task-row.test.tsx` passed.

## Task 6: Visual smoke and accessibility pass

**Files:**
- No source files expected unless visual smoke reveals issues.
- Update: `../TASK-WORKBRANCH.md` with evidence.

- [x] **Step 1: Build the companion**

Run:

```bash
pnpm --filter @workbranch/companion tauri build
```

Expected: release binary and macOS app bundle build successfully.

- [x] **Step 2: Run isolated release smoke**

Run:

```bash
APP_BIN="apps/workbranch-companion/src-tauri/target/release/workbranch-companion"
TMP_XDG=$(mktemp -d)
LOG=$(mktemp)
XDG_CONFIG_HOME="$TMP_XDG" "$APP_BIN" >"$LOG" 2>&1 &
pid=$!
sleep 5
kill -0 "$pid"
kill "$pid"
wait "$pid" 2>/dev/null || true
cat "$LOG"
rm -rf "$TMP_XDG" "$LOG"
```

Expected: `kill -0` succeeds while the app is running; log is empty or contains no error/panic.

- [x] **Step 3: Run interactive visual smoke**

Run:

```bash
pnpm --filter @workbranch/companion tauri dev
```

Manual checks:
- Popover reads as a compact worktree cockpit, not a generic card dashboard.
- Active/current step is visible before the nested checklist.
- Dirty repo chip is visible but does not dominate the row.
- Actions wrap cleanly at narrow width.
- Keyboard focus is visible on refresh, disclosure, and action buttons.
- No duplicated task status text in the task header.

Record the result in `TASK-WORKBRANCH.md`. If this environment cannot drive the visible menu bar, record the gap and require a human visual check before release.

Task 6 evidence: `pnpm --filter @workbranch/companion tauri build` passed. Isolated release smoke with temporary `XDG_CONFIG_HOME` kept the release binary running for 5 seconds and emitted no logs. Visible menu-bar visual checks could not be observed from this CLI session, so task status remains `review` until a human confirms the popover visually.

## Task 7: Final verification

**Files:**
- Update: `docs/plans/0034-companion-linear-ui-refresh.md`
- Update: `../TASK-WORKBRANCH.md`

- [x] **Step 1: Run full relevant checks**

Run:

```bash
pnpm --filter @workbranch/companion test
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
pnpm --filter @workbranch/companion tauri build
git diff --check
```

Expected:
- Vitest passes.
- TypeScript passes.
- Biome exits 0. Existing `parseContract.ts` info diagnostics may print, but must not be newly introduced by changed files.
- Tauri build passes.
- `git diff --check` is clean.

- [x] **Step 2: Measure modified source file sizes**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
files = [
    'apps/workbranch-companion/src/App.tsx',
    'apps/workbranch-companion/src/ui/TaskRow.tsx',
    'apps/workbranch-companion/src/style.css',
    'apps/workbranch-companion/tests/task-row.test.tsx',
]
for f in files:
    count = 0
    for line in Path(f).read_text().splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith('//') and not stripped.startswith('/*') and not stripped.startswith('*'):
            count += 1
    print(f'{f}: {count}')
PY
```

Expected: TS/TSX files are at or below 250 pure LOC. CSS can exceed 250 only if it remains a cohesive stylesheet; if it becomes hard to review, split by section comments is acceptable for CSS but do not create new CSS tooling.

- [x] **Step 3: Update plan with execution evidence**

Append a `## 구현 결과` section to this plan with:
- files changed,
- tests run and pass/fail status,
- visual smoke result or explicit visual gap,
- any remaining risk.

- [x] **Step 4: Update task brief to done or review**

Set `TASK-WORKBRANCH.md` status:
- `done` if automated checks pass and visual smoke was observed;
- `review` if code is complete but visible app/menu-bar confirmation remains for the user.

## Self-review checklist for this plan

- [x] Covers design source of truth via `DESIGN.md`.
- [x] Covers semantic UI tests before markup changes.
- [x] Keeps CLI/contract/Rust scope unchanged.
- [x] Avoids shadcn/Tailwind dependency churn in v1.
- [x] Includes exact file paths and commands.
- [x] Includes visual/manual gate for a UI task.
- [x] Avoids placeholders such as TBD/TODO.
