---
intent: COMP001-screensaver-feature
---
# Plan · COMP001 screensaver-feature

## Summary
작업 중(실행 중 또는 내 응답 대기 세션이 있음)인 동안 companion 이 Mac 을 깨워 두고, 설정 시간 동안 입력이 없으면 모든 모니터에 시안 D 의 dashboard 를 띄우며, dashboard 에 입력이 오면 즉시 macOS 잠금으로 넘긴다. 기능은 설정 스위치 하나로 켜고 끄며 기본은 꺼짐이다. 먼저 runtime 데이터 수집을 Rust 의 단일 서비스로 옮겨(Slice 0) main 창·dashboard 창·screensaver 서비스가 같은 데이터를 push 로 받게 한다.

## Architecture decisions
- runtime 데이터의 단일 출처는 Rust `RuntimeService` 다. `~/.workbranch/runtime/` 을 `notify` 로 감시해 변경 시(debounce) `workbranch runtime --json` 을 읽고, 시간이 지나 바뀌는 stale 판정 때문에 60초마다 한 번 더 읽는다. 마지막 결과를 보관하고 `runtime-snapshot` 이벤트로 모든 창에 보내며, 늦게 열린 창은 `runtime_snapshot` command 로 받는다 — 숨겨진 창의 JS 타이머에 기대지 않고, CLI 실행을 한 곳으로 모은다. (Q2)
- companion 은 runtime SQLite 를 직접 읽지 않는다. schema 가 있는 CLI JSON(`packages/contract`)이 경계다 — DB 는 수집기 버전과 함께 바뀌는 agent-runtime 내부 저장소다. (Q2)
- main 창의 1초 runtime polling 은 `runtime-snapshot` 구독으로 바꾼다. 계약 검증(`parseRuntimeDocument`)과 호환성 오류 분류는 지금처럼 TS 에 둔다. (Q2)
- 목록 데이터(task·repo·branch)는 지금의 이벤트 기반 workspace monitor(`roots-changed` + 5분 heartbeat)를 각 창이 그대로 쓴다. 목록까지 Rust store 로 옮기는 것은 follow-up 이다(Discovered). (Q2)
- screensaver 서비스는 `RuntimeService` 의 snapshot 을 프로세스 안에서 구독해 작업 중(`observation == "observed"` 이고 `state` 가 `running`/`waiting`)을 판정한다. 칸반 `runtimeRole()` 과 같은 기준이다. (Q2)
- idle 시간은 권한 없이 쓸 수 있는 알림 API 가 없어 polling 한다: 평소 1초, dashboard 표시 중 0.25초. 프로세스를 띄우지 않는 함수 호출이다. (Q2)
- OS 연동은 typed binding 을 쓴다: 전원 유지는 `NSProcessInfo` activity(`objc2-foundation`; 디스플레이·시스템 idle 잠자기 방지 + App Nap 해제), 창 level·collection behavior·활성화는 `objc2-app-kit`, idle 시간은 `objc2-core-graphics` 의 `CGEventSourceSecondsSinceLastEventType`. `objc2`·`objc2-foundation`·`objc2-app-kit`·`objc2-core-graphics` 를 직접 의존성으로 추가한다(이미 lock 에 있는 버전, 새 crate 없음). (Q3)
- 바뀌는 OS 상태는 알림으로 받는다: 화면 잠김·해제는 `NSDistributedNotificationCenter` 의 `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`, 모니터 구성 변경은 `NSApplicationDidChangeScreenParametersNotification`. polling 은 idle 시간뿐이다. (Q3)
- 비공개 `SACLockScreenImmediate` 만 `dlopen`/`dlsym` 으로 찾는다. unsafe 는 이 한 곳에 SAFETY 주석과 함께 둔다. (Q3)
- 모든 OS 동작은 `Platform` trait 뒤에 둔다. screensaver 는 순수 상태 기계(`step(상태, 입력) -> (상태, 동작들)`)이고, 전이는 가짜 Platform 으로 단위 테스트, OS 동작은 behaviour check 로 확인한다. (Q3)
- 화면이 잠긴 동안(사용자가 잠갔든 R6 으로 잠겼든) companion 은 아무것도 하지 않는다: dashboard 없음, 전원 activity 해제 — macOS 기본 동작 그대로. 잠금이 풀리면 다시 판정한다. 잠자기 방지는 "작업 중 && 잠기지 않음 && 기능 켜짐" 일 때만이다. (Q4)
- dashboard 는 별도 Vite 진입점(`dashboard.html`, multi-page build)이다. dashboard 창은 dashboard 코드만 로드하고, capability 는 `dashboard-*` 창 전용으로 필요한 권한만 준다. 공통 로직은 application·domain·ui import 로 공유한다. (Q5)
- dashboard 카드는 메뉴바 카드와 같은 원천(`buildMainViewModel()` 의 lead session·repo·알림)에서 프롬프트·도구 동작·마지막 응답·변경 상태를 받는다. 세부 줄은 줄 수를 고정해 자르고(line clamp) 크기는 화면 높이(vh)에 비례하므로, 카드 최대 높이가 화면 비율에 대해 일정하다. 그래서 열당 카드 수는 DOM 측정 없이 상수(3)로 둔다. 열·대기 이유·종료 결과의 문구는 `ui/boardCopy.ts` 하나를 메뉴바와 함께 쓴다. (Slice 5)

