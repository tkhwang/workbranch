# 0054 Companion Worktree Status Matrix + All Repositories Implementation Plan

> **Superseded:** The active Companion Main contract moved to the stage-grouped design in [`0055-companion-stage-grouped-main-and-repo-branch-notes.md`](./0055-companion-stage-grouped-main-and-repo-branch-notes.md). This document is retained only as historical implementation and verification evidence; do not reuse its matrix-and-queue architecture for current work.

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Before each behavior change use `superpowers:test-driven-development` (red → green → refactor). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 메뉴바 Companion을 열면 상단에서 조회에 성공한 모든 active worktree의 `PLAN → EXECUTION → REVIEW` 위치를 즉시 파악하고, 하단에서 선택 필터 없이 그 active worktree에 속한 모든 repo/branch의 Git 사실과 기존 configured launcher 진입점을 확인할 수 있게 한다. 일부 configured root 조회가 실패하면 성공한 inventory는 유지하되 `ALL REPOSITORIES` heading에서 incomplete 상태를 즉시 알린다.

**Architecture:** 기존 CLI `list --global --json`과 Companion domain model을 그대로 source of truth로 사용한다. `application/state.ts`가 task lifecycle, repo activity, unavailable root count를 하나의 `MainViewModel`로 정규화하고, 상단 `StageBoard`는 active task matrix를, 하단 `RepositoryQueue`는 동일한 active set의 모든 task card를 전역 우선순위로 렌더링한다. Repo가 없는 active task도 `NO REPOSITORIES` card로 남겨 matrix 선택의 highlight/scroll 목적지가 항상 존재하게 한다. 일부 root가 실패하면 `ALL REPOSITORIES <N> · INCOMPLETE — <M> ROOT(S) UNAVAILABLE`를 queue heading에 표시하고 기존 root별 상세 오류도 유지한다. Matrix 선택은 하단을 필터링하지 않고 대응 task를 강조하고 화면 안으로 이동시킨다.

**Tech Stack:** Tauri v2, React 18, TypeScript strict mode, plain CSS, Vitest + `renderToStaticMarkup`, Biome, pnpm.

---

## 승인된 사용자 흐름

1. Plan 단계는 AI와 사람이 함께 진행한다.
2. `EXECUTION` 단계는 AI가 담당하므로 해당 worktree와 연결된 repo/branch를 확인한다.
3. Review 단계는 사람이 코드를 확인해야 하므로 가장 높은 attention priority로 표시한다.
4. 상단 matrix는 전체 위치를 빠르게 읽는 navigator다.
5. 하단은 선택한 task만 보여주는 detail panel이 아니라 **상단 active matrix 전체 task card와 그 task의 모든 repo 정보**를 항상 유지한다. Repo가 없는 active task도 `NO REPOSITORIES` card로 유지한다.
6. 상단 task를 선택하면 하단의 대응 task card만 강조하고 첫 repo 위치로 scroll한다. 다른 repo는 숨기지 않는다.
7. 코드 확인/실행은 기존 task-level `IDE | Terminal | Finder` action을 재사용하며 launcher command와 path resolution은 `workbranch config`/CLI가 소유한다.
8. 일부 configured root 조회가 실패하면 성공한 task/repo는 계속 표시하고, queue heading에서 incomplete 상태와 실패 root 수를 즉시 확인한다. 기존 root별 상세 오류도 유지한다.

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
  - Recommended default: initial `720×760`, `minWidth: 460`, `resizable: true`, repository cards 620px 이하 / matrix 520px 이하 compact layout.
  - Status: resolved — 사용자 선택 A. 넓게 시작하되 기존 460px fallback을 보존한다.
- [x] All Repositories의 task 범위
  - Impact: Main 정보 밀도, matrix/queue 대응 관계, clean todo/done inventory 노출 여부.
  - Current evidence: 현재 matrix는 planning/execution/review와 Git evidence로 derived execution인 task만 active로 취급한다. 사용자가 요청한 범위는 “위의 모든 repo”였다.
  - Recommended default: 상단 matrix의 모든 active task card와 그 task의 모든 repo를 하단에 표시하고 clean todo/done은 제외.
  - Status: resolved — 사용자 선택 A. queue와 matrix의 task set을 일치시키며 clean inactive inventory는 Main에 렌더링하지 않는다. Repo-less active task의 세부 동작은 아래 navigator 목적지 결정으로 보완한다.
