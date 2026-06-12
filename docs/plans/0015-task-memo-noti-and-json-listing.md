# 0015 Task 메모, 알림, JSON 목록 계획

> **agentic worker 지침:** 이 계획을 실행할 때는 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용한다. 동작 변경 전에는 `superpowers:test-driven-development` 흐름을 따른다. 코드는 `src/workbranch/**`를 먼저 수정하고 `scripts/build-workbranch.sh`로 `bin/workbranch`를 재생성한다. 검증은 syntax check, targeted tests, `./tests/run.sh`, `git diff --check` 순서로 한다. `bin/workbranch`를 직접 수정하지 않는다.
>
> **시리즈 위치:** menu bar companion initiative의 첫 번째 핵심 CLI 계약이다. 0016 focus/open-warp 계획은 제거되었고, 현재 실행 순서는 **0015 → 0019 (native app, superseding 0017) → 0018 (re-written with cask/native assumptions)**이다. 0018은 companion 공개 배포가 필요할 때만 실행하며, 이제 cask/native 변경을 전제로 한다.

**목표:** task별 사람이 읽고 고칠 수 있는 작업 메모(`workbranch memo`, `<task>/TASK-WORKBRANCH.md`), task 알림 inbox(`workbranch noti`, `<task>/.workbranch/notifications.jsonl`), 그리고 companion이 소비할 안정적인 `workbranch list --json` 출력을 추가한다.

**아키텍처:** task 상태는 repo worktree 밖의 task root에 둔다. 메모는 `<task>/TASK-WORKBRANCH.md`, agent 안내는 `<task>/AGENTS.md`, 알림은 `<task>/.workbranch/notifications.jsonl`에 저장한다. `workbranch add`가 task directory와 기본 상태 파일을 만들고, `workbranch remove`는 workbranch가 소유한 task 상태만 정리하되 사용자가 만든 임의 파일은 보존한다. JSON 출력은 `cmd_list`의 별도 early branch로 처리해 기존 human list 출력과 섞지 않는다.

**기술 스택:** portable Bash, `.workbranch.config`, generated single-file CLI, `tests/run.sh` integration tests, `python3` JSON assertion.

**제품 관점:** companion의 핵심 데이터 계약이다. Git branch 이름은 구현 세부사항이고, task memo/noti가 “이 task가 무엇이고 지금 어떤 상태인가”를 설명한다.

---

## 문제

여러 task workspace를 동시에 열면 Git 상태만으로는 각 workspace의 목적과 다음 행동을 알 수 없다. task별 작업 의도는 사람이/agent가 갱신하는 메모가 필요하고, agent/build 이벤트는 task별 inbox가 필요하다. 또한 companion, Raycast, script가 사용할 수 있는 machine-readable task 목록이 필요하다.

## 현재 repo 근거

- `src/workbranch/commands/list.sh`는 사람이 읽는 colored output만 만든다.
- `src/workbranch/lib/task-metadata.sh`는 task-scoped metadata 선례다.
- `src/workbranch/lib/task-identity.sh`는 task 이름 검증/해결을 제공한다.
- 테스트는 `tests/run.sh`와 `tests/cases/*.sh`의 Bash integration harness를 사용한다.
- `remove`는 repo worktree와 `.workbranch.task`를 제거한 뒤 task dir `rmdir`을 시도한다. 따라서 workbranch-owned task state cleanup 규칙이 필요하다.

## 결정 사항

- [x] **task brief 위치:** `<task>/TASK-WORKBRANCH.md`.
  - 이유: repo 밖 task root에 있어 repo `.gitignore`를 건드리지 않고 editor/agent가 쉽게 찾는다.

- [x] **agent guidance 위치:** `<task>/AGENTS.md`.
  - 이유: task root 또는 repo folder에서 작업하는 agent에게 같은 task brief를 갱신하라는 규칙을 주입한다.

- [x] **notification 위치:** `<task>/.workbranch/notifications.jsonl`.
  - 이유: append-only machine data이므로 숨김 task state 아래에 둔다.

- [x] **`list --json`은 public frontend contract다.**
  - 이유: companion이 config parsing과 Git 상태 판단을 재구현하지 않고 CLI만 호출한다. shape 변경은 breaking change다.

- [x] **JSON path에서 network/Git fetch 금지.**
  - 이유: companion은 주기적으로 poll한다. dirty 여부는 `git status --porcelain`만 사용한다.

- [x] **memo cwd inference는 읽기 전용으로 제한한다.**
  - 결정: task workspace 안에서는 `workbranch memo`가 현재 task brief를 읽는다. 쓰기/삭제는 항상 explicit task가 필요하다.
  - 이유: 빠른 읽기는 허용하되 실수로 다른 task 메모를 덮어쓰지 않는다.

- [x] **remove cleanup 정책.**
  - 결정: `TASK-WORKBRANCH.md`, generated `AGENTS.md`, `.workbranch/notifications.jsonl`, 빈 `.workbranch/`는 successful remove 후 삭제한다. `notes.txt` 같은 사용자 파일은 보존한다.

