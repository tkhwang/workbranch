# 0033 Companion 응답성 회귀 수정 — 메인 스레드 논블로킹화 + watch 범위 축소 계획

> **agentic worker 지침:** 실행 시 `superpowers:executing-plans`(또는 `subagent-driven-development`)를 사용한다. Rust port 변경(async/`spawn_blocking`, watch 이벤트 필터)은 순수 함수로 분리해 `cargo test`로 검증하고, 비동기화 자체는 `cargo clippy -- -D warnings` + 수동 `tauri dev` 응답성 확인으로 검증한다. TS application 로직(monitor 코얼레싱, heartbeat)은 `superpowers:test-driven-development`(red→green→refactor)로 구현하고 `pnpm --filter @workbranch/companion test`(vitest)로 검증한다. **이 계획은 0032의 아키텍처 결정을 그대로 계승한다 — Rust는 thin port(도메인 무지, JSON pass-through), 파싱/도메인/ACL은 TS, `workbranch` CLI public contract(`list --json` schemaVersion 1, argv, 명령 동작)는 변경하지 않는다.** companion 내부 IPC/watch 동작만 손댄다. 문서를 건드리면 EN/KO를 같은 PR에서 동기화한다.
>
> **시리즈 위치:** 0019(Swift companion) → **0032(Tauri+React 재작성)** 위에 얹는 **회귀 수정**이다. 0032가 Swift→Tauri로 스택을 바꾸면서 도입된 응답성 회귀를 고친다. 0032의 제품 결정·데이터 계약·BC 경계는 전부 유지하며, "idle 비용 거의 0 + 이벤트 직후 즉시 갱신" 경험을 회복하는 것이 목표다.

**목표:** Tauri companion이 "자주 hang 되고 응답성이 떨어지는" 회귀를 제거한다. 근본 원인 2가지 — (1) blocking subprocess/IO가 **메인 스레드(이벤트 루프/트레이/webview)** 에서 실행됨, (2) 프로젝트 루트 전체에 대한 **재귀 FS watch**가 `node_modules`/빌드 산출물 같은 무관한 churn으로 refresh 폭풍을 일으켜 (1)의 블로킹을 반복 트리거함 — 을 각각 해소한다. workbranch 구조상 `<task>/`는 git 미관리 metadata/agent workspace이고, 실제 source repo는 `<task>/<repo>/` linked worktree이며, linked-worktree gitdir metadata는 `_base/<repo>/.git/worktrees/...` 쪽에 있을 수 있다. 따라서 `TASK-WORKBRANCH.md`/plan metadata와 source file 변경은 반드시 relevant이고, `list --json`이 repo `branch`/`dirty`를 보여주므로 `.git` 전체 blanket-ignore는 하지 않는다. 추가로 0032가 설계상 의도했으나 구현되지 않은 **heartbeat fallback**과 monitor refresh **코얼레싱**을 더해 누락 이벤트/중첩 실행에 대한 회복력을 확보한다.

---

## 문제

0032로 Swift native menu bar app을 Tauri v2 + React로 재작성한 뒤, companion이 자주 멈추고(hang) 응답성이 떨어진다. Swift 버전에는 없던 회귀다.

### 근본 원인 #1 (주범): blocking 작업이 메인 스레드에서 실행됨

Tauri v2에서 **`async`가 아닌 동기 `#[tauri::command]` 함수는 메인 스레드(window/tray/webview 이벤트 루프를 돌리는 스레드)에서 실행**된다. 현재 `apps/workbranch-companion/src-tauri/src/lib.rs`의 커맨드 5개가 전부 동기 `fn`이다:

