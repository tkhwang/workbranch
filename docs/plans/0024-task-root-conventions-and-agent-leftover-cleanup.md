# 0024 Task root 규약 명문화와 agent 비추적 잔여물 정리 계획

> **agentic worker 지침:** 실행 시 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용한다. 동작 변경 전에는 `superpowers:test-driven-development` 흐름(red → green → refactor)을 따른다. 코드는 `src/workbranch/**`를 먼저 수정하고 `scripts/build-workbranch.sh`로 `bin/workbranch`를 재생성한다. `bin/workbranch`를 직접 수정하지 않는다. 새/수정 테스트는 반드시 `tests/run.sh`에 `run_test ...`로 등록한다. 검증은 syntax check → 관련 테스트 red/green 확인 → `./tests/run.sh` 전체 → `git diff --check` 순서. 문서는 EN/KO를 같은 PR에서 동기화한다.
>
> **시리즈 위치:** 0015(memo/noti/json) → 0021(companion 진행도·라이프사이클)에서 정립된 "task root = repo worktree 밖의 workbranch 메타 공간" 모델을 사용자에게 **명문화**하고, agent가 task root에서 실행되며 만드는 비추적 파일(`.omc/`, `.omx/` 등)의 라이프사이클을 마무리하는 후속 계획이다.

**목표:** 네 가지를 분명히 한다.

1. **폴더 사용 기준의 결정과 가이드** — `<task>`(task root)는 git으로 관리되지 않는 workbranch 메타/agent 작업 공간이고, 실제 git repo는 `<task>/<repo>`라는 사실을 README(EN/KO)·docs·생성되는 `AGENTS.md`에 명시한다. `workbranch terminal`은 task root를, `workbranch ide`는 repo 폴더를 연다는 규약을 코드·문서에 일치시킨다.
2. **비추적 잔여물 한 방 정리** — `workbranch remove` 시 task root에 남은 비-git 잔여물(agent가 만든 `.omc/`, `.omx/`, 그 외 workbranch가 모르는 모든 항목)을 "git으로 관리되지 않아 사라진다"고 **알려주고**, 한 번의 확인으로 전부 지우고 나올 수 있게 한다.
3. **진행 요약 언어 설정** — 최초 init의 tool 설정 앞에서 `TASK-WORKBRANCH.md` status/progress update 언어를 English/한글 중 고르게 하고, `workbranch config`에서 다시 설정할 수 있게 한다. 새 task brief와 generated `AGENTS.md`는 이 설정 언어를 따른다.
4. **Companion 현재 작업 한 줄 강조** — companion에서 project/task/repo/branch 고정 정보 바로 아래에 “현재 repo/branch에서 무엇을 하는지”를 짧은 한 줄로 항상 노출하고, 이 줄을 가장 눈에 띄는 색/위계로 표시한다. 상세 checklist/status는 그 아래 보조 정보로 둔다.

**아키텍처:** task 상태는 repo worktree 밖의 task root에 둔다(0015 계승). workbranch가 **소유하는 known 파일**은 `TASK-WORKBRANCH.md`, `AGENTS.md`, `.workbranch/`(notifications.jsonl), `.workbranch.task`(metadata)뿐이다. task root의 그 외 모든 항목은 repo worktree(이 단계에서는 이미 제거됨)가 아닌 한 **비-git 잔여물**로 간주한다. remove는 (a) worktree/branch 제거 → (b) workbranch known 메타 제거 → (c) 남은 것이 있으면 목록을 보여주고 1회 확인 후 task root 전체 삭제 순서로 동작한다. `.omc/.omx`를 코드에서 special-case로 silent 삭제하던 로직은 **제거**하고, 모든 비-known 항목이 동일한 (c) 경로를 타게 한다.

**기술 스택:** portable Bash, generated single-file CLI(`scripts/build-workbranch.sh` → `bin/workbranch`), `tests/run.sh` integration harness. 문서는 `README.md`/`README.ko.md`/`docs/*.md`.

