# 0052 Companion repo 활동 신호 + agent 이벤트 — 빈 보드 회귀 수정

> **agentic worker 지침:** 실행 시 `superpowers:executing-plans`를 사용한다. 동작 변경 전에는 `superpowers:test-driven-development`(red → green → refactor)를 따른다. 이 plan은 **CLI(Bash) + contract + Companion(TS) + Tauri(Rust) 전 계층**을 건드리므로 slice 경계를 엄격히 지킨다. 검증은 계층별로 — CLI는 `./apps/cli/tests/run.sh`, contract는 `pnpm --filter @workbranch/contract test`, Companion TS는 `pnpm --filter @workbranch/companion test` + `typecheck` + `lint`, Rust는 `cargo test` + `cargo clippy -- -D warnings`. CLI source를 고치면 반드시 `apps/cli/scripts/build-workbranch.sh`로 `apps/cli/bin/workbranch`를 재생성한다. Step은 checkbox(`- [ ]`)로 추적한다.
>
> **시리즈 위치:** 0031이 brief를 current-only로 줄이고, 0048/0049가 stage-first 칸반(PLAN/EXECUTION/REVIEW)을 세웠으며, 0033이 응답성 회귀(메인 스레드 블로킹 + watch 폭풍)를 고쳤다. 그 뒤 사용자가 **agent의 status 갱신 부담을 3단계로 축소**하면서, 보드를 채우던 **유일한 신호원이 함께 잘려나갔다.** 이 plan은 0033이 "후속"으로 명시적으로 미뤄둔 **partial refresh**를 회수하고, 보드가 **agent의 선의가 아니라 관측 가능한 사실**에서 채워지도록 신호원을 바꾼다. 0033의 아키텍처 결정(Rust는 thin port, 파싱/도메인/ACL은 TS)은 그대로 계승한다.

**목표:** "동시에 여러 작업을 돌릴 때 각 repo/branch가 **어디까지 와 있는지**"를 Companion 보드만 보고 파악할 수 있게 한다. 세부 진행이 아니라 **"이 branch는 지금 이런 상태"** 수준이면 충분하다.

---

## 배경 / 조사 결과 (2026-08-20)

사용자 피드백: **"status 파일 갱신에 토큰과 시간을 너무 써서 3단계로 줄였는데, 막상 보드에 제대로 안 보인다."**

### 실측 — 지금 보드에 뭐가 보이나

`workbranch list --global --json`을 실행 환경에서 직접 돌려 확인했다. 등록된 task 8개 중 **보드에 뜨는 건 2개**다.

| task | brief `status:` | repo 실제 상태 | 보드 |
| --- | --- | --- | --- |
| `feat-adjust-windows` | `todo` | clean, 17시간 전 커밋 | **안 보임** |
| `feat-update-state-handling` | `planning` | — | PLAN |
| `feature-cpq-task-a` | `done` | backend dirty 1건, **3시간 전 커밋** | **안 보임** |
| `feature-cpq-task-b` / `-c` / `-d` | brief 본문 없음 (`plans: []`) | — | **안 보임** |
| `feat-context-menu` | `todo` | — | **안 보임** |
| `feat-diff-mode` | `review` | — | REVIEW |

`feature-cpq-task-a`는 3시간 전 커밋과 dirty 파일이 있는 **실제 활성 작업인데 화면에서 사라져 있다.** 이것이 "제대로 안 보인다"의 실체다.

### 근본 원인 #1: `todo`/`done`에 갈 곳이 없다

`taskStage`(`apps/companion/src/domain/model.ts:85-98`)가 `todo`와 `done`에 `undefined`를 리턴하고, `buildBoardModel`(`apps/companion/src/application/state.ts:96`)이 `if (stage === undefined) continue;`로 카드를 통째로 버린다. 6개 상태를 3개 칼럼으로 줄이면서 **나머지 상태의 집이 사라졌다.** `todo`는 `write_default_task_brief`(`apps/cli/src/workbranch/lib/task-state.sh`)가 쓰는 기본값이므로, 이 구멍에 빠지는 것이 정상 경로이지 예외가 아니다.

### 근본 원인 #2: `status:` 줄의 유일한 작성자가 "agent의 선의"다

`status:`를 옮기는 주체는 `write_task_agent_guidance`가 생성하는 AGENTS.md 산문 지침뿐이다. agent가 `todo → planning`을 옮기지 않으면 영원히 `todo`다. **상세 업데이트를 줄이면서 유일한 heartbeat도 같이 잘렸다.** 위 표에서 5개 task가 정확히 이 상태다.

### 근본 원인 #3: `updatedAt`이 brief의 mtime이다

`task_updated_at`(`apps/cli/src/workbranch/lib/task-state.sh:18`)이 `TASK-WORKBRANCH.md`의 mtime을 그대로 쓴다. brief를 안 건드리면 **정렬(`buildBoardModel`의 `updatedAt` 내림차순)과 신선도가 같이 죽는다.** 코드가 아무리 바뀌어도 카드는 맨 아래에 머문다.

### 근본 원인 #4: 카드에 표시할 재료가 JSON에 없다

`cmd_list_json`(`apps/cli/src/workbranch/commands/list.sh:53-68`)이 내보내는 repo 정보는 `{name, branch, dirty}` **3개뿐**이다. 그 결과 `StageCard`(`apps/companion/src/ui/StageBoard.tsx`)에 남는 것은:

- `planTitle`은 task 폴더명과 같으면 숨겨지고 (0031의 current-only brief에서는 거의 항상 같다)
- `progressTotal === 0`이라 progress 배지 숨김
- `currentItem`은 빈 문자열

→ **프로젝트명 + 폴더명 + dirty 점 하나.** "여기까지 하고 있고"를 말할 재료가 애초에 없다.

한편 CLI에는 **이미 필요한 git 사실을 계산하는 코드가 있다.** `apps/cli/src/workbranch/lib/status-format.sh`의 `commit_diff_label`(`git rev-list --left-right --count`), `remote_diff_label`, `head_commit_full`, `worktree_status_label`이 그것이고 `cmd_status`(`apps/cli/src/workbranch/commands/status.sh:35-37`)가 base commit 기준으로 호출한다. **`list --json`만 이 정보를 안 내보낸다.**

### 조사: 비교 대상 앱 5종의 통신 방식

같은 문제(= "지금 이 agent가 뭘 하고 있나"를 GUI에 띄우기)를 푸는 앱들을 실제 설치본에서 확인했다. 전부 `~/.claude/settings.json`의 hook에 물려 있다.

| 앱 | 전송 방식 | 특징 |
| --- | --- | --- |
| ClaudeIsland | Unix socket `/tmp/claude-island.sock` | 권한 승인을 소켓에서 blocking `recv`로 대기 |
| Agent Notch | Unix socket `~/Library/Application Support/AgentNotch/notch.sock` | NDJSON, fire-and-forget + gate만 장시간 block |
| Herdr | Unix socket `$HERDR_SOCKET_PATH` | pane 단위 상태, 환경변수 가드 |
| Caudex | **파일 append** `~/.caudex/session-event.json` | 소켓 없음 — hook script가 `cat >> file` 두 줄 |
| Superset | 로컬 HTTP POST | Codex 이벤트까지 서버에서 정규화 |

**전송 계층은 제각각인데 신호원은 하나로 수렴한다: Claude Code hook.** 모델이 파일을 쓰는 게 아니라 hook이 `SessionStart`/`UserPromptSubmit`/`Notification`/`Stop`/`SessionEnd`에서 자동으로 push한다. **토큰 0, 지연 0, agent가 까먹을 수 없다.** workbranch에 없는 것이 정확히 이 축이다.

### 조사: IPC(소켓)가 필요한가 → **아니다**

Companion의 transport는 이미 event-driven이다 — FSEvents watcher + 경로 ignore 필터(`watch_roots.rs`, `watch_filter.rs`), root당 500ms 디바운스(`should_emit_root_change`), monitor 코얼레싱(`workspaceMonitor.ts`), 5분 heartbeat(`App.tsx:170`). **망가진 것은 transport가 아니라 신호원이므로, 소켓을 넣어도 빈 보드는 그대로다.**

