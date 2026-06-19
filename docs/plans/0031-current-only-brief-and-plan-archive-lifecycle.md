# 0031 현재 Plan만 담는 Brief + 완료 Plan Archive 라이프사이클 계획

> **agentic worker 지침:** 실행 시 `superpowers:executing-plans` 또는 `superpowers:subagent-driven-development`를 사용한다. 동작 변경 전에는 `superpowers:test-driven-development`(red → green → refactor)를 따른다. CLI 코드는 `src/workbranch/**`를 먼저 수정하고 `scripts/build-workbranch.sh`로 `bin/workbranch`를 재생성한다. `bin/workbranch`를 직접 수정하지 않는다. 새 모듈을 만들면 `scripts/workbranch-sources.txt`에 등록한다. 새/수정 bash 테스트는 `tests/run.sh`에 `run_test ...`로 등록한다. Companion 변경은 `companion/`에서 `swift build` + `swift run CompanionCoreTestRunner`로 검증한다. 검증 순서: `bash -n` syntax check → 관련 테스트 red/green → `./tests/run.sh` 전체 → companion build/test → `git diff --check`. 문서를 건드리면 EN/KO를 같은 PR에서 동기화한다.
>
> **시리즈 위치:** 0021(task progress/lifecycle), 0026(`todo` lifecycle + `plan:` 도입), 0028(task별 시간 측정), 0029(`## Plan:` 섹션으로 Plan 단위 Step 묶음 + Plan별 시간) 위에 얹으면서 **0029의 표시·형식 모델을 개정**한다. 0029는 한 brief 안에 모든 Plan을 `## Plan:` H2로 누적·전부 표시했다. 0031은 (1) Plan 구분자를 `# <plan>` **H1**로 바꾸고, (2) brief에는 **현재 Plan만** 남기며, (3) 완료 Plan을 **plan별 archive 파일**로 떼어내고, (4) 라이브 모니터는 **현재 Plan만** 보여준다. **Activity report의 Plan별 시간(0028/0029)은 그대로 유지**된다 — 시간 진실의 원천은 `activity.jsonl`이며, archive 후에도 Companion이 이미 관측한 Plan별 시간 이력은 보존된다. 단, `done`/archive 명령 자체가 final done activity event를 CLI에서 직접 쓰지는 않는다.

**목표:** 하나의 `<task>` workspace에서 branch 전환/merge를 반복해도 `TASK-WORKBRANCH.md`가 무한 누적되지 않게 한다.
1. **`TASK-WORKBRANCH.md` = 현재 진행 Plan만.** 라이브 모니터가 보여줄 내용과 1:1.
2. **완료 Plan = archive 파일.** `.workbranch/plans/done/<timestamp>-<slug>.md`로 떼어내 보존.
3. **완료 처리는 명시적이고 안전하게.** 추측하지 않는다. 확실할 때만, 항상 사용자 확인(y/N) 후 archive.
4. **Activity report는 무변경.** Plan별 시간 집계는 `activity.jsonl` 기반이며, 보존 범위는 Companion이 archive 전까지 관측한 이벤트다.

**아키텍처(핵심 결정):**
- 진실의 원천은 여전히 `<task>/TASK-WORKBRANCH.md` 한 파일(현재 Plan) + `~/.local/state/workbranch/activity.jsonl`(시간 이력). 에이전트는 brief를 직접 편집한다(0028 원칙 유지).
- **Plan 구분자 = `# <name>` (H1) 헤딩**(사용자 확정). 0029의 `## Plan:` (H2)를 대체하는 **클린 브레이크**. 구형 `## Plan:`/최상단 `status:`·`plan:` 필드는 더 이상 지원하지 않는다.
- **task 이름은 workspace에서** 온다. brief의 H1은 더 이상 task 이름이 아니라 **Plan 이름**이다.
- **Plan status는 명시적 `status:` 줄**(사용자 확정 옵션 A). 없으면 Step done/total로 파생.
- **완료 = `done` 한 동작**: 현재 active Plan을 `status: done`으로 만들고 → archive 파일로 이동 → brief를 다음 Plan용으로 비운다. 내부 함수 1개를 명령/트리거가 공유(DRY).
- **자동 트리거는 확실한 신호 + 프롬프트만.** `land`/`finalize`(로컬 merge 성공), `pull`(task 브랜치가 base에 merged) 감지 시 y/N 확인 후 archive. `push`·squash/rebase 등 모호한 경우는 아무것도 안 한다.
- Activity 집계/리포트는 0028/0029처럼 Companion `CompanionCore` 순수 Swift에만 둔다. CLI `report` 명령은 만들지 않고, archive/done CLI도 `activity.jsonl`을 직접 쓰지 않는다.

