# COMP · Screensaver

설정을 켜면 companion 은 agent 가 작업 중인 동안 Mac 이 idle 잠자기에 들어가지 않게 한다. 언제 화면을 덮고 잠글지는 macOS 가 정한다: macOS 화면보호기가 시작되거나 화면이 잠기면 companion 은 Mac 을 잠그고(이미 잠겼으면 그대로), 모든 모니터의 잠금 화면 **위에** dashboard 를 띄우고, 디스플레이가 꺼지지 않게 붙잡는다. 화면은 잠겨 있지만 멀리서 작업 진행이 보이고, Mac 은 잠들지 않는다. 입력이 오면 dashboard 만 비켜 macOS 잠금 화면이 드러나고, macOS 계정 암호나 Touch ID 로 돌아온다 ([COMP002](../../intents/COMP002-lock-screen-dashboard.md)).

꺼져 있으면 companion 은 잠자기·화면보호기·잠금에 관여하지 않는다. 켜져 있어도 새 권한 요청(손쉬운 사용·입력 모니터링·화면 기록)은 없다. companion 은 macOS 의 화면보호기·잠금·잠자기 설정 값을 바꾸지 않고, 별도 암호를 두지 않는다.

## 용어
- **작업 중**: runtime 문서([runtime snapshot](runtime-snapshot.md))에 `observation: "observed"` 이고 `state` 가 `running` 또는 `waiting` 인 세션이 하나 이상 있는 상태. 칸반 `runtimeRole()` 과 같은 기준이다. 턴 종료(`finished`)·`idle` 세션과 `uncertain`·`stale` 관측은 세지 않는다.
- **덮임(covered)**: 기능 켜짐 && 작업 중 && (화면 잠김 || macOS 화면보호기 실행 중). dashboard 와 디스플레이 유지는 덮임 동안에만 있다.

## 설정
- 저장 위치: `companion-preferences.json` 의 `screensaver` 키, `{ enabled: boolean }`. 기본값 `{ enabled: false }`.
- `enabled` 가 boolean 이 아니면 `false` 로 읽는다. COMP002 이전 store 의 `idleMinutes` 는 무시하고, main 창이 시작할 때 키를 지워 다시 저장한다. Settings(`application/screensaver.ts` 의 `sanitizeScreensaverConfig`)와 Rust 서비스(`Config::from_store_value`)가 같은 규칙으로 읽는다.
- Settings › Screen Saver: "While agents work" 스위치와 Preview 의 "Show now" 버튼. dashboard 를 띄우는 시간 설정은 없다. macOS 화면보호기 시간(시스템 설정 › 잠금 화면)이 그 역할을 한다. 바꾸면 저장한 뒤 `screensaver_refresh` 로 서비스가 설정을 다시 읽는다.

## 전원 유지
`NSProcessInfo` activity 두 개를 따로 건다. 이유 문자열은 "Workbranch agents are working" 이다.

| 조건 | activity 옵션 | `pmset -g assertions` |
|---|---|---|
| 켜짐 && 작업 중 (화면 잠김과 무관) | `UserInitiated` | `PreventUserIdleSystemSleep` |
| 덮임 (켜짐 && 작업 중 && (잠김 \|\| 화면보호기)) | `IdleDisplaySleepDisabled` | `PreventUserIdleDisplaySleep` |

- 시스템 쪽은 화면이 잠겨 있어도 유지한다. 잠금 화면은 agent 를 멈추지 않지만 잠자기는 멈추기 때문이다.
- 화면을 쓰는 동안(잠기지 않고 화면보호기도 없을 때)에는 디스플레이 쪽을 걸지 않는다. 그래서 macOS 화면보호기와 그 잠금이 macOS 설정대로 시작된다. 디스플레이 쪽은 화면보호기나 잠금 화면이 뜬 뒤에 걸어 dashboard 가 보이는 동안 디스플레이가 꺼지지 않게 한다. caffeinate 같은 잠자기 방지 utility 가 디스플레이를 붙잡아 화면보호기와 잠금까지 막던 문제를 피한다.
- macOS 디스플레이 끄기 시간이 화면보호기 시간보다 짧으면 디스플레이가 먼저 꺼진다. 이미 꺼진 디스플레이는 companion 이 켜지 않으므로 dashboard 가 보이지 않는다. 화면보호기 시간을 디스플레이 끄기 시간보다 짧게 둔다(이 Mac: 화면보호기 5분, 디스플레이 10분).
- 작업 중이 끝나면(턴 종료만 남거나 세션이 없으면) dashboard 를 내리고 둘 다 푼다. 이후 잠금 화면의 디스플레이 꺼짐과 잠자기는 macOS 기본 동작이다. companion 이 끝나거나 비정상 종료되면 OS 가 회수한다.
- `UserInitiated` activity 는 App Nap 도 끈다. 작업 중이 아닐 때는 App Nap 으로 서비스 주기가 늦어질 수 있다.
- runtime 읽기가 실패하면 마지막 판단을 유지하고, 3분(`UNREADABLE_GRACE`, 60초 보조 읽기 두 번 이상) 넘게 계속 실패할 때만 작업 중이 아닌 것으로 본다. 읽기에는 성공했지만 계약(`schemaVersion` 1, 세션의 모든 필드와 열거값)을 어긴 문서는 바로 작업 중이 아니다. 실패한 읽기는 작업 중을 새로 시작하지 않는다.
- 노트북 덮개를 닫으면 macOS 규칙대로 잠든다. 배터리·전원 상태에 따라 다르게 동작하지 않는다.

