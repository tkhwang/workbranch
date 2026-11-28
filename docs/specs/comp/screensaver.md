# COMP · Screensaver

설정을 켜면 companion 은 agent 가 작업 중인 동안 Mac 이 idle 잠자기에 들어가지 않게 한다. 언제 화면을 덮고 잠글지는 macOS 가 정한다: macOS 화면보호기가 시작되거나 화면이 잠기면 companion 은 Mac 을 잠그고(이미 잠겼으면 그대로), 모든 모니터의 잠금 화면 **위에** dashboard 를 띄우고, 디스플레이가 꺼지지 않게 붙잡는다. 화면은 잠겨 있지만 멀리서 작업 진행이 보이고, Mac 은 잠들지 않는다. 작업 중이 아니어도 덮임은 최대 30분 이어져, 턴이 끝난 뒤 자리를 비워도 결과가 보인다. 그 뒤에는 macOS 가 디스플레이와 잠자기를 돌려받는다. 입력이 오면 dashboard 만 비켜 macOS 잠금 화면이 드러나고, macOS 계정 암호나 Touch ID 로 돌아온다 ([COMP002](../../intents/COMP002-lock-screen-dashboard.md)). dashboard 는 task 마다 최근 3시간을 그린 링으로 작업 상태·진행·결과를 보인다 ([COMP004](../../intents/COMP004-ring-dashboard.md)).

꺼져 있으면 companion 은 잠자기·화면보호기·잠금에 관여하지 않는다. 켜져 있어도 새 권한 요청(손쉬운 사용·입력 모니터링·화면 기록)은 없다. companion 은 macOS 의 화면보호기·잠금·잠자기 설정 값을 바꾸지 않고, 별도 암호를 두지 않는다.

## 용어
- **작업 중**: runtime 문서([runtime snapshot](runtime-snapshot.md))에 `observation: "observed"` 이고 `state` 가 `running` 또는 `waiting` 인 세션이 하나 이상 있는 상태. 칸반 `runtimeRole()` 과 같은 기준이다. 턴 종료(`finished`)·`idle` 세션과 `uncertain`·`stale` 관측은 세지 않는다.
- **자리 비움(away)**: 화면 잠김 || macOS 화면보호기 실행 중.
- **무작업 덮임 시간**(`COVER_WITHOUT_WORK`, 30분): 자리 비움 중 작업 중이 아닌 시간의 상한. "자리 비움이 시작된 시각"과 "자리 비움 중 작업 중이 끝난 시각" 중 늦은 쪽부터 잰다. 시각은 세션 읽기마다 붙는 monotonic 시계(서비스 시작 기준)로 재므로, 상한은 그 조건이 된 뒤 첫 읽기부터 센다. 다하면 같은 자리 비움 동안에는 다시 덮지 않고, 그 사이 기능을 껐다 켜도 마찬가지다. 작업 중이 다시 시작되면 바로 덮고, 다시 끝나면 그때부터 새로 잰다. 잠금이 풀리면(자리 비움이 끝나면) 초기화된다.
- **덮임(covered)**: 기능 켜짐 && 자리 비움 && (작업 중 || 무작업 덮임 시간이 남음). dashboard 와 디스플레이 유지는 덮임 동안에만 있다.

## 설정
- 저장 위치: `companion-preferences.json` 의 `screensaver` 키, `{ enabled: boolean, showMessages: boolean }`. 기본값 `{ enabled: false, showMessages: false }`.
- `enabled`·`showMessages` 가 없거나 boolean 이 아니면 `false` 로 읽는다(`showMessages` 가 없던 store 는 main 창이 시작할 때 채워 다시 저장한다). `showMessages` 는 dashboard 창만 읽고, Rust 서비스는 `enabled` 만 읽는다. COMP002 이전 store 의 `idleMinutes` 는 무시하고, main 창이 시작할 때 키를 지워 다시 저장한다. Settings(`application/screensaver.ts` 의 `sanitizeScreensaverConfig`)와 Rust 서비스(`Config::from_store_value`)가 같은 규칙으로 읽는다.
- Settings › Screen Saver(페이지 제목 "Dashboard over the lock screen"): "Cover the lock screen" 스위치, "Show work details" 스위치(기본 꺼짐, 저장 키는 예전 이름 그대로 `screensaver.showMessages`), Preview 의 "Show now" 버튼. dashboard 를 띄우는 시간 설정은 없다. macOS 화면보호기 시간(시스템 설정 › 잠금 화면)이 그 역할을 한다. 바꾸면 저장한 뒤 `screensaver_refresh` 로 서비스가 설정을 다시 읽는다.