**제품 관점:** 사용자가 "어디서 무엇을 편집/실행하는가"와 "remove하면 무엇이 사라지는가"를 한눈에 알게 한다. terminal은 agent가 사는 곳(task root, `AGENTS.md`/`TASK-WORKBRANCH.md`/전체 repo 가시), ide는 코드를 고치는 곳(repo). remove는 git이 지켜주지 않는 잔여물을 명시적으로 경고하고 한 번에 정리한다.

---

## 문제

1. **폴더 사용 위치가 코드와 의도가 어긋남.** `workbranch terminal <task>`는 현재 task root가 아니라 각 repo 폴더를 연다(`ide`와 동일). agent는 `<task>` root에서 실행되어야 `AGENTS.md`를 읽고 `TASK-WORKBRANCH.md`를 갱신하며 전체 repo를 볼 수 있는데, terminal이 repo로 들어가 버린다.
2. **`<task>`가 비-git 공간이라는 사실이 문서화되어 있지 않음.** 사용자가 `<task>`에서 한 작업(메모 외 임의 파일, agent state)이 git으로 보호되지 않는다는 점, 실제 repo는 `<task>/<repo>`라는 점이 README에 분명하지 않다.
3. **agent 잔여물이 조용히 삭제됨.** `remove_task_state_files()`가 `.omc/`, `.omx/`를 무조건 silent로 force 삭제한다. 사용자는 "무엇이 남아 있었고 무엇이 지워지는지" 알 길 없이 사라진다. 요구는 *알려주고, 선택에 따라 한 방에 정리*다.

## 현재 repo 근거

- `src/workbranch/commands/tool-launcher.sh` `cmd_tool_launcher()`: `--repo` 없을 때 `ide`/`terminal` 모두 `REPO_NAMES`를 순회하며 각 `task/<repo>`를 연다. `resolve_task_path`로 task root를 검증하지만 실제 열기에는 쓰지 않는다. `finder`는 이미 task root를 연다(`cmd_finder`).
- `src/workbranch/lib/task-state.sh` `remove_task_state_files()`: `TASK-WORKBRANCH.md`/`AGENTS.md`/notifications/`.workbranch/` 제거 후 `.omx/`·`.omc/`를 무조건 `rm -rf`. `write_task_agent_guidance()`가 `AGENTS.md` 템플릿을 생성한다.
- `src/workbranch/commands/remove.sh`: known 메타 제거 후 `rmdir` 시도 → 실패(비어있지 않음)하면 `prompt_delete_remaining_task_root()`가 "Unknown task-root items remain for …" 목록과 `Delete remaining task root now? [y/N]`를 출력. `--force`는 무조건 `rm -rf`.
- `src/workbranch/lib/output.sh:248` `info_tool_opening()`이 "Opening <tool>: <label>" 포맷을 만든다.
- 테스트: `tests/cases/tool-launcher.sh`, `tests/cases/remove.sh`, `tests/cases/memo.sh`, `tests/cases/meta.sh`. `tests/run.sh`는 case file을 source하지만 테스트 실행은 명시 `run_test ...` 등록으로 고정되어 있고, 현재 인자 기반 필터는 없다.
- 문서/도움말 표면: `README.md`/`README.ko.md`, `docs/ai-agents.md`/`.ko.md`, `docs/usage.md`/`.ko.md`, `docs/architecture.md`, `src/workbranch/usage.sh`(generated `bin/workbranch` 포함).
- `src/workbranch/commands/init.sh`: 최초 init 후 `prompt_tool_config_after_init()`에서 IDE/Terminal을 묻는다. 언어 설정은 이 tool 설정 앞에 추가한다.
- `src/workbranch/commands/config.sh`: 현재 config target은 `all|base|ide|terminal`뿐이다. `workbranch config language` target을 추가해야 한다.
- `src/workbranch/lib/config.sh`: config directive parse/write가 uppercase 지시어 기반이다. 새 `PREFERRED_LANGUAGE en|ko`도 같은 형식으로 parse/write해야 한다.
- `companion/Sources/CompanionCore/Models.swift`: `WorkbranchTask`에는 이미 `status`, `progressDone`, `progressTotal`, `currentItem`, `repos[]`가 있다.
- `companion/Sources/CompanionApp/Views/RowView.swift`: 현재 `currentItem`은 `statusDetailsBlock` 안의 `statusSummaryLine`에 포함되어 checklist detail과 같은 영역에 묻힌다. 사용자가 원하는 “항상 외부 노출되는 가장 눈에 띄는 한 줄” 위계가 아니다.

