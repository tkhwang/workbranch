# 0021 Companion task 진행도·계층 표시와 라이프사이클 자가치유 계획

> **agentic worker 지침:** 실행 시 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용한다. 동작 변경 전에는 `superpowers:test-driven-development` 흐름을 따른다.
> - Bash CLI: `src/workbranch/**`를 먼저 수정하고 `scripts/build-workbranch.sh`로 `bin/workbranch`를 재생성한다. `bin/workbranch`를 직접 수정하지 않는다. 검증은 syntax check → targeted tests → `./tests/run.sh` → `git diff --check` 순서.
> - Companion: 순수 로직(JSON decode, menu model 파생, 진행도/계층 렌더 데이터, config self-heal 판정)은 `CompanionCore`에 두고 TDD + `swift run CompanionCoreTestRunner` + `swift test`로 검증한다. FSEvents/`Process`/SwiftUI는 unit test하지 않는다. companion 코드는 `companion/**`에만 둔다.
> - CLI contract와 companion 대응은 **한 PR**로 landing해 schema drift를 막는다(0019 결정 계승).
>
> **시리즈 위치:** menu bar companion initiative의 후속 제품 단계다. 실행 순서는 **0015 memo/noti/json(완료) → 0019 native menu bar(완료) → 0020 brew 배포(완료) → 0021(이 계획)**. hard dependency는 0015의 `workbranch list --json`/`memo`와 0019의 companion 앱이다. 이 계획은 외부 배포 전 단계이므로 `list --json`의 **schemaVersion 1을 유지한 채** v1 contract에 진행도 필드를 additive로 확장한다.

**목표:** companion만 보면 "어떤 project의 어떤 repo에서 어떤 task가, 지금 연속 작업 중 어디쯤 진행되고 있는지"를 한눈에 파악할 수 있게 한다. 세 축으로 강화한다.

1. **UI 계층** — Project → Task → Repo 3단 계층으로 task별 repo/branch/dirty를 펼쳐 보여준다.
2. **진행도** — task 메모를 markdown 체크리스트 기반으로 정형화해 `status`(단계)와 `done/total`(진행률), "지금 하는 일"(첫 미체크 항목)을 companion에 노출한다.
3. **라이프사이클 자가치유** — `workbranch remove`가 task root의 비추적 파일까지 깔끔히 정리할 경로를 제공하고, workbranch를 거치지 않고 configured project root가 수동 삭제된 경우 companion이 에러를 계속 내지 않고 스스로 정리한다.

**아키텍처:** companion은 여전히 presentation-only client다(0019 계승). 상태는 `workbranch list --json` pull이 유일한 source of truth, 변경 감지는 FSEvents push. 이 계획은 (a) 기존 JSON contract(v1)에 진행도 필드를 추가하고, (b) CompanionCore의 menu model 파생에 repo child row와 진행도 렌더를 추가하며, (c) configured project root 부재(true deletion) 판정과 config self-heal 로직을 CompanionCore에 추가한다. 메모 정형은 새 파일 타입이 아니라 **기존 `TASK-WORKBRANCH.md`의 markdown 관례**로 표현하고 CLI가 파싱한다 — 사람/agent는 체크박스만 켜고 끄면 된다.

**기술 스택:** portable Bash + generated single-file CLI + `tests/run.sh`(python3 JSON assertion). Swift 5.9+ / SwiftUI `MenuBarExtra` / CompanionCore + `CompanionCoreTestRunner` + `swift test` build check. 기존 `.workbranch.config`, `TASK-WORKBRANCH.md`, `AGENTS.md` 관례.

**제품 관점:** git branch는 구현 세부, task memo가 "이 task가 무엇이고 지금 어디쯤인가"를 말한다(0015 계승). 0015가 "무엇"을 줬다면 0021은 "어디쯤"을 준다. 핵심 UX는 한 줄에 `상태 아이콘 · 한줄요약 · n/m` + 보조 줄 "지금: 현재 단계"다.

---

## 문제

0019로 companion이 task 목록·memo title·noti·dirty를 보여주지만, 다음이 비어 있다.

