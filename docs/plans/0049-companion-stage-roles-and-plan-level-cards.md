# 0049 Companion stage board 역할 라벨 + plan-level 카드 + planning-only PLAN

> **agentic worker 지침:** 실행 시 `superpowers:executing-plans`를 사용한다. 동작 변경 전에는 `superpowers:test-driven-development`(red → green → refactor)를 따른다. 이 plan은 **Companion(React) 전용** slice다 — CLI/contract/Tauri는 건드리지 않는다. `apps/companion`에서 `pnpm test` + `pnpm typecheck` + `pnpm lint`로 검증한다. Step은 checkbox(`- [ ]`)로 추적한다.
>
> **시리즈 위치:** 0048이 stage-first 칸반(StageBoard)과 status-only agent 프로토콜을 만들었다. 이 slice는 그 보드의 **정보 밀도를 올리고 신호를 정제한다**: (1) stage별 AI/사람 역할 라벨, (2) 카드에 plan-level 컨텍스트(active plan 제목 + repo 칩), (3) PLAN 컬럼을 "지금 planning 중"으로 한정. 현재 branch의 Companion baseline은 131 tests green이며, 이 plan의 Decision Gates를 모두 닫은 뒤 구현을 시작한다.

**목표:** StageBoard 상단을 보드 전체가 공유하는 하나의 2행 header(stage 이름 / 역할 라벨)로 만들고, 카드에 active plan 제목과 repo 칩을 추가하며, PLAN 컬럼에서 `todo`(activity 없음)를 제외해 `planning`(지금 계획 중)만 표시한다.

## 배경 (2026-08-17)

0048 이후 보드 카드는 project 라벨 + task 이름 + (blocked/progress/`+N`)만 표시한다. 사용자 피드백 두 건:

1. **"너무 정보가 없어."** 각 stage에서 AI와 사람(ME)의 역할이 안 보이고, 카드만 봐서는 그 task가 어떤 작업인지 알 수 없다. 단, 과거처럼 step/status를 매번 갱신하는 노이즈는 원치 않는다 — **plan level까지만**. 이는 DESIGN.md의 "Stage beats step detail" 원칙과 일치한다.
2. **"PLAN에는 지금 planning 하고 있는 것만 표시하고 싶어."** 현재 `todo`와 `planning`이 모두 PLAN 컬럼에 들어가서, 만들어만 두고 손대지 않은 task 다수가 실제로 움직이는 task를 가린다. `status:` 어휘가 이미 이 구분을 제공한다(`todo`=대기, `planning`=계획 중 — 0048 D1 프로토콜).

필요한 데이터는 전부 이미 카드까지 내려와 있다: `Task.plans[].title`(brief H1), `Task.repos[]`(name/branch/dirty — agent 비용 0). **CLI·contract·파서 변경은 불필요하다.**

## 결정 사항 (2026-08-17, 사용자 확정)

