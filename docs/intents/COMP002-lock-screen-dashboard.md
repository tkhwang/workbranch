---
id: COMP002
slug: lock-screen-dashboard
created: 2026-10-18T04:20:00.000Z
updated: 2026-10-20T21:40:00.000Z
---
# COMP002 · lock-screen-dashboard

## Background

COMP001 로 dashboard 와 잠자기 방지를 넣었지만 dashboard 가 뜬 뒤 유지가 안 된다.

COMP001 의 흐름은 "화면을 쓰는 동안 디스플레이를 붙잡아 macOS 화면보호기를 막고 → companion 의 idle 시간 뒤 dashboard 를 띄우고 → 입력이 오면 잠그면서 dashboard 를 내리고 → 잠긴 뒤에는 디스플레이를 macOS 에 맡긴다" 였다. 그래서

* 누가(또는 내가) 한 번 건드리면 dashboard 는 사라지고 잠금 화면만 남으며, 디스플레이도 곧 꺼진다.
* 직접 잠그고(Ctrl+Cmd+Q) 자리를 뜨면 dashboard 는 아예 뜨지 않는다.
* 화면을 쓰는 동안 디스플레이를 붙잡으므로 macOS 화면보호기와 그 잠금이 companion 없이는 동작하지 않는다. caffeinate 로 잠자기를 막을 때 잠금 화면이 안 되던 문제와 같은 모양이다.

원하는 동작:

* OS screen saver 동작 시에 dashboard 가 그 위에 뜬다.
  - OS screen saver: lock screen
  - workbranch dashboard: 화면 표시, sleep 들지 않게 함
* screen lock 된 상태이나 화면에는 dashboard 가 보이고, dashboard 로 인해서 sleep 에 빠지지 않고, 화면에서 진행 사항을 볼 수 있다.

## Goal

잠금은 macOS 화면보호기·잠금 화면이 맡고, companion 은 그 위에 dashboard 를 띄워 디스플레이와 시스템을 깨워 둔다. 자리를 비운 동안 Mac 은 잠겨 있고, 잠들지 않고, 멀리서 진행 상황이 보인다.

## Non-goals
- companion 전용 idle 시간 설정. dashboard 를 띄우는 시점은 macOS 화면보호기 시간이 정한다.
- 화면을 쓰는 동안(잠기지 않고 화면보호기도 없을 때) 디스플레이를 붙잡는 것.
- 이미 꺼진 디스플레이를 companion 이 켜는 것.
- dashboard 에서 작업을 조작하는 것. 보기 전용이다(COMP001 과 같음).
- companion 이 macOS 의 화면보호기·잠금·잠자기 설정 값을 바꾸는 것(COMP001 과 같음).

## Success criteria
- 작업 중에 자리를 비우면 macOS 화면보호기 시간에 Mac 이 잠기고, 잠금 화면 위에 dashboard 가 뜬다.
- dashboard 가 뜬 채로 macOS 디스플레이 끄기 시간보다 오래 두어도 디스플레이와 dashboard 가 켜져 있고, Mac 이 잠들지 않는다.
- 입력하면 dashboard 가 비켜 macOS 잠금 화면이 보이고, 암호나 Touch ID 로만 데스크톱으로 돌아온다. 풀지 않고 두면 dashboard 가 다시 뜬다.
- 작업이 없을 때 자리를 비우거나 자리를 비운 동안 작업이 끝나도, 30분 동안은 dashboard 와 디스플레이가 켜져 있고 Mac 이 잠들지 않는다. 그 뒤에는 dashboard 가 내려가고 잠금 화면·디스플레이·잠자기가 macOS 기본 동작으로 돌아간다.