**제품 관점:** 한 repo에서 branch를 바꾸며 여러 작업을 이어가도 현재 화면은 "지금 하는 Plan"만 깔끔하게 보이고, 지난 Plan은 archive로 회고 가능하며, 시간 집계는 끊기지 않는다.

---

## 문제

1. **brief가 무한 누적된다.** 한 workspace에서 branch 전환/merge를 반복하면 사용자가 같은 `TASK-WORKBRANCH.md`에 Plan 블록을 계속 덧붙인다. 라이브 모니터가 전부(예: 88/88)를 한 화면에 쌓아 보여 "지금 무엇을 하는지"가 묻힌다.
2. **H1이 task 이름이라 낭비된다.** 현재 권장 형식은 `# <task>`(workspace에서 이미 아는 값) + `## Plan:`(0029). task 이름은 `add <task>`로 고정되어 안 바뀌는데 매 블록 반복된다.
3. **완료 Plan을 떼어낼 메커니즘이 없다.** 완료된 Plan을 brief에서 안전하게 archive로 옮기고, `remove` 시 함께 정리하는 흐름이 없다.
4. **완료 신호가 정의되지 않았다.** land/finalize/pull/push 중 무엇이 "이 Plan 끝"인지, 자동/수동 경계가 없다.

## 현재 repo 근거

- brief 파서/형식: `src/workbranch/lib/task-state.sh` — `task_load_plans`(현재 `## Plan:` H2를 구분자로, `:79` 부근 정규식), `task_plan_status_at`, `task_active_plan_title`(첫 non-done, 없으면 마지막), `task_plans_json`, `write_default_task_brief`(`# $task` + `## Plan: $task` 템플릿), `write_task_agent_guidance`(`## Plan:` 규칙 안내), `remove_task_state_files`(`:461` `rmdir "$state_dir"` — 비어있을 때만 성공), `task_state_dir_path`(`<root>/<task>/.workbranch`).
- JSON 방출: `src/workbranch/commands/list.sh` `cmd_list_json` — task별 `memoTitle`/`planTitle`(=`task_active_plan_title`)/`status`/progress/`currentItem`/`plans[]`(0029)/`repos`.
- 명령 디스패치: `src/workbranch/main.sh:8` `case "$cmd"` — `done`을 여기 등록.
- 완료 신호 후보: `commands/land.sh` `execute_land_task`(성공 직후), `commands/finalize.sh` `cmd_finalize`(끝의 `execute_land_task`), `commands/pull.sh` `run_pull`/`execute_pull_repos`(base만 갱신, task 인자 없음), `commands/push.sh` `cmd_push_task`(origin push만 — 약한 신호).
- git 헬퍼: `src/workbranch/git-ops.sh:114` land의 `merge --ff-only`만 존재. ancestor/merged 판정 헬퍼는 **신규** 필요.
- 프롬프트/출력: `src/workbranch/lib/prompts.sh:1` `prompt_read`, `lib/output.sh` `info`/`success`/`die`, `commands/remove.sh` `prompt_delete_remaining_task_root`(TTY 가드 + `WORKBRANCH_ALLOW_NON_TTY_PROMPT` 패턴 — 그대로 재사용).
- Companion 표시: `companion/Sources/CompanionApp/Views/RowView.swift:224` `renderablePlans`(현재 `row.plans` 전부 렌더), `:134` `statusDetailsBlock`. 매핑: `companion/Sources/CompanionCore/MenuState.swift` `taskRow`(`plans: task.plans`).
- 시간 파이프라인(무변경): `companion/Sources/CompanionCore/ActivityEvent.swift`(`diff`가 `task.activityPlans` 순회, append-only), `ActivityReport.swift`(`makePlanReports` → `ActivityReportPlan` Plan별 seconds), `companion/Sources/CompanionApp/ActivityRecorder.swift`(`~/.local/state/workbranch/activity.jsonl`).

