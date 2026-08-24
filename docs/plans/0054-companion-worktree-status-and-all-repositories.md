# 0054 Companion Worktree Status Matrix + All Repositories Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Before each behavior change use `superpowers:test-driven-development` (red → green → refactor). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 메뉴바 Companion을 열면 상단에서 모든 active worktree의 `PLAN → EXECUTION → REVIEW` 위치를 즉시 파악하고, 하단에서 선택 필터 없이 그 active worktree에 속한 모든 repo/branch의 Git 사실과 기존 configured launcher 진입점을 확인할 수 있게 한다.

**Architecture:** 기존 CLI `list --global --json`과 Companion domain model을 그대로 source of truth로 사용한다. `application/state.ts`가 task lifecycle과 repo activity를 하나의 `MainViewModel`로 정규화하고, 상단 `StageBoard`는 active task matrix를, 하단 `RepositoryQueue`는 동일한 active set 중 repo가 있는 task를 전역 우선순위로 렌더링한다. Matrix 선택은 하단을 필터링하지 않고 대응 task를 강조하고 화면 안으로 이동시킨다.

**Tech Stack:** Tauri v2, React 18, TypeScript strict mode, plain CSS, Vitest + `renderToStaticMarkup`, Biome, pnpm.

---

## 승인된 사용자 흐름

1. Plan 단계는 AI와 사람이 함께 진행한다.
2. `EXECUTION` 단계는 AI가 담당하므로 해당 worktree와 연결된 repo/branch를 확인한다.
3. Review 단계는 사람이 코드를 확인해야 하므로 가장 높은 attention priority로 표시한다.
4. 상단 matrix는 전체 위치를 빠르게 읽는 navigator다.
5. 하단은 선택한 task만 보여주는 detail panel이 아니라 **상단 active matrix 전체 task의 모든 repo 정보**를 항상 유지한다.
6. 상단 task를 선택하면 하단의 대응 task card만 강조하고 첫 repo 위치로 scroll한다. 다른 repo는 숨기지 않는다.
7. 코드 확인/실행은 기존 task-level `IDE | Terminal | Finder` action을 재사용하며 launcher command와 path resolution은 `workbranch config`/CLI가 소유한다.

## Decision Gates

- [x] 3단계 lifecycle과 담당 주체
  - Impact: Main matrix vocabulary, status mapping, live agent state 의존 여부.
  - Current evidence: `apps/companion/src/domain/model.ts`의 `planning | in-progress/blocked | review` mapping은 이미 3단계에 대응하고, 현재 wire에는 agent heartbeat가 없다. `docs/plans/0052-companion-repo-activity-signals-and-agent-events.md`의 Slice C는 미완료다.
  - Recommended default: `PLAN (AI/Human) → EXECUTION (AI) → REVIEW (Human)`.
  - Status: resolved — 사용자 확정. `EXECUTION`은 lifecycle ownership이며 live process heartbeat를 뜻하지 않는다.
- [x] All Repositories component/test 경계
  - Impact: 새 파일 경로, StageBoard/ProjectGroup 책임, relative-time test ownership.
  - Current evidence: `StageBoard.tsx`는 423줄, `task-row.test.tsx`는 649줄이며 기존 `ProjectGroup.tsx`는 project grouping만 소유한다. `stage-board-clock.test.tsx`의 relative-time 책임은 repo detail과 함께 이동해야 한다.
  - Recommended default: `apps/companion/src/ui/RepositoryQueue.tsx` + `apps/companion/tests/repository-queue.test.tsx`.
  - Status: resolved — 사용자 선택 A. 전용 component/test를 만들고 `ProjectGroup.tsx`, `project-group.test.tsx`, `stage-board-clock.test.tsx`의 기존 책임을 제거·통합한다.
- [x] 코드 실행 launcher와 path ownership
  - Impact: Companion action contract, CLI/Tauri 확장 여부, multi-repo IDE 동작.
  - Current evidence: `App.tsx`와 Tauri allowlist는 `{kind, task}`만 전달한다. `workbranch ide <task>`는 project의 `IDE` config를 사용해 repo worktree별로 실행하고, `terminal <task>`와 `finder <task>`는 task root를 연다. `--repo`는 CLI가 이미 소유하지만 이번 Companion action에는 노출하지 않는다.
  - Recommended default: task card당 기존 `IDE | Terminal | Finder` action 한 세트, path/config 해석은 전부 CLI에 위임.
  - Status: resolved — 사용자 확정. 미리 설정한 `workbranch config`의 IDE/path launcher를 그대로 사용한다.