## 결정 사항 (확정됨)

1. **열기 위치:** `terminal <task>` → **task root**(`<task>/`)를 1회 연다. `ide <task>` → **repo 폴더**를 연다(멀티레포면 repo별로). `--repo <repo>`는 두 명령 모두에서 특정 repo를 연다(기존 유지). `finder`는 task root(기존 유지). → **terminal은 동작 변경**.
2. **remove 정리:** workbranch known 메타와 repo worktree를 제외한 task root의 **모든 항목을 비-git 잔여물로 통합 취급**한다. 목록을 보여주고 "git 미관리라 사라진다"는 취지를 알린 뒤, **1회 확인**으로 task root 전체를 삭제한다. `.omc/.omx`의 무조건 silent 삭제는 **폐기**(이제 잔여물 목록·확인 경로를 탄다). `--force`는 무조건 정리(기존 유지).
3. **잔여물 인식 범위:** 하드코딩/설정 목록을 두지 않는다. "workbranch가 관리하는 known 파일이 아닌 모든 것"이 대상. 새 agent 툴이 생겨도 코드 수정 없이 자동 대응.

## 결정 게이트 결과

- [x] **테스트 러너 필터는 이번 slice에서 추가하지 않는다.**
  - Impact: test strategy / delivery scope.
  - Current evidence: `tests/run.sh`는 `main "$@"`로 인자를 받지만 `main()` 내부에서 필터로 쓰지 않고, 각 테스트는 명시 `run_test ...` 호출로 실행된다.
  - Resolved: `tests/run.sh tool-launcher` / `tests/run.sh remove` 같은 필터형 검증 명령은 plan에서 제거한다. 이번 slice는 새/수정 테스트를 `tests/run.sh`에 등록하고, 최종 검증은 `./tests/run.sh` 전체로 한다.
  - Rejected: 이번 slice에 테스트 필터 기능 추가. 이유: task-root/remove 제품 계약과 별도 runner feature이며 meta test와 사용법까지 새로 잠가야 해서 scope가 넓어진다.

- [x] **TASK-WORKBRANCH status update 언어 설정을 0024에 포함한다.**
  - Impact: public config format / init-config UX / generated task guidance.
  - Current evidence: `init` 후 tool config에서 IDE/Terminal을 묻고, `config`는 현재 `base|ide|terminal|--rewrite`만 지원하며, task brief/AGENTS 템플릿은 고정 문구다.
  - Resolved: 이번 slice에서 최초 init tool 설정 앞에 status update 언어 선호를 묻고 저장한다. `workbranch config`에서도 다시 설정 가능해야 하며, 이후 생성되는 `TASK-WORKBRANCH.md`와 generated `AGENTS.md`가 그 언어 선호를 반영한다.
  - Resolved contract: `.workbranch.config`에는 `PREFERRED_LANGUAGE en|ko`로 저장하고, 재설정 subcommand는 `workbranch config language`로 한다. 현재 적용 범위는 generated `TASK-WORKBRANCH.md`와 generated `AGENTS.md`이며, 전체 CLI localization이 아니다.

- [x] **선호 언어 설정 이름은 `PREFERRED_LANGUAGE en|ko` + `workbranch config language`로 한다.**
  - Impact: public config directive / CLI subcommand naming.
  - Current evidence: config directive는 uppercase(`IDE`, `TERMINAL`, `REPO`)이고 config subcommand는 짧은 noun(`ide`, `terminal`, `base`) 형태다.
  - Resolved: directive는 `PREFERRED_LANGUAGE`, 값은 `en|ko`, subcommand는 `workbranch config language`로 고정한다.
  - Rejected: `TASK_LANGUAGE` / `STATUS_LANGUAGE`는 적용 범위가 너무 좁고, `LANGUAGE`는 전체 CLI localization으로 오해될 수 있다.