- **계층:** repo/branch가 task row의 `●`(dirty) 한 점으로만 합쳐져, 멀티 repo task에서 어떤 repo가 어느 branch/상태인지 안 보인다.
- **진행도:** memo가 "제목 한 줄"뿐이라 task가 시작 단계인지 거의 끝났는지, 지금 무슨 단계를 하는지 알 수 없다. 연속 작업의 위치 감각이 없다.
- **라이프사이클:**
  - `workbranch remove`(정상 경로)는 worktree/branch/workbranch-owned state만 지우고 task root에 남은 비추적 파일(`.omx/`, `.DS_Store`, IDE 파일 등)이 있으면 `rmdir` 실패로 디렉토리가 잔존한다. 사용자 파일 보존(0015 결정)은 옳지만, "툴이 만든 잔여물"까지 남겨 깔끔히 못 지우는 경로가 없다.
  - workbranch를 거치지 않고 폴더를 직접 지우면, task 단위 삭제는 `list --json`에서 자연 소멸하지만 companion config에 등록된 **project root 자체가 사라지면** `list --json`이 실패해 companion이 stale 캐시 + Error row를 계속 띄운다("무조건 error" 증상).

## 현재 repo 근거

- `src/workbranch/commands/list.sh` `cmd_list_json`: `schemaVersion:1`, task별 `name/path/memoTitle/notiCount/repos[]`, repo별 `name/branch/dirty`를 출력한다. network/Git fetch 없이 `git status --porcelain`만 사용(0015 결정).
- `src/workbranch/lib/task-state.sh`:
  - `task_brief_path` = `<task>/TASK-WORKBRANCH.md`, `task_brief_title`은 첫 non-empty line에서 선행 `#`만 제거해 반환.
  - `write_default_task_brief`(초기 템플릿), `write_task_agent_guidance`(`<task>/AGENTS.md`), `noti_count`, `remove_task_state_files`.
- `src/workbranch/commands/remove.sh`: 정상 경로는 worktree remove → branch delete → `.workbranch.task` 삭제 → `remove_task_state_files` → `rmdir`(비었을 때만). **stale 경로**(`is_stale_task_directory_path`)만 `remove_stale_task_directory_path`에서 `rm -rf`로 통째 삭제 — 두 경로 cleanup 강도가 불일치.
- `companion/Sources/CompanionCore/Models.swift`: `WorkbranchListDocument`가 `schemaVersion == 1`이 아니면 `unsupportedSchemaVersion`으로 **하드 거부**. `WorkbranchTask`는 `name/path/memoTitle/notiCount/repos`.
- `companion/Sources/CompanionCore/MenuState.swift`: `MenuState.make`가 root별 section, task별 `MenuRow` 1개를 만든다. `row(for:)`가 title 문자열에 `name — memoTitle 🔔n ●`를 합친다. repo는 dirty 여부 집계로만 쓰인다. `MenuRowKind`는 `task/message/error`.
- `companion/Sources/CompanionApp/StateStore.swift`: root별 `list --json`을 detached로 실행, 실패 시 `previous?[root]` stale 유지 + error row. config는 `CompanionConfig`(roots)로 로드만 한다.
- `companion/Sources/CompanionApp/RootWatcher.swift`: root/config FSEvents watcher.
- 0019 지침: CompanionCore의 menu model 파생은 TDD 대상, IO는 제외.

## 결정 사항

### 메모 포맷 (markdown 관례, 새 파일 없음)

- [x] **`TASK-WORKBRANCH.md` 정형:** 첫 `#` 헤딩 = 한줄 요약(제목). 선택적 `status:` 줄 = 단계 enum. `- [ ]`/`- [x]` 체크리스트 = 작업 단계.
  - 예:
    ```markdown
    # companion 연동 강화

    status: in-progress

    - [x] JSON 스키마 v1 additive 확장 설계
    - [x] companion 계층 렌더
    - [ ] 라이프사이클 자동 정리
    - [ ] 메모 진행도 파싱
    ```
  - 이유: 순수 markdown이라 사람/agent가 자연스럽게 유지하고, companion은 파싱만 한다. `memoTitle`(첫 헤딩) 로직을 그대로 재사용.

