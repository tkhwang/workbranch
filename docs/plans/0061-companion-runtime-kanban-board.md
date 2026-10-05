# 0061 Companion Runtime Kanban Board

**Goal:** hook으로 수집한 runtime 상태를 Main 화면에서 칸반 열로 보여주고, task별 IDE/Terminal/Finder 실행과 repo 메타 정보를 카드를 펼치지 않아도 바로 쓰게 한다.

**Architecture:** 0060의 runtime 계약(`workbranch runtime --json`)과 `buildMainViewModel`의 대표 상태(`runtimeRole`)는 그대로 둔다. `StageBoard`가 기존 `groups`/`idleRows`를 받아 `waiting | running | finished` 열과 `WORKSPACES` 목록(unknown + idle)으로 나눠 렌더링한다. Rust collector, contract schema, Tauri command는 바꾸지 않는다. native 창 기본 너비만 520px에서 860px로 바꾼다.

**Approved mockup:** https://claude.ai/artifact/Xb2TLVAD78x4nbaVMjHTrT (시안 A "3열 칸반" 승인: "860 으로 넓히고, A 로 해볼까 ?")

---

## 사용자 문제와 흐름

1. 0060에서 hook 연동으로 바꾸면서 Main이 대기/실행/턴 종료 그룹의 세로 목록이 됐다. 사용자는 BITL·AgentNotch처럼 상태를 칸반으로 나눠 보고 싶어 한다.
2. task(repo) 메타 정보로 IDE를 여는 것이 가장 중요한 작업인데, IDE/Terminal/Finder 버튼과 repo/branch 정보가 카드를 펼친 뒤 세션 상세 아래에 숨어 있다.
3. 열 구성은 사용자 제안대로 현재 코드의 runtime 단계를 그대로 쓴다. plan/execution 구분을 위해 `permission_mode`를 새로 수집하는 안은 이번 범위에서 제외했다.

## 결정

- D1. 열: `내 응답 대기(WAITING) | 실행 중(RUNNING) | 턴 종료 · 검토(REVIEW)`. 기존 `runtimeRole`의 대표 상태를 그대로 쓴다. 턴 종료는 작업 완료가 아니라 사람이 검토할 차례라는 뜻이다.
- D2. 세션이 여러 개인 task는 대표 상태 열에 한 번만 두고, 다른 상태의 관측 세션은 `+N 실행 중` 같은 칩으로 표시한다.
- D3. 세션 없음, 관측 불명(stale/uncertain), 비활성 task는 보드 아래 `WORKSPACES` 목록에 기본으로 펼쳐 둔다. 관측 불명 세션을 실행 중 열에 넣지 않는다.
- D4. 모든 카드 첫 줄에 기존 launcher 묶음을 겹쳐 둔다. repo 행(이름, branch, `CLEAN`/`●N`/`↑N`/`↓N`, note 버튼)은 항상 보인다. 최근 commit과 세션 상세는 펼쳤을 때만 보인다.
- D5. 클릭은 상세 펼치기와 선택, 더블클릭은 repo가 있는 task의 IDE 실행이다. 더블클릭의 두 번째 click은 무시하고, dblclick에서 펼침 상태를 원래대로 되돌린다.
- D6. 카드가 열을 옮기면 React가 다시 마운트하므로, 펼친 카드 key와 작성 중인 note draft를 `StageBoard` state로 올려 유지한다.
- D7. 레이아웃: `.runtime-board`를 inline-size container로 두고, 보드 너비 720px 이상에서 3열과 2열 `WORKSPACES`, 그보다 좁으면 같은 순서의 세로 레인으로 쌓는다. 기본 창은 860×760, 최소 460px은 유지한다.
- D8. runtime 상태 색은 `--runtime-*` 테마 토큰으로 옮긴다. 두 테마가 같은 값을 쓴다. 새 표면에는 `color-mix`를 쓰지 않는다.

## 범위 밖

- hook payload의 `permission_mode` 수집과 PLAN 단계 표시. 필요하면 후속으로 agent-runtime·contract에 optional 필드를 추가한다.
- 원격 allow/deny 등 agent 제어 버튼.
- 카드 drag-and-drop 등 상태 수동 변경.

## 변경 파일