소켓이 값을 하는 경우는 ① 100ms 이하 반응, ② Companion UI에서 권한 승인 blocking(ClaudeIsland/Notch가 하는 것) 둘뿐이고, 이 plan의 목표("너무 세부사항이 될 필요 없는 repo/branch 파악")에는 **500ms~2초면 충분하다.** 따라서 Caudex 방식(파일 append)을 택한다 — 자세한 근거는 D4.

### 확인된 제약: refresh 비용

`workbranch list --global --json`을 실측하면 **1.5초**다(0.46s user + 1.35s sys). 프로젝트 root마다 CLI를 새로 spawn하고(`cmd_list_global_json`이 `$self list --json`을 재귀 호출), repo마다 `git branch --show-current` + `git status --porcelain`을 돈다. **모든 fs 이벤트가 이 global 전체 재조회를 유발한다.**

- Slice A가 repo당 git 호출을 2 → 4로 늘리므로 이 비용은 **더 나빠진다.**
- Slice C가 이벤트 빈도를 올리므로 이 비용이 **곱해진다.**

→ **Slice B(partial refresh)는 선택이 아니라 A와 C 사이의 필수 전제조건이다.** 0033이 "후속 튜닝"으로 미뤄둔 항목을 여기서 회수한다.

다행히 배선의 절반은 이미 있다:

- `workbranch_list(root)` Rust command가 `lib.rs`에 구현·등록되어 있으나 **TS 호출자가 0건이다**(`grep` 확인). 단일 root 조회 port가 이미 존재한다.
- Rust는 `app.emit("roots-changed", root_label)`로 **바뀐 root 문자열을 이미 실어 보낸다.** 그런데 `onRootChanged`(`tauriClient.ts:91`)의 시그니처가 `callback: () => void`라 **페이로드를 버리고 있다.**

---

## 결정 사항

> **D1. 보드는 선언된 active stage를 우선하되, `todo`/`done`을 반증하는 strong repo evidence가 있으면 증거를 따른다.** `planning`/`in-progress`/`blocked`/`review`는 선언 stage를 유지한다. `todo` 또는 `done` task의 repo에 `ahead > 0`이나 `dirty`가 하나라도 있으면 EXECUTION으로 파생 승격한다. `lastCommitAt` 단독은 활동 증거가 아니며 승격에 사용하지 않는다. 승격된 카드는 **파생임을 시각적으로 표시**해 선언 상태와 구분한다. agent가 status를 갱신하지 않거나 `done` 뒤 미정리 변경이 남아도 보드가 살아있게 하는 것이 목표이지, `status:` 계약을 폐기하거나 brief를 다시 쓰는 것이 아니다.
>
> **D2. StageBoard는 stage별 column/section 대신 full-width task lifecycle feed를 사용하고, 어떤 task도 조용히 사라지지 않는다.** active task를 최신 활동순으로 나열하고 각 task 첫 영역을 bordered inset Stage panel로 분리한다. panel header는 `STAGE · <CURRENT>`를 표시하고, 아래 connected 3-node `PLAN → EXECUTION → REVIEW` stepper에서 current stage만 filled node + soft halo + accent label로 강조한다. 각 task row는 panel 밖 `PROJECT` label 아래 task identity를 분리하고, repo별 고정 label rail `REPO / BRANCH / COMMIT`으로 관측 가능한 활동 사실(`dirty/changedFiles`, `ahead/behind`, `lastCommitSubject · lastCommitAt`)을 표시한다. changed file count는 `DIRTY 28 FILES`처럼 단위를 포함한다. task header 우측에는 non-idle agent aggregate를 `RUNNING · CLAUDE+CODEX` 또는 `WAITING · CODEX`처럼 한 줄로 표시하고 idle은 생략한다. `DERIVED`는 task identity 옆 작은 배지로 유지한다. Git으로 알 수 없는 현재 작업 의미를 추측하지 않는다. active stage에 속하지 않는 clean `todo`/`done`은 feed 하단의 접힌 `OTHER N` disclosure에 남긴다(G2/G9).
>
> **D3. `list --json` repo 활동 필드는 `schemaVersion: 1`의 optional additive 필드로 추가한다.** 신규 CLI는 필드를 항상 출력하지만 published JSON Schema와 `WorkbranchRepo` DTO에서는 optional로 선언한다. 새 Companion은 누락값을 ACL에서 `0`/`""`로 정규화해 **구/new CLI × 구/new Companion 4조합**을 모두 수용한다. `additionalProperties: false`는 유지해 알려지지 않은 필드는 계속 거부한다. v2는 양쪽 consumer가 dual-read 준비를 갖춘 별도 변경에서 도입한다(G7).
>
> **D4. Claude Code와 Codex agent 이벤트는 provider adapter를 거쳐 동일한 `<task>/.workbranch/agent.jsonl` append로 전달한다.** `<project>`와 `<task>`는 Git repo가 아닌 workbranch management directory이고 실제 Git worktree는 `<task>/<repo>` 아래에 있으므로, 이 runtime 파일은 repo dirty state를 만들지 않는다. canonical envelope는 `{v:1, ts, provider:"claude"|"codex", sessionId, turnId?, event}`다. `turnId`는 Codex payload에 있을 때만 보존하고 상태 identity는 `(provider, sessionId)`를 사용한다. 근거 4가지:
> 1. Companion이 이미 task root를 watch하므로 append가 **기존 `roots-changed`를 그대로 발화한다 — 새 transport가 0줄이다.**
> 2. Companion이 꺼져 있어도 이벤트가 파일에 남는다(소켓은 유실).
> 3. daemon·소켓 수명·경로 협상·권한이 전부 사라져 "CLI가 진실, Companion은 뷰어"라는 0032/0033 경계를 유지한다.
> 4. `.workbranch/notifications.jsonl`(`apps/cli/src/workbranch/commands/noti.sh`)이라는 **동일 패턴이 이미 존재한다** — 새 개념이 아니라 확장이다.
>
> **D5. provider별 coarse lifecycle hook만 받는다.** 공통 확정 이벤트는 `SessionStart` / `UserPromptSubmit` / `Stop` / `SessionEnd`이며 두 provider 모두 **일반 `PreToolUse`/`PostToolUse`는 배선하지 않는다.** `UserPromptSubmit`은 같은 session의 두 번째 turn부터 `waiting → running`으로 돌아가기 위한 필수 신호다. Claude `Notification(permission_prompt)`과 Codex `PermissionRequest`는 권한 요청 시작은 알리지만 사용자가 승인해 실행이 재개된 시점을 알리는 대응 lifecycle event가 없어, waiting으로 기록하면 승인 후 stale waiting이 된다. permission-waiting 포함 여부는 G11에서 확정한다.
>
> **D5-A. 상태 writer hook은 짧은 동기 command로 실행한다.** background hook은 provider가 완료 순서를 보장하지 않아 빠른 `UserPromptSubmit → Stop`이 파일에서 뒤집힐 수 있다. 각 hook은 stdout/stderr 없이 local JSONL 한 줄만 append하고 timeout 1초를 사용한다(`SessionEnd`도 1초). 정상 목표는 100ms 미만이며 timeout/error에서도 agent turn을 block하지 않는 provider advisory semantics를 사용한다. 상태 fold는 `ts` 정렬이 아니라 append file order를 최신 순서로 취급한다.
>
> **D6. Slice 순서는 A → B → C이고 각각 독립 PR로 나갈 수 있다.** A만 머지해도 보드는 눈에 띄게 살아난다. B는 A가 추가한 git 비용을 흡수하며 C의 전제조건이다. C는 A/B 없이 머지하면 안 된다.

## Decision Gates

- [x] IPC(Unix socket / HTTP) 도입 여부
  - Impact: 새 daemon·소켓 수명 관리, Companion 미실행 시 이벤트 유실, CLI/Companion 경계 훼손.
  - Evidence: transport는 이미 event-driven(FSEvents + 디바운스 + 코얼레싱 + heartbeat)이고 빈 보드의 원인이 아님을 실측으로 확인. 비교 앱 5종 중 Caudex는 소켓 없이 파일 append만으로 같은 문제를 푼다. 소켓이 필요한 두 용례(sub-100ms, 승인 blocking)는 본 목표 범위 밖.
  - Status: resolved — **소켓 도입하지 않음.** 파일 append(D4).
