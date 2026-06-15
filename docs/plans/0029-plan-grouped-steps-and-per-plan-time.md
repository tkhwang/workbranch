# 0029 Task 안의 Plan 단위 Step 묶음과 Plan별 시간 측정 계획

> **agentic worker 지침:** 실행 시 `superpowers:executing-plans` 또는 `superpowers:subagent-driven-development`를 사용한다. 동작 변경 전에는 `superpowers:test-driven-development`(red → green → refactor)를 따른다. CLI 코드는 `src/workbranch/**`를 먼저 수정하고 `scripts/build-workbranch.sh`로 `bin/workbranch`를 재생성한다. `bin/workbranch`를 직접 수정하지 않는다. 새 모듈을 만들면 `scripts/workbranch-sources.txt`에 등록한다. 새/수정 bash 테스트는 `tests/run.sh`에 `run_test ...`로 등록한다. Companion 변경은 `companion/`에서 `swift build` + `swift run CompanionCoreTestRunner`로 검증한다. 검증 순서: `bash -n` syntax check → 관련 테스트 red/green → `./tests/run.sh` 전체 → companion build/test → `git diff --check`. 문서를 건드리면 EN/KO를 같은 PR에서 동기화한다.
>
> **시리즈 위치:** 0021(task progress/lifecycle), 0026(`todo` lifecycle + `plan:` 도입), 0028(task별 시간 측정 + 일/주/프로젝트 통계) 위에 얹는다. 0028이 "task별" 시간을 측정했다면, 0029는 측정·표시 단위를 **task 안의 Plan**으로 한 단계 더 쪼갠다. 기존 `list --json` 계약과 `activity.jsonl`은 **additive**로만 확장한다(schemaVersion 1 유지, 신규 필드는 모두 optional + 하위호환 fallback).

**목표:** 하나의 `<task>` 안에서 진행을 **Plan 단위로 묶고**, 각 Plan 아래에 그 Plan의 **Step**들을 구분해 보여준다. 두 곳에 동시에 반영한다.
1. **라이브 모니터(status monitor / `RowView`)** — 지금은 task 아래에 Step이 flat하게만 나열된다. 이를 `Plan → Step` 트리로 묶어 표시한다.
2. **Activity report 탭** — 지금은 task 단위 누적 시간만 집계된다. 이를 **Plan 단위 누적 시간**으로 분해해 "이 task의 어떤 Plan에 얼마나 시간을 썼는지"를 보여준다.

**아키텍처(핵심 결정):**
- 진실의 원천은 여전히 `<task>/TASK-WORKBRANCH.md` 한 파일이다. 에이전트/CLI 편집 프로토콜은 바꾸지 않는다(0028과 동일 원칙).
- **Plan은 `## Plan: <name>` 마크다운 헤딩 섹션으로 표현**한다(사용자 확정). 각 Plan 헤딩 아래의 `- [ ]`/`- [x]` 체크리스트가 그 Plan의 Step이다. Step의 하위 Step은 기존처럼 2칸 들여쓰기(`depth`)로 표현한다.
- **Plan의 status/진행률은 파생값**이다. 별도 `status:`를 Plan마다 두지 않고, 그 Plan의 Step done/total로 todo|in-progress|done을 계산한다(task-level 파생 로직 재사용).
- 시간은 **(task, plan) 단위**로 측정한다(사용자 확정: "plan 단위로 얼마나 시간이 되었는지"). 한 task의 모든 repo는 같은 brief 한 장을 공유하므로 **repo별 시간 신호는 존재하지 않는다**(아래 "미해결/후속" 참조). report는 task의 repo/branch를 맥락으로 보여주되, 시간은 Plan에 귀속한다.
- 집계(세션화 → 일/주)와 사람이 읽는 리포트는 0028처럼 **Companion `CompanionCore` 순수 Swift 로직**에만 둔다. CLI `report` 명령은 만들지 않는다.

**제품 관점:** 사용자가 task를 열었을 때 "이 task는 어떤 Plan들로 구성됐고, 각 Plan이 어디까지 진행됐고, 어디에 시간을 썼는지"를 한눈에 회고할 수 있게 한다. 에이전트 워크플로(직접 brief 편집)는 그대로 유지한다.

---

## 문제