- [x] repo 없는 active task의 navigator 목적지
  - Impact: matrix/queue 대응 관계, selection highlight/scroll, launcher availability.
  - Current evidence: schema v1의 `repos`는 빈 배열을 허용하고, 기존 model fixture도 planning no-repo task를 matrix에는 포함하지만 queue에서는 제외한다. CLI `ide <task>`는 repo loop가 0회이면 아무 target도 열지 않고 성공하며, `terminal <task>`와 `finder <task>`는 task root를 연다.
  - Recommended default: repo-less active task도 하단 `NO REPOSITORIES` card로 렌더링하고 selection 목적지를 보존한다. IDE는 disabled, Terminal/Finder는 enabled로 표시한다.
  - Status: resolved — 사용자 선택 A. matrix의 모든 active task에 대응하는 하단 card를 유지한다.
- [x] partial global error의 Main 표시
  - Impact: `ALL REPOSITORIES` 완전성 의미, 부분 성공 UX, error acceptance.
  - Current evidence: schema v1은 정상 `projects[]`와 실패 `errors[]`를 동시에 반환할 수 있고, 현재 App은 성공한 repo count와 root별 오류를 서로 떨어진 위치에 렌더링한다. 기존 acceptance는 렌더된 repo 합계만 검증해 configured root 전체의 완전성을 보장하지 않는다.
  - Recommended default: 성공한 inventory는 유지하고 queue heading에 `INCOMPLETE — <N> ROOT(S) UNAVAILABLE`를 표시하며 기존 root별 상세 오류도 유지한다.
  - Status: resolved — 사용자 선택 A. 부분 성공을 전체 성공처럼 보이지 않게 한다.
- [x] relative-time 자동 갱신의 test boundary
  - Impact: 시간 경과 UI의 회귀 보호 수준, test dependency/runtime 범위.
  - Current evidence: `useCurrentEpochSeconds`는 60초 interval에서 state를 갱신하지만 기존 test는 timer 등록만 확인하고, 계획의 “timer tick 후 relative time 갱신” 완료 주장을 직접 증명하지 않는다.
  - Recommended default: 기존 `repository-queue.test.tsx`에서 fake timer가 hook state setter에 새 epoch를 전달하는지와 서로 다른 `nowSeconds`가 `1m → 2m` markup을 만드는지를 분리 검증한다. 새 dependency/file은 추가하지 않는다.
  - Status: resolved — 사용자 선택 A. React rerender 자체는 framework contract로 두고 product-owned 두 경계를 결정적으로 검증한다.
- [x] follow-up visual QA evidence 경로
  - Impact: 실제 화면 검증의 재현성, repository binary artifact 범위, 완료 증거.
  - Current evidence: 기존 Companion 계획은 `/tmp/workbranch-companion-*/` capture와 manifest 경로를 계획에 기록하며, repository 내부에는 `docs/evidence/**` 관례가 없다. 기존 0054 visual PASS 문구에는 artifact 경로가 없다.
  - Recommended default: `/tmp/workbranch-companion-0054-followup/`에 Claude/Codex × 720/460 capture, `manifest.json`, 두 reviewer 결과를 저장하고 계획에 정확한 경로를 기록한다.
  - Status: resolved — 사용자 선택 A. repository에 binary evidence directory를 추가하지 않는다.

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

Repo가 0개인 active task도 하단 task card를 렌더링하고 repo list 자리에 `NO REPOSITORIES`를 표시한다. 이 card는 status/current work/progress와 task-root 기반 Terminal/Finder action을 유지한다. IDE action과 matrix double-click/`⌘Enter`는 disabled 처리해 아무 target도 열지 않는 성공을 사용자-visible 성공으로 오해하지 않게 한다.

### D3. 하단 전역 정렬은 사람 attention 우선이다

active task card priority는 다음과 같다.

1. `REVIEW`
2. `BLOCKED`
3. `EXECUTION` (`in-progress` 또는 derived execution)
4. `PLAN`

같은 priority 안에서는 `max(task.updatedAt, ...repo.lastCommitAt)` 내림차순, 동률이면 기존 project/task wire 순서를 유지한다.

### D4. 상단 선택은 navigator이며 필터가 아니다