## 세션 읽기
- 작업 중인 동안 1초마다(`IDLE_POLL`), dashboard 가 떠 있거나 잠금을 기다리는 동안 0.25초마다(`INPUT_POLL`) 세션을 읽는다: idle 시간은 `CGEventSourceSecondsSinceLastEventType`(HID 시스템 상태, 모든 입력 종류), 잠김은 세션 사전의 `CGSSessionScreenIsLocked`, 화면보호기 실행 여부는 비공개 `login.framework` 의 `SACScreenSaverIsRunning`(loginwindow 에 묻는 동기 호출, 약 0.2ms). 작업 중이 아니면 읽지 않고, 지난 idle 표본을 버린다. runtime snapshot 이 읽기 주기보다 자주 와도 다음 읽기 시각은 밀리지 않는다.
- `NSDistributedNotificationCenter` 의 `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` 는 바로 다시 읽으라는 신호로만 쓴다. 잠김 여부는 언제나 세션에서 읽으므로, 잘못 온 알림이 쓰고 있는 데스크톱 위에 dashboard 를 띄우지 않는다.
- `com.apple.screensaver.didstart` / `com.apple.screensaver.didstop` 도 바로 다시 읽으라는 신호다. 그래서 companion 이 화면보호기가 이미 돌고 있을 때 시작되거나 알림을 놓쳐도 다음 읽기에서 안다. `SACScreenSaverIsRunning` 을 찾지 못하면 이 알림으로만 알고, 멈춤 알림을 놓쳐도 잠금이 풀리거나 잠기지 않은 상태에서 입력이 오면 화면보호기는 끝난 것으로 본다.
- 잠금이 풀리면 화면보호기가 멈춤으로 읽히거나 새로 시작(`didstart`)될 때까지 "실행 중" 판독을 믿지 않는다. Touch ID 로 풀면 키보드·마우스 입력이 없어 idle 이 큰 채로 남으므로, 늦게 온 "실행 중" 판독이 방금 푼 Mac 을 다시 잠그지 않게 하기 위해서다.

