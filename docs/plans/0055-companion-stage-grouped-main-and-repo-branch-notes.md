# 0055 Companion Stage-Grouped Main View + Repo/Branch Notes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Before each behavior change use `superpowers:test-driven-development` (red → green → refactor). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Main view의 슬라이더형 3열 stage matrix를 제거하고, `01 PLAN → 02 EXECUTION → 03 REVIEW` 세로 stage 섹션 아래에 각 worktree task와 그 repo/branch 정보(현재 진행 내용 포함)를 한 번만 표시하는 통합 뷰로 바꾼다. 각 repo/branch에 사용자가 메모를 저장·표시·수정할 수 있게 하고, 창 기본 폭을 720에서 520으로 줄인다.

**Architecture:** 기존 CLI `list --global --json` → Companion domain model 흐름은 그대로 유지한다. `application/state.ts`의 `MainViewModel`에 lifecycle 순 `stageGroups`를 추가하고, `StageBoard`가 기존 `RepositoryQueue`/`TaskMetaRow`의 repo activity 책임을 흡수해 단일 컴포넌트가 된다. 메모는 기존 preferences와 동일한 tauri plugin-store 패턴(`companion-notes.json`, key `repo:branch`)으로 frontend에서만 소유하며 Rust/contract 변경이 없다.

**Tech Stack:** Tauri v2, React 18, TypeScript strict mode, plain CSS, `@tauri-apps/plugin-store`, Vitest + `renderToStaticMarkup`, Biome, pnpm.

**Approved mockup:** https://claude.ai/code/artifact/3cdcef4b-987b-4fbe-b615-88326b437474 (v2 `세로 스테이지 통합 뷰`, 전체 정보 표시 variant + repo 행 인라인 메모)

---

## 승인된 사용자 문제와 흐름

1. 기존 slide-pointer(3열 점·선·노드)로는 각 행이 어느 stage인지 읽기 어렵다 → stage는 색상 + 번호 + 텍스트의 **세로 섹션 헤더**로 명시한다.
2. 현재 진행 중인 작업 내용이 Worktree Status에 보이지 않는다 → 이미 wire로 내려오는 `plan.currentItem`(없으면 plan title)을 각 task 아래 한 줄로 표시한다.
3. 폭이 너무 크다 → 3열 grid를 제거하고 창 기본 폭을 `720 → 520`으로 줄인다(최소 460 유지).
4. 사용자가 각 repo/branch 별로 메모를 남기고 싶다 → repo 행 인라인 ✎ 편집, 메모가 있으면 한 줄 상시 노출.
5. stage 섹션 아래에 task와 repo 정보가 함께 보이므로, 같은 정보를 반복하던 `ALL REPOSITORIES` 섹션은 제거한다(사용자 승인).

## Decision Gates

- [x] Stage 표시 방식
  - Impact: Main 정보 구조, StageBoard/RepositoryQueue 존폐, CSS/test 계약 전면 교체 범위.
  - Options: A) 스테이지별 그룹핑, B) 행별 배지, C) 컴팩트 스텝퍼 칩, D) 세로 스테이지 통합 뷰(그룹핑 + repo 정보 인라인).
  - Status: resolved — 사용자가 D를 직접 제안("세로로 stage 구분하고 거기에 포함된 repo 를 표시", "repo 에 해당하는 정보를 함께 표시")하고 mockup으로 승인("좋아").
- [x] 섹션 통합 여부
  - Impact: `RepositoryQueue`/`TaskMetaRow` 삭제, App 배선, selection scroll 동작.
  - Status: resolved — 통합. 각 task는 stage 그룹 아래 한 번만 렌더링하며 별도 `ALL REPOSITORIES` 섹션은 없다.
- [x] repo 정보 밀도
  - Options: 전체 정보(branch·dirty·ahead/behind·last commit·relative time) vs 컴팩트(last commit 생략).
  - Status: resolved — 전체 정보(추천안)로 승인.
- [x] 메모 부착 단위와 UX
  - Options: repo 행 인라인(repo+branch 키) vs task 카드당 1개.
  - Status: resolved — repo 행 인라인. 원 요청이 "각 repo/branch 별"이며 mockup으로 승인.
- [x] 메모 저장소
  - Impact: Rust/contract 변경 여부, worktree 제거 후 메모 수명.
  - Status: resolved — `@tauri-apps/plugin-store` 신규 파일 `companion-notes.json`, key `repo:branch`. Rust 변경 없음. worktree를 지워도 메모는 남고 같은 repo/branch를 다시 열면 다시 보인다.
- [x] 그룹 순서
  - Status: resolved — lifecycle 순 `01 PLAN → 02 EXECUTION → 03 REVIEW`(사용자 스케치 순서). 그룹 내부는 기존 전역 정렬을 유지해 EXECUTION 안에서 blocked가 먼저 온다.
- [x] 빈 stage 표시
  - Impact: Main의 lifecycle 가시성, empty-state markup/test contract.
  - Status: resolved — 사용자 선택 A. PLAN/EXECUTION/REVIEW 헤더는 항상 렌더링하고 빈 stage는 count `0`과 header/rule만 표시하며 별도 empty row는 만들지 않는다.