- [x] native menu bar window 크기
  - Impact: matrix/repository 정보 밀도, 작은 화면 fallback, Activity/Settings 회귀 범위.
  - Current evidence: 현재 window는 `460×680`, `minWidth: 460`, `resizable: true`이고 기존 CSS/test가 460px 무overflow를 보장한다. 새 4열 matrix + repo queue는 더 넓은 primary width가 필요하다.
  - Recommended default: initial `720×760`, `minWidth: 460`, `resizable: true`, 520px 이하 compact layout.
  - Status: resolved — 사용자 선택 A. 넓게 시작하되 기존 460px fallback을 보존한다.
- [x] All Repositories의 task 범위
  - Impact: Main 정보 밀도, matrix/queue 대응 관계, clean todo/done inventory 노출 여부.
  - Current evidence: 현재 matrix는 planning/execution/review와 Git evidence로 derived execution인 task만 active로 취급한다. 사용자가 요청한 범위는 “위의 모든 repo”였다.
  - Recommended default: 상단 matrix active task의 모든 repo만 하단에 표시하고 clean todo/done은 제외.
  - Status: resolved — 사용자 선택 A. queue와 matrix의 task set을 일치시키며 clean inactive inventory는 Main에 렌더링하지 않는다.

## 결정 사항

### D1. `EXECUTION`은 AI가 담당하는 lifecycle stage다

- `planning` → `PLAN`
- `in-progress` → `EXECUTION`
- `blocked` → `EXECUTION` + `BLOCKED`
- `review` → `REVIEW`
- `todo`/`done` + `dirty || ahead > 0` → 기존 규칙대로 derived `EXECUTION`
- clean `todo`/`done` → matrix와 repository queue 모두에서 제외하고 `idleCount`에만 포함

0052의 미완료 agent-event slice(`RUNNING · CLAUDE/CODEX`)를 이 UI의 선행조건으로 만들지 않는다. 구현자는 `status:`와 Git evidence만으로 정확히 말할 수 있는 범위만 표시한다. agent heartbeat가 나중에 도입되면 task status 옆 보조 label로 추가할 수 있지만, 이번 plan은 provider/session 상태나 repo-level agent attribution을 추측하지 않는다.

### D2. Matrix는 task/worktree 단위, 하단은 task card 안의 모든 repo 단위다

한 task에 여러 repo가 있을 수 있으므로 matrix row를 repo별로 복제하지 않는다. 상단 row identity는 `project / task`, 하단 task card는 repo별로 다음을 모두 표시한다.

- repo name
- branch
- `CLEAN` 또는 `DIRTY <N> FILE(S)`
- `AHEAD <N>` / `BEHIND <N>`
- `last commit: <subject> · <relative time>`
- task status, active plan `currentItem`, notification/progress cue
- task-level `IDE | Terminal | Finder`

repo 내부 순서는 `dirty` → `ahead > 0` → 최신 `lastCommitAt` → 원래 wire 순서다. 이는 “지금 코드 확인 가능성이 높은 repo”를 위로 올리되 Git facts 이상을 추측하지 않는다.

### D3. 하단 전역 정렬은 사람 attention 우선이다

active task card priority는 다음과 같다.

1. `REVIEW`
2. `BLOCKED`
3. `EXECUTION` (`in-progress` 또는 derived execution)
4. `PLAN`

같은 priority 안에서는 `max(task.updatedAt, ...repo.lastCommitAt)` 내림차순, 동률이면 기존 project/task wire 순서를 유지한다.

### D4. 상단 선택은 navigator이며 필터가 아니다

- matrix row single click / native button activation: 해당 task를 선택, 하단 task card 강조, `scrollIntoView({ block: "nearest" })`.
- matrix row pointer double-click / `⌘Enter` 또는 `Ctrl+Enter`: 기존 IDE launch.
- 선택 전에는 하단에 강조 항목이 없다. stale key는 자동으로 첫 task를 선택하지 않는다.
- 선택 후에도 repository card count와 DOM row count는 변하지 않는다.

### D5. 메뉴바 window는 넓게 열되 기존 compact fallback을 보존한다

- initial width: `720`
- min width: `460`
- height: `760`
- `720px`에서는 repo fact/current work/action을 3영역 grid로 표시한다.
- `520px` 이하에서는 task/repo facts 위, current work와 action 아래로 쌓는다.
- Activity/Settings는 동일 window에서 max-width를 사용하며 기능/정보 구조는 변경하지 않는다.

## 범위 밖

