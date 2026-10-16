---
id: COMP001
slug: screensaver-feature
created: 2026-10-16T03:56:10.000Z
updated: 2026-10-17T04:40:00.000Z
---
# COMP001 · screensaver-feature

## Background

agent 동작 시에는 sleep 에 들어가지 않도록 또 다른 utility 를 활용 중 
* utility 이용할 경우 screen saver 가 동작하지 않으므로 화면에 항상 open되어 있음.

그러니깐 문제는 다음 두 가지임.

* 작업 진행 중에 sleep 들어가는 문제 
* 이를 방지 하기 위해서 sleep 방지 utilty 를 사용하는데, 그러면 화면이 항상 Open 되어 있는 문제 

## Goal

workbranch companion 에서 screen saver 역할을 하는 다음 기능을 제공한다.

screen save 를 대체해도 좋고, 어렵다면 다음 기능만 만족하면 됨.

* screen saver 처럼 maximized 화면 표시가 되고, 상단에는 7-segment 로 현재 시각을 표현. 
* workbranch 에서 진행중인 작업이 있는 경우에는 sleep 들어가지 않도록 처리 
* screen saver 처럼 특정 시간 이후에 키보드/마우스 action 이 없다면 dashboard 화면이 전체 화면에 뜨고 
  * 상단 시간 표시 
  * 하단에 진행 중에 branch 의 작업을 box 형태로 간단하게 표시 
  * screen lock 처럼 password 요구해서 아무나 화면 접근 못 하도록 할 것.

즉, macOS 화면보호기(잠그지만 잠자기를 막지 못하고 아무것도 보여 주지 않음)와 잠자기 방지 utility(잠자기는 막지만 화면이 열린 채 남음)가 따로 하던 일을 하나로 합친다: 자리를 비운 동안 agent 는 계속 일하고, 멀리서 작업 상태가 보이고, 아무도 내 컴퓨터를 쓰지 못한다.

## Non-goals
- 노트북 덮개를 닫았을 때의 잠자기 방지. 덮개를 닫으면 macOS 규칙대로 잠든다.
- companion 전용 암호·PIN.
- companion 이 macOS 의 화면보호기·잠금·잠자기 설정 값을 바꾸는 것.
- dashboard 에서 작업을 조작하는 것(승인, 프롬프트 입력, 버튼). dashboard 는 보기 전용이다.
- 작업 중이 아닐 때 시계만 띄우는 화면보호기.
- 기존 잠자기 방지 utility 를 감지하거나 끄는 것.
- 배터리·전원 상태에 따라 다르게 동작하는 것.
- 화면이 잠긴 동안 디스플레이를 켜 두는 것. 잠긴 동안(R6 으로 잠긴 경우 포함) 디스플레이 꺼짐과 잠금 화면은 macOS 기본 동작 그대로다. 시스템 잠자기만 R2 대로 막는다.
- 관측 불명(15분 넘게 hook 이벤트가 없는) 세션을 작업 중으로 세는 것. companion 칸반과 같은 기준으로 작업 중에서 빠진다.

## Success criteria
- 작업을 걸어 두고 자리를 비우면, 화면을 잠갔든(직접 또는 R6) 잠그지 않았든 작업 중인 동안 Mac 이 잠들지 않는다.
- 자리를 비운 동안 멀리서 시계, 상태별 개수, 나를 기다리는 작업이 보인다.
- 누가 키보드나 마우스를 건드리면 바로 macOS 잠금 화면이 되고, macOS 계정 인증 없이는 데스크톱이 보이지 않는다.
- 작업 중이 끝나면 화면과 잠자기가 macOS 기본 동작으로 돌아간다.
- 기능을 끄면 지금 companion 과 달라지는 것이 없고, 켜도 새 권한 요청이 뜨지 않는다.

## Constraints
- 새 권한 요청이 없다. 손쉬운 사용·입력 모니터링·화면 기록 권한 없이 동작한다.
- companion 이 지원하는 macOS 13 이상에서 동작한다.
- 기능이 꺼져 있으면 지금 companion 의 동작이 하나도 바뀌지 않는다.
- companion 이 종료되거나 비정상 종료되면 잠자기 방지가 남아 있지 않는다.