> **D1. 역할 라벨은 `ME` 표기.** 컬럼별 고정 매핑: PLAN `AI·ME` · EXECUTION `AI` · REVIEW `ME`. 대안 `I`(한 글자라 시인성 낮고 l/1과 혼동), `HUMAN`(좁은 컬럼에 과도)은 기각. AI와 같은 2글자라 대칭이다. 라벨은 정적 개념(도구의 워크플로 모델)이므로 하드코딩한다.
>
> **D2. 카드의 "무슨 작업인지"는 active plan 제목 한 줄.** `activePlan(task).title`을 task 이름 아래 표시한다. 단 **제목이 task 이름과 같으면 숨긴다** — 기본 brief 템플릿이 `# <task>`라서 fresh task는 중복 줄이 되기 때문. plan 제목은 새 Plan이 시작될 때만 바뀌므로 step-level 노이즈가 없다. 단일 라인 ellipsis + `title` tooltip, `▸ ` prefix는 CSS `::before`로 붙인다(DOM 텍스트는 제목만).
>
> **D3. repo 칩은 이름 + dirty dot만, branch는 tooltip.** 460px 3컬럼(컬럼당 ~140px)에서 branch 텍스트는 들어가지 않는다. 칩 텍스트는 repo 이름만, dirty면 `●`(notify 색), `title="<name> <branch> dirty|clean"`으로 branch를 보조 제공한다. TaskMetaRow의 RepoChips(이름+branch 2컬럼 grid)와는 다른 보드 전용 컴팩트 컴포넌트로 만들고, class도 `stage-card-repo*`로 분리해 surface별 CSS ownership(0048)을 지킨다.
>
> **D4. PLAN 컬럼은 `planning`만. `todo`는 board 제외.** `taskStage()` 매핑을 `todo → undefined`로 바꾼다(`done`과 동일 처리). todo task는 0048 D4의 done과 똑같이 하단 TaskMetaRow에 남아 IDE/Terminal/Finder 재접근이 가능하다. agent가 planning을 시작해 `status: planning`으로 올리는 순간 카드가 PLAN에 나타난다 — "지금 움직이는 것만 보이는" 보드.
>
> **D5. stage/role은 StageBoard 전체가 공유하는 하나의 2행 header로 표시.** 각 `.stage-column` 안에 독립 header를 반복하지 않는다. `.stage-board-header` 하나가 3열 grid를 이루고, 첫 행은 `PLAN | EXECUTION | REVIEW`, 둘째 행은 `AI·ME | AI | ME`를 같은 열 축에 맞춰 표시한다. header와 카드 영역은 모두 동일한 `repeat(3, minmax(0, 1fr))`과 6px column gap을 사용하고, header 바깥선은 track 폭을 줄이지 않는 inset shadow로 표현해 세 칸이 하나의 header surface로 읽혀야 한다.
>
> **D6. stage별 카드 count는 유지하되 역할보다 약하게 표시.** 각 heading cell의 둘째 행은 role을 왼쪽, count를 오른쪽에 두는 `.stage-board-heading-meta` flex row로 구성한다. count는 기존 정보를 보존하되 `var(--faint)`, tabular numeral, 10px로 낮춰 `AI·ME`/`AI`/`ME`가 주 신호로 읽히게 한다.

## Decision Gates

- [x] 역할 라벨 표기 (`ME` vs `I` vs `HUMAN`)
  - Status: resolved — 사용자 선택 `ME` (2026-08-17).
- [x] 카드 정보의 출처 (기존 데이터 vs repo별 한 줄 요약 신설)
  - Impact: companion-only 변경이냐, brief 포맷+CLI 파서+contract까지 확장이냐.
  - Status: resolved — 사용자 선택 A: 기존 데이터(plan 제목 + repo 칩)만 사용. repo별 서술 필드 신설은 하지 않는다.
- [x] board에서 빠진 `todo` task의 행방
  - Status: resolved by 0048 D4 pattern — done과 동일하게 TaskMetaRow에 유지. 별도 컬럼/딤 처리 없음.
- [x] stage/role header 구조 (컬럼별 header vs 보드 공통 header)
  - Impact: 460px에서 stage/role의 시각적 그룹과 StageBoard DOM/CSS 구조.
  - Current evidence: 기존 구현은 각 `.stage-column` 안에 header를 두지만, 사용자 확정안은 보드 전체가 하나의 header로 읽히는 2행 구조다.
  - Status: resolved — 사용자 선택: `.stage-board-header` 하나 + 3열 정렬 + stage/role 2행.
- [x] stage별 카드 count 표시 여부와 위치
  - Impact: 공통 2행 header의 정보 밀도와 정렬 계약.
  - Current evidence: 기존 UI는 각 컬럼 count를 표시하지만, 확정된 2행 스케치에는 count가 없다.
  - Status: resolved — 사용자 선택 B. 둘째 행에서 role 오른쪽에 낮은 강조도의 count를 유지한다.

## Global Constraints