## Dashboard 표시와 내림
- 덮임 동안 idle 시간이 15초(`SHOW_AFTER`) 이상이면 dashboard 를 띄운다. 화면보호기는 그보다 훨씬 긴 idle 뒤에 시작하므로 바로 덮이고, 직접 잠근 경우(Ctrl+Cmd+Q)에는 손을 뗀 뒤 15초 뒤에 뜬다.
- 잠금이 가능한 Mac 에서 dashboard 는 세션이 잠김으로 읽힐 때만 보인다. 화면보호기만 시작되었고 아직 잠기지 않았으면(macOS 의 "암호 요구까지 지연"이 남은 경우) 먼저 잠그고, 잠김이 확인되면 띄운다. 잠금은 비공개 `login.framework` 의 `SACLockScreenImmediate`(Ctrl+Cmd+Q 와 같은 잠금)이고, 시작할 때 `dlopen`/`dlsym` 으로 찾는다. 2초(8 표본) 안에 잠기지 않으면 다시 요청하고, 모두 3번(약 6초) 요청해도 잠기지 않으면 이번 화면보호기 동안에는 더 요청하지 않는다. 그때는 디스플레이를 켜 둔 채 dashboard 없이 기다리다가, macOS 가 지연 시간 뒤 스스로 잠그면 띄운다. 그래서 dashboard 가 보이는 동안 Mac 은 잠겨 있고 "화면 잠김" 표시가 거짓이 되지 않으며, 입력해도 암호 없이 데스크톱이 드러나지 않는다. 떠 있는 dashboard 도 세션이 잠김이 아니게 읽히면 바로 내린다.
- 입력이 오면(idle 이 직전 표본보다 줄면) dashboard 만 내린다. 그 아래 잠금 화면에서 암호나 Touch ID 로 잠금을 푼다. 디스플레이 유지는 잠긴 동안 계속되므로 잠금 화면이 켜진 채 남고, 잠금을 풀지 않고 15초 동안 입력이 없으면 dashboard 가 다시 뜬다. 잠긴 상태에서는 띄운 직후 1초(4 표본) 동안의 입력을 무시한다. 잠금 화면이 올라오며 생기는 순간적인 표본이 dashboard 를 바로 내리지 않게 하기 위해서다.
- 잠금이 풀리면(덮임이 끝나면) dashboard 를 내리고 디스플레이 유지를 푼다. 작업 중이 끝나거나 기능을 꺼도 마찬가지다.
- **잠금 불가**: 잠금 심볼을 찾지 못하면 dashboard 는 똑같이 화면보호기와 잠금 화면 위에 뜨되 "화면 잠김" 표시를 숨기고, 직접 잠그지 않는다. 화면보호기만 떠 있을 때 입력이 오면 dashboard 가 내려가고 macOS 설정대로(지연 시간 안이면 암호 없이) 화면보호기가 끝난다. `screensaver_status` command 가 `{ lockAvailable }` 을 돌려준다. 개발용 환경 변수 `WORKBRANCH_SCREENSAVER_NO_LOCK`(값 무관)이 있으면 잠금 불가로 시작한다.

## 창
- 모니터마다 창 하나: 라벨 `dashboard-<n>`, 미리 보기는 `dashboard-preview-<n>`. 모니터 전체 크기, 테두리·그림자 없음, 크기 변경·최소화·닫기 불가, Dock·창 순환에 나오지 않음.
- 잠금 화면 위에 그리기 위해 비공개 SkyLight space 를 쓴다. 처음 띄울 때 `SLSSpaceCreate` 로 space 를 하나 만들고 `SLSSpaceSetAbsoluteLevel` 로 절대 level 400(macOS 가 잠금 화면 위 알림에 쓰는 level, 잠금 화면은 300)을 준 뒤 `SLSShowSpaces` 로 보이고, 창을 `SLSSpaceAddWindowsAndRemoveFromSpaces` 로 그 space 에 옮긴다. space 는 앱이 끝날 때까지 둔다. SkyLight 함수를 하나라도 찾지 못하면 창은 화면보호기 위에만 뜨고 잠금 화면 아래에 가려진다.
- 창 level 은 `CGShieldingWindowLevel() + 1`, collection behavior 는 `CanJoinAllSpaces | FullScreenAuxiliary | Stationary | IgnoresCycle`, `canBecomeVisibleWithoutLogin` 은 참이다.
- dashboard 창은 키보드를 받지 않는다(focus 없음, app 활성화 없음). 잠긴 동안 키 입력은 잠금 화면의 암호 칸으로 간다. 실제 dashboard 는 마우스도 통과시켜 클릭이 잠금 화면에 닿는다. 미리 보기 창은 클릭을 받아, 밑에 있는 앱에 클릭이 가지 않는다.
- 모니터 구성이 바뀌면(`NSApplicationDidChangeScreenParametersNotification`) 지금 모니터 목록에 맞춰 창을 다시 만든다.
- 창과 webview 배경은 `#131313`(Claude 테마 `--surface-0`)이다. Tauri `macOSPrivateApi` 를 켜 webview 의 기본 흰 배경을 그리지 않는다. 내릴 때는 모든 dashboard 창을 먼저 숨긴 뒤 destroy 하므로 열고 닫을 때 흰 화면이 비치지 않는다.
- capability `dashboard`(`dashboard-*` 창 전용)는 `core:event:allow-listen`, `core:event:allow-unlisten`, `store:allow-load`, `store:allow-get` 만 준다.

