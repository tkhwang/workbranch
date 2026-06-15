# 0030 Activity report 시간창별 Plan 단위 정리와 표시 granularity 계획

> **agentic worker 지침:** 실행 시 `superpowers:executing-plans` 또는 `superpowers:subagent-driven-development`를 사용한다. 동작 변경 전에는 `superpowers:test-driven-development`(red → green → refactor)를 따른다. 이 plan은 **Companion 전용**이다(CLI/brief 포맷/`list --json` 계약 변경 없음). Companion 변경은 `companion/`에서 `swift build` + `swift run CompanionCoreTestRunner`로 검증한다. 검증 순서: 관련 테스트 red/green → companion build/test → `git diff --check`. 문서를 건드리면 EN/KO를 같은 PR에서 동기화한다.
>
> **시리즈 위치:** 0028(task별 시간 측정 + 일/주/프로젝트 통계), 0029(task 안 Plan 단위 묶음 + Plan별 시간) 위에 얹는 **표시(display) 정리** slice다. 0029가 Plan 단위 데이터/이벤트/집계를 만들었다면, 0030은 그 데이터를 **시간창(Today/Weekly/Monthly)별로 적절한 granularity로 보기 좋게 표시**하는 데 집중한다. `list --json` 계약과 brief 포맷은 **변경하지 않는다**. 사용자 시각 피드백으로 확인된 `plan > step` 표시는 `activity.jsonl` v1에 optional `items` snapshot만 추가해 기존 로그 하위호환을 유지한다.

**목표:** Activity report와 라이브 모니터의 Plan 표시를 "한눈에 회고 가능한" 수준으로 정리한다. 핵심은 **시간창이 넓어질수록 표시 단위를 올리는 granularity 사다리**다.
1. **Today** — `project > task > plan > step snapshot`(가능한 경우). 우선 Plan 단위를 시간순 정렬/빈 Plan 제거/노이즈 축소로 정리하고, 이후 이벤트에 저장되는 optional step snapshot은 Plan 아래에 표시한다.
2. **Weekly** — `project > task > plan`. 지금은 task 합계만 보인다. Plan 단위 합계까지 보여준다.
3. **Monthly** — `project` 단위. 지금은 task까지 보인다. project 합계로 접는다.

**우선순위(사용자 확정):** "우선은 Today를 plan 단위로만이라도 정리해서 표시하자. 이렇게 정리한 이후에 plan > step 단위까지 표시." → **Slice A(Today plan 단위 정리)가 1순위**, 그 다음 Slice B(주/월 granularity), Slice C(메인 popover 정리) 순으로 진행했다. 사용자 스크린샷 피드백에서 Plan 제목만 반복되어 Step 문맥이 사라지는 문제가 확인되어, `plan > step`은 별도 live join 없이 optional activity event snapshot으로 보정한다.

**아키텍처(핵심 결정):**
- 데이터 원천은 그대로다: `activity.jsonl`(0028/0029)과 `list --json`의 `plans[]`(0029). `list --json`은 바꾸지 않고, future activity events에만 optional `items` snapshot을 저장해 report가 live state와 join하지 않고도 Plan 아래 Step을 표시한다.
- 집계/정렬 로직은 0028/0029처럼 `CompanionCore`의 순수 Swift(`ActivityReport`)에만 둔다. `ActivityReportView`는 표현만 한다.
- 시간창별 granularity는 view 분기(현재 `showsPlanDetails: Bool`)를 **표시 레벨 enum**으로 일반화한다.

**제품 관점:** 사용자가 Today를 열면 "오늘 어떤 Plan들을, 어떤 순서로, 각 얼마나 했는지"가 시간 흐름대로 읽힌다. Step snapshot이 있는 새 이벤트는 `plan` 아래 `step` 행으로 문맥을 보여준다. Weekly는 "이번 주 어떤 task의 어떤 Plan에 시간을 썼는지", Monthly는 "이번 달 어떤 project에 시간을 썼는지"로 자연스럽게 줌아웃된다. 기존 히스토릭 로그는 Step snapshot이 없으므로 Plan 행까지만 표시된다.

---

## 문제 (현재 동작 + 데이터 근거)

### P1. Today의 Plan이 시간순이 아니라 알파벳순으로 표시된다 (핵심)
한 task는 하루 동안 여러 `## Plan:`을 순차적으로 만들고 끝낸다. 그런데 각 Plan은 그 시점 brief의 **유일한** Plan이었으므로 거의 전부 `planIndex: 0`이다. `ActivityReport.makePlanReports`(`ActivityReport.swift:243-246`)는 `(index, title)`로 정렬하므로, index가 전부 0이면 결국 **title 알파벳순**으로 렌더된다. 하루의 작업 흐름(시간순)이 완전히 사라진다.