## 전원 유지
`NSProcessInfo` activity 두 개를 따로 건다. 이유 문자열은 "Workbranch agents are working" 이다.

| 조건 | activity 옵션 | `pmset -g assertions` |
|---|---|---|
| (켜짐 && 작업 중) \|\| 덮임 (화면 잠김과 무관) | `UserInitiated` | `PreventUserIdleSystemSleep` |
| 덮임 | `IdleDisplaySleepDisabled` | `PreventUserIdleDisplaySleep` |

- 시스템 쪽은 화면이 잠겨 있어도 유지한다. 잠금 화면은 agent 를 멈추지 않지만 잠자기는 멈추기 때문이다. 덮인 동안에는 작업 중이 아니어도 유지한다. 잠들면 dashboard 도 사라지기 때문이다.
- 화면을 쓰는 동안(잠기지 않고 화면보호기도 없을 때)에는 디스플레이 쪽을 걸지 않는다. 그래서 macOS 화면보호기와 그 잠금이 macOS 설정대로 시작된다. 디스플레이 쪽은 화면보호기나 잠금 화면이 뜬 뒤에 걸어 dashboard 가 보이는 동안 디스플레이가 꺼지지 않게 한다. caffeinate 같은 잠자기 방지 utility 가 디스플레이를 붙잡아 화면보호기와 잠금까지 막던 문제를 피한다.
- macOS 디스플레이 끄기 시간이 화면보호기 시간보다 짧으면 디스플레이가 먼저 꺼진다. 이미 꺼진 디스플레이는 companion 이 켜지 않으므로 dashboard 가 보이지 않는다. 화면보호기 시간을 디스플레이 끄기 시간보다 짧게 둔다(이 Mac: 화면보호기 5분, 디스플레이 10분).
- 화면을 쓰는 동안 작업 중이 끝나면(턴 종료만 남거나 세션이 없으면) 시스템 쪽을 푼다. 덮인 동안 작업 중이 끝나면 무작업 덮임 시간 동안 dashboard 와 둘 다 유지하고, 그 시간이 다하면 dashboard 를 내리고 둘 다 푼다. 이후 잠금 화면의 디스플레이 꺼짐과 잠자기는 macOS 기본 동작이다. 작업이 없는 밤에 Mac 이 아침까지 깨어 있지 않게 하는 상한이다. companion 이 끝나거나 비정상 종료되면 OS 가 회수한다.
- `UserInitiated` activity 는 App Nap 도 끈다. 작업 중도 덮임도 아닐 때는 App Nap 으로 서비스 주기가 늦어질 수 있다.
- runtime 읽기가 실패하면 마지막 판단을 유지하고, 3분(`UNREADABLE_GRACE`, 60초 보조 읽기 두 번 이상) 넘게 계속 실패할 때만 작업 중이 아닌 것으로 본다. 읽기에는 성공했지만 계약(`schemaVersion` 1, 세션의 모든 필드와 열거값)을 어긴 문서는 바로 작업 중이 아니다. 실패한 읽기는 작업 중을 새로 시작하지 않는다.
- 노트북 덮개를 닫으면 macOS 규칙대로 잠든다. 배터리·전원 상태에 따라 다르게 동작하지 않는다.

