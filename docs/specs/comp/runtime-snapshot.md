# COMP · Runtime snapshot

companion 이 agent runtime 상태를 읽는 곳은 Rust `RuntimeService`(`apps/companion/src-tauri/src/runtime_service.rs`) 하나다. main 창, dashboard 창, screensaver 서비스([screensaver](screensaver.md))는 모두 이 서비스가 보내는 snapshot 을 받아 쓰고, 스스로 CLI 를 실행하지 않는다. 숨겨진 창도 타이머 없이 최신 상태를 받는다.

## 경계
- 데이터 원천은 `workbranch runtime --json` 이 내는 runtime 문서(schema 1, `packages/contract` 의 `WorkbranchRuntimeDocument`)다.
- companion 은 `state.sqlite3` 를 직접 읽지 않는다. SQLite 는 수집기 버전과 함께 바뀌는 agent-runtime 내부 저장소이고, schema 가 있는 CLI 문서가 계약이다.
- 감시 디렉터리는 `WORKBRANCH_RUNTIME_DIR` 이 있으면 그 경로, 없으면 `$HOME/.workbranch/runtime` 이다(agent-runtime 의 `runtime_dir()` 과 같은 규칙).

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