- [x] Task action 표현
  - Impact: 520/460px task identity 폭, action accessibility, dependency 범위.
  - Status: resolved — 사용자 선택 A. IDE/Terminal/Finder는 text 대신 icon-only inline SVG로 표시한다. 기존 aria-label/title/disabled/focus/handler를 유지하고 새 icon dependency나 별도 component file은 추가하지 않는다.
- [x] IDE icon 형태
  - Status: resolved — 사용자 선택 A. IDE는 generic code glyph 대신 window bar + file sidebar + code lines의 editor-window icon으로 표시하고 tooltip은 `IDE / Editor`로 명시한다.
- [x] 창 폭
  - Status: resolved — 기본 `520×760`, `minWidth: 460`, resizable 유지.

## 결정 사항

### D1. Main은 stage 그룹 단일 뷰다

- `stageGroups`: `MATRIX_COLUMNS` 순서(`plan`, `execution`, `review`)의 세 그룹을 항상 포함한다. 빈 stage도 `rows: []`와 count `0` header를 유지한다.
- 그룹 내부 순서는 기존 `mainPriority` 전역 정렬(review 0 → blocked 1 → execution 2 → plan 3, 이후 최근 activity)에서 해당 role만 필터한 순서를 그대로 사용한다. 결과적으로 EXECUTION 그룹 안에서 blocked task가 위로 온다. 빈 그룹은 header 아래 task block 없이 다음 stage header로 이어진다.
- derived execution(`todo`/`done` + dirty/ahead)은 기존 규칙대로 EXECUTION 그룹에 `DERIVED` pill과 함께 표시한다.
- clean todo/done은 그대로 `IDLE <N> · inactive` footer로만 집계한다.
- `repositoryRows`/`repositoryCount`는 소비자가 사라지므로 `MainViewModel`에서 제거한다.

### D2. Task block이 기존 repository card의 정보를 전부 흡수한다

task 한 블록에 다음을 표시한다.

- task line: prompt marker `›` + task name + `StatusToken` + `BLOCKED`/`DERIVED`/progress(`n/m`)/`+noti` pill + 우측 IDE/Terminal/Finder icon actions
- current work line: `└ <currentItem>` (비면 task name과 다른 plan title, 둘 다 없으면 생략 — 기존 `currentWorkText` 로직 재사용)
- repo rows (기존 `orderedRepos` 정렬 유지): repo name(+dirty dot) · branch · `CLEAN`/`DIRTY <N> FILE(S)` · `AHEAD <N>` / `BEHIND <N>` · 둘째 줄 `last commit: <subject> · <relative>` · 메모 줄/편집기

### D3. 선택·실행 interaction은 기존 계약을 유지한다

- task 이름 영역 single click: 선택(`aria-pressed`), 선택 시 배경 + 2px accent inset rail.
- pointer double-click / `⌘Enter` / `Ctrl+Enter`: 기존 IDE launch.
- `IDE | Terminal | Finder` 버튼: 기존 task-level action, aria-label 유지(`open <task> in IDE` 등).
- HTML 유효성: action/메모 button이 있으므로 task line 전체를 button으로 감싸지 않는다. 선택 버튼은 이름+pill 영역만 감싼다(button 중첩 금지).
- 두 섹션이 하나가 되었으므로 선택 시 `scrollIntoView` 동기화는 삭제한다.

### D4. 메모는 frontend-owned key-value다

- store file: `companion-notes.json` (`@tauri-apps/plugin-store`, `autoSave: false`)
- key: `${repo.name}:${repo.branch}` — git ref 이름에 `:`는 올 수 없어 충돌이 없다. 같은 repo+branch를 쓰는 task가 여러 개면 같은 메모를 공유한다(의도된 동작: 메모의 대상은 worktree가 아니라 repo/branch).
- value: 문자열. `trim()` 후 빈 값 저장은 key delete와 같다.
- 저장 queue는 preferences의 `enqueuePreferenceSave` 패턴을 재사용하고, 실패 시 preferences와 동일하게 이전 값으로 복원한다.
- 읽기 시 non-string 값은 무시한다(sanitize).

### D5. 창은 좁게 열되 460 fallback을 보존한다

- initial `520×760`, `minWidth: 460`, `resizable: true`.
- 3열 grid가 사라지므로 `--stage-grid` 기반 compact media query도 함께 삭제된다.
- 460px에서 남는 조정: repo facts ellipsis, 긴 이름 truncate + `title` 원문. 가로 scroll 금지.

## UI 가이드

승인 mockup(artifact v2)의 계약을 구현 기준으로 옮긴다. 모든 값은 기존 theme token을 사용하고 신규 색상은 `--plan`/`--plan-soft`뿐이다.

### 레이아웃 구조

