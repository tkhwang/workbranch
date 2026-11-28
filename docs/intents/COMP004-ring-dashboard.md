---
id: COMP004
slug: ring-dashboard
module: COMP
created: 2026-11-28T05:58:12.000Z
updated: 2026-11-28T08:29:48.000Z
---
# COMP004 · 잠금 화면 dashboard 를 task 링으로 바꾸기

## Background
- 지금 잠금 화면 dashboard([COMP002](COMP002-lock-screen-dashboard.md), [screensaver spec](../specs/comp/screensaver.md))는 시계, 상태별 task 개수, 최근 3시간 timeline 만 보인다. task 가 언제 돌았고 언제 멈췄는지는 보이지만, agent 가 지금 무엇을 하는지, 얼마나 진행했는지, 끝난 turn 이 무엇을 남겼는지는 보이지 않는다. 자리를 비운 사람이 멀리서 보고 돌아갈지 판단하기에 정보가 부족해 크게 도움이 되지 않는다.
- agent-runtime 수집기는 tool 호출 hook 을 받지만 마지막 동작 한 줄만 남긴다. tool 호출 기록, todo 진행, turn 결과는 runtime 문서에 없다.
- 한 Claude Code 세션을 knowledge graph(turn 링 + 안쪽 tool·파일 + 바깥 topic·decision)로 그린 사례에서 출발했다. 화면 보호기 용도에 맞게 시안을 만들며 방향을 정했다(Planning hints 의 시안 경로). 원 사례의 semantic 층은 잠금 화면에서 읽히지 않고 노출 위험이 커서 뺐다.

## Goal
잠금 화면 dashboard 가 task 마다 최근 3시간을 시계판처럼 그린 링을 보여, 멀리서도 다음 세 가지를 한눈에 알 수 있게 한다.
1. 나를 기다리는 task 가 있는가.
2. 실행 중인 task 는 지금 무엇을 하고, 얼마나 진행했는가.
3. 턴이 끝난 task 는 무엇을 남겼는가.

## Non-goals
- topic·decision·question 같은 의미 층을 모델로 태깅해 그리는 것.
  - follow-up intent: 턴이 끝날 때 모델로 의미를 태깅해 링 바깥에 표시
- 막힘 감지(같은 명령의 연속 실패, 같은 파일 반복 수정 경고).
  - follow-up intent: agent 가 헛도는 상태를 감지해 링에 경고
- subagent 를 turn 에서 뻗은 가지 링으로 그리는 것.
  - follow-up intent: subagent 가지 링
- 번인 방지(레이아웃 이동)와 야간 감광.
  - follow-up intent: 장시간 표시용 번인 방지와 감광
- main 창 칸반과 Settings 의 다른 화면 변경. 노출 설정 스위치는 예외(R9).
- 세션 transcript 파일을 직접 읽는 것. 데이터는 지금처럼 hook 이벤트로만 모은다.
- 여러 세션을 잇는 전역 그래프와 그 질의.
- 화면 보호기를 덮고 내리는 규칙(덮임, 입력, 잠금, 디스플레이 유지) 변경.

## Success criteria
- 응답 대기 task 가 있으면 dashboard 첫 자리(왼쪽 위)에 놓이고, 3m 떨어진 거리에서 "Needs you" 와 경과 시간이 읽힌다.
- 실행 중인 task 가 tool 을 쓰면 2초 안에 그 호출이 링에 나타난다.
- todo 를 쓰는 세션은 링 가운데에 완료 수/전체 수가 보인다.
- 턴이 끝난 task 는 바뀐 파일 수, 추가·삭제 줄 수, 테스트 결과, commit 수를 보인다.
- 실행 중·대기 task 가 6개일 때도 모두 링으로 보이고, 화면 밖으로 넘치거나 스크롤이 생기지 않는다.
- 기본 설정의 잠금 화면에는 파일 이름, 명령, todo 문장이 보이지 않는다.

## Constraints
- runtime 문서는 schema 1 을 유지한다. 새 데이터는 선택 필드로만 더하고, 필드가 없는 이전 수집기의 문서도 처리한다.
- companion 은 지금처럼 `workbranch runtime --json` 문서만 읽는다. 수집기 내부 저장소는 직접 읽지 않는다.
- 수집기 쓰기는 hook 을 보낸 agent 를 늦추지 않는다. 기존 쓰기 대기 정책 안에서 끝난다.
- 잠금 화면 노출 원칙은 기존 "Show recent messages" 와 같다. 기본은 숨기고, 자격 증명처럼 보이는 글은 같은 규칙으로 가린다.
- dashboard 는 디스플레이를 켜 둔 채 몇 시간 떠 있다. 변화가 없으면 애니메이션 frame 을 그리지 않는다.
- dashboard 창은 지금처럼 입력을 받지 않고, 덮임·내림 규칙은 바뀌지 않는다.
- hook 을 보내는 provider(claude, codex, grok) 모두에서 동작한다. provider 가 주지 않는 데이터는 없는 것으로 그린다.

