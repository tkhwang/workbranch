# 0025 Companion UX 다듬기와 언어 prompt 선택지 개선 계획

> **agentic worker 지침:** 실행 시 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용한다. 동작 변경 전에는 `superpowers:test-driven-development` 흐름(red → green → refactor)을 따른다. CLI 코드는 `src/workbranch/**`를 먼저 수정하고 `scripts/build-workbranch.sh`로 `bin/workbranch`를 재생성한다. `bin/workbranch`를 직접 수정하지 않는다. 새/수정 bash 테스트는 반드시 `tests/run.sh`에 `run_test ...`로 등록한다. Companion 변경은 `companion/`에서 `swift build` + `swift run CompanionCoreTestRunner`로 검증한다. 검증은 syntax check → 관련 테스트 red/green → `./tests/run.sh` 전체 → companion build → `git diff --check` 순서. 문서를 건드리면 EN/KO를 같은 PR에서 동기화한다.
>
> **시리즈 위치:** 0024에서 도입한 `PREFERRED_LANGUAGE en|ko`와 companion current-work line 위에 얹는 **UX 다듬기** slice다. 동작 계약을 새로 만들지 않고, 기존 prompt/정렬/레이아웃을 더 쓰기 좋게 조정한다.

**목표:** 사용자 피드백 다섯 가지를 반영한다.

1. **언어 선택 prompt 선택지 노출** — 현재 `[*] Preferred language for generated task guidance [English]:`는 현재값만 보여 한글 선택 가능 여부가 드러나지 않는다. IDE/Terminal prompt처럼 `1) English` / `2) 한글` 번호 프리셋을 먼저 출력해 선택지를 분명히 한다.
2. **Companion 정렬 = 최신 memo update 위로 (task + project 모두)** — 각 프로젝트 안 task를 `updatedAt`(= `TASK-WORKBRANCH.md` mtime) 내림차순으로, 프로젝트(섹션)도 각 프로젝트의 가장 최신 task `updatedAt` 기준 내림차순으로 정렬한다. 최근 갱신한 작업이 항상 위로 온다.
3. **Companion 기본 height 확대** — popover 기본 높이를 600 → 720으로 늘려 task가 많을 때 여유를 준다.
4. **status 우측 content 테두리 제거** — task row의 `status` 줄에서 현재값 텍스트를 감싸는 외곽선(stroke) 박스를 제거한다. 강조 색/굵기는 유지하되 테두리만 없앤다.
5. **status update 읽지 않음 표시** — `updatedAt/currentItem`이 바뀐 task는 사용자가 해당 status/message row를 클릭하기 전까지 companion에서 unread로 구분한다. unread 판정은 companion-local read marker와 `updatedAt` 비교로 처리하고, 개별 notification message read/unread는 별도 slice로 둔다.

**아키텍처:** 1번만 CLI(`src/workbranch/**` → generated `bin/workbranch`)이고, 2·3·4·5번은 companion 표현 계층/로컬 상태(`companion/Sources/**`, `~/.config/workbranch-companion/read-state.json`)만 바꾼다. JSON 계약(`workbranch list --json`)과 workbranch config 포맷은 변경하지 않는다. 정렬은 companion `MenuState.make()`에서 수행하므로 CLI 출력 순서(`list.sh`의 glob 순서)는 그대로 둔다.

**기술 스택:** portable Bash + generated single-file CLI, `tests/run.sh` integration harness, Swift/SwiftUI companion(`companion/Package.swift`).

**제품 관점:** 첫 설정에서 한글이 선택 가능함을 바로 알게 하고(1), 메뉴바를 열었을 때 방금 손댄 작업이 맨 위에 보이며(2), 화면이 더 넉넉하고(3), status 줄이 박스 없이 깔끔하고(4), 새 status update가 사용자의 확인 전까지 눈에 띄도록(5) 한다. 전부 비파괴적 UX 개선이다.

---

## 문제

