# 0056 Companion IDLE Task List + Commit Icon + Brief Summary Current-Work Line Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Before each behavior change use `superpowers:test-driven-development` (red → green → refactor). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Main view에서 (1) idle task를 `IDLE 4 · inactive` 개수 집계 대신 보드 하단 compact 목록으로 전부 표시해 plan을 시작할 task를 바로 찾고 열 수 있게 하고, (2) repo 행의 `last commit:` 텍스트 라벨을 git-commit 아이콘으로 줄이며, (3) task brief(`TASK-WORKBRANCH.md`)의 `status:` 아래 첫 본문 줄을 plan summary로 파싱해 현재 작업 줄(`└ ...`)이 체크리스트 없이도 채워지게 한다.

**Architecture:** CLI `list --global --json` → contract → parseContract → ACL → domain → `buildMainViewModel` → `StageBoard` 흐름을 유지한다. summary는 CLI 파서(`task-state.sh`)가 plan별로 추출해 wire의 `plans[].summary`(optional)로 내려주고, companion domain `Plan.summary`(required, ACL이 `""` 정규화)로 매핑한다. `currentWorkText`는 `currentItem → summary → (task명과 다른) plan title` 폴백 체인이 된다. idle 노출은 `MainViewModel.idleRows` projection 추가와 `StageBoard`의 IDLE 섹션 렌더링으로 구현하며 Rust/Tauri 변경은 없다. agent가 summary를 채우도록 생성되는 task workspace `AGENTS.md` 템플릿에 "한 줄 요약 유지" 지침을 추가한다.

**Tech Stack:** Bash CLI(단일 파일 조립: `apps/cli/scripts/build-workbranch.sh` 재빌드 필수), Tauri v2, React 18, TypeScript strict mode, plain CSS, Vitest + `renderToStaticMarkup`, Biome, pnpm.

**Approved mockup:** https://claude.ai/code/artifact/2f05505c-9dee-4812-acda-1542bbece7e5 (현행/제안 토글 + 현재 작업 줄 소스 비교 variant, "제안대로 가되 3번은 brief 요약으로" 승인)

---

## 승인된 사용자 문제와 흐름

1. active task만 보여서 plan을 시작하려는 task가 화면에 없다 → workbranch가 관리하는 task 전부를 조회할 수 있도록 idle task를 보드 맨 아래 IDLE 섹션에 한 줄 compact row로 표시하고, IDE/터미널/Finder 버튼으로 바로 열 수 있게 한다.
2. `last commit:` 라벨이 모든 repo 줄마다 반복되어 자리를 차지한다 → 라벨을 git-commit 아이콘으로 대체하고 subject + 상대시간만 남긴다. hover title과 aria-label로 의미는 유지한다.
3. 현재 무슨 일을 하는지 표시가 없다 → `└` 현재 작업 줄은 이미 있으나 체크리스트가 있어야만 채워진다. brief의 `status:` 아래 첫 본문 줄을 summary로 파싱해 표시하고, 생성되는 AGENTS.md에 summary 유지 지침을 추가해 agent가 자동으로 채우게 한다.

## Decision Gates

- [x] IDLE 표시 방식
  - Options: A) 하단 compact 한 줄 목록(항상 표시), B) 접이식 섹션, C) 현행 개수 집계 유지.
  - Status: resolved — A. mockup으로 승인("제안대로"). 활성 영역과 구분되도록 dim 처리, 활성 task와 동일한 action 버튼 제공.
- [x] `last commit:` 라벨 처리
  - Status: resolved — git-commit 아이콘(원 + 좌우 수평선 inline SVG)으로 대체. mockup으로 승인.
- [x] 현재 작업 줄 데이터 소스
  - Options: A) brief 요약 파싱(CLI+contract+companion), B) 최신 커밋 폴백(companion만, repo 줄과 중복), C) 생략.
  - Status: resolved — A. 사용자 지시 "3번은 brief 요약으로". B는 mockup에서 중복 문제 확인 후 기각.
- [x] summary 파싱 규칙
  - Status: resolved(기본값 채택) — plan 섹션(H1) 안에서 첫 checklist 항목 이전, 비어 있지 않으면서 `status:`·heading·fence·`-`로 시작하는 목록 줄이 아닌 첫 줄을 trim해 채택. 없으면 `""`.