1. **Plan 구분이 없다.** 현재 task는 `plan:` frontmatter **단일 문자열 1개**(`task-state.sh:74` `task_plan_title`)와 **flat 체크리스트**(`task-state.sh:128` `task_checklist_items_json`)만 가진다. 즉 "plan"은 task 전체에 붙는 라벨일 뿐, 여러 Plan으로 Step을 묶을 방법이 없다. 그래서 모니터에 Step은 보이지만 Plan 묶음이 안 보인다(`RowView.swift:134` `statusDetailsBlock`이 `row.checklistItems`를 depth만으로 평면 렌더).
2. **시간이 task 단위로만 집계된다.** `ActivityReport.make`(`ActivityReport.swift:91`)는 `(root, project, task)`로 grouping하고, `ActivityReportTask`는 `planTitle` **한 개**만 라벨로 들고 있다(`ActivityReport.swift:18`). Plan별로 시간을 나눌 수 없다.
3. **이벤트가 Plan을 모른다.** `ActivityEvent`(`ActivityEvent.swift:3`)는 task 스냅샷당 `planTitle` 1개만 기록한다. 어떤 Plan이 바뀌어서 편집이 일어났는지 구분 정보가 없다.

## 현재 repo 근거

- brief 포맷/기본 템플릿: `src/workbranch/lib/task-state.sh:162` `write_default_task_brief`(`plan: $task` + flat 체크리스트), `:199` `write_task_agent_guidance`("keep `plan:` set to the concrete Plan name that groups the Steps").
- brief 파싱: `task_checklist_counts:38`, `task_explicit_status:51`, `task_plan_title:74`, `task_current_item:111`, `task_checklist_items_json:128`. 모두 `in_code` 펜스만 건너뛰고 파일 전체를 훑는다. `## Notes`/`## 메모`(`:179`, `:193`)는 `- [ ]` 마커가 아니라 매칭되지 않는다.
- JSON 방출: `src/workbranch/commands/list.sh:1` `cmd_list_json` — task별 `memoTitle`/`planTitle`/`status`/`progressDone`/`progressTotal`/`currentItem`/`items`/`repos`.
- Swift 모델: `companion/Sources/CompanionCore/Models.swift:79` `WorkbranchTask`(`planTitle`, `items:[WorkbranchChecklistItem]`), `:151` `WorkbranchChecklistItem`(`text`,`checked`,`depth`).
- 라이브 렌더: `companion/Sources/CompanionApp/Views/RowView.swift:134` `statusDetailsBlock`, `:160` `statusItemLine`. 매핑: `companion/Sources/CompanionCore/MenuState.swift:341` `taskRow`(→ `checklistItems: task.items`).
- 시간 측정 파이프라인: `ActivityEvent.swift:66` `diff`(task별 1 이벤트), `ActivityEvent.swift:119` `activityEventKey`(steps 포함 dedup 키), `ActivityReport.swift:91` `make`(세션화/롤업), `ActivityReport.swift:201` `rollupSessions`(idle gap 25분, lead pad 5분), `ActivityReportView.swift:50` `projectBlock`.
- 기록기: `companion/Sources/CompanionApp/ActivityRecorder.swift`(append-only JSONL `~/.local/state/workbranch/activity.jsonl`).
- 테스트: `tests/cases/list-json.sh`(python으로 JSON shape 검증), `companion/Sources/CompanionCoreTestRunner/CompanionCoreTestRunnerTests.swift`.

## 결정 사항 (확정됨)

1. **Plan 표현 = `## Plan: <name>` 헤딩 섹션.**(사용자 선택) 각 섹션 아래 체크리스트가 그 Plan의 Step.
2. **시간 측정 granularity = Plan 단위.**(사용자 선택) (task, plan)별 세션 롤업.
3. **진행 방식 = 계획 우선.**(사용자 선택) 본 문서 승인 후 Bash + Swift 구현.
4. **Plan status/진행률은 파생.** Plan마다 `status:`를 두지 않는다. Step done/total로 계산.
5. **하위호환은 fallback으로.** schemaVersion 1 유지. `## Plan:` 헤딩이 없는 기존 brief는 **암묵 단일 Plan**(이름 = `plan:` frontmatter 값 또는 task 이름)으로 취급. 신규 JSON 필드/이벤트 필드는 모두 optional + 기본값.
6. **CLI `report` 명령은 만들지 않는다.** 0028 결정 유지.
7. **Plan identity = `(title, occurrenceIndex)`.** 같은 task 안에 동명 `## Plan:`이 반복될 수 있으므로, Plan 표시 이름(`title`)과 안정 식별자(`index`, 정규화된 plans 배열 내 0-based 등장 순서)를 분리한다. diff/dedup/grouping은 `(task, title, index)`를 사용한다.

