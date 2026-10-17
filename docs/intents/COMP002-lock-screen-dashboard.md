---
id: COMP002
slug: lock-screen-dashboard
created: 2026-10-18T04:20:00.000Z
updated: 2026-10-18T04:20:00.000Z
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
- 작업 중이 끝나면 dashboard 가 내려가고 잠금 화면·디스플레이·잠자기가 macOS 기본 동작으로 돌아간다.

## Requirements
- R1 (MUST) 켜짐 && 작업 중 && (화면 잠김 || macOS 화면보호기 실행 중) 이면 모든 모니터에서 잠금 화면과 화면보호기 **위에** dashboard 가 보인다. — acceptance: 작업 중에 Ctrl+Cmd+Q 로 잠그고 15초 기다리면 모든 모니터에 dashboard 가 보인다.
- R2 (MUST) 화면을 쓰는 동안에는 디스플레이를 붙잡지 않아 macOS 화면보호기와 잠금이 macOS 설정대로 시작되고, 화면보호기나 잠금 화면이 뜬 뒤 작업 중인 동안에는 디스플레이를 붙잡는다. 시스템 잠자기 방지는 COMP001 R2 그대로다. — acceptance: 잠기지 않은 상태에서 `pmset -g assertions` 에 companion 의 `PreventUserIdleDisplaySleep` 이 없고, 잠긴 뒤에는 있다.
- R3 (MUST) dashboard 가 보일 때 Mac 은 잠겨 있다. 화면보호기만 시작되었고 아직 잠기지 않았으면(macOS 의 "암호 요구까지 지연") 띄우면서 바로 잠근다. — acceptance: "암호 요구" 지연을 5분으로 둔 Mac 에서 화면보호기 위에 dashboard 가 뜬 직후 입력하면 잠금 화면이 나온다.
- R4 (MUST) dashboard 위에서 입력하면 dashboard 만 내려가 잠금 화면이 보인다. 잠금을 풀지 않고 15초 동안 입력이 없으면 다시 뜬다. 잠금이 풀리면 내려가고 디스플레이 유지도 푼다. — acceptance: dashboard 상태에서 마우스를 움직이면 잠금 화면이 보이고, 그대로 두면 15초 뒤 dashboard 가 돌아온다.
- R5 (MUST) 잠금 불가 환경에서는 dashboard 가 같은 조건에 뜨되 "화면 잠김" 표시를 숨기고 직접 잠그지 않는다(COMP001 R7 의 갱신). — acceptance: `WORKBRANCH_SCREENSAVER_NO_LOCK=1` 로 실행하면 "화면 잠김" 표시가 없다.
- R6 (MUST) Settings › Screen Saver 에는 스위치와 Show now 만 있고, "Dashboard after" 는 없다. 이전 store 의 `idleMinutes` 는 무시하고 지운다. — acceptance: Settings 에 분 선택이 없고, 시작 후 store 의 `screensaver` 가 `{ "enabled": … }` 만 갖는다.

COMP001 의 R1(스위치), R2(시스템 잠자기 방지), R5(작업 중이 끝나면 내림), R8~R12(화면 구성·카드·모니터·미리 보기)는 그대로다. R3·R4·R6·R7 은 이 intent 의 R1~R5 로 바뀐다.

## Decision Log
- 2026-10-18 · 트리거 → macOS 화면보호기 시작(`com.apple.screensaver.didstart`)과 화면 잠김 · 사용자 요구 "OS screen saver 동작 시에 dashboard 그 위에 뜸". companion 의 idle 시간 설정(Dashboard after)은 없앤다
- 2026-10-18 · 잠금 화면 위 표시 방법 → SkyLight 비공개 space(절대 level 400) · loginwindow 로그에서 잠금 화면이 `LUIUnmanagedSpace: level=300` 에 그려짐을 확인. 잠금 화면 위 UI 를 띄우는 공개 앱(SkyLightWindow, PC Bio Unlock)과 같은 방법. macOS 27.2 에서 심볼 존재 확인
- 2026-10-18 · 화면보호기만 떠 있고 잠기지 않았을 때 → dashboard 를 띄우면서 바로 잠근다 · 요구가 "screen lock 된 상태이나 화면은 dashboard 가 보이고" 이고, 화면보호기를 덮어 잠김 여부가 보이지 않으므로 dashboard 가 보이면 잠겨 있어야 한다. 이 Mac 은 "암호 요구까지 지연" 300초
- 2026-10-18 · 잠김 판단 → 알림 대신 세션의 `CGSSessionScreenIsLocked` 를 읽는다 · 2026-10-18 00:01~00:42 `pmset -g log` 에 loginwindow 잠금 기록 없이 companion 의 디스플레이 assertion 만 20~50초 간격으로 풀렸다 잡혔다. 원인은 확정하지 못했지만, 잘못 온 잠김 알림이 데스크톱 위에 dashboard 를 띄우고 잠그는 일을 막는다
- 2026-10-18 · 다시 띄우는 시간 → 15초 · 잠금 화면에서 암호를 입력하는 동안은 뜨지 않고, 그냥 두고 가면 곧 돌아온다

## Outcome
- 2026-10-18 · **Pending human verification** · 비공개 API 동작(잠금 화면 위 SkyLight space, 잠금 화면에서의 디스플레이 유지, 잠긴 동안의 webview 갱신)은 실제 잠금으로만 확인할 수 있다.