- matrix row single click / native button activation: 해당 task를 선택, 하단 task card 강조, `scrollIntoView({ block: "nearest" })`.
- repo-bearing matrix row pointer double-click / `⌘Enter` 또는 `Ctrl+Enter`: 기존 IDE launch. Repo-less row는 selection만 제공한다.
- 선택 전에는 하단에 강조 항목이 없다. stale key는 자동으로 첫 task를 선택하지 않는다.
- 선택 후에도 repository card count와 DOM row count는 변하지 않는다.
- repo가 없는 active task도 `NO REPOSITORIES` card가 selection/highlight/scroll 목적지가 된다.

### D5. 메뉴바 window는 넓게 열되 기존 compact fallback을 보존한다

- initial width: `720`
- min width: `460`
- height: `760`
- `720px`에서는 repo fact/current work/action을 3영역 grid로 표시한다.
- `620px` 이하에서는 task/repo facts 위, current work와 action 아래로 쌓고, matrix stage tracks는 `520px` 이하에서 compact width로 전환한다.
- Activity/Settings는 동일 window에서 max-width를 사용하며 기능/정보 구조는 변경하지 않는다.

### D6. `ALL REPOSITORIES`는 partial data 여부를 heading에서 말한다

- `errors.length === 0`: `ALL REPOSITORIES <repoCount>`.
- `errors.length > 0`: `ALL REPOSITORIES <repoCount> · INCOMPLETE — <errorCount> ROOT(S) UNAVAILABLE`.
- `<repoCount>`는 성공적으로 읽은 active task의 실제 repo 합계이며 실패 root의 repo 수를 추측하지 않는다.
- 성공한 matrix/queue rows는 그대로 유지하고 partial error 때문에 전체 Main을 empty/error state로 대체하지 않는다.
- 기존 root별 `<root>: <message>` 상세 오류를 유지한다.
- incomplete cue는 시각적으로 heading에 인접하고 accessibility tree에서도 heading text로 읽힌다.

### D7. Relative-time refresh는 두 product-owned 경계로 검증한다

- clock boundary: fake system time과 fake timer를 사용해 60초 tick이 `setCurrentNow(nextEpochSeconds)`를 호출하는지 검증한다.
- rendering boundary: 동일 repo를 `nowSeconds=3_600`과 `nowSeconds=3_660`으로 각각 렌더링해 `1m`과 `2m` markup을 검증한다.
- interval 등록 수와 cleanup도 기존 contract대로 유지한다.
- React renderer의 내부 rerender 동작을 검증하기 위한 `jsdom`, Testing Library, `react-test-renderer`는 추가하지 않는다.
- 두 경계를 통과하면 product code가 소유하는 timer 값 전달과 relative-time formatting은 보호된다. 실제 React state rerender는 React framework contract로 둔다.

### D8. Follow-up visual evidence는 승인된 `/tmp` 경로와 manifest로 묶는다

- evidence root: `/tmp/workbranch-companion-0054-followup/`.
- required captures:
  - `claude-720.png`
  - `claude-460.png`
  - `codex-720.png`
  - `codex-460.png`
- required metadata/reviews:
  - `manifest.json`
  - `visual-integrity.json`
  - `visual-fidelity.json`