## Scope
- 패키지: `apps/companion` (Rust `src-tauri` + React `src`). CLI·agent-runtime·contract 는 바꾸지 않는다.
- 새 파일 (Q6):
  - `apps/companion/src-tauri/src/runtime_service.rs`, `apps/companion/src-tauri/src/runtime_service_tests.rs` — RuntimeService (감시·읽기·배포·command)
  - `apps/companion/src-tauri/src/screensaver.rs` — 모듈 루트: 서비스 연결, command, 설정 미러
  - `apps/companion/src-tauri/src/screensaver/machine.rs`, `apps/companion/src-tauri/src/screensaver/machine_tests.rs` — 순수 상태 기계
  - `apps/companion/src-tauri/src/screensaver/platform.rs` — `Platform` trait + 테스트용 가짜
  - `apps/companion/src-tauri/src/screensaver/macos.rs` — macOS 구현 (objc2, dlopen)
  - `apps/companion/src-tauri/src/screensaver/windows.rs` — 모니터별 dashboard 창 관리
  - `apps/companion/src-tauri/capabilities/dashboard.json` — `dashboard-*` 창 전용 권한
  - `apps/companion/dashboard.html`
  - `apps/companion/src/dashboardMain.tsx` — dashboard 진입점 (`main.tsx` 와 나란히)
  - `apps/companion/src/DashboardApp.tsx` — dashboard 조립 지점 (`App.tsx` 와 나란히)
  - `apps/companion/src/application/useRuntimeSessions.ts` — snapshot 구독 hook (main·dashboard 공용)
  - `apps/companion/src/application/screensaver.ts` — 설정 타입·기본값·보정
  - `apps/companion/src/application/dashboard.ts` — dashboard 모델
  - `apps/companion/src/ui/ScreensaverSettings.tsx`, `apps/companion/src/ui/Dashboard.tsx`, `apps/companion/src/ui/SegmentClock.tsx`
  - `apps/companion/src/styles/dashboard.css`
  - `apps/companion/tests/runtime-sessions.test.ts`, `apps/companion/tests/screensaver-settings.test.tsx`, `apps/companion/tests/dashboard-model.test.ts`, `apps/companion/tests/dashboard.test.tsx`
- 바뀌는 파일: `src-tauri/src/lib.rs`, `src-tauri/Cargo.toml`, `src/App.tsx`, `src/application/preferences.ts`, `src/application/useCompanionSettings.ts`, `src/ui/SettingsPanel.tsx`, `src/infrastructure/tauriClient.ts`, `vite.config.ts`, `tests/preferences.test.ts`

## Slices
0. Slice 0 (prefactor) — runtime 데이터를 Rust `RuntimeService` 가 감시·배포하고 main 창은 구독한다. 칸반 동작은 그대로다.
1. Slice 1 — 설정을 켜면 작업 중인 동안 Mac 이 잠들지 않는다 (R1, R2)
2. Slice 2 — 작업 중 입력이 없으면 모든 모니터에 dashboard 가 뜨고, 작업 중이 끝나면 내려간다 (R3, R4, R5, R8, R9, R10, R11)
3. Slice 3 — dashboard 에 입력이 오면 macOS 잠금으로 넘어가고, 잠금을 쓸 수 없으면 dashboard 만 닫힌다 (R6, R7)
4. Slice 4 — 설정의 미리 보기 버튼으로 dashboard 를 바로 띄워 본다 (R12, 구현 중 추가)
5. Slice 5 — dashboard 카드에 프롬프트·진행 중 동작·마지막 응답·변경 상태를 보여 준다 (R9, R11, 구현 중 변경, 시안 E)