- Companion: TS/TSX 탭 들여쓰기 + biome, readonly type/순수 함수 idiom. 테스트는 DOM 없이 `renderToStaticMarkup`. 새 의존성 금지.
- CLI(`apps/cli`), `packages/contract`, 파서(`parseContract.ts`), Tauri(Rust)는 변경하지 않는다.
- `parseContract.ts`의 기존 `useLiteralKeys` biome **info** 42건은 이 slice와 무관하다 — 수정하지 말 것(scope 밖).
- biome formatter가 긴 시그니처/삼항을 다중 라인으로 강제한다 — green 후 `npx biome format --write`로 정리하고 lint를 error 0으로 맞춘다.
- DESIGN.md의 최소 폰트 10px 규칙 유지(새 텍스트 전부 10px 이상).

## public contract (변경 / 비변경)

### 변경하는 것
- Companion `taskStage()` 매핑: `todo`가 board stage 없음(undefined)이 된다.
- StageBoard 렌더 구조: 보드 공통 2행/3열 header + 그 아래 카드 컬럼, 카드에 plan 제목/repo 칩 추가.

### 변경하지 않는 것
- `status:` 어휘와 brief 파싱 규칙, schema v1 JSON, `@workbranch/contract`.
- TaskMetaRow/ProjectGroup/summary 카운트(`buildMenuModel`) — todo는 여전히 목록·카운트에 포함.
- 0048의 done 처리, blocked 배지, `+N` 배지, full-name wrapping.

## 파일 구조 (touched)

```text
apps/companion/src/domain/model.ts             # taskStage: todo → undefined (done과 같은 분기로 이동)
apps/companion/src/ui/StageBoard.tsx           # STAGE_ROLES 상수, 공통 StageBoardHeader, 카드 plan 제목 + StageCardRepos
apps/companion/src/styles/stage-board.css      # stage-board-header/-heading/-role/-count, stage-card-plan(::before "▸ "), stage-card-repo*
apps/companion/tests/model.test.ts             # taskStage 매핑, buildBoardModel todo 제외
apps/companion/tests/task-row.test.tsx         # 역할 라벨, plan 제목/중복 숨김, repo 칩, todo 보드 부재, CSS 계약
DESIGN.md                                      # "Done visibility" 문단 → "Todo/done visibility"로 확장 (94행 부근)
```

---

### Task 1: PLAN 컬럼 planning-only (D4)

**Red:** `tests/model.test.ts` — `taskStage` it.each에서 `["todo", "plan"]` → `["todo", undefined]`. `buildBoardModel` 테스트에서 plan 컬럼 기대를 `["planning-new"]`만으로 축소(기존 `"todo-old"` 제거), 테스트명을 "…excluding todo and done"으로 갱신. `tests/task-row.test.tsx` — 공유 state에 `status: "todo"`인 `todoTask` fixture를 추가하고 board html에 `"todo-task"` 부재를 고정하는 테스트 신설.

**Green:** `src/domain/model.ts`의 `taskStage()` switch에서 `case "todo"`를 `case "done"` 옆(undefined 반환)으로 이동. `buildBoardModel`은 stage undefined를 이미 skip하므로 다른 변경 불필요.

- [x] red 확인 (매핑/보드 테스트 3건이 기존 `todo → plan` 동작 때문에 실패)
- [x] green: targeted 19 tests + typecheck 통과

### Task 2: 보드 공통 2행 stage/role/count header (D1, D5, D6)