- `workbranch_list_global`(`lib.rs:90`), `workbranch_list`(`lib.rs:84`), `workbranch_run`(`lib.rs:111`) → 모두 `run_workbranch`(`lib.rs:217`)를 경유해 **`std::process::Command::…output()`** 호출. 이는 `workbranch` CLI 프로세스를 spawn→실행→종료까지 **블로킹 wait** 한다. PATH 해석 + 프로세스 생성 + CLI 런타임 부팅 + 워크스페이스 스캔 + `git status --porcelain` 합산으로 수십~수백 ms가 걸리며, 그 시간 동안 메인 스레드가 멈춰 webview와 트레이가 얼어붙는다.
- `watch_roots`(`lib.rs:123`)는 `notify` watcher를 동기로 구성한다. 등록 자체는 macOS FSEvents에서 저렴하지만, 동기 커맨드라 메인 스레드에서 실행된다.
- `append_activity_events`(`lib.rs:103`)는 동기 파일 I/O(`activity_store::append_activity_events_default`).

즉 사용자가 트레이를 클릭하거나 watch 이벤트로 자동 갱신될 때마다 메인 스레드가 CLI 종료까지 블로킹된다 = "hang".

### 근본 원인 #2 (증폭기): 재귀 FS watch가 refresh 폭풍을 일으킴

`watch_roots`가 **프로젝트 루트 전체를 `RecursiveMode::Recursive`로 감시**한다(`lib.rs:146`). 루트에는 `node_modules`, `target`, `dist` 등 변경이 끊임없지만 Companion 상태와 무관한 디렉터리가 들어있다. watcher 콜백(`lib.rs:138-145`)은 **이벤트 경로를 전혀 보지 않고**(`event.is_err()`만 체크) 무조건 `roots-changed`를 emit한다. 디바운스는 루트당 500ms(`should_emit_root_change`, `lib.rs:160`)뿐이라, 작업 중인 프로젝트에서는 노이즈성 변경이 500ms마다 한 번씩 통과한다. 반면 workbranch의 task root 자체는 git repo가 아니라 `TASK-WORKBRANCH.md`/`.workbranch/**` 같은 metadata를 담고, 실제 repo는 linked worktree인 `<task>/<repo>/`다. linked worktree의 `.git`은 파일일 수 있고 실제 gitdir은 `_base/<repo>/.git/worktrees/...`에 있을 수 있으므로, `.git` 전체를 ignore하면 일부 git command 이후 repo `branch`/`dirty` freshness를 heartbeat에 의존하게 될 수 있다.

데이터 흐름:
```
node_modules/빌드 산출물 같은 무관한 변경
  → (경로 무필터) roots-changed emit (루트당 500ms 디바운스)
  → 프론트 scheduleRefresh (workspaceMonitor.ts:38)
  → refreshWithActivity → workbranch_list_global invoke
  → 메인 스레드 블로킹 CLI spawn ❌ 프리즈
```

따라서 hang 빈도가 감시 중인 프로젝트의 파일시스템 활동량에 정비례한다("자주" 멈추는 이유). 또한 `scheduleRefresh`(`workspaceMonitor.ts:38`)는 진행 중 refresh를 await/취소하지 않고 `pending`을 덮어쓰므로, 이벤트가 몰리면 CLI invoke가 **중첩 실행**될 수 있다.

### 부수 문제 (회복력 공백)

- 0032 계획은 "watcher가 놓칠 때 대비 TS application 레벨에서 느린 heartbeat(예: 5분) fallback 재조회"(0032 §Rust port, §Slice E)를 명시했으나, 현재 프론트엔드에 `setInterval`/`setTimeout`이 **하나도 없다**(`src/` 전체 grep 결과 0건). 이벤트를 놓치면 영원히 stale.
- watch 이벤트는 어떤 root가 바뀌었는지 무시하고 항상 global 전체 재조회를 한다(부분 refresh 최적화는 0032에서 후속으로 미뤄둠 — 본 계획 범위 밖).

## 현재 repo 근거