- deterministic fixture는 repo-bearing review/execution task, repo-less planning task, partial global errors 2개, 긴 repo/branch/commit 문자열을 한 화면에 포함한다.
- 각 capture는 repo-less task가 선택된 상태로 `NO REPOSITORIES` highlight, disabled IDE, enabled Terminal/Finder, `INCOMPLETE — 2 ROOTS UNAVAILABLE`를 함께 보여야 한다.
- manifest는 capture path, logical width/height, theme, fixture identity, selected task key, rendered task/repo count, unavailable root count, horizontal overflow 결과, capture timestamp를 기록한다.
- 계획의 완료 evidence에는 위 exact paths와 두 reviewer PASS를 기록한다. `/tmp` artifact가 없거나 manifest와 capture가 불일치하면 visual gate는 미완료다.

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
apps/companion/src/application/state.ts       # MainViewModel, task priority, repo ordering, unavailable root count, stable task key
apps/companion/src/ui/StageBoard.tsx           # 상단 active matrix 전용; selected-only Detail/OTHER 제거
apps/companion/src/ui/RepositoryQueue.tsx      # 신규: all active task cards + incomplete cue + scroll/highlight orchestration
apps/companion/src/ui/TaskRow.tsx              # repo activity facts, current work, task actions, highlighted state
apps/companion/src/App.tsx                     # buildMainViewModel, selection wiring, ProjectGroup 제거
apps/companion/src/styles/stage-board.css      # wide matrix + selected navigator state
apps/companion/src/styles/task-details.css     # all-repository card/repo grid + compact fallback
apps/companion/src/styles/status-groups.css    # RepositoryQueue section ownership; legacy project-group 제거
apps/companion/src-tauri/tauri.conf.json       # 720×760 initial, 460 min width
apps/companion/tests/model.test.ts             # view-model inclusion/order/repo/error count contracts
apps/companion/tests/task-row.test.tsx         # matrix + all repository rendering/interaction contracts
apps/companion/tests/app-shell.test.tsx        # CSS/window contract
apps/companion/tests/repository-queue.test.tsx # 신규: scroll/highlight/all-visible/partial-error contract

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
- 2026-08-24 (worktree matrix + all repositories): Main은 상단 `WORKTREE STATUS` matrix와 하단 `ALL REPOSITORIES` queue의 2단 구조다. Matrix는 `PLAN | EXECUTION | REVIEW` lifecycle 위치를 task/worktree 단위로 압축하고, 하단은 선택과 무관하게 matrix의 모든 active task card와 그 repo/branch activity facts를 유지한다. Repo-less active task도 `NO REPOSITORIES` card로 남긴다. Matrix 선택은 필터가 아니라 하단 task highlight + nearest scroll이다. 하단은 `REVIEW → BLOCKED → EXECUTION → PLAN` 순서이며 task 안 repo는 dirty/ahead/latest-commit evidence 순으로 배치한다. clean todo/done은 Main inventory에 포함하지 않는다. task actions는 기존 `IDE | Terminal | Finder`만 유지하되 repo-less task의 IDE는 disabled다. 초기 native window는 720×760, 최소 폭은 460이다.
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

`matrixRows`는 `role !== "idle"`만 포함한다. 이 Task의 기존 구현은 `repositoryRows`를 `matrixRows` 중 repo가 하나 이상인 task로 제한했지만, 2026-08-26 Decision 1에서 이 filter가 superseded되었다. 현재 contract는 Task 7과 같이 repo-less active task도 `repositoryRows`에 유지한다. 각 `repos`는 복사본을 stable sort하고 원본 `Task.repos`는 mutate하지 않는다. blocked priority는 execution보다 먼저 적용한다.

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
		--stage-grid: minmax(0, 1fr) repeat(3, 56px);
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

기존 `stage-board-clock.test.tsx`의 fake timer contract도 이 파일로 옮긴다. 이 Task의 기존 구현은 interval 등록만 검증했으며 timer tick 이후 값 전달/markup 변화까지 검증했다는 완료 주장은 2026-08-26 review에서 superseded되었다. 현재 relative-time test contract는 Task 9에서 완성한다.

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
- `@media (max-width: 620px)`에서 current work와 actions가 다음 행으로 내려간다.
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

`buildMenuModel`은 header summary/errors만 반환하도록 줄이고 `ProjectGroup` type/`groups` 계산을 삭제한다. 이 Task의 기존 구현은 repository가 없는 active task를 matrix에만 남겼지만, 2026-08-26 Decision 1에서 superseded되었다. 현재 contract는 Task 7과 같이 repo-less active task도 queue card로 유지한다.

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

- [x] **Step 5: compact fallback을 검증한다** — 460×760 native capture, 56px stage tracks, all-repo cards, Claude/Codex themes 확인.

Window를 `460×760`으로 줄이고 두 theme에서 확인한다.

Acceptance:

- matrix의 `PLAN | EXECUTION | REVIEW` label/node가 잘리지 않는다.
- repo facts/current work/action이 다음 행으로 쌓이고 가로 scroll이 없다.
- 32px action target과 keyboard focus ring이 유지된다.
- Activity/Settings tab도 460px에서 기존 기능을 유지한다.

- [x] **Step 6: 최초 구현 당시 최종 diff 검증** — `git diff --check` 통과, debug/QA temporary artifact 정리, 독립 visual integrity/visual fidelity reviewer PASS로 기록되었다. 2026-08-26 review에서 exact capture/reviewer path가 없어 재검증할 수 없음을 확인했으며, 이 visual 완료 주장은 Task 10과 재개방된 완료 기준이 supersede한다.

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

### Task 7: repo-less active task의 navigator contract를 완성한다