- [x] **status enum:** `planning | in-progress | review | blocked | done`.
  - `status:` 줄이 있으면 그 값(허용 enum만, 그 외는 `in-progress`로 강등하지 않고 raw 노출 없이 빈 status 처리)을 쓴다.
  - 없으면 체크리스트로 도출: total==0 → `planning`, done==total && total>0 → `done`, 그 외 → `in-progress`.
  - `blocked`/`review`는 체크리스트로 추론 불가하므로 그때만 명시한다.
  - 이유: 평소엔 체크박스만 켜면 status가 따라오고, 예외 상태만 손으로 적는다.

- [x] **진행도 카운트 = 완료/전체(`done/total`).** (미세결정 확정: 추천안 A)
  - `done` = `- [x]`/`- [X]` 줄 수, `total` = `- [ ]`+`- [x]` 줄 수.
  - 이유: 표준적이고 "지금 하는 일" 보조 줄과 합치면 현재 위치도 동시에 표현된다.

- [x] **"지금 하는 일" = 첫 번째 `- [ ]` 미체크 항목 텍스트(`currentItem`).** companion 보조 줄로 표시한다. (미세결정 확정)
  - total==0이거나 전부 완료면 빈 문자열.

- [x] **status 표기 문법 = 본문 분리된 `status: <enum>` 한 줄.** 제목 인라인이 아니다. (미세결정 확정)
  - 파싱: 첫 헤딩 이후, 첫 체크박스 이전 구간에서 `^[[:space:]]*status:[[:space:]]*<token>` 매칭(대소문자 무시).

### JSON contract

- [x] **결정: `workbranch list --json`은 schemaVersion 1을 유지한다.** task에 `status`, `progressDone`, `progressTotal`, `currentItem` 4개 flat 필드를 v1에 additive로 추가한다. 기존 `memoTitle`/`notiCount`/`repos`는 유지.
  - flat 필드(중첩 객체 아님)로 둬 Bash 출력과 Swift decode를 단순화한다.
  - 이유: 아직 외부 배포 전이라 v2 호환 레이어를 만들 필요가 없고, companion/CLI를 한 PR로 landing해 schema drift를 막을 수 있다. companion이 진행도 표시를 위해 markdown 파싱을 재구현하지 않게 하되 CLI가 유일 contract(0019 계승)라는 원칙은 유지한다.

- [x] **companion은 schemaVersion 1만 수용한다.** 새 필드는 decode 기본값(빈 status/0/빈 문자열)을 제공해 기존 v1 fixture/구포맷 task가 깨지지 않게 한다.
  - 이유: schemaVersion bump는 breaking-change 신호로 남겨두고, 이번 변경은 외부 배포 전 v1 contract의 additive 정착으로 처리한다. 향후 v2가 필요해질 때 별도 계획에서 1|2 호환 정책을 다시 설계한다.

### UI 계층 (Project → Task → Repo)

- [x] **계층 방향 = Project → Task → Repo.** (workbranch 실제 모델 `task→repos`와 일치)
  - section = project, task row 아래에 repo child row를 들여쓰기해 `[+] <repo>  <branch>  <dirty?●>` 형태로 표시.
  - 이유: 멀티 repo task에서 repo별 branch/상태가 보여야 하고, 모델 변환이 없어 단순하다. (mockup의 repo-위-task 역전은 멀티 repo에서 task 중복을 유발해 채택하지 않음.)

- [x] **repo child row는 CompanionCore의 `MenuState.make`가 생성한다.** `MenuRowKind`에 `.repo`를 추가하고 task row 뒤에 child row를 emit한다.
  - 이유: 렌더 데이터 파생을 unit test 가능하게 유지(0019 지침). SwiftUI 뷰는 들여쓰기만 담당.
  - 단일 repo task도 일관성을 위해 repo row를 emit한다(접기 최적화는 후속).

- [x] **task row 표면 = `<상태아이콘> <memoTitle> <notiCount?🔔n> <progress?n/m>`, 보조 줄 = `지금: <currentItem>`.**
  - 상태 아이콘: `planning ⚪ / in-progress 🟡 / review 🔵 / blocked 🔴 / done ✅`, status 빈 값이면 아이콘 생략.
  - `progress`는 total>0일 때만 `n/m` 표기.

### 라이프사이클

