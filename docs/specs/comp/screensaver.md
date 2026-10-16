# COMP · Screensaver

설정을 켜면 companion 은 agent 가 작업 중인 동안 Mac 이 idle 잠자기에 들어가지 않게 하고, 키보드·마우스 입력 없이 설정 시간이 지나면 모든 모니터에 dashboard 를 띄우며, dashboard 에 입력이 오면 macOS 잠금 화면으로 넘긴다. 자리를 비운 동안 agent 는 계속 일하고, 멀리서 작업 상태가 보이고, 잠금 성공 후에는 macOS 계정 인증으로 돌아온다. 잠금 불가 또는 잠금 요청 실패 시에는 잠금 없이 dashboard 만 닫히므로, dashboard 표시 자체가 잠금을 보장하지는 않는다.

꺼져 있으면 companion 은 잠자기·화면보호기·잠금에 관여하지 않는다. 켜져 있어도 새 권한 요청(손쉬운 사용·입력 모니터링·화면 기록)은 없다. companion 은 macOS 의 화면보호기·잠금·잠자기 설정 값을 바꾸지 않고, 별도 암호를 두지 않는다.

## 용어
- **작업 중**: runtime 문서([runtime snapshot](runtime-snapshot.md))에 `observation: "observed"` 이고 `state` 가 `running` 또는 `waiting` 인 세션이 하나 이상 있는 상태. 칸반 `runtimeRole()` 과 같은 기준이다. 턴 종료(`finished`)·`idle` 세션과 `uncertain`·`stale` 관측은 세지 않는다.
- **무장(armed)**: 기능 켜짐 && 작업 중 && 화면이 잠기지 않음. dashboard 는 무장 중에만 뜬다.

## 설정
- 저장 위치: `companion-preferences.json` 의 `screensaver` 키, `{ enabled: boolean, idleMinutes: number }`. 기본값 `{ enabled: false, idleMinutes: 5 }`.
- 필드마다 따로 읽는다. `enabled` 가 boolean 이 아니면 `false`, `idleMinutes` 가 유한한 숫자가 아니면 `5`, 숫자면 반올림한 뒤 1~60 으로 자른다. Settings(`application/screensaver.ts` 의 `sanitizeScreensaverConfig`)와 Rust 서비스(`Config::from_store_value`)가 같은 규칙으로 읽는다.
- main 창은 시작할 때 보정이 필요한 값을 고쳐 저장하고 서비스에 다시 읽게 한다.
- Settings › Screen Saver: "While agents work" 스위치, "Dashboard after" 분 입력, Preview 의 "Show now" 버튼. 바꾸면 저장한 뒤 `screensaver_refresh` 로 서비스가 설정을 다시 읽는다.

## 전원 유지
`NSProcessInfo` activity 두 개를 따로 건다. 이유 문자열은 "Workbranch agents are working" 이다.

| 조건 | activity 옵션 | `pmset -g assertions` |
|---|---|---|
| 켜짐 && 작업 중 (화면 잠김과 무관) | `UserInitiated` | `PreventUserIdleSystemSleep` |
| 무장 (켜짐 && 작업 중 && 잠기지 않음) | `IdleDisplaySleepDisabled` | `PreventUserIdleDisplaySleep` |

- 시스템 쪽은 화면이 잠겨 있어도(직접 잠갔든 dashboard 입력으로 잠겼든) 유지한다. 잠금 화면은 agent 를 멈추지 않지만 잠자기는 멈추기 때문이다. 잠긴 동안 디스플레이 꺼짐과 잠금 화면은 macOS 기본 동작 그대로다.
- 디스플레이 쪽이 걸려 있는 동안에는 macOS 화면보호기와 그 잠금도 뜨지 않는다. 그 자리를 dashboard 가 대신한다.
- 작업 중이 끝나면(턴 종료만 남거나 세션이 없으면) 둘 다 푼다. companion 이 끝나거나 비정상 종료되면 OS 가 회수한다.
- `UserInitiated` activity 는 App Nap 도 끈다. 작업 중이 아닐 때는 App Nap 으로 서비스 주기가 늦어질 수 있다.
- runtime 읽기가 실패하면 마지막 판단을 유지하고, 3분(`UNREADABLE_GRACE`, 60초 보조 읽기 두 번 이상) 넘게 계속 실패할 때만 작업 중이 아닌 것으로 본다. 읽기에는 성공했지만 계약(`schemaVersion` 1, 세션의 모든 필드와 열거값)을 어긴 문서는 바로 작업 중이 아니다. 실패한 읽기는 작업 중을 새로 시작하지 않는다.
- 노트북 덮개를 닫으면 macOS 규칙대로 잠든다. 배터리·전원 상태에 따라 다르게 동작하지 않는다.

