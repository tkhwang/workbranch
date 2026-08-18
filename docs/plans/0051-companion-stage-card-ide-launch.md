# 0051 Companion stage card 더블 클릭 IDE 실행

> **agentic worker 지침:** 실행 시 `superpowers:executing-plans`를 사용한다. 동작 변경 전에는 `superpowers:test-driven-development`(red → green → refactor)를 따른다. 이 plan은 **Companion(React) 전용** slice다 — CLI/contract/Tauri(Rust)는 건드리지 않는다. `apps/companion`에서 `pnpm test` + `pnpm typecheck` + `pnpm lint`로 검증한다. Step은 checkbox(`- [ ]`)로 추적한다.
>
> **시리즈 위치:** 0048이 stage-first 칸반(StageBoard)을, 0049가 카드에 plan-level 컨텍스트를 더했다. 이 slice는 카드를 **표시 전용에서 실행 가능한 진입점으로** 바꾼다: 가장 많이 쓰는 동작(해당 task의 코드 변경을 IDE에서 보기)을 보드에서 바로 실행한다. 이 plan의 접근은 2026-08-18에 실제로 프로토타입 구현되어 137 tests green(신규 4 포함) + typecheck + lint까지 확인한 뒤 rollback되었다 — 아래 Task 단계는 검증된 경로다.

**목표:** StageBoard 카드를 **더블 클릭**하면 하단 TaskMetaRow의 IDE 버튼과 동일한 `workbranch_run` `ide` 액션으로 에디터를 실행한다. 키보드(Enter/Space) 접근을 보장하고, hover/tooltip으로 클릭 가능함을 표시한다.

## 배경 / 조사 결과 (2026-08-18)

사용자 피드백: **"가장 많이 쓰이는 기능이 workbranch stage에서 해당 코드 변경을 보는 것"** — 그런데 현재 보드 카드는 표시 전용이라, IDE를 열려면 스크롤해 하단 project 그룹의 TaskMetaRow에서 IDE 버튼을 찾아야 한다.

필요한 배선은 전부 이미 존재한다:

- 실행 경로: `TaskMetaRow` 버튼 → `App.handleTaskAction(root, task, kind)` → `commandForTaskAction` → `runAction({kind:"ide", task}, root)` → Tauri `workbranch_run` (`App.tsx`). **재사용만 하면 되고 새 백엔드/contract 코드는 0이다.**
- `BoardCard`는 이미 `root`와 `task`를 담고 있다 (`application/state.ts`) — StageBoard에 handler prop 하나만 내리면 된다.

프로토타입에서 확인한 함정 2개:

1. **biome a11y 규칙이 `<article role="button">`을 거부한다** — `lint/a11y/useSemanticElements` + `lint/a11y/noNoninteractiveElementToInteractiveRole` 2건 error. 카드 내부에 `<ul>`(repo 칩)이 있어 카드 자체를 `<button>`으로 바꿀 수도 없다(phrasing content 제약). 해법: 카드 전체를 덮는 투명 오버레이 `<button className="stage-card-open">`(absolute inset:0)을 카드 첫 자식으로 두는 표준 접근 카드 패턴. 시맨틱 유효 + lint 통과를 프로토타입에서 확인했다.
2. **더블 클릭은 device-independent 활성화 경로가 아니다** — native `<button>`의 Enter/Space/접근성 API 활성화는 `click`으로 합성되므로 `onClick`을 제거하면 보조기술 경로가 끊긴다. 해법: `onDoubleClick`은 포인터 더블 클릭을 소유하고, `onClick`은 `event.detail === 0`인 native 비포인터 활성화만 처리한다. `detail > 0`인 마우스/포인터 단일 클릭은 무시한다. 별도 `onKeyDown`은 두지 않고 native button semantics를 유지한다.

부수 트레이드오프(수용): 오버레이가 카드를 덮으므로 카드 내부 요소의 개별 tooltip(`stage-card-name`/`stage-card-plan`의 `title`)은 가려지고, 오버레이 자신의 `title="Double-click to open <task> in IDE"`가 대신 표시된다 — 전체 task 이름이 포함되므로 truncation 보조는 유지되고, 사용법 힌트를 겸한다.

## 결정 사항 (2026-08-18, 사용자 확정)