## Requirements
- R1 (MUST) 켜짐 && (화면 잠김 || macOS 화면보호기 실행 중) && (작업 중 || R8 의 무작업 덮임 시간 안) 이면 모든 모니터에서 잠금 화면과 화면보호기 **위에** dashboard 가 보인다. — acceptance: 작업 중에 Ctrl+Cmd+Q 로 잠그고 15초 기다리면 모든 모니터에 dashboard 가 보인다.
- R2 (MUST) 화면을 쓰는 동안에는 디스플레이를 붙잡지 않아 macOS 화면보호기와 잠금이 macOS 설정대로 시작되고, 화면보호기나 잠금 화면이 뜬 뒤 작업 중이거나 R8 의 무작업 덮임 시간 안인 동안에는 디스플레이와 시스템을 붙잡는다. 화면을 쓰는 동안의 시스템 잠자기 방지는 COMP001 R2 그대로다. — acceptance: 잠기지 않은 상태에서 `pmset -g assertions` 에 companion 의 `PreventUserIdleDisplaySleep` 이 없고, 잠긴 뒤에는 있다.
- R3 (MUST) 잠금이 가능한 Mac 에서 dashboard 는 세션이 잠김으로 읽힐 때만 보인다. 화면보호기만 시작되었고 아직 잠기지 않았으면(macOS 의 "암호 요구까지 지연") 먼저 잠그고 잠김이 확인되면 띄운다. 잠금 요청이 끝내 안 되면(2초 간격 3번) dashboard 없이 macOS 가 스스로 잠글 때까지 기다린다. — acceptance: "암호 요구" 지연을 5분으로 둔 Mac 에서 화면보호기 위에 dashboard 가 뜬 직후 입력하면 잠금 화면이 나온다. 잠금이 안 되게 만든 환경에서는 "화면 잠김" 표시를 단 dashboard 가 잠기지 않은 화면 위에 뜨지 않는다.
- R4 (MUST) dashboard 위에서 입력하면 dashboard 만 내려가 잠금 화면이 보인다. 잠금을 풀지 않고 15초 동안 입력이 없으면 다시 뜬다. 잠금이 풀리면 내려가고 디스플레이 유지도 푼다. — acceptance: dashboard 상태에서 마우스를 움직이면 잠금 화면이 보이고, 그대로 두면 15초 뒤 dashboard 가 돌아온다.
- R5 (MUST) 잠금 불가 환경에서는 dashboard 가 같은 조건에 뜨되 "화면 잠김" 표시를 숨기고 직접 잠그지 않는다(COMP001 R7 의 갱신). — acceptance: `WORKBRANCH_SCREENSAVER_NO_LOCK=1` 로 실행하면 "화면 잠김" 표시가 없다.
- R6 (MUST) Settings › Screen Saver 에는 스위치와 Show now 만 있고, "Dashboard after" 는 없다. 이전 store 의 `idleMinutes` 는 무시하고 지운다. — acceptance: Settings 에 분 선택이 없고, 시작 후 store 의 `screensaver` 가 `{ "enabled": … }` 만 갖는다.
- R7 (MUST) companion 이 화면보호기가 이미 도는 중에 시작되거나 화면보호기 알림을 놓쳐도, 다음 세션 읽기(작업 중이면 1초 안)에서 화면보호기를 알아본다. — acceptance: 화면보호기가 도는 중(암호 요구 지연 안)에 companion 을 다시 시작하면 잠기고 dashboard 가 뜬다.

- R8 (MUST) 자리 비움(화면 잠김 || 화면보호기) 중 작업 중이 아니어도 dashboard·디스플레이 유지·시스템 잠자기 방지를 최대 30분(`COVER_WITHOUT_WORK`) 유지한다. 30분은 "자리 비움이 시작된 시각"과 "자리 비움 중 작업 중이 끝난 시각" 중 늦은 쪽부터 잰다. 다하면 dashboard 를 내리고 둘 다 풀며, 같은 자리 비움 동안에는 기능을 껐다 켜도 다시 덮지 않는다. 작업 중이 다시 시작되면 바로 다시 덮고, 다시 끝나면 그때부터 새로 잰다. 잠금이 풀리면 초기화된다. 작업 중의 정의(COMP001, `stale` 900초 포함)는 바꾸지 않는다. — acceptance: 모든 세션이 턴 종료인 상태에서 화면보호기가 시작되면 잠금 화면 위에 dashboard 가 뜨고 `pmset -g assertions` 에 companion 의 두 assertion 이 있다. 30분 뒤 dashboard 가 내려가고 두 assertion 이 사라지며, 이후 macOS 설정대로 디스플레이가 꺼지고 잠든다.

COMP001 의 R1(스위치), R2(시스템 잠자기 방지), R8~R12(화면 구성·카드·모니터·미리 보기)는 그대로다. R3·R4·R6·R7 은 이 intent 의 R1~R5 로, R5(작업 중이 끝나면 내림)는 R8 로 바뀐다.

## Decision Log
- 2026-10-18 · 트리거 → macOS 화면보호기 시작(`com.apple.screensaver.didstart`)과 화면 잠김 · 사용자 요구 "OS screen saver 동작 시에 dashboard 그 위에 뜸". companion 의 idle 시간 설정(Dashboard after)은 없앤다
- 2026-10-18 · 잠금 화면 위 표시 방법 → SkyLight 비공개 space(절대 level 400) · loginwindow 로그에서 잠금 화면이 `LUIUnmanagedSpace: level=300` 에 그려짐을 확인. 잠금 화면 위 UI 를 띄우는 공개 앱(SkyLightWindow, PC Bio Unlock)과 같은 방법. macOS 27.2 에서 심볼 존재 확인
- 2026-10-18 · 화면보호기만 떠 있고 잠기지 않았을 때 → dashboard 를 띄우면서 바로 잠근다 · 요구가 "screen lock 된 상태이나 화면은 dashboard 가 보이고" 이고, 화면보호기를 덮어 잠김 여부가 보이지 않으므로 dashboard 가 보이면 잠겨 있어야 한다. 이 Mac 은 "암호 요구까지 지연" 300초
- 2026-10-18 · 잠김 판단 → 알림 대신 세션의 `CGSSessionScreenIsLocked` 를 읽는다 · 2026-10-18 00:01~00:42 `pmset -g log` 에 loginwindow 잠금 기록 없이 companion 의 디스플레이 assertion 만 20~50초 간격으로 풀렸다 잡혔다. 원인은 확정하지 못했지만, 잘못 온 잠김 알림이 데스크톱 위에 dashboard 를 띄우고 잠그는 일을 막는다
- 2026-10-18 · 다시 띄우는 시간 → 15초 · 잠금 화면에서 암호를 입력하는 동안은 뜨지 않고, 그냥 두고 가면 곧 돌아온다