## 세션 읽기
- 작업 중이거나 덮인 동안 1초마다(`IDLE_POLL`), dashboard 가 떠 있거나 잠금을 기다리는 동안 0.25초마다(`INPUT_POLL`) 세션을 읽는다: idle 시간은 `CGEventSourceSecondsSinceLastEventType`(HID 시스템 상태, 모든 입력 종류), 잠김은 세션 사전의 `CGSSessionScreenIsLocked`, 화면보호기 실행 여부는 비공개 `login.framework` 의 `SACScreenSaverIsRunning`(loginwindow 에 묻는 동기 호출, 약 0.2ms). 작업 중도 덮임도 아니면 주기적으로 읽지 않고(아래 알림이 오면 읽는다), 지난 idle 표본을 버린다. 읽기마다 서비스 시작 기준 monotonic 시각을 붙여 무작업 덮임 시간을 잰다. runtime snapshot 이 읽기 주기보다 자주 와도 다음 읽기 시각은 밀리지 않는다.
- `NSDistributedNotificationCenter` 의 `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` 는 바로 다시 읽으라는 신호로만 쓴다. 잠김 여부는 언제나 세션에서 읽으므로, 잘못 온 알림이 쓰고 있는 데스크톱 위에 dashboard 를 띄우지 않는다.
- `com.apple.screensaver.didstart` / `com.apple.screensaver.didstop` 도 바로 다시 읽으라는 신호다. 그래서 companion 이 화면보호기가 이미 돌고 있을 때 시작되거나 알림을 놓쳐도 다음 읽기에서 안다. `SACScreenSaverIsRunning` 을 찾지 못하면 이 알림으로만 알고, 멈춤 알림을 놓쳐도 잠금이 풀리거나 잠기지 않은 상태에서 입력이 오면 화면보호기는 끝난 것으로 본다.
- 잠금이 풀리면 화면보호기가 멈춤으로 읽히거나 새로 시작(`didstart`)될 때까지 "실행 중" 판독을 믿지 않는다. Touch ID 로 풀면 키보드·마우스 입력이 없어 idle 이 큰 채로 남으므로, 늦게 온 "실행 중" 판독이 방금 푼 Mac 을 다시 잠그지 않게 하기 위해서다.

## Dashboard 표시와 내림
- 덮임 동안 idle 시간이 15초(`SHOW_AFTER`) 이상이면 dashboard 를 띄운다. 화면보호기는 그보다 훨씬 긴 idle 뒤에 시작하므로 바로 덮이고, 직접 잠근 경우(Ctrl+Cmd+Q)에는 손을 뗀 뒤 15초 뒤에 뜬다.
- 잠금이 가능한 Mac 에서 dashboard 는 세션이 잠김으로 읽힐 때만 보인다. 화면보호기만 시작되었고 아직 잠기지 않았으면(macOS 의 "암호 요구까지 지연"이 남은 경우) 먼저 잠그고, 잠김이 확인되면 띄운다. 잠금은 비공개 `login.framework` 의 `SACLockScreenImmediate`(Ctrl+Cmd+Q 와 같은 잠금)이고, 시작할 때 `dlopen`/`dlsym` 으로 찾는다. 2초(8 표본) 안에 잠기지 않으면 다시 요청하고, 모두 3번(약 6초) 요청해도 잠기지 않으면 이번 화면보호기 동안에는 더 요청하지 않는다. 그때는 디스플레이를 켜 둔 채 dashboard 없이 기다리다가, macOS 가 지연 시간 뒤 스스로 잠그면 띄운다. 그래서 dashboard 가 보이는 동안 Mac 은 잠겨 있고 "화면 잠김" 표시가 거짓이 되지 않으며, 입력해도 암호 없이 데스크톱이 드러나지 않는다. 떠 있는 dashboard 도 세션이 잠김이 아니게 읽히면 바로 내린다.
- 입력이 오면(idle 이 직전 표본보다 줄면) dashboard 만 내린다. 그 아래 잠금 화면에서 암호나 Touch ID 로 잠금을 푼다. 디스플레이 유지는 잠긴 동안 계속되므로 잠금 화면이 켜진 채 남고, 잠금을 풀지 않고 15초 동안 입력이 없으면 dashboard 가 다시 뜬다. 잠긴 상태에서는 띄운 직후 1초(4 표본) 동안의 입력을 무시한다. 잠금 화면이 올라오며 생기는 순간적인 표본이 dashboard 를 바로 내리지 않게 하기 위해서다.
- 잠금이 풀리면(덮임이 끝나면) dashboard 를 내리고 디스플레이 유지를 푼다. 무작업 덮임 시간이 다하거나 기능을 꺼도 마찬가지다. 덮인 동안 작업 중이 끝나는 것만으로는 내리지 않는다.
- **잠금 불가**: 잠금 심볼을 찾지 못하면 dashboard 는 똑같이 화면보호기와 잠금 화면 위에 뜨되 "화면 잠김" 표시를 숨기고, 직접 잠그지 않는다. 화면보호기만 떠 있을 때 입력이 오면 dashboard 가 내려가고 macOS 설정대로(지연 시간 안이면 암호 없이) 화면보호기가 끝난다. `screensaver_status` command 가 `{ lockAvailable }` 을 돌려준다. 개발용 환경 변수 `WORKBRANCH_SCREENSAVER_NO_LOCK`(값 무관)이 있으면 잠금 불가로 시작한다.