- [x] **G7. `list --json` wire versioning 정책**
  - Impact: 구/new CLI × 구/new Companion 런타임 조합과 published JSON Schema 소비자의 호환성.
  - Evidence: `parseContract.ts`의 구 Companion은 repo 미지 필드를 무시하지만, `packages/contract/schema/workbranch-list.schema.json`의 `$defs.repo`는 `additionalProperties: false`다. 같은 v1에 새 필드를 required로 추가하면 기존 v1 schema는 새 CLI를 거부하고 새 v1 schema는 구 CLI를 거부한다.
  - 선택지: (a) `schemaVersion: 1` 유지 + 새 필드는 schema optional, 새 Companion이 기본값 정규화, (b) `schemaVersion: 2` 도입 + 새 Companion이 v1/v2를 모두 수용, 구 Companion + 새 CLI 조합은 명시적 비호환, (c) v1 유지 + 새 필드 required를 유지하되 published schema는 현재 출력 snapshot이며 역사적 호환 계약이 아니라고 명시.
  - Recommended default: **(a) v1 유지 + schema optional.** 설치된 CLI와 Companion 버전이 어긋날 수 있는 현재 배포 구조에서 런타임 4조합을 모두 살리고, 새 Companion 경계에서만 기본값을 채운다. 엄격한 버전 신호가 필요해지면 기존/신규 소비자가 v1/v2 dual-read 준비를 갖춘 별도 계획에서 v2로 전환한다.
  - Status: resolved — **(a) `schemaVersion: 1` 유지 + 신규 repo 활동 필드는 schema/DTO optional. 신규 CLI는 항상 출력하고 새 Companion ACL이 누락값을 기본값으로 정규화한다.**
- [x] partial refresh를 이 plan에 포함할지
  - Impact: 미포함 시 Slice A/C가 1.5초 global 재조회 비용을 증폭시킨다.
  - Evidence: `list --global --json` 실측 1.5s. `workbranch_list(root)` Rust command가 이미 존재하나 TS 호출자 0건. `roots-changed`가 root 페이로드를 이미 싣고 있으나 `onRootChanged` 시그니처가 버린다.
  - Status: resolved — **Slice B로 포함**(D6).
- [x] **G1. 파생 stage 승격의 강도**
  - Impact: 오탐(오래전 dirty가 남은 방치 task가 EXECUTION을 점유) 대 미탐(활성 작업이 계속 사라짐)의 균형.
  - 선택지: (a) `todo`/`done`에 `ahead > 0` 또는 `dirty`가 있으면 무조건 EXECUTION 파생 승격, (b) `todo`만 승격하고 `done + evidence`는 기타 섹션 유지, (c) dirty 파일 mtime 기반 `lastActivityAt`을 추가해 24시간 창 안에서만 승격.
  - Recommended default: **(a) `todo`/`done` 모두 strong evidence로 승격.** dirty나 base 대비 ahead는 시간이 지나도 해소되지 않은 Git 사실이며, 오래되었다는 이유로 숨기면 원래 회귀가 재발한다. `lastCommitAt` 단독은 evidence가 아니므로 clean task를 승격하지 않는다.
  - Status: resolved — **(a) `todo`/`done` task에 `ahead > 0` 또는 `dirty`가 있으면 EXECUTION으로 파생 승격. 선언 active stage는 유지하고 파생 배지로 구분.**
- [x] **G2. StageBoard 레이아웃과 active stage 밖 task 표시**
  - Impact: 460px 폭 메뉴바 창에서 stage와 repo/branch 활동을 동시에 읽을 수 있는 정보 밀도.
  - 선택지: (a) vertical stage lanes + full-width cards, (b) stage divider + full-width grouped task feed, (c) stage accordion, (d) stage rail + selected-stage focus panel.
  - Recommended default: **full-width task lifecycle feed + inset Stage panel.** bare connected stepper도 일반 task 정보처럼 읽힌다는 runtime feedback을 반영했다. 두 번째 HTML 비교안 A/B/C 중 B는 nested border가 하나 늘지만, stage semantic boundary를 가장 명확하게 만들고 repo activity 전체 폭도 유지한다.
  - Status: resolved/revised — **stage section을 제거하고 active task를 최신순 full-width feed로 표시한다. 각 task row 첫 영역에 `STAGE · <CURRENT>` header와 connected stepper를 가진 bordered inset panel을 둔다. current stage만 filled node + soft halo + accent label로 표시하고 literal bracket은 사용하지 않는다. clean `todo`/`done`은 하단 `OTHER N` disclosure에 둔다.**
- [x] **G2-A. grouped feed의 repo activity 정보 밀도**
  - Impact: 460px task row 높이와 "repo/branch에서 무엇을 하는지"를 설명하는 정보량.
  - 선택지: (a) repo별 2줄 activity stack(branch + Git 수치 / last commit subject + 상대 시각), (b) 1줄 compact(branch + dirty/ahead) + commit subject는 tooltip, (c) changed file 이름 목록까지 contract/UI에 추가.
  - Recommended default: **(a) 2줄 activity stack.** branch와 Git 수치만으로는 작업 의미가 부족하고, changed file 이름은 contract·Git 비용·세로 밀도를 불필요하게 늘린다. 마지막 commit 제목은 현재 dirty 작업 설명으로 오인되지 않도록 `last commit:` label을 붙인다.
  - Status: resolved — **(a) 화면에 `PROJECT`와 task identity를 분리하고, repo별 `REPO / BRANCH / COMMIT` label rail 아래 `DIRTY <N> FILES · AHEAD/BEHIND`, `<subject> · <relative time>`을 직접 표시. changed file 이름은 추가하지 않음. 긴 branch/subject는 ellipsis + title/접근성 이름으로 보존.**
- [x] **G3. provider hook 설치 방식과 source path**
  - Impact: 기존 user hook 보존, portable Bash 의존성, Claude/Codex 독립 선택·신뢰·enable/disable·uninstall, plugin source와 runtime cache의 소유권.
  - 선택지: (a) provider-native plugin 2개를 `<repo>/integrations/agent-events/{claude-code,codex}/`에 두고 전용 `workbranch hooks`가 provider manager를 호출, (b) `~/.claude/settings.json`/`~/.codex/hooks.json`을 CLI가 직접 JSON 병합, (c) 설정 snippet만 출력.
  - Recommended default: **(a) provider-native plugin 2개.** provider가 hook merge/trust/cache/enable/disable/uninstall을 소유하므로 portable Bash JSON parser가 필요 없고 기존 user hook을 직접 수정하지 않는다. Claude/Codex source package를 분리해 사용자가 독립 선택할 수 있다.
  - Status: resolved — **(a) source base는 repo-relative `integrations/agent-events/`; `claude-code/`와 `codex/` provider plugin을 독립 package로 둔다. `workbranch hooks install|status|uninstall --provider ...`은 provider plugin manager를 사용하고 cache 경로를 hardcode하지 않는다. runtime 상태 source of truth는 `<task>/.workbranch/agent.jsonl`이다.**
- [x] **G8. provider plugin marketplace 배포 경로**
  - Impact: Homebrew로 CLI만 설치한 사용자가 repo checkout 없이 provider plugin source를 발견·설치·업데이트할 수 있어야 한다.
  - 선택지: (a) 현재 `tkhwang/workbranch` Git repo 안 provider별 sparse marketplace, (b) Claude/Codex marketplace 전용 Git repo 두 개, (c) CLI release asset에 plugin bundle 첨부 후 local marketplace로 추출.
  - Recommended default: **(a) same-repo sparse marketplace.** CLI command와 provider adapter를 같은 commit에서 변경하고 별도 repository/release asset pipeline을 만들지 않는다. Claude/Codex CLI가 모두 Git marketplace source와 monorepo sparse path를 지원한다.
  - Status: resolved — **(a) `tkhwang/workbranch`를 marketplace Git source로 사용한다. Claude는 sparse path `integrations/agent-events/claude-code`, Codex는 `integrations/agent-events/codex`만 checkout한다. 각 provider root는 marketplace manifest와 `plugins/workbranch-agent-events/` package를 포함한다.**
