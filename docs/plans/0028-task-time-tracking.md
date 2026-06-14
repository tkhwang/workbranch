# 0028 Companion task 시간 측정과 일/주/프로젝트 통계 계획

> **agentic worker 지침:** 실행 시 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용한다. 동작 변경 전에는 `superpowers:test-driven-development`(red → green → refactor)를 따른다. CLI 코드는 `src/workbranch/**`를 먼저 수정하고 `scripts/build-workbranch.sh`로 `bin/workbranch`를 재생성한다. `bin/workbranch`를 직접 수정하지 않는다. 새 모듈은 `scripts/workbranch-sources.txt`에 등록한다. 새/수정 bash 테스트는 `tests/run.sh`에 `run_test ...`로 등록한다. Companion 변경은 `companion/`에서 `swift build` + `swift run CompanionCoreTestRunner`로 검증한다. 검증 순서: syntax check → 관련 테스트 red/green → `./tests/run.sh` 전체 → companion build/test → `git diff --check`. 문서를 건드리면 EN/KO를 같은 PR에서 동기화한다.
>
> **시리즈 위치:** 0025에서 도입한 companion-local `read-state.json`(updatedAt 기반 unread)과 0026의 `todo` 라이프사이클 위에 얹는 **시간 측정/통계** slice다. 새로운 데이터 종류(활동 이력)를 도입하되, 기존 `list --json` 계약과 task brief 포맷은 변경하지 않는다.

**목표:** Companion이 task별 실제 작업 시간을 측정해 누적하고, 이를 일간·주간·프로젝트별로 집계해 보여준다. 추가로 Companion task row의 task name 옆에 task별 누적(오늘) 작업 시간을 inline으로 표시한다.

**아키텍처(핵심 결정):**
- task update(= `TASK-WORKBRANCH.md` 편집)는 **그대로 둔다.** 에이전트/CLI 프로토콜을 바꾸지 않는다.
- "편집 시각"은 새로 만들지 않는다. `updatedAt`(= brief mtime, `src/workbranch/lib/task-state.sh:25`)이 OS가 저장 후 남기는 권위 있는 편집 시각이다. 현재 `list --json` 계약은 초 단위 epoch이므로 v1 activity event도 관측된 초 단위 `updatedAt` 증가를 기준으로 한다.
- 없는 것은 **이력**뿐이다. Companion이 이미 FSEvents(0.25s latency + 2s debounce, `RootWatcher.swift` / `StateStore.swift:103`)로 각 root를 감시하다 brief 저장 후 ~2초 안에 `apply(results:)`(`StateStore.swift:135`)로 새 문서를 받는다. 그 시점에 직전 스냅샷 `previous[root]`(`:15`, `:141`에서 덮어쓰기 전)와 비교해 `updatedAt`이 증가한 task의 **활동 이벤트**를 append-only 로그에 기록한다.
- 이벤트의 시각은 관측시각이 아니라 `editedAt`(= `updatedAt`/mtime)을 권위값으로 쓴다. 같은 `(root, task, editedAt)`은 중복 기록하지 않으므로 빠른 연속 저장이 같은 초 안에 들어오거나 debounce 중 합쳐지면 하나의 활동 이벤트로 수렴할 수 있다.
- 저장소는 **DB 없이 append-only JSONL** 단일 파일(`~/.local/state/workbranch/activity.jsonl`)을 진실의 원천으로 둔다. SQLite는 이번 범위에서 도입하지 않는다(아래 "DB 미도입 결정" 참조).
- 집계(세션화 → 일/주/프로젝트)와 사람이 읽는 리포트는 **Companion UI 전용 기능**으로 제공한다. CLI `workbranch report`는 만들지 않는다. 세션화·롤업은 `CompanionCore`의 순수 Swift 로직 한곳에만 둔다.

**기술 스택:** 기존 portable Bash CLI의 `list --json` 계약은 그대로 소비하고, 새 구현은 append-only JSONL(`notifications.jsonl`·`read-state.json` 선례와 동일 계열), Swift/SwiftUI companion(`companion/Package.swift`)의 `CompanionCore`/`CompanionApp` 타겟과 `CompanionCoreTestRunner`에 둔다.