```text
┌ .stage-board ────────────────────────────────────────┐  border: 1px --line-strong
│ WORKTREE STATUS 3                                    │  caption: 10px 700 --accent,
│ ──────────────────────────────────────────────────── │  하단 1px --line rule
│ 01 PLAN ────────────────────────────────────────── 1 │  ← .stage-group-head
│  › feature-cpq-task-a  ● PLAN      [IDE][Term][Fin]  │  ← .stage-task-line
│    └ Quotation 흐름 설계 정리 중                       │  ← .stage-current-line
│    backend  feature/cpq-task-a          CLEAN     ✎  │  ← .stage-repo-row (1줄: facts)
│      last commit: docs(cpq-w): … · 2h                │     (2줄: commit)
│ 02 EXECUTION ───────────────────────────────────── 2 │
│  › feature-cpq-task-b  ● RUN  DERIVED  3/7  [actions]│
│    └ SOR 템플릿 Slide 섹션 렌더링 작업                  │
│    backend ● feature/cpq-task-b  DIRTY 14 FILES … ✎  │
│      last commit: feat(cpq-w): … · 40m               │
│      ✎ rebase 전에 quotation migration 충돌 확인       │  ← .stage-note-line (메모 존재 시)
│    frontend  feature/cpq-task-b  CLEAN · BEHIND 2  ✎ │
│ 03 REVIEW ──────────────────────────────────────── 1 │
│  › feat-brew-update    ● REVIEW  +1      [actions]   │
│    …                                                 │
│                                    IDLE 3 · inactive │
└──────────────────────────────────────────────────────┘
```

- board padding `0 10px 8px`, border-top `2px solid var(--emphasis)`, radius 5px — 기존 `.stage-board` 프레임 유지.
- task block 사이 1px `--line` rule. repo row 사이는 더 옅은 rule(`--line` 55% 투명도 수준).
- current line/repo rows 들여쓰기 16px. 8px grid 리듬 유지, click target 최소 높이는 기존 32px 관행(task action `min-height: 30px` + 패딩) 유지.

### Stage 그룹 헤더 (`.stage-group-head`)

| 요소 | 스펙 |
|---|---|
| 번호 pill | `01`/`02`/`03`, 10px 700, radius 999px, 배경 `--<stage>-soft`, 색 `--<stage>` |
| label | `PLAN`/`EXECUTION`/`REVIEW`, 10px 700, letter-spacing 0.08em, 색 `--<stage>` |
| rule | label 뒤 1px `--line` 가로선이 남은 폭을 채움 |
| count | 그룹 내 task 수, 10px `--faint`, tabular-nums |

stage 색 매핑 (`data-column` attribute로 스타일링):

| stage | color token | soft token | 비고 |
|---|---|---|---|
| plan | `--plan` | `--plan-soft` | **신규 token.** claude/codex 모두 `#7aa2f7` / `rgba(122, 162, 247, 0.14)` |
| execution | `--emphasis` | `--emphasis-soft` | claude `#cd694a`, codex `#ededed` (기존 값) |
| review | `--review` | `--review-soft` | 기존 `#bb9af7` |

### Task line (`.stage-task-line`)

- prompt marker `›`: `--accent`, 700. (PromptLine 컴포넌트는 div 구조라 button 안에 못 쓰므로 span으로 렌더링)
- task name: 11px 600, ellipsis + `title` 원문.
- `StatusToken` 재사용(기존 스타일: `● RUN` 등 상태별 색).
- pills: 기존 `.stage-task-*` 계열 재사용 — `BLOCKED`(`--blocked`), `DERIVED`(`--surface-3`/`--faint`), progress `n/m`(`--surface-3`/`--muted`, tabular-nums), `+N` notification(`--notify`).
- actions: 우측 정렬 `IDE | Terminal | Finder`. 기존 `.task-action` 시각 언어(11px, `--accent`, hover `--button-bg-hover`, 120ms transition)를 따르되 520px 폭에 맞는 컴팩트 폭(고정 190~220px grid 제거).
- blocked task: block 왼쪽 `inset 3px 0 0 var(--blocked)` rail 유지.
- selected task: 배경 `--task-selected-summary-bg` + `inset 2px 0 0 var(--accent)`.

### Current work line (`.stage-current-line`)

- `└` tick: `--faint`. 본문: 11px `--muted`, 한 줄 ellipsis + `title` 원문.
- 데이터: `currentWorkText(task)` (currentItem → plan title fallback) 재사용.

### Repo row (`.stage-repo-row`)

- 1줄(facts): repo name 11px 600(`--muted`, dirty면 `--notify` + `●` dot) · branch 11px `--faint` ellipsis · 우측 facts 10px `--muted` tabular-nums (`repoFacts` 재사용) · 메모 button.
- 2줄(commit): `last commit: <subject> · <relative>` 10px `--faint` ellipsis + `title` 원문 (`formatRelativeTime` 재사용). subject가 비면 줄 생략.
- relative time은 기존 `useCurrentEpochSeconds`(60초 tick) 사용.

### 메모 (`.stage-note-*`)