- [x] **G10. task agent 상태 wire shape**
  - Impact: `list --json` public contract, schema 확장성, 구 CLI fallback, Companion UI coupling.
  - 선택지: (a) optional nested `agent: {state, providers, updatedAt}`, (b) flat `agentState`/`agentProviders`/`agentUpdatedAt`, (c) provider/session 세부 목록까지 public wire에 노출.
  - Recommended default: **(a) optional nested object.** task UI에 필요한 aggregate만 공개하고 session fold는 CLI 내부 구현으로 유지한다. provider나 future aggregate field는 object 안에서 확장할 수 있다.
  - Status: resolved — **(a) 새 CLI는 모든 task에 `agent: {state:"running"|"waiting"|"idle", providers:["claude"|"codex"], updatedAt}`을 출력한다. `providers`는 unexpired non-idle session이 있는 provider만 canonical `claude`, `codex` 순서로 중복 없이 담고, `updatedAt`은 aggregate에 기여한 최신 event epoch second, idle/no-event는 `0`이다. schema/DTO에서 `agent` object 전체는 optional이며 새 Companion ACL은 부재 시 idle/[]/0으로 정규화한다. session 목록은 public wire에 노출하지 않는다.**
- [x] **G9. grouped task feed의 agent/provider 표시**
  - Impact: Claude/Codex 동시 실행 식별과 460px task header 정보 밀도.
  - 선택지: (a) aggregate 상태 + compact provider label, (b) aggregate 상태만 표시, (c) provider별 상태를 별도 행으로 표시.
  - Recommended default: **(a) compact label.** `RUNNING · CLAUDE+CODEX` 한 줄이면 provider identity를 보존하면서 repo activity stack 높이를 늘리지 않는다.
  - Status: resolved/revised — **(a) non-idle task header 우측에 `<STATE> · <PROVIDERS>`를 표시한다. provider는 canonical `CLAUDE`, `CODEX` 순서로 `+` 결합하고 하나면 단독 표시한다. idle은 시각 label을 생략하되 접근성 이름에는 idle 상태를 보존한다. stage는 각 task의 connected lifecycle stepper에서 current node/label만 강조하고 `DERIVED`는 task identity 옆 배지로 유지한다.**
- [x] **G4. Slice C의 이벤트 보존 정책**
  - Impact: `agent.jsonl`이 무한히 커진다. `notifications.jsonl`은 `noti clear`로 명시적으로만 비워진다.
  - 선택지: (a) task lifecycle 동안 append-only + `done/remove` 정리 + 1 MiB doctor 경고, (b) append마다 최근 500줄로 rotation, (c) `agent-state.json` snapshot 원자 덮어쓰기.
  - Recommended default: **(a) lifecycle append-only.** Claude/Codex async hook 동시 writer에서 truncate/rename race를 피하고 짧은 history를 유지한다. 상태 계산은 G6 TTL 안의 이벤트만 사용하며 명시적 task lifecycle에서 정리한다.
  - Status: resolved — **(a) 실행 중 truncate하지 않는다. `list`는 전체 파일을 scan하되 상태 fold에는 최근 24시간 event만 사용한다. `workbranch done`은 `agent.jsonl`을 비우고 `remove`는 state directory와 함께 삭제한다. 1 MiB 초과 시 `doctor`가 경고한다.**
- [x] **G5. agent provider 범위**
  - Impact: 사용자에게 보이는 `running | waiting | idle`이 Claude Code만 뜻하는지, Codex까지 포함한 공통 상태인지 결정한다.
  - 선택지: (a) v1은 Claude Code hook adapter만 제공, (b) v1부터 Claude Code + Codex adapter를 제공하고 설치 시 `claude | codex | both`를 사용자가 선택.
  - Evidence: 공식 Codex Hooks/Config Reference는 user-level `~/.codex/hooks.json` 또는 `~/.codex/config.toml` lifecycle hooks와 `SessionStart`/`UserPromptSubmit`/`PermissionRequest`/`Stop`/`SessionEnd`를 지원한다. command hook은 stdin으로 Claude와 같은 공통 `session_id`/`cwd`/`hook_event_name`을 받고 Codex 전용 `turn_id`를 추가한다. 로컬 `codex-cli 0.148.0`에도 inline hooks와 `hooks.json`이 활성화되어 있음을 확인했다.
  - Recommended default: **(b) Claude Code + Codex, provider별 선택 설치.** 두 provider가 동일한 coarse lifecycle과 공통 입력 필드를 제공하므로 상태 domain을 복제할 이유가 없다. provider adapter는 설치/이벤트 mapping만 소유하고 canonical `agent.jsonl`/집계/UI는 공유한다.
  - Status: resolved — **(b) v1에서 Claude Code + Codex 동시 지원. `workbranch hooks install`은 interactive `Claude Code | Codex | Both` 선택을 제공하고 non-interactive에서는 repeatable `--provider claude|codex`를 사용한다. status/uninstall도 provider별 선택을 지원한다.**
- [x] **G6. session 집계와 stale 만료 정책**
  - Impact: 같은 task의 복수 session, 비정상 종료, 누락된 `SessionEnd`가 task 상태를 영구 오염시키는지 결정한다.
  - 선택지: (a) `(provider, sessionId)`별 최신 상태를 계산하고 running 우선으로 task 집계 + running 6시간/waiting 24시간 TTL, (b) session별 집계하되 TTL 없음, (c) 파일의 마지막 이벤트 1건만 task 상태로 사용.
  - Recommended default: **(a) provider/session별 집계 + TTL self-heal.** Claude/Codex 동시 실행을 서로 덮어쓰지 않고, 정상 종료 hook이 누락돼도 영구 running/waiting을 막는다. TTL은 정상 lifecycle을 대체하지 않고 stale 상태에만 적용한다.
  - Status: resolved — **(a) identity는 `(provider, sessionId)`. unexpired running이 하나라도 있으면 task `running`, running 없이 unexpired waiting이 있으면 `waiting`, 모두 종료/만료면 `idle`. running TTL 6시간(21,600초), waiting TTL 24시간(86,400초).**
- [ ] **G11. permission prompt를 task `waiting`에 포함할지**
  - Impact: "사용자를 기다림" 정확도 대 승인 후 stale waiting, hook 실행 빈도와 refresh 비용.
  - Evidence: Claude `Notification(permission_prompt)`과 Codex `PermissionRequest`는 요청 시작 event만 제공한다. 승인 완료/실행 재개 전용 event가 없어 coarse hook만으로는 `waiting → running` 복귀를 관측할 수 없다. 일반 `PostToolUse`를 추가하면 복귀는 가능하지만 모든 tool call에서 hook process가 실행돼 D5의 저빈도 목표를 깨뜨린다.
  - 선택지: (a) v1 waiting은 `SessionStart`와 `Stop` 이후의 turn-between state로 한정하고 permission prompt는 표시하지 않음, (b) permission prompt를 waiting으로 표시하고 다음 `UserPromptSubmit`/TTL까지 stale 가능성을 수용, (c) `PostToolUse` recovery hook을 추가해 waiting session일 때만 running event를 append하지만 모든 tool call hook overhead를 수용.
  - Recommended default: **(a) permission prompt 제외.** 정확히 복귀시킬 수 없는 상태를 표시하는 것보다 waiting을 turn 경계의 신뢰 가능한 의미로 제한한다. 권한 대기는 provider native UI가 계속 소유한다.
  - Status: **미해결 — 구현 중 lifecycle gap 발견, 사용자 확인 필요.**

## Global Constraints