**제품 관점:** 사용자가 "어느 프로젝트의 어느 task에 얼마나 시간을 썼는지"를 일/주 단위로 회고할 수 있게 하고, 메뉴바를 열면 task별 오늘 작업 시간이 바로 보이게 한다. 에이전트 워크플로(직접 brief 편집)는 그대로 유지한다.

---

## 문제

1. **시간 이력이 없다.** 워크브랜치가 가진 유일한 시간값은 `updatedAt`(brief mtime, `task-state.sh:25`)뿐이고, 항상 "마지막 한 번"만 보인다. 시간에 따른 변화 이력이 없어 "이 task가 실제로 몇 시간 걸렸나", "오늘/이번 주 어디에 시간을 썼나"를 계산할 수 없다.
2. **status 변경 주체가 CLI가 아니다.** status/진행 상황은 에이전트(또는 사람)가 `TASK-WORKBRANCH.md`를 직접 편집해 바뀐다. 워크브랜치 명령을 거치지 않으므로 "명령 시점에 기록" 방식이 불가능하다. 변화를 **관측해서** 기록할 주체가 필요하다.
3. **표시 수단이 없다.** Companion은 status/`updatedAt`만 보여줄 뿐 task별 누적 작업 시간을 표시하지 못한다.

## 현재 repo 근거

- `src/workbranch/lib/task-state.sh:25` `task_updated_at`: brief mtime(`stat -f %m` / `stat -c %Y`)을 초 단위 epoch으로 반환한다. v1 activity event는 이 `updatedAt` 증가를 관측했을 때 기록한다.
- `src/workbranch/commands/list.sh:31,38` `cmd_list_json`이 task별 `updatedAt`(과 `status`/`progressDone`/`progressTotal`)을 emit한다. 글로벌은 `cmd_list_global_json`(`:160`)이 registry root별로 합친다.
- `src/workbranch/commands/noti.sh` + `task_noti_path`(`task-state.sh:7`) = `<task>/.workbranch/notifications.jsonl`: 이미 append-only JSONL 선례가 있다(append/list/clear, `json_escape`/`json_unescape`).
- `companion/Sources/CompanionApp/StateStore.swift:135` `apply(results:isBaseline:)`: 모든 refresh가 모이는 단일 funnel. `:15` `previous: [String: WorkbranchListDocument]`가 직전 스냅샷을 들고 있고 `:141`에서 새 문서로 덮어쓴다. 여기가 delta 계산의 유일한 지점.
- `companion/Sources/CompanionApp/RootWatcher.swift`: FSEvents 파일 이벤트(latency 0.25s)로 root 변경을 감지 → `noteFilesystemChange`(`StateStore.swift:103`) → 2s debounce → `refreshFromWatcher`. 즉 brief 저장 후 ~2초 내 새 `updatedAt` 관측. `:433` `startHeartbeat` 300s는 백업 폴링.
- `companion/Sources/CompanionCore/Models.swift:159` `StatusReadMarkers`(0025): `~/.config/workbranch-companion/read-state.json`에 schemaVersion + nested map을 load/write하는 companion-local 영속 상태의 선례. baseline-first-run 처리(`markBaselineRead`, `StateStore.swift:172`)도 동일 패턴으로 재사용한다.
- `companion/Sources/CompanionCore/Models.swift:35` `MenuRow`: 표현 전용 필드(예: `isStatusUnread`, `:52`)를 추가했던 선례. task row inline 표시용 `activeTimeText`를 같은 방식으로 추가.
- `companion/Sources/CompanionCore/MenuState.swift:220` `make(...)`가 row를 만들고 `:336` `taskRow`가 표시 문자열을 조립한다. 정렬은 `updatedAt` 내림차순(0025).
- `companion/Sources/CompanionApp/CLIClient.swift` + `StateStore.runExternal`(`:345`): companion이 이미 `workbranch`를 subprocess로 호출하는 경로가 있지만, 이번 slice의 report는 CLI subprocess가 아니라 CompanionCore 모델을 직접 소비한다.
- companion 테스트 진입점: `companion/Sources/CompanionCoreTestRunner/CompanionCoreTestRunnerTests.swift`.

## DB 미도입 결정 (확정됨)