**Red:** `tests/task-row.test.tsx` StageBoard describe에 다음 구조를 고정한다.
- `.stage-board-header`는 DOM에 정확히 하나만 존재하고, `.stage-column-header`는 존재하지 않는다.
- header 안에 3개의 `.stage-board-heading`이 있고 각각 `PLAN`+`AI·ME`, `EXECUTION`+`AI`, `REVIEW`+`ME`를 같은 cell 안에 렌더한다.
- CSS 계약은 parent와 `.stage-board-header`가 동일한 `repeat(3, minmax(0, 1fr))` + `column-gap: 6px`를 사용하고, parent의 `row-gap: 6px`은 별도로 유지함을 고정한다. header 외곽선은 track 폭에 영향을 주지 않는 `box-shadow: inset 0 0 0 1px var(--line)`으로 고정한다.
- 각 `.stage-board-heading-meta` 안에서 role 뒤에 현재 column의 카드 count가 렌더되고, PLAN/EXECUTION/REVIEW fixture가 각각 기대 count를 표시함을 고정한다.
- `.stage-board-heading-meta`는 flex row, `.stage-board-count`는 `margin-left: auto`, `font-variant-numeric: tabular-nums`, 10px, `var(--faint)`를 사용함을 CSS 계약으로 고정한다.

**Green:** `StageBoard.tsx`에 `const STAGE_ROLES: Record<TaskStage, string> = { plan: "AI·ME", execution: "AI", review: "ME" }`. `StageBoard`의 첫 child로 `<header className="stage-board-header">`를 두고, `board.columns`를 순회해 각 `.stage-board-heading` 안에 `<h2>{label}</h2>`와 둘째 행 `<div className="stage-board-heading-meta"><span className="stage-board-role">…</span><span className="stage-board-count">{column.cards.length}</span></div>`를 렌더한다. 기존 `.stage-column-header`는 제거하고 각 `.stage-column`은 카드 목록만 소유한다. header와 카드 영역은 모두 `repeat(3, minmax(0, 1fr))` + 6px column gap을 사용해 열 축을 공유한다. CSS는 header 전체에 하나의 background/inset border를 적용하고, heading cell 사이에는 가벼운 vertical divider만 둔다. role은 muted, count는 faint로 시각적 우선순위를 분리한다.

- [x] red 확인 (공통 header DOM/CSS 계약 2건이 기존 컬럼별 header 때문에 실패)
- [x] green: targeted 12 tests + typecheck 통과

### Task 3: 카드 plan 제목 + repo 칩 (D2, D3)

**Red:** `tests/task-row.test.tsx` —
- plan 제목: html이 `'class="stage-card-plan" title="Generated Plan">Generated Plan</span>'` 등 기존 fixture의 plan 제목 span을 포함.
- plan 없음: `plans: []` fixture는 기존 모델 계약상 `todo`로 분류되어 StageCard 생성 전에 board에서 제외됨을 고정하고, `activePlan()`의 `Plan | undefined` 반환은 production guard + typecheck로 증명.
- 중복 숨김: plan 제목 == task 이름인 `freshTask` fixture(**주의: status는 `planning`으로 둘 것** — Task 1 이후 todo는 보드에 안 오르므로 todo면 이 테스트가 공허하게 통과한다)를 추가하고, `'class="stage-card-plan" title="fresh-task"'` 부재를 고정.
- repo 칩: `'class="stage-card-repo stage-card-repo-dirty" title="workbranch feat/update-0617 dirty"'`와 `'class="stage-card-repo" title="docs main clean"'` 포함, `'class="repo-branch-name"'`(branch 텍스트) 부재.
- 긴 repo 이름: 길이 제한이 없는 repo fixture를 추가해 `.stage-card-repo-name` span이 존재하고 dirty dot은 별도 sibling으로 유지됨을 고정.
- CSS 계약: `.stage-card-plan`에 `text-overflow: ellipsis`, `.stage-card-repos`에 `flex-wrap: wrap; min-width: 0`, `.stage-card-repo`에 `max-width: 100%; min-width: 0`, `.stage-card-repo-name`에 `overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0`을 고정.