## 결정 게이트 결과

- [x] **동명 Plan identity는 `(title, occurrenceIndex)`로 처리한다.**
  - Impact: Plan별 activity event dedup, activity report grouping, 동명 Plan 렌더 안정성.
  - Current evidence: `ActivityEvent.diff`는 현재 task 단위 event key만 갖고 있고, 0029가 Plan별 event를 추가하면 title-only grouping은 동명 Plan에서 충돌한다.
  - Resolved: 정규화된 `plans` 배열의 0-based `index`를 Plan identity 일부로 둔다. Public JSON `plans[]`에는 optional additive `index`를 싣고, activity log에는 optional `planIndex`를 싣는다. 구버전/legacy 이벤트에서 `planIndex`가 없으면 `0`으로 디코드한다.
  - Rejected: task 안 Plan title 중복 금지. 이유: Markdown 직접 편집 workflow를 불필요하게 제약하고, 같은 이름의 반복 phase를 사용자가 만들 수 있다.

## 용어 계약

- **Plan:** task brief 안에서 `## Plan: <name>` 헤딩으로 시작하는 Step 묶음. 한 task는 0개 이상의 Plan을 가진다(0개 = 암묵 단일 Plan으로 정규화).
- **Step:** Plan 섹션 안의 `- [ ]`/`- [x]` 체크리스트 항목. `depth`(2칸/level)로 하위 Step 표현.
- **암묵 Plan(implicit plan):** `## Plan:` 헤딩이 하나도 없을 때, 또는 첫 헤딩 이전에 등장한 Step들을 담는 단일 Plan. 이름은 `plan:` frontmatter → 없으면 task 이름.
- **Plan identity:** `(title, index)` pair. `index`는 정규화된 `plans` 배열 안의 0-based 등장 순서이며, 같은 task 안 동명 Plan 충돌을 막기 위해 diff/dedup/grouping에 포함한다.
- **Plan key(시간 dedup용):** `title  index  status  progressDone  progressTotal  currentItem  stepKey`.

## public contract

### task brief 포맷 (신규 권장 형태)

```text
# feat-task1

status: in-progress

## Plan: Backend confirmation
- [x] Backend confirmation gate reached
- [x] Map consumers of new BOM id contract

## Plan: Frontend compatibility
- [x] Frontend compatibility orientation
  - [x] Confirm frontend package sync exists
- [ ] Frontend targeted verification

## Notes
-
```