- [x] wire/domain 형태
  - Status: resolved(기본값 채택) — wire `plans[].summary`는 optional(구 CLI 출력 호환), domain `Plan.summary`는 required(ACL이 `""` 정규화). task-level summary 필드는 추가하지 않는다(companion은 plans를 소비).
- [x] JSON Schema/public contract 동기화
  - Status: resolved(repo evidence) — schema v1을 유지하고 `packages/contract/schema/workbranch-list.schema.json`의 `$defs.plan.properties.summary`에 optional string을 추가한다. `additionalProperties: false`이므로 TypeScript DTO만 바꾸면 live CLI contract test가 실패한다. 기존 fixture는 summary 생략 호환을 유지하고, plan fixture 한 건은 summary 포함 형태를 검증한다.
- [x] `.tsx` test fixture 검증 방식
  - Status: resolved(repo evidence) — 이번 slice에서 `tsconfig.json`의 기존 `tests/**/*.ts` 범위를 넓히지 않는다. `tests/**/*.tsx`를 포함하면 기존 `activity-calendar.test.tsx`의 별도 strict 오류까지 범위가 확장되므로, `stage-board.test.tsx`의 `Plan.summary` fixture는 Task 4에서 명시적으로 갱신하고 Vitest rendering/unit test로 보호한다. typecheck가 `.tsx` fixture까지 검증한다고 주장하지 않는다.
- [x] partial-success 가시성 범위
  - Status: resolved(repo evidence) — “모든 task”는 `list --global --json`의 성공한 `projects[]`에서 로드된 모든 task를 뜻한다. `errors[]`에 unavailable root가 있어도 성공한 active/idle row는 유지하고, 실패한 root의 task 수는 추정하지 않는다.
- [x] 기존 workspace rollout 범위
  - Options: A) 신규 workspace부터 적용하고 기존 workspace는 자동 수정하지 않음, B) 기존 `AGENTS.md`에 migration/backfill 수행.
  - Status: resolved(user) — A. 기존 호환성/backfill은 고려하지 않고 신규 workspace부터 적용한다. 기존 `AGENTS.md`와 brief는 수정·재생성하지 않으며, 기존 brief에 사용자가 summary를 직접 추가한 경우 parser가 읽는 것만 허용한다.
- [x] 최종 QA surface
  - Options: A) 실제 Tauri 앱에서 native action을 검증하고 deterministic Chrome capture로 두 theme/compact layout을 보완, B) deterministic Chrome capture + Vitest callback만 사용.
  - Status: resolved(user) — A. 실제 Tauri 앱에서 idle Terminal/Finder, repo-bearing IDE, repo-less IDE disabled를 검증한다. Claude/Codex 두 theme와 520px/460px layout·overflow는 deterministic Chrome capture로 반복 가능하게 검증한다.
- [x] 현재 작업 줄 폴백 순서
  - Status: resolved(기본값 채택) — `currentItem → summary → (task명과 다른) plan title → 생략`. checklist가 있으면 지금처럼 현재 항목이 우선한다.
- [x] IDLE row 구성·정렬
  - Status: resolved(기본값 채택) — `› task명 · StatusToken · 첫 repo@branch(+N) · 경과시간 · actions` 한 줄. 최근 활동(`latestActivityAt`) 내림차순. 선택(selection) 대상에는 포함하지 않고 action 버튼만 제공한다. repo가 없으면 branch 자리는 비운다.
- [x] IDLE 헤더 형태
  - Status: resolved(기본값 채택) — 기존 stage 헤더 레이아웃 재사용하되 번호 pill은 lifecycle 단계가 아니므로 `–`(dim), label `IDLE`, count는 idle 수. 기존 `IDLE N · inactive` footer 텍스트는 제거한다.

## 결정 사항

### D1. summary는 CLI가 파싱해 wire로 내려준다