## Verification plan
| package | typecheck | lint | format | test |
|---|---|---|---|---|
| companion | pnpm --filter @workbranch/companion typecheck | pnpm --filter @workbranch/companion lint | (lint 의 biome check 에 포함) | pnpm --filter @workbranch/companion test && cargo test --manifest-path apps/companion/src-tauri/Cargo.toml |

추가: FFI·objc 를 쓰는 task 는 `cargo clippy --manifest-path apps/companion/src-tauri/Cargo.toml` (Cargo.toml 의 `[lints.clippy]` 가 `undocumented_unsafe_blocks` 등을 deny), Slice 2 끝에 `pnpm --filter @workbranch/companion tauri build` (CI 의 app bundle smoke).

Behaviour checks (실제 Mac, `pnpm companion:dev` 또는 빌드한 앱):
- Slice 0: main 창을 숨긴 채 agent 를 돌리고 창을 열면, 열자마자 칸반이 최신이다. 창을 연 채로 hook 이 쓰이면 1초 안에 칸반이 바뀐다. 아무 일이 없을 때는 `workbranch runtime` 이 60초에 한 번만 실행된다.
- R1: 새 설정 파일로 시작하면 스위치가 꺼져 있고, 꺼진 채로 agent 를 돌리고 비워 둬도 `pmset -g assertions` 에 companion 이 없고 dashboard 가 뜨지 않는다.
- R2: 켜고 agent 를 돌리면 `pmset -g assertions` 에 companion activity 가 보이고, 턴 종료 후 또는 화면을 잠그면(Ctrl+Cmd+Q) 사라지며 잠금을 풀면 다시 보인다. `kill -9` 로 companion 을 죽이면 즉시 사라진다.
- R3: companion 2분, macOS 화면보호기 1분으로 두고 작업 중에 비우면 2분에 dashboard, 그 전에 화면보호기 없음.
- R4: macOS 디스플레이 꺼짐(이 Mac 10분)보다 오래 비워도 작업 중이면 dashboard 가 켜져 있다.
- R5: 마지막 작업 중 세션이 턴 종료되면 dashboard 가 내려가고 macOS 설정대로 진행. 턴 종료만 남은 상태에서는 dashboard 가 뜨지 않는다.
- R6: dashboard 에서 마우스를 움직이면 바로 잠금 화면, 데스크톱 노출 없음. 밑에 터미널이 포커스였어도 그 키 입력이 터미널에 들어가지 않는다.
- R7: 잠금 probe 를 강제로 실패시키는 개발용 환경 변수로 실행하면 "입력 시 잠금" 표시가 없고 입력 시 dashboard 만 닫힌다.
- R8·R9·R11: dashboard 의 개수·카드가 열어 둔 companion 칸반과 같고, 각 카드의 프롬프트·도구 동작(대기·실행 중)·마지막 응답(턴 종료)이 메뉴바 카드와 같으며, 넘치는 열에 "+n more". 긴 프롬프트·응답과 대기 카드 3장이 한 열에 있어도 카드가 잘리거나 아래로 넘치지 않는다(1440×900 과 외부 모니터 둘 다).
- R10: 모니터 2대에서 둘 다 dashboard, 메뉴바·Dock·다른 Space 의 전체 화면 앱 위를 덮는다.
- R12: 기능을 끈 채 Settings › Screen Saver › Preview 를 누르면 dashboard 가 뜨고 "미리 보기 · 입력하면 닫힘" 이 보이며, 2초 안의 마우스 움직임으로는 닫히지 않고 그 뒤 움직이면 잠금 없이 닫힌다. 그동안 `pmset -g assertions` 에 companion 이 없다.

