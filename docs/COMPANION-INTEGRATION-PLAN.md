# workbranch companion 통합 계획

## 목적 (한 문장)

터미널을 일일이 열지 않고 **메뉴바 companion만 보면 모든 project > task의 진행 상황이 한눈에** 파악되도록,
CLI(`workbranch`)와 companion을 project 레지스트리로 연동하고, `TASK-WORKBRANCH.md`의 계층적 진행을 정리해서 렌더링한다.

## 설계 원칙

1. **레지스트리는 "project 목록"만 관리한다.** task/repo는 저장하지 않고 항상 파일시스템(git worktree)에서 실시간 도출한다. (단일 source of truth, drift 방지)
2. **레지스트리 쓰기는 `init`/`destroy`만 한다.** `add`/`remove`(task)는 레지스트리를 건드리지 않는다 — FSEvents + `list`가 자동 반영. `forget` 명령은 만들지 않는다.
3. **companion은 status-first task cockpit.** project/task 생성·삭제는 CLI가 담당하고, companion은 task 운영 action(memo edit, notification clear, Finder/IDE/terminal launch, copy path, refresh/quit)을 유지한다. `New workspace` 생성 UI만 제거한다.
4. **status 표시가 1순위.** 평소엔 접어서 glance, 펼치면 계층적 진행 상세.

---

## 확정된 결정 (Decisions)

### D1. 레지스트리 형식/위치 — **Markdown registry `projects.md`로 변경**
- 레지스트리는 복잡한 JSON 객체가 아니라 project root 목록이므로 Markdown/line-oriented 파일로 관리한다.
- `jq`, Python fallback, 기타 user-installed JSON writer 의존성을 만들지 않는다. Bash CLI가 portable text 처리로 add/remove/list를 보장한다.
- companion은 기존 JSON config parser 대신 Markdown registry parser를 읽는다. 아직 개발 단계라 JSON config 호환/migration은 범위 밖이다.
- 레지스트리 파일 위치/이름은 `~/.config/workbranch-companion/projects.md`로 확정한다.

### D2. 레지스트리 쓰기 — **추가 의존성 없는 Markdown 편집**
- 추가/제거 시 기존 수동 주석과 `workbranchBin` 설정 줄을 보존한다.
- project root는 항상 **절대경로**(`cd "$dir" && pwd -P`)로 정규화해 bullet line으로 저장한다.
- `registry_add_root`/`registry_remove_root`는 멱등이어야 하며, jq/Python 미설치 여부와 무관하게 동작해야 한다.
- 레지스트리 파일 `~/.config/workbranch-companion/projects.md` 예시는 다음 형태를 기본으로 한다:
  ```markdown
  # workbranch companion projects

  workbranchBin: /opt/homebrew/bin/workbranch

  ## projects
  - /abs/project-a
  - /abs/project-b
  ```

### D3. `destroy` 명령 — **destructive-only, `forget`/`--keep-files` 제외**
- dirty(uncommitted) 또는 unpushed 커밋이 있는 worktree가 있으면 **중단**, `--force`로만 강행.
- 기본 확인 프롬프트를 둔다. `forget` 별도 명령과 `destroy --keep-files`는 만들지 않는다.
- 삭제는 init의 역순: task worktree → base repo → `.workbranch.config` → 레지스트리.

### D4. JSON 스키마 버전 — **v1 유지 + `items[]` additive 확장**
- 아직 개발 단계라 외부 호환성/migration 비용을 만들지 않는다. `workbranch list --json`은 `schemaVersion: 1`을 유지한다.
- 기존 v1 flat progress 필드(`status`, `progressDone`, `progressTotal`, `currentItem`)는 유지하고, 계층 checklist 렌더링용 `items[]`를 additive field로 추가한다.
- companion `Models.swift`는 `schemaVersion == 1`만 수용하고, `items`는 `decodeIfPresent ?? []`로 처리한다. 구포맷 task/fixture는 깨지지 않아야 한다.