- `task_load_plans`가 `TASK_PLAN_SUMMARIES[]`를 채운다: plan별로 첫 checklist 이전(`TASK_PLAN_TOTAL == 0`), 아직 summary가 없고, 공백이 아니며 `-`로 시작하지 않는 첫 줄을 trim해 저장.
- `task_plans_json`이 `"summary"` key를 `currentItem` 뒤에 출력한다. plans 전체 dict를 비교하는 기존 테스트는 `"summary":""`를 포함하도록 갱신한다.
- `status:` 줄은 기존 분기가 먼저 consume하므로 summary로 잡히지 않는다. checklist 이후 본문(회고/노트)은 summary가 아니다.

### D2. companion은 summary를 required 필드로 정규화한다

- contract `WorkbranchPlan.summary?: string` (optional — 구 CLI JSON 호환).
- JSON Schema `$defs.plan.properties.summary`도 optional string으로 추가하고 `required`에는 넣지 않는다. 기존 CLI 출력(summary 없음)과 신규 CLI 출력(summary 있음)을 모두 schema v1로 수용한다.
- `parseContract.isPlan`: `isOptionalString(value["summary"])` 검증.
- domain `Plan.summary: string` (required) — `mapPlan`은 `dto.summary ?? ""`, `legacyPlan`은 `""`.
- `Plan` 리터럴을 만드는 모든 테스트 fixture에 `summary` 필드를 추가한다(typecheck 계약).
- `activity.ts`의 `planSignature`에는 summary를 넣지 않는다 — summary 변경만으로 activity event를 만들지 않는다(범위 밖).

### D3. 현재 작업 줄은 폴백 체인이다

```ts
export function currentWorkText(task: Task): string {
	const plan = activePlan(task);
	if (plan === undefined) return "";
	if (plan.currentItem !== "") return plan.currentItem;
	if (plan.summary !== "") return plan.summary;
	return plan.title === task.name ? "" : plan.title;
}
```

렌더링 위치·스타일(`.stage-current-line`, `└` + 11px `--muted` ellipsis)은 기존 계약 그대로다.

### D4. commit 라벨은 아이콘이 대체한다

- `StageRepoRow`의 commit 줄: `last commit: ` 문자열 프리픽스 제거 → inline SVG 아이콘 + `<subject> · <relative>`.
- 컨테이너에 `title="last commit: <subject>"` 유지, 아이콘은 `aria-hidden`, 텍스트 span 앞에 시각적으로만 선행. 스크린리더용으로 `aria-label="last commit"`을 줄에 부여한다.
- subject가 비면 기존처럼 줄 자체를 생략한다.

### D5. idle task는 IDLE 섹션의 compact row다

- `MainViewModel.idleRows: readonly MainTaskRow[]` 추가 — `role === "idle"`인 row를 `latestActivityAt` 내림차순(동률이면 wire 순) 정렬. `idleCount === idleRows.length` 불변식 유지.
- `StageBoard`는 `idleRows` prop을 받아 REVIEW 그룹 아래 IDLE 섹션을 렌더링한다. idle이 0이면 섹션 전체 생략.
- row 내용: `›` prompt marker(dim) · task명 · `StatusToken` · 첫 repo `@` branch(추가 repo는 ` +N`) · 마지막 활동 경과시간(`formatRelativeTime(latestActivityAt)`) · IDE/터미널/Finder 버튼(기존 `taskActionsFor` 재사용, repo 없으면 IDE disabled).
- 기존 `.stage-idle-count` footer(`IDLE N · inactive`)는 삭제한다.

### D6. 생성되는 AGENTS.md가 summary를 요구한다

"작업 진행 업데이트 규칙" / "Task progress update protocol" 섹션에 각각 추가:

- KO: `` `status:` 바로 아래에 지금 하는 일을 나타내는 요약 한 줄을 유지하고, 작업 내용이 바뀌면 갱신합니다.``
- EN: ``Keep a one-line summary of the current work directly below `status:`, and refresh it when the focus changes.``

기존 workspace의 AGENTS.md와 brief는 재생성·migration하지 않는다. 신규 task에서 생성되는 AGENTS.md부터 적용하며, 기존 brief에 summary가 이미 있거나 사용자가 직접 추가한 경우에는 동일 parser가 읽는다.

## UI 가이드

승인 mockup의 계약을 구현 기준으로 옮긴다. 모든 값은 기존 theme token을 사용하며 신규 색상 token은 없다.

