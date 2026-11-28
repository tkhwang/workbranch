# COMP · Runtime snapshot

companion 이 agent runtime 상태를 읽는 곳은 Rust `RuntimeService`(`apps/companion/src-tauri/src/runtime_service.rs`) 하나다. main 창, dashboard 창, screensaver 서비스([screensaver](screensaver.md))는 모두 이 서비스가 보내는 snapshot 을 받아 쓰고, 스스로 CLI 를 실행하지 않는다. 숨겨진 창도 타이머 없이 최신 상태를 받는다.

## 경계
- 데이터 원천은 `workbranch runtime --json` 이 내는 runtime 문서(schema 1, `packages/contract` 의 `WorkbranchRuntimeDocument`)다.
- companion 은 `state.sqlite3` 를 직접 읽지 않는다. SQLite 는 수집기 버전과 함께 바뀌는 agent-runtime 내부 저장소이고, schema 가 있는 CLI 문서가 계약이다.
- 감시 디렉터리는 `WORKBRANCH_RUNTIME_DIR` 이 있으면 그 경로, 없으면 `$HOME/.workbranch/runtime` 이다(agent-runtime 의 `runtime_dir()` 과 같은 규칙).

- 세션은 선택 필드 `transitions`(최근 24시간 상태 전환, 그 시작 시점에 유효했던 전환부터, 최대 500개)와 `totals`(보관된 기록 전체의 상태별 초)를 가질 수 있다. 이전 수집기는 둘 다 보내지 않으므로 소비자는 없을 때를 다뤄야 한다(dashboard 링은 현재 상태만 그린다). 문서 schema 는 1 그대로다.
- 세션은 선택 필드 `messages`(최근 요청 `prompt` 와 턴을 끝낸 응답 `response`, 오래된 것부터 최대 3개, 각각 `kind`·`text`·`at`)도 가질 수 있다. 글은 `prompt`·`response` 와 같은 규칙으로 정리하고 300자로 자른다. 이전 수집기는 보내지 않는다.
- 다음 세 필드(`turns`·`calls`, `todos`, `lastTurn`)는 dashboard 링을 위한 것이다 ([COMP004](../../intents/COMP004-ring-dashboard.md)).
- 세션은 선택 필드 `turns`(최근 3시간에 시작한 turn, 오래된 것부터 최대 50개, 각각 `kind`·`at`)와 `calls`(최근 3시간의 tool 호출, 오래된 것부터 최대 300개)도 가질 수 있다. `turns` 의 `kind` 는 사용자 요청(`UserPromptSubmit`, turn id 가 바뀔 때만)이면 `prompt`, subagent 보고(Claude Code `SubagentStop`, 플러그인 `hooks.json` 에 등록)면 `agent` 다. `SubagentStop` 은 `agent_id` 로 정해지는 subagent 세션을 턴 종료로 바꾸고 그 세션에 `agent` turn 을 남긴다. 부모 세션의 상태는 바꾸지 않고, `agent_id` 가 없으면 무시한다. `calls` 는 각각 `tool`(provider 가 보낸 도구 이름 그대로), `files`(건드린 파일의 이름, 경로가 아니다. 없으면 빠짐, 최대 8개), `failed`(provider 가 실패를 알렸을 때만 `true`, Claude Code `PostToolUseFailure`), `at`(호출 시작 시각)이다. 파일 이름은 `file_path`·`notebook_path`(Claude Code), `apply_patch` 패치의 `*** Add/Update/Delete File:`·`*** Move to:` 줄(Codex)에서 읽는다. 명령 글, 편집 내용, tool 결과는 남기지 않는다. 수집기는 호출을 `state.sqlite3` 의 `tool_calls` 테이블(schema 3)에 24시간 보관하고, 같은 `tool_use_id` 는 한 번만 남긴다. 이전 수집기는 둘 다 보내지 않는다.
- 세션은 선택 필드 `todos`(`total`·`done`·`active`)도 가질 수 있다. agent 의 todo 도구가 마지막으로 남긴 목록의 크기, 끝난 수, 진행 중인 항목의 글(없으면 빠짐)이다. 수집기는 성공한 호출(`PostToolUse`)만 반영한다: Claude Code `TodoWrite`(`todos[{content, status}]`)와 Codex `update_plan`(`plan[{step, status}]`)은 목록 전체를 바꾸고, Claude Code `TaskCreate`(`subject`)는 하나를 더하며(id 는 응답의 `task.id`·`taskId`·`id` 순으로 찾고, 없으면 만든 순서로 매긴다), `TaskUpdate`(`taskId`, `status`, `subject`)는 그 id 의 상태·글을 바꾸거나 `deleted` 면 지운다. 상태는 `completed`·`in_progress`·`pending`·`deleted` 만 알아듣고, 모르는 모양의 입력은 무시해 이전 목록을 지킨다. 글은 `prompt` 와 같은 규칙으로 정리하고 120자로 자른다. 목록(최대 50개)은 세션 행에만 두고 snapshot 에는 요약만 싣는다. Claude Code `TaskCreate`·`TaskUpdate` 모양은 실제 세션(2.1.332)으로 확인했다. Claude Code 는 현재 모델에서 todo 도구를 기본으로 주지 않으므로(`CLAUDE_CODE_ENABLE_TODO_TOOLS=1` 로 켬) 켜지 않은 세션에는 `todos` 가 없다. `TodoWrite` 실제 payload 와 Codex `update_plan` hook 은 확인되지 않았다. 모양이 다르면 todo 가 비어 보일 뿐 다른 기록에는 영향이 없다. 이전 수집기는 보내지 않는다.
- 세션은 선택 필드 `lastTurn`(`startedAt`·`filesChanged`·`linesAdded`·`linesRemoved`·`tests`·`commits`)도 가질 수 있다. 마지막 사용자 요청 turn 이 끝난(`finished`) 세션에만 있고, snapshot 이 `tool_calls` 에서 그 turn 의 시작(`turns` 의 마지막 `prompt`) 이후 호출로 계산한다(저장하지 않는다). `filesChanged` 는 편집 호출(`Edit`·`MultiEdit`·`Write`·`NotebookEdit`·`apply_patch`)이 건드린 서로 다른 파일 수, `linesAdded`·`linesRemoved` 는 편집 입력으로 센 줄 수다: Codex 패치는 `+`·`-` 줄(정확), Claude Code `Edit` 는 이전·새 글의 줄을 한 번씩 짝지어 남는 줄(근사), `Write`·`NotebookEdit` 는 새 글의 줄 수를 추가로 센다. 수집기는 git 을 실행하지 않는다. `tests` 는 turn 의 마지막 테스트 명령 결과다: 셸 명령(`Bash`)을 `&&`·`||`·`;`·`|`·줄바꿈으로 나눈 부분 중 하나라도 테스트 실행기(`cargo test`/`nextest`, `pnpm`·`npm`·`yarn`·`bun`·`npx` 의 `test`/`vitest`/`jest`, `vitest`, `jest`, `pytest`, `python -m pytest`, `go`·`mvn`·`gradle`·`make`·`swift`·`dotnet` 의 `test`, `…/tests/run.sh`)면 테스트로 본다. Claude Code 는 실패를 `PostToolUseFailure` 로 알리므로 `PostToolUse` 면 `passed`, 다른 provider 는 응답에 종료 코드(`exit_code`·`exitCode`)가 있을 때만 `passed`·`failed` 이고 없으면 `unknown`, 테스트 명령이 없으면 `none` 이다. `commits` 는 실패하지 않은 `git … commit` 명령 수다(`--dry-run` 제외). 명령 글은 남기지 않고 분류만 `tool_calls.kind`(`test`·`commit`, 성공이 확인되면 ` ok`)에 남긴다. 이전 수집기는 보내지 않는다.