### D5. `list --global` — **이번 plan의 companion data path**
- Phase 4로 `workbranch list --global`과 `workbranch list --global --json`을 이번 plan에 포함한다.
- companion은 현행 root별 N회 호출(StateStore.swift:332-345)을 제거하고, `workbranch list --global --json` 1회 호출을 기본 refresh data path로 사용한다.
- FSEvents는 계속 root/config 변경 감지와 refresh trigger만 담당한다. 상태 source of truth는 global list 출력이다.
- `--global`은 companion이 쓰는 public CLI contract이자 terminal에서 전체 registered project 상태를 확인하는 command다.

---

## Phase 1 — Markdown 레지스트리 기반 (`registry.sh`)

신규: `src/workbranch/lib/registry.sh`

| 함수 | 동작 |
|------|------|
| `registry_path()` | `${XDG_CONFIG_HOME:-$HOME/.config}/workbranch-companion/projects.md` 출력 |
| `registry_add_root <abs_path>` | 파일 없으면 Markdown skeleton 생성. project bullet에 없으면 추가(멱등). `workbranchBin`/주석 보존 |
| `registry_remove_root <abs_path>` | project bullet에서 제거(멱등, 없어도 에러 아님). 다른 줄 보존 |
| `registry_list_roots()` | project bullet의 absolute paths를 줄단위 출력 |
| `registry_workbranch_bin()` | `workbranchBin:` 줄이 있으면 값 출력, 없으면 빈 값 |

- 경로는 절대경로로 정규화해 저장 (companion이 absolute path만 허용).
- jq/Python/Node 등 추가 writer 의존성 없이 Bash text 처리만으로 성공해야 한다.
- unknown Markdown 내용은 가능한 보존하되, project root로 인정하는 줄은 `- /abs/path` bullet만이다.

**Acceptance**: `registry_add_root /tmp/p1` 2회 → project bullet 1개. `workbranchBin:`과 주석 유지. remove 후 bullet 사라짐. jq/Python 미설치 환경에서도 add/remove/list 성공.

---

## Phase 2 — `init` → 레지스트리 등록

수정: `src/workbranch/commands/init.sh`

- `cmd_init`의 두 경로 모두 성공 지점에서 `registry_add_root "$PROJECT_ROOT"`:
  - 기존 config 재clone 성공 후 (init.sh:205-206 근처)
  - `cmd_init_interactive`의 `clone_base_repos` 성공 후 (init.sh:134-135 근처)
- `--no-companion` 플래그로 등록 skip.
- 등록 시 `info` 1줄: `Registered with companion: <root>`.

**Acceptance**: 새 프로젝트 init → 레지스트리 roots에 PROJECT_ROOT 추가 → companion 재조회 시 메뉴 등장. `--no-companion`이면 미등록.

---

## Phase 3 — `destroy` 명령

신규: `src/workbranch/commands/destroy.sh`
수정: `src/workbranch/main.sh`(dispatch), `src/workbranch/usage.sh`(도움말), completion(`__complete-commands`)

### `cmd_destroy` (init의 반대)
삭제 순서 (역순):
1. 모든 task worktree 제거 (`git worktree remove`; dirty/unpushed 검사 → 막히면 중단 또는 `--force`)
2. base repo 디렉토리 제거
3. `.workbranch.config` 제거
4. `registry_remove_root "$PROJECT_ROOT"`

- 옵션: `--force`(안전검사 무시), 기본 확인 프롬프트. `--keep-files`는 제공하지 않는다.
- dispatch: `destroy) cmd_destroy "$@" ;;`

**Acceptance**: dirty worktree면 destroy 중단+경고. `--force`로 안전검사를 무시하고 project 삭제+레지스트리 제거. `forget` 명령과 `destroy --keep-files`는 존재하지 않는다.

---

## Phase 4 — `workbranch list --global`

수정: `src/workbranch/commands/list.sh`

- `cmd_list`는 인자 파싱을 먼저 수행하고, `--global` 경로에서는 cwd project의 `require_project` 없이 Markdown registry를 읽는다.
- `--global`: `registry_list_roots` 순회 → 각 root에서 서브셸 `cd` 후 프로젝트 단위 수집 → 집계 출력.
- `--global --json`: 래퍼 문서
  ```json
  {
    "schemaVersion": 1,
    "projects": [ <기존 list --json 문서>, ... ],
    "errors": [ { "root": "/missing/root", "message": "..." } ]
  }
  ```