- 2026-10-18 · (PR #245 리뷰) 잠금 확인 → dashboard 를 띄운 뒤 잠그던 것을 "잠그고, 잠김이 확인되면 띄운다" 로 바꾸고 COMP001 의 재시도(2초 간격 3번)를 되살림. 끝내 안 잠기면 dashboard 없이 macOS 의 지연 잠금을 기다림 · 한 번만 요청하고 결과를 버리면, 잠금이 실패했을 때 "화면 잠김" 을 단 dashboard 가 잠기지 않은 화면보호기를 덮고 입력하면 암호 없이 데스크톱이 드러남
- 2026-10-18 · (PR #245 리뷰) 화면보호기 상태 초기화 → 알림 대신 `SACScreenSaverIsRunning` 을 세션 읽기마다 묻는다 · 알림만으로는 companion 이 화면보호기 도중에 시작되거나, 시작 직후 observer 등록 전에 온 알림을 알 수 없음. 백그라운드 스레드에서 평균 0.19ms
- 2026-10-18 · (PR #245 리뷰 반영 중 발견) 잠금 해제 직후의 "실행 중" 판독 → 멈춤으로 읽히거나 새로 시작될 때까지 믿지 않음 · Touch ID 로 풀면 HID 입력이 없어 idle 이 크게 남아, 늦은 판독 하나가 방금 푼 Mac 을 다시 잠글 수 있음
- 2026-10-19 · (실사용 중 발견) 모니터 구성 알림 → 창을 다시 만들지 않고 모니터 목록과 비교해 바뀐 창만 열고·옮기고·닫는다 · dashboard 가 뜬 지 16초쯤 뒤 깜빡이다 사라지고 잠금 화면만 남았다. 2026-10-19 10:20·10:30 두 번 모두 내장 XDR 디스플레이의 EDR 밝기 램프와 같은 시각에 dashboard 창이 2초 동안 약 30번 다시 만들어졌고(WebKit 로그), 마지막 회차에 새 창을 못 만들어 창 0개로 끝났다. 상태 기계는 표시 중으로 남아(0.25초 읽기 지속) 잠금 해제 때까지 다시 띄우지 않았다. Tauri `destroy()` 는 비동기라 같은 라벨로 바로 만들면 실패할 수 있고, 그 실패를 무시하고 있었다
- 2026-10-19 · (PR #254 리뷰) 창 라벨과 추적 → 창마다 번호를 붙인 새 라벨을 쓰고, companion 이 열고 아직 닫지 않은 창만 추적한다. 옮기기는 위치·크기가 둘 다 성공했을 때만 기록한다 · 모니터가 빠졌다 곧 다시 붙으면 destroy 중인 창이 열린 창으로 잡혀 옮겨진 것으로 기록되고, 그 창이 사라진 뒤에는 같은 알림이 와도 아무것도 하지 않아 그 모니터가 비었다. 옮기기 실패를 성공으로 기록해도 같은 일이 생겼다
- 2026-10-21 · (실사용 중 발견, 토론 Q1) 작업 중이 아닐 때의 자리 비움 → D. 자리 비움 동안은 작업과 무관하게 덮고, 작업이 없으면 30분 상한(R8 추가, COMP001 R5 대체) · 사용자 보고 "화면보호기 시점에 검은 화면만 나옴". 10-18~10-21 화면보호기 시작 26건 중 dashboard 가 뜬 10건은 모두 작업 중, 안 뜬 16건은 모두 작업 중이 아니었고, 그때는 화면보호기 → 2~5분 뒤 디스플레이 꺼짐 → 20초 뒤 잠자기였다. 작업 중인 실제 잠금 테스트 2회는 두 모니터 모두 정상 표시. codex 는 A(유지), grok 은 D 를 권했고 사용자가 D 를 골랐다. 상한은 COMP001 Q5 의 "상시 깨움 utility 화" 를 막기 위함이고 30분은 초깃값이다. 후속 후보: hook 없이 15분 넘는 도구 호출·대기가 `stale` 로 작업 중에서 빠지는 경로, 창 열기 실패 시 재시도 없음

## Outcome
- 2026-10-18 · **Pending human verification** · 비공개 API 동작(잠금 화면 위 SkyLight space, 잠금 화면에서의 디스플레이 유지, 잠긴 동안의 webview 갱신)은 실제 잠금으로만 확인할 수 있다.