- [x] **Companion current work line은 고정 identity 아래의 primary row로 표시한다.**
  - Impact: companion visual hierarchy / task observability.
  - Current evidence: companion model already carries `currentItem`, `status`, `progressDone`, `progressTotal`, and repo/branch; current SwiftUI renders the current item inside detail status summary, not as the primary always-visible line.
  - Resolved: companion task block order is project section → task line → repo line → branch line → **prominent one-line current work status** → detail checklist/status block. The current work line is always outside the scroll/detail block and must remain visible whenever the task row is visible.
  - Visual contract: terminal/cockpit aesthetic, fixed-width font, high-contrast accent/status color, one-line truncation, no low-contrast muted treatment for the current work line.


## 비목표

- agent 잔여물을 selective(항목별)로 보존/삭제하는 UI. (전부-or-보존 1회 확인만.)
- `.workbranch.config`에 agent-state 글롭 설정 추가. (결정 3에 따라 불필요.)
- `ide`가 task root를 열도록 바꾸는 것. (repo 유지.)
- stale task directory 경로(`is_stale_task_directory_path`) 동작 변경.
- `tests/run.sh <filter>` 형태의 테스트 필터 기능 추가. 이번 slice에서는 현재 runner 계약(명시 `run_test` 등록 + 전체 `./tests/run.sh`)을 따른다.

---

## 설계: 파일별 변경

### 1. `src/workbranch/commands/tool-launcher.sh` — terminal을 task root로

`cmd_tool_launcher()`에서 `--repo` 미지정 분기를 tool별로 분리한다.

- `terminal`(repo filter 없음): `resolve_task_path "$task"` 후 `info_tool_opening "terminal" "$task"` + `run_tool_command terminal "$command" "$RESOLVED_PATH"`로 **task root 1회** 실행.
- `ide`(repo filter 없음): 기존대로 `REPO_NAMES` 순회하며 repo별 실행.
- `--repo` 지정: 두 tool 모두 기존대로 해당 repo 실행.

구현 메모: tool별 분기는 `case "$tool_label"`로 처리하거나, "root를 여는 tool" 집합을 `terminal`로 한정. `finder`는 별도 `cmd_finder`라 영향 없음. `display_label`(IDE 대문자화)은 유지.

### 2. `src/workbranch/lib/task-state.sh` — `.omc/.omx` silent 삭제 제거

`remove_task_state_files()`에서 아래 두 줄을 **삭제**한다:

```sh
[ ! -e "$task_dir/.omx" ] || rm -rf "$task_dir/.omx" || die "failed to remove task OMX state: $task_dir/.omx"
[ ! -e "$task_dir/.omc" ] || rm -rf "$task_dir/.omc" || die "failed to remove task OMC state: $task_dir/.omc"
```

이후 `.omc/.omx`는 known 메타가 아니므로 remove의 (c) 잔여물 경로에서 다른 항목과 동일하게 처리된다. (force 경로는 `cmd_remove`의 `rm -rf` task_dir가 이미 처리.)

`write_task_agent_guidance()` 템플릿 보강(아래 docs/ai-agents 변경과 함께): agent가 **task root(`<task>`)에서 실행되는 것이 기본**이고, `<task>` 자체는 git으로 관리되지 않는 workbranch 메타/agent 작업 공간이며, 실제 git repo는 `<task>/<repo>` 아래에 있다는 경계를 명시한다. 코드 변경·git 명령은 repo 폴더에서 수행하고, 진행 상황 기록은 task root의 `TASK-WORKBRANCH.md`에 한다. repo 폴더 안에서 실행 중이면 `../TASK-WORKBRANCH.md`를 갱신한다는 기존 안내도 유지한다.

필수 포함 문구(영문 generated `AGENTS.md` 기준):

```md
- Run AI agent sessions from the task root (`<task>`) by default.
- The task root is not a Git repository; it is a workbranch metadata/agent workspace.
- The actual Git repositories live under `<task>/<repo>`.
- Make code changes and run Git commands inside the repo folders; keep progress in `TASK-WORKBRANCH.md` at the task root.
```