1. **언어 선택지가 숨어 있음.** `configure_preferred_language_prompt()`는 `[$current]`(현재값)만 보여준다. `normalize_preferred_language_choice()`는 이미 `한글`/`ko`/`2`는 아니지만 `1`/`en`/`English`를 받지만, 사용자는 한글을 고를 수 있다는 사실 자체를 화면에서 알 수 없다.
2. **정렬이 갱신 시각과 무관.** companion `MenuState.make()`는 `document.tasks`를 CLI가 준 순서(= `list.sh`의 `for path in "$PROJECT_ROOT"/*` glob, 사실상 알파벳)대로 그대로 나열하고, 섹션도 config 등록 순서 그대로다. 방금 갱신한 task가 아래에 묻힐 수 있다.
3. **height가 좁음.** `CompanionPopoverView`가 `height: 600`으로 고정되어 task가 늘면 답답하다.
4. **status 줄에 불필요한 테두리.** `RowView.currentWorkLine`이 현재값 텍스트에 `RoundedRectangle(...).stroke(...)` 박스를 둘러 시각적으로 과하다.
5. **status update가 읽힘/안읽힘 없이 같은 모양.** 현재 companion은 task row에 `updatedAt/currentItem`을 표시할 수 있고 noti count는 보여주지만, 사용자가 새 status update를 실제로 확인했는지 구분하는 companion-local read marker가 없다.

## 현재 repo 근거

- `src/workbranch/commands/config.sh:175` `configure_preferred_language_prompt()`: `info "Preferred language"` 후 `prompt_read "[*] Preferred language for generated task guidance [$current]: "`. IDE/Terminal은 `configure_ide_prompt()`/`configure_terminal_prompt()`에서 `print_ide_presets`/`print_terminal_presets`로 번호 목록을 먼저 출력하는 패턴을 쓴다.
- `src/workbranch/lib/config.sh:165` `normalize_preferred_language_choice()`: `en|EN|English|english|1 → en`, `ko|KO|Korean|korean|Hangul|hangul|한글 → ko`, 그 외 die. **`2`는 아직 매핑되어 있지 않다.**
- `src/workbranch/lib/config.sh:158` `preferred_language_label()`: `ko → 한글`, 그 외 `English`.
- `src/workbranch/commands/init.sh:170` `prompt_language_config_after_init()` → `configure_preferred_language_prompt yes` (EOF 허용). config 흐름은 `cmd_config`의 `language` target에서 같은 함수를 호출.
- prompt 문자열을 검증하는 테스트: `tests/cases/interactive-init.sh:76,78,82,398,400`, `tests/cases/config.sh:139`가 `[*] Preferred language for generated task guidance [English]:` 를 `assert_contains`로 본다. → **prompt 본문 문자열은 유지**하면 회귀 없음.
- `companion/Sources/CompanionCore/MenuState.swift:208` task 루프는 `for task in document.tasks` 그대로 순회하며 `rows.append(taskRow(...))`. 섹션은 `for root in roots`(config 순서) 순서로 `sections.append(...)`.
- `companion/Sources/CompanionCore/Models.swift:87` `WorkbranchTask.updatedAt: Int` 존재(`task-state.sh:25` `task_updated_at` = `TASK-WORKBRANCH.md` mtime). `MenuSection`(`Models.swift:113`)에는 timestamp 필드가 없다.
- `companion/Sources/CompanionApp/Views/CompanionPopoverView.swift:32` `.frame(width: 560, height: 600)`.
- `companion/Sources/CompanionApp/Views/RowView.swift:92` `currentWorkLine`: status `Text(statusDisplayText)`에 `.padding(.horizontal,7)`, `.padding(.vertical,2)`, `.background(RoundedRectangle(cornerRadius:4).stroke(palette.warning.opacity(0.75), lineWidth:1))` 적용. 색은 `palette.warning`, `.fontWeight(.bold)`.
- `companion/Sources/CompanionApp/Views/RowView.swift:171` `statusDisplayText`: `currentWorkText`와 `updatedTimeText`(`updatedAt` → `HH:mm`)를 합쳐 status line에 표시한다.
- `src/workbranch/commands/noti.sh:1` `workbranch noti <add|list|clear>`는 task 단위 inbox를 append/list/clear만 한다. `src/workbranch/lib/task-state.sh:378` `noti_count()`와 `src/workbranch/commands/list.sh:41` `notiCount`는 unread count처럼 보이지만 개별 message read marker는 없다.
- `companion/Sources/CompanionCore/MenuState.swift:137` `NotificationTracker`는 `notiCount` 증가를 감지해 macOS notification을 보내는 runtime tracker다. `companion/Sources/CompanionCore/Actions.swift:31` clear action은 `workbranch noti clear <task>` 전체 삭제다.
- companion 테스트 진입점: `companion/Sources/CompanionCoreTestRunner/main.swift`, `Tests/CompanionCoreTests/`. 현재 `companion/Tests/CompanionCoreTests/Empty.swift`는 XCTest/Testing module unavailable 때문에 비워 둔다는 주석만 있다.