## Requirements
- R1 (MUST) 수집기는 세션마다 tool 호출의 시각, 도구 이름, 대상 파일 이름, 실패 여부를 기록하고, runtime 문서에 최근 3시간치를 낸다. 파일 이름은 경로가 아니라 basename 이다.
  - acceptance: tool 을 쓴 세션 뒤 `workbranch runtime --json` 의 그 세션에 호출마다 네 값이 나온다. 3시간이 지난 호출과 상한을 넘은 호출은 나오지 않는다.
- R2 (MUST) 수집기는 사용자 요청으로 시작한 turn 의 시각을 runtime 문서에 낸다.
  - acceptance: 요청을 두 번 보낸 세션의 문서에 turn 시작 시각이 두 개 있다.
- R3 (MUST) 수집기는 agent 가 todo 도구로 남긴 최신 todo 목록을 runtime 문서에 낸다. 항목 수, 완료 수, 진행 중 항목 문장이 들어간다.
  - acceptance: todo 7개 중 3개를 끝내고 1개를 진행 중인 세션의 문서에 7·3과 진행 중 항목 문장이 있다.
- R4 (MUST) 수집기는 턴이 끝나면 그 turn 의 결과 요약을 runtime 문서에 낸다. 바뀐 파일 수, 추가·삭제 줄 수, 마지막 테스트 명령의 성공·실패(없으면 없음), commit 수가 들어간다.
  - acceptance: 파일 2개를 고치고 테스트 명령 하나가 성공한 뒤 commit 한 turn 의 요약이 각각 2, 줄 수, 성공, 1이다.
- R5 (MUST) dashboard 는 task 마다 최근 3시간을 한 바퀴로 하는 링을 그린다.
  - 맨 위가 지금이고, 시간이 지나면 링이 돈다.
  - 상태 기록은 링 선의 색과 굵기로 그린다. 실행 중은 초록 실선, 응답 대기는 굵은 주황, 턴 종료는 노란 점선이다. 관측 규칙은 기존 timeline 과 같다(stale·uncertain 처리, task 의 세션 합치기).
  - turn 시작은 링 위의 점으로, tool 호출은 링 안쪽의 점으로 그린다. 실패한 호출은 ×로 그린다.
  - acceptance: 시안(Planning hints)과 같은 요소가 나온다. 30분 뒤 같은 기록이 링에서 30분만큼 옮겨 가 있다.
- R6 (MUST) dashboard 는 task 를 응답 대기 → 실행 중 → 턴 종료 순으로 놓는다. 같은 상태끼리는 최근 활동 순이다. 실행 중·대기 task 수에 따라 배치가 다르다.
  - 3개 이하: 큰 링을 최대 3개 나란히 놓고, 남는 자리는 턴 종료 task 가 채운다.
  - 4개: 작은 링 2×2로 놓는다.
  - 5~6개: 작은 링 3×2로 놓는다.
  - 링에 들지 못한 task 는 아래 한 줄에 "+n more" 로 모은다. 턴 종료 task 는 결과 요약을 붙인다.
  - acceptance: 실행 중·대기 task 가 1, 3, 4, 6, 7개인 문서에서 각각 위 배치가 나오고, 화면을 넘치지 않는다.
- R7 (MUST) 링 가운데에 상태별 요약을 보인다.
  - 실행 중: todo 완료 수/전체 수. 큰 링에서는 진행 중 항목 문장도 보인다(R9 를 따른다).
  - 응답 대기: "Needs you", 대기 이유, 경과 시간.
  - 턴 종료: R4 의 결과 요약.
  - acceptance: 세 상태의 task 가 각각 위 내용을 가운데에 보인다.
- R8 (MUST) 큰 링은 최근 30분의 호출을 도구 노드와 잇고, 그 호출이 건드린 최근 파일 6개를 파일 노드로 잇는다. 도구 노드는 호출이 많을수록 크다. 작은 링은 도구·파일·눈금 label 을 그리지 않는다.
  - acceptance: 30분이 지난 호출은 선 없이 점만 남는다. 파일 노드는 6개를 넘지 않는다. 작은 링에는 label 이 없다.