## 결정 사항 (확정됨)

1. **지난 Plan 처리 = 현재-only brief + archive(Option B).** 시간 이력은 `activity.jsonl`에 있으므로 brief에서 떼어내도 Companion이 이미 관측한 Plan별 시간은 보존된다. archive 명령의 final done 상태를 activity log에 쓰는 것은 보장하지 않는다.
2. **archive는 명시적 파일로 보존.** `activity.jsonl`은 `## Notes` 산문을 담지 않으므로(아래 근거) 결정/잔여이슈 narrative 보존을 위해 필요. (`ActivityEvent`는 title/status/items/progress/time만 기록 — `companion/Sources/CompanionCore/ActivityEvent.swift`.)
3. **archive 구조 = plan별 파일.** `.workbranch/plans/done/<timestamp>-<slug>.md`. merge 충돌 최소(유일 파일명), 백엔드 `docs/cpq/plans/done/` 컨벤션과 동일.
4. **완료 주체 = 단일 내부 함수.** 명령/트리거가 공유.
5. **명령 이름 = `done`.** 동작: 현재 Plan을 `status: done` 처리 → archive 이동(한 동작). (`archive`는 내부 함수명에만.)
6. **자동 트리거:** `land`/`finalize` 성공 후, `pull`로 repo filter 대상 task 브랜치들이 모두 base에 merged 감지 시. 각각 **y/N 프롬프트** 후 archive.
7. **추측 금지:** `push`(약한 신호)·squash/rebase merge(ancestor 아님) 등 불확실한 경우 아무 동작 안 함. 비-TTY 기본 N.
8. **brief 형식 = `# <plan>` H1 + `status:` 줄(옵션 A).** 최상단 `status:`/`plan:` 필드 제거. task 이름은 brief에 안 씀.
9. **하위호환 = 클린 브레이크.** 구형 `## Plan:`/`# <task>`+`plan:` 누적 형식은 미지원. 기존 파일은 1회 정리.
10. **HUD = 현재 Plan만, steps만.** Plan의 `## Notes`는 HUD 미표시(파일/archive에서만).
11. **archive 파일 = frontmatter 메타 + Plan 블록 verbatim.** 시간은 미포함(`activity.jsonl`이 SoT).
12. **정렬:** 새 Plan은 brief 아래에 추가. "현재" = 위에서 첫 non-done, 전부 done이면 마지막.
13. **remove 정리:** `remove_task_state_files`가 `.workbranch`를 **`rm -rf`**로 통째 정리(archive 포함, 자동화 갭도 닫힘).

## 결정 게이트 결과

- [x] **archive 시점 activity 기록 계약은 Companion 관측 기반으로 유지한다.**
  - Impact: activity/history ownership, CLI side effects, archive의 user-visible completion semantics.
  - Current evidence: `companion/Sources/CompanionCore/ActivityEvent.swift`의 `ActivityEvent.diff`는 `next` snapshot의 `task.activityPlans`를 순회하므로, archive 후 brief에서 제거된 Plan의 final `done` 상태는 자동 emit되지 않는다.
  - Resolved: `done`/land/finalize/pull archive는 `activity.jsonl`에 final event를 직접 쓰지 않는다. Activity report는 archive 전까지 Companion이 관측한 Plan별 이벤트를 보존하는 범위로 계약을 낮춘다.
  - Rejected: Bash CLI가 `activity.jsonl`에 final done event를 append한다. 이유: 0028/0029의 Companion-local activity writer 경계를 깨고, multi-writer append/observedAt/backfill 정책을 새 public contract로 만들기 때문이다.