## Dashboard 표시와 내림
- idle 시간은 `CGEventSourceSecondsSinceLastEventType`(HID 시스템 상태, 모든 입력 종류)로 잰다. 알림 API 가 없어 무장 중에만 polling 한다: 평소 1초, dashboard 표시 중 0.25초. 무장이 아니면 재지 않고, 무장이 풀릴 때 지난 표본을 버린다.
- 무장 중 idle 시간이 설정 시간 이상이면 dashboard 를 띄운다. 작업 중이면 이 시간이 macOS 화면보호기 시간보다 길어도 화면보호기가 먼저 뜨지 않는다.
- 무장이 풀리면(작업 중 끝, 기능 꺼짐, 화면 잠김) dashboard 를 바로 내린다. 화면이 잠긴 동안에는 띄우지 않는다. 잠금이 풀리면 다시 판정한다.
- 화면 잠김·해제는 `NSDistributedNotificationCenter` 의 `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` 로 받고, 시작할 때 세션 잠금 상태(`CGSSessionScreenIsLocked`)를 한 번 읽는다.

## 입력 시 잠금
- dashboard 는 보기 전용이다. 표시 중 idle 시간이 직전 표본보다 줄면(입력) 잠금을 요청한다. 잠금은 비공개 `login.framework` 의 `SACLockScreenImmediate`(Ctrl+Cmd+Q 와 같은 잠금)이고, 시작할 때 `dlopen`/`dlsym` 으로 찾는다. 해제는 macOS 계정 암호나 Touch ID 로만 된다.
- dashboard 는 잠김이 확인될 때까지 떠 있어 데스크톱이 드러나지 않고 키가 밑의 앱으로 가지 않는다. 기다리는 동안 0.25초마다 세션 잠금 상태를 직접 읽어, 잠금 알림이 늦어도 잠김을 확인한다.
- 2초(8 표본) 안에 잠기지 않으면 다시 요청한다. 모두 3번(약 6초) 요청해도 잠기지 않으면 잠금 없는 Mac 으로 보고 dashboard 만 닫는다.
- 잠기면 무장이 풀려 dashboard 가 내려가므로, 잠금을 풀면 원래 화면이다.
- **잠금 불가**: 잠금 심볼을 찾지 못하면 dashboard 는 똑같이 뜨되 "입력 시 잠금" 표시를 숨기고, 입력이 오면 잠금 없이 dashboard 만 닫는다. `screensaver_status` command 가 `{ lockAvailable }` 을 돌려준다. 개발용 환경 변수 `WORKBRANCH_SCREENSAVER_NO_LOCK`(값 무관)이 있으면 잠금 불가로 시작한다.

## 창
- 모니터마다 창 하나: 라벨 `dashboard-<n>`, 미리 보기는 `dashboard-preview-<n>`. 모니터 전체 크기, 테두리·그림자 없음, 크기 변경·최소화·닫기 불가, Dock·창 순환에 나오지 않음.
- 창 level 은 `NSScreenSaverWindowLevel`, collection behavior 는 `CanJoinAllSpaces | FullScreenAuxiliary | Stationary | IgnoresCycle` 이라 메뉴바·Dock·다른 Space 의 전체 화면 앱 위를 덮는다.
- 띄울 때 companion 을 활성화하고 주 모니터의 창을 key window 로 만든다. 잠기기 전에 눌린 키는 dashboard 가 받는다.
- 덮는 동안에는 앱 메인 메뉴를 떼어 Cmd-Q·Cmd-H·Cmd-M·Cmd-W 같은 메뉴 단축키가 듣지 않고, 내릴 때 되돌린다.
- 모니터 구성이 바뀌면(`NSApplicationDidChangeScreenParametersNotification`) 지금 모니터 목록에 맞춰 창을 다시 만든다.
- 창과 webview 배경은 `#131313`(Claude 테마 `--surface-0`)이다. Tauri `macOSPrivateApi` 를 켜 webview 의 기본 흰 배경을 그리지 않는다. 내릴 때는 모든 dashboard 창을 먼저 숨긴 뒤 destroy 하므로 열고 닫을 때 흰 화면이 비치지 않는다.
- capability `dashboard`(`dashboard-*` 창 전용)는 `core:event:allow-listen`, `core:event:allow-unlisten`, `store:allow-load`, `store:allow-get` 만 준다.