이 가이드는 필요하다. 이유는 agent가 `<task>`에서 실행되면 현재 cwd가 git repo가 아니므로, 명시 안내가 없을 때 task root에 코드/상태 파일을 잘못 만들거나 git 명령을 잘못 실행할 수 있기 때문이다.

### 3. `src/workbranch/commands/remove.sh` — 잔여물 메시지 개선

`prompt_delete_remaining_task_root()`의 안내 문구를 "비-git 잔여물"이 분명하도록 바꾼다(테스트와 함께 갱신). 예:

```
These items in the task root are NOT git-managed and will be lost if deleted:
  .omc
  .omx
  notes.txt
[*] Delete the entire task root for <task> now? [y/N]:
```

동작/프롬프트 입력 처리(`y/N`, `WORKBRANCH_ALLOW_NON_TTY_PROMPT`, non-TTY 보존)는 유지. 새 문구 키워드는 테스트에서 안정적으로 assert할 수 있게 고정한다(예: `not git-managed`, `Delete the entire task root`).

### 4. `src/workbranch/usage.sh` + `tests/cases/meta.sh` — help 표면 동기화

- `usage_plain()` / `usage_enhanced()`에서 `terminal <task>` 설명을 task root 기준으로 바꾼다. 예: `Open the task root in the configured terminal`.
- `ide <task>`는 repo worktree 기준 설명을 유지한다.
- `tests/cases/meta.sh`의 `test_help_groups_commands` 기대값을 새 help 문구로 갱신한다.
- `workbranch config language` help/usage 문구도 추가한다. 예: `config language   Update preferred language for generated task guidance`.
- `scripts/build-workbranch.sh` 이후 generated `bin/workbranch`에도 같은 help 문구가 반영되어야 한다.

### 5. `README.md` — 폴더 규약 + remove 정책

- **What it creates** 트리에 주석 보강: `<task>` = git 미관리 workbranch 메타/agent 작업 공간, `<task>/<repo>` = 실제 git worktree. (예: `feat-login          // task root (not git-managed)`, `└── frontend     // the git repo (worktree)`).
- **새 소절 "The task folder layout"**(또는 기존 "Task brief & notifications" 확장): task root에 들어가는 것 — `TASK-WORKBRANCH.md`, `AGENTS.md`, `.workbranch/`, 그리고 agent가 만드는 `.omc/`·`.omx/` 같은 비-git 런타임 파일. "task root에 직접 둔 파일은 git이 보호하지 않는다; 코드는 `<task>/<repo>`에서 작업하라"를 명시.
- **Working on a task**: `workbranch terminal <task>` → task root를 열어 agent가 `AGENTS.md`를 읽고 모든 repo·`TASK-WORKBRANCH.md`에 접근. `workbranch ide <task>` → 코드 편집용 repo 폴더. 둘 다 `--repo <repo>`로 특정 repo 지정 가능.
- **remove 문단**: "deletes workbranch-managed task state … including `.omx/`, `.omc/`" 같은 현재 서술을 새 정책으로 교체 — known 메타는 정리하고, 그 외 비-git 잔여물(`.omc/`·`.omx/` 포함)은 목록과 함께 경고한 뒤 1회 확인으로 task root를 통째로 삭제. `--force`는 확인 없이 정리.

### 6. `README.ko.md` — 5의 한국어 동기화

동일 변경을 한국어로. 문구: `<task>`는 git 미관리, 실제 repo는 `<task>/<repo>`; terminal=task root, ide=repo; remove는 비-git 잔여물 경고 후 1회 확인.

### 7. `docs/ai-agents.md` + `docs/ai-agents.ko.md`

- agent는 `<task>` task root에서 실행 → `AGENTS.md` 규약대로 `TASK-WORKBRANCH.md` 갱신, 코드는 `<task>/<repo>`에서 수정.
- `<task>`가 git 미관리 메타 공간이라는 점과, agent state(`.omc/.omx` 등)는 remove 시 정리 대상이라는 점 명시.