**Files:**
- Modify: `DESIGN.md`
- Modify: `apps/companion/src/application/state.ts`
- Modify: `apps/companion/src/ui/StageBoard.tsx`
- Modify: `apps/companion/src/ui/TaskRow.tsx`
- Modify: `apps/companion/tests/model.test.ts`
- Modify: `apps/companion/tests/task-row.test.tsx`
- Modify: `apps/companion/tests/repository-queue.test.tsx`

- [x] **Step 1: repo-less selection/action contract를 failing test로 고정한다** — 기존 filter/IDE behavior로 6 tests가 의도대로 FAIL한 뒤 production 변경을 시작했다.

planning 상태이고 `repos: []`인 task를 구성해 다음을 단언한다.

```ts
expect(main.matrixRows.some((row) => row.task.name === "no-repo-task")).toBe(true);
expect(main.repositoryRows.some((row) => row.task.name === "no-repo-task")).toBe(true);
```

`RepositoryQueue` rendering/interaction assertions:

```ts
expect(html).toContain("NO REPOSITORIES");
expect(html).toContain('data-repository-task="/tmp/acme:no-repo-task"');
expect(html).toContain('aria-current="true"');
expect(scrollIntoView).toHaveBeenCalledWith({ block: "nearest" });
expect(html).toContain('aria-label="open no-repo-task in IDE" disabled');
expect(html).not.toContain('aria-label="open no-repo-task in terminal" disabled');
expect(html).not.toContain('aria-label="open no-repo-task in Finder" disabled');
```

`MatrixTaskRow`에서는 repo-less row의 double-click/`⌘Enter`/`Ctrl+Enter`가 `onOpenIde`를 호출하지 않는지 검증한다. Single click selection은 repo-bearing row와 동일하게 유지한다.

- [x] **Step 2: MainViewModel과 task card를 최소 변경한다** — 모든 active row를 queue에 유지하고 `NO REPOSITORIES`, IDE-disabled, selection-only matrix shortcut을 구현했으며 `DESIGN.md`를 동기화했다.

- `repositoryRows`는 repository-bearing subset이 아니라 `matrixRows`와 동일한 active task-card set을 유지한다.
- `repositoryCount`는 계속 실제 repo 개수 합계이므로 repo-less card가 count를 증가시키지 않는다.
- `TaskMetaRow`는 `repos.length === 0`이면 repo list 대신 `NO REPOSITORIES` empty cue를 렌더링한다.
- `taskActionsFor(task)`는 `task.repos.length === 0`일 때 IDE만 disabled로 반환하고 Terminal/Finder는 enabled를 유지한다.
- `MatrixTaskRow`는 repo-less row의 IDE shortcut을 실행하지 않으며 accessible label/title에서 IDE shortcut을 제공한다고 말하지 않는다.
- `DESIGN.md`의 current contract와 Direction revision에 repo-less `NO REPOSITORIES` card, IDE disabled, Terminal/Finder enabled 규칙을 반영한다.
- CLI, JSON schema, contract DTO, ACL, Rust command는 변경하지 않는다.

- [x] **Step 3: targeted green과 actual interaction을 검증한다** — model/task-row/repository-queue 3 files, 27 tests PASS; typecheck PASS; lint exit 0(기존 parseContract info diagnostics만 유지).

Run:

```bash
pnpm --filter @workbranch/companion exec vitest run \
  tests/model.test.ts \
  tests/task-row.test.tsx \
  tests/repository-queue.test.tsx
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
```

Acceptance:

- repo-less planning task가 matrix와 queue 양쪽에 한 번씩 보인다.
- matrix single click은 `NO REPOSITORIES` card를 강조하고 nearest 위치로 이동한다.
- repo-bearing task/repo count/정렬은 이전과 동일하다.
- repo-less task에서 IDE는 disabled이고 Terminal/Finder는 task root를 연다.
- selection 전후 card/repo DOM count는 변하지 않는다.

---

### Task 8: partial global error를 queue completeness에 연결한다

**Files:**
- Modify: `DESIGN.md`
- Modify: `apps/companion/src/application/state.ts`
- Modify: `apps/companion/src/App.tsx`
- Modify: `apps/companion/src/ui/RepositoryQueue.tsx`
- Modify: `apps/companion/tests/model.test.ts`
- Modify: `apps/companion/tests/repository-queue.test.tsx`
- Modify: `apps/companion/tests/app-shell.test.tsx`

- [x] **Step 1: partial-error contract를 failing test로 고정한다** — unavailable count/model, queue heading/aria, App wiring assertions가 기존 구현에서 3 tests로 의도대로 FAIL했다.

