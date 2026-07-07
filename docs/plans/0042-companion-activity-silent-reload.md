# 0042 Companion Activity 백그라운드 갱신 시 선택·화면 유지 (silent reload)

> **agentic worker 지침:** 실행 시 `superpowers:executing-plans`를 사용한다. 동작 변경 전에는 `superpowers:test-driven-development`(red → green → refactor)를 따른다. 이 plan은 **Companion(Tauri/React) 전용**이며 `apps/companion/src/activity/ActivityCalendarView.tsx` 한 파일의 로드 정책만 바꾼다 — Rust command, `activity.jsonl` 스키마, workspace monitor(0033), 캘린더 도메인(0041)은 변경하지 않는다. 검증은 `apps/companion`에서 `pnpm test` + `pnpm typecheck` + `pnpm lint`로 한다. Step은 checkbox(`- [ ]`)로 추적한다.
>
> **시리즈 위치:** 0041이 Activity 캘린더 타임라인을 추가했고, 0033의 workspace monitor는 root 파일 변경 이벤트마다 전역 refresh를 실행한다. 두 slice가 결합되면서 생긴 UX regression을 고치는 slice다: agent가 작업 중이면 수 초 간격으로 refresh가 발생하고, 그때마다 Activity 뷰가 로딩 화면으로 깜빡이며 사용자가 클릭한 블록 선택(상세 패널)이 강제로 해제된다.

**목표:** 백그라운드 갱신(같은 날짜 범위의 재조회)은 화면 깜빡임 없이 데이터만 조용히 교체하고, 사용자가 클릭한 세션 선택과 상세 패널을 유지한다. 날짜 이동·모드 전환처럼 범위가 바뀌는 로드는 지금처럼 로딩 상태를 보여준다.

## 근본 원인 (조사 완료)

재현: Activity 탭에서 블록 클릭 → 상세 패널 확인 중 → 수 초 내 화면이 "Loading activity…"로 바뀌고 선택 해제.

원인 체인:

1. `workspaceMonitor.ts` — `onRootChanged` 이벤트마다 `scheduleRefresh()`. agent가 파일을 쓰는 동안 수 초 간격으로 refresh가 발생한다 (0033의 의도된 동작).
2. `App.tsx:100` — `applyState()`가 호출될 때마다 `setActivityReloadToken(n + 1)`.
3. `ActivityCalendarView.tsx:331-337` — `loadRange` memo에 `reloadToken`이 포함되어 토큰 증가마다 로드 effect 재실행.
4. `ActivityCalendarView.tsx:341` — effect 시작 시 `setLoading(true)`. 타임라인은 `!loading`일 때만 렌더되므로(465행) **매 갱신마다 전체 캘린더가 언마운트되고 "Loading activity…"로 교체**된다.
5. `ActivityCalendarView.tsx:350` — 로드 완료 시 `setSelectedKey(undefined)`. **사용자 선택이 무조건 해제**되어 상세 패널이 사라진다.

핵심 사실: 세션 key는 `root\0task\0start`(`calendar.ts:99-101`)로, 같은 범위를 재조회해 진행 중 세션에 이벤트가 추가되어도 key가 안정적이다(start는 첫 이벤트 기준). 따라서 선택 key를 유지하면 갱신 후에도 같은 블록이 선택된 채 상세 패널이 최신 데이터로 갱신된다. 세션이 사라진 경우는 렌더 시 `calendarSessions.find(...)`가 `undefined`를 반환해 상세 패널이 자연스럽게 숨겨진다(379-381행) — 별도 정리 코드가 필요 없다.

## Global Constraints

- monorepo: pnpm workspace. Companion 명령은 `apps/companion`에서 실행한다.
- TS/TSX는 탭 들여쓰기 + biome (`pnpm lint`). 기존 파일 스타일(readonly type, 순수 함수, 의존성 주입)을 따른다.
- 테스트는 기존 idiom 유지: DOM 환경 없이 순수 함수 + `renderToStaticMarkup`. 새 테스트 의존성(jsdom, testing-library) 추가 금지.
- `reloadToken` prop 계약과 App.tsx의 토큰 증가 로직은 변경하지 않는다(다른 뷰·향후 소비자와의 계약). 정책은 뷰 내부에서 결정한다.
- 커밋은 Conventional Commits (`fix(companion): …`), 이모지 prefix 금지.

## 결정 사항

> **Decision 1 resolved (2026-07-07):** 선택 유지는 같은 `from`/`to` 범위의 token-only silent reload에만 적용한다. 첫 로드·날짜 이동·모드 전환처럼 범위가 바뀌는 load는 기존처럼 loading placeholder를 보여주고 선택을 clear한다.