- CLI, JSON Schema, contract DTO, ACL, Rust command 변경
- repo별 agent process attribution 또는 provider/session 표시
- diff viewer 또는 신규 `DIFF` action. 승인 mockup의 `DIFF`는 개념 표시였으며 현재 allowlist에는 없다.
- task lifecycle mutation UI
- Activity/Settings 정보 구조 변경
- 새 UI/runtime/test dependency

## 변경 파일 구조

```text
DESIGN.md                                      # 새 Main 정보 구조, 폭, 정렬, interaction 계약
apps/companion/src/application/state.ts       # MainViewModel, task priority, repo ordering, stable task key
apps/companion/src/ui/StageBoard.tsx           # 상단 active matrix 전용; selected-only Detail/OTHER 제거
apps/companion/src/ui/RepositoryQueue.tsx      # 신규: active repository-bearing task + scroll/highlight orchestration
apps/companion/src/ui/TaskRow.tsx              # repo activity facts, current work, task actions, highlighted state
apps/companion/src/App.tsx                     # buildMainViewModel, selection wiring, ProjectGroup 제거
apps/companion/src/styles/stage-board.css      # wide matrix + selected navigator state
apps/companion/src/styles/task-details.css     # all-repository card/repo grid + compact fallback
apps/companion/src/styles/status-groups.css    # RepositoryQueue section ownership; legacy project-group 제거
apps/companion/src-tauri/tauri.conf.json       # 720×760 initial, 460 min width
apps/companion/tests/model.test.ts             # view-model inclusion/order/count contracts
apps/companion/tests/task-row.test.tsx         # matrix + all repository rendering/interaction contracts
apps/companion/tests/app-shell.test.tsx        # CSS/window contract
apps/companion/tests/repository-queue.test.tsx # 신규: scroll/highlight/all-visible contract

# 제거
apps/companion/src/ui/ProjectGroup.tsx
apps/companion/tests/project-group.test.tsx
apps/companion/tests/stage-board-clock.test.tsx
```

---

### Task 1: DESIGN.md에 새 Main contract를 먼저 고정한다

**Files:**
- Modify: `DESIGN.md`

- [x] **Step 1: superseded Main 구조를 명시한다**

`## Direction revision` 끝에 다음 결정을 추가한다.

```markdown
- 2026-08-24 (worktree matrix + all repositories): Main은 상단 `WORKTREE STATUS` matrix와 하단 `ALL REPOSITORIES` queue의 2단 구조다. Matrix는 `PLAN | EXECUTION | REVIEW` lifecycle 위치를 task/worktree 단위로 압축하고, 하단은 선택과 무관하게 matrix active task 중 repository-bearing task와 그 모든 repo/branch activity facts를 유지한다. Matrix 선택은 필터가 아니라 하단 task highlight + nearest scroll이다. 하단은 `REVIEW → BLOCKED → EXECUTION → PLAN` 순서이며 task 안 repo는 dirty/ahead/latest-commit evidence 순으로 배치한다. clean todo/done은 Main inventory에 포함하지 않는다. task actions는 기존 `IDE | Terminal | Finder`만 유지한다. 초기 native window는 720×760, 최소 폭은 460이다.
```

- [x] **Step 2: 기존 모순을 현재형 섹션에서 교정한다**

다음 항목을 동시에 바꾼다.

```text
Information architecture:
  selected-only DetailPanel → WORKTREE STATUS + ALL REPOSITORIES

Components:
  ProjectGroup + selected DetailPanel → StageBoard + RepositoryQueue + TaskMetaRow

Responsive behavior:
  primary 460px → primary 720px, 460px compact fallback

Interaction states:
  default first-row selection → no default selection
  selection filters detail → selection highlights/scrolls without hiding rows
```

- [x] **Step 3: 문서 diff를 검사한다** — `git diff --check -- DESIGN.md` 통과.

Run:

```bash
git diff -- DESIGN.md
git diff --check -- DESIGN.md
```

Expected: 새 방향과 현재형 섹션이 일치하며 `selected DetailPanel`, “460px primary”가 active contract로 남지 않는다.

- [x] **Step 4: commit gate** — 사용자 요청에 commit 권한이 없어 safety gate에 따라 commit 없이 계속 진행.

```bash
git add DESIGN.md
git commit -m "docs(companion): define worktree status repository queue"
```

---

### Task 2: MainViewModel을 red → green으로 추가한다

**Files:**
- Modify: `apps/companion/tests/model.test.ts`
- Modify: `apps/companion/src/application/state.ts`

- [x] **Step 1: failing model tests를 작성한다**

`model.test.ts`에 한 state 안에서 review, blocked, in-progress, planning, clean todo, clean done, dirty done, no-repo task를 구성하고 아래 contract를 단언한다.