## 결정 사항 (확정됨)

1. **언어 prompt 스타일:** IDE/Terminal과 동일한 **번호 프리셋 목록**(`1) English`, `2) 한글`)을 prompt 위에 출력한다. 입력은 `1`/`2`/`en`/`ko`/`English`/`한글` 등 기존 + 신규를 모두 허용한다. **prompt 본문 문자열은 그대로 유지**한다.
2. **정렬 범위:** **task와 project(섹션) 모두** 최신 `updatedAt` 내림차순. 섹션 키는 그 섹션의 task 중 최대 `updatedAt`. 동률·task 없는(에러/무데이터) 섹션은 기존 config 등록 순서를 안정적으로 유지하고 하단으로 보낸다(최대값 0 취급).
3. **height:** 기본 `600 → 720`. width(560)는 유지.
4. **테두리:** status 줄 현재값 텍스트의 **stroke 박스 제거**. 색(`palette.warning`)·굵기(bold)는 유지. 박스가 사라지므로 의미 없어진 좌우/상하 padding도 함께 제거해 정렬을 깔끔히 한다.
5. **읽지 않음 범위:** 이번 slice는 **status/current-work update의 companion-local unread 표시**만 처리한다. unread key는 `root + task`, unread 판정은 `task.updatedAt > lastReadUpdatedAt[root/task]`, 읽음 처리는 사용자가 해당 status/message row를 클릭했을 때다. read marker는 `~/.config/workbranch-companion/read-state.json`에 저장한다. 개별 notification message 단위 read/unread, message id, partial clear는 별도 계획으로 둔다.

## 결정 게이트 결과

- [x] **언어 prompt 본문 문자열은 바꾸지 않는다(프리셋만 추가).**
  - Impact: 기존 prompt-문자열 의존 테스트(interactive-init, config) 회귀 여부.
  - Current evidence: 5개 assert가 `[*] Preferred language for generated task guidance [English]:` 부분 문자열을 본다.
  - Resolved: prompt 위에 프리셋 줄만 추가하고 `prompt_read` 문자열은 유지 → 기존 `assert_contains` 통과. 프리셋 노출은 신규 assert로 잠근다.
  - Rejected: prompt 본문을 `[English/한글]`로 교체. 이유: 5개 테스트 동시 수정 필요 + 사용자가 고른 스타일(번호 프리셋)과 불일치.

- [x] **정렬은 companion `MenuState`에서 수행하고 CLI 출력 순서는 두지 않는다.**
  - Impact: 정렬 위치(CLI vs UI), 결정성.
  - Current evidence: `list.sh`는 glob 순서로 deterministic하게 task를 emit. companion이 표시 직전 모델을 만든다.
  - Resolved: 정렬을 `MenuState.make()`에 둔다. CLI는 변경 없음 → JSON 계약/타 소비자 영향 없음. 알림 카운트 집계는 순서 무관이라 동일.
  - Rejected: `list.sh`에서 정렬. 이유: JSON 순서는 다른 소비자 계약일 수 있고, 표현 정렬은 UI 관심사다.

