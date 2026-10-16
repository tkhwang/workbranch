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
- 전원 유지는 두 activity 로 나눈다: 시스템 잠자기 방지(`UserInitiated`)는 "기능 켜짐 && 작업 중" 이면 잠김과 상관없이, 디스플레이 잠자기 방지(`IdleDisplaySleepDisabled`)는 거기에 "잠기지 않음" 까지일 때만 건다. 화면이 잠긴 동안(사용자가 잠갔든 R6 으로 잠겼든)은 dashboard 없음, 디스플레이·잠금 화면은 macOS 그대로이고 agent 만 계속 돈다. 잠금이 풀리면 다시 판정한다. (Q4, 구현 중 변경)
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
- R2: 켜고 agent 를 돌리면 `pmset -g assertions` 에 companion 의 `PreventUserIdleSystemSleep` 과 `PreventUserIdleDisplaySleep` 이 보이고, 화면을 잠그면(Ctrl+Cmd+Q) 디스플레이 쪽만 사라지며 잠금을 풀면 다시 보인다. 턴 종료 후에는 둘 다 사라진다. `kill -9` 로 companion 을 죽이면 즉시 사라진다.
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
| 잠긴 채 작업 중인 동안 노트북이 깨어 있어 배터리를 씀 | 배터리 소모 | 작업이 끝나면 바로 해제. 덮개를 닫으면 macOS 규칙대로 잠듦(intent Non-goals). 잠긴 동안 디스플레이는 꺼짐 |
| SQLite 쓰기 방식(WAL·journal) 때문에 파일 이벤트가 몰리거나 빠짐 | 과도한 CLI 실행 또는 반영 지연 | 디렉터리 단위 감시 + debounce, 60초 보조 읽기로 최악 1분 지연 |
| main 창 데이터 경로 변경으로 칸반 회귀(오류 표시, 호환성 안내, uncertain 처리) | 기존 기능 손상 | 기존 테스트 유지 + T0.2 에서 오류·호환성 경로 테스트 추가 |
| 작업 중이 아닐 때 App Nap 으로 Rust 서비스 주기가 늦어짐 | 작업 중 판정이 몇 초 늦음 | 작업 중이 되면 activity 가 App Nap 을 끈다. 시작 지연은 허용 |
| 모니터 연결·해제가 dashboard 표시 중에 일어남 | 새 모니터가 덮이지 않음 | screen parameters 알림을 받으면 창을 다시 맞춘다(T2.2) |