실측(`~/.local/state/workbranch/activity.jsonl`, 2026-06-15 `feat-task1`):
- 실제 작업 순서: `09:59 feat-task1` → `11:13 BOM draft tree ... plan review` → `11:17 ... decision grill` → … → `17:25 Fix CpqRfqModule ...` → `17:34 Complete ... closeout` (총 16개 Plan).
- 현재 UI 렌더 순서: `BOM draft tree ... backend kickoff` → `BOM draft tree ... decision grill` → … → `Review ...` → `feat-task1` (알파벳순). 시간 정보가 행에 없어 흐름을 읽을 수 없다.

### P2. Today가 한 task에 Plan 라인을 너무 많이 쌓아 읽기 어렵다
위 예시처럼 하루에 한 task가 16개 Plan을 가지면, Today에서 그 task 아래에 16줄의 Plan 라인 + 1줄의 status 라인이 깔린다. 사용자 피드백 "Activity report는 더 보기 힘듦"의 직접 원인이다.

### P3. 빈 제목 Plan이 빈 줄로 렌더된다
`plan`/`planTitle`이 빈 이벤트(0029 이전 legacy 줄, 또는 status-only diff)는 `makePlanReports`에서 빈 title 버킷으로 묶여 `│ plan   <duration>`처럼 **빈 Plan 라인**이 된다. 실측에서 `feat-update-0614-part8` 등은 planTitle이 비어 있다.

### P4. task별 status 라인이 노이즈를 더한다
`ActivityReportView.statusLine`(`:109-128`)은 task마다 `│ status <…> │ sessions <n> │ last <time>` 한 줄을 더 깐다. Plan을 주된 단위로 보고 싶은데 task 메타가 시각적 비중을 차지한다.

### P5. 시간창별 granularity가 요구와 어긋난다
`ActivityReportView`(`:14-16`)는 Today만 `showsPlanDetails: true`, Weekly/Monthly는 `false`다.
- Weekly: 현재 `project > task`만. 요구는 `project > task > plan`.
- Monthly: 현재 `project > task`. 요구는 `project`만(task로 접지 않음).

### P6. (메인 popover) `memo` 라인이 정보를 못 준다
`RowView.statusDetailsBlock`(`:137-139`)은 `memoTitle`이 있으면 `│ memo <memoTitle>`을 항상 표시한다. memo가 task 이름과 같으면(예: `memo feat-task1`) 아무 정보가 없다. `MenuState.taskRow`(`:347`)도 헤더 label을 `name — memoTitle`로 조립해 중복이 생긴다.

### P7. (메인 popover) 단일 Plan일 때 Plan 헤더가 사라진다
`RowView`(`:140`)는 `row.plans.count > 1`일 때만 Plan 헤더+Step 트리를 그리고, 1개면 flat 체크리스트만 그린다. 그래서 "지금 어떤 Plan이 진행 중인지"가 단일 Plan task에서는 보이지 않는다(스크린샷의 flat 목록).

## 현재 repo 근거

- 정렬 버그: `companion/Sources/CompanionCore/ActivityReport.swift:243-246` `makePlanReports` 반환 정렬(`index` → `title`).
- Plan 그룹 키: `ActivityReport.swift:220` `"\(event.plan)\u{0}\(event.planIndex)"`. 빈 plan title → 빈 버킷(P3).
- task 정렬: `ActivityReport.swift:174-178`(`seconds` desc → `lastEditedAt` desc → `task` asc).
- Plan 모델: `ActivityReport.swift:18-47` `ActivityReportPlan`(`title,index,seconds,sessions,lastEditedAt,status,progressDone,progressTotal`) — **firstEditedAt 없음**(시간순 정렬에 필요, 아래 결정 게이트).
- Plan row identity 위험: `ActivityReportView.swift:67`은 `ForEach(task.plans, id: \.index)`를 사용한다. 0030의 핵심 케이스처럼 서로 다른 Plan들이 모두 `planIndex == 0`이면 SwiftUI row identity가 충돌하므로, Slice A에서 stable row identity를 함께 고쳐야 한다.
- view granularity 분기: `ActivityReportView.swift:14-16`(Today만 details), `:27` `sectionBlock(showsPlanDetails:)`, `:50` `projectBlock`, `:91` `planLine`, `:109` `statusLine`.
- 라이브 렌더: `companion/Sources/CompanionApp/Views/RowView.swift:134` `statusDetailsBlock`, `:137-139` memo 라인, `:140` 단일/복수 Plan 분기, `:167` `planBlock`, `:176` `planHeaderLine`, `:197` `statusItemLine`.
- header label 조립: `companion/Sources/CompanionCore/MenuState.swift:344-380` `taskRow`(`:347` `name — memoTitle`).
- 테스트 진입점: `companion/Sources/CompanionCoreTestRunner/CompanionCoreTestRunnerTests.swift`. report shape/정렬은 여기서 합성 이벤트로 잠근다.