- [x] **`updatedAt` 동률·무데이터 섹션은 config 순서로 안정 정렬한다.**
  - Impact: 정렬 안정성/예측 가능성.
  - Current evidence: 에러/이전 캐시 섹션은 task가 없어 `updatedAt` 최대값이 정의되지 않는다.
  - Resolved: 무데이터/동률은 최대값 0 + 기존 인덱스 tie-break로 config 순서를 보존하고 하단에 둔다.

- [x] **status update unread는 companion-local `updatedAt` read marker로 처리한다.**
  - Impact: user-visible unread semantics / local companion state placement.
  - Current evidence: `workbranch list --json` already exposes `updatedAt/currentItem/status`; existing `noti` contract is task-level append/list/clear with only `notiCount` in JSON and no message id/read marker.
  - Resolved: 이번 slice는 `root + task`별 `lastReadUpdatedAt`을 `~/.config/workbranch-companion/read-state.json`에 저장하고, `task.updatedAt > lastReadUpdatedAt`이면 status/current-work line을 unread로 표시한다. 사용자가 해당 row/status message를 클릭하면 현재 `updatedAt`까지 읽음 처리한다.
  - Rejected: `<task>/.workbranch/notifications.jsonl` message별 read/unread를 이번 slice에 추가. 이유: message id, partial clear/list JSON shape, CLI command semantics까지 새 계약이 필요해 UX 다듬기 범위를 넘는다.

- [x] **read-state 파일 위치는 `~/.config/workbranch-companion/read-state.json`로 고정한다.**
  - Impact: companion-local persistence artifact path / future migration cost.
  - Current evidence: `StateStore.defaultConfigURL()` already uses `~/.config/workbranch-companion/projects.md`; existing companion config state is rooted under `~/.config/workbranch-companion/`.
  - Resolved: unread read marker는 `projects.md`와 분리된 `~/.config/workbranch-companion/read-state.json` JSON 파일에 저장한다.
  - Rejected: `projects.md`에 함께 저장. 이유: 사람이 편집하는 config와 자동 갱신 read marker가 섞인다.
  - Rejected: `~/Library/Application Support/workbranch-companion/read-state.json`. 이유: macOS 앱 관례에는 맞지만 현재 companion 설정 루트와 분리되어 사용자가 상태 파일을 찾기 어려워진다.

- [x] **read-state 최초 생성 시 기존 task는 baseline read로 처리한다.**
  - Impact: upgrade / first-run unread semantics.
  - Current evidence: 기존 task 대부분은 `TASK-WORKBRANCH.md` 때문에 `updatedAt > 0`이며, 현재 `NotificationTracker`도 baseline refresh에서는 알림을 보내지 않는다.
  - Resolved: `read-state.json`이 없거나 비어 있는 최초 baseline refresh에서는 현재 보이는 task의 `updatedAt`을 read marker로 저장하고 unread로 표시하지 않는다. 이후 refresh에서 `updatedAt`이 marker보다 커질 때만 unread로 표시한다.
  - Rejected: 빈 read state에서 모든 `updatedAt > 0` task를 unread로 표시. 이유: 기능 도입 전부터 있던 task가 모두 unread가 되어 새 update 신호가 노이즈가 된다.