`projects`와 `errors`가 동시에 있는 state를 구성해 다음을 단언한다.

```ts
const main = buildMainViewModel({
  projects: [successfulProject],
  errors: [
    { root: "/tmp/missing-a", message: "not inside a workbranch project" },
    { root: "/tmp/missing-b", message: "task root unavailable" },
  ],
});

expect(main.unavailableRootCount).toBe(2);
```

`RepositoryQueue`는 `unavailableRootCount={2}`일 때 다음을 렌더링한다.

```ts
expect(html).toContain("ALL REPOSITORIES 4");
expect(html).toContain("INCOMPLETE — 2 ROOTS UNAVAILABLE");
expect(html).toContain('aria-label="All repositories, incomplete, 2 roots unavailable"');
```

`unavailableRootCount={0}`에서는 `INCOMPLETE`와 `UNAVAILABLE` 문구가 없어야 한다. `App` source/markup test는 `main.unavailableRootCount`가 queue에 전달되고 기존 `model.errors.map(...)` 상세 오류가 남는지 함께 검증한다.

- [x] **Step 2: MainViewModel과 queue heading을 최소 변경한다** — `unavailableRootCount`, incomplete cue/aria label, App wiring을 추가하고 성공 rows와 상세 root errors를 유지했으며 `DESIGN.md`를 동기화했다.

- `MainViewModel`에 `readonly unavailableRootCount: number`를 추가하고 `state.errors.length`로 설정한다.
- `RepositoryQueueProps`에 `readonly unavailableRootCount: number`를 추가한다.
- queue heading은 repo count와 incomplete cue를 한 문맥으로 렌더링하되 실패 root의 repo 수를 추측하지 않는다.
- `App.tsx`는 `unavailableRootCount={main.unavailableRootCount}`를 전달한다.
- 기존 root별 상세 오류 rendering은 삭제하거나 숨기지 않는다.
- `DESIGN.md`의 information architecture, error states, accessibility contract에 partial inventory 표현을 반영한다.
- CLI, schema, DTO, ACL, Rust command는 변경하지 않는다.

- [x] **Step 3: partial success actual behavior와 regression을 검증한다** — model/repository-queue/app-shell 3 files, 45 tests PASS; typecheck PASS; lint exit 0(기존 parseContract info diagnostics만 유지).

Run:

```bash
pnpm --filter @workbranch/companion exec vitest run \
  tests/model.test.ts \
  tests/repository-queue.test.tsx \
  tests/app-shell.test.tsx
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
```

Acceptance:

- 정상 project의 matrix/task/repo 수와 action은 error 유무로 변하지 않는다.
- error가 1개 이상이면 `ALL REPOSITORIES` heading에서 incomplete와 정확한 failed-root count를 읽을 수 있다.
- failed root의 repository count는 추측하거나 총합에 더하지 않는다.
- root별 상세 오류는 그대로 확인할 수 있다.
- error가 0개면 기존 heading shape를 유지한다.

---

### Task 9: relative-time tick과 rendering 경계를 실제로 검증한다

**Files:**
- Modify: `apps/companion/tests/repository-queue.test.tsx`

- [x] **Step 1: timer가 새 epoch를 state setter에 전달하는지 검증한다** — fake system time/timer가 60초 뒤 epoch seconds를 state setter에 전달하는 test PASS.

기존 hoisted React mock에 `useState` setter spy를 추가하고 fake system time/fake timer로 다음을 단언한다.

```ts
vi.useFakeTimers();
vi.setSystemTime(new Date("2026-08-26T00:00:00Z"));

renderToStaticMarkup(
  <RepositoryQueue
    onAction={() => undefined}
    rows={main.repositoryRows}
    selectedKey={undefined}
    theme="claude"
    unavailableRootCount={0}
  />,
);

vi.setSystemTime(new Date("2026-08-26T00:01:00Z"));
vi.advanceTimersByTime(60_000);

expect(setCurrentNow).toHaveBeenCalledWith(
  Math.floor(new Date("2026-08-26T00:01:00Z").getTime() / 1_000),
);
```

기존 `vi.getTimerCount() === 1` assertion과 cleanup은 유지한다. React mock은 이 test file에서 `useCurrentEpochSeconds`가 사용하는 state setter만 관찰하며 production code를 변경하지 않는다.