### 레이아웃 구조

```text
┌ .stage-board ────────────────────────────────────────┐
│ WORKTREE STATUS 2                                    │
│ 01 PLAN ────────────────────────────────────────── 0 │
│ 02 EXECUTION ───────────────────────────────────── 2 │
│  › feature-cpq-task-b  ● TODO  DERIVED    [actions]  │
│    └ CPQ 정책 CLI 프리셋을 견적 승인 플로우에 연동      │  ← summary 폴백
│    backend ● feature/cpq-task-b     DIRTY 1 FILE  ✎  │
│      ⊙ feat(cpq): Agent AI Policy CLI에 … · 2h       │  ← 아이콘 + subject
│ 03 REVIEW ──────────────────────────────────────── 0 │
│ –  IDLE ────────────────────────────────────────── 4 │  ← 신규 섹션
│  › feat-add-title   ● TODO  workbranch @ feat/… · 1h │  ← .stage-idle-row
│  › fix-noti-badge   ● TODO  tasteful-todo @ … · 3d   │     (우측에 compact actions)
│  › chore-deps-bump  ● DONE  backend @ … · 5d         │
│  › docs-readme-ko   ● TODO  workbranch @ … · 12d     │
└──────────────────────────────────────────────────────┘
```

### Commit 줄 (`.stage-repo-commit`)

| 요소 | 스펙 |
|---|---|
| 아이콘 | inline SVG 20×20 viewBox, `circle cx=10 cy=10 r=3.2` + `M1.5 10h5.3` / `M13.2 10h5.3`, stroke `currentColor` 1.6, 렌더 크기 13px, `aria-hidden`, flex `none` |
| 텍스트 | `<subject> · <relative>` 10px `--faint`, 한 줄 ellipsis |
| 컨테이너 | flex, gap 5px, `title="last commit: <subject>"`, `aria-label="last commit"` |

### IDLE 섹션

| 요소 | 스펙 |
|---|---|
| 헤더 | `.stage-group-head` 레이아웃 재사용, `data-column="idle"`. 번호 pill `–` 배경 `--surface-3` 색 `--faint`, label `IDLE` 색 `--faint`, rule + count 기존 스펙 |
| row | grid: `10px(›) · auto(task명) · auto(status) · minmax(0,1fr)(repo@branch) · auto(경과) · 76px(actions)`, gap 7px, padding `6px 2px`, row 사이 옅은 rule(`--line` 55%), 전체 `opacity 0.78` |
| task명 | 11px 500(활성 600과 구분), ellipsis + `title` 원문 |
| repo@branch | `<repo> @ <branch>` 10px `--faint` ellipsis, repo 2개 이상이면 ` +N` |
| 경과시간 | 10px `--faint` tabular-nums, 우측 정렬 |
| actions | 기존 `.stage-actions` 시각 언어, 폭 76px·버튼 `min-height 24px`·아이콘 12px compact variant. aria-label 기존 포맷(`open <task> in IDE` 등) 유지, repo 없으면 IDE disabled |

### 타이포그래피·접근성

- 10px 미만 금지 규칙 유지. 신규 selector: `.stage-idle-row` 본문 11px/보조 10px.
- 모든 focusable에 `:focus-visible` outline `2px solid var(--accent)` — idle action 버튼 포함.
- 가로 overflow 금지: idle row의 branch·task명 `min-width: 0` + ellipsis + `title`.
- 신규 애니메이션 없음(`prefers-reduced-motion` 계약 변동 없음).

## 범위 밖

- 현재 작업 줄의 최신 커밋 폴백(기각된 option B), task-level summary wire 필드
- summary 변경의 activity event 반영, Activity/Settings 뷰 변경
- Rust/Tauri command·state 변경, 새 dependency
- 기존 workspace AGENTS.md/brief migration 또는 재생성, `TASK-WORKBRANCH.md` 기본 템플릿 변경(summary 줄은 신규 workspace의 agent가 작성)
- idle row의 선택(selection)·상세 패널 연동

## 변경 파일 구조