> **D1. 실행 제스처는 더블 클릭.** 단일 클릭 즉시 실행(실수 유발), 카드 내 IDE 버튼 추가(460px 카드 밀도 훼손)를 기각하고 사용자가 더블 클릭을 선택했다. 단일 클릭은 아무 동작도 하지 않는다 — 향후 카드 선택/상세 같은 단일 클릭 동작의 여지도 남는다.
>
> **D2. 기존 `ide` 액션을 그대로 재사용한다.** `StageBoard`에 `onOpenIde(root, task)` prop을 추가하고 `App`에서 `handleTaskAction(root, task, "ide")`로 배선한다. Tauri command·contract·CLI는 무변경.
>
> **D3. 접근성은 오버레이 native button + device-independent `click` 경로로.** `<article>`은 그대로 두고(`role`/`tabIndex` 없음), 오버레이 `<button type="button">`이 `onDoubleClick`으로 포인터 더블 클릭을, `onClick`의 `event.detail === 0` 분기로 Enter/Space·접근성 API 활성화를 소유한다. `detail > 0`인 포인터 단일 클릭은 아무 동작도 하지 않는다. `aria-label="open <task> in IDE"`는 기존 TaskRow 액션의 aria 문구 패턴을 따른다.
>
> **D4. 클릭 가능 신호는 CSS로.** `.stage-card`에 `cursor: pointer` + `position: relative`, hover 시 `--surface-3`/`--line-strong`, 오버레이 `:focus-visible`에 `--accent` outline(inset). 노이즈가 되는 상시 아이콘/배지는 추가하지 않는다.

## Decision Gates

- [x] 실행 제스처 (단일 클릭 vs 더블 클릭 vs 카드 내 버튼)
  - Impact: 오발동 빈도, 460px 카드 정보 밀도, 향후 단일 클릭 동작의 여지.
  - Status: resolved — 사용자 선택 **더블 클릭** (2026-08-18, AskUserQuestion).
- [x] 접근성 구현 패턴 (`article role="button"` vs 카드 전체 `<button>` vs 오버레이 버튼)
  - Impact: biome a11y lint 통과 여부, HTML 유효성(`<ul>` in `<button>` 불가), 키보드 동작.
  - Evidence: 프로토타입에서 `role="button"`은 biome error 2건, 오버레이 패턴은 lint clean 확인.
  - Status: resolved — 오버레이 `<button className="stage-card-open">`.
- [x] native button 활성화 이벤트 (`onKeyDown` 직접 처리 vs device-independent `onClick`)
  - Impact: 물리 키보드뿐 아니라 접근성 API·음성·스위치 입력에서 IDE 실행 가능 여부.
  - Evidence: native button의 비포인터 활성화는 `click`으로 합성되며, 기존 `TaskMetaRow`도 `onClick`을 단일 실행 경로로 사용한다.
  - Status: resolved by platform/repo evidence — `onClick(detail === 0)` + `onDoubleClick`, 별도 `onKeyDown` 없음.
- [x] StageBoard interaction 테스트 배치 (`tests/task-row.test.tsx` 확장 vs `tests/stage-board.test.tsx` 신설)
  - Impact: 새 파일/폴더 계약, 기존 StageBoard fixture·회귀 테스트의 중복 여부.
  - Current evidence: 현재 StageBoard 테스트와 fixture는 `tests/task-row.test.tsx`에 있고, 같은 파일의 기존 `<StageBoard board={...} />` 4곳도 새 required prop에 맞춰 갱신해야 한다.
  - Recommended default: 기존 `tests/task-row.test.tsx` 확장.
  - Recommended rationale: 기존 fixture와 CSS 계약을 재사용하고, 새 required prop에 따른 회귀 수정과 interaction 검증을 한 파일에서 함께 관리해 중복 tree traversal helper와 새 파일을 피한다.
  - Status: resolved — 사용자 승인으로 기존 `tests/task-row.test.tsx` 확장 (2026-08-18).

## Global Constraints

- Companion: TS/TSX 탭 들여쓰기 + biome, readonly type/순수 함수/의존성 주입 idiom. 테스트는 DOM 없이 순수 함수 + `renderToStaticMarkup`. 새 테스트 의존성 금지.
- Tauri 쪽(Rust command, watch, activity store)과 CLI/contract는 변경하지 않는다.
- 0048/0049의 surface별 CSS ownership 유지 — 보드 스타일은 `styles/stage-board.css`에만.
- 새 interaction·hover·focus·접근성 계약은 구현 전에 `DESIGN.md`의 StageCard/Accessibility/Interaction 항목에 반영한다.
- 커밋은 Conventional Commits, 이모지 prefix 금지.

## public contract (변경 / 비변경)

### 변경하는 것
- `StageBoard` component props: `{ board }` → `{ board, onOpenIde }` (`StageCardOpenIde = (root: string, task: Task) => void`). Companion 내부 계약이다.

### 변경하지 않는 것
- Tauri command 계약(`workbranch_list_global`, `workbranch_run`, watch, activity)과 `CompanionCommand` 3종(ide/terminal/finder).
- `handleTaskAction`의 동작(실행 후 refresh + "Action complete" status, 실패 시 `showError`) — 보드 경유 실행도 동일 UX를 그대로 얻는다.
- TaskMetaRow의 IDE/Terminal/Finder 버튼 — 보드 더블 클릭은 추가 진입점이지 대체가 아니다.
- `BoardCard`/`buildBoardModel` 등 application/domain 모델.

## 파일 구조 (touched)