```ts
const main = buildMainViewModel(state);

expect(main.matrixRows.map((row) => row.task.name)).toEqual([
	"review-task",
	"blocked-task",
	"dirty-done-task",
	"execution-task",
	"planning-task",
]);
expect(main.repositoryRows.map((row) => row.task.name)).toEqual([
	"review-task",
	"blocked-task",
	"dirty-done-task",
	"execution-task",
	"planning-task",
]);
expect(main.repositoryCount).toBe(
	main.repositoryRows.reduce((count, row) => count + row.task.repos.length, 0),
);
expect(main.idleCount).toBe(2);
expect(main.matrixRows.some((row) => row.task.name === "no-repo-task")).toBe(
	true,
);
expect(main.repositoryRows.some((row) => row.task.name === "no-repo-task")).toBe(
	false,
);
```

repo ordering test도 추가한다.

```ts
expect(main.repositoryRows[0]?.repos.map((repo) => repo.name)).toEqual([
	"dirty-repo",
	"ahead-repo",
	"recent-clean-repo",
	"old-clean-repo",
]);
```

- [x] **Step 2: red를 확인한다** — `buildMainViewModel is not a function`으로 의도대로 FAIL.

Run:

```bash
pnpm --filter @workbranch/companion test -- model.test.ts
```

Expected: `buildMainViewModel` export가 없어 FAIL.

- [x] **Step 3: 최소 MainViewModel을 구현한다**

`state.ts`에 다음 책임을 둔다.

```ts
export type MainRole = "plan" | "execution" | "review" | "idle";

export type MainTaskRow = {
	readonly key: string;
	readonly project: string;
	readonly root: string;
	readonly task: Task;
	readonly repos: readonly Repo[];
	readonly role: MainRole;
	readonly blocked: boolean;
	readonly derived: boolean;
	readonly latestActivityAt: number;
};

export type MainViewModel = {
	readonly matrixRows: readonly MainTaskRow[];
	readonly repositoryRows: readonly MainTaskRow[];
	readonly activeCount: number;
	readonly idleCount: number;
	readonly repositoryCount: number;
};

export function mainTaskKey(root: string, taskName: string): string {
	return `${root}:${taskName}`;
}
```

구현 규칙:

```ts
function roleForTask(task: Task): Pick<MainTaskRow, "role" | "blocked" | "derived"> {
	const placement = matrixPlacement(task);
	if (placement === undefined) {
		return { role: "idle", blocked: false, derived: false };
	}
	return {
		role: placement.column,
		blocked: placement.blocked,
		derived: placement.derived,
	};
}

function mainPriority(
	role: MainRole,
	blocked: boolean,
): number {
	if (role === "review") return 0;
	if (blocked) return 1;
	if (role === "execution") return 2;
	if (role === "plan") return 3;
	return 4;
}
```

`matrixRows`는 `role !== "idle"`만 포함한다. `repositoryRows`는 `matrixRows` 중 repo가 하나 이상인 task만 포함하므로 clean todo/done은 repo가 있어도 제외된다. 각 `repos`는 복사본을 stable sort하고 원본 `Task.repos`는 mutate하지 않는다. blocked priority는 execution보다 먼저 적용한다. no-repo fixture는 `planning`으로 만들어 matrix에는 남지만 repositoryRows에는 빠지는 경계를 검증한다.

- [x] **Step 4: model tests를 green으로 만든다** — Companion 156 tests 및 typecheck 통과.

Run:

```bash
pnpm --filter @workbranch/companion test -- model.test.ts
pnpm --filter @workbranch/companion typecheck
```

Expected: PASS, TypeScript diagnostics 0.

- [x] **Step 5: commit gate** — commit 권한이 없어 safety gate에 따라 생략.

```bash
git add apps/companion/src/application/state.ts apps/companion/tests/model.test.ts
git commit -m "refactor(companion): build main worktree view model"
```

---

### Task 3: StageBoard를 상단 navigator 전용으로 줄인다

**Files:**
- Modify: `apps/companion/src/ui/StageBoard.tsx`
- Modify: `apps/companion/tests/task-row.test.tsx`
- Modify: `apps/companion/src/styles/stage-board.css`

- [x] **Step 1: selected-only detail 제거 contract를 test로 고정한다**

`task-row.test.tsx`에서 기존 `DetailPanel`, `selectedMatrixRow`, `OtherTaskRow` imports/tests를 제거하고 다음 assertions를 추가한다.