- 동기 커맨드 등록: `lib.rs:258-264`(`generate_handler!`)에 5개 모두 동기 `fn`으로 등록됨.
- blocking subprocess: `run_workbranch`(`lib.rs:217-231`)의 `Command::new(bin).…output()`; `run_pbcopy`(`lib.rs:233-247`)도 `spawn` + `wait_with_output`.
- 재귀 watch + 경로 무필터 콜백: `watch_roots`(`lib.rs:123-158`), 특히 `RecursiveMode::Recursive`(`lib.rs:146`)와 콜백(`lib.rs:138-145`).
- 디바운스: `should_emit_root_change`(`lib.rs:160-173`), `DEBOUNCE_WINDOW = 500ms`.
- 동기 파일 I/O: `activity_store.rs` `append_activity_events_*`.
- 프론트 트리거/중첩: `workspaceMonitor.ts:22-44`(`refreshAndWatch`/`scheduleRefresh`/`onRootChanged`), `App.tsx:100-122`(monitor 구동).
- heartbeat 부재: `src/` 내 타이머 0건.
- 의존성: `src-tauri/Cargo.toml` — `tauri 2.9.5`, `notify 8`, `tauri-plugin-positioner 2`. (tokio 직접 의존 없음 — `tauri::async_runtime` 사용으로 충분.)

## 결정 사항 (확정)

- [x] **무거운 커맨드를 `async fn` + `tauri::async_runtime::spawn_blocking`으로 메인 스레드 밖에서 실행.** `async` 커맨드는 메인 스레드가 아닌 async task에서 구동되고, 블로킹 body는 `spawn_blocking`으로 블로킹 풀에 넘겨 async 워커도 굶기지 않는다. **신규 의존성(tokio 등) 추가 없음** — Tauri가 재노출하는 `tauri::async_runtime::spawn_blocking`만 쓴다. 프론트는 이미 전부 `await invoke(...)`라 **TS 변경 불필요**.
- [x] **재귀 watch는 유지하되 콜백에서 이벤트 경로를 필터링한다.** macOS FSEvents 백엔드에선 재귀 등록이 저렴하고 비용은 이벤트 볼륨이므로, 등록 범위 축소보다 **이벤트 경로 ignore 필터**가 올바른 레버다. `node_modules`/`target`/`dist`/`build`/`.next`/`.turbo`/`.cache` 컴포넌트만 포함된 이벤트는 emit하지 않는다. **`.git` 전체는 무시하지 않는다** — workbranch linked worktree의 gitdir metadata가 `<task>/<repo>/.git` 디렉터리가 아니라 `_base/<repo>/.git/worktrees/...`에 있을 수 있고, `list --json`은 repo `branch`/`dirty`를 노출한다. 이 v1 fix에서는 git metadata path를 blanket-ignore하지 않고, async+coalescing으로 git 이벤트 비용을 흡수한다. 더 정밀한 gitdir-aware 필터는 후속 튜닝으로 둔다.
- [x] **monitor refresh 코얼레싱 + heartbeat fallback 추가(TS).** 진행 중 refresh가 있으면 덮어쓰지 않고 "queued" 플래그로 1회만 뒤따르게 하여 CLI invoke 중첩을 제거한다. 0032가 의도한 5분 heartbeat를 주입 가능한 타이머로 구현해 누락 이벤트 self-heal을 보장한다.
- [x] **CLI public contract·도메인 경계 무변경.** `list --json`/`--global --json` 스키마, argv, 명령 동작, `workbranch` 명령 이름, ACL/domain/Published Language는 그대로다. Rust는 계속 JSON pass-through thin port다.
- [x] **부분 refresh(변경 root만 갱신) 최적화는 본 계획 범위 밖.** 0032의 후속 항목으로 유지. 본 계획은 응답성 회귀 제거에 한정한다.

## 변경 / 비변경 contract

### 변경 (companion 내부)
- `apps/workbranch-companion/src-tauri/src/lib.rs`: `workbranch_list`/`workbranch_list_global`/`workbranch_run`/`append_activity_events`/`watch_roots`를 `async fn`으로 전환, 블로킹 body는 `spawn_blocking`으로 분리. watch 콜백에 경로 ignore 필터 추가.
- `apps/workbranch-companion/src/infrastructure/workspaceMonitor.ts`: `scheduleRefresh` 코얼레싱 + 선택적 heartbeat 타이머(주입식). `WorkspaceMonitorDeps`에 테스트 가능한 타이머/heartbeat 옵션 추가.