```text
apps/cli/src/workbranch/lib/task-state.sh    # summary 파싱 + plans JSON + AGENTS 템플릿 지침
apps/cli/tests/cases/list-json.sh            # summary wire 계약 tests
apps/cli/tests/cases/memo.sh                 # 템플릿 지침 tests
apps/cli/tests/run.sh                        # 신규 test 등록
packages/contract/src/index.ts               # WorkbranchPlan.summary?: string
packages/contract/schema/workbranch-list.schema.json # plan.summary optional schema v1 계약
packages/contract/fixtures/list-with-plans.json       # summary 포함 fixture
packages/contract/tests/contract.test.mjs             # fixture + live CLI schema 계약
apps/companion/src/infrastructure/parseContract.ts  # isPlan summary 검증
apps/companion/src/infrastructure/acl.ts     # mapPlan/legacyPlan summary 정규화
apps/companion/src/domain/model.ts           # Plan.summary: string
apps/companion/src/ui/TaskRow.tsx            # currentWorkText summary 폴백
apps/companion/src/ui/StageBoard.tsx         # commit 아이콘, IDLE 섹션, idleRows prop
apps/companion/src/application/state.ts      # MainViewModel.idleRows
apps/companion/src/App.tsx                   # idleRows 배선
apps/companion/src/styles/stage-board.css    # commit 아이콘·idle row 스타일, .stage-idle-count 삭제
apps/companion/tests/acl.test.ts             # summary 매핑 계약
apps/companion/tests/model.test.ts           # idleRows 계약 + fixture summary
apps/companion/tests/stage-board.test.tsx    # 아이콘/IDLE/폴백 rendering 계약 + fixture summary
apps/companion/tests/app-shell.test.tsx      # idleRows 배선·CSS 계약
apps/companion/tests/activity-refresh.test.ts # fixture summary (typecheck)
```

---

### Task 1: CLI plan summary 파싱 (red → green)

**Files:**
- Modify: `apps/cli/tests/cases/list-json.sh`, `apps/cli/tests/run.sh`
- Modify: `apps/cli/src/workbranch/lib/task-state.sh`

- [x] **Step 1: failing test 작성** — `test_list_json_plan_summary`(첫 본문 줄 채택, checklist 이후 본문 무시), `test_list_json_plan_summary_absent_is_empty`(status-only brief → `""`)를 추가하고 run.sh에 등록했다.
- [x] **Step 2: red 확인** — 두 test 모두 `KeyError: 'summary'`로 FAIL.
- [x] **Step 3: 구현** — `TASK_PLAN_SUMMARIES` 배열(reset/add 초기화), checklist 분기 앞 summary 캡처 분기, `task_plans_json`의 `"summary"` 출력, plans 전체 비교 기존 test에 `"summary":""` 반영.
- [x] **Step 4: green 확인** — 재빌드 후 신규 2건 + 인접 3건(`implicit_and_empty_plans`, `plan_sections_shape_and_aggregate`, `progress_and_status`) PASS.

### Task 2: 생성 AGENTS.md summary 지침 (red → green)

**Files:**
- Modify: `apps/cli/tests/cases/memo.sh`
- Modify: `apps/cli/src/workbranch/lib/task-state.sh`

- [x] **Step 1: failing test 작성** — EN/KO 템플릿 test에 D6 지침 문구 `assert_contains` 추가.
- [x] **Step 2: red 확인** — 두 test FAIL.
- [x] **Step 3: 구현 + green** — KO/EN 템플릿에 지침 추가, 재빌드 후 2건 PASS.

### Task 3: contract → domain summary 전파 (red → green)

**Files:**
- Modify: `apps/companion/tests/acl.test.ts`
- Modify: `packages/contract/src/index.ts`, `packages/contract/schema/workbranch-list.schema.json`, `packages/contract/fixtures/list-with-plans.json`, `packages/contract/tests/contract.test.mjs`
- Modify: `apps/companion/src/infrastructure/parseContract.ts`, `apps/companion/src/infrastructure/acl.ts`, `apps/companion/src/domain/model.ts`