- [x] **read 처리 클릭 대상은 status/current-work line으로 한정한다.**
  - Impact: user-visible read lifecycle / accidental read risk.
  - Current evidence: 현재 task row 전체 click action은 없고, `CompanionCoreTestRunner` source-level test가 task row primary action 미실행을 잠근다. unread 표시 대상은 `RowView.currentWorkLine`이다.
  - Resolved: 사용자가 `status/current-work` line을 클릭할 때만 해당 task의 현재 `updatedAt`까지 read marker를 저장한다. task row 전체, repo/branch/detail checklist 영역 클릭은 read 처리하지 않는다.
  - Visual contract: unread 상태의 status/current-work line은 mobile notification clear affordance처럼 “여기를 눌러 읽음 처리한다”가 보이게 만든다. 예: unread dot/`unread` token + hover/click 가능한 plain button row + 강조색. 단, 0025의 기존 결정대로 status 텍스트 자체를 감싸던 old stroke box는 되살리지 않는다.
  - Rejected: task row 전체 클릭. 이유: repo/branch/detail을 훑거나 스크롤하려는 동작이 accidental read가 될 수 있다.
  - Rejected: unread badge/token만 클릭. 이유: 너무 작은 target이라 메뉴바 popover UX에서 번거롭고, 사용자가 말한 message click보다 좁다.

- [x] **read-state JSON shape는 schemaVersion + nested root/task map으로 고정한다.**
  - Impact: durable local state schema / future migration and pruning behavior.
  - Current evidence: `workbranch list --json`와 Companion model은 `schemaVersion`을 명시하고, root path는 delimiter 기반 flat key에서 디버깅/escaping이 까다롭다.
  - Resolved: 파일 구조는 `{ "schemaVersion": 1, "roots": { "<canonicalRoot>": { "<task>": <lastReadUpdatedAt> } } }`로 한다.
  - Rejected: `tasks` flat map with `root\u0000task`. 이유: compact하지만 두 identifier가 한 key에 숨어 escaping/debugging이 어렵다.
  - Rejected: `entries[]` array. 이유: explicit하지만 write마다 search/update/dedup 로직이 필요하다.

## 변경 계획

### 1. `src/workbranch/lib/config.sh` — 언어 선택지 매핑 + 프리셋 출력 헬퍼

- `normalize_preferred_language_choice()`에 `2 → ko` 매핑을 추가한다(`en`은 `1` 기유지). 기존 허용 입력은 모두 유지.
- IDE/Terminal `print_*_presets`를 모방한 `print_language_presets()` 헬퍼를 추가한다(또는 config.sh의 presets 위치에 맞춰 배치):
  ```
  1) English
  2) 한글
  ```
  현재값을 `(current)`로 살짝 표시하는 형태도 허용하되, 핵심은 두 줄 노출이다.

### 2. `src/workbranch/commands/config.sh` — prompt 앞 프리셋 노출

- `configure_preferred_language_prompt()`에서 `prompt_read` 직전에 `print_language_presets`를 호출한다.
- **prompt 본문**(`[*] Preferred language for generated task guidance [$current]: `)은 그대로 유지한다.
- EOF/allow_eof 처리, `normalize_preferred_language_choice` → `set_preferred_language` 흐름은 변경 없음.

### 3. `companion/Sources/CompanionCore/MenuState.swift` — 정렬

- task 루프: `for task in document.tasks` → `document.tasks.enumerated().sorted { ($0.element.updatedAt, -$0.offset) > ($1.element.updatedAt, -$1.offset) }.map(\.element)`처럼 `updatedAt` 내림차순 + 원래 index tie-break로 정렬한다. Swift `sorted { $0.updatedAt > $1.updatedAt }`만 쓰면 동률 안정성이 보장되지 않으므로 사용하지 않는다. 알림/카운트 집계 결과는 동일.
- 섹션: 빌드 중 각 섹션의 `maxUpdatedAt`(task 없는 섹션은 0)을 함께 모은 뒤, 전체 섹션을 `maxUpdatedAt` 내림차순 + 원래 인덱스 오름차순(tie-break)으로 정렬해 반환한다. 빈/무데이터/에러 섹션은 하단 + config 순서 유지.
- `MenuSection`에 공개 필드를 추가하지 않고 빌드 시점 로컬 배열로 정렬한다(모델 계약 불변 유지).

### 4. `companion/Sources/CompanionCore` + `CompanionApp` — status update unread read marker