## 화면 구성
- 별도 Vite 진입점 `dashboard.html`(`src/dashboardMain.tsx` → `src/DashboardApp.tsx`)이라 dashboard 창은 dashboard 코드만 로드한다. 버튼·링크·입력이 없다.
- 상단 왼쪽: 7-segment 시계(현재 시각, 분 단위), 날짜, "화면 잠김" 표시. 표시는 잠금 가능할 때만 보이고, 잠금 가능 여부를 읽기 전에는 숨긴다. 미리 보기에서는 대신 "미리 보기 · 입력하면 닫힘" 을 보인다.
- 상단 오른쪽: 상태별 task 개수(내 응답 대기 · 실행 중 · 턴 종료). companion 칸반의 열별 개수와 같다.
- 하단: 칸반과 같은 3열(내 응답 대기 · 실행 중 · 턴 종료 · 검토)과 같은 상태 색(`--runtime-waiting` / `--runtime-running` / `--runtime-finished`). 열 이름·대기 이유·종료 결과 문구는 `ui/boardCopy.ts` 를 메뉴바 칸반과 함께 쓴다.
- 카드는 `buildMainViewModel()` 이 칸반 3열에 넣는 task 와 같다. 세션 없는·관측 불명·비활성 task 는 나오지 않는다. 각 카드는 lead session 기준으로 task 이름, 그 상태에 들어간 뒤 경과 시간, agent, repo(여러 개면 "+n")·branch, 프롬프트 한 줄, 세부 줄(대기·실행 중: 지금 하는 도구 동작, 턴 종료: 마지막 응답이 있으면 응답, 없으면 도구 동작), 대기 카드의 대기 이유, 턴 종료 카드의 오류로 종료·중단됨 표시, repo 변경 상태 합계(변경 파일 수 · ahead · behind), 알림 수를 보여 준다.
- 글은 runtime 이 저장한 그대로다. 민감 정보 제외와 길이 제한은 수집 단계에서 한다. 잠금 화면 위에 보이므로, 자리를 비운 동안 화면 앞의 누구나 이 내용을 읽을 수 있다.
- 열당 카드는 3장(`DASHBOARD_CARDS_PER_COLUMN`)이고 나머지는 "+n more" 로 줄인다. 세부 줄은 줄 수를 고정해 자르고 크기는 화면 높이(vh)에 비례하므로, 카드가 잘리거나 화면 아래로 넘치지 않고 스크롤이 생기지 않는다.
- 테마와 글꼴은 companion preference 를 따른다.
- 데이터는 main 창과 같은 원천이다: runtime 은 `useRuntimeSessions` 구독, 목록은 workspace monitor 이벤트.

## 미리 보기
- Settings › Screen Saver › Show now(`screensaver_preview`)는 기능 켜짐·작업 중·화면보호기와 상관없이 모든 모니터에 미리 보기 창을 바로 띄운다. 실제 dashboard 가 떠 있으면 무시한다.
- 처음 2초(8 표본)의 입력은 무시하고, 그 뒤 입력이 오면 잠그지 않고 닫는다. 화면이 잠겨도 닫는다.
- 미리 보기 자체는 잠자기 방지와 디스플레이 유지를 걸지 않는다.

## 구조
- `src-tauri/src/screensaver/machine.rs`: 순수 상태 기계. `Machine::step(Event) -> Vec<Action>` 이 설정·작업 중·읽기 실패·화면보호기 알림·세션 표본(idle, 잠김, 화면보호기)·미리 보기를 받아 전원 유지·창·잠금 동작을 낸다. 전이는 `machine_tests.rs` 가 OS 없이 검사한다.
- `screensaver/platform.rs`: OS 동작을 감싼 `Platform` trait. `screensaver/macos.rs`: objc2 typed binding(`objc2-foundation`·`objc2-app-kit`·`objc2-core-graphics`·`objc2-core-foundation`)과 잠금·SkyLight `dlopen` 구현. unsafe 블록마다 SAFETY 주석을 둔다. `screensaver/windows.rs`: 모니터별 창 배치.
- `src-tauri/src/screensaver.rs`: 한 스레드에서 runtime snapshot·설정 변경·잠김 알림·화면보호기 알림·모니터 변경·미리 보기 요청을 받아 상태 기계에 넣고, 상태 기계가 원하는 주기로 세션을 읽는다. command 는 `screensaver_refresh`, `screensaver_status`, `screensaver_preview`.
- 비공개 API(`SACLockScreenImmediate`, `SACScreenSaverIsRunning`, SkyLight space, webview `drawsBackground`)를 쓰므로 Mac App Store 로는 배포할 수 없다. companion 은 Homebrew cask 로 배포한다. 이후 macOS 에서 사라지거나 바뀔 수 있다.