| 상태 | 스펙 |
|---|---|
| button ✎ | 11px, 기본 `--faint`, hover 배경 `--button-bg`/색 `--text`, 메모 있으면 `--notify`. `aria-expanded`, `aria-label="edit note for <repo> <branch>"` |
| 표시 줄 | 메모 존재 + 비편집 시 상시 노출: `✎ <text>` 10px `--notify`, 한 줄 ellipsis + `title` 원문 |
| 편집기 | textarea: `--surface-1` 배경, 1px `--line-strong` border(포커스 시 `--accent`), 10px, min-height 40px, resize vertical. 아래 hint `⌘Enter 저장 · Esc 취소 · 비우고 저장하면 삭제` 9.5→10px `--faint` (10px 미만 금지 규칙에 따라 10px) |
| 키/포커스 | 열면 textarea autofocus. `⌘Enter`/`Ctrl+Enter` 저장, `Esc` 취소(원값 복원), blur 저장. 빈 값 저장 = 삭제 |

### 타이포그래피

기존 규칙(10px 미만 금지, 사용자 선택 monospace stack) 유지. 신규/변경 selector의 최종 크기:

| selector | size |
|---|---|
| `.stage-matrix-caption` (유지) | 10px 700 |
| `.stage-group-num`, `.stage-group-label`, `.stage-group-count` | 10px |
| `.stage-task-name` | 11px 600 |
| `.stage-current-line` | 11px |
| `.stage-repo-name`, `.stage-repo-branch` | 11px |
| `.stage-repo-facts`, `.stage-repo-commit`, `.stage-note-line` | 10px |
| `.stage-note-editor textarea`, hint | 10px |
| `.task-action` (유지) | 11px |

### 접근성·기타

- section `aria-label="Worktree status"` (matrix가 아니므로 문구 변경).
- 선택 버튼 `aria-label`: `<project>, <task>, <STAGE>[, blocked], select; double-click or command-enter to open in IDE` — 기존 포맷 유지, stage 텍스트는 그룹에서도 중복 제공(스크린리더가 헤더 없이 행만 읽는 경우 대비).
- `prefers-reduced-motion` 존중: 기존 motion.css 계약 그대로, 신규 애니메이션 없음.
- 모든 focusable에 `:focus-visible` outline `2px solid var(--accent)`.
- 가로 overflow 금지: 모든 한 줄 텍스트 `min-width: 0` + ellipsis, 원문은 `title`.

## 범위 밖

- CLI, JSON Schema, contract DTO, ACL, Rust command/state 변경
- 메모의 CLI 노출·동기화, task 파일(`memo:`)과의 연동 (기존 `Task.notiCount`용 memo/noti 체계와 별개)
- task lifecycle mutation UI
- Activity/Settings 정보 구조 변경
- 새 UI/runtime/test dependency

## 변경 파일 구조

```text
DESIGN.md                                        # Main 통합 구조, 520px primary, 메모 계약
apps/companion/src/application/state.ts          # MainViewModel: stageGroups 추가, repositoryRows/Count 제거
apps/companion/src/application/notes.ts          # 신규: note store, key, sanitize, write/delete 로직
apps/companion/src/application/useRepoNotes.ts   # 신규: notes 로드/저장 hook (preferences hook 패턴)
apps/companion/src/ui/StageBoard.tsx             # 통합 뷰 전면 재작성 (group head/task block/repo row/메모)
apps/companion/src/ui/TaskRow.tsx                # helpers만 유지(taskActionsFor, repoFacts, formatRelativeTime, currentWorkText); TaskMetaRow/RepoActivityRow 삭제
apps/companion/src/App.tsx                       # RepositoryQueue 제거, useRepoNotes 배선, empty state 문구
apps/companion/src/styles/themes.css             # --plan/--plan-soft (양 theme)
apps/companion/src/styles/stage-board.css        # 전면 재작성 (matrix/slider selector 전부 삭제)
apps/companion/src/styles/task-details.css       # .error/.empty만 잔류, task-meta/repo-activity selector 삭제
apps/companion/src/style.css                     # status-groups.css/task-actions.css import 정리
apps/companion/src-tauri/tauri.conf.json         # width 720 → 520
apps/companion/tests/model.test.ts               # stageGroups 계약 추가
apps/companion/tests/notes.test.ts               # 신규: key/sanitize/write-delete/queue 계약
apps/companion/tests/stage-board.test.tsx        # 신규: 통합 뷰 rendering/interaction/CSS 계약 (task-row·repository-queue test 대체)
apps/companion/tests/app-shell.test.tsx          # window 520, RepositoryQueue 부재, 신규 CSS/타이포 계약

# 제거
apps/companion/src/ui/RepositoryQueue.tsx
apps/companion/src/styles/status-groups.css
apps/companion/src/styles/task-actions.css       # 스타일은 stage-board.css로 흡수
apps/companion/tests/task-row.test.tsx
apps/companion/tests/repository-queue.test.tsx
```

---

### Task 1: DESIGN.md에 통합 Main contract를 먼저 고정한다

**Files:**
- Modify: `DESIGN.md`

- [x] **Step 1: Direction revision을 추가한다** — 2026-08-26 stage-grouped Main + repo/branch notes 방향을 current design history에 추가했다.