- companion-local read state 모델을 추가한다. 저장 파일은 `~/.config/workbranch-companion/read-state.json`이며, JSON shape는 `{ "schemaVersion": 1, "roots": { "<canonicalRoot>": { "<task>": <lastReadUpdatedAt> } } }`이다. value는 마지막으로 사용자가 확인한 `updatedAt`이다.
- `StateStore`가 시작 시 read state를 로드하고, `MenuState.make()`에 read marker snapshot을 전달해 task별 `isStatusUnread`를 계산하게 한다. JSON/config 계약은 바꾸지 않는다.
- `MenuRow`에 presentation-only 필드(예: `isStatusUnread: Bool`)를 추가해 SwiftUI row가 unread 여부를 알 수 있게 한다. 공개 `workbranch list --json` 필드는 추가하지 않는다.
- `RowView.currentWorkLine`을 클릭 가능한 plain button/gesture로 만들고, click 시 `StateStore.markStatusRead(root:task:updatedAt:)`를 호출해 read marker를 저장한다. task row 전체, repo/branch/detail checklist 클릭은 read 처리하지 않는다.
- unread 표시 방식은 terminal/cockpit 톤을 유지하면서 mobile notification clear affordance처럼 명확히 actionable해야 한다: 예를 들어 status label 앞 `●`, `unread` token, hover/click 가능한 row treatment, 더 강한 accent/warning 색을 사용한다. click 후 즉시 일반 강조 상태로 돌아와야 한다.
- status 텍스트 자체를 감싸던 old `RoundedRectangle(...).stroke(...)` 박스는 되살리지 않는다. unread affordance는 dot/token/button-row treatment로 해결한다.
- 기존 `notiCount`/`NotificationTracker`/`workbranch noti clear` 의미는 변경하지 않는다.

### 5. `companion/Sources/CompanionApp/Views/CompanionPopoverView.swift` — height

- `.frame(width: 560, height: 600)` → `.frame(width: 560, height: 720)`.

### 6. `companion/Sources/CompanionApp/Views/RowView.swift` — status 테두리 제거

- `currentWorkLine`의 status `Text(statusDisplayText)`에서 `.background(RoundedRectangle(cornerRadius:4).stroke(palette.warning.opacity(0.75), lineWidth:1))`를 제거한다.
- 박스가 사라지므로 `.padding(.horizontal, 7)`·`.padding(.vertical, 2)`도 제거한다.
- 색(`palette.warning`)·`.fontWeight(.bold)`·`.lineLimit(1)`·`.truncationMode(.tail)`는 유지해 강조와 한 줄 스캔성을 보존한다.

---

## 테스트 계획 (TDD: 먼저 빨갛게)

### `tests/cases/config.sh` / `tests/cases/interactive-init.sh` — 언어 프리셋

- (red) 신규 assert: 언어 prompt 직전에 `1) English`와 `2) 한글`(또는 확정 문구)이 출력되는지 `assert_contains`로 잠근다. init 후 / `workbranch config language` 두 경로 모두.
- 입력 `2`로 진행 시 `.workbranch.config`에 `PREFERRED_LANGUAGE ko`가 저장되는지 assert.
- 기존 `[*] Preferred language for generated task guidance [English]:` 부분 문자열 assert는 **그대로 통과**해야 한다(회귀 확인).
- 새 테스트는 `tests/run.sh`의 해당 영역에 `run_test ...`로 등록한다.

### `companion` 정렬

- `CompanionCoreTestRunner`에 `MenuState.make` 테스트 추가(`companion/Tests/CompanionCoreTests/Empty.swift`는 현재 XCTest/Testing module unavailable 때문에 비워 둔 convention 유지):
  - 한 프로젝트에 `updatedAt`이 다른 task 3개를 섞어 넣고 결과 row 순서가 `updatedAt` 내림차순인지 검증.
  - 프로젝트 2개(각 최신 task `updatedAt` 다름)에서 섹션 순서가 최신 프로젝트 먼저인지 검증.
  - 동률/무데이터 섹션이 하단 + config 순서로 안정 정렬되는지 검증.