- [x] **결정: `workbranch remove <task>`는 known generated task-state를 정리한 뒤, unknown 잔여 항목이 있으면 warning + 남은 항목 목록을 보여주고 즉시 삭제 여부를 묻는다.** (결정 확정)
  - known generated task-state: `TASK-WORKBRANCH.md`, generated `AGENTS.md`, `.workbranch/`, `.omx/`, `.omc/`.
  - normal remove에서 unknown 잔여 항목이 없으면 task root를 삭제한다.
  - normal remove에서 unknown 잔여 항목이 있으면 warning + 남은 항목 목록을 출력한 뒤 `남은 항목까지 지금 삭제할까요? [y/N]` 형태로 즉시 묻는다. 기본값은 보존(`No`)이고, 사용자가 확인하면 같은 command flow 안에서 task root 전체를 삭제한다. non-interactive stdin에서는 prompt를 띄우지 않고 보존한다.
  - `--force`는 묻지 않고 worktree/branch 제거 후 task root 전체를 `rm -rf`로 삭제한다(stale 경로와 강도 일치).
  - 이유: `remove <task>`는 task lifecycle 종료 의도이므로 agent/runtime 잔여물까지 기본 정리하되, 이름을 모르는 사용자 파일은 목록과 확인 prompt로 보호한다. `--force`는 확인 없는 전체 삭제 경로로 둔다.

- [x] **companion configured project root self-heal:** companion config의 `roots[]`에 등록된 project root가 **true deletion**(부모 디렉토리는 존재하나 project root 자체가 부재)으로 연속 2회 판정되면 config에서 자동 제거 + 1회 알림. (결정 확정: A)
  - unmount/네트워크 부재(부모까지 부재)는 삭제로 보지 않고 "unavailable" 표시만(config 유지).
  - 오삭제 방지 grace: refresh 실패가 "project root 경로 ENOENT"이고 부모가 존재할 때만 forget 후보로 보고, 연속 2회(또는 watcher 이벤트 + 다음 refresh) 확인 시 실제 제거.
  - 이유: 사용자가 companion config에 등록된 project root 폴더를 수동 삭제한 경우 에러를 영구히 띄우지 않고 스스로 정리하되(요구사항), 일시적 부재로 config를 파괴하지 않는다. `<task>` 수동 삭제는 `list --json`에서 자연 소멸하며 config를 수정하지 않고, `<task>/<repo>` 삭제는 partial/stale task 상태로 다룬다.

- [x] **task 단위 수동 삭제는 별도 처리 불필요.** `<task>` 폴더 수동 삭제는 `list --json`이 사라진 task를 자연히 빼고, companion이 해당 project root만 갱신하면 row가 소멸한다(현행 동작 확인 + 테스트로 고정). `<task>/<repo>` 삭제는 project root self-heal 대상이 아니며 partial/stale workspace 진단 영역이다.

### 가이드/템플릿 동기화

- [x] **결정: status update 자동화는 hook adapter가 아니라 generated `AGENTS.md`의 명시적 protocol로 처리한다.** (결정 확정)
  - Claude Code와 Codex는 hook 설정 형식과 이벤트 surface가 다르므로, 0021에서 runtime-specific hook adapter를 생성하지 않는다.
  - 이번 범위는 task root의 generated `AGENTS.md`와 `TASK-WORKBRANCH.md` 템플릿에 status update protocol을 강하게 명시하는 것으로 제한한다.
  - 후속에서 실제 runtime hook adapter가 필요해지면 Claude Code/Codex별 별도 계획으로 분리한다.

- [x] **`write_task_agent_guidance`(`AGENTS.md`)와 `write_default_task_brief`(`TASK-WORKBRANCH.md` 템플릿)를 새 메모 포맷과 status update protocol로 갱신한다.** 같은 포맷 정의를 가이드·템플릿·companion 파서 세 곳이 공유한다.
  - 기존 task의 파일은 마이그레이션하지 않는다(다음 `add`부터 적용, 기존은 agent가 점진 갱신). 구포맷도 파서가 호환되게 둔다(헤딩=제목, 체크박스 없으면 total=0).
  - generated `AGENTS.md`는 다음 시점에 `TASK-WORKBRANCH.md`를 갱신하라고 요구한다: 의미 있는 작업 시작/재개, active step 변경, 검증 시작 전, 검증 결과 확인 후, blocked 감지, final response 직전.
  - update 규칙: `status:`를 `planning | in-progress | review | blocked | done` 중 하나로 유지하고, checklist는 작고 실행 가능한 단계로 두며, 완료 항목은 즉시 `[x]`로 바꾸고, 첫 미체크 항목이 현재/다음 작업을 나타내게 한다.