## Coverage
| R-id | slice / task | notes |
|---|---|---|
| — | T0.1, T0.2 | Slice 0 prefactor: R2·R3·R5·R9 가 쓰는 runtime 데이터 경로 |
| R1 | T1.1, T1.2, T1.3, T1.4 | |
| R2 | T1.1, T1.2, F9 | 잠긴 동안 시스템 잠자기 방지 유지(F9) |
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
- 2026-10-16 · (verify) 범위 밖 실패 2건(contract lint 서식, CLI 테스트 2개) → 기존 상태로 기록하고 별도 작업으로 넘김. signoff 를 막지 않음 · COMP001 이 건드리지 않은 코드이고 R-id 영향 없음, 고치면 plan 범위(CLI·contract 무변경)를 넓힘
- 2026-10-16 · (verify 중 발견) dashboard 닫을 때 흰 화면 깜빡임 → Tauri `macos-private-api`(`app.macOSPrivateApi`) 를 켜 dashboard 의 배경색을 webview 층에도 적용하고, 창은 화면에서 먼저 내린 뒤 destroy 한다 · 흰색의 출처(webview 기본 배경)를 없애는 근본 수정. 비공개 API(`drawsBackground`)가 하나 늘지만 이미 `SACLockScreenImmediate` 를 쓰고 brew 배포라 App Store 제약은 원래 해당. main 창은 배경색·투명 지정이 없어 동작이 바뀌지 않음. 창을 숨긴 채 만들고 첫 렌더 뒤에 보이는 방식은 화면을 덮는 시점이 늦어지고 handshake·대체 타이머가 필요해 택하지 않음
- 2026-10-17 · (PR #236 리뷰) 잠금이 오지 않을 때 → 알림만 기다리지 않고 세션 잠금 상태를 표본마다 읽어 확인하고, 2초마다 잠금을 다시 요청(모두 3번, 약 6초)하는 동안 dashboard 를 유지한다. 끝내 잠기지 않으면 잠금 없는 Mac 으로 보고 R7 처럼 닫는다 · 확인되지 않은 2초 타임아웃으로 데스크톱이 드러나는 것은 R6 위반. 잠기지 않는 Mac 에서 dashboard 를 끝없이 유지하면 Cmd-Q 도 막혀 강제 재시동 말고는 돌아갈 길이 없어 택하지 않음
- 2026-10-17 · (PR #236 리뷰) dashboard 가 덮는 동안 앱 메인 메뉴를 떼어 둔다(`AppHandle::remove_menu`/`set_menu`) · Cmd-Q·Cmd-H 같은 메뉴 단축키는 250ms 입력 표본보다 먼저 처리돼 잠금 없이 앱을 끝낼 수 있다. Tauri 는 macOS Cmd-Q 에 `ExitRequested` 를 보장하지 않아(tauri-apps/tauri#9198) 종료 가로채기보다 단축키 자체를 없애는 쪽을 택함. dashboard 는 보기 전용이라 메뉴가 없어도 잃는 것이 없음
- 2026-10-17 · (PR #236 리뷰) Rust 가 runtime 문서를 v1 계약 serde 타입으로 검사하고, `screensaver` 설정을 필드별로 읽는다 · board(`parseRuntimeDocument`)와 Settings(`sanitizeScreensaverConfig`)와 같은 문서·설정을 같은 뜻으로 읽어야 UI 와 서비스가 어긋나지 않음
- 2026-10-17 · (PR #236 CodeRabbit 리뷰) runtime 읽기 실패 → 마지막 판단을 3분(`UNREADABLE_GRACE`, 60초 fallback 읽기 2번 이상) 유지한 뒤에야 작업 중이 아닌 것으로 본다 · 한 번의 timeout·업그레이드 중 실패로 잠자기 방지가 풀려 agent 가 멈추면 안 되고, 계속 실패하는 CLI 가 Mac 을 끝없이 깨워 두어서도 안 됨. 계약을 어긴 문서(읽기는 성공)는 지금처럼 바로 작업 중 아님
- 2026-10-17 · (PR #236 CodeRabbit 리뷰) runtime 디렉터리가 지워졌다 다시 생길 때 watcher 재설정 → 고치지 않음, 근거만 코드 주석으로 남김 · companion 은 macOS 전용(CI·릴리스 macos-15)이고 FSEvents 는 경로 기준이라 같은 watcher 가 삭제·재생성 뒤에도 이벤트를 받음(notify 8.2.0 로 직접 확인). inotify 로 옮길 때만 필요
- 2026-10-17 · (구현 중 변경) Q4 수정: 화면이 잠긴 동안에도 작업 중이면 시스템 잠자기 방지를 유지하고, 디스플레이 잠자기 방지와 dashboard 만 잠김에 따라 푼다. 전원 activity 를 시스템·디스플레이 둘로 나눈다(`HoldAwake`/`HoldDisplay`) · 잠금 화면은 agent 를 멈추지 않고 잠자기가 멈춘다. 기존 Q4 로는 R6 으로 잠긴 뒤 Mac 이 잠들어 agent 가 멈춤. 두 activity 가 각각 `PreventUserIdleSystemSleep`·`PreventUserIdleDisplaySleep` 하나씩만 만드는 것은 Swift probe 로 확인 · 사용자 선택

## Discovered
- follow-up(COMP001 범위 밖): 목록 데이터(workspace monitor 의 root 별 갱신·오류 병합)도 Rust store 로 옮겨, 모든 창이 하나의 push 상태를 구독하는 순수 view 가 되게 한다.
- NOTICED, NOT TOUCHED: `formatRelativeTime` 이 컴포넌트 파일 `apps/companion/src/ui/TaskRow.tsx` 에 있어 dashboard 번들이 TaskRow 공유 chunk 를 함께 받는다 · `src/ui/TaskRow.tsx` · 시간 포맷터를 `src/ui/time.ts` 같은 순수 모듈로 옮기기
- NOTICED, NOT TOUCHED: `apps/companion/tsconfig.json` 의 `include` 가 `tests/**/*.ts` 만 있어 `.tsx` 테스트는 typecheck 되지 않는다 · tsconfig.json · `tests/**/*.tsx` 추가 후 드러나는 타입 오류 정리
- NOTICED, NOT TOUCHED: 기존 `setup.rs`·`watch_scope_tests.rs` 가 rustfmt 형식과 다르고 CI 에 rustfmt 검사가 없다 · apps/companion/src-tauri · `cargo fmt` 적용과 CI 의 `cargo fmt --check` 도입 검토
- NOTICED, NOT TOUCHED: `packages/contract` 의 `src/index.ts`·`tests/contract.test.mjs` 가 biome 서식과 달라 `pnpm --filter @workbranch/contract lint` 가 실패하고, CI 는 이 lint 를 돌리지 않는다 · packages/contract · `biome format --write` 적용 후 CI 에 contract lint 추가 검토
- NOTICED, NOT TOUCHED: macOS 로컬에서 CLI 테스트 2개 실패(`test_add_bare_tty_name_prefills_task_name_on_shared_parent_feature_base`: TTY 출력의 색 코드, `test_stash_cleanup_failure_keeps_saved_ref_and_skips_reset`: rm mock 경로에서 기대한 실패가 나지 않음). CI 는 ubuntu 에서만 돈다 · apps/cli/tests/cases · 깨끗한 checkout 에서 재현 확인 후 테스트를 환경 독립적으로 고치기

## Verification
run: 2026-10-16 23:18 · fix: no · stale: yes

| package | check | command | result | notes |
|---|---|---|---|---|
| companion | typecheck | `pnpm --filter @workbranch/companion typecheck` | pass | config |
| companion | lint · format | `pnpm --filter @workbranch/companion lint` (biome check) | pass | errors 0, warnings 0, infos 110(구현 전과 같음) |
| companion | test (TS) | `pnpm --filter @workbranch/companion test` | pass | 21 files / 237 tests |
| companion | test (Rust) | `cargo test --manifest-path apps/companion/src-tauri/Cargo.toml` | pass | 133 passed, 1 ignored(기존) |
| companion | clippy | `cargo clippy --manifest-path apps/companion/src-tauri/Cargo.toml --all-targets` | pass | 경고 0 · plan Verification plan |
| companion | bundle smoke | `pnpm --filter @workbranch/companion tauri build` | pass | `WorkbranchCompanion.app` 생성 · companion-ci.yml |
| contract | typecheck | `pnpm --filter @workbranch/contract typecheck` | pass | config |
| contract | lint · format | `pnpm --filter @workbranch/contract lint` (biome check) | fail | 기존 상태로 수용(Decision Log, Discovered). `src/index.ts`, `tests/contract.test.mjs` 서식 오류 2건. COMP001 이 건드리지 않은 파일(마지막 변경 3a35216, 2026-10-05)이고 CI 는 이 명령을 돌리지 않는다. R-id 영향 없음 |
| contract | test | `pnpm --filter @workbranch/contract test` | pass | 8 tests |
| agent-runtime | typecheck (build) | `cargo +1.95.0 build --locked --manifest-path apps/agent-runtime/Cargo.toml` | pass | 경고 0. 이 Mac 은 PATH 첫 `cargo` 가 Homebrew 라 `+toolchain` 을 몰라 rustup proxy(`~/.cargo/bin/cargo`)로 같은 명령 실행 |
| agent-runtime | lint · format | — | — | config 에 없음(rustfmt 검사 없음은 Discovered) |
| agent-runtime | test | `cargo +1.95.0 test --locked --manifest-path apps/agent-runtime/Cargo.toml` | pass | 23 tests |
| cli | typecheck (syntax) | `/bin/bash -n bin/workbranch install.sh apps/cli/install.sh apps/cli/bin/workbranch apps/cli/tests/run.sh apps/cli/scripts/build-workbranch.sh` | pass | config · ci.yml |
| cli | lint | `find apps/cli/src/workbranch apps/cli/scripts -type f -name '*.sh' -print0 \| xargs -0 shellcheck -s bash -S warning -e SC2034 install.sh apps/cli/install.sh` | pass | config · ci.yml |
| cli | format | — | — | config 에 없음 |
| cli | test | `apps/cli/scripts/build-workbranch.sh && apps/cli/tests/run.sh` | fail | 기존 상태로 수용(Decision Log, Discovered). 290 passed, 2 failed(아래). COMP001 은 CLI 파일을 하나도 바꾸지 않았고(빌드 후에도 변경 0), CI 는 ubuntu 에서 돌린다. 이 Mac 환경에서의 기존 실패로 보이며 R-id 영향 없음 |

```text
contract lint
src/index.ts format ━━━
  × Formatter would have printed the following content:
    13    │ - ·readonly·name:·string;          (공백 1칸 들여쓰기 → 탭)
    67    │ - export·type·WorkbranchRuntimeDocument·=·{·readonly·schemaVersion:·1;·readonly·sessions:·readonly·WorkbranchAgentSession[]·};
tests/contract.test.mjs format ━━━
  × Formatter would have printed the following content:
Found 2 errors.

cli tests
[*] test_add_bare_tty_name_prefills_task_name_on_shared_parent_feature_base
[-] Error: expected output to contain '  task repo branch [feature/cpq-task1]'; got: … task repo branch [\e[0;35mfeature/cpq-task1\e[0m]: …
[*] test_stash_cleanup_failure_keeps_saved_ref_and_skips_reset
[-] Error: expected output to contain 'stash kept and reset skipped'; got: [-] Error: expected failure: …/apps/cli/bin/workbranch stash
Tests passed: 290
Tests failed: 2
```

| R-id | behaviour check | result | evidence |
|---|---|---|---|
| R1 (MUST) | 기본 꺼짐, 꺼진 채로는 잠자기 방지·dashboard 없음 | human | 설정 기본값·보정은 `tests/preferences.test.ts`, 꺼짐 전이는 `machine_tests.rs` 로 통과. 실제 앱은 Human check 1 |
| R2 (MUST) | 작업 중이면 잠겨도 시스템 잠자기 방지, 잠긴 동안 디스플레이 쪽만 해제, 비정상 종료 시 사라짐 | human | 전이는 `machine_tests.rs` 통과, 같은 activity 가 PreventUserIdleSystemSleep·PreventUserIdleDisplaySleep 을 만드는 것은 구현 중 Swift probe 로 확인. Human check 2 |
| R3 (MUST) | 설정 시간 뒤 dashboard, macOS 화면보호기보다 먼저 | human | Human check 3 |
| R4 (MUST) | 디스플레이 꺼짐 시간보다 오래 dashboard 유지 | human | Human check 4 |
| R5 (MUST) | 작업 중이 끝나면 dashboard 내림, 턴 종료만 있으면 안 뜸 | human | 전이는 `machine_tests.rs` 통과. Human check 5 |
| R6 (MUST) | 입력 시 즉시 macOS 잠금, 데스크톱·키 유출 없음 | human | Human check 6 |
| R7 (MUST) | 잠금 불가 환경에서 표시 숨김, 입력 시 닫힘 | human | 표시 숨김은 `tests/dashboard.test.tsx`, 닫힘 전이는 `machine_tests.rs` 통과. Human check 7 |
| R8 (MUST) | 시안 D 구성, 시계·개수 일치 | human | 렌더 구조는 `tests/dashboard.test.tsx` 통과. Human check 8 |
| R9 (MUST) | 카드 목록·프롬프트·도구 동작·마지막 응답이 메뉴바 칸반과 같음 | human | 모델은 `tests/dashboard-model.test.ts`(같은 `buildMainViewModel` 원천) 통과. Human check 8 |
| R10 (MUST) | 모든 모니터에 dashboard | human | 모니터별 창 배치는 `windows.rs` 테스트 통과. Human check 9 |
| R11 (SHOULD) | "+n more", 스크롤·카드 넘침 없음 | pass (자동) + human | 가장 긴 카드로 채운 화면을 headless Chrome 1280×800·1440×900·1920×1080 렌더 → 세 열 모두 "+n more" 까지 화면 안. 실제 화면은 Human check 8 |
| R12 (SHOULD) | 미리 보기: 즉시 표시, 2초 무시, 잠금 없이 닫힘, 잠자기 방지 없음 | human | 전이는 `machine_tests.rs` 통과. Human check 10 |
| R5·R7·R12 | dashboard 가 닫혀 데스크톱으로 돌아갈 때 흰 화면 깜빡임이 없다 | fail | 사람 확인 중 보고: "dashboard 빠져 나올 때 하얀색으로 깜빡임". 원인: Tauri `macos-private-api` 가 꺼져 있어 `background_color` 가 WKWebView 에 적용되지 않음(wry `drawsBackground` 는 `transparent` 기능에서만 끔) → 창을 destroy 하는 동안 webview 기본 흰 배경이 보임. todo `## Fixes` F1·F2 |

### Human checks
준비: 설치된 Companion 을 종료한다(같은 `~/Library/Application Support/dev.tkhwang.workbranch.companion/companion-preferences.json` 을 쓴다). 방금 빌드한 앱을 `pnpm companion:run` 으로 연다(Slice 5 포함). Settings › Screen Saver 에서 "While agents work" 를 켜고 "Dashboard after" 를 1 min 으로 둔다. "작업 중" 은 터미널에서 Claude Code 등에 몇 분 걸리는 작업을 시켜 실행 중 또는 권한 승인 대기로 만든 상태다.

1. (R1) Companion 을 끄고 위 preference 파일을 다른 이름으로 옮긴 뒤 다시 연다 → Settings 의 스위치가 꺼져 있다. 꺼진 채로 작업을 걸고 3분 비운다 → `pmset -g assertions | grep -i "Workbranch agents"` 결과 없음, dashboard 없음. 확인 후 파일을 되돌린다.
2. (R2) 켠 상태에서 작업을 건다 → `pmset -g assertions | grep -i "Workbranch agents"` 에 `PreventUserIdleSystemSleep` 과 `PreventUserIdleDisplaySleep` 두 줄이 보인다. 턴이 끝나면 둘 다 사라진다. 작업 중에 터미널에서 `(sleep 20; pmset -g assertions | grep -i "Workbranch agents" > /tmp/locked.txt) &` 를 실행하고 바로 Ctrl+Cmd+Q 로 잠근다 → 30초 뒤 풀고 `cat /tmp/locked.txt` 하면 `PreventUserIdleSystemSleep` 한 줄만 있다. 풀린 뒤에는 디스플레이 쪽이 다시 보인다. 잠긴 채 macOS 잠자기 시간보다 오래 둬도 agent 가 계속 진행된다. `kill -9 $(pgrep -x workbranch-companion)` 뒤 즉시 사라진다.
3. (R3) Companion 2 min, 시스템 설정 › 잠금 화면 › 화면보호기 1분으로 두고 작업 중에 비운다 → 2분에 dashboard, 그 전에 macOS 화면보호기가 뜨지 않는다.
4. (R4) 디스플레이 꺼짐 시간(이 Mac 10분)보다 오래(11분 이상) 비운다 → 작업 중이면 dashboard 가 켜져 있다.
5. (R5) dashboard 가 떠 있을 때 마지막 실행 중·대기 세션의 턴이 끝나면 dashboard 가 내려가고 이후 macOS 설정대로 진행된다. 턴 종료만 남은 상태에서는 설정 시간이 지나도 dashboard 가 뜨지 않는다.
6. (R6) dashboard 에서 마우스를 움직인다 → 곧바로 잠금 화면, 데스크톱이 보이지 않는다. 밑에 터미널이 포커스였던 상태에서 키를 눌러 잠근 뒤 풀면 그 키가 터미널에 들어가 있지 않다. dashboard 에서 Cmd-Q, Cmd-H, Cmd-M, Cmd-W 를 각각 눌러도 앱이 끝나거나 숨지 않고 잠금 화면이 된다. 풀고 나면 메뉴바 창에서 Cmd-C/Cmd-V 가 다시 된다(메뉴 복원).
7. (R7) Companion 을 끄고 `WORKBRANCH_SCREENSAVER_NO_LOCK=1 pnpm companion:dev` 로 띄운 뒤 dashboard 를 띄운다 → "입력 시 잠금" 표시가 없고, 입력하면 잠금 없이 dashboard 만 닫힌다.
8. (R8·R9·R11) dashboard 가 상단 시계·날짜·"입력 시 잠금"·상태별 개수, 하단 3열(시안 D + E 카드)이다. 개수와 카드 목록이 메뉴바 칸반과 같고, 각 카드의 프롬프트·도구 동작(대기·실행 중)·마지막 응답(턴 종료)이 메뉴바 카드와 같다. 한 열에 4개 이상이면 "+n more", 긴 프롬프트·응답이 있어도 카드가 잘리거나 화면 아래로 넘치지 않는다(내장·외부 모니터 모두).
9. (R10) 모니터 2대에서 두 화면 모두 dashboard 가 뜨고, 메뉴바·Dock·다른 Space 의 전체 화면 앱 위를 덮는다.
10. (R12, SHOULD) 기능을 끈 채 Settings › Screen Saver › Show now → 모든 모니터에 dashboard 와 "미리 보기 · 입력하면 닫힘". 2초 안의 마우스 움직임으로는 닫히지 않고, 그 뒤 움직이면 잠금 없이 닫힌다. 그동안 `pmset -g assertions | grep -i "Workbranch agents"` 결과 없음.