## Risks
| risk | impact | mitigation |
|---|---|---|
| 디스플레이 잠자기 방지가 macOS 화면보호기도 막는다는 가정이 틀림 | R3 실패(화면보호기가 먼저 뜸) | Slice 1 behaviour check 에서 먼저 확인. 틀리면 Slice 2 에서 다른 수단을 찾는다 |
| dashboard 가 뜬 직후 첫 키 입력이 밑의 앱(예: 승인 대기 중인 터미널)으로 감 | 보안: 잠기기 전 한 번의 입력이 agent 승인 등으로 이어질 수 있음 | dashboard 표시 시 companion 을 활성화하고 dashboard 창을 key window 로 만든다. R6 behaviour check 에 포함 |
| 비공개 `SACLockScreenImmediate` 가 이후 macOS 에서 사라짐 | 잠금 불가 | 시작 시 probe, 실패 시 R7 경로(dashboard 만, 표시 숨김) |
| 사용자가 직접 잠근 뒤 dashboard 가 떠 있다가 잠금 해제 직후 입력으로 다시 잠김 | 잠금 해제 반복 | 화면 잠김 동안 dashboard 를 띄우지 않음(Q4) |
| R6 으로 잠긴 뒤(누군가 건드림) macOS 설정대로 Mac 이 잠들어 agent 가 멈춤 | 자리를 비운 동안 작업 중단 | 의도된 동작(Q4, intent R2·Non-goals). 잠금 해제 후 작업 중이면 다시 잠자기 방지 |
| SQLite 쓰기 방식(WAL·journal) 때문에 파일 이벤트가 몰리거나 빠짐 | 과도한 CLI 실행 또는 반영 지연 | 디렉터리 단위 감시 + debounce, 60초 보조 읽기로 최악 1분 지연 |
| main 창 데이터 경로 변경으로 칸반 회귀(오류 표시, 호환성 안내, uncertain 처리) | 기존 기능 손상 | 기존 테스트 유지 + T0.2 에서 오류·호환성 경로 테스트 추가 |
| 작업 중이 아닐 때 App Nap 으로 Rust 서비스 주기가 늦어짐 | 작업 중 판정이 몇 초 늦음 | 작업 중이 되면 activity 가 App Nap 을 끈다. 시작 지연은 허용 |
| 모니터 연결·해제가 dashboard 표시 중에 일어남 | 새 모니터가 덮이지 않음 | screen parameters 알림을 받으면 창을 다시 맞춘다(T2.2) |

## Coverage
| R-id | slice / task | notes |
|---|---|---|
| — | T0.1, T0.2 | Slice 0 prefactor: R2·R3·R5·R9 가 쓰는 runtime 데이터 경로 |
| R1 | T1.1, T1.2, T1.3, T1.4 | |
| R2 | T1.1, T1.2 | 잠김 시 해제 포함 |
| R3 | T2.1 | |
| R4 | T2.1, T2.2 | |
| R5 | T2.1 | |
| R6 | T2.2, T3.1 | key window 는 T2.2 |
| R7 | T3.1, T3.2, T3.3 | |
| R8 | T2.3, T2.4, T2.5, T3.3 | |
| R9 | T2.3, T2.4, T5.1, T5.2, T5.3 | Slice 5 에서 카드 정보 확장 |
| R10 | T2.2 | |
| R11 | T2.3, T2.4, T5.3 | 열당 4장 → 3장, 세부 줄 수 제한 |
| R12 | T4.1, T4.2, T4.3 | 구현 중 추가 |