```ts
const html = renderToStaticMarkup(
	<StageBoard
		rows={main.matrixRows}
		activeCount={main.activeCount}
		idleCount={main.idleCount}
		onOpenIde={() => undefined}
		onSelect={() => undefined}
		selectedKey={undefined}
	/>,
);

expect(html).toContain("WORKTREE STATUS");
expect(html).toContain("EXECUTION");
expect(html).toContain('aria-label="Worktree status matrix"');
expect(html).not.toContain("DETAIL");
expect(html).not.toContain("OTHER");
expect(html).not.toContain('aria-pressed="true"');
```

selection test:

```ts
const selected = renderBoard(main.matrixRows[1]?.key);
expect(selected).toContain('aria-pressed="true"');
expect(selected.match(/aria-pressed="true"/g)).toHaveLength(1);
```

- [x] **Step 2: targeted red를 확인한다** — old `matrix` prop/detail/CSS 계약으로 7 tests FAIL.

Run:

```bash
pnpm --filter @workbranch/companion test -- task-row.test.tsx
```

Expected: old `matrix` prop/DetailPanel markup 때문에 FAIL.

- [x] **Step 3: StageBoard public props와 markup을 교체한다**

```ts
type StageBoardProps = {
	readonly rows: readonly MainTaskRow[];
	readonly activeCount: number;
	readonly idleCount: number;
	readonly onOpenIde: StageOpenIde;
	readonly onSelect: (key: string) => void;
	readonly selectedKey: string | undefined;
};
```

- header label은 `WORKTREE STATUS`.
- columns는 `PLAN | EXECUTION | REVIEW`.
- row identity는 task name 위, `project` 아래.
- `MatrixCell`은 `MainTaskRow.role`을 사용하고 기존 CSS data value `plan | execution | review`를 유지한다. `idle`은 matrixRows에 없으므로 cell renderer 입력에서 제외한다.
- `blocked`, `derived`, progress, notification cue는 유지.
- `selectedKey === row.key`일 때만 `aria-pressed=true`와 selected style 적용.
- click은 selection, pointer double-click/`⌘Enter`/`Ctrl+Enter`는 기존 IDE action 유지.
- `idleCount > 0`이면 footer text `IDLE <N> · inactive`만 표시하며 disclosure나 repository row를 만들지 않는다.
- `DetailPanel`, `DetailRepo`, `selectedMatrixRow`, `OtherTaskRow`, `formatRelativeTime`, `repoFacts`, `Fragment`, `StatusToken`, `useCurrentEpochSeconds`를 이 파일에서 삭제한다.

- [x] **Step 4: wide + compact CSS를 구현한다**

```css
.stage-board {
	--stage-grid: minmax(220px, 1.7fr) repeat(3, minmax(82px, 0.62fr));
}

@media (max-width: 520px) {
	.stage-board {
		--stage-grid: minmax(0, 1fr) repeat(3, 58px);
	}
}
```

old `.stage-detail-*`, `.stage-repo-*`, `.stage-other*` selectors는 모두 삭제한다. `.stage-matrix-row[data-selected="true"]`는 배경과 좁은 accent rail만 사용하고 다른 row를 흐리게 하지 않는다.

- [x] **Step 5: green 확인** — StageBoard 10 tests, App shell 28 tests, typecheck, lint 통과.

Run:

```bash
pnpm --filter @workbranch/companion test -- task-row.test.tsx app-shell.test.tsx
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
```

Expected: PASS, lint/type diagnostics 0.

- [x] **Step 6: commit gate** — commit 권한이 없어 safety gate에 따라 생략.

```bash
git add apps/companion/src/ui/StageBoard.tsx apps/companion/src/styles/stage-board.css apps/companion/tests/task-row.test.tsx
git commit -m "refactor(companion): make matrix a worktree navigator"
```

---

### Task 4: 모든 repo를 유지하는 RepositoryQueue를 추가한다

**Files:**
- Create: `apps/companion/src/ui/RepositoryQueue.tsx`
- Create: `apps/companion/tests/repository-queue.test.tsx`
- Modify: `apps/companion/src/ui/TaskRow.tsx`
- Modify: `apps/companion/src/styles/task-details.css`
- Modify: `apps/companion/src/styles/status-groups.css`
- Delete: `apps/companion/tests/stage-board-clock.test.tsx`

- [x] **Step 1: all-visible/highlight contract test를 작성한다**

```tsx
const html = renderToStaticMarkup(
	<RepositoryQueue
		nowSeconds={3_600}
		rows={main.repositoryRows}
		selectedKey={main.matrixRows[0]?.key}
		theme="claude"
		onAction={() => undefined}
	/>,
);

expect(html).toContain('aria-label="All repositories"');
expect(html).toContain(`ALL REPOSITORIES ${main.repositoryCount}`);
expect(html.match(/data-repository-task=/g)).toHaveLength(
	main.repositoryRows.length,
);
expect(html.match(/data-highlighted="true"/g)).toHaveLength(1);
for (const row of main.repositoryRows) {
	for (const repo of row.repos) {
		expect(html).toContain(repo.name);
		expect(html).toContain(repo.branch);
	}
}
```