- 기본(플래그 없음)은 현행 유지 = cwd 로컬 1개이며 이 경로만 `require_project`를 호출한다.
- 실패 root는 registry에서 제거하지 않는다. JSON에서는 `errors[]`에 포함하고, human output에서는 stderr warning을 출력한다(self-heal은 companion 담당).
- partial failure exit status: 성공 project가 하나라도 있으면 exit 0이고 실패 root는 `errors[]`로만 표현한다. registry를 읽을 수 없거나 모든 root가 실패하면 nonzero로 종료한다.

**Acceptance**: cwd가 project 밖이어도 registry N개 → `list --global`이 성공 project status와 실패 root warning을 함께 집계 출력. `--global --json`은 `{ "schemaVersion": 1, "projects": [...], "errors": [...] }` wrapper를 출력하고 각 project 문서는 기존 v1+items contract를 따른다. 실패 root는 `errors[]`에 `{ "root", "message" }`로 포함하며 registry를 수정하지 않는다. partial failure는 exit 0, registry unreadable 또는 all-roots failure는 nonzero다. companion refresh는 root별 N회 호출 없이 이 wrapper JSON 1회를 파싱하고 실패 root를 error row/self-heal 판단에 사용한다.

---

## Phase 5 — `TASK-WORKBRANCH.md` 계층 진행 + JSON `items[]`

### 5a. 컨벤션 (들여쓰기 = major/medium/small)
수정: `src/workbranch/lib/task-state.sh`
- `write_default_task_brief` 템플릿을 중첩 예시로:
  ```markdown
  # <task>

  status: planning

  - [ ] Major: <큰 작업>
    - [ ] <중간 작업>
      - [ ] <작은 작업>

  ## Notes
  -
  ```
- `write_task_agent_guidance`에 "하위 작업은 들여쓰기로 표현" 규칙 추가.

### 5b. CLI: 체크리스트 항목을 depth와 함께 JSON에
수정: `src/workbranch/lib/task-state.sh`(신규 `task_checklist_items_json`), `src/workbranch/commands/list.sh`
- 코드블록 제외, `- [x]/- [ ]` 줄 순회, **leading 공백으로 depth 계산**(2칸=1레벨 고정), `{ "text", "checked", "depth" }` 배열 생성.
- `cmd_list_json`의 각 task에 `"items":[...]`를 additive field로 추가한다. `schemaVersion`은 1을 유지한다.
- 기존 flat progress fields(`status`, `progressDone`, `progressTotal`, `currentItem`)도 유지한다. `items[]`는 계층 렌더링용이고 flat fields는 glance/요약용 contract다.

### 5c. companion: schemaVersion 1 + items 모델
수정: `companion/Sources/CompanionCore/Models.swift`
- `WorkbranchListDocument`: `schemaVersion == 1` 유지(2를 허용하지 않음).
- `WorkbranchTask`에 `items: [WorkbranchChecklistItem]` (`decodeIfPresent ?? []`).
- 신규 `WorkbranchChecklistItem { text: String; checked: Bool; depth: Int }`.

**Acceptance**: 중첩 체크리스트 task → `list --json`이 `schemaVersion: 1`을 유지하면서 flat progress fields와 depth 담긴 `items[]`를 함께 출력. companion은 v1 문서를 파싱하고 `items` 누락 시 빈 배열로 처리.

---

## Phase 6 — companion UI 개편 (status-first cockpit + 계층 트리)

수정: `companion/Sources/CompanionApp/Views/CompanionPopoverView.swift`, `companion/Sources/CompanionCore/MenuState.swift`, `companion/Sources/CompanionCore/Models.swift`, `companion/Sources/CompanionApp/CLIClient.swift`, `companion/Sources/CompanionApp/StateStore.swift`