## 결정 사항 (확정됨)

1. **시간창별 표시 granularity 사다리**(사용자 확정): Today = `project > task > plan` + optional `step` snapshot, Weekly = `project > task > plan` + optional `step` snapshot, Monthly = `project`만.
2. **Today Plan은 시간순으로 표시**한다(P1). index/title 알파벳순이 아니라 그 Plan의 활동 시각 순서.
3. **빈 제목 Plan은 표시에서 합치거나 숨긴다**(P3). 빈 Plan 라인을 만들지 않는다.
4. **task별 status/sessions/last 라인은 제거**해 별도 노이즈 라인을 줄인다(P4). task 헤더는 `task <name> <duration>`만 남기고, status/progress는 Plan 라인의 `done/total`로 읽게 한다.
5. **이 slice는 CLI/brief/`list --json` 계약을 바꾸지 않는다.** 표시·정렬·집계 granularity만 바꾼다. 시간순 정렬을 위해 `ActivityReportPlan`에 표현 전용 additive 필드(`firstEditedAt`)를 더하고, 사용자 시각 피드백 해결을 위해 `activity.jsonl` v1 이벤트에 optional `items` snapshot을 더하는 것은 허용한다. 기존 로그는 `items: []`로 decode한다.
6. **우선순위:** Slice A(Today plan 정리) → B(주/월 granularity) → C(popover 정리) → D(optional Plan step snapshot 보정). A는 단독으로 머지 가능해야 한다.

## 결정 게이트 결과

- [x] **G1. Today Plan 정렬 키 = scope-local `firstEditedAt` 오름차순.**
  - Impact: 하루 흐름을 "시작한 순서"로 볼지 "최근 건드린 순서"로 볼지. 같은 Plan을 나중에 다시 만지면 순서가 달라진다.
  - Current evidence: `ActivityReportPlan`은 `lastEditedAt`만 있다. `ActivityReport.make`는 session을 먼저 만들고 day/week/month scope에 clip하므로, 정렬용 시작 시각도 전체 로그 첫 이벤트가 아니라 현재 report scope 안에서 해당 Plan이 처음 기여한 시각으로 정의해야 한다.
  - Resolved: Today Plan 정렬은 **scope-local `firstEditedAt` ascending**으로 한다. `firstEditedAt`은 현재 report scope 안에서 해당 Plan이 처음 활동으로 표시되는 시각이다. tie-break는 `lastEditedAt`, `index`, `title` 순서로 결정적으로 둔다.
  - Rejected: `lastEditedAt` 기반 정렬. 이유: 최근 수정 순서는 "오늘 어떤 Plan을 어떤 흐름으로 했는지"라는 회고 목표보다 "최근 건드린 것"에 치우치고, 같은 Plan을 나중에 조금 수정하면 하루 서사 위치가 흔들린다.

- [x] **G2. Today에서 한 task의 Plan이 많아도 v1은 모두 표시한다.**
  - Impact: P2 가독성. 전부 보일지, 상위 N개 + "N more", 또는 시간 임계값(예: `<1m` 미만 접기) 적용할지.
  - Current evidence: 0030의 실측 예시는 하루 한 task에 Plan 16개가 쌓이는 케이스다. G1의 시간순 정렬과 G3의 task-level status/sessions/last 제거만으로도 현재 알파벳순+노이즈 상태보다 읽기 쉬워진다.
  - Resolved: Slice A v1은 **모든 non-empty Plan을 scope-local `firstEditedAt` 시간순으로 전부 표시**한다. 상위 N 접기, 최근 N 접기, `<1m` 접기는 후속으로 둔다.
  - Rejected: v1부터 `N more` 접기. 이유: 어떤 Plan을 숨길지(duration 상위, 최근, 짧은 Plan 등)라는 추가 UX 정책이 필요하고, Slice A의 핵심인 "시간순 흐름을 먼저 확인"하는 검증을 흐린다.