### 8. `docs/usage.md` + `docs/usage.ko.md`

- `terminal`/`ide`/`finder`의 열기 위치 표/설명 갱신(terminal=root, ide=repo, finder=root; `--repo` 지원).
- `remove`의 잔여물 1회-확인 정책과 `--force` 차이 갱신.

### 9. `docs/architecture.md`

task root vs repo worktree 경계, known 메타 집합 정의, remove의 3단계(worktree → known 메타 → 비-git 잔여물 1회 확인) 흐름을 한 단락으로 반영(필요 시).

### 10. 진행 요약 언어 설정 — init/config + generated task state

- config directive는 `PREFERRED_LANGUAGE en|ko`로 저장한다. 기본값은 기존 동작과 호환되도록 `en`이다.
- 재설정 command는 `workbranch config language`로 추가한다. 전체 config(`workbranch config`) 흐름에서도 현재 값을 보여주고 Enter로 유지할 수 있게 한다.
- 최초 `workbranch init`에서 project/repo 생성과 첫 task 생성 이후, IDE/Terminal tool 설정을 묻기 전에 선호 언어를 묻고 저장한다. Prompt 표시는 `English` / `한글`로 하되 저장 값은 `en|ko`만 허용한다.
- 저장된 언어는 이후 `write_default_task_brief()`와 `write_task_agent_guidance()`에 반영한다. 기존 task 파일은 자동 rewrite하지 않는다.
- English 선택 시 generated `TASK-WORKBRANCH.md`와 `AGENTS.md`는 영어 status/update 안내를 유지한다. 한글 선택 시 생성되는 task brief/AGENTS guidance의 진행 기록 안내와 기본 checklist 문구를 한국어로 쓴다.
- 범위는 generated task brief와 generated agent guidance다. 전체 CLI 출력 localization은 이번 slice의 목표가 아니다.

### 11. Companion 현재 작업 한 줄 강조 — fixed identity + primary current status

- UI order for each task must be:

  ```text
  [*] ProjectName
    [+] <task> name
    │ repo <repoName>
    │ branch <branchName>
    │ status <short current repo/branch work>   # always visible, strongest visual emphasis
    │ [x] detailed task item...
    │ [ ] detailed task item...
  ```

- The current-work line is part of the fixed identity/header area, not the detail area. The always-visible boundary is: project → task → repo → branch → current-work line. Everything below that is detail.
- The current-work line source is `currentItem` from `workbranch list --json`, i.e. the short sentence that tells the user what is happening in the current repo/branch. If `currentItem` is empty, still render a one-line fallback so the row shape is stable:
  - `done`: `status done`
  - no checklist/unknown current item: `status no active checklist item`
- The line must be the easiest line to notice relative to repo/branch and detail checklist:
  - use the palette accent/status color rather than muted gray;
  - use semibold/bold text plus a subtle filled/outlined strip or badge inside the terminal theme;
  - keep it one line with tail truncation so it is scan-friendly;
  - keep it visible without expanding, scrolling, or opening the checklist detail block.
- Details below keep the current checklist/status rendering, but the detail block is secondary. Checklist rows may scroll/collapse; the current-work line may not disappear while the task row is visible.
- This is a companion presentation change only. The JSON contract does not need a new field because `currentItem`, `status`, `progressDone`, `progressTotal`, and `repos[]` already exist.
- Visual thesis: terminal cockpit hierarchy — identity is stable, current work is the bright command line, checklist is the dim audit trail.

---

## 테스트 계획 (TDD: 먼저 빨갛게)

### `tests/cases/tool-launcher.sh`

- `test_ide_and_terminal_run_configured_command_for_task_repos`: terminal 분기를 **task root 1회**로 수정.
  - `terminal login` → `assert_contains "$out" "[*] Opening terminal: login"` (repo별 두 줄 제거).
  - fake tool 로그가 `"$canonical_project/login|$canonical_project/login"`(task root) 1회를 포함하도록.
  - ide 분기(`--repo frontend`, repo별)는 그대로 유지.