## public contract

### `workbranch list --json` (schemaVersion 1 additive 확장)

```json
{
  "schemaVersion": 1,
  "project": "workbranch",
  "root": "/abs/path",
  "tasks": [
    {
      "name": "feat-cowork-with-companion",
      "path": "/abs/path/feat-cowork-with-companion",
      "memoTitle": "companion 연동 강화",
      "status": "in-progress",
      "progressDone": 2,
      "progressTotal": 4,
      "currentItem": "라이프사이클 자동 정리",
      "notiCount": 2,
      "repos": [
        {"name": "workbranch", "branch": "feature/cowork-with-companion", "dirty": true}
      ]
    }
  ]
}
```

- `status`: 허용 enum 또는 빈 문자열. network/Git fetch 없이 파일 파싱만.
- `progressDone`/`progressTotal`: 정수. 체크박스 없으면 둘 다 0.
- `currentItem`: 첫 미체크 항목 텍스트 또는 빈 문자열. JSON escape 적용.
- 기존 필드/규칙(stale·partial task 제외, dirty=porcelain) 유지.

### `TASK-WORKBRANCH.md` 포맷 (사람/agent contract)

```markdown
# <한줄 요약>

status: <planning|in-progress|review|blocked|done>   # 선택, 생략 시 체크박스로 도출

- [ ] 단계 1
- [x] 단계 2
```

### `workbranch remove`

```bash
workbranch remove <task>            # known generated state 정리, unknown 잔여 항목은 목록 안내 후 즉시 삭제 여부 prompt
workbranch remove <task> --force    # prompt 없이 worktree/branch 제거 후 task root 전체 rm -rf
```

## 파일 구조

```text
# Bash CLI
src/workbranch/lib/task-state.sh        # task_status, 체크리스트 카운트, current item helper 추가
src/workbranch/commands/list.sh         # --json v1 additive 필드 출력
src/workbranch/commands/remove.sh       # normal remove 잔여 항목 즉시 삭제 prompt, --force full rm -rf
src/workbranch/lib/task-state.sh        # write_default_task_brief / write_task_agent_guidance 포맷 갱신
README.md / README.ko.md                # 메모 포맷 + remove --force 문서화
docs/specs/0001-workbranch-mvp.md       # contract 갱신(해당 시)

tests/cases/list-json.sh                # v1 additive shape, status 도출, 진행도, currentItem
tests/cases/memo.sh                     # 포맷 파싱(체크박스/ status 줄)
tests/cases/remove.sh                   # normal prompt cleanup, --force full cleanup
tests/cases/add.sh                      # 새 템플릿/가이드 생성
tests/run.sh

# Companion
companion/Sources/CompanionCore/Models.swift        # schemaVersion 1 유지, 새 필드 기본값
companion/Sources/CompanionCore/MenuState.swift     # .repo row kind, 진행도/상태 렌더 데이터
companion/Sources/CompanionApp/Views/CompanionPopoverView.swift  # repo 들여쓰기, 보조 줄
companion/Sources/CompanionApp/StateStore.swift     # configured project root self-heal 트리거
companion/Sources/CompanionCore/Config.swift        # root 제거(저장) 지원
companion/Sources/CompanionCoreTestRunner/main.swift # decode, menu model, self-heal 판정 behavioral tests
companion/Tests/CompanionCoreTests/*.swift          # swift test placeholder/build check
```

## 구현 작업

### Task 1: 메모 포맷 파서 helper (`task-state.sh`)

- [x] RED: `test_task_status_explicit_and_derived` — `status:` 줄 우선, 없으면 체크박스로 도출(planning/in-progress/done).
- [x] RED: `test_task_checklist_counts` — `- [ ]`/`- [x]`/`- [X]` 카운트, 코드블록·비체크 라인 무시.
- [x] RED: `test_task_current_item` — 첫 미체크 항목 텍스트, 전부 완료/0개면 빈 문자열.
- [x] GREEN: `task_status`, `task_checklist_counts`(done/total 출력), `task_current_item` 구현. `task_brief_title` 재사용.
- [x] 검증: `scripts/build-workbranch.sh`, targeted tests.