- Workbranch layout invariant: `<project>`는 Git repo 위의 management folder이며 그 자체는 Git worktree가 아니다. task metadata(`TASK-WORKBRANCH.md`, `AGENTS.md`, `.workbranch/*.jsonl`)는 `<project>/<task>/`에 두고, 실제 Git worktree만 `<project>/<task>/<repo>/`에 둔다. runtime metadata를 nested repo 안에 쓰거나 commit 대상으로 만들지 않는다.
- Agent cwd attribution: hook `cwd`가 정확한 `<task>` root이거나 `<task>/<repo>/...` 하위일 때만 해당 task에 귀속한다. `<project>` root, `<project>/_base/<repo>`, 다른 task 밖 경로, 알 수 없는 경로는 조용히 무시해 잘못된 task event를 만들지 않는다.
- CLI: portable Bash, 명시적 quoting, snake_case 함수명. `bin/workbranch`를 직접 편집하지 않는다 — `src/workbranch/**`를 고치고 `scripts/build-workbranch.sh`로 재생성한다. `scripts/workbranch-sources.txt`의 생성 순서를 유지한다. 사용자 메시지 prefix(`[*]`/`[+]`/`[-] Error:`) 유지.
- Companion: TS/TSX 탭 들여쓰기 + biome, readonly type / 순수 함수 / 의존성 주입 idiom. 테스트는 DOM 없이 순수 함수 + `renderToStaticMarkup`. **새 테스트 의존성 금지.**
- Rust는 thin port를 유지한다 — 도메인 무지, JSON pass-through. 파싱·도메인·ACL은 TS에 둔다(0032/0033 계승).
- 새 git 호출은 반드시 실패에 관대해야 한다 — repo 없음/detached HEAD/remote 없음에서 `?`나 기본값으로 낙하하고 절대 `list --json` 전체를 실패시키지 않는다(`status-format.sh`의 기존 낙하 패턴을 따른다).
- 문서를 건드리면 EN/KO를 같은 PR에서 동기화한다(`README.md`/`README.ko.md`, `docs/ai-agents.md`/`ai-agents.ko.md`, `docs/usage.md`/`usage.ko.md`).
- 커밋은 Conventional Commits, 이모지 prefix 금지.

## public contract (변경 / 비변경)

### 변경하는 것

- **`list --json`의 repo 객체가 확장된다** (`schemaVersion: 1`, 신규 필드는 schema/DTO optional):
  ```
  {name, branch, dirty}
    → {name, branch, dirty, ahead, behind, changedFiles, lastCommitSubject, lastCommitAt}
  ```
  `packages/contract/schema/workbranch-list.schema.json`의 `$defs.repo`와 fixture 3종을 함께 갱신한다. `additionalProperties: false`와 `schemaVersion: 1`은 유지하고, 신규 필드는 `properties`에 추가하되 `required`에는 넣지 않는다. `WorkbranchRepo` DTO도 신규 필드를 optional로 선언하며 TS ACL이 구 CLI 필드 부재를 기본값으로 정규화한다(D3/G7).
- **Slice C에서 `<task>/.workbranch/agent.jsonl`이 신설된다** — canonical NDJSON `{v:1, ts, provider, sessionId, turnId?, event}`. `workbranch agent-event --provider claude|codex` 명령이 유일한 작성자다.
- **Slice C에서 `list --json` task 객체에 optional `agent` object가 추가된다** — `{state, providers, updatedAt}`. 새 CLI는 항상 출력하고 새 Companion은 구 CLI의 object 부재를 `{state:"idle", providers:[], updatedAt:0}`으로 정규화한다. provider/session 원본 목록은 `agent.jsonl` 내부에만 남는다.
- **Slice B에서 `onRootChanged` 시그니처가 바뀐다**: `(callback: () => void)` → `(callback: (root: string) => void)`. Companion 내부 계약이다.

### 변경하지 않는 것

- `schemaVersion` 값(1), `list --global --json`의 최상위 구조(`{schemaVersion, projects, errors}`), 기존 task 필드 전부.
- `TASK-WORKBRANCH.md`의 `status:` 계약과 `todo | planning | in-progress | review | blocked | done` 6개 값. **파생 승격은 표시 계층에서만 일어나고 brief를 다시 쓰지 않는다.**
- 기존 `workbranch` 명령의 argv/동작, `CompanionCommand` 3종(ide/terminal/finder), activity.jsonl 포맷·경로. 신규 `agent-event`/`hooks` 명령만 additive로 추가한다.
- Rust의 thin port 성격과 `workbranch_run` / activity command 계약.
- 0048/0049의 surface별 CSS ownership — 보드 스타일은 `styles/stage-board.css`에만.

## 파일 구조 (touched)

```text
# Slice A — repo 활동 사실
apps/cli/src/workbranch/lib/status-format.sh      # repo 활동 사실 추출 순수 함수 (json 친화 반환)
apps/cli/src/workbranch/commands/list.sh          # repo 객체에 ahead/behind/changedFiles/lastCommit* 추가
apps/cli/tests/cases/list-json.sh                 # repo 키 집합 단언 갱신 + 신규 필드 shape 테스트
packages/contract/schema/workbranch-list.schema.json  # $defs.repo 확장
packages/contract/fixtures/*.json                 # 3종 fixture 갱신
packages/contract/src/index.ts                    # WorkbranchRepo 타입 확장
apps/companion/src/infrastructure/parseContract.ts # 새 필드 optional 검사
apps/companion/src/infrastructure/acl.ts          # 구 CLI 대비 기본값 매핑
apps/companion/src/domain/model.ts                # Repo 타입 확장, 파생 stage 규칙
apps/companion/src/application/state.ts           # drop 제거, 파생 승격, 세로 stage section + OTHER 모델
apps/companion/src/ui/StageBoard.tsx              # grouped task feed + repo/branch activity stack + 파생 표시
apps/companion/src/styles/stage-board.css         # full-width feed row / repo activity / 파생 배지 스타일
apps/companion/tests/{model,acl,task-row}.test.*  # 파생 규칙 + 매핑 + 렌더 계약
DESIGN.md                                         # StageCard 활동 요약 / 파생 stage 계약

# Slice B — partial refresh
apps/companion/src/infrastructure/tauriClient.ts  # refreshRoot(root) 추가, onRootChanged 페이로드 전달
apps/companion/src/infrastructure/workspaceMonitor.ts # root 단위 코얼레싱 + 부분 병합
apps/companion/tests/workspace-monitor.test.ts    # 부분 refresh / 병합 / heartbeat 상호작용
apps/companion/src/application/activity.ts        # partial refresh도 기존 activity diff/append 경로 통과
apps/companion/src/App.tsx                        # global/root refresh를 activity-aware port로 주입
apps/companion/tests/activity-refresh.test.ts     # root baseline/diff/append 회귀 방지
apps/companion/src-tauri/src/watch_roots.rs       # (필요 시) 디바운스 창 재조정

# Slice C — agent 이벤트
apps/cli/src/workbranch/commands/agent-event.sh   # 신규: Claude/Codex hook stdin → provider-neutral agent.jsonl 1줄
apps/cli/src/workbranch/lib/task-state.sh         # agent 상태 읽기 + agent.jsonl 경로
apps/cli/src/workbranch/commands/hooks.sh         # 신규: provider plugin install/status/uninstall orchestrator
apps/cli/src/workbranch/commands/done.sh          # agent.jsonl lifecycle cleanup
apps/cli/src/workbranch/commands/doctor.sh        # provider plugin disabled/outdated 상태 진단
apps/cli/src/workbranch/main.sh                   # agent-event/hooks dispatch
apps/cli/src/workbranch/usage.sh                  # 신규 public command help
apps/cli/src/workbranch/commands/completion.sh    # 신규 command/flags completion
apps/cli/scripts/workbranch-sources.txt           # 신규 source 등록
apps/cli/tests/cases/agent-event.sh               # 신규 테스트 케이스
apps/cli/tests/cases/{meta,completion}.sh          # help/completion public surface
apps/cli/tests/run.sh                             # 케이스 등록
integrations/agent-events/claude-code/.claude-plugin/marketplace.json # Claude sparse marketplace manifest
integrations/agent-events/claude-code/plugins/workbranch-agent-events/.claude-plugin/plugin.json # Claude plugin manifest
integrations/agent-events/claude-code/plugins/workbranch-agent-events/hooks/hooks.json # Claude lifecycle adapter
integrations/agent-events/codex/.agents/plugins/marketplace.json # Codex sparse marketplace manifest
integrations/agent-events/codex/plugins/workbranch-agent-events/.codex-plugin/plugin.json # Codex plugin manifest
integrations/agent-events/codex/plugins/workbranch-agent-events/hooks/hooks.json # Codex lifecycle adapter
docs/ai-agents.md / docs/ai-agents.ko.md          # hook 기반 신호 설명
docs/usage.md / docs/usage.ko.md                   # 신규 public command 사용법
```