1. **로딩 표시 정책은 순수 함수로 분리** — `shouldShowLoading(loadedRange, nextRange)`: 첫 로드이거나 `from`/`to`가 바뀌면 `true`, 같은 범위의 토큰-only 재조회면 `false`(silent). `validateProjectFilter`와 같은 exported-pure-function 패턴으로 테스트한다.
2. **선택 유지는 같은 범위의 silent reload에만 적용** — `shouldShowLoading(loadedRangeRef.current, loadRange)`가 `false`인 token-only 재조회에서는 `setSelectedKey(undefined)`를 건너뛰어 사용자가 클릭한 세션을 유지한다. 첫 로드·날짜 이동·모드 전환처럼 `shouldShowLoading(...)`이 `true`인 범위 변경 load에서는 기존처럼 선택을 clear한다. stale key는 같은 범위 silent reload에서 세션이 사라질 때 렌더 시 find가 걸러내므로 안전하다. key 안정성은 `sessionsFromEvents` 회귀 테스트로 고정한다. (Decision 1: A 확정)
3. **백그라운드 갱신 실패 시 동작은 이번 slice에서 바꾸지 않는다** — 현재처럼 error 표시 + events 초기화 유지(후속 참고).

## public contract (변경 / 비변경)

### 변경하지 않는 것
- `ActivityCalendarViewProps`(`loadEvents`, `reloadToken`, `today`)와 App.tsx 연결.
- workspace monitor·`applyState`·토큰 증가 로직.
- 캘린더 도메인 함수 전부(`calendar.ts`), 세션 key 형식.

### 추가하는 것 (additive)
- `shouldShowLoading(loadedRange: { from, to } | undefined, nextRange: { from, to }): boolean` export (`ActivityCalendarView.tsx`).

## 파일 구조 (touched)

```text
apps/companion/src/activity/ActivityCalendarView.tsx  # 로드 effect: silent reload + 선택 유지
apps/companion/tests/activity-calendar.test.tsx       # shouldShowLoading + 세션 key 안정성 테스트
```

---

### Task 1: 실패하는 테스트 (red) — 작성 완료, 확인만 남음

**Files:**
- Test: `apps/companion/tests/activity-calendar.test.tsx`

**Interfaces:**
- Consumes: `shouldShowLoading` (Task 2가 제공 예정 — 현재 미구현이라 red).

- [x] **Step 1: 실패하는 테스트 작성** — 이미 반영됨:
  - `describe("shouldShowLoading")` 3건: 첫 로드 `true` / 범위 변경 `true` / 같은 범위 토큰-only 재조회 `false`.
  - `sessionsFromEvents`에 "keeps the session key stable when a reload extends an ongoing session" 1건: 진행 중 세션에 이벤트가 추가돼도 key 불변(선택 유지의 전제 invariant 고정).
- [x] **Step 2: 실패 확인** — Run: `cd apps/companion && pnpm vitest run tests/activity-calendar.test.tsx`
  확인됨 (2026-07-07): `3 failed | 33 passed` — `shouldShowLoading` 미export로 3건 FAIL, key 안정성 테스트는 기존 invariant라 PASS.

---

### Task 2: silent reload + 선택 유지 구현 (green)

**Files:**
- Modify: `apps/companion/src/activity/ActivityCalendarView.tsx`

**Interfaces:**
- Produces: `export function shouldShowLoading(loadedRange: ActivityLoadRange | undefined, nextRange: ActivityLoadRange): boolean`

- [x] **Step 1: 구현** —
  1. `shouldShowLoading` 추가:

     ```ts
     export function shouldShowLoading(
     	loadedRange: ActivityLoadRange | undefined,
     	nextRange: ActivityLoadRange,
     ): boolean {
     	return (
     		loadedRange === undefined ||
     		loadedRange.from !== nextRange.from ||
     		loadedRange.to !== nextRange.to
     	);
     }
     ```

  2. 컴포넌트에 `const loadedRangeRef = useRef<ActivityLoadRange>()` 추가 (`useRef` import).
  3. 로드 effect 수정:
     - effect 시작 시 `const showLoading = shouldShowLoading(loadedRangeRef.current, loadRange);` 계산.
     - `setLoading(true)` → `if (showLoading) { setLoading(true); }` (같은 범위 재조회면 기존 타임라인을 그대로 보여준 채 조용히 갱신).
     - `.then` 성공 시 `loadedRangeRef.current = { from: loadRange.from, to: loadRange.to };` 기록.
     - `.then` 성공 시 `if (showLoading) { setSelectedKey(undefined); }` 유지: 첫 로드·날짜 이동·모드 전환은 기존처럼 선택 clear, 같은 범위 silent reload만 선택 유지.
     - `.finally`의 `setLoading(false)`는 유지 (silent 경로에서는 이미 false라 무해).