**Green:** `StageBoard.tsx` —
- `StageCard`에서 `const plan = activePlan(card.task)`; **`plan !== undefined && plan.title !== card.task.name`**일 때만 `<span className="stage-card-plan" title={plan.title}>{plan.title}</span>`를 task 이름 아래 렌더한다. `activePlan()`의 실제 반환 타입 `Plan | undefined`를 non-null assertion이나 type escape 없이 처리한다.
- `StageCardRepos({ repos })` 신설: `repos.length === 0`이면 null, 아니면 `<ul aria-label="repositories" className="stage-card-repos">`에 repo당 `<li className={"stage-card-repo" + (dirty ? " stage-card-repo-dirty" : "")} key={name} title={\`${name} ${branch} ${dirty ? "dirty" : "clean"}\`}>` — 이름은 `<span className="stage-card-repo-name">{name}</span>`으로 감싸 ellipsis owner를 명확히 하고, dirty면 그 sibling으로 `<span className="stage-card-repo-dot" aria-label="dirty" role="img">●</span>`를 추가한다.
- CSS(`stage-board.css`): `.stage-card-plan`(muted, 10px, 단일 라인 ellipsis, `::before { content: "▸ "; color: var(--faint); }`), `.stage-card-repos`(flex wrap, min-width 0, column-gap 6px/row-gap 2px, list reset), `.stage-card-repo`(faint, 10px, inline-flex, max-width 100%, min-width 0), `.stage-card-repo-name`(min-width 0, overflow hidden, 단일 라인 ellipsis), `.stage-card-repo-dirty`/`.stage-card-repo-dot`(`var(--notify)`, dot은 `flex: 0 0 auto`).

- [x] red 확인 (plan/repo DOM과 CSS 계약 2건이 기존 compact card 때문에 실패)
- [x] green: targeted 21 tests + typecheck 통과
- [x] Biome format 적용 + lint error 0 (`parseContract.ts` 기존 info 42건 유지)

### Task 4: 문서 동기화

`DESIGN.md`를 다음 범위로 동기화한다.
- Components의 StageBoard 설명: 보드 전체가 공유하는 2행/3열 stage-role header와 그 아래 카드 3열을 명시.
- StageCard metadata bullet: project/blocked/progress/notification에 active plan 제목과 compact repo name/dirty metadata를 추가.
- "Done visibility" bullet을 다음 취지로 교체: "Todo/done visibility: todo(아직 activity 없음)와 done task는 StageBoard에서 제외하되 TaskMetaRow에는 유지해 IDE/Terminal/Finder 접근을 보장한다; PLAN 컬럼은 planning 중인 task만 표시한다."
- Responsive behavior: 460px에서 header와 카드 영역이 동일한 3열 grid 축을 공유하고, 긴 repo 이름은 칩 내부에서 ellipsis되며 dirty dot은 보존됨을 명시.
- Decision history에 2026-08-17 stage-role header/plan-level card 결정을 한 항목으로 기록.

- [x] DESIGN.md 갱신 (components, metadata, visibility, 460px responsive, decision history)

### Task 5: 전체 검증

- [x] `apps/companion`: 133 tests + typecheck + lint error 0 통과 (`parseContract.ts` 기존 info 42건 유지)
- [x] `pnpm --filter @workbranch/companion build` 통과 (Vite 58 modules)
- [x] 실제 UI QA: `pnpm companion:dev` + Chrome Stable 460×680에서 Claude/Codex Main 캡처 — 공통 2행 header, stage/role/count와 카드 열 정렬, todo board 부재/meta 유지, plan 제목/repo 칩, 긴 repo ellipsis+dirty dot, horizontal overflow 없음. 독립 visual QA 2개 pass.

## 기대 화면 (참고)

```text
┌──────────────────────────────────────────┐
│   PLAN          EXECUTION        REVIEW  │
│  AI·ME   1         AI    1        ME   0 │
├─────────────┬──────────────┬─────────────┤
│ MONASK-…    │ TESTFUL-…    │             │
│ feature-    │ feat-unify-  │             │
│ cpq-task-a  │ mode         │             │
│ ▸ CPQ 견적서 │              │             │
│ frontend    │              │             │
│ backend●    │              │             │
│ 3/7         │              │             │
└─────────────┴──────────────┴─────────────┘
todo 5건은 보드 아래 project별 task 목록에만 표시
```