---

### Slice A — repo 활동 사실을 `list --json`에 싣고 보드에 표시

> A만 머지해도 위 실측 표의 "안 보임" 6건 중 활동 증거가 있는 건이 살아나고, 카드가 폴더명 이상을 말하게 된다.

#### Task A1: CLI가 repo 활동 사실을 내보낸다

**Red:** `apps/cli/tests/cases/list-json.sh`의 `test_list_json_shape`에 있는 `assert set(repo) == {"name", "branch", "dirty"}`가 새 키 집합을 요구하도록 바꾼다. 이어서 신규 테스트를 추가한다 — 커밋 1건 + 파일 1개 수정 후 `ahead == 1`, `changedFiles == 1`, `lastCommitSubject`가 커밋 제목과 일치, `lastCommitAt`이 양의 정수인지 확인한다. **remote 없음 / base commit 미확정 / repo 폴더 없음 3가지 낙하 경로도 테스트한다** — 각각 `list --json` 전체가 성공하고 해당 필드가 기본값(`0` / `""`)이어야 한다.

**Green:**

- `status-format.sh`에 JSON 친화 추출 함수를 추가한다. 기존 `commit_diff_label`/`remote_diff_label`은 **사람이 읽는 라벨(`±3/2`, `+5`)을 반환하므로 재사용하지 않는다** — `git rev-list --left-right --count`의 원시 정수 2개를 그대로 돌려주는 함수를 새로 만들고, 기존 라벨 함수가 그것을 감싸도록 리팩터해 중복 git 호출을 피한다.
- base commit은 `cmd_status`(`commands/status.sh:35-37`)와 동일하게 `head_commit_full "$(base_repo_path "$name")"`로 얻는다. **base repo 조회는 task마다 반복되므로 repo별로 1회만 계산해 캐시한다** — task 4개 × repo 2개면 base rev-parse가 8회에서 2회로 준다.
- `changedFiles`는 `git status --porcelain | wc -l`. 이미 `is_git_dirty`가 같은 명령을 돌고 있으므로 **한 번 실행해 결과를 재사용하고 `dirty`와 `changedFiles`를 함께 유도한다** — repo당 git 호출 순증가를 최소화한다.
- `lastCommitSubject` / `lastCommitAt`은 `git log -1 --format=%s` / `%ct` 1회 호출로 얻는다.
- 모든 신규 필드는 실패 시 `0` 또는 `""`로 낙하하고 절대 비영점 exit을 전파하지 않는다.
- `scripts/build-workbranch.sh`로 `bin/workbranch` 재생성.

- [x] red 확인
- [x] green: `./apps/cli/tests/run.sh` 전체 통과 + `bin/workbranch` freshness 체크 통과
- [x] repo당 git 호출 수가 2 → 4를 넘지 않음을 확인 (`branch --show-current`, `status --porcelain`, `rev-list`, `log -1`)

#### Task A2: contract 스키마 + 타입 확장

**Red:** `packages/contract/tests/contract.test.mjs`가 fixture 3종(`list-empty`, `list-with-plans`, `list-global-with-error`)을 검증하므로, 스키마에 새 required 필드를 넣으면 기존 fixture가 먼저 빨갛게 된다.

**Green:** `$defs.repo`의 `properties`에 optional 필드 5개를 추가한다(`ahead`/`behind`/`changedFiles`는 `integer, minimum: 0`, `lastCommitSubject`는 `string`, `lastCommitAt`은 `integer, minimum: 0`). `required`에는 추가하지 않고 `additionalProperties: false`와 `schemaVersion: 1`을 유지한다. fixture 3종은 신규 필드를 포함한 현재 CLI 출력 예시로 갱신하고, `src/index.ts`의 `WorkbranchRepo` 신규 필드는 optional로 선언한다.

- [x] G7 확정 — v1 유지 + 신규 필드 schema/DTO optional
- [x] red 확인
- [x] green: `pnpm --filter @workbranch/contract test` 통과 (실제 `bin/workbranch` 출력도 스키마를 만족하는지 포함)

#### Task A3: Companion 파서/ACL이 구 CLI에 관대하게 확장

**Red:** `apps/companion/tests/acl.test.ts`에 두 케이스를 추가한다 — (1) 새 필드가 있는 문서가 값을 보존하며 매핑된다, (2) **새 필드가 없는 구 CLI 문서도 파싱에 성공하고 `ahead: 0` 등 기본값으로 매핑된다.**

**Green:** `parseContract.ts`의 `isRepo`는 **새 필드를 검사하지 않는다**(존재 시 타입만 확인하는 optional 검사). `acl.ts`의 `mapTask`가 `repo.ahead ?? 0` 형태로 기본값을 채우고 신규 activity 필드 존재 여부를 `activityAvailable`로 보존한다. 구 CLI의 `dirty:true` + 필드 부재는 UI에서 `DIRTY`로 표시하고 잘못된 `DIRTY 0`을 만들지 않는다. `domain/model.ts`의 `Repo` 타입을 확장한다.

- [x] red 확인
- [x] green: 신·구 CLI 문서 양방향 통과

#### Task A4: 보드가 파생 stage와 활동 요약을 표시

> **선행:** G1(승격 강도)과 G2(기타 task 표시 형태)가 확정되어야 착수 가능하다.

**Red:** `apps/companion/tests/model.test.ts`에 파생 규칙 테이블 테스트를 추가한다 — `status: todo` + `ahead > 0` 또는 dirty → EXECUTION(파생 표시 on), `status: done` + `ahead > 0` 또는 dirty → EXECUTION(파생 표시 on), `todo`/`done` + strong evidence 없음 → active stage feed 밖, 최근 `lastCommitAt`만 있고 clean/ahead 0 → active stage feed 밖, `status: review` + dirty → REVIEW 유지(**선언 active stage가 파생을 이긴다**). `tests/task-row.test.tsx`에는 (1) active task가 최신순 한 feed로 렌더되는지, (2) 모든 task가 bordered inset Stage panel 안에 `STAGE · <CURRENT>` header와 connected `PLAN → EXECUTION → REVIEW` 3-node stepper를 표시하는지, (3) current node/label만 강조하고 literal bracket이 렌더되지 않는지, (4) task row가 repo별 `name`/`branch`, dirty + `changedFiles`, `ahead`/`behind`, `lastCommitSubject` + 상대 시각을 표시하는지, (5) last commit을 현재 dirty 작업 설명처럼 오인시키지 않는 label/title이 있는지, (6) `RUNNING · CLAUDE+CODEX`/`WAITING · CODEX` canonical label, idle visual omission + accessible state, 파생 배지와 `OTHER N` disclosure가 있는지, (7) `stage-board.css` 대응 class가 존재하는지 추가한다.

**Green:** `domain/model.ts`에 `deriveStage(task)` 순수 함수 추가(`taskStage`는 선언 stage 전용으로 유지하고 파생은 별도 함수로 분리해 두 개념을 섞지 않는다). `application/state.ts`는 기존 `continue` drop을 제거하고 `BoardModel`을 최신순 `cards` + `otherTasks`로 구성하며 각 row에 `stage`와 `derived: boolean`을 보존한다. `StageBoard.tsx`는 stage section을 제거하고 각 task 첫 줄에 전체 lifecycle track을 렌더한 뒤, repo별 2줄 activity stack을 렌더한다:

1. identity line: `repoName · branch` + dirty cue
2. activity lines: `REPO / BRANCH / COMMIT` label rail + `DIRTY <N> FILES`, `ahead/behind`, `<subject> · <relative time>`

branch/subject가 길면 화면에서는 ellipsis하고 전체 문자열은 `title`/접근성 이름에 보존한다. lifecycle panel은 별도 surface/border/radius/padding으로 stage semantic boundary를 만들고, 내부 track은 `auto 1fr auto 1fr auto` grid로 node/label은 intrinsic width를 유지하며 connector가 남은 폭을 흡수한다. current node는 filled + halo, inactive node는 outline이며 bracket text를 쓰지 않는다. 모든 production text는 10px 이상이고 StageTaskRow 전체 launcher는 기존 native button overlay/focus 계약을 유지한다. `stage-board.css`와 `DESIGN.md`에 per-task inset lifecycle feed 계약을 기록한다.