repo activity assertion:

```ts
expect(html).toContain("DIRTY 7 FILES · AHEAD 2");
expect(html).toContain("CLEAN · BEHIND 1");
expect(html).toContain("last commit: implement companion activity feed · 1m");
expect(html).toContain("Review screenshot");
```

기존 `stage-board-clock.test.tsx`의 fake timer contract도 이 파일로 옮긴다. `RepositoryQueue`가 initial render의 `nowSeconds`를 즉시 사용하고 timer tick 후 relative time을 갱신하는지 검증한 뒤 old test file을 삭제한다.

- [x] **Step 2: red 확인** — RepositoryQueue skeleton에서 content/scroll/clock 4 tests FAIL.

Run:

```bash
pnpm --filter @workbranch/companion test -- repository-queue.test.tsx
```

Expected: `RepositoryQueue` module이 없어 FAIL.

- [x] **Step 3: TaskMetaRow를 complete repository card로 확장한다**

`TaskMetaRow` props:

```ts
type TaskMetaRowProps = {
	readonly highlighted: boolean;
	readonly nowSeconds: number;
	readonly repos: readonly Repo[];
	readonly root: string;
	readonly task: Task;
	readonly taskKey: string;
	readonly theme: CompanionTheme;
	readonly onAction: TaskActionHandler;
};
```

`TaskMetaRow` root element는 다음 contract를 갖는다.

```tsx
<article
	id={`repository-${encodeURIComponent(taskKey)}`}
	className={`task-meta-row task-${status}`}
	data-highlighted={highlighted ? "true" : "false"}
	data-repository-task={taskKey}
>
```

각 repo는 정렬된 `repos` prop을 순회하고 `repoFacts(repo)`와 `formatRelativeTime(repo.lastCommitAt, nowSeconds)`를 사용해 2줄로 렌더링한다. `currentItem`이 비어 있으면 task 이름과 다른 active plan title을 fallback으로 사용하고, 둘 다 없으면 current-work line을 생략한다. `IDE | Terminal | Finder`는 repo마다 복제하지 않고 task card당 한 번만 렌더링한다.

- [x] **Step 4: RepositoryQueue를 구현한다**

```tsx
export function RepositoryQueue({
	nowSeconds,
	rows,
	selectedKey,
	theme,
	onAction,
}: RepositoryQueueProps) {
	const currentNowSeconds = useCurrentEpochSeconds(nowSeconds);

	useEffect(() => {
		if (selectedKey === undefined) return;
		document
			.getElementById(`repository-${encodeURIComponent(selectedKey)}`)
			?.scrollIntoView({ block: "nearest" });
	}, [selectedKey]);

	const repositoryCount = rows.reduce(
		(count, row) => count + row.repos.length,
		0,
	);

	return (
		<section aria-label="All repositories" className="repository-queue">
			<h2>ALL REPOSITORIES {repositoryCount}</h2>
			{rows.map((row) => (
				<TaskMetaRow
					key={row.key}
					highlighted={row.key === selectedKey}
					nowSeconds={currentNowSeconds}
					repos={row.repos}
					root={row.root}
					task={row.task}
					taskKey={row.key}
					theme={theme}
					onAction={onAction}
				/>
			))}
		</section>
	);
}
```

- [x] **Step 5: CSS로 wide/compact layout과 attention state를 고정한다**

- 720px: task identity / current work / actions가 3영역 grid.
- repo rows는 name+branch, facts, last commit을 읽는 3영역 grid.
- `review`는 `--review`, `blocked`는 `--blocked`, selected는 `--accent` 2px inset rail.
- selected 외 card opacity를 낮추지 않는다.
- `@media (max-width: 520px)`에서 current work와 actions가 다음 행으로 내려간다.
- 긴 task/repo/branch/subject는 `min-width:0`, ellipsis, `title`로 원문 보존.

- [x] **Step 6: green 확인** — RepositoryQueue/TaskRow/App shell 42 tests, typecheck, lint 통과.

Run:

```bash
pnpm --filter @workbranch/companion test -- repository-queue.test.tsx task-row.test.tsx
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
```

Expected: PASS, diagnostics 0.

- [x] **Step 7: commit gate** — commit 권한이 없어 safety gate에 따라 생략.