- `terminal login --repo backend`(라인 98 색상 테스트)·platform gate(라인 195) 등 `--repo`/플랫폼 테스트는 변경 없이 통과해야 함 — 회귀 확인.
- 신규: `test_terminal_opens_task_root_without_repo_filter` 추가(분기 의도를 명시적으로 잠금).
- 새 테스트는 `tests/run.sh`의 tool-launcher 영역에 `run_test test_terminal_opens_task_root_without_repo_filter`로 등록한다.

### `tests/cases/meta.sh` / `tests/cases/memo.sh`

- `tests/cases/meta.sh`: help 문구 변경을 잠근다. `terminal <task>`는 task root, `ide <task>`는 repo worktrees로 서로 다르게 기대한다.
- `tests/cases/memo.sh`: generated `AGENTS.md` 템플릿에 task root가 git 미관리 workbranch 메타/agent 작업 공간이고 실제 repo가 `<task>/<repo>`라는 문구가 들어갔는지 assert를 추가한다. 또한 코드 변경/git 명령은 repo 폴더에서 수행하고 진행 기록은 task root의 `TASK-WORKBRANCH.md`에 남긴다는 안내를 잠근다.

### `tests/cases/config.sh` / `tests/cases/interactive-init.sh` — 언어 설정

- 최초 init에서 preferred language prompt가 IDE/Terminal prompt보다 먼저 출력되는지 잠근다.
- 선택한 언어가 `.workbranch.config`에 `PREFERRED_LANGUAGE en|ko`로 저장되는지 assert한다.
- `workbranch config language`가 기존 IDE/Terminal/base 설정을 보존하면서 `PREFERRED_LANGUAGE`만 갱신하는지 assert한다.
- invalid language 값은 config parse 또는 prompt validation에서 실패하는지 assert한다.
- 언어 설정에 따라 새 task의 `TASK-WORKBRANCH.md`와 generated `AGENTS.md` 안내가 영어/한글로 생성되는지 assert한다.

### `companion` 현재 작업 한 줄 표시

- `CompanionCoreTestRunner` 또는 CompanionCore tests에 menu/render model expectation을 추가한다: task row model must preserve `currentItem` as the primary current-work line data and keep checklist items separate as details.
- SwiftUI view-level behavior is verified by build/manual visual QA rather than unit-testing SwiftUI internals: run companion build and inspect the popover with a task containing repo/branch/currentItem/checklist.
- Acceptance: project/task/repo/branch/current-work line is visible without expanding/scrolling details; current-work line uses accent/status treatment and is the easiest line to scan; hiding/collapsing/scrolling detail checklist rows never hides the current-work line.

### `tests/cases/remove.sh`

- `test_remove_cleans_known_generated_task_state`(현재 `.omc/.omx` 생성 후 무프롬프트 전삭제 기대) → **재작성**: 이제 `.omc/.omx`는 잔여물이므로 프롬프트가 떠야 한다.
  - 새 이름 예: `test_remove_warns_and_can_purge_agent_leftovers`.
  - `printf 'y\n' | WORKBRANCH_ALLOW_NON_TTY_PROMPT=1` 로 확인 → `.omc/.omx` 나열 + 새 경고 문구 + `assert_not_exists "$project/login"`.
  - 별도 케이스: 같은 상황에서 `n` 입력 → task root와 `.omc/.omx` 보존(`assert_dir`).
- `test_remove_prompts_before_deleting_unknown_task_root_files` 등 문구 의존 테스트: `assert_contains "Unknown task-root items remain"`/`Delete remaining task root now?`를 **새 문구**로 갱신(예: `not git-managed`, `Delete the entire task root`). 영향 케이스: prompts/declined/noninteractive/confirmed 4종.
- `test_remove_force_purges_without_prompt`: 변경 없이 통과 확인(force 경로).
- renamed/new remove 테스트가 있으면 `tests/run.sh`의 remove 영역에 등록하고, 제거한 테스트명은 `tests/run.sh`에서도 함께 정리한다.

### 통합