### 6a. global list 소비
- `CLIClient`에 `listGlobalJSON()`을 추가해 `workbranch list --global --json`을 project cwd 없이 실행한다. exit 0 partial failure는 성공으로 decode하고, `errors[]`를 UI 상태로 전달한다.
- `Models.swift`에 global wrapper model을 추가한다: `{ "schemaVersion": 1, "projects": [WorkbranchListDocument], "errors": [WorkbranchGlobalError] }`. 각 project 문서는 기존 `WorkbranchListDocument` v1+items contract를 재사용한다.
- `StateStore.refreshAll`은 root별 task group 호출 대신 global wrapper 1회를 호출해 `MenuState.make`에 project documents를 전달한다.
- root/config FSEvents는 refresh trigger와 watcher 재구성에만 사용한다. 변경된 root만 부분 refresh하는 최적화는 후속으로 미룬다.
- global wrapper의 `errors[]`는 `MenuState` error row와 companion의 true-deletion grace/self-heal 판단에 사용한다. stderr/statusMessage는 보조 진단으로만 둔다.

### 6b. 생성 UI 제거 / task action 유지
- `New workspace…` 생성 UI만 제거한다: `showingNewWorkspace`, `newWorkspaceSheet`, `selectedRoot`, `newTaskName`, `.sheet`, `StateStore.addWorkspace`, `MenuAction.newWorkspace`를 정리한다. task 생성은 `workbranch add` CLI가 담당한다.
- task cockpit action은 유지한다: inline memo edit, notification clear, terminal/IDE/Finder launch, copy path. `MenuAction`/`Actions.swift`에서 해당 action builder를 삭제하지 않는다.
- 헤더 우측 아이콘 버튼 2개: `↻`(refresh → `store.refreshAll()`), `⏻`(quit → `store.quit()`).
- `Open config`는 레지스트리 문제를 진단/수정하는 escape hatch로 유지하되 primary 생성 flow로 홍보하지 않는다.
- 하단 `statusMessage`는 refresh/action 에러용 1줄만 유지한다.

### 6c. 계층 렌더 Project > Task > Repo (collapsible)
- 모델을 트리로 확장(또는 뷰에서 직접 트리 구성).
- Task = `DisclosureGroup`:
  - **접힘(기본)**: `status 배지(색) + done/total + now ▸ <currentItem>`
  - **펼침**: repo 줄(branch + dirty ●) + 계층 체크리스트 트리(depth 들여쓰기, 노드별 rollup `done/total`)
- 기본 펼침 정책: `blocked`이거나 noti 있는 task는 펼침, `done`/clean은 접힘.

목표 레이아웃:
```
▾ workbranch                                  🔔1
  ▾ feat-companion-ui        ● in-progress 6/10
       now ▸ status 렌더링 구현
       workbranch  feat/companion-ui  ●
       docs        main
       ▾ Major: companion UI        3/5
           ✓ RootWatcher 구현
           ▾ status 렌더링           1/2
               ✓ 색 매핑
               ☐ 펼침 로직
           ☐ 알림 연동
  ▸ fix-login                ✓ done 3/3
```

### 6d. status 색/아이콘 매핑
| status | 아이콘 | 색 |
|--------|--------|-----|
| done | ✓ | green |
| in-progress | ● | blue |
| review | ◐ | purple |
| blocked | ⚠ | red |
| planning | ○ | gray |

### 6e. 메뉴바 타이틀 롤업
- `MenuState.title`에 전체 집계: 예 `▶3 ⚠1 🔔2` (진행중/blocked/알림). 팝오버 안 열어도 감지.

**Acceptance**: 팝오버에 project>task>repo 트리, task 접기/펼치기, status 색 구분, currentItem("now") 노출, `New workspace` 생성 UI 없음, task action(memo/noti/launch/copy path) 유지, refresh/quit 접근 가능, 메뉴바 롤업 표시.

---

## Phase 7 — 검증 & 테스트