- [x] **Step 2: 통과 확인** — Run: `cd apps/companion && pnpm vitest run tests/activity-calendar.test.tsx && pnpm test && pnpm typecheck && pnpm lint`
  Expected: 전체 PASS (기존 parseContract info 진단 제외).
- [ ] **Step 3: 커밋** — safety gate로 자동 실행 보류: `git add apps/companion && git commit -m "fix(companion): keep activity selection and timeline across background reloads"`
  - 보류 사유(2026-07-07): `plan-execute` safety gate상 git commit은 자동 실행하지 않음.

---

### Task 3: 수동 검증

- [ ] **Step 1: 실동작 확인** — `cd apps/companion && pnpm tauri dev`로 실행 후:
  1. agent가 작업 중인 상태(수 초 간격 refresh 발생)에서 Activity 탭 진입 → 타임라인이 "Loading activity…"로 깜빡이지 않고 유지되는지.
  2. 블록 클릭 → 상세 패널이 열린 상태로 수십 초 대기 → 백그라운드 갱신이 지나가도 선택·상세 패널이 유지되는지 (진행 중 세션이면 end 시각이 자라며 갱신되는지).
  3. 날짜 이동(`‹`/`›`/`Today`)·모드 전환 시에는 기존처럼 로딩 표시가 나오는지.
  GUI 육안 확인이 비대화형 실행에서 불가하면 사용자 확인으로 대체하고 결과를 기록한다.
- [ ] **Step 2: 최종 검증 기록** — 아래 "검증 기록"에 명령·결과를 남긴다.

---

## 롤아웃 / 호환성

- **비파괴.** 데이터 경로·IPC·prop 계약 불변. 뷰 내부의 로딩 표시 정책과 선택 초기화 한 줄만 바뀐다.
- 백그라운드 재조회 빈도 자체는 그대로다(monitor가 파일 변경마다 refresh). 이번 slice는 UI 파괴만 제거한다.

## 미해결 / 후속

- **백그라운드 갱신 실패 시 UX**: 현재는 error 표시 + events 초기화로 타임라인이 사라진다. 일시적 읽기 실패면 마지막 데이터를 유지하는 편이 자연스럽다 — 후속 slice.
- **재조회 빈도 절감**: monitor 이벤트 debounce 또는 Activity 뷰가 보일 때만 reload token 소비 — 성능 이슈가 관측되면 후속.
- **선택 세션이 갱신으로 사라진 경우의 안내**: 현재는 상세 패널이 조용히 닫힌다. 필요하면 후속에서 처리.

## 실행 결과

- [x] Task 1 — 실패하는 테스트 (red 확인: 2026-07-07, `3 failed | 33 passed`)
- [x] Task 2 — silent reload + 선택 유지 (green)
- [ ] Task 3 — 수동 검증 (비대화형 CLI 환경에서 GUI 육안 확인 미수행)

### 검증 기록

- 2026-07-07 Task 1: `cd apps/companion && pnpm vitest run tests/activity-calendar.test.tsx` — RED 확인 (`shouldShowLoading` 미구현으로 3 failed, 33 passed).
- 2026-07-07 Task 2 RED 재확인: `cd apps/companion && pnpm vitest run tests/activity-calendar.test.tsx` — RED (`shouldShowLoading is not a function` 3 failed, 33 passed).
- 2026-07-07 Task 2 targeted green: `cd apps/companion && pnpm vitest run tests/activity-calendar.test.tsx` — PASS (36 passed).
- 2026-07-07 Task 2 full test/typecheck: `cd apps/companion && pnpm test && pnpm typecheck` — PASS (`14 passed`, `101 passed`; `tsc --noEmit` PASS).
- 2026-07-07 Task 2 lint: `pnpm lint`는 기존 `src/infrastructure/parseContract.ts` `lint/complexity/useLiteralKeys` info 진단으로 exit 1. 변경 파일 한정 `pnpm biome check src/activity/ActivityCalendarView.tsx tests/activity-calendar.test.tsx` — PASS. Plan의 기존 info 제외 조건에 맞춰 `pnpm biome check src tests --diagnostic-level=error` — PASS.
- 2026-07-07 Task 2 build smoke: `cd apps/companion && pnpm build` — PASS (`tsc -p tsconfig.json && vite build`).
- 2026-07-07 Task 3: 비대화형 CLI 환경에서는 `pnpm tauri dev` GUI 육안 검증을 수행하지 못함. 릴리즈 전 Activity 탭에서 same-range refresh 유지 / 날짜 이동 clear를 사람이 확인 필요.