- **이번 slice는 SQLite/DB를 도입하지 않는다.** 이 워크로드는 (a) 쓰기가 순수 append(수정/삭제 없음), (b) writer가 Companion 하나, (c) 데이터량이 작고(일 수백~수천 줄), (d) 읽기가 Companion UI에서 가끔 부르는 group-by 풀스캔이다. append-only JSONL이 이 패턴에 맞고, CompanionCore 순수 Swift 집계로 처리할 수 있으므로 `sqlite3` 의존성을 추가하지 않는다.
- **JSONL을 진실의 원천으로 고정한다.** 향후 (1) 풍부한 ad-hoc 쿼리, (2) 수년치 대용량 빠른 슬라이싱, (3) Companion 실시간 집계 성능, (4) mutable 레코드 중 하나가 실제로 필요해지면, 그때 **JSONL에서 파생되는 SQLite 캐시/인덱스**(권위는 여전히 JSONL)를 별도 plan으로 추가한다. 이번 범위 밖.

## 결정 사항 (확정됨)

1. **기록 주체/시점:** Companion `apply(results:)`에서 `previous`(갱신 전)와 새 문서를 diff해 관측된 초 단위 `updatedAt`이 증가한 task만 이벤트로 append한다. 첫(baseline) refresh는 세션 기점만 잡고 과거를 소급 생성하지 않는다.
2. **이벤트 시각:** `editedAt = updatedAt`(mtime)을 모든 계산의 기준으로 쓴다. `observedAt`(companion이 본 시각)은 진단용으로만 같이 남기고 계산에는 쓰지 않는다.
3. **저장 위치:** `~/.local/state/workbranch/activity.jsonl` (XDG state). companion-local read-state(`~/.config/workbranch-companion/`)와는 분리한다. 사람이 편집하는 config가 아니라 기계가 누적하는 상태이고, repo/task 삭제 뒤에도 회고용 이력을 보존해야 하기 때문이다.
4. **"걸린 시간" 정의:** 활동 세션 합(active-session sum). 정렬된 `editedAt` 사이 간격이 **idle gap(기본 25분)** 이내면 같은 세션, 세션 길이 = `last - first` + **lead pad(기본 5분)**. task 총 작업 시간 = 세션 길이 합. 각 이벤트에 `status`를 실어 두어 status별 분해는 후속(Slice D)에서 무비용에 가깝게 추가한다.
5. **집계/표시 로직 단일화:** 세션화·롤업은 `CompanionCore` 순수 Swift 로직에만 구현한다. Companion task row inline label과 일/주/프로젝트 리포트 UI가 같은 `ActivityReport` 모델을 소비한다. CLI `workbranch report`는 만들지 않는다.
6. **보존/복구:** activity log는 repo/task가 사라진 뒤에도 회고용 이력이므로 v1에서 삭제·압축·prune 명령을 제공하지 않는다. `workbranch prune`은 task workspace 정리 명령이며 activity log를 건드리지 않는다. 깨진 줄은 Companion report 로직에서 skip하고 전체를 깨뜨리지 않는다. append는 단일 writer + `O_APPEND`로 원자성을 가정한다(JSON 한 줄 < 4KB).

## 결정 게이트 결과

- [x] **이벤트는 관측된 초 단위 `updatedAt` 증가 시에만, 시각은 `editedAt=updatedAt`으로 기록한다.**
  - Impact: 시간 계산의 정확성/결정성, 폴링 cadence 의존 여부, 기존 `list --json` 계약 유지.
  - Current evidence: `task_updated_at`은 `stat -f %m`/`stat -c %Y`로 epoch seconds를 반환하고, Companion watcher는 약 2초 debounce 뒤 refresh한다. `apply`에 `previous`가 있어 delta 계산 가능하다.
  - Resolved: v1은 기존 `list --json.updatedAt` 계약을 유지한다. 관측된 초 단위 `updatedAt` 증가마다 최대 1개 이벤트를 기록하고, 같은 `(root, task, editedAt)`은 중복 기록하지 않는다. 빠른 연속 저장은 하나의 이벤트로 합쳐질 수 있음을 문서화한다.
  - Rejected: 고해상도 mtime 또는 별도 edit sequence 도입. 이유: `list --json`/task state 계약을 넓히고, 이번 slice의 Companion-local 시간 추적 범위를 벗어난다.