## Requirements
"작업 중" = "실행 중" 또는 "내 응답 대기" 세션이 하나 이상 있는 상태(companion 칸반과 같은 판정).

- R1 (MUST) 설정 화면에 이 기능 전체(잠자기 방지 · dashboard · 잠금)를 켜고 끄는 스위치가 하나 있고, 기본값은 꺼짐이다. 꺼져 있으면 companion 은 잠자기·화면보호기·잠금에 관여하지 않는다. — acceptance: 새로 설치하거나 업데이트한 직후 스위치가 꺼져 있고, 꺼진 상태에서는 작업 중에 오래 비워 둬도 잠자기 방지와 dashboard 가 없다.
- R2 (MUST) 작업 중인 동안 Mac 은 idle 잠자기에 들어가지 않는다. 화면이 잠겨 있어도(직접 잠갔든 R6 으로 잠겼든) 마찬가지이고, 잠긴 동안에는 디스플레이만 macOS 기본 동작대로 꺼진다. 작업 중이 끝나면(턴 종료만 남거나 세션이 없으면) 잠자기 방지를 풀고 macOS 기본 동작을 따른다. — acceptance: 작업 중이면 잠김과 상관없이 `pmset -g assertions` 에 companion 의 시스템 잠자기 방지(`PreventUserIdleSystemSleep`)가 보이고, 마지막 작업 중 세션이 턴 종료가 되면 사라진다. 잠긴 동안에는 companion 의 디스플레이 잠자기 방지(`PreventUserIdleDisplaySleep`)가 없다.
- R3 (MUST) 작업 중에 companion 설정의 시간(기본 5분, 1~60분) 동안 키보드·마우스 입력이 없으면 dashboard 가 macOS 화면보호기 대신 뜬다. 작업 중에는 이 시간이 macOS 화면보호기 시간보다 길어도 macOS 화면보호기가 먼저 뜨지 않는다. — acceptance: companion 을 2분, macOS 화면보호기를 1분으로 두고 작업 중에 비우면 2분에 dashboard 가 뜨고, 그 전에 macOS 화면보호기가 뜨지 않는다.
- R4 (MUST) 작업 중이 유지되는 동안 디스플레이는 켜진 채 dashboard 가 계속 보이고, macOS 화면보호기가 그 위를 덮지 않는다. — acceptance: macOS 디스플레이 꺼짐 시간보다 오래 비워도 작업 중이면 dashboard 가 보인다.
- R5 (MUST) 작업 중이 아니면 dashboard 를 띄우지 않고, 떠 있던 dashboard 는 작업 중이 끝나는 즉시 내린다. 이후 화면보호기·잠금·잠자기는 macOS 기본 동작에 맡긴다. — acceptance: 마지막 작업 중 세션이 턴 종료가 되면 dashboard 가 사라지고, 이후 macOS 설정대로 화면보호기·잠금·잠자기가 진행된다. 턴 종료만 있을 때는 설정 시간이 지나도 dashboard 가 뜨지 않는다.
- R6 (MUST) dashboard 는 보기 전용이다. dashboard 가 떠 있는 동안 키보드·마우스 입력이 들어오면 즉시 macOS 잠금 화면으로 넘어가고, macOS 계정 암호 또는 Touch ID 로만 해제된다. companion 은 별도 암호를 두지 않는다. — acceptance: dashboard 상태에서 마우스를 움직이면 바로 macOS 잠금 화면이 되고, 암호나 Touch ID 입력 전에는 데스크톱이 보이지 않는다.
- R7 (MUST) macOS 가 즉시 잠금을 제공하지 않는 환경에서도 dashboard 는 똑같이 뜨되 "입력 시 잠금" 표시를 숨기고, 입력이 들어오면 잠금 없이 dashboard 만 닫힌다. — acceptance: 즉시 잠금을 쓸 수 없게 만든 환경에서 dashboard 에 "입력 시 잠금" 표시가 없고, 입력하면 dashboard 만 닫힌다.
- R8 (MUST) dashboard 는 화면 전체를 채운다. 상단 왼쪽에는 digital(7-segment) 시계로 현재 시각과 날짜, "입력 시 잠금" 표시를, 상단 오른쪽에는 상태별(내 응답 대기 · 실행 중 · 턴 종료) task 개수를 크게 보여 준다. 하단에는 companion 칸반과 같은 3열(내 응답 대기 · 실행 중 · 턴 종료·검토)을 같은 상태 색으로 보여 준다. — acceptance: 화면 구성이 확정 시안 D 와 같고, 시계는 현재 시각(분 단위), 상태별 개수는 companion 칸반의 열별 개수와 일치한다.
- R9 (MUST) 하단 카드에는 세 상태 중 하나인 세션이 있는 task 만 나오고, 각 카드에 task 이름, 경과 시간, 프롬프트 한 줄, agent, repo · branch, repo 변경 상태(변경 파일 수 · ahead · behind), 알림 수를 보여 준다. 열별로 내 응답 대기 카드에는 대기 이유(권한 승인, 질문 등)와 기다리는 대상(승인할 명령이나 질문), 실행 중 카드에는 지금 하는 도구 동작, 턴 종료 카드에는 마지막 응답 발췌와 오류·중단 여부를 함께 보여 준다. 글은 runtime 이 저장한 그대로(민감 정보 제외·길이 제한) 쓰고, 액션 버튼은 보여 주지 않는다. — acceptance: dashboard 의 카드 목록이 companion 칸반 3열의 카드 목록과 같고, 각 카드의 프롬프트·도구 동작·마지막 응답이 메뉴바 카드와 같으며, 비활성·관측 불명·세션 없는 task 는 나오지 않는다.
- R10 (MUST) 모니터가 여러 대면 모든 모니터에 같은 dashboard 를 띄워, 어느 모니터에도 원래 화면 내용이 보이지 않는다. — acceptance: 모니터 2대를 연결하고 dashboard 가 뜨면 두 모니터 모두 dashboard 가 보이고 원래 창은 보이지 않는다.
- R11 (SHOULD) 카드의 task 이름·경과 시간·대기 이유는 2~3m 거리에서 읽을 수 있는 크기이고, 프롬프트·도구 동작·응답 줄은 줄 수를 정해 잘라 카드 높이에 상한이 있다. 열에 다 들어가지 않으면 스크롤 대신 "+n more" 로 줄여 보여 준다. — acceptance: 한 열의 task 가 표시 가능한 카드 수보다 많으면 "+n more" 가 보이고 스크롤이 생기지 않으며, 긴 프롬프트·응답이 있어도 카드가 잘리거나 겹치지 않는다.
- R12 (SHOULD) 설정 화면의 "미리 보기" 버튼을 누르면 기능 켜짐·작업 중·idle 시간과 상관없이 모든 모니터에 dashboard 가 바로 뜬다. 처음 2초의 입력은 무시하고, 그 뒤 입력이 오면 잠그지 않고 닫힌다. 미리 보기 중에는 "입력 시 잠금" 대신 "미리 보기 · 입력하면 닫힘" 을 표시하고, 잠자기 방지는 걸지 않는다. — acceptance: 기능을 끈 상태에서 미리 보기를 누르면 모든 모니터에 dashboard 가 뜨고, 2초 뒤 마우스를 움직이면 잠금 화면 없이 닫히며, 그동안 `pmset -g assertions` 에 companion 의 잠자기 방지가 없다.