- R9 (MUST) 파일 이름, 명령, todo 문장은 Settings 의 노출 설정을 켤 때만 dashboard 에 보인다. 기본은 꺼짐이다.
  - acceptance: 새 설치의 dashboard 에 세 종류 글이 없다. 설정을 켜면 나타난다.
- R10 (MUST) 새 tool 호출은 runtime snapshot 이 도착하면 링에 나타나며, 링에서 도구 노드로 움직여 들어가는 짧은 표시가 있다. 변화가 없으면 frame 을 그리지 않는다.
  - acceptance: hook 이벤트 뒤 2초 안에 표시된다. 변화 없는 1분 동안 animation frame 요청이 없다.
- R11 (MUST) 새 필드가 없는 문서(이전 수집기)에서도 dashboard 는 오류 없이 상태 기록만으로 링을 그린다. todo·결과 요약 자리는 비우거나 대체 표시한다.
  - acceptance: 이전 수집기 형식의 문서로 띄운 dashboard 에 오류가 없고 링이 보인다.
- R12 (SHOULD) 시계·날짜·잠금 표시와 상태별 개수 header 는 그대로 두고, 기존 timeline 은 링으로 대체한다.
  - acceptance: header 가 지금과 같고 timeline 행이 없다.
- R13 (SHOULD) subagent 나 다른 agent 의 보고로 이어진 turn 은 속이 빈 점으로 구분한다.
  - acceptance: subagent 결과가 들어온 세션의 링에 속이 빈 turn 점이 있다.

## Open questions
- 모두 계획 단계에서 정했다(아래 Decision Log 와 Outcome 의 결정 요약).

## Planning hints
- 시안: workbranch task 루트(저장소 밖)의 `mockups/ring-dashboard.html`, `mockups/ring-dashboard-v1.html`, `mockups/agent-status-pill.html`.
- agent-runtime: `apps/agent-runtime/src/event.rs` 의 `PreToolUse` / `PostToolUse` / `PostToolUseFailure` / `Stop` 처리, `store.rs` 에 `transitions` 처럼 시간 index 가 있는 호출 테이블.
- todo 출처: Claude 는 `TodoWrite` 의 `tool_input.todos[]`. 다른 provider 의 plan 도구는 확인이 필요하다.
- contract: `packages/contract` 의 `WorkbranchRuntimeDocument` 세션 선택 필드(예: 호출 목록, turn 목록, todo, 마지막 turn 요약). `transitions`·`messages` 를 더한 방식과 같다.
- companion: `src/DashboardApp.tsx`, 칸반 순서와 행 선택은 `buildMainViewModel()` 재사용, 데이터는 `useRuntimeSessions`.
- 렌더링: 정적 SVG 층과 애니메이션 층을 나눈다. task 가 많으면 Canvas 도 검토한다.
- spec 갱신: `docs/specs/comp/screensaver.md` 화면 구성, `docs/specs/comp/runtime-snapshot.md` 세션 필드.

## Decision Log
- 2026-11-27 · Q1 의미 층(topic·decision·question)을 넣을까 → 넣지 않는다 · 잠금 화면에서 멀리 읽히지 않고, 모델 태깅 비용과 내용 노출이 크다.
- 2026-11-28 · Q2 링 한 바퀴의 기준 → 최근 3시간, 맨 위가 지금 · 자리를 비운 동안에는 사용자 turn 이 늘지 않아 turn 기준 링은 거의 움직이지 않는다. 시간 기준이면 쉰 구간도 보이고 기존 timeline 역할도 맡는다.
- 2026-11-28 · Q3 여러 task 의 위계 → 응답 대기 → 실행 중 → 턴 종료 순, 칸반과 같다 · 잠금 화면에서 가장 중요한 질문은 "나를 기다리는가"다.
- 2026-11-28 · Q4 큰 링을 몇 개까지 → 최대 3개, 실행 중·대기 task 가 4~6개면 작은 링 격자, 그 이상은 한 줄 · 큰 링 하나 + 위성 배치보다 세 개를 나란히 둬도 가운데 정보가 충분히 읽힌다.
- 2026-11-28 · Q5 진행도와 결과를 보일까 → todo 완료/전체와 턴 종료 요약(파일, 줄 수, 테스트, commit)을 보인다 · 멀리서 알고 싶은 "얼마나 남았나"와 "무엇을 남겼나"에 답한다.
- 2026-11-28 · Q6 선이 엉키는 문제 → 도구 선은 최근 30분만, 파일 노드는 최근 6개만 · 오래된 선이 가운데를 덮어 지금 하는 일이 안 보였다.
- 2026-11-28 · Q7 파일 이름 노출 → 기본 숨김 · 기존 메시지 노출과 같은 원칙이다.
- 2026-11-28 · 계획 결정 → Slice 0 공용 규칙 이동 · 화면 먼저 · 줄 수는 편집 입력 · 테스트는 고정 패턴(`passed`/`failed`/`unknown`/`none`) · 도구 11개 묶음은 companion 이 · 노출 설정은 `showMessages` 하나를 "Show work details" 로 · `tool_calls` 24시간·snapshot 3시간 300건·schema 3 한 번 · 작은 링은 단순하게 · todo 없으면 경과 시간 + 30분 호출 수 · 새 호출 표시는 SVG `animateMotion`.
- 2026-11-28 · 검증 뒤 사용자 요청 → branch·repo 를 링 위로, agent | 상태를 한 알약으로 나눈다(agent 는 무채색 모양과 이름, 색은 상태만).