## 화면 구성
- 별도 Vite 진입점 `dashboard.html`(`src/dashboardMain.tsx` → `src/DashboardApp.tsx`)이라 dashboard 창은 dashboard 코드만 로드한다. 버튼·링크·입력이 없다.
- 상단 왼쪽: 7-segment 시계(현재 시각, 분 단위), 날짜, "입력 시 잠금" 표시. 표시는 잠금 가능할 때만 보이고, 잠금 가능 여부를 읽기 전에는 숨긴다. 미리 보기에서는 대신 "미리 보기 · 입력하면 닫힘" 을 보인다.
- 상단 오른쪽: 상태별 task 개수(내 응답 대기 · 실행 중 · 턴 종료). companion 칸반의 열별 개수와 같다.
- 하단: 칸반과 같은 3열(내 응답 대기 · 실행 중 · 턴 종료 · 검토)과 같은 상태 색(`--runtime-waiting` / `--runtime-running` / `--runtime-finished`). 열 이름·대기 이유·종료 결과 문구는 `ui/boardCopy.ts` 를 메뉴바 칸반과 함께 쓴다.
- 카드는 `buildMainViewModel()` 이 칸반 3열에 넣는 task 와 같다. 세션 없는·관측 불명·비활성 task 는 나오지 않는다. 각 카드는 lead session 기준으로 task 이름, 그 상태에 들어간 뒤 경과 시간, agent, repo(여러 개면 "+n")·branch, 프롬프트 한 줄, 세부 줄(대기·실행 중: 지금 하는 도구 동작, 턴 종료: 마지막 응답이 있으면 응답, 없으면 도구 동작), 대기 카드의 대기 이유, 턴 종료 카드의 오류로 종료·중단됨 표시, repo 변경 상태 합계(변경 파일 수 · ahead · behind), 알림 수를 보여 준다.
- 글은 runtime 이 저장한 그대로다. 민감 정보 제외와 길이 제한은 수집 단계에서 한다.
- 열당 카드는 3장(`DASHBOARD_CARDS_PER_COLUMN`)이고 나머지는 "+n more" 로 줄인다. 세부 줄은 줄 수를 고정해 자르고 크기는 화면 높이(vh)에 비례하므로, 카드가 잘리거나 화면 아래로 넘치지 않고 스크롤이 생기지 않는다.
- 테마와 글꼴은 companion preference 를 따른다.
- 데이터는 main 창과 같은 원천이다: runtime 은 `useRuntimeSessions` 구독, 목록은 workspace monitor 이벤트.

## 미리 보기
- Settings › Screen Saver › Show now(`screensaver_preview`)는 기능 켜짐·작업 중·idle 시간과 상관없이 모든 모니터에 미리 보기 창을 바로 띄운다. 실제 dashboard 가 떠 있으면 무시한다.
- 처음 2초(8 표본)의 입력은 무시하고, 그 뒤 입력이 오면 잠그지 않고 닫는다. 화면이 잠겨도 닫는다.
- 미리 보기 자체는 잠자기 방지를 걸지 않는다.

## 구조
- `src-tauri/src/screensaver/machine.rs`: 순수 상태 기계. `Machine::step(Event) -> Vec<Action>` 이 설정·작업 중·읽기 실패·잠김·idle 표본·미리 보기 입력을 받아 전원 유지·창·잠금 동작을 낸다. 전이는 `machine_tests.rs` 가 OS 없이 검사한다.
- `screensaver/platform.rs`: OS 동작을 감싼 `Platform` trait. `screensaver/macos.rs`: objc2 typed binding(`objc2-foundation`·`objc2-app-kit`·`objc2-core-graphics`)과 잠금 `dlopen` 구현. unsafe 블록마다 SAFETY 주석을 둔다. `screensaver/windows.rs`: 모니터별 창 배치.
- `src-tauri/src/screensaver.rs`: 한 스레드에서 runtime snapshot·설정 변경·잠김 알림·모니터 변경·미리 보기 요청을 받아 상태 기계에 넣고, 상태 기계가 원하는 주기로 idle 시간이나 잠금 상태를 표본한다. command 는 `screensaver_refresh`, `screensaver_status`, `screensaver_preview`.
- 비공개 API(`SACLockScreenImmediate`, webview `drawsBackground`)를 쓰므로 Mac App Store 로는 배포할 수 없다. companion 은 Homebrew cask 로 배포한다.