- [x] **`pull` 자동 archive는 repo filter 대상 전체가 merged일 때만 프롬프트한다.**
  - Impact: multi-repo task lifecycle, false-positive completion/archive risk.
  - Current evidence: `src/workbranch/commands/pull.sh`는 base repos만 pull하고 task 인자를 받지 않는다. `--repo` filter는 기존 horizontal/vertical 명령에서 대상 repo를 좁히는 public UX다.
  - Resolved: `workbranch pull` 후 스캔은 각 task별로 현재 repo filter 대상 repo만 평가한다. `--repo`가 없으면 task의 모든 repos가 기준이고, `--repo <repo>`가 있으면 해당 repo만 기준이다. 대상 repo 각각에 대해 pull 전 task branch에 의미있는 커밋이 있었고, pull 후 task branch가 base branch의 ancestor일 때만 y/N archive 프롬프트를 띄운다. 하나라도 미충족이면 자동 archive 프롬프트를 띄우지 않는다.
  - Rejected: 하나라도 merged이면 프롬프트를 띄우고 나머지는 경고로 처리한다. 이유: archive는 task-level 완료 처리라 partial repo merge에 반응하면 아직 끝나지 않은 repo 작업을 완료 처리할 수 있다.

- [x] **새 Bash 구현 파일은 `lib/archive.sh` + `commands/done.sh`로 둔다.**
  - Impact: new file placement, generated `bin/workbranch` source order, archive lifecycle ownership.
  - Current evidence: command entrypoints live under `src/workbranch/commands/*.sh`; shared state/prompt/parser helpers live under `src/workbranch/lib/*.sh`; `scripts/workbranch-sources.txt` controls generated binary order.
  - Resolved: shared archive lifecycle logic goes in `src/workbranch/lib/archive.sh`; `workbranch done` command entrypoint goes in `src/workbranch/commands/done.sh`; both are registered in `scripts/workbranch-sources.txt` before callers need them.
  - Rejected: putting archive lifecycle functions into existing `src/workbranch/lib/task-state.sh`. 이유: archive frontmatter, slug/collision handling, and brief rewrite are lifecycle side effects rather than parser/template state helpers, and `task-state.sh` is already broad.

- [x] **새 CLI 테스트 파일은 기능별 3개로 분리한다.**
  - Impact: new test artifact placement, targeted regression ownership, git-lifecycle setup cost.
  - Current evidence: existing tests live as behavior-scoped `tests/cases/*.sh` files and are registered from `tests/run.sh`.
  - Resolved: add `tests/cases/current-plan-brief.sh` for H1 parser/current-plan JSON contract, `tests/cases/plan-archive.sh` for archive + `done` command + no activity-log write, and `tests/cases/plan-archive-triggers.sh` for land/finalize/pull prompts. Register each with `run_test ...` in `tests/run.sh`.
  - Rejected: one large `tests/cases/current-plan-archive.sh`. 이유: parser/archive checks and git topology trigger checks have different setup costs; one file would make failures harder to isolate.


## 용어 계약

- **Plan:** brief 안에서 `# <name>` (H1) 헤딩으로 시작하는 Step 묶음. brief에는 보통 현재 Plan 1개만 존재(전환기엔 done 1 + 신규 1 등 ≥1 가능).
- **Step:** Plan 아래 `- [ ]`/`- [x]` 항목. 2칸/level 들여쓰기로 하위 Step.
- **현재(active) Plan:** brief의 Plan 중 위에서 첫 non-done. 전부 done이면 마지막.
- **archive Plan:** `done` 처리되어 `.workbranch/plans/done/<timestamp>-<slug>.md`로 이동한 완료 Plan.
- **완료 신호:** Plan이 끝났다는 확실한 근거 — 명시적 `done`, 로컬 `land`/`finalize` 성공, `pull` 후 task 브랜치가 base의 ancestor(merged).

## public contract

### brief 형식 (신규, 클린 브레이크)

```markdown
# Fix PricingDetailPage stale mock
status: in-progress
- [ ] Reproduce failing Vitest
- [ ] Patch stale mock
  - [ ] Add hook to mutation mock
- [ ] Rerun test and lint
## Notes
- useAddPriceVariantColumnMutation 누락 추정
```