- 새/수정 테스트는 `tests/run.sh`에 명시 등록한다. `tests/run.sh <name>` 필터는 이번 slice에서 사용하지 않는다.
- `./tests/run.sh` 전체 그린.
- `scripts/build-workbranch.sh`로 `bin/workbranch` 재생성 후 `git diff --check`.

---

## 검증 순서

1. `bash -n` syntax check (수정한 `src` 파일).
2. `scripts/build-workbranch.sh` → `bin/workbranch` 재생성.
3. 새/수정 테스트가 `tests/run.sh`에 등록됐는지 확인한다(`run_test ...`).
4. `./tests/run.sh` 전체.
5. `git diff --check`.

## 롤아웃 / 호환성

- **동작/계약 변경 4건**을 CHANGELOG/PR 본문에 명시:
  1. `workbranch terminal <task>`가 repo 폴더 대신 task root를 연다(특정 repo는 `--repo` 사용).
  2. `workbranch remove`가 `.omc/.omx`를 더 이상 조용히 삭제하지 않고, 비-git 잔여물로 경고 후 1회 확인으로 정리한다(무인 환경 기존 보존 동작 유지, `--force` 무프롬프트 유지).
  3. `.workbranch.config`에 `PREFERRED_LANGUAGE en|ko`가 추가되고 `workbranch config language`로 재설정할 수 있다. 현재 적용 범위는 새로 생성되는 `TASK-WORKBRANCH.md`와 generated `AGENTS.md`다.
  4. Companion task row에서 repo/branch 아래 현재 작업 한 줄이 항상 보이고 가장 강한 시각 위계를 갖는다.
- 사용자 데이터 손실 위험 감소(silent → 명시 확인) 방향이라 안전. 자동화에서 무프롬프트가 필요하면 `--force`. 언어 설정은 기존 config에 없으면 `en` 기본값으로 동작해 backward-compatible하게 처리한다.

## 실행 순서 요약

1. (red) tool-launcher/remove 테스트를 새 동작 기대로 수정·추가.
2. (green) `tool-launcher.sh` terminal 분기, `task-state.sh`에서 `.omc/.omx` 삭제 제거, `remove.sh` 문구 개선.
3. `usage.sh` help 문구 + `AGENTS.md` 템플릿 보강, 관련 meta/memo 테스트 갱신.
4. `PREFERRED_LANGUAGE en|ko` config/init/`config language`/task-template 반영 및 config/interactive-init/memo 테스트 갱신.
5. Companion RowView/MenuState 표현을 current-work primary line 구조로 갱신하고 companion build/manual visual QA 수행.
6. 문서 동기화(README EN/KO, docs ai-agents/usage/architecture EN/KO, companion README/plan notes if needed).
7. `tests/run.sh` 등록 확인, 빌드 재생성 + 전체 테스트 + diff check.

---

## 실행 결과 (2026-06-14)

- [x] `terminal <task>`는 task root를 1회 열고, `ide <task>`는 repo worktree를 유지한다.
- [x] `.omc/`와 `.omx/` silent 삭제를 제거하고, task-root 비-git 잔여물 경고 + 1회 확인 경로로 통합했다.
- [x] generated `AGENTS.md`에 task root / repo folder 경계와 progress update 위치를 명시했다.
- [x] `.workbranch.config`에 `PREFERRED_LANGUAGE en|ko`를 추가하고 `workbranch config language`와 init 후 preferred language prompt를 구현했다.
- [x] Companion task row에서 repo/branch 아래 current-work line을 항상 보이는 primary line으로 올리고, detail checklist와 분리했다.
- [x] README EN/KO, docs/ai-agents EN/KO, docs/usage EN/KO, docs/architecture를 동기화했다.

검증 evidence:

- `bash -n $(find src tests -name '*.sh' | sort)`
- `scripts/build-workbranch.sh`
- `(cd companion && swift build && swift run CompanionCoreTestRunner)`
- `(cd companion && ./scripts/build-app.sh)` → `dist/WorkbranchCompanion.app (v1.5.0)` build success
- `./tests/run.sh` → `Tests passed: 243`
- `git diff --check`