- [x] **Step 1: failing test 작성** — parse→map 경유로 `plans[0].summary` 전파, 생략 시 `""` 정규화 test 추가.
- [x] **Step 2: red 확인** — `plans?.[0]?.summary` undefined FAIL.
- [x] **Step 3: 구현 + green** — D2대로 contract/parse/domain/ACL 수정, acl 6 tests PASS.
- [x] **Step 4: published schema red → green** — live CLI contract test 2건의 `additionalProperty: "summary"` FAIL을 red로 확인한 뒤 schema v1의 plan properties에 optional `summary`를 추가하고 fixture를 갱신했다. contract 3 tests, typecheck, lint PASS.

### Task 4: currentWorkText summary 폴백 + fixture summary 일괄 반영 (red → green)

**Files:**
- Modify: `apps/companion/tests/stage-board.test.tsx` (unit test 추가)
- Modify: `apps/companion/src/ui/TaskRow.tsx`
- Modify: `apps/companion/tests/model.test.ts`, `apps/companion/tests/activity-refresh.test.ts`, `apps/companion/tests/stage-board.test.tsx` (Plan fixture에 `summary` 추가)

- [x] **Step 1: failing test 작성** — `currentWorkText` 직접 unit test로 currentItem 우선 / summary 폴백 / (task명과 다른) title 최후 폴백 / 전부 비면 `""`를 추가했다.
- [x] **Step 2: red 확인** — summary 폴백 case가 `Brief summary` 대신 `Implementation plan`을 반환해 FAIL하는 것을 확인했다.
- [x] **Step 3: 구현** — D3 폴백 체인을 최소 변경으로 구현했다.
- [x] **Step 4: green + typecheck** — stage-board 7 tests와 Companion typecheck PASS. `.ts` fixture와 `stage-board.test.tsx` fixture에 `summary`를 명시했으며, 기존 tsconfig가 `.tsx` tests를 typecheck하지 않는 한계는 유지한다.

### Task 5: commit 라벨 아이콘화 (red → green)

**Files:**
- Modify: `apps/companion/tests/stage-board.test.tsx`
- Modify: `apps/companion/src/ui/StageBoard.tsx`, `apps/companion/src/styles/stage-board.css`

- [x] **Step 1: failing test 작성** — visible text의 `last commit:` 부재, commit icon, tooltip title, subject + relative text 유지 계약을 추가했다.
- [x] **Step 2: red 확인** — 기존 visible `last commit:` prefix 때문에 stage-board test가 FAIL하는 것을 확인했다.
- [x] **Step 3: 구현 + green** — `StageRepoRow`를 inline commit SVG + subject/relative text로 바꾸고 flex/icon 스타일을 적용했다. stage-board 7 tests와 Companion typecheck PASS.

### Task 6: idleRows projection과 IDLE 섹션 (red → green)

**Files:**
- Modify: `apps/companion/tests/model.test.ts`, `apps/companion/tests/stage-board.test.tsx`, `apps/companion/tests/app-shell.test.tsx`
- Modify: `apps/companion/src/application/state.ts`, `apps/companion/src/ui/StageBoard.tsx`, `apps/companion/src/App.tsx`, `apps/companion/src/styles/stage-board.css`

- [x] **Step 1: failing model test 작성** — clean todo/done 최신 활동순, 동일 timestamp wire 순서, `idleCount === idleRows.length` 계약을 추가했다.
- [x] **Step 1a: partial-success model test** — unavailable root error가 있어도 성공한 idle row가 유지되는 계약을 추가했다.
- [x] **Step 2: red → 구현 → green** — `idleRows` 부재로 model 3 tests가 FAIL하는 것을 확인한 뒤 projection과 안정 정렬을 구현했다. model 13 tests와 typecheck PASS.
- [x] **Step 3: failing stage-board test 작성** — IDLE header/order/task/repo/terminal action/footer 제거/idle 0 생략 계약을 추가하고 IDLE header 부재 FAIL을 확인했다.
- [x] **Step 4: red → 구현 → green** — `StageBoardProps.idleRows`, compact IDLE row/header/actions/CSS를 구현하고 App에 배선했다.
- [x] **Step 5: app-shell 계약 갱신** — `idleRows={main.idleRows}` source contract를 추가했다. model/stage-board/app-shell 49 tests와 Companion typecheck PASS.

### Task 7: 전체 검증과 실제 앱 QA