- `apps/companion/src/ui/StageBoard.tsx`: 칸반 열, `RuntimeCard`(card/row), `WORKSPACES` 목록, 상태 lifting.
- `apps/companion/src/ui/TaskRow.tsx`: `compactRepoFacts`, `formatObservedAgo`(`now 전` 대신 `방금`).
- `apps/companion/src/styles/stage-board.css`: runtime 섹션 교체, container query.
- `apps/companion/src/styles/themes.css`: `--runtime-*` 토큰.
- `apps/companion/src-tauri/tauri.conf.json`: 기본 너비 860.
- `apps/companion/tests/runtime-view.test.tsx`, `apps/companion/tests/app-shell.test.tsx`.
- `DESIGN.md`.

## 검증 (2026-10-05)

- `pnpm --filter @workbranch/companion test`: 19 files, 226 tests passed.
- `pnpm --filter @workbranch/companion typecheck`, `lint`: error 없음. 기존 info 85개는 그대로다.
- 임시 preview 페이지(fixture 데이터, 검증 후 삭제)를 headless Chrome으로 확인했다.
  - 860px: 세 열이 나란히 놓이고 `WORKSPACES`가 2열이다. 가로 overflow 없음.
  - 460px(Claude), 520px(Codex): 세로 레인으로 쌓이고, launcher와 note 버튼이 잘리지 않는다.
  - CDP 조작: 클릭하면 펼쳐지고 commit과 세션 상세가 보인다. 더블클릭은 IDE action을 한 번 호출하고 펼침 상태를 유지한다. note 작성 중 카드가 RUNNING에서 REVIEW로 옮겨져도 draft와 focus가 유지되고, ⌘Enter로 저장된다.
- 남은 acceptance: 설치된 Companion 앱에서 실제 hook 데이터와 860px popover의 메뉴바 위치(`Position::TrayCenter` 제약)를 확인한다. window-state plugin이 없으므로 앱은 매번 설정된 크기로 열린다.

## 후속 수정 — 좁은 열의 카드 정리 (2026-10-05)

실제 앱 화면(REVIEW 열)에서 확인한 문제: launcher가 `project / task` 줄을 나눠 쓰면서 task 이름이 `feature-cpq-task-` / `a`처럼 끊겼다. repo 줄은 branch 때문에 이름이 잘렸다. 상태 칩, provider, 시간이 한 줄씩 밀려 내려갔다. 카드 전체에 걸린 tooltip이 내용을 가렸다.

- 1행은 project 이름(말줄임)과 launcher만 둔다. task 이름은 2행 전체 폭을 쓴다.
- 모든 repo가 같은 branch면 repo 묶음 위에 branch를 아이콘과 함께 한 번만 표시한다. 다르면 repo 줄 아래에 각자 표시한다.
- repo 줄은 이름, 상태, ✎만 둔다. 이름은 잘리지 않고 하이픈에서 줄바꿈된다. `CLEAN`은 `●`/`↑`/`↓`가 하나도 없을 때만 표시한다.
- 상태 줄: 대표 상태만 pill로 두고, 나머지 세션 수는 흐린 일반 텍스트로 둔다. provider·시간은 오른쪽에 붙인다.
- 카드 toggle의 `title` tooltip을 제거했다.
- 검증: Companion 테스트 229개 통과, typecheck·lint error 없음. 열이 가장 좁아지는 760px 창에서 두 테마로 headless Chrome 캡처를 확인했다(임시 preview는 삭제).

## 후속 수정 — provider 아이콘 (2026-10-05)

- 카드의 `CLAUDE`/`CODEX` 글자와 세션 상세의 provider 이름을 14px `ProviderIcon`(`apps/companion/src/ui/ProviderIcon.tsx`)으로 바꿨다. Claude는 주황 spark, Codex는 육각형, Grok은 사선 원이다. 브랜드 로고를 복제하지 않은 단순 표식이며, `title`과 `aria-label`로 이름을 제공한다.
- 한 task에 여러 provider 세션이 있으면 대표 세션부터 provider별 아이콘을 하나씩 나란히 둔다.
- 칸반 카드 테두리를 대표 세션 provider 색으로 옅게 칠한다(Claude 주황, Codex 청록, Grok 은색). 아이콘도 같은 색을 쓴다. 대기 카드는 테두리 대신 바깥 링(`--runtime-waiting-ring`)으로 강조해서 provider 색과 대기 상태를 함께 읽을 수 있게 했다. WORKSPACES 행은 칠하지 않는다.
- 색 토큰 `--provider-{claude,codex,grok}`와 `--provider-*-line`, `--runtime-waiting-ring`을 두 테마에 추가했다.