```markdown
- 2026-08-26 (stage-grouped main + repo/branch notes): Main은 단일 `WORKTREE STATUS` 뷰다. 3열 slide-pointer matrix와 `ALL REPOSITORIES` queue를 제거하고, `01 PLAN → 02 EXECUTION → 03 REVIEW` 세로 stage 섹션 아래에 각 active task를 현재 진행 내용(`currentItem`), repo/branch Git facts, task actions와 함께 한 번만 표시한다. EXECUTION 그룹 안에서 blocked가 먼저 온다. 각 repo/branch에는 사용자 메모를 인라인으로 저장·표시한다(`companion-notes.json`, key `repo:branch`, frontend-owned). 초기 native window는 520×760, 최소 폭 460.
```

- [x] **Step 2: 현재형 섹션(Information architecture, Components, Visual language, Interaction)에서 matrix/queue 서술을 통합 뷰 서술로 교정한다** — active contract를 세로 stage 그룹, inline repo facts/notes, 520px primary로 교정했다. 이전 용어는 historical Direction revision에만 남는다.

- [x] **Step 3: 검증** — `git diff --check -- DESIGN.md` PASS.

```bash
git diff -- DESIGN.md
git diff --check -- DESIGN.md
```

- [x] **Step 4: commit gate** — commit 권한 요청이 없어 생략하고 auto 실행을 계속한다.

---

### Task 2: MainViewModel에 stageGroups를 red → green으로 추가한다

**Files:**
- Modify: `apps/companion/tests/model.test.ts`
- Modify: `apps/companion/src/application/state.ts`

- [x] **Step 1: failing test 작성** — lifecycle group order, EXECUTION blocked priority, empty-group omission tests를 추가했다.

```ts
const main = buildMainViewModel(state);

expect(main.stageGroups.map((group) => group.column)).toEqual([
	"plan",
	"execution",
	"review",
]);
expect(
	main.stageGroups
		.find((group) => group.column === "execution")
		?.rows.map((row) => row.task.name),
).toEqual(["blocked-task", "dirty-done-task", "execution-task"]);
// 빈 stage는 그룹 자체가 없다
expect(
	buildMainViewModel(planOnlyState).stageGroups.map((g) => g.column),
).toEqual(["plan"]);
// 제거된 필드
expect("repositoryRows" in main).toBe(false);
```

- [x] **Step 2: red 확인** — `stageGroups` 부재로 model tests 2건이 의도대로 FAIL했다.

- [x] **Step 3: 구현** — `MainStageGroup`과 lifecycle-ordered non-empty `stageGroups` projection을 추가했다. Legacy repository fields 제거는 App 전환 Task 5로 미뤘다.

```ts
export type MainStageGroup = {
	readonly column: MatrixColumn;
	readonly rows: readonly MainTaskRow[];
};
```

`stageGroups`는 `MATRIX_COLUMNS.map(column => ({ column, rows: matrixRows.filter(row => row.role === column) }))`의 세 항목을 항상 유지한다. 그룹 내부 순서는 기존 전역 정렬 결과를 재사용하므로 별도 정렬이 없다. 빈 그룹도 count `0` header를 렌더링한다. `repositoryRows`/`repositoryCount`를 제거한다.

- [x] **Step 4: green + typecheck** — model 12 tests PASS, typecheck PASS.

- [x] **Step 5: commit gate** — commit 권한 요청이 없어 생략했다.

---

### Task 3: 메모 저장 모듈을 red → green으로 추가한다

**Files:**
- Create: `apps/companion/tests/notes.test.ts`
- Create: `apps/companion/src/application/notes.ts`

- [x] **Step 1: failing test 작성** — key/sanitize/update/load/read/set/delete/save tests를 추가했다.

```ts
expect(repoNoteKey("backend", "feature/cpq-task-b")).toBe(
	"backend:feature/cpq-task-b",
);
expect(sanitizeRepoNotes([["a:b", "note"], ["c:d", 7], ["e:f", "  "]])).toEqual(
	{ "a:b": "note" },
);
expect(applyNoteUpdate({ "a:b": "old" }, "a:b", "")).toEqual({});
expect(applyNoteUpdate({}, "a:b", " new ")).toEqual({ "a:b": "new" });
// writeRepoNote: 빈 값이면 store.delete, 아니면 store.set 후 save 호출 (fake store로 검증)
```

- [x] **Step 2: red 확인** — `notes.ts` module 부재로 의도대로 FAIL했다.

- [x] **Step 3: 구현** — frontend-owned `companion-notes.json` store와 pure update/sanitize helpers를 구현했다.

```ts
export const COMPANION_NOTES_STORE_FILE = "companion-notes.json";

export type CompanionNoteStore = {
	readonly entries: () => Promise<readonly (readonly [string, unknown])[]>;
	readonly set: (key: string, value: unknown) => Promise<void>;
	readonly delete: (key: string) => Promise<boolean>;
	readonly save: () => Promise<void>;
};

export type RepoNotes = Readonly<Record<string, string>>;

export function repoNoteKey(repoName: string, branch: string): string;
export function sanitizeRepoNotes(entries): RepoNotes; // string & non-blank만 채택, trim
export function applyNoteUpdate(notes, key, text): RepoNotes; // trim 후 빈 값 → key 제거
export async function loadCompanionNoteStore(): Promise<CompanionNoteStore>; // plugin-store load(..., { autoSave: false, defaults: {} })
export async function readRepoNotes(store): Promise<RepoNotes>;
export async function writeRepoNote(store, key, text): Promise<void>; // 빈 값 → delete, 아니면 set; 마지막에 save
```