- [x] **JSON task eligibility.**
  - 결정: `list --json`은 registered task workspace만 포함한다. stale/partial task-shaped directory는 companion-facing JSON에서 제외한다.

- [x] **notification producer/consumer 경계.**
  - 결정: `workbranch noti add`와 agent hook이 producer, companion은 consumer/clearer다. 자동 hook wiring은 후속 계획이다.

## public contract

### `workbranch memo`

```bash
workbranch memo <task>
workbranch memo <task> "작업 메모"
workbranch memo <task> --clear
# task workspace 내부에서 읽기만 생략 가능
workbranch memo
```

- 메모 파일: `<task>/TASK-WORKBRANCH.md`
- 첫 번째 non-empty line이 `memoTitle`이 된다.
- unknown task는 `Cannot memo: unknown task 'task9'` 형태로 실패한다.

### `workbranch noti`

```bash
workbranch noti add <task> "tests passed"
workbranch noti list <task>
workbranch noti clear <task>
```

- 저장 파일: `<task>/.workbranch/notifications.jsonl`
- 한 줄 shape: `{"ts":"<ISO8601>","text":"..."}`
- missing file은 empty inbox로 취급한다.

### `workbranch list --json`

stdout은 log/color 없이 JSON 하나만 출력한다.

```json
{
  "schemaVersion": 1,
  "project": "monask-fullstack",
  "root": "/abs/path",
  "tasks": [
    {
      "name": "task3",
      "path": "/abs/path/task3",
      "memoTitle": "draft-tree 가이드 작성",
      "notiCount": 2,
      "repos": [
        {"name": "backend", "branch": "feature/cpq-task3", "dirty": true}
      ]
    }
  ]
}
```

## 파일 구조

```text
src/workbranch/lib/task-state.sh        # task state path, memo title, noti count, json_escape
src/workbranch/commands/memo.sh         # cmd_memo
src/workbranch/commands/noti.sh         # cmd_noti
src/workbranch/commands/list.sh         # --json early branch
src/workbranch/main.sh                  # memo/noti route
src/workbranch/usage.sh                 # usage 문구
scripts/workbranch-sources.txt          # bundle source order
bin/workbranch                          # build script로만 재생성

tests/cases/memo.sh
tests/cases/noti.sh
tests/cases/list.sh
tests/cases/remove.sh
tests/cases/completion.sh
tests/run.sh

README.md
README.ko.md
docs/specs/0001-workbranch-mvp.md
```

## 구현 작업

### Task 1: `task-state.sh` helper와 `memo` 명령

- [x] RED: `test_memo_set_show_clear`.
  - `workbranch memo login "publish API 구현"`이 `login/TASK-WORKBRANCH.md`를 쓴다.
  - `workbranch memo login`이 내용을 출력한다.
  - `workbranch memo login --clear`가 파일을 제거한다.
- [x] RED: `test_memo_rejects_unknown_task`.
- [x] RED: `test_memo_resolves_task_from_cwd`.
- [x] RED: `test_add_creates_task_brief_and_agent_guidance`.
- [x] GREEN: `task_brief_path`, `task_brief_title`, `task_agents_path`, `cmd_memo`, `cmd_add` bootstrap 구현.
- [x] 검증: `scripts/build-workbranch.sh`, memo/add targeted tests.

### Task 2: `noti` 명령

- [x] RED: `test_noti_add_list_clear`.
- [x] RED: `test_noti_rejects_unknown_task`.
- [x] RED: `test_noti_state_removed_with_workspace`.
- [x] GREEN: `task_noti_path`, `noti_count`, UTC timestamp, JSON string escaping 구현.
- [x] 검증: `scripts/build-workbranch.sh`, noti/remove targeted tests.

### Task 3: `list --json`

- [x] RED: `test_list_json_shape`.
- [x] RED: `test_list_json_no_color_no_log_noise`.
- [x] RED: `test_list_json_dirty_flag`.
- [x] RED: `test_list_json_skips_stale_and_partial_task_dirs`.
- [x] GREEN: `cmd_list` early `--json` branch와 JSON writer 구현.
- [x] 검증: `scripts/build-workbranch.sh`, list-json targeted tests.

### Task 4: completion/docs/spec/build

- [x] `completion.sh`: `memo`, `noti`, `list --json`, `memo --clear` completion 추가.
- [x] `usage.sh`, README, README.ko, spec에 public contract 반영.
- [x] `scripts/workbranch-sources.txt`에 새 source 추가.
- [x] `bin/workbranch` rebuild.
- [x] 검증: `/bin/bash -n bin/workbranch install.sh tests/run.sh`, targeted completion/remove tests.

## 최종 검증

- [x] `scripts/build-workbranch.sh`
- [x] `/bin/bash -n bin/workbranch install.sh tests/run.sh`
- [x] `./tests/run.sh`
- [x] `git diff --check`
- [x] README/README.ko/spec 동기화

## 후속 작업

- 0017에서 companion이 이 계약을 소비한다.
- notification producer hook은 companion display loop가 유용하다고 확인된 뒤 별도 계획으로 진행한다.