## 창
- 모니터마다 창 하나: 라벨 `dashboard-<n>-<번호>`, 미리 보기는 `dashboard-preview-<n>-<번호>`. `<n>` 은 모니터 순서, `<번호>` 는 창을 열 때마다 1씩 늘어난다. Tauri 는 창이 destroy 를 마친 뒤에야 라벨을 놓아 주므로, 새 창이 destroy 중인 창과 라벨이 겹쳐 열리지 못하는 일이 없다. 모니터 전체 크기, 테두리·그림자 없음, 크기 변경·최소화·닫기 불가, Dock·창 순환에 나오지 않음.
- 잠금 화면 위에 그리기 위해 비공개 SkyLight space 를 쓴다. 처음 띄울 때 `SLSSpaceCreate` 로 space 를 하나 만들고 `SLSSpaceSetAbsoluteLevel` 로 절대 level 400(macOS 가 잠금 화면 위 알림에 쓰는 level, 잠금 화면은 300)을 준 뒤 `SLSShowSpaces` 로 보이고, 창을 `SLSSpaceAddWindowsAndRemoveFromSpaces` 로 그 space 에 옮긴다. space 는 앱이 끝날 때까지 둔다. SkyLight 함수를 하나라도 찾지 못하면 창은 화면보호기 위에만 뜨고 잠금 화면 아래에 가려진다.
- 창 level 은 `CGShieldingWindowLevel() + 1`, collection behavior 는 `CanJoinAllSpaces | FullScreenAuxiliary | Stationary | IgnoresCycle`, `canBecomeVisibleWithoutLogin` 은 참이다.
- dashboard 창은 키보드를 받지 않는다(focus 없음, app 활성화 없음). 잠긴 동안 키 입력은 잠금 화면의 암호 칸으로 간다. 실제 dashboard 는 마우스도 통과시켜 클릭이 잠금 화면에 닿는다. 미리 보기 창은 클릭을 받아, 밑에 있는 앱에 클릭이 가지 않는다.
- 모니터 구성 알림(`NSApplicationDidChangeScreenParametersNotification`)이 오면 지금 모니터 목록과 떠 있는 창을 비교해, 창이 없는 모니터에만 창을 열고, 사라진 모니터의 창은 닫고, 위치·크기가 바뀐 모니터의 창만 옮긴다. 그대로인 창은 건드리지 않는다. macOS 는 XDR 디스플레이의 밝기가 바뀔 때마다(EDR headroom 변화) 이 알림을 초당 수십 번 보내므로, 알림마다 창을 다시 만들면 dashboard 가 깜빡이고, 같은 라벨의 창이 아직 destroy 중일 때 새 창을 못 만들어 dashboard 가 잠금 해제 때까지 사라진다. companion 이 직접 열고 아직 닫지 않은 창만 비교 대상으로 삼으므로 destroy 중인 창을 다시 쓰지 않는다. 모니터 목록을 읽지 못하면 떠 있는 창을 그대로 둔다. 창을 열거나 옮기지 못했거나 창이 사라졌으면, 다음 알림이나 다음 표시 때 다시 연다(옮기기는 위치와 크기가 둘 다 바뀌었을 때만 끝난 것으로 본다).
- 창과 webview 배경은 `#131313`(Claude 테마 `--surface-0`)이다. Tauri `macOSPrivateApi` 를 켜 webview 의 기본 흰 배경을 그리지 않는다. 내릴 때는 모든 dashboard 창을 먼저 숨긴 뒤 destroy 하므로 열고 닫을 때 흰 화면이 비치지 않는다.
- capability `dashboard`(`dashboard-*` 창 전용)는 `core:event:allow-listen`, `core:event:allow-unlisten`, `store:allow-load`, `store:allow-get` 만 준다.