저장 직렬화 queue는 `preferences.ts`의 `enqueuePreferenceSave`를 import해 재사용한다.

- [x] **Step 4: green + typecheck** — notes 8 tests PASS, typecheck PASS.

- [x] **Step 5: commit gate** — commit 권한 요청이 없어 생략했다.

---

### Task 4: useRepoNotes hook을 추가한다

**Files:**
- Create: `apps/companion/src/application/useRepoNotes.ts`
- Modify: `apps/companion/tests/notes.test.ts` (hook의 순수 로직 계약 추가)

- [x] **Step 1: `useCompanionSettings` 패턴으로 구현한다** — cancelled load guard, optimistic queued save/delete, conditional rollback, status/error handling을 구현했다.

```ts
export type RepoNotesState = {
	readonly notes: RepoNotes;
	readonly saveNote: (key: string, text: string) => Promise<void>;
};

export function useRepoNotes(options: {
	readonly onError: (error: unknown) => void;
	readonly onStatus: (status: string) => void;
}): RepoNotesState;
```

- mount 시 tauri runtime이 있으면 store를 load하고 `readRepoNotes`로 state 초기화 (cancelled guard 포함).
- `saveNote`: `applyNoteUpdate`로 optimistic update → queue로 `writeRepoNote` → 성공 시 `onStatus("Note saved")` / 삭제면 `"Note removed"` → 실패 시 해당 key가 변경되지 않았을 때만 이전 값 복원 후 `onError`.
- tauri runtime이 없으면 `onStatus("Tauri runtime unavailable")` 후 no-op (기존 관행).

- [x] **Step 2: green + typecheck + lint** — notes 8 tests, typecheck, lint exit 0 PASS.

- [x] **Step 3: commit gate** — commit 권한 요청이 없어 생략했다.

---

### Task 5: StageBoard를 통합 뷰로 재작성하고 App을 배선한다

**Files:**
- Modify: `apps/companion/src/ui/StageBoard.tsx`
- Modify: `apps/companion/src/ui/TaskRow.tsx`
- Modify: `apps/companion/src/App.tsx`
- Modify: `apps/companion/src/styles/stage-board.css`
- Modify: `apps/companion/src/styles/themes.css`
- Modify: `apps/companion/src/styles/task-details.css`
- Modify: `apps/companion/src/style.css`
- Create: `apps/companion/tests/stage-board.test.tsx`
- Delete: `apps/companion/src/ui/RepositoryQueue.tsx`
- Delete: `apps/companion/src/styles/status-groups.css`
- Delete: `apps/companion/src/styles/task-actions.css`
- Delete: `apps/companion/tests/task-row.test.tsx`
- Delete: `apps/companion/tests/repository-queue.test.tsx`

- [x] **Step 1: 통합 뷰 contract test를 작성한다** (`stage-board.test.tsx`) — group order, content, notes, actions, selection, stale CSS assertions를 추가했다.

기존 task-row/repository-queue test의 fixture 구성 방식을 재사용해 아래를 단언한다.

```ts
// 구조
expect(html).toContain('aria-label="Worktree status"');
expect(html).toContain("WORKTREE STATUS");
expect(html).toContain(">01<"); // PLAN 그룹 번호 pill
expect(html).toContain(">PLAN<");
expect(html).toContain(">EXECUTION<");
expect(html).toContain(">REVIEW<");
// 그룹 순서 = plan → execution → review, execution 안 blocked 우선
// 빈 그룹도 count 0 header 유지, IDLE footer 유지
// 내용
expect(html).toContain("execution-task current work"); // └ current line
expect(html).toContain("DIRTY 7 FILES · AHEAD 2");
expect(html).toContain("last commit: implement companion activity feed · 1m");
expect(html).toContain('aria-label="open review-task in IDE"');
// 메모
expect(html).toContain("rebase 전에"); // notes prop의 메모 상시 노출
expect(html).toContain('aria-label="edit note for workbranch feat/update-ui-0824"');
// 선택/IDE interaction: 기존 task-row.test의 collectButtonProps 방식으로
// click=select(detail>2 무시), double-click/⌘Enter/Ctrl+Enter=IDE 계약 이전
// CSS contract: stage-board.css에 matrix/slider selector 부재
expect(css).not.toContain("--stage-grid");
expect(css).not.toContain(".stage-node");
expect(css).not.toContain(".stage-cell");
expect(css).toMatch(/\.stage-group-head\[data-column="plan"\][\s\S]*var\(--plan\)/);
```

메모 편집 로직(열기/저장/취소/빈값 삭제)은 `collectButtonProps`/element props 호출 방식으로 검증한다: ✎ onClick → editor open, textarea onKeyDown `⌘Enter` → `onSaveNote(key, draft)` 호출, `Esc` → 닫히고 저장 없음.

- [x] **Step 2: red 확인** — old StageBoard props/markup/CSS로 4 tests가 의도대로 FAIL했다.