### `companion` unread status update

- `CompanionCoreTestRunner`에 read-state persistence 테스트 추가:
  - `read-state.json`이 없는 최초 baseline refresh는 현재 task들의 `updatedAt`을 read marker로 저장하고 unread로 표시하지 않는다.
  - baseline 이후 새로 계산할 때 `updatedAt`이 marker보다 크면 unread가 된다.
  - `markStatusRead(root, task, updatedAt)` 후 같은 `updatedAt`은 read, 더 큰 `updatedAt`은 unread가 된다.
  - 다른 root/task의 marker와 섞이지 않는다.
  - persisted JSON은 `schemaVersion: 1` + nested `roots[root][task] = updatedAt` shape로 round-trip된다.
  - malformed/missing read-state file은 companion 시작을 깨뜨리지 않고 빈 상태로 복구된다.
- `MenuState.make` 테스트에 `isStatusUnread` row expectation 추가: `updatedAt`과 read marker 비교 결과가 row에 보존된다.
- `RowView`/`StateStore` source-level 또는 focused runner test로 status/current-work line click이 `markStatusRead` action으로 연결되고, task row 전체 click은 read 처리하지 않는지 잠근다.
- Acceptance: 새 status update는 unread 표시가 보이고, 사용자가 status/current-work line을 클릭하면 즉시 read 표시로 바뀌며, 다음 `updatedAt` 증가 때 다시 unread가 된다. unread line은 notification clear affordance처럼 클릭 가능함이 보여야 한다.

### `companion` height / 테두리

- SwiftUI 레이아웃 수치/모디파이어는 단위 테스트 대신 build + 수동 visual QA로 확인한다.
- Acceptance: popover 높이가 720으로 늘었고, status 줄이 old stroke box 없이 색 강조만 유지하며 한 줄로 보인다. unread 상태는 click 전/후 시각 차이가 분명하고, clickable affordance가 status/current-work line에만 있다.

### 통합

- 새/수정 bash 테스트는 `tests/run.sh`에 등록. `./tests/run.sh` 전체 그린.
- `scripts/build-workbranch.sh`로 `bin/workbranch` 재생성 후 `git diff --check`.
- `(cd companion && swift build && swift run CompanionCoreTestRunner)` 그린.
- 수동 visual QA: unread status 표시와 click-to-read 전환 확인.
- read-state 저장 파일은 companion-local UX state이므로 `workbranch` CLI 테스트가 아니라 CompanionCore/StateStore 테스트에서 검증한다.

---

## 검증 순서

1. `bash -n` syntax check (수정한 `src` 파일).
2. (red→green) config/interactive-init 언어 프리셋 테스트.
3. `scripts/build-workbranch.sh` → `bin/workbranch` 재생성.
4. `./tests/run.sh` 전체.
5. `(cd companion && swift build && swift run CompanionCoreTestRunner)` + 수동 visual QA(정렬/height/테두리/unread click).
6. `git diff --check`.

## 롤아웃 / 호환성

- **비파괴 UX 개선.** 새 workbranch CLI 동작 계약/디렉티브/JSON 필드 없음. 단, companion-local read-state 파일(`~/.config/workbranch-companion/read-state.json`)은 새로 생긴다.
- 언어 prompt는 입력 허용 범위만 넓힘(`2` 추가). 기존 `1`/`en`/`한글` 입력 그대로 동작.
- 정렬은 companion 표시 순서만 바뀜. config 등록 순서에 의존하던 사용자는 시각 순서 변화가 있을 수 있음(의도된 개선) — PR 본문에 명시.
- unread status는 companion의 로컬 확인 상태만 바꿈. task memo/noti 파일이나 CLI output은 변경하지 않는다.
- height/테두리는 순수 표현 변경.

## 실행 순서 요약