## 읽는 시점
- 디렉터리에 변경 이벤트가 오면, 마지막 이벤트 뒤 200ms 동안 조용할 때 한 번 읽는다. 쓰기가 이어져도 첫 이벤트 뒤 1초 안에는 읽는다. hook 이벤트 하나가 저장소를 여러 번 건드려도 읽기는 한 번이다.
- 변경이 없어도 마지막 읽기 뒤 60초마다 읽는다. 쓰기 없이 `stale` 로 바뀌는 세션과 감시가 놓친 변경을 잡는다.
- 감시는 macOS FSEvents(경로 기준)라 runtime 디렉터리가 지워졌다 다시 생겨도 이어진다. inode 기준 backend(inotify 등)로 옮기면 다시 등록해야 한다.

## Snapshot
| 필드 | 뜻 |
|---|---|
| `sequence` | 읽기마다 1씩 느는 번호 |
| `readAtMs` | 읽은 시각(epoch ms) |
| `document` | 읽기에 성공하면 CLI 가 낸 문서(문자열), 실패하면 `null` |
| `error` | 읽기에 실패하면 오류 메시지, 성공하면 `null` |

- 읽을 때마다 모든 창에 `runtime-snapshot` 이벤트로 보낸다.
- 늦게 열린 창은 `runtime_snapshot` command 로 마지막 snapshot 을 받는다(아직 한 번도 읽지 않았으면 `null`).
- 프로세스 안 소비자(screensaver)는 `RuntimeService::subscribe()` 채널로 받는다.
- 서비스는 문서를 해석하지 않고 그대로 넘긴다. 계약 검사는 소비자가 한다.

## 창의 구독 (`application/useRuntimeSessions.ts`)
- listener 를 먼저 달고 `runtime_snapshot` 을 읽는다. 지금 가진 `sequence` 보다 크지 않은 snapshot 은 버리므로, push 와 읽기 응답의 순서가 엇갈려도 새 값을 옛 값이 덮지 않는다.
- 문서는 `parseRuntimeDocument()` 로 계약을 검사해 세션 목록으로 바꾼다.
- 읽기가 실패했거나 계약을 어긴 문서면 마지막 세션을 `observation: "uncertain"` 으로 바꿔 보여 주고 오류를 상태에 둔다. main 창은 CLI 호환성 오류를 CLI 업데이트 안내로, 그 밖의 오류를 오류 문구로 보여 준다.
- 첫 읽기가 실패해도 listener 는 남아 있어 다음 push 로 회복한다.
- 구독을 끄면 마지막 세션은 화면에 남고 오류는 지운다.

## 목록 데이터
task·repo·branch 목록은 이 경로가 아니라 각 창의 workspace monitor(`roots-changed` 이벤트 + 5분 heartbeat)로 받는다. watcher 등록은 main 창이 하고, dashboard 창은 이벤트를 듣기만 한다. runtime 읽기는 Git 조회를 일으키지 않는다.