- [x] **Step 3: StageBoard를 재작성한다** — vertical group heads, task blocks, repo facts/current work, inline note editor, repo-less actions를 구현했다.

```ts
export type StageBoardProps = {
	readonly activeCount: number;
	readonly idleCount: number;
	readonly groups: readonly MainStageGroup[];
	readonly notes: RepoNotes;
	readonly nowSeconds?: number;
	readonly onAction: TaskActionHandler; // ide | terminal | finder
	readonly onSaveNote: (key: string, text: string) => void;
	readonly onSelect: (key: string) => void;
	readonly selectedKey: string | undefined;
};
```

내부 구성: `StageGroupHead`(번호/label/rule/count, `data-column`), `StageTaskBlock`(선택 button + StatusToken + pills + actions + current line), `StageRepoRow`(facts/commit/메모 — `editing`/`draft` local state). UI 가이드의 markup/aria 계약을 그대로 따른다. `TaskRow.tsx`는 `TaskActionKind`/`taskActionsFor`/`repoFacts`/`formatRelativeTime`/`currentWorkText` helpers만 남기고 component를 삭제하며, 필요한 helper는 export로 승격한다. `theme` prop 의존은 제거한다(PromptLine 미사용).

- [x] **Step 4: App을 배선한다** — `useRepoNotes`와 unified StageBoard를 연결하고 RepositoryQueue/scroll sync를 제거했다.

```tsx
const { notes, saveNote } = useRepoNotes({ onError: showError, onStatus: showStatus });

<StageBoard
	activeCount={main.activeCount}
	idleCount={main.idleCount}
	groups={main.stageGroups}
	notes={notes}
	onAction={(root, task, kind) => void handleTaskAction(root, task, kind)}
	onSaveNote={(key, text) => void saveNote(key, text)}
	onSelect={setSelectedStageTask}
	selectedKey={selectedStageTask}
/>
```

`RepositoryQueue` import/render와 `repositoryRows` empty-state 분기를 제거하고, `main.activeCount === 0 && taskCount > 0`이면 `No active worktrees.`를 렌더링한다.

- [x] **Step 5: CSS를 재작성한다** — matrix/slider CSS를 vertical group/task/repo/note CSS로 교체하고 `--plan` tokens를 추가했으며 legacy queue/action styles를 제거했다.

- `stage-board.css`: UI 가이드 스펙으로 전면 교체. `.stage-matrix-*`(head/col/cell/dot/node)와 `--stage-grid` media query 전부 삭제. `.task-action` 시각 언어는 이 파일의 `.stage-actions .task-action`으로 흡수.
- `themes.css`: 두 theme block에 `--plan: #7aa2f7; --plan-soft: rgba(122, 162, 247, 0.14);` 추가.
- `task-details.css`: `.error`/`.empty`만 남기고 task-meta/repo-activity selector 삭제.
- `style.css`: `status-groups.css`, `task-actions.css` import 제거.

- [x] **Step 6: green 확인** — stage-board/model/notes 3 files, 24 tests PASS; typecheck PASS; lint exit 0.

```bash
pnpm --filter @workbranch/companion test -- stage-board.test.tsx model.test.ts notes.test.ts
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
```

- [x] **Step 7: commit gate** — commit 권한 요청이 없어 생략했다.

---

### Task 6: window·app-shell 계약을 갱신한다

**Files:**
- Modify: `apps/companion/src-tauri/tauri.conf.json`
- Modify: `apps/companion/tests/app-shell.test.tsx`

- [x] **Step 1: app-shell 계약을 갱신한다** — 520×760 config, unified StageBoard/useRepoNotes source, vertical group/repo/note CSS 및 typography assertions로 교체했다.

- window: `width: 520`, `height: 760`, `minWidth: 460` 단언으로 교체.
- source 계약: `<RepositoryQueue` 부재, `<StageBoard` 존재, `useRepoNotes` 배선.
- shell markup 계약: `stage-matrix-caption`/`stage-matrix-col-num` 단언을 새 caption/그룹 헤더 계약으로 교체.
- CSS 계약: "keeps the stage board framed"는 프레임(border/emphasis top) 단언만 유지하고 `--stage-grid` 단언 삭제. "uses a wide repository grid" test는 삭제하고 새 repo-row ellipsis/min-width 계약으로 대체. 타이포그래피 map에서 삭제된 selector를 제거하고 UI 가이드 표의 신규 selector를 추가한다(10px 미만 금지 스캔은 그대로 신규 CSS까지 커버).

- [x] **Step 2: red 확인 후 config/CSS를 맞춘다** — 기존 720/matrix/queue assertions 9건 FAIL을 확인하고 `tauri.conf.json` width를 520으로 변경했다.

- [x] **Step 3: green 확인** — app-shell 29 tests PASS.

- [x] **Step 4: commit gate** — commit 권한 요청이 없어 생략했다.

---

### Task 7: 전체 검증과 실제 menu bar QA

**Files:**
- Verify all files above; QA 결함 시 scope 내 파일만 수정

- [x] **Step 1: stale contract 스캔** — production source에서 legacy matrix/queue/component/style ownership 0건을 확인했다.