1. (red) config/interactive-init 언어 프리셋 + `ko` 저장 테스트 추가.
2. (green) `lib/config.sh` `2→ko` + `print_language_presets`, `commands/config.sh` prompt 앞 프리셋 호출.
3. companion `MenuState.make` task/섹션 정렬 + CompanionCore 테스트.
4. companion read-state 모델/저장 + `MenuRow.isStatusUnread` + status line click-to-read 연결.
5. companion `CompanionPopoverView` height 720, `RowView` status 테두리/padding 제거.
6. `tests/run.sh` 등록 확인, `bin/workbranch` 재생성 + 전체 테스트 + companion build + diff check.

---

## 실행 결과

- [x] 언어 prompt에 `1) English` / `2) 한글` 프리셋을 노출하고 `2`/`ko`/`한글` 입력으로 `PREFERRED_LANGUAGE ko`를 저장한다(prompt 본문 문자열 유지).
- [x] Companion이 task와 project를 최신 `updatedAt` 내림차순으로 정렬한다(무데이터/동률은 config 순서 하단 유지).
- [x] Companion popover 기본 height를 720으로 늘렸다.
- [x] status 줄 현재값 텍스트의 old stroke box/padding을 제거하고 색 강조만 유지했다.
- [x] Companion status update가 `updatedAt` 기준 unread로 표시되고, 사용자가 status/current-work line을 클릭하면 read marker가 저장되어 읽음으로 바뀐다.
- [x] `read-state.json`이 없거나 빈 상태인 최초 baseline refresh에서는 기존 visible task를 read로 저장해 도입 직후 전체 task가 unread가 되지 않게 했다.
- [x] 후속 UI 보정: task header에서는 status를 제거하고 primary status line을 `│ STATUS │ HH:mm │ MESSAGE` 형식으로 단순화했다. unread는 status segment의 compact dot/색 강조로 유지한다.
- [x] 리뷰 보정: status read 클릭 후 재빌드가 마지막 refresh error를 보존하고, first-run baseline은 root별 pending set으로 추적해 startup partial failure root가 나중에 복구되어도 기존 task가 unread로 튀지 않게 했다.
- [x] 리뷰 보정: read-state persistence가 config directory watcher를 다시 깨우지 않도록 config watcher를 `projects.md` 파일 이벤트로 제한했다.

검증 evidence:

- `bash -n src/workbranch/lib/config.sh src/workbranch/commands/config.sh bin/workbranch` → pass.
- `scripts/build-workbranch.sh` → `bin/workbranch` regenerated, generated-surface check included in full suite.
- `bash -c 'source src/workbranch/lib/config.sh; print_language_presets'` → `1) English` / `2) 한글`이 실제 개행으로 출력됨.
- `./tests/run.sh` → `Tests passed: 243`.
- `(cd companion && swift build)` → build complete.
- `(cd companion && swift run CompanionCoreTestRunner)` → `CompanionCoreTestRunner: PASS`.
- `git diff --check` → pass.
- 후속 UI 보정 검증: `(cd companion && swift build && swift run CompanionCoreTestRunner)` → build complete + `CompanionCoreTestRunner: PASS`; `git diff --check` → pass.
- 리뷰 보정 검증: `CompanionCoreTestRunner` red/green으로 refresh error 보존과 root별 pending baseline source invariant를 확인했고, `(cd companion && swift build && swift run CompanionCoreTestRunner)` → PASS, `git diff --check` → pass.
- read-state watcher 보정 검증: `EventFilter(allowedFileName:)` red/green으로 `projects.md`만 config refresh 대상이고 `read-state.json`은 무시됨을 확인했고, `(cd companion && swift build && swift run CompanionCoreTestRunner)` → PASS, `git diff --check`/`git diff --cached --check` → pass.
- 수동 visual QA: 미실행. 메뉴바 popover GUI 조작은 이 세션에서 직접 관찰하지 못했고, 대신 source invariant + `swift build`로 height/status/unread click wiring을 검증했다.