- [x] **G3. task별 status/sessions/last 라인은 완전히 제거한다.**
  - Impact: 진단 정보(sessions/last edit) 노출 여부.
  - Current evidence: `ActivityReportView.projectBlock`은 Plan rows 뒤에 `statusLine(task)`를 호출하고, `statusLine`은 task status, sessions, last edit 시각을 별도 행으로 렌더한다. 이 행은 Today의 Plan 흐름 읽기보다 진단 정보에 가깝다.
  - Resolved: Today/Weekly의 task header는 `task <name> <duration>`만 남긴다. task-level status/sessions/last 별도 라인은 제거한다. Plan별 status/progress는 Plan line에 유지한다.
  - Rejected: task header에 `last HH:mm`만 축약 표시. 이유: 0030의 우선 목표가 Plan 흐름 가독성 회복이고, `last`는 회고 기본 정보보다 디버깅 정보에 가깝다.

- [x] **G4. Today/Weekly `plan > step`은 live join이 아니라 optional activity event snapshot으로 표시한다.**
  - Impact: 기존 활동 로그에는 step 텍스트/시간이 없다(0029 "미해결/후속"). 히스토릭 Plan(이미 brief에서 사라진 완료 Plan)은 live step과 매칭 불가하므로 과거 row는 Plan까지만 표시된다.
  - Current evidence: `ActivityReportView`는 `ActivityReport` 3개(today/week/month)만 받고, `list --json plans[].items`는 현재 brief snapshot이므로 과거에 brief에서 사라진 Plan step은 복원할 수 없다. 사용자 스크린샷에서는 긴 Plan 제목이 반복/축약되어 Step 문맥이 필요하다는 것이 확인됐다.
  - Resolved: `ActivityEvent` v1에 optional `items: [WorkbranchChecklistItem]` snapshot을 더한다. 새 이벤트는 changed Plan의 Step snapshot을 저장하고, 기존 JSONL은 `items: []`로 decode한다. `ActivityReportPlan`은 최신 non-empty snapshot을 들고, `ActivityReportView`는 Plan 아래 `[ ]/[x]` Step 행을 표시한다.
  - Rejected: live `list --json plans[].items`를 `ActivityReportView`까지 전달해 현재 brief에 남은 Plan에만 step을 표시한다. 이유: report 데이터와 live task snapshot을 join하는 새 경계가 필요하고, 히스토릭 Plan은 step 없이 표시되는 불균등 정책이 생긴다. optional event snapshot이 더 정직하고 durable하다.

## public contract (변경 / 비변경)

### 변경하지 않는 것 (중요)
- `workbranch list --json` 필드/의미, `plans[]` 스키마(0029).
- `~/.local/state/workbranch/activity.jsonl`의 schemaVersion(1)과 기존 필드 의미. 단, `items`는 optional additive snapshot으로 새 이벤트에만 기록될 수 있다.
- brief(`TASK-WORKBRANCH.md`) 포맷, 세션화 파라미터(idle gap 25분, lead pad 5분).
- CLI 명령(어떤 `report` 명령도 추가하지 않음 — 0028 결정 유지).

### CompanionCore 내부 모델(표현 전용, 공개 계약 아님)
- `ActivityReportPlan`에 `firstEditedAt: Int` additive 추가. 디코드는 `decodeIfPresent`로 하위호환. 값은 전체 로그 첫 이벤트가 아니라 현재 report scope 안에서 해당 Plan이 처음 기여한 시각으로 둔다.
- `ActivityEvent`/`ActivityReportPlan`에 `items: [WorkbranchChecklistItem]` optional/additive snapshot 추가. 디코드는 없으면 빈 배열, 인코드는 non-empty일 때만 기록한다.
- `ActivityReportView`의 `showsPlanDetails: Bool`을 표시 레벨 enum(예: `ReportDetailLevel { case projectOnly, taskPlans }`)으로 일반화. Today=`taskPlans`, Weekly=`taskPlans`, Monthly=`projectOnly`. Step snapshot이 있는 Plan은 Plan 아래 Step 행을 표시한다.

## 파일 구조 (touched)