## Outcome
- 2026-11-28T08:29:48.000Z · **Go with follow-ups**
- 이룬 것:
  - R1 수집기가 tool 호출(도구 이름, 파일 basename, 실패 여부)을 `tool_calls`(schema 3, 24시간)에 남기고 snapshot `calls`(3시간·300건)로 낸다. 명령 글·경로·편집 내용은 남기지 않는다.
  - R2 사용자 요청 turn 시작을 `turns` 로 낸다.
  - R3 Claude Code `TaskCreate`/`TaskUpdate`, `TodoWrite`, Codex `update_plan` 을 성공한 호출만 반영해 `todos`(전체·완료·진행 중 글)로 낸다.
  - R4 끝난 turn 의 요약 `lastTurn`(바뀐 파일, 추가·삭제 줄, 마지막 테스트 결과, commit 수)을 snapshot 에서 계산한다.
  - R5–R8 잠금 화면 dashboard 가 timeline 대신 task 링을 그린다: 최근 3시간 시계판(맨 위가 지금), 상태 선, turn 점, todo 조각, 링 안쪽 호출 점·도구 노드·최근 파일과 30분 선(큰 링만), 상태별 가운데, 실행 중·대기 수에 따른 배치(큰 링 3 / 2×2 / 3×2 / 한 줄).
  - R9 "Show work details" 가 꺼져 있으면 파일 이름·지금 하는 일·메시지·todo 글이 화면 모델에 실리지 않는다.
  - R10 새 호출은 SVG 애니메이션으로 한 번 보이고, JS 타이머·rAF 를 쓰지 않는다.
  - R11 새 필드가 없는 문서에서도 동작한다. R12 header 는 그대로, timeline 은 없어졌다. R13 Claude `SubagentStop` 을 등록해 subagent 보고를 속이 빈 turn 점으로 그린다.
  - 링 위에 agent | 상태 알약과 branch·repo, 링 아래에 work details.
- 검증: `run: 2026-11-28 17:12 · stale: no · audit: self` · tasks 22/22 + F1 · R-ids 13/13 · Quality bar 17/17 · 수집기 57 · contract 8 · companion vitest 351 · src-tauri 178 · R3·R4 는 실제 Claude Code 세션(2.1.332)으로, R5·R7–R10 은 로컬 설치판에서 사용자가 확인. baseline 실패(CLI 테스트 2건, contract format 2건)는 이 변경과 무관.
- note: Claude `Edit` 의 줄 수는 근사치다. 같은 PostToolUse 가 반복되면 id 없는 `TaskCreate` 가 todo 를 하나 더 셀 수 있다.
- 남은 확인: R13(SHOULD) 실제 subagent 화면은 Claude 플러그인을 이 저장소 버전으로 다시 설치한 뒤 본다.
- follow-ups:
  - Claude Code 는 현재 모델에서 todo 도구를 기본으로 주지 않는다(`CLAUDE_CODE_ENABLE_TODO_TOOLS=1`). `TodoWrite` 실제 payload 와 Codex `update_plan` hook 은 미확인.
  - 잠기지 않은 dashboard(미리 보기·창)의 단축키(`1`/`2`/`3` 링 크게 보기, `F` 전체 화면, `Enter` 닫기) — 새 intent.
  - 메뉴 막대 칸반 카드에 같은 agent | 상태 알약 — 새 intent.
  - README 의 dashboard 그림(`assets/readme/dashboard-en.svg`)과 설명을 링 화면으로 — docs commit.
  - 내용 없는 `COMP003-dashboard-timeline.md` 정리(`/tk-intent archive COMP003`).
  - CLI 통합 테스트 2건의 기존 실패(TTY 입력, stash 정리).
  - Non-goals 의 follow-up intent 네 가지(의미 층 태깅, 막힘 감지, subagent 가지 링, 번인 방지·감광).