- [x] **Step 1: stale contract 스캔** — production source에서 `stage-idle-count` 0건. visible `last commit:` 부재는 targeted rendering test로 PASS.
- [x] **Step 2: quality gates** — Companion 15 files/151 tests, typecheck, lint, Vite build, Tauri release bundle, contract 3 tests/typecheck/lint, CLI 286 tests, `git diff --check` PASS:

```bash
pnpm --filter @workbranch/companion test
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
pnpm --filter @workbranch/companion build
pnpm companion:build
pnpm --filter @workbranch/contract test
pnpm --filter @workbranch/contract typecheck
pnpm --filter @workbranch/contract lint
apps/cli/tests/run.sh
git -C . diff --check
```

- [x] **Step 3: 실제 Tauri app native-action QA** — fresh release app과 현재 CLI를 연결해 실제 성공 경계를 확인했다:
  - 신규-format brief의 summary가 active task 아래 `└ <summary>`로 보이고, checklist를 추가하면 current item이 summary를 대체한다.
  - idle row의 Terminal/Finder가 해당 task root를 실제로 열고, repo-bearing IDE가 configured launcher를 호출한다.
  - repo-less task의 IDE는 disabled이고 Terminal/Finder는 계속 동작한다.
- [x] **Step 4: deterministic Chrome visual QA (두 theme × 520px/460px)** — production StageBoard/CSS harness에서 summary/currentItem precedence, Korean/CJK commit text, commit icon, IDLE rows, repo-less IDE disabled, focus-visible, ellipsis를 확인했다. 두 width 모두 document overflow 없음, 76px action group이 board 안에 유지됨. independent visual reviewer PASS.
- [x] **Step 5: DESIGN.md Direction revision 추가** — IDLE inventory, commit icon, summary fallback, 신규 workspace rollout 계약을 design history에 기록했다.

## 완료 기준

- [x] `list --global --json`에서 성공적으로 로드된 모든 task가 Main에 보인다: active는 stage 그룹, idle은 하단 IDLE 섹션 compact row. unavailable root는 기존 error surface로 남고 그 task 수는 추정하지 않는다. `IDLE N · inactive` footer는 없다.
- [x] repo 줄의 commit 정보가 아이콘 + subject + 상대시간 한 줄이고 tooltip/aria로 의미가 유지된다.
- [x] brief `status:` 아래 요약 한 줄이 CLI JSON `plans[].summary`로 내려오고, checklist가 없어도 `└` 현재 작업 줄에 표시된다. 구 CLI 출력(summary 없음)도 파싱된다.
- [x] 신규 task의 AGENTS.md가 KO/EN 모두에서 summary 유지 지침을 포함한다. 기존 workspace 파일은 변경하지 않는다.
- [x] 실제 Tauri 앱에서 idle Terminal/Finder와 repo-bearing IDE 경로 전달을 확인했고, deterministic production harness에서 repo-less IDE disabled를 확인했다. 두 theme의 520px/460px capture에 horizontal overflow가 없다.
- [x] CLI 전체 suite, contract test/typecheck/lint, companion full tests/typecheck/lint/Vite build/Tauri build, `git diff --check`가 전부 통과한다.

## 진행 현황 (2026-08-31)

- Task 1–3 완료. Task 3은 DTO/parse/ACL과 published JSON Schema/fixture를 동기화했고 contract 3 tests, typecheck, lint가 green이다.
- Task 4 완료. currentItem/summary/title/blank precedence targeted 7 tests와 Companion typecheck가 green이다.
- Task 5 완료. visible label 제거와 icon/tooltip/subject 계약이 targeted 7 tests 및 typecheck로 green이다.
- Task 6 완료. idle projection/order/partial-success와 IDLE render/App wiring targeted 49 tests 및 typecheck가 green이다.
- Task 7 완료. Native evidence: idle Terminal `/Users/tommyhwang/Documents/git/monask-fullstack/feature-cpq-task-c`, Finder 동일 task root, IDE backend/frontend 경로 전달 PASS. Visual evidence: `/tmp/workbranch-0056-{claude,codex}-{520,460}.png`, `/tmp/workbranch-0056-visual-metrics.json`; independent code fidelity APPROVE와 visual QA PASS.