- [x] G1 확정 — `todo`/`done` strong evidence 파생 승격
- [x] G2 확정/revised — latest-first per-task lifecycle feed + repo/branch activity stack + `OTHER N`
- [x] red 확인
- [x] green: `pnpm --filter @workbranch/companion test` + `typecheck` + `lint` 통과
- [x] 실 UI QA: 460×680에서 가로 overflow 없음, Claude/Codex 테마 양쪽 확인

#### Task A5: Slice A 통합 검증

- [x] `./apps/cli/tests/run.sh` / contract test / companion test·typecheck·lint·build 전부 통과
- [x] **구 Companion + 새 CLI**: 새 필드가 무시되고 기존 동작이 유지됨을 확인
- [x] **새 Companion + 구 CLI**: 기본값으로 낙하하고 크래시하지 않음을 확인
- [x] 위 배경의 실측 표를 다시 측정해 "안 보임" 건수가 줄었음을 기록
- [x] `list --global --json` 실행 시간을 재측정해 기록 (baseline 1.655s → Slice A median 1.733s)

Slice A 검증 결과(2026-08-20): CLI 284 tests, contract 3 tests, Companion 15 files / 149 tests, typecheck, lint, Vite build, `git diff --check` 통과. 현재 8 task 중 active stage feed 대상은 기존 2개에서 planning 1 + review 1 + strong repo evidence derived 2개로 4개가 됐다. 사용자 screenshot 피드백으로 PROJECT/TASK와 REPO/BRANCH/STATUS hierarchy를 재현했고, mixed-version `DIRTY 0` root cause를 activity-field 부재로 확인해 `activityAvailable` fallback을 추가했다. 후속 runtime feedback으로 stage별 section을 최신순 per-task lifecycle feed로 교체했다. 첫 HTML 비교에서 connected stepper를 선택한 뒤, bare stepper도 일반 정보처럼 읽힌다는 피드백에 따라 두 번째 비교안 B의 bordered inset Stage panel을 최종 적용했다. Playwright 460×680 Claude/Codex capture에서 lifecycle panel, `DIRTY 28 FILES`, `REPO/BRANCH/COMMIT` label rail, extreme long branch ellipsis와 no-overflow를 확인했다.

---

### Slice B — partial refresh

> **동기:** A5에서 재측정한 시간이 baseline 1.5s보다 늘어난다. B는 그 회귀를 흡수하고 C의 전제조건을 만든다. 0033이 후속으로 미뤄둔 항목이다.

#### Task B1: root 페이로드를 살려 단일 root만 재조회

**Red:** `apps/companion/tests/workspace-monitor.test.ts`와 `activity-refresh.test.ts`에 추가한다 — (1) `roots-changed`가 root A를 실으면 A만 재조회하고 B는 재조회하지 않는다, (2) 부분 결과가 기존 `GlobalState`에 **해당 project만 교체하는 방식으로 병합**되고 나머지 project는 참조가 유지된다, (3) heartbeat는 계속 global 전체 조회를 수행한다(누락 self-heal 보장), (4) 같은 root의 연속 이벤트가 코얼레싱되고 **서로 다른 root의 이벤트는 서로를 취소하지 않는다**, (5) root refresh도 이전 root baseline과 비교해 기존 `activity.jsonl` 이벤트를 append한다, (6) heartbeat full refresh와 root refresh가 겹쳐도 snapshot 이후 변경을 잃지 않는다, (7) partial failure는 기존 project를 보존하고 root error를 upsert하며 다음 성공이 해당 error를 제거한다.

**Green:**

- `tauriClient.ts`: `onRootChanged` 시그니처를 `(root: string) => void`로 바꾸고 `listen<string>`의 `event.payload`를 전달한다. `refreshRoot(root)`를 추가해 **이미 등록되어 있으나 미사용인 `workbranch_list` command**를 호출하고 `mapListDocumentToProject`로 매핑한다. Rust 변경 0줄.
- `workspaceMonitor.ts`: 코얼레싱을 root 단위로 확장한다. 기존 단일 `queued: boolean`을 pending root 집합으로 바꾸되, **집합이 비어있는 heartbeat 경로는 기존 global 조회를 그대로 쓴다.**
- `activity.ts` / `App.tsx`: global/root refresh가 같은 per-root baseline과 `activityEventsForRefresh`를 공유하게 확장한다. partial refresh가 UI state만 바꾸고 activity 기록을 우회하는 경로를 금지한다.
- 부분 실패는 해당 project만 error로 표시하고 나머지 상태를 보존한다.

- [x] red 확인
- [x] green: companion test·typecheck·lint 통과
- [x] 단일 root 변경 시 실행 시간이 global 대비 유의미하게 짧음을 측정 기록

#### Task B2: 디바운스/heartbeat 재조정

- [x] 부분 refresh 도입 후 500ms 디바운스(`watch_roots.rs`)와 5분 heartbeat(`App.tsx:170`)가 여전히 적절한지 판단하고, 바꾼다면 근거를 이 문서에 기록
- [ ] agent가 활발히 파일을 쓰는 상태에서 CPU/refresh 빈도를 관찰해 폭풍이 없음을 확인

Slice B 검증 결과(2026-08-20): root payload 전달, root별 coalescing, 서로 다른 root 보존, full heartbeat 우선순위, partial error upsert/clear, activity baseline 공유 회귀 테스트를 포함해 Companion 15 files / 148 tests, typecheck, lint, Vite build 통과. 현재 project 실측 local `list --json` median 0.332s, global median 1.555s로 partial 경로가 약 4.7배 짧다. 500ms watcher debounce는 local 조회보다 길어 동일 root 폭풍을 충분히 흡수하고, 5분 heartbeat는 누락 self-heal 전용이므로 둘 다 유지한다. live write-storm CPU 관찰은 Slice C event writer까지 연결한 최종 manual QA에서 수행한다.

---

### Slice C — agent 이벤트 (hook → `agent.jsonl`)

> **선행:** Slice A/B 머지 완료 + G3(설치 방식) / G4(보존 정책) 확정. **A/B 없이 머지하지 않는다.**
>
> **범위:** Slice A/B가 "코드가 어디까지 왔나"(git 사실)를 답한다. C는 git으로 유도 불가능한 단 하나의 축 — **"지금 agent가 돌고 있나, 아니면 나를 기다리나"** — 만 추가한다.

#### Task C1: `workbranch agent-event` 명령

**Red:** `apps/cli/tests/cases/agent-event.sh` 신설. Claude Code와 Codex fixture를 각각 stdin으로 흘려 `<task>/.workbranch/agent.jsonl`에 canonical 1줄이 append되는지 확인한다. 공통 단언은 `{v:1, provider, sessionId, event}`이고 Codex fixture만 `turnId`를 보존한다. 두 provider 모두 `cwd`가 정확한 task root이거나 `<task>/<repo>/...`이면 올바른 task로 귀속되는지(`resolve_current_task_from_cwd` 재사용) 확인한다. 반대로 management project root, `_base/<repo>`, 다른 task 밖 경로, 알 수 없는 cwd, 깨진 JSON은 조용히 exit 0 하고 어떤 task log도 만들지 않아야 한다(hook은 절대 agent 세션을 깨거나 잘못 귀속하면 안 된다). concurrent append가 기존 줄을 잃지 않는지도 확인한다. G4 acceptance로 append 중 truncate/rename이 없고, `workbranch done` 후 파일이 비며 `remove` 후 state directory가 삭제되고, 1 MiB 초과 파일을 `doctor`가 경고하는지 테스트한다. `--provider` 누락/미지원 값은 직접 CLI 호출에서는 usage error지만 provider hook wrapper는 항상 명시값을 전달한다.