- **CLI(shell)** `tests/`: Markdown registry add/remove 멱등성·workbranchBin 보존·추가 의존성 없음, init→등록, `--no-companion`, destroy 안전검사/삭제순서/`--force`, `--keep-files` 거부, `list --global --json` wrapper(`projects[]`+`errors[]`) 스키마, partial failure exit 0, all-roots failure nonzero, `items[]` depth 파싱.
- **companion(Swift)** `CompanionCoreTests`: schemaVersion 1 + additive items 디코딩, global wrapper(`projects[]`+`errors[]`) 디코딩, partial failure decode, `list --global --json` 1회 refresh, 실패 root error row/self-heal 판단, items depth, MenuState 롤업/색/타이틀, 트리 구성, `New workspace` 제거 후 기존 task action 유지. `CompanionCoreTestRunner/main.swift` 갱신.
- **수동**: 실제 2~3개 프로젝트 init → companion 트리/접기/색/now/롤업 육안 확인.

---

## 구현 순서 (tracer-bullet)

```
Phase 1 (registry.sh)
   ↓
Phase 2 (init 등록) ─── 최소 가치: "init한 프로젝트가 companion에 자동 표시"
Phase 3 (destroy)
Phase 4 (list --global + companion global consumption)
   ↓
Phase 5 (TASK-WORKBRANCH.md 계층 + schemaVersion 1 additive items[])
   ↓
Phase 6 (companion UI 개편) ─── 핵심 가치: "계층적 진행을 한눈에"
   ↓
Phase 7 (테스트/검증)
```

## 영향받는 파일 요약

**신규**
- `src/workbranch/lib/registry.sh`
- `src/workbranch/commands/destroy.sh`

**수정**
- `src/workbranch/main.sh` (dispatch: destroy)
- `src/workbranch/usage.sh` (도움말) + completion
- `src/workbranch/commands/init.sh` (등록 hook + `--no-companion`)
- `src/workbranch/commands/list.sh` (`--global`, `items[]`, schemaVersion 1 유지)
- `src/workbranch/lib/task-state.sh` (템플릿/가이던스/`task_checklist_items_json`)
- `companion/Sources/CompanionCore/Models.swift` (schemaVersion 1 유지, global wrapper projects/errors, items)
- `companion/Sources/CompanionCore/MenuState.swift` (트리/롤업/색/타이틀)
- `companion/Sources/CompanionApp/Views/CompanionPopoverView.swift` (UI 개편)
- `companion/Sources/CompanionApp/CLIClient.swift` (`list --global --json` 호출)
- `companion/Sources/CompanionApp/StateStore.swift` (`list --global` 1회 refresh, `New workspace` 제거, task action 유지)
- 테스트: `tests/`, `companion/Tests/`, `companion/Sources/CompanionCoreTestRunner/main.swift`
---

## 실행 결과 (2026-06-13)

- 구현 완료: Markdown `projects.md` 레지스트리, `init --no-companion`, `destroy --force`, `list --global --json`, `schemaVersion: 1` + additive `items[]`, companion global refresh, New workspace UI 제거, task action 유지, checklist DisclosureGroup 렌더링.
- 검증 통과:
  - `scripts/build-workbranch.sh`
  - `/bin/bash -n bin/workbranch src/workbranch/lib/task-state.sh src/workbranch/commands/list.sh`
  - `./tests/run.sh` → `Tests passed: 231`
  - `cd companion && swift run CompanionCoreTestRunner`
  - `cd companion && swift test`
  - 추가 회귀 검증: `test_run_test_isolates_companion_registry_config`, `test_init_existing_config_clones_base_repos`, `test_init_registers_companion_project_markdown` → `PASS=3 FAIL=0`
- 후속 수정: full suite가 사용자 `~/.config/workbranch-companion/projects.md`에 temp fixture roots를 등록하지 않도록 `tests/lib/helpers.sh`의 `run_test`가 per-test `XDG_CONFIG_HOME`을 격리한다.
- 수동 육안 QA: 스크린샷으로 temp root 오염 증상을 확인했고, 실제 registry 정리 후 `workbranch list --global --json`이 빈 wrapper를 반환함을 확인했다. 실제 메뉴바 팝오버는 Refresh 후 빈 상태가 되어야 한다.