- [x] **Step 2: 전달된 시간이 relative-time markup을 바꾸는지 검증한다** — 동일 fixture의 fixed `nowSeconds`가 `1m → 2m` markup을 만드는 test PASS.

동일 fixture를 fixed time으로 두 번 static render한다.

```ts
const oneMinute = renderQueue({ nowSeconds: 3_600 });
const twoMinutes = renderQueue({ nowSeconds: 3_660 });

expect(oneMinute).toContain("last commit: implement companion activity feed · 1m");
expect(twoMinutes).toContain("last commit: implement companion activity feed · 2m");
```

`lastCommitAt <= 0`은 relative-time suffix를 만들지 않는 기존 boundary도 유지한다.

- [x] **Step 3: focused/full regression을 검증한다** — repository-queue 7 tests PASS; Companion 15 files/152 tests PASS; typecheck PASS; lint exit 0(기존 parseContract info diagnostics만 유지).

Run:

```bash
pnpm --filter @workbranch/companion exec vitest run tests/repository-queue.test.tsx
pnpm --filter @workbranch/companion test
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
```

Acceptance:

- 60초 timer tick이 새 epoch seconds를 hook state setter에 전달한다.
- fixed `nowSeconds` 변화가 relative-time markup을 결정적으로 변경한다.
- 새 test dependency, test environment, test file을 추가하지 않는다.
- interval cleanup과 기존 all-visible/highlight/partial-error assertions가 유지된다.

---

### Task 10: follow-up native visual evidence를 재현 가능하게 남긴다

**Artifacts:**
- Create: `/tmp/workbranch-companion-0054-followup/claude-720.png`
- Create: `/tmp/workbranch-companion-0054-followup/claude-460.png`
- Create: `/tmp/workbranch-companion-0054-followup/codex-720.png`
- Create: `/tmp/workbranch-companion-0054-followup/codex-460.png`
- Create: `/tmp/workbranch-companion-0054-followup/manifest.json`
- Create: `/tmp/workbranch-companion-0054-followup/visual-integrity.json`
- Create: `/tmp/workbranch-companion-0054-followup/visual-fidelity.json`
- Modify: `docs/plans/0054-companion-worktree-status-and-all-repositories.md` only to append actual evidence paths/results after verification

- [x] **Step 1: deterministic follow-up fixture와 capture manifest를 준비한다** — CJK/long-string, repo-less task, 2 partial errors fixture와 SHA-256 manifest를 `/tmp/workbranch-companion-0054-followup/`에 생성했다.

Fixture requirements:

```text
review task: multi-repo, dirty/ahead, long commit subject
execution task: normal repo-bearing task
planning task: repos=[]
global errors: 2 unavailable roots
selected task: repo-less planning task
themes: claude, codex
logical sizes: 720×760, 460×760
```

Capture 전에 `/tmp/workbranch-companion-0054-followup/`를 새로 만들고 stale artifact를 재사용하지 않는다. `manifest.json`에는 각 capture의 filename, SHA-256, logical size, theme, fixture id, selected key, task-card count, repo count, unavailable-root count, `scrollWidth <= clientWidth` 결과, timestamp를 기록한다.

- [x] **Step 2: 실제 native/Vite surface에서 4개 capture를 만든다** — Browser backend가 없어 production components/CSS deterministic Vite harness를 Chrome Stable CDP로 구동했다. Claude/Codex × 720/460 fresh captures에서 selected repo-less card, focus, incomplete cue, CJK ellipsis, no horizontal overflow를 확인했다.

각 theme/width에서 repo-less row를 single click해 대응 `NO REPOSITORIES` card가 highlight/nearest scroll 되는 상태를 capture한다. 다음을 실제 화면에서 확인한다.

- `ALL REPOSITORIES <N> · INCOMPLETE — 2 ROOTS UNAVAILABLE`가 heading에서 잘리지 않는다.
- repo-less card의 IDE는 disabled, Terminal/Finder는 enabled다.
- repo-bearing task/repo cards와 상세 root errors가 유지된다.
- 720px과 460px 모두 horizontal overflow가 없다.
- 460px에서 stage labels, no-repo cue, incomplete cue, action focus ring이 읽힌다.
- Claude/Codex theme identity와 selected/highlight contrast가 유지된다.

- [x] **Step 3: 두 visual reviewer 결과를 artifact로 저장한다** — initial review가 fixed-tab clearance와 missing `·` separator를 발견해 scroll-margin/test 및 heading contract를 수정·재캡처했다. 최종 `visual-integrity.json`과 independent `visual-fidelity.json`은 모두 PASS다.