```text
# Companion (Swift) — 표시/정렬/집계 granularity만
companion/Sources/CompanionCore/ActivityReport.swift          # Plan 시간순 정렬, 빈 Plan 병합/제거, (G1) firstEditedAt
companion/Sources/CompanionApp/Views/ActivityReportView.swift # 표시 레벨 enum, Today/Weekly/Monthly granularity, status 라인 정리, Plan row stable identity
companion/Sources/CompanionApp/Views/RowView.swift            # (Slice C) memo 라인 정리, 단일 Plan 헤더 표시
companion/Sources/CompanionCore/MenuState.swift               # (Slice C) header label 중복(name — memo) 정리
companion/Sources/CompanionCoreTestRunner/CompanionCoreTestRunnerTests.swift  # 정렬/빈Plan/granularity 테스트

# 문서
companion/README.md, README.md, README.ko.md                  # report granularity 설명 동기화(해당 슬라이스에서)
```

## 구현 작업 (TDD: 먼저 빨갛게)

### Slice A — Today를 Plan 단위로 제대로 정리 (1순위)
- **red:** `CompanionCoreTestRunnerTests`에 합성 이벤트로
  1. 같은 task에 `planIndex` 모두 0인 Plan 여러 개 → report의 plan 순서가 **scope-local `firstEditedAt` 시간순**임을 assert(현재는 title 알파벳순으로 실패).
  2. `plan`/`planTitle`이 빈 이벤트 포함 → 결과 plans에 **빈 title 라인이 없음**(병합/제외) assert.
  3. `firstEditedAt`이 현재 report scope 안에서 해당 Plan이 처음 기여한 editedAt와 같음 assert. 경계 케이스(예: 전날 23:55 → 오늘 00:05 연속 session)는 전체 첫 이벤트가 아니라 오늘 scope 안의 첫 표시 시각으로 잠근다.
  4. `ActivityReportView`에서 서로 다른 Plan들이 모두 `index == 0`이어도 row identity가 충돌하지 않음을 source-invariant 또는 helper 테스트로 잠근다.
  5. `ActivityReportView`가 task-level `statusLine(task)`를 더 이상 렌더하지 않음을 source-invariant로 잠근다.
- **green:** `makePlanReports` 정렬을 scope-local `firstEditedAt` 키로 교체, 빈 title 버킷 처리(병합 또는 제외), `ActivityReportPlan.firstEditedAt` additive 필드 추가, `ActivityReportView` Plan row stable identity 추가.
- **view:** `ActivityReportView` Today에서 `statusLine(task)` 호출과 `statusLine` UI를 제거한다. task header는 `task <name> <duration>`만 남기고, Plan 라인은 `plan <title> · <duration> · <done/total status>`로 정리한다. 빈 Plan은 view에서도 그리지 않음.
- **검증:** 해당 테스트 red→green, `swift build`, `swift run CompanionCoreTestRunner`. 시각 검증은 "실행 결과"에 캡처 메모.
- **Acceptance:** Today에서 한 task의 모든 non-empty Plan들이 작업한 시간순으로, 빈 줄 없이, task-level status/sessions/last 노이즈 없이 표시된다. Plan rows는 v1에서 접지 않는다.

### Slice B — 시간창별 granularity 사다리
- **red:** Today/Weekly/Monthly 각각에 대해 표시 레벨이 `taskPlans`/`taskPlans`/`projectOnly`로 매핑되는지, Monthly가 task/plan 라인을 내지 않고 project 합계만 내는지 view-model 레벨에서 assert(가능한 범위에서 순수 함수로).
- **green:** `showsPlanDetails: Bool` → `ReportDetailLevel` enum. `ActivityReportView`의 `sectionBlock`/`projectBlock`이 레벨에 따라 task/plan/step 렌더를 분기. Weekly에 Plan 라인 추가, Monthly에서 task 접기.
- **검증:** `swift build` + Runner. 시각 캡처 메모.
- **Acceptance:** Weekly가 `project > task > plan`, Monthly가 `project`만 보여준다.

### Slice C — 메인 popover 정리 (메시지1 피드백, 독립 가능)
- **memo 라인:** memo가 비었거나 task 이름과 같으면 `│ memo` 라인을 그리지 않는다(`RowView:137-139`). `MenuState.taskRow`(`:347`)의 헤더 label도 memo==name이면 중복 제거.
- **단일 Plan 헤더:** `RowView:140` 분기를 바꿔 Plan이 1개여도 Plan 헤더(이름 · done/total · status)를 표시하고 그 아래 Step. (Plan이 0개일 때만 flat/빈 처리.)
- **red/green:** `MenuState` label 조립 테스트(memo==name 중복 제거), RowView는 source-invariant/빌드로 검증.
- **Acceptance:** memo가 task 이름과 같을 때 memo 라인이 사라지고, 단일 Plan task도 "지금 어떤 Plan이 진행 중인지"가 Plan 헤더로 보인다.