## Open questions
_None._

## Planning hints
- dashboard 시안: https://claude.ai/artifact/Y6URuqw6aafthatNwaqf3y 의 "D · B 상단 + A 하단" 으로 확정하고, 카드는 "E · D + 상세 카드" 로 넓힘. 1440×900 기준 열당 카드 3장, companion claude 테마의 runtime 색(`--runtime-waiting` / `--runtime-running` / `--runtime-finished`)과 고정폭 글꼴 사용.
- 작업 중 판정: 기존 `runtimeRole()` (`apps/companion/src/application/state.ts`) 과 같은 기준. 실행 중·대기 세션은 900초 동안 갱신이 없으면 `observation: "stale"` 로 바뀐다(`apps/agent-runtime/src/store.rs`). "턴 종료" 는 다음 프롬프트나 세션 종료까지 남는다(`apps/agent-runtime/src/event.rs`).
- 설정: 스위치와 idle 시간은 기존 `companion-preferences.json` (`apps/companion/src/application/preferences.ts`, `ui/SettingsPanel.tsx`) 에 추가.
- 창: 지금 companion 은 Tauri 창 `main` 하나(`visible: false`, `alwaysOnTop`, `skipTaskbar`) + tray 다. 모니터마다 전체 화면 dashboard 창이 필요하다.
- 즉시 잠금: 비공개 `login.framework` 의 `SACLockScreenImmediate`. 권한 요청 없음. macOS 27.2 에서 심볼 존재 확인(호출은 하지 않음). 비공개 API 라 Mac App Store 배포는 불가(companion 은 brew 배포라 무관)하고, 이후 macOS 에서 사라질 수 있다(R7).
- 입력·idle 감지: `CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState, kCGAnyInputEventType)`. 손쉬운 사용·입력 모니터링 권한 불필요(실측 확인).
- 잠자기 방지: `PreventUserIdleSystemSleep` power assertion. 시스템 잠자기만 막고 디스플레이 꺼짐·화면보호기·잠금은 허용한다. 작업 중이면 잠김과 상관없이 건다. dashboard 를 띄울 수 있는 동안(작업 중이고 잠기지 않음) 디스플레이를 켜 두는 것(R3·R4)은 별도 디스플레이 assertion(`PreventUserIdleDisplaySleep`)이다. 모두 권한 불필요이고, 프로세스가 죽으면 OS 가 회수한다.
- 쓰지 않을 것: Ctrl+Cmd+Q 키 입력 흉내(손쉬운 사용 권한 필요). `pmset displaysleepnow` / 화면보호기 실행은 macOS 의 "암호 요구까지 지연" 설정을 따르므로 즉시 잠기지 않는다(이 Mac 은 300초, `sysadminctl -screenLock status`).
- 이 Mac 의 현재 설정(참고): 화면보호기 300초, 디스플레이 꺼짐 10분.