## Decision Log
- 2026-10-16 · Q1 slice 구성과 순서 → A. 3개 slice, Slice 1(설정 + 잠자기 방지) → 2(dashboard) → 3(입력 시 잠금) · slice 마다 관찰 수단이 하나씩이고 가장 위험한 가정(디스플레이 잠자기 방지가 화면보호기도 막음)을 먼저 검증. 잠금 없는 dashboard 는 기본 꺼짐 상태로 Slice 3 전까지 출시하지 않음
- 2026-10-16 · Q2 runtime 데이터 구조 → A. Rust `RuntimeService` 단일 출처(디렉터리 감시 + 60초 보조 읽기, `runtime-snapshot` 이벤트 + `runtime_snapshot` command), main·dashboard 창은 구독, 목록은 기존 이벤트 기반 monitor, idle 만 polling · 원칙: 현재 구현의 최소 수정이 아니라 더 나은 구조. 숨겨진 창 throttling 과 중복 CLI 실행을 없애고, CLI JSON 계약을 경계로 유지. 목록의 Rust 이전은 범위 대비 이득이 적어 follow-up
- 2026-10-16 · Q1 수정 → Slice 0(runtime 단일 서비스, prefactor)을 앞에 추가해 0 → 1 → 2 → 3 · Q2 의 결정
- 2026-10-16 · Q3 macOS 연동 수단과 의존성 → A. objc2 계열 typed binding(직접 의존성 4개, 새 crate 없음) + 잠김·모니터 변경은 OS 알림 + idle 만 polling + 비공개 잠금만 dlopen + `Platform` trait 뒤의 순수 상태 기계 · 타입 안전, unsafe 최소, push 우선, OS 없이 전이 테스트 가능
- 2026-10-16 · Q4 화면이 잠긴 동안 → companion 은 아무것도 하지 않음(dashboard 없음, 잠자기 방지 해제, macOS 그대로). intent R2 를 "잠기지 않은 동안"으로 좁힘 · 원칙: 잠자기 방지는 agent 가 동작하고 dashboard 가 동작할 수 있을 때만, 나머지는 OS 그대로. 결과: R6 으로 잠긴 뒤에는 macOS 설정대로 잠들 수 있음
- 2026-10-16 · Q5 dashboard 진입점 → A. 별도 Vite 진입점 `dashboard.html` + `dashboard-*` 전용 최소 권한 capability · 창마다 필요한 코드·권한만, main 앱 부수 효과 격리
- 2026-10-16 · Q6 새 파일·폴더 경로 → A. Rust 는 `runtime_service.rs` + `screensaver.rs`/`screensaver/`(machine·platform·macos·windows) 폴더 모듈(mod.rs 없음), TS 는 기존 계층에 넣고 진입점은 `src/dashboardMain.tsx`·`src/DashboardApp.tsx` · 하나의 기능을 폴더로 묶어 경계와 비공개 범위를 드러내고, TS 계층을 깨는 새 최상위 폴더를 만들지 않음

- 2026-10-16 · (구현 중 추가) Settings 미리 보기 → intent R12(SHOULD) 와 Slice 4 추가. 미리 보기 창은 라벨 `dashboard-preview-<n>` 으로 구분해 기존 `dashboard-*` capability 를 그대로 쓰고, 상태 기계에 미리 보기 모드(2초 입력 무시, 잠금 없음, 잠자기 방지 없음)를 둔다 · 사용자 요청
- 2026-10-16 · (구현 중 변경) dashboard 카드 정보 → 시안 E, intent R9·R11 변경과 Slice 5 추가(프론트엔드만, Rust 변경 없음). 열당 카드 3장, 세부 줄 line clamp, 종료 결과 문구를 `boardCopy.ts` 로 모아 메뉴바와 공유 · 사용자 요청: 전체 화면인데 메뉴바보다 정보가 적음

## Discovered
- follow-up(COMP001 범위 밖): 목록 데이터(workspace monitor 의 root 별 갱신·오류 병합)도 Rust store 로 옮겨, 모든 창이 하나의 push 상태를 구독하는 순수 view 가 되게 한다.
- NOTICED, NOT TOUCHED: `formatRelativeTime` 이 컴포넌트 파일 `apps/companion/src/ui/TaskRow.tsx` 에 있어 dashboard 번들이 TaskRow 공유 chunk 를 함께 받는다 · `src/ui/TaskRow.tsx` · 시간 포맷터를 `src/ui/time.ts` 같은 순수 모듈로 옮기기
- NOTICED, NOT TOUCHED: `apps/companion/tsconfig.json` 의 `include` 가 `tests/**/*.ts` 만 있어 `.tsx` 테스트는 typecheck 되지 않는다 · tsconfig.json · `tests/**/*.tsx` 추가 후 드러나는 타입 오류 정리
- NOTICED, NOT TOUCHED: 기존 `setup.rs`·`watch_scope_tests.rs` 가 rustfmt 형식과 다르고 CI 에 rustfmt 검사가 없다 · apps/companion/src-tauri · `cargo fmt` 적용과 CI 의 `cargo fmt --check` 도입 검토