```text
apps/companion/src/ui/StageBoard.tsx           # onOpenIde prop, StageCard 오버레이 native button + pointer/native activation 분리
apps/companion/src/App.tsx                     # <StageBoard onOpenIde={...handleTaskAction(root, task, "ide")}>
apps/companion/src/styles/stage-board.css      # cursor/hover, .stage-card-open 오버레이 + :focus-visible
apps/companion/tests/task-row.test.tsx          # 더블 클릭/native activation/포인터 단일 클릭 무동작/CSS 계약 + 기존 호출부 갱신
DESIGN.md                                      # StageCard launcher gesture, hover/focus, 접근성 activation 계약
```

---

### Task 1: StageBoard 더블 클릭 → IDE 배선

**Red:** 기존 `tests/task-row.test.tsx`를 확장한다. 임의의 `JSXElementConstructor`를 `child.type(child.props)`로 호출하지 않는다(`ComponentClass | FunctionComponent` union 때문에 strict TypeScript에서 callable로 좁혀지지 않음). `StageCard`를 app-internal named export로 두고 기존 `TaskMetaRow` 테스트처럼 직접 호출해 button props를 수집한다. 같은 파일의 기존 `<StageBoard board={...} />` 4곳에는 required `onOpenIde` fixture를 함께 전달한다. 테스트 4건:

1. 정적 마크업에 `class="stage-card-open"` + `type="button"` + `aria-label="open <task> in IDE"` 노출.
2. 오버레이 버튼 `onDoubleClick()` 호출 시 handler가 `(root, task)`로 호출된다.
3. `onClick`은 `detail === 0`이면 실행하고 `detail === 1`/`2`이면 무시해 native keyboard/접근성 activation과 포인터 단일 클릭 무동작을 함께 고정한다. 별도 `onKeyDown` prop은 두지 않는다.
4. CSS 계약(`readFileSync("src/styles/stage-board.css")`): `.stage-card`에 `cursor: pointer`와 `position: relative`, `.stage-card:hover` 존재, `.stage-card-open`에 `inset: 0` + `position: absolute`, `.stage-card-open:focus-visible` 존재.

**Green:**

- `StageBoard.tsx`: `StageCardOpenIde` type과 app-internal `StageCard` named export, `StageCard`에 `onOpenIde` 전달. 카드 첫 자식으로 `<button aria-label / className="stage-card-open" / onClick / onDoubleClick / title="Double-click to open <task> in IDE" / type="button" />`. `onClick`은 `event.detail !== 0`이면 조기 return하고 native 비포인터 activation만 실행한다.
- `App.tsx`: `<StageBoard board={board} onOpenIde={(root, task) => void handleTaskAction(root, task, "ide")} />`.
- `stage-board.css`: D4의 스타일. 오버레이는 `appearance/background/border/margin/padding` reset + `border-radius: 3px`.
- `DESIGN.md`: StageCard를 IDE launcher 진입점으로 명시하고 포인터 더블 클릭, native button activation, hover/focus 신호, overlay tooltip tradeoff를 기록한다.
- biome formatter가 긴 `expect(...toMatch(...))` 라인을 재배치하므로 마지막에 `pnpm exec biome check --write tests/task-row.test.tsx`로 정리한다.

- [x] red 확인 (신규 4개 behavior를 순차적으로 추가해 각각 feature 부재로 실패 확인)
- [x] green: StageBoard/App/CSS/DESIGN 구현 후 137 tests + typecheck 통과
- [x] biome format 적용 확인 (`biome check --write` changed files 4개)

### Task 2: 전체 검증

- [x] `apps/companion`: `pnpm test` 전체 통과 (15 files, 137 tests)
- [x] `pnpm typecheck` 통과
- [x] `pnpm lint` — error 0, 기존 `useLiteralKeys` info 42건 유지
- [x] `pnpm build` 통과 (`tsc -p tsconfig.json` + Vite 58 modules)
- [x] 실제 UI QA: `pnpm companion:dev` native shell 기동 확인 + production `StageBoard.tsx`/`style.css`를 그대로 로드한 격리 460×680 harness에서 Claude/Codex rest·hover·focus 6개 capture 확인 — 포인터 단일 클릭 무동작, 더블 클릭·Enter·Space·accessibility click 실행, task-specific tooltip/aria, horizontal overflow 없음. 독립 visual QA 2개 PASS (`/tmp/stagecard-qa-evidence.json`, `/tmp/stagecard-{claude,codex}-{rest,hover,focus}.png`). 외부 IDE 앱 자체는 활성 데스크톱을 방해하지 않도록 띄우지 않았고, `App.handleTaskAction(..., "ide")` → `workbranch_run` source trace와 Tauri 23 tests로 command 경계를 검증했다.
- [x] 하단 TaskMetaRow IDE/Terminal/Finder 회귀 없음 확인 (137 Vitest + architecture check PASS)