### Slice D — Activity report `plan > step` snapshot 보정 (스크린샷 피드백)
- **red:** changed Plan 이벤트가 `items` snapshot을 보존하는지, 기존 `activity.jsonl` line이 `items` 없이도 decode되는지, `ActivityReportPlan`이 최신 non-empty snapshot을 선택하는지 테스트한다.
- **green:** `ActivityEvent.items` optional/additive 필드 추가(`decodeIfPresent ?? []`, non-empty일 때만 JSON 인코드). `ActivityEvent.diff`는 changed/status-only Plan 이벤트에 `plan.items`를 싣는다. `ActivityReportPlan.items`는 최신 non-empty snapshot을 들고, view는 `planLine` 아래 `planStepLine`을 렌더한다.
- **Acceptance:** 새 activity event가 생성된 Plan은 report에서 `plan` 아래 `[ ]/[x] step` 행으로 보이고, 기존 히스토릭 로그는 깨지지 않고 Plan 행까지만 표시된다.

## 최종 검증

```bash
cd companion && swift build && swift run CompanionCoreTestRunner
git diff --check
```

- 결정성: 합성 로그로 정렬/병합/granularity가 입력에만 의존함을 테스트로 잠근다.
- 수동/시각: 메뉴바 popover와 Activity report를 실제로 열어 Today 시간순/Weekly plan/Monthly project를 확인(release/manual QA 단계).

## 롤아웃 / 호환성

- **비파괴.** CLI/brief/`list --json` 계약은 불변. 기존 `activity.jsonl`은 그대로 읽히며, `items`가 없는 라인은 빈 step snapshot으로 처리한다. 마이그레이션 불필요.
- `firstEditedAt`은 CompanionCore 내부 모델 필드로 `decodeIfPresent` 하위호환. 외부에 노출 안 함.
- `ActivityEvent.items`는 optional additive snapshot이다. 구버전 companion은 알 수 없는 JSON field를 무시하고, 신버전 companion은 old log를 step 없이 표시한다.

## 미해결 / 후속

- **Step별 시간**: 이번 보정은 Plan별 Step snapshot 표시만 한다. Step마다 몇 분을 썼는지는 활동 로그에 없으므로, 진짜 step 단위 시간 추적은 별도 event 설계가 필요하다.
- **Plan이 매우 많은 task의 접기/요약**(G2): Slice A v1은 모든 non-empty Plan을 표시한다. 상위 N 접기·최근 N 접기·`<1m` 접기·세션 병합 요약은 후속.
- **Weekly/Monthly Plan 병합**: 같은 Plan title이 여러 날 반복될 때 주간에서 어떻게 합칠지(title 기준 합산 vs 날짜별)는 Slice B에서 단순 규칙으로 시작하고 필요 시 후속.

## 실행 결과

- [x] Slice A — Today Plan 시간순 정렬 + 빈 Plan 제거 + status 라인 정리.
- [x] Slice B — Today/Weekly/Monthly granularity 사다리.
- [x] Slice C — 메인 popover memo 라인/단일 Plan 헤더 정리.
- [x] Slice D — optional activity event `items` snapshot과 Activity report Plan > Step 렌더링.

### 검증 기록

- `cd companion && swift run CompanionCoreTestRunner` — PASS after Slice A red/green, Slice B red/green, and Slice C red/green.
- `cd companion && swift build && swift run CompanionCoreTestRunner` — PASS after Slice D step snapshot changes.
- `cd companion && swift build && swift run CompanionCoreTestRunner && cd .. && git diff --check` — PASS.
- `python3` trailing-whitespace check for untracked `docs/plans/0030-activity-report-time-window-granularity.md` — PASS.

### 수동/시각 검증 메모

- Native menu bar UI를 직접 띄워 육안 확인하는 단계는 이 실행에서 수행하지 않았다. 대신 `ActivityReportView`/`RowView` source-invariant와 `swift build`로 Today/Weekly/Monthly granularity, Plan row identity, task status line 제거, memo 중복 제거, 단일 Plan header 렌더 경계를 잠갔다. 실제 menu bar popover 시각 QA는 release/manual QA 단계에서 Today 시간순, Weekly Plan rows, Monthly project-only, memo/단일 Plan 표시를 확인한다.