- [x] **저장소는 DB 없이 단일 append-only JSONL로 한다.**
  - Impact: 의존성/이식성, 향후 마이그레이션 비용.
  - Current evidence: `notifications.jsonl` 선례, activity log writer는 Companion 하나, 집계는 CompanionCore 순수 Swift로 충분하다.
  - Resolved: JSONL을 진실의 원천으로 고정. SQLite는 트리거 조건부 파생 캐시로 후속.
  - Rejected: 처음부터 SQLite. 이유: 새 런타임 의존성/마이그레이션/캐시 무효화 복잡도가 현 데이터량과 v1 요구에 비해 크다.

- [x] **세션화 파라미터는 상수로 시작하고 config 노출은 후속으로 둔다.**
  - Impact: "걸린 시간" 정의의 사용자 조정 가능성.
  - Current evidence: gap/pad는 결과를 좌우하지만 합리적 기본값(25/5분)이 있다.
  - Resolved: v1은 25분/5분 상수. 필요 시 `.workbranch.config` 또는 companion config 키로 노출하는 후속 plan.

- [x] **리포트는 Companion UI 전용으로 제공한다.**
  - Impact: public CLI/API surface, 문서 범위, 테스트 범위, 세션 로직 소유 위치.
  - Current evidence: activity log writer는 Companion이고, 현재 제품 요구는 Companion task row inline 시간과 Companion 회고 표시다. CLI에 `report` 명령은 없다.
  - Resolved: CLI `workbranch report`는 만들지 않는다. `CompanionCore`의 `ActivityReport` 순수 Swift 모델이 activity log parse/sessionize/rollup을 담당하고, task row inline label과 report UI가 같은 모델을 소비한다.
  - Rejected: CLI `workbranch report --json`을 public command로 추가. 이유: Bash command/API/docs/test surface가 불필요하게 생기고, Companion 기능을 위해 CLI public contract를 늘리게 된다.

- [x] **activity log는 v1에서 삭제/압축하지 않는다.**
  - Impact: 회고 이력 보존, 기존 `workbranch prune` 의미와의 충돌 방지, Companion append와 CLI replace 간 동시성 위험 제거.
  - Current evidence: 기존 `workbranch prune`은 clean task workspace 정리 명령이고, activity log는 `~/.local/state/workbranch/activity.jsonl` 글로벌 이력이다.
  - Resolved: activity log 삭제/압축 명령은 도입하지 않는다. repo/task가 사라져도 과거 activity log는 보존한다. Companion report 로직은 로그를 읽기만 하며 깨진 줄만 skip한다.
  - Rejected: `report --prune <date>`로 오래된 줄 삭제. 이유: 회고 이력 손실, 기존 prune 용어와 혼동, append 중 replace에 따른 유실 위험.

- [x] **새 activity/report 파일은 기존 CompanionCore/CompanionApp 경계에 맞춰 배치한다.**
  - Impact: 새 파일/폴더 배치, 테스트 경계, UI surface 범위.
  - Current evidence: 순수 모델과 테스트 대상은 `companion/Sources/CompanionCore`, 앱 I/O와 SwiftUI view는 `companion/Sources/CompanionApp` 아래에 두는 현재 구조가 있다.
  - Resolved: `ActivityEvent.swift`와 `ActivityReport.swift`는 `CompanionCore`에 둔다. `ActivityRecorder.swift`와 `ActivityReportView.swift`는 `CompanionApp`에 둔다. Report UI는 별도 window가 아니라 Companion popover footer의 Report icon으로 여는 별도 view로 추가한다. Footer 왼쪽 navigation은 Home(main view), Report, Setting 순서다. 기본 main view에는 report block을 직접 표시하지 않는다.
  - Rejected: activity/report 전체를 `CompanionApp`에 두거나 별도 window/screen을 만든다. 이유: 순수 로직 테스트 경계가 흐려지고 macOS window 상태 관리까지 slice가 넓어진다.

## 용어 계약

- **Plan**: `TASK-WORKBRANCH.md`의 `plan:` 값. 하나의 workbranch task workspace 안에서 Step들을 묶는 구체적인 상위 작업 계획 이름이다. Activity report의 Today 상세는 이 Plan 이름을 우선 표시한다.
- **Step**: Plan을 구성하는 Markdown checklist 항목(`- [ ]`/`- [x]`). 기존 JSON 호환 필드명(`items`, `currentItem`)은 유지하지만, 사용자-facing 문서와 generated guidance에서는 Step이라고 부른다.
- **Task workspace**: workbranch가 만든 `<task>` 디렉터리/branch 작업 공간이다. Checklist 항목을 task라고 부르지 않는다.