```bash
git add apps/companion/src/ui/RepositoryQueue.tsx apps/companion/src/ui/TaskRow.tsx apps/companion/src/styles/task-details.css apps/companion/src/styles/status-groups.css apps/companion/tests/repository-queue.test.tsx
git add -u apps/companion/tests/stage-board-clock.test.tsx
git commit -m "feat(companion): show all repository activity"
```

---

### Task 5: App integration과 넓은 menu bar window를 연결한다

**Files:**
- Modify: `apps/companion/src/App.tsx`
- Modify: `apps/companion/src/application/state.ts`
- Modify: `apps/companion/src-tauri/tauri.conf.json`
- Modify: `apps/companion/tests/app-shell.test.tsx`
- Delete: `apps/companion/src/ui/ProjectGroup.tsx`
- Delete: `apps/companion/tests/project-group.test.tsx`

- [x] **Step 1: App integration contract를 test로 추가한다**

`app-shell.test.tsx`는 source/CSS/config를 읽어 아래를 단언한다.

```ts
expect(appSource).toContain("buildMainViewModel");
expect(appSource).toContain("<RepositoryQueue");
expect(appSource).not.toContain("<ProjectGroup");

const tauri = JSON.parse(
	readFileSync("src-tauri/tauri.conf.json", "utf8"),
) as { app: { windows: Array<{ width: number; minWidth: number; height: number }> } };
expect(tauri.app.windows[0]).toMatchObject({
	width: 720,
	minWidth: 460,
	height: 760,
});
```

- [x] **Step 2: red 확인** — native window가 460×680이라 의도대로 FAIL.

Run:

```bash
pnpm --filter @workbranch/companion test -- app-shell.test.tsx
```

Expected: ProjectGroup가 남아 있고 window가 460×680이어서 FAIL.

- [x] **Step 3: App main view를 새 model로 배선한다** — Task 4 required-prop typecheck 경계를 위해 queue wiring을 앞당겨 적용.

```tsx
const main = buildMainViewModel(state);

<StageBoard
	rows={main.matrixRows}
	activeCount={main.activeCount}
	idleCount={main.idleCount}
	onOpenIde={(root, task) => void handleTaskAction(root, task, "ide")}
	onSelect={setSelectedStageTask}
	selectedKey={selectedStageTask}
/>
<RepositoryQueue
	rows={main.repositoryRows}
	selectedKey={selectedStageTask}
	theme={activeTheme}
	onAction={(root, task, kind) =>
		void handleTaskAction(root, task, kind)
	}
/>
```

`buildMenuModel`은 header summary/errors만 반환하도록 줄이고 `ProjectGroup` type/`groups` 계산을 삭제한다. repository가 없는 active task도 matrix에는 남고, repository queue가 비면 `No repositories registered.` empty state를 렌더링한다.

- [x] **Step 4: window config를 바꾼다**

```json
{
  "width": 720,
  "minWidth": 460,
  "height": 760,
  "resizable": true
}
```

- [x] **Step 5: legacy project-group surface를 삭제한다**

다음 파일/selector/import를 제거한다.

```text
apps/companion/src/ui/ProjectGroup.tsx
apps/companion/tests/project-group.test.tsx
.project-group
ProjectGroup model type
buildMenuModel(...).groups
App.tsx ProjectGroup import/render loop
```

`TerminalPanel`은 Settings/다른 호출자가 있으므로 검색 후 유지한다.

- [x] **Step 6: integration green 확인** — 5 targeted files/58 tests, typecheck, lint 통과.

Run:

```bash
pnpm --filter @workbranch/companion test -- app-shell.test.tsx model.test.ts task-row.test.tsx repository-queue.test.tsx
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
```

Expected: PASS, diagnostics 0.

- [x] **Step 7: commit gate** — commit 권한이 없어 safety gate에 따라 생략.

```bash
git add apps/companion/src/App.tsx apps/companion/src/application/state.ts apps/companion/src-tauri/tauri.conf.json apps/companion/tests/app-shell.test.tsx apps/companion/src/styles/status-groups.css
git add -u apps/companion/src/ui/ProjectGroup.tsx apps/companion/tests/project-group.test.tsx
git commit -m "feat(companion): connect repository queue to main view"
```

---

### Task 6: 전체 자동 검증과 실제 menu bar QA를 통과시킨다

**Files:**
- Verify all files above
- Modify only files already in scope if QA exposes a defect

- [x] **Step 1: stale contract와 placeholder를 검사한다** — production source stale ownership 0건.

Run:

```bash
rg -n "DetailPanel|selectedMatrixRow|OtherTaskRow|ProjectGroup|stage-detail-|stage-other" apps/companion/src
rg -n "T[B]D|implement[ ]later|fill[ ]in details|similar[ ]to Task" docs/plans/0054-companion-worktree-status-and-all-repositories.md
```

Expected: first command has no stale production ownership; second command has no placeholder hit.

- [x] **Step 2: Companion quality gates를 실행한다** — 15 files/145 tests, typecheck, lint, Vite build, Rust 23 tests 통과.

Run:

```bash
pnpm --filter @workbranch/companion test
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
pnpm --filter @workbranch/companion build
cargo test --manifest-path apps/companion/src-tauri/Cargo.toml
```

Expected: all commands exit 0.

- [x] **Step 3: release bundle을 만든다** — Tauri release build 및 `.app` bundle 생성 통과.

Run:

```bash
pnpm --filter @workbranch/companion tauri build
```

Expected: exit 0 and `apps/companion/src-tauri/target/release/bundle/macos/WorkbranchCompanion.app` exists.

- [x] **Step 4: 실제 menu bar app에서 primary width를 검증한다** — 720×760 native Tauri + deterministic CLI fixture capture, real workbranch data capture, matrix selection/highlight 확인.

실제 `workbranch list --global --json` 데이터로 app을 실행하고 Claude/Codex 두 theme에서 확인한다.

```text
Window: 720×760
Data: review, blocked, in-progress, planning, clean todo/done, derived dirty done,
      multi-repo task, long repo/branch/commit subject 포함
```

Acceptance:

- 3초 안에 Review 대상과 Execution 대상의 project/task를 찾을 수 있다.
- 하단 `ALL REPOSITORIES` count가 실제 렌더된 repo 합계와 같다.
- matrix task를 선택하기 전/후 하단 task/repo 수가 동일하다.
- 선택 시 대응 task card가 강조되고 nearest 위치로 이동한다.
- Review/Blocked/Execution/Plan/Idle 우선순위가 D3와 일치한다.
- 긴 문자열이 가로 overflow를 만들지 않고 tooltip/title로 전체 값을 확인할 수 있다.
- IDE는 configured `workbranch ide <task>`를 통해 repo worktree별 target을 열고, Terminal/Finder는 CLI가 해석한 task root를 연다.
- matrix pointer double-click과 `⌘Enter`가 IDE를 연다.
- bottom tabs 위 reserved clearance와 scroll로 마지막 repository row/action까지 도달할 수 있다.

- [x] **Step 5: compact fallback을 검증한다** — 460×760 native capture, 58px stage tracks, all-repo cards, Claude/Codex themes 확인.

Window를 `460×760`으로 줄이고 두 theme에서 확인한다.

Acceptance:

- matrix의 `PLAN | EXECUTION | REVIEW` label/node가 잘리지 않는다.
- repo facts/current work/action이 다음 행으로 쌓이고 가로 scroll이 없다.
- 32px action target과 keyboard focus ring이 유지된다.
- Activity/Settings tab도 460px에서 기존 기능을 유지한다.

- [x] **Step 6: 최종 diff 검증** — `git diff --check` 통과, debug/QA temporary artifact 정리, 독립 visual integrity/visual fidelity reviewer PASS.

Run:

```bash
git diff --check
git status --short
```

Expected: whitespace error 0; 변경 파일은 이 plan의 file structure와 일치한다.

- [x] **Step 7: commit gate** — commit 권한이 없어 safety gate에 따라 생략.

QA에서 수정이 발생한 경우에만:

```bash
git add DESIGN.md apps/companion
git commit -m "fix(companion): polish worktree repository overview"
```

---

## 완료 기준

- [x] 상단은 task/worktree 단위 `PLAN | EXECUTION | REVIEW` matrix다.
- [x] 하단은 selection과 무관하게 matrix active task 중 repository-bearing task와 그 모든 repo를 표시하며 clean todo/done은 제외한다.
- [x] Review가 가장 먼저, Blocked가 다음, Execution이 그 다음으로 보인다.
- [x] matrix 선택은 highlight + scroll만 수행하고 filtering하지 않는다.
- [x] repo/branch/Git facts/last commit/current work가 실제 contract 데이터와 일치한다.
- [x] 실행 동작은 기존 `IDE | Terminal | Finder`와 matrix IDE shortcut만 사용하며 path/config resolution은 Companion이 복제하지 않고 CLI에 위임한다.
- [x] 720×760 primary와 460px compact fallback이 두 theme에서 실제로 검증된다.
- [x] targeted/full tests, typecheck, lint, web build, Rust tests, Tauri release build, `git diff --check`가 모두 통과한다.