### Task 2: `list --json` v1 additive 확장

- [x] RED: `test_list_json_schema_v1_progress_shape` — `schemaVersion:1` 유지 + 새 4필드 존재.
- [x] RED: `test_list_json_progress_and_status` — 메모 fixture로 status/done/total/currentItem 값 검증.
- [x] RED: `test_list_json_currentItem_escaped` — 특수문자 escape.
- [x] RED: `test_list_json_legacy_memo_no_checkboxes` — 체크박스 없는 구포맷에서 total=0, status=planning, currentItem="".
- [x] GREEN: `cmd_list_json`에 필드 추가. no-color/no-log 유지.
- [x] 검증: build, list targeted tests.

### Task 3: remove 라이프사이클

- [x] RED: `test_remove_cleans_known_generated_task_state` — normal remove가 `TASK-WORKBRANCH.md`, generated `AGENTS.md`, `.workbranch/`, `.omx/`, `.omc/`를 삭제.
- [x] RED: `test_remove_prompts_before_deleting_unknown_task_root_files` — unknown 잔여 항목이 있으면 warning + 남은 항목 목록 + 같은 command flow 안의 삭제 여부 prompt.
- [x] RED: `test_remove_keeps_unknown_files_when_prompt_declined` — prompt 기본값/No는 unknown 파일과 task root 보존.
- [x] RED: `test_remove_noninteractive_unknown_files_keeps_without_prompt` — non-interactive stdin에서는 묻지 않고 unknown 파일과 task root 보존.
- [x] RED: `test_remove_deletes_unknown_files_when_prompt_confirmed` — prompt Yes는 같은 command flow 안에서 task root 전체 삭제.
- [x] RED: `test_remove_force_purges_without_prompt` — `remove --force`는 `.omx/`/unknown 파일이 있어도 묻지 않고 디렉토리를 완전 제거.
- [x] RED: `test_manual_task_dir_delete_vanishes_from_json` — task dir 수동 삭제 후 `list --json`에서 제외.
- [x] GREEN: `cmd_remove` normal immediate prompt cleanup + force full `rm -rf` 구현.
- [x] 검증: build, remove/list targeted tests.

### Task 4: add 템플릿/가이드 갱신

- [x] RED: `test_add_writes_formatted_brief` — 새 `TASK-WORKBRANCH.md`가 `#`/`status:`/체크박스 형태.
- [x] RED: `test_add_agents_md_describes_format` — `AGENTS.md`가 메모 포맷 규칙을 포함.
- [x] RED: `test_add_agents_md_describes_status_update_protocol` — `AGENTS.md`가 갱신 시점(시작/재개, active step 변경, 검증 전후, blocked, final response 직전)과 checklist/status 규칙을 포함.
- [x] GREEN: `write_default_task_brief`, `write_task_agent_guidance` 갱신. Claude Code/Codex hook adapter 생성은 scope 밖.
- [x] 검증: build, add tests.

### Task 5: completion/docs/build

- [x] `usage.sh`/README/README.ko에 메모 포맷·`remove --force` 반영.
- [x] `scripts/workbranch-sources.txt` 갱신(신규 source 시).
- [x] `bin/workbranch` rebuild.
- [x] 검증: `/bin/bash -n bin/workbranch install.sh tests/run.sh`, targeted tests.

### Task 6: CompanionCore decode (v1 additive fields)

- [x] RED: `test_decode_schema_v1_full_progress` — v1 JSON에서 새 필드 decode.
- [x] RED: `test_decode_schema_v1_defaults` — 새 필드가 없는 기존 v1 JSON에서 기본값(빈 status/0/빈 문자열), 거부하지 않음.
- [x] RED: `test_decode_rejects_unsupported_version` — 0/2 등은 명확한 에러(schemaVersion 1만 수용).
- [x] GREEN: `WorkbranchListDocument`/`WorkbranchTask`에 새 필드 기본값 + v1 유지 로직.
- [x] 검증: `swift run CompanionCoreTestRunner`, `swift test`.

### Task 7: CompanionCore menu model (계층 + 진행도)