## 화면 구성
- 별도 Vite 진입점 `dashboard.html`(`src/dashboardMain.tsx` → `src/DashboardApp.tsx`)이라 dashboard 창은 dashboard 코드만 로드한다. 버튼·링크·입력이 없다.
- 상단 왼쪽: 7-segment 시계(현재 시각, 분 단위. 끝이 뾰족한 segment, 화면 높이의 8%, 6° 기울임), 날짜, "화면 잠김" 표시. 표시는 잠금 가능할 때만 보이고, 잠금 가능 여부를 읽기 전에는 숨긴다. 미리 보기에서는 대신 "미리 보기 · 입력하면 닫힘" 을 보인다.
- 상단 오른쪽: 활성 세션(세 열의 task 수 합계)을 먼저 보이고, 구분선 뒤에 상태별 task 개수를 일의 흐름 순서(실행 중 · 내 응답 대기 · 턴 종료)로 보인다. 상태별 개수는 companion 칸반의 열별 개수와 같다.
- 하단: task 링. task 는 `buildMainViewModel()` 이 칸반 3열에 넣는 task 와 같고(세션 없는·관측 불명·비활성 task 는 없다), 칸반 순서(내 응답 대기 → 실행 중 → 턴 종료, 각 열 안에서는 최근 활동 순)로 놓는다(`application/dashboardLayout.ts`). 실행 중·대기 task 가 3개 이하이면 큰 링을 최대 3개 나란히 놓고, 남는 자리는 턴 종료 task 가 채운다. 4개이면 작은 링 2×2, 5~6개이면 작은 링 3×2 격자이고, 격자에는 실행 중·대기 task 만 들어간다. 링에 들지 못한 task 는 아래 한 줄에 "+n more · branch 상태 경과 시간" 으로 모은다(턴 종료 task 는 요약을 붙인다, 아래 턴 종료 요약). task 가 없으면 "진행 중인 작업 없음" 을 보인다.
- 링 한 바퀴는 최근 3시간이다(`application/ring.ts`). 맨 위가 지금이고, 지금과 3시간 전 사이에 8° 틈을 둔다. 기록은 시계 방향으로 오래된 것에서 새것으로 흐르고, 시간이 지나면 링이 돈다. 링 선은 runtime 의 상태 전환 기록(`transitions`)으로 그린다: 실행 중은 초록 실선, 내 응답 대기는 굵은 주황 띠, 턴 종료는 노란 점선이다. 턴이 끝난 자리에는 점을 찍고, 오류(`StopFailure`)로 끝났으면 × 를 그린다(중간에 도구가 실패했어도 agent 가 이어서 정상 종료했으면, 그리고 중단이면 보통 점). 한 task 의 세션(subagent 포함)이 겹치면 칸반과 같은 우선순위(대기 > 실행 > 종료)로 하나의 선으로 합친다. 칸반처럼 확인되지 않은 현재는 그리지 않는다: stale 세션은 마지막 이벤트 시각에서 선을 끊고, 관측 불명(uncertain) 세션은 현재 상태를 그리지 않는다. 기록이 없는 세션(이전 수집기)은 현재 상태만 상태 시작 시각부터 그린다. 상태 구간과 글 정리 규칙은 `application/taskHistory.ts` 에 있다.
- 링 가운데: 내 응답 대기는 "응답 대기" 와 대기 이유(질문 · 권한 요청 · 계획 승인 · 입력 요청)·경과 시간, 실행 중은 경과 시간, 턴 종료는 "✓ 턴 종료"(오류로 끝났으면 "✕ 오류로 끝남". lead session 의 `outcome` 이 있으면 그것으로 정하고, 없을 때만 기록의 마지막 turn 끝으로 정한다. 그래서 기록이 없는 이전 수집기의 세션도 알아보고, 다른 세션의 예전 오류가 lead 의 성공을 덮지 않는다)와 "12분 전" 같은 경과다. 대기 중인 링은 바깥 테두리가 천천히 밝아졌다 어두워지고, 실행 중인 링은 지금 위치에서 맥박이 퍼진다. 두 애니메이션은 `opacity`·`transform` 만 바꾸고, `prefers-reduced-motion` 이면 멈춘다.
- 큰 링에는 30분 눈금과 "지금" · "1시간 전" · "2시간 전" label 이 있고, 작은 링에는 label 이 없다. 링 위에는 agent·상태 알약과 그 아래 worktree branch(첫 repo 의 branch, 없으면 task 이름, 길면 말줄임)·repo(여러 개면 +n)를 보인다. 알약은 둘로 나뉜다: 왼쪽은 task 의 모든 세션의 agent(lead 먼저, 같은 provider 는 한 번)를 무채색 아이콘(모양)과 짧은 이름("Claude", "Codex", "Grok", 여럿이면 "Claude + Codex")으로만 보이고 색을 쓰지 않는다. 오른쪽은 상태(실행 중 · 내 응답 대기 · 턴 종료, 마지막 turn 이 오류로 끝났으면 "오류로 끝남")와 경과 시간을 상태 색 배경으로 보이고, 상태마다 점 모양이 다르다(실행 중: 깜빡이는 점, 대기: 천천히 밝아지는 점, 턴 종료: 빈 원, 오류: ×). agent 색과 상태 색이 겹치지 않도록 색은 상태만 쓴다. 큰 링 아래에는 work details 만 남는다. 2×2 격자의 작은 링은 링이 왼쪽, 글이 오른쪽이고 branch·repo 아래에 알약을 둔다. lead session 은 task 의 상태와 같은 상태의 관측된 세션이고, 없으면 칸반의 첫 세션이다. repo 이름은 이름으로 정해지는 4가지 색 `--repo-1`~`--repo-4` 중 하나라 같은 repo 는 어느 링에서나 같은 색이고, "+n" 은 흐리게 보인다. 크기는 화면 높이(vh)에 비례하고, 격자의 칸은 dashboard 너비를 나눠 쓰고 작은 링은 높이와 너비 중 좁은 쪽(`min(24vh, 18vw)`, 3열은 `min(22vh, 16vw)`)에 맞추므로 세로 화면에서도 넘치지 않으며 스크롤이 생기지 않는다. 링 그림은 화면 낭독기에서 숨기는 대신, 그림의 숫자(대기 이유, todo 수, 최근 호출 수, 턴 종료 요약)를 보이지 않는 글로 함께 둔다. 이 글도 같은 화면 모델에서 만들어 work details 규칙을 따른다.
- 큰 링 안쪽에는 최근 3시간의 tool 호출을 시각 각도에 점으로 찍는다(runtime `calls`, 실패한 호출은 ×). 도구는 11개 묶음(Bash · Read · Edit · Write · Search · Web · Agent · Todo · Ask · MCP · Other, `ring.ts` 의 `toolGroup`: `apply_patch`·`MultiEdit`·`NotebookEdit` 는 Edit, `run_terminal_command`·`shell`·`exec_command`·`local_shell` 은 Bash, `mcp__*` 는 MCP, 모르는 이름(객체가 원래 가진 속성 이름 포함)은 Other)의 노드로 링 안쪽에 고정된 자리에 그리고, 노드 크기는 3시간 호출 수에 따라 커진다. 최근 30분의 호출만 노드와 선으로 잇고, 그 호출이 건드린 최근 파일 6개를 파일 노드(이름 label)로 잇는다. 파일 노드는 마지막으로 건드린 시각의 각도에 두고, 겹치면 16° 씩 물린다. 링 위의 turn 시작(runtime `turns`, task 의 모든 세션)은 사용자 요청이면 채운 점, subagent 보고(Claude Code `SubagentStop`)면 속이 빈 점이다. 실행 중인 큰 링의 가운데 아래 줄은 최근 30분 호출이 있으면 "48 calls · 30m", 없으면 "실행 중" 이다. 작은 링에는 호출 점·노드·파일·선이 없고, turn 시작 점은 있다. 시작한 지 3초가 안 된 호출은 "지금" 위치에서 그 호출의 점을 거쳐 도구 노드로 1.2초 동안 움직이는 점으로 한 번 보인다(SVG `animateMotion`, JS 타이머·`requestAnimationFrame` 없음, dashboard 가 1초마다 다시 그리므로 snapshot 이 늦어도 3초 안이면 보인다). `prefers-reduced-motion` 이면 보이지 않는다.
- todo 진행: task 의 세션 중 runtime `todos` 가 있고 가장 최근에 갱신된 세션의 목록을 링 바로 바깥에 todo 수만큼의 조각으로 그린다. 끝난 todo 는 밝은 조각, 실행 중인 task 의 다음 todo(끝난 수 다음 조각)는 천천히 밝아졌다 어두워지는 초록 조각, 나머지는 흐린 가는 조각이다. todo 가 있는 실행 중 링의 가운데는 경과 시간 대신 "3/7"(끝난 수/전체)이고, 큰 링은 그 아래에 "TODOS DONE" 과, "Show work details" 가 켜져 있으면 진행 중 todo 글(24자에서 자름)을 보인다. 대기 중인 큰 링은 대기 이유 아래에 "todos 2/5" 를 보인다. todo 가 없는 세션은 앞의 경과 시간 표시 그대로다.
- 턴 종료 요약: task 의 세션 중 runtime `lastTurn` 이 있고 가장 늦게 끝난(상태가 마지막으로 바뀐) 것을 쓴다. 턴이 끝난 큰 링의 가운데는 "✓ 턴 종료"(오류면 "✕ 오류로 끝남"), "12분 전 · todos 4/4"(todo 가 있을 때) 아래에 네 칸을 크게 보인다: 바뀐 파일 수, "+530 −133" 줄 수(추가는 초록, 삭제는 빨강), 테스트(통과 ✓ 초록 · 실패 ✗ 빨강 · 결과 모름 ? · 없음 –), commit 수. 작은 링과 요약이 없는 링(이전 수집기)은 제목과 경과만 보인다. 아래 "+n more" 줄의 턴 종료 task 는 경과 뒤에 "· 4 files · +530 −133 · tests ✓ · 1 commit" 을 붙인다.
- 세션 글은 기본으로 dashboard 에 나오지 않는다. "Show work details" 가 꺼져 있을 때 잠금 화면에 보이는 것은 agent 이름, branch·repo 이름, 상태·시간·대기 이유, tool 묶음과 호출 점, todo 의 완료 수/전체 수와 조각, 턴 종료 요약의 숫자(파일 수, 추가·삭제 줄 수, 테스트 결과, commit 수)다. 글(파일 이름, 지금 하는 일, 메시지, 진행 중 todo 글)은 보이지 않는다. Settings 의 "Show work details" 를 켜면 큰 링에 파일 이름(파일 노드), 캡션 아래 "▸ 지금 하는 일"(lead session 의 `activity`, 도구와 대상·명령), 최신 메시지 한 줄(task 의 모든 세션의 요청 `Human`·응답 `AI`, 모든 repo 의 이 task 커밋 `Commit` 중 가장 최근 것과 "12분 전" 같은 경과)을 보인다. 작은 링에는 켜도 보이지 않는다. 꺼져 있으면 이 글들은 화면 모델(`buildDashboardModel`)에 아예 실리지 않는다.
- 메시지 글은 줄바꿈을 접고 300자로 자르며, 자격 증명처럼 보이는 글은 통째로 "[sensitive content omitted]" 로 바꾼다. 요청·응답은 수집 단계에서, CLI 가 그대로 내는 커밋 제목은 companion 이 같은 규칙(`scrubMessage`)으로 정리한다. 수집기가 메시지를 남기기 전의 세션이나, 턴 도중에 수집기가 바뀌어 요청이 빠진 세션은 저장된 마지막 요청·응답으로 채운다(같은 글이면 한 번만). 시각이 같은 초이면 나중에 기록된 것(요청 뒤의 응답, CLI 의 더 새 커밋)이 위에 온다. "지금 하는 일" 도 같은 규칙(`scrubMessage`)을 거친다. 켜 두면 자리를 비운 동안 화면 앞의 누구나 읽을 수 있으므로 기본은 꺼짐이다.
- 테마와 글꼴은 companion preference 를 따른다.
- 데이터는 main 창과 같은 원천이다: runtime 은 `useRuntimeSessions` 구독, 목록은 workspace monitor 이벤트.