### 비변경
- `workbranch` CLI(`apps/workbranch-cli/**`)와 `list --json` 계약, `packages/contract/**`. `<task>/TASK-WORKBRANCH.md` metadata freshness와 `<task>/<repo>` source/repo `branch`/`dirty`의 event-driven freshness도 Companion 사용자 경험의 일부로 유지한다.
- Rust→TS 반환 타입(`String`, `RunResult`, `WatchResult`), invoke 이름, `roots-changed` 이벤트 페이로드. (프론트 IPC 표면 그대로 → 프론트 무변경으로도 #1이 동작.)
- ACL/domain/UI, activity.jsonl 포맷·경로.

## 구현 작업 (TDD: 먼저 빨갛게)

### Slice A — Rust 커맨드 논블로킹화 (#1)
- green(비동기화): `lib.rs`의 5개 커맨드를 `async fn`으로 바꾸고 블로킹 body를 `tauri::async_runtime::spawn_blocking(move || { … })`로 감싼다. `JoinError`는 `CompanionError::Io(std::io::Error::other(...))`로 매핑한다.
  - `workbranch_list`/`workbranch_list_global`/`workbranch_run`/`append_activity_events`: 인자가 owned(Send)라 클로저로 그대로 이동. 기존 동기 헬퍼(`run_workbranch`, `run_pbcopy`, `workbranch_list_global_with_config_home`, `append_activity_events_default`)는 **시그니처 유지** — 클로저 안에서 호출만 한다(헬퍼는 cargo test 그대로 통과).
  - `watch_roots`: `app: AppHandle`을 clone해 클로저로 이동, watcher 구성(초기 재귀 스캔 포함)을 `spawn_blocking`에서 수행하고 `Vec<RecommendedWatcher>`(Send)를 반환받아 `await` 후 `WatcherStore`에 저장한다. `State<WatcherStore>` 락은 await 이후 메인측에서 잡는다(클로저로 `State`를 넘기지 않음).
- 검증: `cargo build`, `cargo clippy -- -D warnings`, 기존 `cargo test`(헬퍼 단위테스트 무영향) green. `pnpm --filter @workbranch/companion tauri dev`로 트레이 클릭/자동 갱신 시 프리즈 없음 수동 확인(캡처 메모).

### Slice B — watch 이벤트 경로 필터 (#2, Rust 순수 함수 TDD)
- red: 순수 함수 `event_has_relevant_change(paths: &[PathBuf], ignored: &[&str]) -> bool`와 `path_is_ignored(path, ignored)` 테스트 추가.
  - `node_modules/foo/x.js`, `target/debug/...`, `dist/...`, `build/...`, `.next/...`, `.turbo/...`, `.cache/...` 단독 변경 → `false`(무시).
  - `TASK-WORKBRANCH.md`, plan 파일, 일반 working-tree 파일 변경 → `true`(emit).
  - linked worktree git metadata path 예시: `_base/repo/.git/worktrees/task-repo/index`(stage/unstage), `_base/repo/.git/worktrees/task-repo/HEAD`(checkout), `_base/repo/.git/refs/heads/<task-branch>` 또는 `_base/repo/.git/packed-refs`(commit/ref 변경) 단독 변경 → `true`(emit). `.git` 전체 blanket-ignore 금지.
  - 혼합 이벤트(무시 경로 + 관심 경로 또는 git metadata 경로) → `true`.
- green: 콜백(`lib.rs:138-145`)에서 `event` unwrap 후 `event_has_relevant_change(&ev.paths, IGNORED_COMPONENTS)`가 `false`면 early-return, 그다음 기존 `should_emit_root_change` 디바운스. `IGNORED_COMPONENTS = ["node_modules","target","dist","build",".next",".turbo",".cache"]` — `.git`은 포함하지 않는다.
- 검증: `cargo test`, `cargo clippy -- -D warnings`. dev 빌드에서 작업 중 프로젝트의 `roots-changed` emit 빈도가 빌드/패키지-manager churn에는 급감하고, `<task>/TASK-WORKBRANCH.md` 저장 후 plan/status가 갱신되며, `<task>/<repo>` 파일 수정과 `git add`/`git commit`/branch checkout 이후 repo `dirty`/`branch` 표시가 event-driven으로 갱신되는지 확인.

### Slice C — monitor 코얼레싱 + heartbeat fallback (TS TDD)
- red(`tests/workspace-monitor.test.ts` 확장):
  - 코얼레싱: `refresh`가 in-flight인 동안 `onRootChanged` 콜백을 N번 호출해도 추가 refresh는 **정확히 1회**만 뒤따른다(`refresh` 호출 횟수 단언). in-flight 없을 때 트리거는 즉시 1회.
  - trailing refresh race: queued follow-up refresh가 이미 실행 중일 때 새 `onRootChanged`가 들어오면 그 refresh의 스냅샷 이후 변경일 수 있으므로 **한 번 더** follow-up refresh가 실행된다. `settle()`은 코얼레싱 큐가 quiet 상태가 될 때까지 resolve하지 않는다.
  - heartbeat: 주입된 fake 타이머가 `heartbeatMs` 경과 시 refresh를 1회 트리거하고, `stop()` 시 타이머가 해제된다.
- green: `scheduleRefresh`를 `running`/`queued` 플래그 기반 코얼레서로 재작성하되, `running` 중 들어온 이벤트는 현재 실행이 끝난 뒤 큐를 drain할 때까지 반복 처리한다(quiet 상태에서 종료). `WorkspaceMonitorDeps`에 선택적 `heartbeatMs`와 주입식 타이머(`setTimer`/`clearTimer` 또는 scheduler 추상)를 추가해 테스트 가능하게 한다. `App.tsx`는 `heartbeatMs: 5*60*1000`과 실제 `setInterval`/`clearInterval`을 주입한다.
- 검증: `pnpm --filter @workbranch/companion test`, `pnpm --filter @workbranch/companion typecheck`, `pnpm run lint`.

### Slice D — 수동 응답성 검증 + (문서 건드릴 경우) 동기화
- 활성 프로젝트(`node_modules` 있는 repo)에서 `tauri dev`로 (a) `<task>/TASK-WORKBRANCH.md` 저장과 `<task>/<repo>` 파일 저장 중 트레이·popover가 멈추지 않음, (b) 작업 외 idle에서 `roots-changed` 폭주가 없음, (c) `git add`/`git commit`/branch checkout 이후 repo `dirty`/`branch` 표시가 event-driven으로 갱신됨, (d) watch 이벤트를 인위로 누락시켜도 5분 내 self-heal 갱신을 확인한다.
- 본 계획은 내부 동작 수정이므로 사용자 문서 변경은 원칙적으로 없다. 만약 `docs/architecture.md` 등에 watch/threading 동작을 기술한 곳을 갱신하면 EN/KO를 같은 PR에서 동기화한다.

## 구현 결과 (2026-06-17)

- [x] **Slice A:** Rust Tauri command 5개(`workbranch_list`, `workbranch_list_global`, `append_activity_events`, `workbranch_run`, `watch_roots`)를 `async fn` + `tauri::async_runtime::spawn_blocking`으로 전환했다. watcher 저장 `Mutex`는 `await` 이후에만 잡아 command async 경계에 non-`Send` state를 넘기지 않는다.
- [x] **Slice B:** watch 경로 필터를 `watch_filter.rs` 순수 함수로 분리하고, watcher 구성/디바운스를 `watch_roots.rs`로 분리했다. ignore 대상은 `node_modules`/`target`/`dist`/`build`/`.next`/`.turbo`/`.cache`이고, `.git`/linked-worktree gitdir metadata는 relevant로 유지한다.
- [x] **Slice C:** `workspaceMonitor.ts`에 `running`/`queued` 기반 refresh 코얼레싱과 주입식 heartbeat 타이머를 추가했다. `App.tsx`는 5분 heartbeat를 실제 `window.setInterval`/`clearInterval`로 주입한다.
- [x] **Slice D 자동 smoke:** 사용자 설정을 건드리지 않도록 임시 `XDG_CONFIG_HOME`으로 release binary를 5초 실행했고 프로세스가 유지되며 stderr/stdout 로그가 없음을 확인했다. 실제 트레이 클릭/popover 수동 관찰과 5분 실시간 heartbeat 관찰은 이 CLI 실행 환경에서는 수행하지 못했으므로, 릴리즈 전 사람이 `tauri dev`로 한 번 보강한다.

## 최종 검증

```bash
# CLI 무영향
apps/workbranch-cli/tests/run.sh
# Rust port
cargo test --manifest-path apps/workbranch-companion/src-tauri/Cargo.toml
cargo clippy --manifest-path apps/workbranch-companion/src-tauri/Cargo.toml --all-targets -- -D warnings
# TS
pnpm --filter @workbranch/companion test
pnpm run typecheck
pnpm run lint
# 통합 빌드 + 수동 응답성 확인
pnpm --filter @workbranch/companion tauri build
git diff --check
```

2026-06-17 실행 증거:
- `apps/workbranch-cli/tests/run.sh` → 259 tests passed.
- `cargo test --manifest-path apps/workbranch-companion/src-tauri/Cargo.toml` → 14 passed.
- `cargo clippy --manifest-path apps/workbranch-companion/src-tauri/Cargo.toml --all-targets -- -D warnings` → passed.
- `pnpm run typecheck` → `packages/contract`, `apps/workbranch-companion` passed.
- `pnpm run lint` → exit 0. 기존 `apps/workbranch-companion/src/infrastructure/parseContract.ts`의 `useLiteralKeys` info 42건은 남아 있으나, 변경 파일 targeted `biome check src/App.tsx src/infrastructure/workspaceMonitor.ts tests/workspace-monitor.test.ts`는 clean.
- `pnpm --filter @workbranch/companion test` → 6 files / 15 tests passed.
- `pnpm --filter @workbranch/companion tauri build` → release binary와 macOS app bundle 생성 성공.
- 격리 smoke: 임시 `XDG_CONFIG_HOME`으로 `target/release/workbranch-companion` 5초 실행 → 프로세스 유지, 로그 없음.
- `git diff --check` → clean.

검증 기준은 "프리즈 부재 + idle 이벤트 폭주 부재 + task metadata freshness + repo `branch`/`dirty` freshness 보존 + heartbeat self-heal"이며, 자동 테스트는 순수 함수(경로 필터)·코얼레싱·heartbeat에 한정하고 비동기 프리즈 부재와 linked-worktree/git metadata freshness는 수동 확인으로 보강한다.

## 롤아웃 / 호환성

- companion 내부 IPC/watch 동작만 바뀌고 CLI·계약·activity.jsonl·프론트 IPC 표면은 불변이라 마이그레이션 불필요. 사용자 입장 변화는 "안 멈춤"뿐.
- 반환 타입/이벤트 페이로드가 동일하므로 Slice A(#1)만 머지해도 즉시 프리즈가 사라진다. Slice B/C는 그 위에 noise·중첩·누락 회복력을 더하되, workbranch의 task-root metadata와 linked-worktree repo 상태 freshness를 희생하지 않는다.
- companion semver: 런타임 버그픽스 → release-please patch 라인. CLI 버전과 무관(0022/0032 독립 버저닝 유지).

## 미해결 / 후속

- **부분 refresh.** 변경된 root만 `list --json`으로 갱신(global 전체 재조회 대신)하는 0032 후속 최적화는 별도 plan. 본 계획의 코얼레싱/필터로 충분히 완화되는지 측정 후 결정.
- **디바운스 / gitdir-aware 필터 튜닝.** 500ms 윈도우는 유지. 필터 적용 후에도 특정 워크플로(대량 git rebase 등)에서 `_base/<repo>/.git/**` 잔여 noise가 보이면 윈도우 상향, trailing-debounce, 또는 linked-worktree gitdir의 `index`/`HEAD`/refs만 통과시키는 정밀 필터로 후속 조정.
- **Windows/Linux.** notify 백엔드가 macOS FSEvents와 달라 재귀 등록 비용/이벤트 입도가 다르다. 타 OS 지원 시 watch 전략 재검토(0032와 동일하게 macOS 한정).