`omo:visual-qa` 또는 동등한 dual-review 절차로 다음 두 lens를 분리한다.

- `visual-integrity.json`: design-system/functional/accessibility/responsive verdict.
- `visual-fidelity.json`: capture/manifest 일치, CJK/ellipsis/clipping, selected/incomplete/no-repo state fidelity verdict.

각 JSON은 `verdict`, inspected capture paths, findings, unresolved risks를 포함한다. 두 verdict 모두 `PASS`여야 한다.

- [x] **Step 4: exact evidence를 계획에 기록하고 final gates를 재실행한다** — Companion 15 files/152 tests, typecheck, lint exit 0, Vite build, Rust 23 tests, Tauri release app bundle, `git diff --check` PASS.

Run:

```bash
pnpm --filter @workbranch/companion test
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
pnpm --filter @workbranch/companion build
cargo test --manifest-path apps/companion/src-tauri/Cargo.toml
pnpm --filter @workbranch/companion tauri build
git diff --check
```

Acceptance:

- manifest의 모든 file path가 존재하고 SHA-256이 실제 capture와 일치한다.
- 4개 capture가 current source/build에서 새로 생성되었다.
- 두 reviewer JSON verdict가 모두 `PASS`다.
- 계획에 exact evidence root, manifest, capture, reviewer path와 verification 결과를 append한다.
- repository에는 screenshot/evidence binary를 추가하지 않는다.

---

## 완료 기준

- [x] 상단은 task/worktree 단위 `PLAN | EXECUTION | REVIEW` matrix다.
- [x] 하단은 selection과 무관하게 matrix의 모든 active task card와 그 task의 모든 repo를 표시하며, repo-less active task는 `NO REPOSITORIES` card로 유지하고 clean todo/done은 제외한다.
- [x] Review가 가장 먼저, Blocked가 다음, Execution이 그 다음으로 보인다.
- [x] matrix 선택은 repo 유무와 관계없이 대응 task card를 highlight + scroll하고 filtering하지 않는다.
- [x] repo/branch/Git facts/last commit/current work가 실제 contract 데이터와 일치한다.
- [x] partial global error가 있으면 성공한 inventory를 유지하면서 queue heading에 incomplete와 failed-root count를 표시하고 기존 상세 오류를 보존한다.
- [x] 60초 timer tick이 새 epoch를 state에 전달하고 해당 시간이 relative-time markup을 변경하는 두 경계가 새 dependency 없이 검증된다.
- [x] 실행 동작은 기존 `IDE | Terminal | Finder`만 사용하고 repo-less task의 IDE/matrix IDE shortcut은 disabled이며, path/config resolution은 Companion이 복제하지 않고 CLI에 위임한다.
- [x] 720×760 primary와 460px compact fallback이 두 theme에서 `/tmp/workbranch-companion-0054-followup/`의 fresh capture/manifest와 dual-review PASS로 검증된다.
- [x] Task 7-10 targeted tests를 포함한 full tests, typecheck, lint, web build, Rust tests, Tauri release build, `git diff --check`가 모두 통과한다.

## 2026-08-26 Follow-up evidence

- Evidence root: `/tmp/workbranch-companion-0054-followup/`
- Manifest: `/tmp/workbranch-companion-0054-followup/manifest.json`
- Captures: `claude-720.png`, `claude-460.png`, `codex-720.png`, `codex-460.png`
- Reviews: `visual-integrity.json` PASS, `visual-fidelity.json` PASS
- Automated proof: Companion 15 files/152 tests PASS; typecheck PASS; lint exit 0 with pre-existing `parseContract.ts` info diagnostics; Vite build PASS; Rust 23 tests PASS; Tauri release bundle PASS; `git diff --check` PASS.
- Visual fix loop: first 460px capture exposed fixed-tab overlap with the selected repo-less card, so `.task-meta-row` gained `scroll-margin-block-end: var(--floating-tabs-content-clearance)` plus regression coverage. Integrity review then found the missing `·` separator; markup/test/captures were refreshed. Final manifest records `bottomContentClearAtMaxScroll: true` and no horizontal overflow for all four captures.
- Environment note: no Browser backend was available, so visual captures used production components/CSS through a deterministic Vite harness in Chrome Stable CDP. The actual Tauri release application was built successfully but not screenshot-driven in this session.