**Green:** `commands/agent-event.sh` 신설. `--provider claude|codex`를 받고 stdin JSON에서 공통 `hook_event_name`/`session_id`/`cwd`와 optional `turn_id`를 추출해 canonical 1줄을 append한다. provider별 event 이름은 command 내부 normalization table로 domain event에 매핑한다. `lib/task-state.sh`에 dependency-free `json_top_level_string <key>` extractor를 추가해 top-level JSON string escape(`\"`, `\\`, `\uXXXX`)와 malformed input을 처리하고, 출력에는 기존 `json_escape`를 재사용한다. jq/Python/Node runtime 의존성은 도입하지 않는다. canonical line은 한 번의 `printf >>`로 append해 line 단위 writer atomicity를 유지한다. `scripts/workbranch-sources.txt`에 등록 후 `bin/workbranch` 재생성.

- [x] G4 확정 — lifecycle append-only + done/remove cleanup + 1 MiB doctor warning
- [ ] red 확인
- [ ] Claude/Codex payload의 quote/backslash/unicode escape와 malformed/nested distractor key가 top-level extractor를 속이지 않는지 확인
- [ ] green: `./apps/cli/tests/run.sh` 통과

#### Task C2: hook 설치 경로

**Green:** repo source package를 provider별 self-contained sparse marketplace로 만든다. Claude root `integrations/agent-events/claude-code/`는 `.claude-plugin/marketplace.json` + `plugins/workbranch-agent-events/`, Codex root `integrations/agent-events/codex/`는 `.agents/plugins/marketplace.json` + `plugins/workbranch-agent-events/`를 가진다. `workbranch hooks install`은 provider manager에 Git source `tkhwang/workbranch`와 provider sparse path를 등록한 뒤 `workbranch-agent-events` plugin을 설치한다. interactive 실행은 `Claude Code | Codex | Both`를 묻고 기본 선택은 Both, automation은 repeatable `--provider claude|codex`를 사용한다. `status`/`uninstall`도 같은 provider selector로 provider plugin manager를 호출하며 선택하지 않은 provider와 기존 user hook은 절대 건드리지 않는다. Claude Code plugin은 D5의 5개 coarse lifecycle 이벤트, Codex plugin은 D5의 대응 5개 lifecycle 이벤트만 배선한다. 모든 writer는 D5-A의 동기/무출력/1초 timeout 계약을 따른다. 설치된 cache 위치는 provider manager의 private implementation으로 취급해 workbranch가 읽거나 hardcode하지 않는다. provider의 non-managed hook trust review를 우회하지 않으며, `hooks install` 완료 메시지와 `hooks status`는 `installed / pending-trust / enabled / disabled / outdated`를 구분한다. 새/변경된 hook hash가 pending trust면 `/hooks` 등 provider-native review 경로를 안내하고 자동 승인 flag를 사용하지 않는다. `doctor`는 plugin absence를 사용자의 미선택으로 허용하고, 설치된 provider plugin의 pending-trust/disabled/outdated/invalid 상태만 issue로 보고한다.

- [x] G3 확정 — provider-native source packages + provider manager install/cache/uninstall
- [x] G5 확정 — Claude Code + Codex, install/status/uninstall provider 선택
- [x] G8 확정 — `tkhwang/workbranch` same-repo sparse marketplaces
- [ ] Claude/Codex provider manifest validation 통과
- [ ] provider CLI stub으로 marketplace add sparse path + plugin install/status/uninstall argv를 단언
- [ ] fresh install과 hook hash 변경 후 provider-native pending-trust 상태가 노출되고, workbranch가 trust를 자동 우회하지 않음을 확인
- [ ] 기존 hook 보존 + provider별 재설치 idempotent 확인
- [ ] provider 하나의 uninstall이 자기 plugin만 제거하고 다른 provider/user hook을 보존함을 확인

#### Task C3: agent 상태를 `list --json`과 카드에 노출

- [x] G5/G6 확정 — Claude/Codex `(provider, sessionId)` 집계 + running 6h / waiting 24h TTL
- [ ] `agent.jsonl`을 append file order로 읽어 `(provider, sessionId)`별 최신 이벤트로 fold하는 순수 함수를 추가하고 `running > waiting > idle` 우선순위로 task 상태를 유도한다. 동일 epoch second 이벤트도 file order가 승리해야 하며 `ts`로 재정렬하지 않는다. `RUNNING_STALE_AFTER_SECONDS=21600`, `WAITING_STALE_AFTER_SECONDS=86400` 상수를 한 곳에서 소유하고 경계값(`ttl-1`, `ttl`, `ttl+1`)을 테스트한다.
- [ ] 정상 `SessionEnd`는 TTL과 무관하게 즉시 해당 session을 idle로 만들고, 다른 provider/session이 running이면 task aggregate는 running을 유지한다.
- [x] G10 확정 — optional nested `agent: {state, providers, updatedAt}`; sessions는 CLI 내부
- [ ] provider/session별 최신 상태에서 task `agent` aggregate를 만든다. `providers`는 unexpired non-idle provider만 `claude`, `codex` canonical 순서로 dedupe하고, `updatedAt`은 aggregate 최신 event, idle/no-event는 0으로 둔다.
- [ ] contract schema의 optional task `agent` object(`state` enum, canonical provider enum array, nonnegative `updatedAt`)와 fixture/type/parser/ACL을 갱신한다. object 내부는 `additionalProperties:false`, 세 필드는 present object에서 required, object 자체만 optional이다. 신·구 CLI fixture 모두 통과시킨다.
- [x] G9 확정 — non-idle `<STATE> · <PROVIDERS>` compact label, idle visual omission
- [ ] grouped task feed header에 canonical agent/provider label을 표시하고 `DESIGN.md`에 idle/derived/stage 중복 제거 계약을 기록한다.
- [ ] `docs/ai-agents.md` / `ai-agents.ko.md`에 hook 기반 신호 설명 추가 (EN/KO 동기화)

#### Task C4: Slice C 통합 검증

- [ ] 전 계층 테스트 통과
- [ ] **hook 미설치 사용자에게 회귀가 없음을 확인** — `agent.jsonl` 부재 시 상태는 `idle`이고 카드는 Slice A 상태로 동작해야 한다
- [ ] Claude Code/Codex를 각각 단독 및 동시에 여러 task에서 실행해 각 task/provider 상태가 독립적으로 갱신되는지 실측
- [ ] 강제 종료로 `SessionEnd`가 누락된 fixture에서 running 6시간/waiting 24시간 경계 이후 `idle` self-heal 확인
- [ ] `hooks install --provider claude`, `--provider codex`, 두 flag 병용 및 interactive Both가 동일한 최종 설치 상태를 만드는지 확인
- [ ] provider 하나만 uninstall해도 다른 provider hook과 기존 user hook은 유지되는지 확인
- [ ] Slice B의 부분 refresh와 결합해 refresh 폭풍이 없음을 확인

---

## 성공 기준

1. 배경의 실측 표를 재측정했을 때, **활동 증거가 있는 task가 보드에서 사라지지 않는다** (`feature-cpq-task-a` 유형).
2. 어떤 task도 조용히 drop되지 않는다 — active stage feed에 없으면 `OTHER N` disclosure에 있다.
3. task row가 폴더명 이상을 말한다 — repo별 branch, dirty/변경 파일 수, ahead/behind와 `last commit` 제목·상대 시각을 2줄 activity stack으로 표시한다.
4. **agent가 `status:`를 한 번도 갱신하지 않아도 보드가 살아있다.**
5. root 변경 후 partial refresh 시간이 Slice A 이전 global refresh baseline(1.5s)보다 유의미하게 짧고, 다른 project를 재조회하지 않는다 (Slice B 완료 기준).
6. 신·구 CLI × 신·구 Companion 4개 조합 모두에서 크래시가 없다.
7. `list --global --json` heartbeat 경로는 Slice A 추가 git 사실의 비용을 별도 측정해 기록하고, 허용 회귀 예산을 넘으면 CLI 최적화를 후속이 아니라 Slice B 안에서 수행한다.
8. Claude/Codex를 단독 또는 함께 설치할 수 있고, task header는 non-idle aggregate를 `RUNNING · CLAUDE+CODEX` 형태로 표시한다. provider hook trust는 native review flow를 거치며 workbranch가 자동 우회하지 않는다.