```bash
rg -n "RepositoryQueue|TaskMetaRow|RepoActivityRow|stage-matrix-col|stage-node|stage-cell|--stage-grid|repositoryRows|repositoryCount|status-groups|task-actions.css" apps/companion/src
```

Expected: production source에 stale ownership 0건.

- [x] **Step 2: quality gates** — Companion 15 files/145 tests, typecheck, lint exit 0, Vite build, Rust 23 tests, Tauri release bundle PASS.

```bash
pnpm --filter @workbranch/companion test
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
pnpm --filter @workbranch/companion build
cargo test --manifest-path apps/companion/src-tauri/Cargo.toml
```

Expected: 전부 exit 0.

- [x] **Step 3: 실제 app QA (520×760, Claude/Codex 두 theme)** — production StageBoard/CSS deterministic Vite harness의 Chrome Stable capture에서 vertical PLAN/EXECUTION/REVIEW, current work/repo facts, selected/blocked state와 note edit/cancel/save/delete를 확인했다.

Acceptance:

- 각 task의 stage를 텍스트 헤더로 3초 안에 읽을 수 있다 (slide pointer 없음).
- 각 task 아래 `└` current work line이 실제 `currentItem`과 일치한다.
- repo 행에서 branch/dirty/ahead-behind/last commit/relative time이 기존 ALL REPOSITORIES와 동일한 사실을 보여준다.
- ✎로 메모 작성 → 표시줄 노출 → 재편집 → 빈 값 저장 시 삭제. app 재시작 후에도 메모가 남는다. worktree 제거 후 같은 repo/branch 재등장 시 메모가 다시 보인다.
- task 선택 하이라이트, double-click/`⌘Enter` IDE, `IDE|Terminal|Finder` 버튼이 기존과 동일하게 동작한다.
- blocked task가 EXECUTION 그룹 상단에 빨간 rail로 보인다.
- 가로 scroll이 없고 긴 문자열은 ellipsis + title로 확인 가능하다.

- [x] **Step 4: 460px compact QA** — Claude/Codex 460×760 capture에서 group/repo/note layout과 no horizontal overflow를 확인했고 app-shell 회귀 tests가 PASS했다.

- [x] **Step 5: 최종 diff 검증** — `git diff --check` PASS; temporary repository harness를 제거했다.

```bash
git diff --check
git status --short
```

- [x] **Step 6: commit gate** — commit 권한 요청이 없어 생략했다.

---

## 완료 기준

- [x] Main은 `01 PLAN → 02 EXECUTION → 03 REVIEW` 세로 stage 섹션의 단일 뷰이고 slide-pointer matrix와 `ALL REPOSITORIES` 섹션이 없다.
- [x] 각 task는 자신의 stage 그룹 아래 한 번만 나오고 current work line + repo/branch Git facts를 함께 보여준다.
- [x] EXECUTION 그룹 안에서 blocked task가 먼저 온다. PLAN/EXECUTION/REVIEW header는 빈 그룹도 count 0으로 항상 렌더링한다. clean todo/done은 IDLE footer로만 집계한다.
- [x] 각 repo/branch에서 메모를 작성·표시·수정·삭제할 수 있고 `companion-notes.json`에 `repo:branch` 키로 유지된다. Rust/contract 변경이 없다.
- [x] 창 기본 폭이 520이고 최소 460 fallback이 두 theme에서 검증된다.
- [x] 선택/IDE launch/action 계약이 기존과 동일하다.
- [x] targeted/full tests, typecheck, lint, web build, Rust tests, `git diff --check`가 모두 통과한다.

## 2026-08-26 Implementation evidence

- Visual evidence: `/tmp/workbranch-companion-0055/manifest.json`
- Captures: `claude-520.png`, `claude-460.png`, `codex-520.png`, `codex-460.png`
- Interaction metrics: lifecycle group order, blocked-first execution, no matrix/queue, note autofocus, Escape cancel, command-enter save, blank delete, selection, and no horizontal overflow all PASS.
- Automated evidence: Companion 15 files/145 tests PASS; typecheck PASS; lint exit 0 with existing `parseContract.ts` info diagnostics; Vite build PASS; Rust 23 tests PASS; Tauri release app bundle PASS; `git diff --check` PASS.

## 2026-08-27 Empty-stage and icon follow-up

- PLAN/EXECUTION/REVIEW groups are now always present in lifecycle order; empty groups render header/rule/count `0` without an empty task row.
- IDE/Terminal/Finder actions are icon-only inline SVG. IDE uses an editor-window silhouette with title bar, file sidebar, and code lines; tooltip remains `IDE / Editor`; aria-label/disabled/focus/action contracts are unchanged.
- Regression evidence: targeted model/stage-board 17 tests PASS; full Companion 15 files/146 tests PASS; typecheck/lint/Vite build/`git diff --check` PASS.
- Visual evidence: `/tmp/workbranch-empty-stage/codex-520-final.png`, `/tmp/workbranch-empty-stage/claude-460-final.png`; runtime CDP measurement at 460 reports `scrollWidth === clientWidth === 460`.