## 미리 보기
- Settings › Screen Saver › Show now(`screensaver_preview`)는 기능 켜짐·작업 중·화면보호기와 상관없이 모든 모니터에 미리 보기 창을 바로 띄운다. 실제 dashboard 가 떠 있으면 무시한다.
- 처음 2초(8 표본)의 입력은 무시하고, 그 뒤 입력이 오면 잠그지 않고 닫는다. 화면이 잠겨도 닫는다.
- 미리 보기 자체는 잠자기 방지와 디스플레이 유지를 걸지 않는다.

## 구조
- `src-tauri/src/screensaver/machine.rs`: 순수 상태 기계. `Machine::step(Event) -> Vec<Action>` 이 설정·작업 중·읽기 실패·화면보호기 알림·세션 표본(시각, idle, 잠김, 화면보호기)·미리 보기를 받아 전원 유지·창·잠금 동작을 낸다. 전이는 `machine_tests.rs` 가 OS 없이 검사한다.
- `screensaver/platform.rs`: OS 동작을 감싼 `Platform` trait. `screensaver/macos.rs`: objc2 typed binding(`objc2-foundation`·`objc2-app-kit`·`objc2-core-graphics`·`objc2-core-foundation`)과 잠금·SkyLight `dlopen` 구현. unsafe 블록마다 SAFETY 주석을 둔다. `screensaver/windows.rs`: 모니터별 창 배치.
- `src-tauri/src/screensaver.rs`: 한 스레드에서 runtime snapshot·설정 변경·잠김 알림·화면보호기 알림·모니터 변경·미리 보기 요청을 받아 상태 기계에 넣고, 상태 기계가 원하는 주기로 세션을 읽는다. command 는 `screensaver_refresh`, `screensaver_status`, `screensaver_preview`.
- 비공개 API(`SACLockScreenImmediate`, `SACScreenSaverIsRunning`, SkyLight space, webview `drawsBackground`)를 쓰므로 Mac App Store 로는 배포할 수 없다. companion 은 Homebrew cask 로 배포한다. 이후 macOS 에서 사라지거나 바뀔 수 있다.