파싱 규칙(`task_load_plans` 개정):
- `# <텍스트>` (H1) = 새 Plan, `title` = 헤딩 텍스트.
- Plan 헤딩 바로 아래 `status:` 줄 = 그 Plan 상태(`todo|planning|in-progress|review|blocked|done`). 없으면 Step done/total로 파생(`done==total→done`, `done==0→todo`, 그 외 `in-progress`).
- `- [ ]`/`- [x]` = Step. depth = 들여쓰기/2.
- `##` 이상(예: `## Notes`, `## 메모`)은 Plan 종료. 그 안의 `-` 항목은 Step 아님.
- 코드펜스(``` ``` ```) 안은 무시(기존 유지).
- 최상단 `status:`/`plan:` 필드는 **읽지 않는다**(클린 브레이크).
- 첫 `#` 이전의 Step은 Plan 없음 → 무시(형식 위반). `task_brief_title`(memoTitle)은 더 이상 task 이름 용도가 아니므로, memoTitle은 현재 Plan title로 대체하거나 비운다.

### archive 파일 `.workbranch/plans/done/<timestamp>-<slug>.md`

```markdown
---
archived_at: 2026-06-16T14:35:00+09:00
task: feat-update-0616
branch: feat/cpq-task1
completed_via: done        # done | land | finalize | pull
---

# Fix PricingDetailPage stale mock
status: done
- [x] Reproduce failing Vitest
- [x] Patch stale mock
- [x] Rerun test and lint
## Notes
- mutation mock에 hook 추가. 2/2 통과.
```

- `<timestamp>` = `YYYYMMDD-HHMMSS`(로컬). `<slug>` = Plan title을 kebab-case 정규화([a-z0-9-], 소문자, 공백→`-`, 길이 제한). 충돌 시 `-2` 등 suffix.
- 본문은 archive되는 Plan 블록 verbatim(헤더+status+steps+`## Notes`). 시간은 미포함.
- `branch`는 task의 대표 repo 현재 task branch(`.workbranch.task` 메타/`repo_task_branch_at`)에서. 멀티 repo면 첫 repo 기준 + 주석은 후속.
- archive/done CLI는 `activity.jsonl`을 직접 수정하지 않는다. final `done` 상태의 activity event가 필요하면 Companion이 archive 전 brief 상태를 관측해야 한다.

### `workbranch done <task>` (신규 명령)

- `main.sh` case에 `done) cmd_done "$@" ;;` 등록. usage/completion에 추가.
- 동작: brief에서 현재 active Plan을 고르고 → archive 파일 본문에는 `status: done`으로 기록 → brief에서 그 Plan 블록 제거. brief에 Plan이 0개가 되면 빈 상태(또는 안내 주석)로 둔다. 이 동작은 `activity.jsonl`을 직접 쓰지 않는다.
- 명시적 호출이므로 추가 프롬프트 없음. archive 경로를 `success`로 출력.
- 현재 Plan이 없으면 `die`(또는 no-op 안내).

### 자동 트리거(확실 + 프롬프트)

| 트리거 | 위치 | 판정 | 동작 |
|---|---|---|---|
| `land` | `execute_land_task` 성공 직후 | 현재 Plan 존재 | 앞에 빈 줄을 두고 `[*] Mark plan "<title>" done and archive? [Y/n]` → Enter/y면 `archive_current_plan`(`completed_via: land`) |
| `finalize` | `cmd_finalize` 끝(land 성공 후) | 위와 동일 | 위와 동일(`completed_via: finalize`) |
| `pull` | `run_pull` 후(신규 스캔) | repo filter 대상 repo 전체에서 task 브랜치가 pull 후 base의 ancestor & pull 전 의미있는 task 커밋 존재 | task별 프롬프트 → y면 archive(`completed_via: pull`) |
| `push`/모호 | — | — | 아무 동작 안 함 |

- 프롬프트는 `prompt_read` + TTY 가드(`prompt_delete_remaining_task_root` 패턴). 비-TTY는 N(`WORKBRANCH_ALLOW_NON_TTY_PROMPT=1`일 때만 응답 가능).
- **pull merge 판정**(`commands/pull.sh` helper): `pull` 실행 전 repo filter 대상 각 repo의 `old_base_head`를 저장하고, `old_base_head..task-branch`에 의미있는 커밋이 1개 이상 있는지 먼저 기록한다. `pull` 후에는 같은 대상 repo 전체에서 `git -C <base> merge-base --is-ancestor <task-branch> <base-branch>` 가 성공해야 한다. 이 pre/post 조합으로 trivial-ancestor(커밋 0개) false positive를 배제한다. 대상 repo 중 하나라도 조건을 만족하지 않으면 자동 archive 프롬프트를 띄우지 않는다. squash/rebase merge는 ancestor가 아니라 감지 안 됨(false negative, 안전) → 사용자는 `done`으로 fallback.

### remove 정리

- `remove_task_state_files`: 마지막 `rmdir "$state_dir"`를 `rm -rf "$state_dir"`로 변경. `.workbranch`(noti + plans/done 전부 workbranch 관리)를 통째 삭제 → archive 잔존/비-TTY 갭 동시 해소.

### `workbranch list --json` (대부분 유지)

- 기존 `plans[]`(0029, additive) 그대로. brief가 현재-only라 `plans[]`는 보통 길이 1. `planTitle`/top-level 집계는 active Plan/현재 Plan 기준으로 채움(기존 `task_active_plan_title` 재사용).
- schemaVersion 1 유지. 신규 필드 없음(archive는 파일 시스템에만, JSON 비노출 — 라이브 모니터는 현재만 보므로).

### Companion 라이브 표시

- `RowView.renderablePlans`: `row.plans` 전부 → **현재 Plan 1개만** 선택(첫 non-done, 없으면 마지막). 데이터 파이프라인(`task.plans`/activity event)은 무변경 — 표시 레이어에서만 필터.
- Plan의 `## Notes`는 미표시(현재도 `statusDetailsBlock`은 memo + steps만; Notes 비노출 유지).

### 변경하지 않는 것

- Activity report 파이프라인 전부(0028/0029): `ActivityEvent`/`ActivityReport`/`ActivityRecorder`/`ActivityReportView`. Plan별 시간은 그대로 동작(아래 "호환성" 참조).
- `updatedAt`=brief mtime 권위값, idle gap(25분)/lead pad(5분), schemaVersion 1.
- status/sync/doctor/destroy/prune 등 다른 명령.

## 파일 구조 (touched)

```text
# CLI (Bash)
src/workbranch/lib/task-state.sh        # task_load_plans: '# ' H1 구분자 + per-plan status:; write_default_task_brief/write_task_agent_guidance 신형 템플릿; remove_task_state_files rm -rf
src/workbranch/lib/archive.sh           # (신규) archive_current_plan, slug/timestamp, frontmatter, brief 재작성
src/workbranch/commands/done.sh         # (신규) cmd_done
src/workbranch/commands/land.sh         # execute_land_task 성공 후 archive 프롬프트
src/workbranch/commands/finalize.sh     # land 후 archive 프롬프트
src/workbranch/commands/pull.sh         # pre-pull meaningful snapshot + post-pull ancestor 스캔 + 프롬프트
src/workbranch/main.sh                  # done) 디스패치
src/workbranch/usage.sh                 # done 도움말
src/workbranch/commands/completion.sh   # done 커맨드/인자 보완
scripts/workbranch-sources.txt          # archive.sh / done.sh 등록
AGENTS.md, 생성 AGENTS guidance, README(EN/KO)  # 신형 Plan 컨벤션 + done/archive 문서화

# Companion (Swift)
companion/Sources/CompanionApp/Views/RowView.swift   # renderablePlans → 현재 Plan만

# Tests
tests/cases/current-plan-brief.sh       # 파서(# H1/status:) + active/current Plan JSON contract
tests/cases/plan-archive.sh             # archive_current_plan + done command + no activity-log write + remove rm -rf
tests/cases/plan-archive-triggers.sh    # land/finalize/pull archive prompts and repo-filtered merge detection
companion/Sources/CompanionCoreTestRunner/CompanionCoreTestRunnerTests.swift  # 현재-Plan 선택(필요 시)
```

## 구현 작업 (TDD: 먼저 빨갛게)

### Slice A — brief 파서 신형 `# <plan>` (CLI)
- red: `tests/cases/current-plan-brief.sh`에 (1) `# A`/`# B` 2개 Plan → `plans` 길이 2, 각 `title`/`index`/`items`/progress, (2) `status:` 줄 명시 시 그 상태, 없으면 Step 파생, (3) `## Notes` 항목이 Step으로 안 잡힘, (4) 최상단 `status:`/`plan:`는 무시(클린 브레이크), (5) 코드펜스 내부 무시, (6) top-level JSON `status`/`progressDone`/`progressTotal`/`currentItem`/`items`가 active Plan 기준임을 추가한다.
- green: `task_load_plans`를 `## Plan:` → `^#[[:space:]]+`(H1) 구분자로 개정. Plan 바로 아래 `status:` 파싱 추가, 없으면 기존 파생 사용. `## Notes`/`##` 헤딩에서 Plan 종료.
- 검증: `bash -n`, 해당 테스트 red→green, `./tests/run.sh`.

### Slice B — archive 함수 (CLI)
- red: `tests/cases/plan-archive.sh`에 (1) 현재 Plan이 `.workbranch/plans/done/<ts>-<slug>.md`로 frontmatter + 본문 생성(archive 본문 status는 done), (2) brief에서 해당 Plan 블록 제거, (3) slug 정규화/충돌 suffix, (4) Plan 없음 시 에러, (5) archive 함수가 `activity.jsonl`을 생성/수정하지 않음을 추가한다.
- green: `lib/archive.sh::archive_current_plan <task> <completed_via>` 구현(타임스탬프, slug, frontmatter, brief 재작성). `scripts/workbranch-sources.txt` 등록.
- 검증: `bash -n`, 테스트, `./tests/run.sh`.

### Slice C — `done` 명령 (CLI)
- red: `tests/cases/plan-archive.sh`에 `workbranch done <task>`가 현재 Plan을 done 처리+archive 생성+brief 갱신, 명시 호출이라 무프롬프트, archive 경로 출력을 추가한다.
- green: `commands/done.sh::cmd_done`(검증 → `archive_current_plan "$task" done`). `main.sh`/`usage.sh`/`completion.sh` 등록.
- 검증: `bash -n`, 테스트, `./tests/run.sh`.

### Slice D — remove 완전 정리 (CLI)
- red: `tests/cases/plan-archive.sh`에 archive 파일이 있는 task `remove`(비-force, 비-TTY) 후 `.workbranch`가 잔존하지 않음을 추가한다.
- green: `remove_task_state_files`의 `rmdir "$state_dir"` → `rm -rf "$state_dir"`.
- 검증: `bash -n`, 테스트, `./tests/run.sh`.

### Slice E — land/finalize 자동 archive(프롬프트) (CLI)
- red: `tests/cases/plan-archive-triggers.sh`에 `land`/`finalize` 성공 후 현재 Plan이 있으면 프롬프트가 뜨고, y면 archive 생성(`completed_via: land`/`finalize`), n/비-TTY면 brief 유지를 추가한다.
- green: `execute_land_task` 성공 경로/`cmd_finalize` 끝에서 `prompt_read` 가드 후 `archive_current_plan`. 프롬프트/가드는 `prompt_delete_remaining_task_root` 패턴 재사용.
- 검증: `bash -n`, 테스트(`WORKBRANCH_ALLOW_NON_TTY_PROMPT`로 y/n 시뮬), `./tests/run.sh`.

### Slice F — pull merge 감지 + archive(프롬프트) (CLI)
- red: `tests/cases/plan-archive-triggers.sh`에 (1) repo filter 대상 전체에서 pull 전 task branch에 의미있는 커밋이 있고 pull 후 base ancestor이면 프롬프트→y→archive(`completed_via: pull`), (2) 커밋 0개 신규 브랜치는 trivial-ancestor false positive로 archive 안 됨, (3) ancestor 아님(squash 모사)이면 아무 동작 없음, (4) multi-repo에서 하나라도 미충족이면 프롬프트 없음, (5) `--repo <repo>`는 해당 repo만 평가를 추가한다.
- green: `commands/pull.sh`에 pre-pull meaningful-commit snapshot + post-pull ancestor 판정 헬퍼를 둔다. `run_pull`은 pull 전 대상 repo 상태를 캡처하고, pull 후 task 스캔에서 repo filter 대상 전체가 merged인 task에만 프롬프트 → archive를 실행한다.
- 검증: `bash -n`, 테스트, `./tests/run.sh`.

### Slice G — Companion 현재 Plan만 (CompanionApp)
- `RowView.renderablePlans`를 현재 Plan(첫 non-done, 없으면 마지막) 1개만 반환하도록 변경. 진행률/헤더/steps는 그 Plan 기준.
- 검증: `swift build` + `swift run CompanionCoreTestRunner`. 시각 검증은 "실행 결과"에 캡처 메모.

### Slice H — 템플릿/문서 동기화
- `write_default_task_brief`를 신형(`# <plan>` + `status:` + Step + `## Notes`)으로 갱신(EN/KO). `write_task_agent_guidance`/`AGENTS.md`에 "Plan은 `# <name>` H1, 그 아래 `status:`와 Step. 완료는 `done`(또는 land/finalize/pull 프롬프트)으로 archive" 규칙 반영. README EN/KO + `docs/architecture.md`/`companion/README.md` 동기화.
- 검증: `bash -n`, `./tests/run.sh`(신규 `current-plan-brief`/`plan-archive`/`plan-archive-triggers` 등록 포함), `git diff --check`.

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

- **Activity report 보존 범위:** 완료 Plan을 archive로 떼어내도 archive 전까지 Companion이 관측해 `activity.jsonl`에 남긴 Plan별 시간은 유지된다. archive/done CLI는 final `done` event를 직접 기록하지 않으므로, archive 직전 상태를 Companion이 관측하지 못한 경우 final status/progress row는 activity report에 없을 수 있다. 이는 v1 계약이며, 시간/history writer를 CLI로 넓히는 것은 후속 범위다.
- **planIndex 안정성:** 현재-only brief는 현재 Plan이 대개 index 0. 과거 Plan들은 각자 활동 당시 index 0으로 기록되었고 title이 다르므로 `(title, planIndex)` grouping에서 자연히 분리된다(0029의 index 이동 문제 완화).
- **클린 브레이크:** 구형 `## Plan:`/누적 형식 brief는 신형 파서에서 의도대로 안 풀린다. 기존 workspace는 1회 정리(현재 Plan만 남기고, 보존할 done 블록은 수동으로 `.workbranch/plans/done/`에 이동) 후 신형으로 전환.
- **companion 버전 차:** 라이브 표시 필터는 표시 레이어 변경이라 구버전 CLI와도 무해(현재 Plan만 고를 뿐).

## 미해결 / 후속

- **멀티 repo branch 표기:** archive frontmatter `branch`는 첫 repo 기준. repo별로 다른 task 브랜치를 쓰는 경우의 표기는 후속.
- **squash/rebase merge 자동 감지 불가:** ancestor 판정 한계. patch-id 기반 감지는 신뢰도가 낮아 범위 밖 — 사용자는 `done`으로 명시 처리.
- **archive 검색/열람 UI:** 현재는 파일 시스템 + Activity report(시간)만. archive 본문(Notes)을 companion에서 직접 열람하는 UI는 후속.
- **brief 빈 상태 UX:** 모든 Plan archive 후 brief가 비면 안내 주석/다음 Plan 템플릿 제시 여부는 사용 후 조정.

## 실행 결과

- [x] Slice A — `# <plan>` H1 파서 + per-plan `status:`(클린 브레이크)
- [x] Slice B — `archive_current_plan`(frontmatter + verbatim + brief 재작성)
- [x] Slice C — `done` 명령
- [x] Slice D — `remove` 완전 정리(`rm -rf .workbranch`)
- [x] Slice E — land/finalize 자동 archive(프롬프트)
- [x] Slice F — pull merge 감지 + archive(프롬프트)
- [x] Slice G — Companion 현재 Plan만 표시
- [x] Slice H — 템플릿/AGENTS/README 동기화

### 검증 기록

- [x] `/bin/bash -n bin/workbranch install.sh tests/run.sh`
- [x] `scripts/build-workbranch.sh`
- [x] `./tests/run.sh` — 257 tests passed
- [x] `cd companion && swift build && swift run CompanionCoreTestRunner` — build complete, runner PASS
- [x] `git diff --check`

### 수동/시각 검증 메모

- Companion은 `RowView.renderablePlans` 소스 invariant와 `CompanionCoreTestRunner`로 current Plan 선택 계약을 검증했다. macOS menu bar 앱을 실제로 열어 보는 시각 QA는 이번 tmux 실행 환경에서는 수행하지 않았다.