## Decision Log
- 2026-10-16 · Q1 범위: 하나로 갈지 둘로 나눌지 → 하나로 유지 (잠자기 방지 + idle dashboard + 잠금을 함께 정의하고 함께 출시) · 세 기능을 한 단위로 정의·리뷰하기로 선택
- 2026-10-16 · Q2 잠금 해제 수단 → A. macOS 계정 인증(입력 시 시스템 잠금으로 전환, 별도 암호 없음) · 권한 요청 없이 가능함을 확인한 뒤 선택
- 2026-10-16 · Q3 잠금을 걸 수 없을 때 → dashboard 는 그대로 띄우고 잠금만 생략 · 잠금보다 시계·작업 현황 표시를 우선
- 2026-10-16 · Q4 dashboard 레이아웃과 세션이 없을 때 → A. 시계 + 칸반 3열 전체 화면 레이아웃, 세션 있는 task 만 간단한 카드로 표시, 세션 없으면 dashboard 없이 macOS 기본 동작 · companion 은 작업 중일 때만 개입
- 2026-10-16 · Q5 잠자기 방지 조건 → A. 실행 중 세션이 있을 때만 · 대기·턴 종료 중에는 잠들어도 잃는 것이 없고, 턴 종료는 오래 남아 utility 와 같아지는 것을 피함
- 2026-10-16 · Q6 dashboard 유지 조건 → A. 실행 중 또는 내 응답 대기 세션이 있는 동안 화면을 켠 채 유지, 턴 종료만 남으면 macOS 기본 동작 · 목적은 잠자기 방지 + 멀리서 진행 상황 보기 + 남이 못 쓰게 잠금이며, 화면이 켜져 있으면 나를 기다리거나 진행 중이라는 신호가 됨
- 2026-10-16 · Q5 수정 → 잠자기 방지 조건을 "실행 중"에서 "실행 중 또는 내 응답 대기"로 넓힘 · 대기 중에 잠들면 dashboard 가 사라져 Q6 의 목적과 어긋남
- 2026-10-16 · Q7 dashboard 를 띄우는 idle 시간 → B. companion 설정(기본 5분, 1~60분) · macOS 설정과 별도로 정하기로 선택. 작업 중 macOS 화면보호기가 먼저 뜨지 않는 것은 Q6(화면보호기 대신)에서 따라옴
- 2026-10-16 · Q8 모니터가 여러 대일 때 → B. 모든 모니터에 같은 dashboard · 어느 모니터에서든 시계·작업 상태가 보이고 원래 화면 내용은 가려짐
- 2026-10-16 · Q9 켜고 끄는 설정과 기본값 → A. 스위치 하나, 기본 꺼짐 · 화면을 덮고 잠그는 동작은 사용자가 직접 켜야 예상할 수 있고, Q1 의 한 단위 결정과 일관됨
- 2026-10-16 · Q10 dashboard 시안 → D (B 의 상단: 작은 시계 + 상태별 개수, A 의 하단: 칸반 3열) · 칸반과 같은 생김새를 유지하면서 멀리서 상태별 개수가 바로 보임
- 2026-10-16 · Q11 Non-goals·Constraints → 제안한 7개 Non-goals 와 4개 Constraints 를 그대로 채택 · 지금까지의 결정과 확인된 사실에서 나온 경계
- 2026-10-16 · Q12 요구사항·Success criteria → R1~R11(MUST 10, SHOULD 1)과 Success criteria 5개로 확정, 관측 불명 세션은 작업 중에서 제외 · 각 R 이 Q1~Q11 의 답을 옮긴 것이고 관찰 가능한 acceptance 를 하나씩 가짐
- 2026-10-16 · (plan Q4) 화면이 잠긴 동안 → companion 은 아무것도 하지 않고 macOS 기본 동작 그대로(잠자기 방지도 해제). R2 를 "잠기지 않은 동안"으로 좁힘 · 원칙: 잠자기 방지는 agent 가 동작하고 dashboard 가 동작할 수 있을 때만, 나머지는 OS 그대로
- 2026-10-16 · (구현 중 추가) Settings 확인 버튼 → A. 미리 보기: 즉시 표시, 2초 입력 무시 후 입력 시 잠금 없이 닫힘, 기능 꺼짐에서도 동작, 잠자기 방지 없음. R12(SHOULD) 로 추가 · 작업을 걸고 N분 기다리지 않고 화면·데이터를 바로 확인. 잠금 동작은 실제 흐름으로 확인
- 2026-10-16 · (구현 중 변경) dashboard 카드 정보 → 시안 E: 프롬프트 한 줄, 열별 세부(대기: 기다리는 대상, 실행 중: 도구 동작, 턴 종료: 마지막 응답·오류·중단), repo 변경 상태, 알림 수. R9 의 "프롬프트 제외" 를 뒤집고 R11 을 카드 제목 크기 + 세부 줄 수 제한으로 바꾸며, 열당 카드는 4장에서 3장으로 · 화면 전체를 쓰면서 메뉴바 카드보다 정보가 적었음. 민감 정보는 runtime 이 저장 단계에서 빼고, dashboard 가 없으면 그 자리에 터미널이 그대로 보였을 것이라 노출을 이유로 뺄 근거가 약함. 별도 표시 설정은 두지 않음(Q9 스위치 하나)
- 2026-10-17 · (구현 중 변경) 화면이 잠긴 동안의 잠자기 방지 → 작업 중이면 잠겨 있어도 시스템 잠자기는 계속 막고, 디스플레이만 macOS 기본 동작대로 꺼지게 둔다. R2·Non-goals·Success criteria 수정 · 잠금 화면은 agent 를 멈추지 않지만 잠자기는 멈춘다. 잠기면 잠자기 방지를 풀던 기존 결정(plan Q4)으로는 R6 으로 잠긴 뒤나 직접 잠그고 자리를 뜬 뒤 Mac 이 잠들어 agent 가 멈춤 · 사용자 선택