- [x] RED: `test_menu_emits_repo_child_rows` — task row 뒤에 repo별 `.repo` row, branch/dirty 포함.
- [x] RED: `test_menu_task_row_shows_status_and_progress` — 상태 아이콘 + `n/m` + 보조 `지금:` 데이터.
- [x] RED: `test_menu_status_icon_mapping` — enum→아이콘, 빈 status 시 아이콘 생략.
- [x] RED: `test_menu_no_checklist_hides_progress` — total==0이면 진행도/보조 줄 생략.
- [x] GREEN: `MenuRowKind.repo`, `row(for:)` 확장, repo child row emit.
- [x] 검증: `swift run CompanionCoreTestRunner`, `swift test`.

### Task 8: Companion config self-heal

- [x] RED: `test_project_root_true_deletion_is_forget_candidate` — 부모 존재 + configured project root 부재 → forget 후보.
- [x] RED: `test_project_root_parent_missing_is_unavailable_not_forget` — 부모까지 부재(unmount) → 보존, unavailable.
- [x] RED: `test_task_delete_does_not_remove_config_root` — `<task>` 삭제는 list row 자연 소멸만 확인하고 config root 제거 없음.
- [x] RED: `test_repo_worktree_delete_does_not_remove_config_root` — `<task>/<repo>` 삭제는 project root self-heal 대상이 아님.
- [x] RED: `test_config_remove_root_persists` — `CompanionConfig`에서 root 제거 후 저장 round-trip.
- [x] GREEN: self-heal 판정 함수(CompanionCore) + `CompanionConfig` root 제거/저장. `StateStore`가 연속 2회 true deletion 판정 결과로 reloadConfig + 1회 알림.
- [x] 검증: `swift run CompanionCoreTestRunner`, `swift test`.

### Task 9: Companion 뷰

- [x] `CompanionPopoverView`: repo child row 들여쓰기, task 보조 줄(`지금:`), 상태 아이콘/진행도 렌더. self-heal 알림 표면.
- [ ] 수동 스모크: 멀티 task root에서 진행도/계층 표시, configured project root 폴더 삭제 시 자동 forget + 알림 확인. (미실행: CLI 환경에서 메뉴바 GUI 상호작용 관찰 불가; CompanionCore runner + app build로 대체 검증)

## 최종 검증

- [x] `scripts/build-workbranch.sh`
- [x] `/bin/bash -n bin/workbranch install.sh tests/run.sh`
- [x] `./tests/run.sh`
- [x] `cd companion && swift run CompanionCoreTestRunner`
- [x] `cd companion && swift test`
- [x] `git diff --check`
- [x] README/README.ko/spec 동기화
- [ ] 수동 스모크: companion이 Project→Task→Repo 계층 + 상태/진행도/지금 줄을 표시하고, configured project root 수동 삭제 시 self-heal한다. (미실행: CLI 환경에서 메뉴바 GUI 상호작용 관찰 불가; CompanionCore runner + app build로 대체 검증)

## 미해결/후속

- [ ] Claude Code/Codex runtime-specific hook adapter — 0021에서는 생성하지 않고, generated `AGENTS.md` protocol로 충분하지 않을 때 별도 계획으로 검토.
- [ ] 단일 repo task에서 repo row 접기(자동 collapse) 최적화 — 본 계획은 항상 emit, UX 확인 후 후속.
- [ ] 진행도 막대(`▓▓░░`) 시각화 여부 — 우선 `n/m` 텍스트, 후속에서 검토.
- [ ] notification producer hook 자동 wiring(0015 후속 항목)과의 결합 — 별도 계획 유지.
- [ ] 구포맷 task 일괄 마이그레이션 명령(`workbranch memo --migrate` 등) 필요 시 후속.

### 검증 메모

- 2026-06-13: `scripts/build-workbranch.sh`, `/bin/bash -n ...`, `./tests/run.sh`(223 tests), `swift run CompanionCoreTestRunner`, `swift test`, `companion/scripts/build-app.sh`, `git diff --check` 통과. 현재 task root에서 `workbranch list --json` v1 progress 필드 출력 smoke 확인. 메뉴바 GUI 클릭 smoke는 이 CLI 실행 환경에서 관찰할 수 없어 미실행.