파싱 규칙:
- `## Plan:` (대소문자 무시, 콜론 뒤 이름) 헤딩이 새 Plan 섹션을 연다. 섹션은 다음 `## Plan:` 또는 **다른 `##`/`#` 헤딩**(예: `## Notes`, `## 메모`) 또는 EOF에서 끝난다.
- 코드펜스(``` ``` ```) 안은 기존처럼 무시.
- `## Plan:` 헤딩이 하나도 없으면: 파일의 모든 Step을 **암묵 단일 Plan**으로 묶는다(= 현재 동작과 동일 결과).
- 첫 `## Plan:` 이전에 등장한 Step이 있으면: 그것들도 암묵 Plan으로 묶어 plans 배열 맨 앞에 둔다(데이터 유실 금지).
- `## Notes`/`## 메모` 등 Plan이 아닌 섹션의 `-` 항목은 Step이 아니다(현재도 매칭 안 됨, 유지).

### `workbranch list --json` (additive, schemaVersion 1 유지)

task 객체에 `plans` 배열을 추가한다. 기존 top-level 필드(`planTitle`,`status`,`progressDone`,`progressTotal`,`currentItem`,`items`)는 **task 집계값으로 그대로 유지**(구버전 companion 호환). `planTitle`은 active Plan(첫 미완료 Plan, 없으면 마지막) 제목으로 채운다.

```jsonc
{
  "name": "feat-task1",
  "planTitle": "Frontend compatibility",   // active plan (호환 라벨)
  "status": "in-progress",                  // task 집계 (기존)
  "progressDone": 3, "progressTotal": 4,    // task 집계 (기존)
  "items": [ /* task 전체 flat steps (기존, 호환) */ ],
  "plans": [                                 // 신규
    {
      "title": "Backend confirmation",
      "index": 0,
      "status": "done",
      "progressDone": 2, "progressTotal": 2,
      "currentItem": "",
      "items": [ {"text":"...","checked":true,"depth":0}, ... ]
    },
    {
      "title": "Frontend compatibility",
      "index": 1,
      "status": "in-progress",
      "progressDone": 1, "progressTotal": 2,
      "currentItem": "Frontend targeted verification",
      "items": [ ... ]
    }
  ],
  "repos": [ ... ]
}
```

암묵 단일 Plan일 때도 `plans`는 항상 길이 ≥ 1로 방출한다(소비자 단순화). Plan이 전혀 없고 Step도 없으면 `plans: []`.

### 활동 로그 `~/.local/state/workbranch/activity.jsonl`

`ActivityEvent`에 **optional `plan` 필드(plan title)**와 **optional `planIndex` 필드(0-based occurrence index)**를 추가한다(v 1 유지, `decodeIfPresent`). 한 번의 brief 저장에서 **key가 바뀐 Plan마다 1개 이벤트**를 방출한다(모두 같은 `editedAt`/mtime 공유). `plan`이 없는 구버전 줄은 `""`(단일 버킷)으로, `planIndex`가 없는 줄은 `0`으로 디코드.

```jsonc
{"v":1,"editedAt":1718000000,"observedAt":...,"root":"...","project":"...",
 "task":"feat-task1","plan":"Frontend compatibility","planIndex":1,"planTitle":"Frontend compatibility",
 "status":"in-progress","progressDone":1,"progressTotal":2}
```

`diff`는 `previous[root].tasks[name].plans`와 `next`의 plans를 `(task, plan title, plan index)`로 매칭해, plan key가 바뀐 Plan에 대해서만 이벤트를 만든다. 같은 `(root, task, plan, planIndex, editedAt)`은 중복 기록하지 않는다.

### Companion activity report model

- `ActivityReportPlan`(신규): `title`, `index`, `seconds`, `sessions`, `lastEditedAt`, `status`, `progressDone`, `progressTotal`.
- `ActivityReportTask`: 기존 필드 유지 + `plans: [ActivityReportPlan]` 추가.
- 롤업: `(root, project, task, plan, planIndex)`로 grouping해 plan별 `rollupSessions`(기존 idle-gap 알고리즘 재사용). **task.seconds는 기존 정의 유지**(task의 모든 이벤트 union 롤업) — plan들을 단순 합산하면 같은 세션이 여러 Plan에 잡혀 과대계상될 수 있으므로, task 합계는 union, plan 행은 plan별 독립 롤업으로 둔다. sum(plan.seconds) ≥ task.seconds 가 될 수 있음은 **의도된 성질**(아래 "미해결/후속"에 명시·표시).

### 변경하지 않는 것

- task 편집 프로토콜(에이전트가 brief 직접 편집), `updatedAt`=brief mtime 권위값(0028).
- schemaVersion(1 유지), 기존 top-level JSON 필드, `notifications.jsonl`/`read-state.json`.
- idle gap(25분)/lead pad(5분) 세션 파라미터.
- CLI human 출력(`cmd_list_local`), status/sync/doctor 등 다른 명령.

## 파일 구조 (touched)

```text
# CLI (Bash)
src/workbranch/lib/task-state.sh      # task_plans_json (신규), 암묵-Plan 정규화, active-plan 파생
src/workbranch/commands/list.sh       # cmd_list_json 에 "plans": 추가
src/workbranch/lib/task-state.sh      # write_default_task_brief / write_task_agent_guidance → ## Plan 템플릿
AGENTS.md, src/workbranch/.../AGENTS guidance, README(EN/KO)  # Plan 컨벤션 문서화

# Companion (Swift)
companion/Sources/CompanionCore/Models.swift          # WorkbranchPlan(title,index), WorkbranchTask.plans (+fallback)
companion/Sources/CompanionCore/ActivityEvent.swift   # plan 필드 + per-plan diff
companion/Sources/CompanionCore/ActivityReport.swift  # ActivityReportPlan, per-plan rollup
companion/Sources/CompanionCore/MenuState.swift       # MenuRow.plans 전달
companion/Sources/CompanionApp/Views/RowView.swift    # Plan→Step 트리 렌더
companion/Sources/CompanionApp/Views/ActivityReportView.swift  # plan별 시간 행

# Tests
tests/cases/list-json.sh                              # plans[] shape/암묵Plan/하위호환
companion/Sources/CompanionCoreTestRunner/CompanionCoreTestRunnerTests.swift  # 파싱/diff/rollup
```

## 구현 작업 (TDD: 먼저 빨갛게)

### Slice A — brief 파서: Plan 섹션 (CLI)
- red: `tests/cases/list-json.sh`에 (1) `## Plan:` 2개 → `plans` 길이 2, 각 plan의 `index`/`items`/`progressDone/Total`/파생 status, (2) 헤딩 없는 기존 brief → `plans` 길이 1(암묵), (3) 첫 헤딩 이전 Step도 보존되는 케이스, (4) 동명 Plan 2개가 같은 `title`이지만 다른 `index`로 보존되는 케이스를 추가.
- green: `task-state.sh`에 `task_plans_json`(섹션 분할 → 섹션별 items/counts/currentItem/파생 status 방출) 구현. `list.sh:cmd_list_json`에 `"plans":` 출력 추가. active-plan 파생으로 top-level `planTitle` 채움.
- 검증: `bash -n`, 해당 테스트 red→green, `./tests/run.sh`.

### Slice B — Swift 모델 + 하위호환 (CompanionCore)
- red: `CompanionCoreTestRunnerTests`에 (1) `plans` 포함 JSON 디코드, (2) `plans` 없는 구버전 JSON → `task.plans`가 `planTitle`+`items`로 합성된 단일 Plan, 테스트.
- green: `WorkbranchPlan` 추가, `WorkbranchTask`에 `plans` + `decodeIfPresent` fallback(`plans` 비면 1개 합성).
- 검증: `swift build` + `swift run CompanionCoreTestRunner`.

### Slice C — 라이브 모니터 Plan 묶음 (CompanionApp)
- `MenuState.taskRow`가 `task.plans`를 `MenuRow`로 전달. `RowView.statusDetailsBlock`을 `Plan 헤더(이름 · done/total · 파생 status) → 그 아래 Step들` 트리로 렌더. memo 라인은 유지. Plan이 1개면 헤더를 접거나 간결 표시(시각 노이즈 최소화).
- 검증: `swift build`. 시각 검증은 "실행 결과"에 캡처 메모.

### Slice D — Plan별 시간 이벤트 + 집계 (CompanionCore)
- red: 테스트에 (1) 두 Plan이 각각 다른 시각에 편집된 이벤트열 → plan별 seconds 분리, (2) `plan`/`planIndex` 없는 구버전 이벤트 → 단일 버킷(index 0), (3) task.seconds=union 유지 확인, (4) 같은 title의 두 Plan이 `planIndex`로 분리 집계됨을 추가.
- green: `ActivityEvent`에 `plan`/`planIndex` 추가 + `diff`를 per-plan 비교로 확장. `ActivityReportPlan` 추가, `make`에서 `(root,project,task)` 묶음 안에서 다시 `(plan,planIndex)`별 롤업. `ActivityRecorder`는 그대로(줄 단위 append).
- 검증: `swift run CompanionCoreTestRunner`.

### Slice E — Activity report 탭 Plan 행 (CompanionApp)
- `ActivityReportView`의 task 블록 아래에 plan별 `duration` 행(이름 · seconds · status done/total)을 렌더. Today는 plan 상세, Week/Month는 task 합계 위주(기존 `showsPlanDetails` 패턴 확장).
- 검증: `swift build`. 시각 검증 캡처.

### Slice F — 템플릿/문서 동기화
- `write_default_task_brief`를 `## Plan: <task>` 1개 섹션 + Step으로 갱신(EN/KO). `write_task_agent_guidance`와 `AGENTS.md`에 "Plan은 `## Plan:` 섹션으로 묶고, Step은 그 아래 체크리스트로 둔다" 규칙 추가. README EN/KO 동기화.
- 검증: `bash -n`, `./tests/run.sh`(템플릿 변화 반영), `git diff --check`.

## 최종 검증

```bash
# CLI
/bin/bash -n bin/workbranch install.sh tests/run.sh
scripts/build-workbranch.sh
./tests/run.sh
git diff --check
# Companion
cd companion && swift build && swift run CompanionCoreTestRunner
```

## 롤아웃 / 호환성

- 구버전 companion ↔ 신버전 CLI: companion이 `plans`를 모르면 무시하고 기존 `items`로 렌더(무해).
- 신버전 companion ↔ 구버전 CLI: `plans` 없으면 `planTitle`+`items`로 단일 Plan 합성.
- 기존 `activity.jsonl`: `plan` 없는 줄은 `""` 버킷 → 단일 Plan으로 자연 표시. 마이그레이션 불필요.
- 기존 brief 파일: `## Plan:` 없어도 암묵 단일 Plan으로 그대로 동작. 사용자가 점진적으로 `## Plan:` 도입 가능.

## 미해결 / 후속

- **repo별 시간은 범위 밖.** 한 task의 모든 repo가 brief 한 장을 공유하므로 repo별 시간 신호가 없다. report는 repo/branch를 맥락으로만 보여준다. 진짜 repo별 시간이 필요하면 repo-local brief 또는 commit 기반 신호가 필요(별도 plan).
- **sum(plan.seconds) ≥ task.seconds** 가능(같은 세션이 여러 Plan에 걸칠 때). UI에 task 합계는 union임을 명확히(라벨/툴팁) 표시.
- Plan 이름 중복은 `(title, index)` identity로 처리한다. 다만 Plan 순서를 대규모로 재배치하면 과거 activity log의 index 의미가 바뀔 수 있으므로, Plan 순서 재배치/rename history 보정은 후속에서 검토한다.

## 실행 결과

- [x] Slice A — `TASK-WORKBRANCH.md`의 `## Plan:` 섹션을 정규화하는 Bash parser를 추가하고, `workbranch list --json`에 additive `plans[]`를 방출한다. 기존 flat `items`/`status`/`progressDone`/`progressTotal`/`currentItem`/`planTitle`은 같은 normalized Plan source에서 파생한다.
- [x] Slice B — `WorkbranchPlan(title,index,...)`와 `WorkbranchTask.plans`를 추가했다. 신버전 `plans[]` JSON을 디코드하고, 구버전 JSON은 `planTitle`+flat `items`/progress에서 단일 fallback Plan을 합성한다.
- [x] Slice C — Companion live monitor가 `MenuRow.plans`를 전달하고, `RowView`에서 여러 Plan을 `Plan header -> Step` 형태로 렌더한다. 단일 Plan은 기존처럼 checklist noise를 최소화한다.
- [x] Slice D — `ActivityEvent`에 optional `plan`/`planIndex`를 추가하고, diff/dedup/report grouping을 `(task, plan, planIndex)` 단위로 분리했다. `ActivityReportTask.seconds`는 task union rollup을 유지하고, `ActivityReportPlan`은 Plan별 독립 rollup을 제공한다.
- [x] Slice E — Activity report Today 상세에 task 아래 Plan별 duration/status 행을 렌더한다. Week/Month는 기존처럼 task 합계 위주로 유지한다.
- [x] Slice F — 기본 `TASK-WORKBRANCH.md` 템플릿, generated `AGENTS.md` guidance, README EN/KO, `docs/architecture.md`, `companion/README.md`를 `## Plan:` 섹션 계약과 `plans[]`/Plan별 activity report에 맞춰 동기화했다.

### 검증 기록

- `/bin/bash -n bin/workbranch install.sh tests/run.sh` → PASS.
- `scripts/build-workbranch.sh` → PASS, `bin/workbranch` regenerated and up to date.
- Targeted CLI tests → PASS:
  - `test_list_json_plan_sections_shape_and_aggregate`
  - `test_list_json_implicit_and_empty_plans`
  - `test_list_json_duplicate_plan_titles_keep_distinct_indexes`
  - `test_add_creates_task_brief_and_agent_guidance`
  - `test_add_agents_md_describes_status_update_protocol`
  - `test_preferred_language_generates_korean_task_guidance`
- `./tests/run.sh` → PASS, `Tests passed: 248`.
- `(cd companion && swift build)` → PASS.
- `(cd companion && swift run CompanionCoreTestRunner)` → PASS.
- `git diff --check` → PASS.
- `git diff --no-index --check /dev/null docs/plans/0029-plan-grouped-steps-and-per-plan-time.md` → PASS for the new untracked plan file.

### 수동/시각 검증 메모

- CLI matching surface는 generated `bin/workbranch`와 full `./tests/run.sh`로 검증했다.
- Companion native menu bar popover의 실제 macOS 시각 캡처는 이 자동 실행에서 수행하지 않았다. 대신 `swift build`로 App target을 컴파일하고, `CompanionCoreTestRunner`의 model/activity/report/source-invariant tests로 Plan 렌더 경로와 Activity report path를 검증했다.