## public contract

### 활동 로그 `~/.local/state/workbranch/activity.jsonl`
- 한 줄 = 한 이벤트(JSON object). 필드:
  ```json
  {"v":1,"editedAt":1718369995,"observedAt":1718370001,"root":"/abs/project/root","project":"workbranch","task":"feat-x","planTitle":"Companion activity time tracking refinement","status":"in-progress","progressDone":3,"progressTotal":8}
  ```
- `v`: schemaVersion(1). `editedAt`/`observedAt`: epoch seconds. `editedAt`이 계산 기준.
- append-only. 같은 `(root,task,editedAt)`는 중복 기록하지 않는다. 빠른 연속 저장이 같은 초 안에 들어오거나 Companion debounce 중 합쳐지면 하나의 이벤트로 기록될 수 있다.

### Companion activity report model
- CLI `workbranch report` 명령은 없다. 리포트는 Companion UI 전용 기능이다.
- `CompanionCore` 내부 모델 shape(테스트 기준):
  ```json
  {"scope":"today","generatedAt":1718370005,
   "projects":[{"project":"workbranch","root":"/abs/root","totalSeconds":4980,
     "tasks":[{"task":"feat-x","planTitle":"Companion activity time tracking refinement","seconds":4980,"sessions":2,"lastEditedAt":1718369995}]}],
   "totals":{"seconds":4980}}
  ```
- 세션화: idle gap 25분, lead pad 5분(상수). 자정을 걸치는 세션은 날짜 버킷별로 분할.
- Companion report 로직은 activity log를 읽기만 한다. v1에는 activity log 삭제/압축 옵션을 두지 않는다.

### 변경하지 않는 것
- 기존 `workbranch list --json` 필드 의미와 task brief(`TASK-WORKBRANCH.md`) 포맷. `planTitle`은 `plan:`을 전달하기 위한 additive 필드다.
- 기존 `noti`/`read-state.json`/`notifications.jsonl` 의미.

## 파일 구조

```text
# Companion
companion/Sources/CompanionCore/ActivityEvent.swift   # 이벤트 모델 + diff(previous,next)->[event]
companion/Sources/CompanionCore/ActivityReport.swift  # activity log parse + 세션화 + 일/주/프로젝트 rollup 순수 로직
companion/Sources/CompanionApp/ActivityRecorder.swift # JSONL append/read I/O (CompanionApp 측 파일 접근)
companion/Sources/CompanionApp/StateStore.swift       # apply()에서 diff→append, ActivityReport→activeTime/report state
companion/Sources/CompanionCore/Models.swift          # MenuRow.activeTimeText (표현 전용)
companion/Sources/CompanionCore/MenuState.swift       # taskRow에 activeTimeText 주입
companion/Sources/CompanionApp/Views/RowView.swift    # task row inline active-time label 렌더
companion/Sources/CompanionApp/Views/ActivityReportView.swift # footer Report icon으로 여는 popover report view UI
companion/Sources/CompanionCoreTestRunner/CompanionCoreTestRunnerTests.swift  # diff/baseline/세션화/포맷 테스트

# 문서
README.md, README.ko.md                # Companion 시간 추적 기능 소개
companion/README.md                    # activity log/report UI 동작과 보존 정책
docs/architecture.md                   # 활동 로그 데이터 경계 한 단락
```

## 구현 작업 (TDD: 먼저 빨갛게)

> 각 Slice는 독립 PR 가능. 권장 순서 A → B → C(데이터 먼저 쌓고 표시를 얹음). 이번 plan은 CLI `workbranch report`를 만들지 않고 Companion 중심으로 구현한다.

### Slice A — 활동 이벤트 기록 (Companion)
- **A1 `ActivityEvent` + diff (CompanionCore, 순수 함수):** `ActivityEvent.diff(previous: [String: WorkbranchListDocument], next: [WorkbranchListDocument], observedAt: Int, isBaseline: Bool) -> [ActivityEvent]`. `next`의 각 task에 대해 `previous[root]`의 동일 task `updatedAt`보다 크면(또는 previous에 없으면) 이벤트 생성. baseline(첫 관측)은 이벤트를 만들지 않고 기준선만 잡는다.
  - 테스트(red→green): updatedAt 증가 시 1건, 동일 updatedAt 반복 시 0건, 신규 task 첫 관측은 baseline이면 0건/비-baseline이면 1건, 다른 root/task가 섞이지 않음.
- **A2 `ActivityRecorder` append (CompanionApp):** `~/.local/state/workbranch/activity.jsonl`에 디렉터리 생성 후 한 줄씩 append. 쓰기 실패는 `statusMessage`로만 surface하고 앱을 깨뜨리지 않는다.
- **A3 `apply()` 연결:** `previous`를 덮어쓰기 **전에** `ActivityEvent.diff`를 호출해 이벤트를 append. baseline 처리는 기존 `pendingBaselineStatusReadRoots` 패턴과 일관되게(root별 첫 성공 refresh는 baseline) 처리.
  - 테스트: source-level/Runner 테스트로 baseline 첫 적용은 append 0건, 이후 updatedAt 증가 적용은 append 1건.
- Acceptance: brief 저장 후 Companion이 새 초 단위 `updatedAt`을 관측하면 `activity.jsonl`에 `editedAt=updatedAt`인 줄이 최대 1건 추가되고, 변화 없는 refresh나 같은 `(root,task,editedAt)` 반복 관측은 줄을 추가하지 않는다.

### Slice B — CompanionCore 집계 + report model
- **B1 `ActivityReport` log parser (CompanionCore):** `ActivityEvent` JSONL 라인을 파싱해 깨진 줄은 skip하고, activity log가 없거나 비어 있으면 empty report를 반환한다. I/O는 `ActivityRecorder`/StateStore 쪽에서 담당하고, parser/sessionizer는 순수 함수로 유지한다.
- **B2 세션화 + 집계 (`ActivityReport.swift`):** task별 `editedAt` 정렬 → idle gap 25분으로 세션 분리 → 세션 길이(+lead pad 5분) 합. 날짜/프로젝트 버킷. 자정 분할 처리.
  - 테스트(red→green): 단일 이벤트 → pad 만큼, gap 이내 연속 → 한 세션, gap 초과 → 두 세션, 자정 걸침 → 두 날짜로 분할, 빈/없는 로그 → 0, malformed line skip.
- **B3 report scope model:** `today`/`week`/`all`, project filter, generatedAt 주입을 `ActivityReport` API로 제공한다. CLI flag나 JSON stdout은 만들지 않는다.
  - 테스트: 합성 activity events로 today/week/month와 project filter 결과를 assert.
- Acceptance: 합성 로그에 대해 CompanionCore가 프로젝트×task 시간을, 주간 롤업을, task별 seconds/session count를 결정적으로 계산한다.

### Slice C — Companion task row inline label
- **C1 `MenuRow.activeTimeText` (CompanionCore):** 표현 전용 필드 추가(`isStatusUnread` 선례). `MenuState.make`에 `activeSecondsByTask: [String(root\0task): Int]` 같은 맵을 받아 `taskRow`에서 포맷(`1h23m`, 0이면 빈 문자열).
  - 테스트: 초→라벨 포맷, 맵 없으면 빈 label, 정렬/카운트 불변.
- **C2 `StateStore` 연동:** refresh 후 activity log를 읽어 `ActivityReport(scope: .today)`를 계산하고 task별 초를 `MenuState.make`에 전달한다. 읽기/파싱 실패 시 inline label과 report panel만 비고 나머지 상태 표시는 정상.
- **C3 `RowView`:** task row의 task name 옆에 `activeTimeText`를 inline 렌더. 색/정렬은 기존 터미널 톤 유지, 0025의 status line 단순화와 충돌하지 않게.
- **C4 `ActivityReportView`:** Companion popover footer의 Report icon으로 오늘/이번 주/이번 달 회고용 report view를 연다. Footer 왼쪽 icon은 Home(main view), Report, Setting 순서로 둔다. 기본 main view에는 report block을 직접 표시하지 않고 task rows만 유지한다. 같은 `ActivityReport` 모델을 소비하고, Today는 `planTitle`이 있으면 project > planTitle 단위로 표시하고 task workspace도 함께 보존한다. `planTitle`이 없으면 project > task workspace 단위로 최신 status/progress/session/last edit를 자세히 표시한다. data 없음/읽기 실패 상태를 명확히 표시한다. 별도 window/screen은 만들지 않는다.
- Acceptance: 메뉴바를 열면 작업한 task 행의 task name 옆에 오늘 작업 시간이 inline으로 표시되고, footer Report icon을 누르면 report UI에서 오늘/이번 주/project별 시간이 보인다. 데이터가 없으면 빈/0 상태이며, activity log 읽기 실패에도 기존 status monitor는 정상 동작한다.

### Slice D — 후속(이번 PR 범위 밖, 별도 plan 후보)
- 이벤트 `status`를 이용한 status별 머문 시간 분해(planning/in-progress/review/**blocked**).
- `<task>/<repo>` git commit 타임스탬프를 활동 신호로 추가(brief 미편집 코딩 시간 보강).
- 세션 gap/pad config 노출, Companion 시각화 대시보드 뷰.
- 트리거 충족 시 JSONL 파생 SQLite 캐시.

## 최종 검증

```bash
# Companion
(cd companion && swift build && swift run CompanionCoreTestRunner)
git diff --check
```

- 수동 확인: 새 task에서 brief 저장 → `~/.local/state/workbranch/activity.jsonl`에 줄 추가 → main view task row inline label과 footer Report view에 시간 표시.
- 결정성 확인: 합성 로그로 세션화 결과가 입력에만 의존하고 실행 시각/폴링과 무관함을 테스트로 잠근다.

## 롤아웃 / 호환성

- **비파괴 추가.** `list --json`/brief 포맷/기존 noti·read-state 의미 불변. 새로 생기는 것은 활동 로그(`activity.jsonl`)와 Companion 시간 표시/report UI뿐이다. CLI `workbranch report`는 추가하지 않는다.
- companion이 꺼져 있던 동안의 편집이나 같은 초/같은 debounce window 안의 빠른 연속 저장은 중간 샘플을 놓쳐 세션 해상도가 떨어질 수 있다(일/주 합계엔 대체로 무해). 문서/PR에 명시.
- mtime 기반이라 brief를 안 건드린 순수 코딩 시간은 v1에서 잡지 않는다(Slice D에서 git 신호로 보강).
- 활동 로그는 단일 writer(Companion) append를 가정한다. 향후 CLI heartbeat 등 두 번째 writer를 추가하면 append 원자성/락을 재검토한다.

## 미해결 / 후속

- status별 분해, git commit 신호, gap/pad config 노출, Companion 시각화, SQLite 파생 캐시는 모두 Slice D/별도 plan.
- 활동 로그 보존정책(자동 로테이션/압축/삭제)은 v1에서 제공하지 않는다. 로그 무한 증가가 실제 문제로 드러나면, 이력 보존을 기본값으로 둔 archive/rotation 방식을 별도 plan에서 검토한다.


## 실행 결과

- [x] Slice A — `ActivityEvent` diff/JSONL round trip과 `ActivityRecorder` append/read I/O를 추가했다. `StateStore.apply`는 `previous`를 덮어쓰기 전에 activity event를 계산하고 append한다.
- [x] Slice B — `CompanionCore.ActivityReport`가 activity JSONL parse, malformed line skip, idle gap/lead pad sessionization, today/week/month scope, project filter, task별 seconds/session count, 최신 status/progress를 계산한다.
- [x] Slice C — `MenuRow.activeTimeText`, `RowView` inline active-time label, `StateStore`의 today/week/month activity report, footer Home/Report/Setting navigation과 Report icon으로 여는 `ActivityReportView`를 추가했다.
- [x] 문서 — README EN/KO, `companion/README.md`, `docs/architecture.md`에 Companion-local activity log/report UI와 보존 정책을 반영했다.

### 검증 기록

- `(cd companion && swift run CompanionCoreTestRunner)` → PASS (Slice A/B/C 테스트 및 source-invariant 포함).
- `(cd companion && swift build)` → PASS.
- `git diff --check` → PASS.
- 새 untracked Swift/plan 파일 대상 `git diff --no-index --check /dev/null <file>` → PASS.

### 수동/시각 검증 메모

- 이 변경은 native macOS menu bar popover UI다. 현재 자동화 가능한 검증은 Swift build와 `CompanionCoreTestRunner` source-invariant로 수행했다. 실제 메뉴바 popover를 여는 수동 시각 QA는 release/manual QA 단계에서 확인한다.
