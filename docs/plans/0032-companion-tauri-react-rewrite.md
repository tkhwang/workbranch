# 0032 Companion을 Tauri + React로 재작성 (DDD / monorepo) 계획

> **agentic worker 지침:** 실행 시 `superpowers:executing-plans` 또는 `superpowers:subagent-driven-development`를 사용한다. 순수 로직(ACL DTO→domain 매핑, domain 파생, activity 세션 롤업)은 `superpowers:test-driven-development`(red → green → refactor)로 구현하고 `pnpm test`(vitest)로 검증한다. Rust port(subprocess, FS watch)는 `cargo test`로, 통합은 `pnpm --filter @workbranch/companion tauri build`로 검증한다. unit test에서 FS watch, subprocess 실행, React 렌더를 직접 수행하지 않는다 — 얇은 IO/IPC wrapper로 격리한다. **Bash CLI 동작과 public `workbranch` command는 이 계획에서 변경하지 않는다.** Slice A에서 기존 CLI 파일은 `apps/workbranch-cli/**`로 이동하고, companion 신규 코드는 `apps/workbranch-companion/**`, 공유 계약은 `packages/contract/**`에만 둔다. 문서를 건드리면 EN/KO를 같은 PR에서 동기화한다.
>
> **시리즈 위치:** 0017(SwiftBar) → 0019(native SwiftUI companion) → 0021/0026/0028/0029(task progress·lifecycle·plan별 시간) 위에 얹는다. **이 계획은 0019의 기술 스택 결정(Swift / SwiftUI `MenuBarExtra` / SwiftPM / XCTest)을 대체(supersede)한다.** 0019·0021·0026·0028·0029의 **제품 결정과 데이터 계약**(presentation-only client, `list --json`이 유일한 상태 source of truth, FSEvents 기반 event-driven 갱신, mutation은 CLI argv 호출, memo/noti/launch action, Task▶Plan▶Step 모델, plan별 시간 측정)은 전부 계승한다. hard dependency는 0015의 `workbranch list --json`/`memo`/`noti`와 0029의 `plans[]` 계약뿐이다.

**목표:** 기존 Swift native menu bar app(`companion/`)을 **Tauri v2 + React/TypeScript** 스택으로 재작성한 새 menu bar app(`apps/workbranch-companion/`)으로 대체한다. 기능 패리티(task workspace 목록, Plan▶Step 트리, memo 인라인 편집, notification count/clear, dirty 상태, launch action, plan별 activity report)를 달성한 뒤 Swift companion을 제거한다. 동시에 repo를 **pnpm workspace 기반 monorepo**로 정리해 deployable app을 `apps/workbranch-cli`(Bash CLI)와 `apps/workbranch-companion`(Tauri app)으로 분리하고, CLI↔companion 사이의 JSON 계약을 `packages/contract/`에 **Published Language**로 명문화한다. 릴리스 버전은 0022의 독립 release-please 결정(separate PR/version)을 유지하며, CLI와 companion을 같은 버전으로 강제 수렴시키지 않는다.

**아키텍처(핵심 결정):**
- 두 개의 **Bounded Context**다. **Workbranch CLI = Supplier(upstream)**, **Companion = Consumer(downstream)**. 관계는 **Customer/Supplier + Published Language**.
- **Published Language = `workbranch list --json` 스키마(schemaVersion 1)**. 이 계약은 0015/0029에서 이미 안정화돼 있고, 본 계획에서 **변경하지 않는다**. `packages/contract/`에 JSON Schema로 박제하고, companion은 거기서 TS 타입을 생성한다(진실원천 1개).
- **companion은 presentation-first consumer다.** task 상태(`TASK-WORKBRANCH.md` 등)를 직접 읽거나 쓰지 않는다. 상태 조회는 `list --global --json`(query)을 기본으로 하고, v1에서 허용하는 운영 action만 **CLI argv 호출**(command)로 위임한다 — `memo`, `noti clear`, Finder/IDE/terminal launch, copy path, open config, refresh/quit, local read-state 처리까지가 범위다. `add`/`done`/`land`/`push` 같은 task lifecycle·Git mutation은 본 rewrite v1 범위에서 제외하고 별도 plan/decision으로 다룬다.
- markdown 포맷은 Workbranch BC의 내부 구현이다. companion은 **절대 markdown을 파싱하지 않는다**(0019 원칙 유지). 파싱·집계는 CLI가, 번역은 companion ACL이 담당한다.
- **Tauri 레이어 매핑:** Rust core(`src-tauri`)는 네이티브 port만 — subprocess 실행, FS watch(notify crate), tray/창 토글. **Rust는 JSON을 파싱하지 않고 문자열 그대로** TS로 넘긴다. domain·ACL·application·UI는 전부 TS에 둔다.

**기술 스택:** Tauri v2, Rust(stable, `tauri`, `notify`, `tauri-plugin-positioner`), React 18 + TypeScript, Vite, pnpm workspace, vitest(TS 순수 로직), `cargo test`(Rust port). 기존 Bash `workbranch` CLI 계약.

**제품 관점:** companion의 가치는 0019와 동일한 task cockpit이다 — "어떤 task가 있고, 각 task가 어떤 Plan들로 구성됐고, 각 Plan이 어디까지 진행됐고, 알림이 있고, memo를 어떻게 갱신할지"를 menu bar에서 이벤트 직후 즉시 본다. idle 비용은 거의 0이어야 한다. 스택만 Swift→Tauri로 바꾸되 이 경험은 유지하거나 개선한다.

---

## 문제

0019로 native Swift companion이 출시됐고 0029까지 Plan▶Step·plan별 시간이 쌓였다. 그러나 유지보수 주체가 Swift에 익숙하지 않아 다음이 어렵다:

- UI/도메인 로직 반복(memo 편집, report 뷰, Plan 트리 렌더) 시 Swift/SwiftUI 학습 비용이 크다.
- 향후 companion 기능 확장(웹 기반 뷰, 더 풍부한 report)에 React 생태계를 쓰지 못한다.

스택을 React/TS로 바꾸면 이 비용이 사라진다. 단 footprint가 중요한 상주 menu bar app이라 Electron(idle ~100–200MB)이 아닌 **Tauri(idle 수십 MB)** 를 택한다. CLI와의 경계가 process+JSON이라 언어 교체에 따른 결합 위험이 없다(빌드타임 의존성 0).

**왜 지금 monorepo로 정리하나:** 현재 Bash CLI(`src/`, `bin/`, `tests/`, `scripts/`)와 `companion/`(Swift)이 root에 평면으로 있고, `cmd_list_json`(생산자)과 `WorkbranchListDocument`(소비자)가 각자 스키마를 알고 있어 진실원천이 둘이다. 스택 교체를 계기로 deployable app을 `apps/workbranch-cli`와 `apps/workbranch-companion`으로 분리하고, 계약을 `packages/contract/`로 단일화한다. public command 이름(`workbranch`), Homebrew formula, root install entrypoint는 compatibility layer로 유지한다.

## 현재 repo 근거

- **Published Language(불변):** `src/workbranch/commands/list.sh:cmd_list_json` — `schemaVersion:1`, task별 `name`/`path`/`memoTitle`/`planTitle`/`status`/`progressDone`/`progressTotal`/`currentItem`/`items[]`/`plans[]`/`notiCount`/`repos[]`. `plans[]`는 0029에서 추가(각 plan `title`/`index`/`status`/`progressDone`/`progressTotal`/`currentItem`/`items[]`). `list --global --json`은 `cmd_list_global_json`(프로젝트 배열 + `errors[]`).
- **파싱은 CLI 소유:** `src/workbranch/lib/task-state.sh`(`task_plans_json`, `task_status`, `task_checklist_counts`, `task_current_item`, `task_updated_at`), `src/workbranch/lib/status-format.sh`(git 상태 라벨). companion은 이 결과 JSON만 본다.
- **command surface(불변):** CLI에는 `done`/`land`/`push`/`pull`/`add`/`memo`/`noti`/`finalize`/`finder`/`ide`/`terminal` 등이 있지만, companion v1 IPC/UI allowlist는 현재 Swift companion과 같은 운영 action(`memo`, `noti clear`, Finder/IDE/terminal launch, copy path, open config, refresh/quit, local status-read)으로 제한한다.
- **대체 대상 Swift consumer:** `companion/Sources/CompanionApp/CLIClient.swift`(subprocess + `WorkbranchListDocument.decode`), `RootWatcher.swift`(FSEvents), `StateStore.swift`, `ActivityRecorder.swift`(append-only `~/.local/state/workbranch/activity.jsonl`), `Views/*`(`RowView`=Plan▶Step 트리, `ActivityReportView`, `CompanionPopoverView`). 순수 로직은 `CompanionCore`(`Models.swift`, `ActivityEvent.swift`, `ActivityReport.swift`, `MenuState.swift`, `Debounce.swift`).
- **companion 내부 상태(계약 아님, 재구현 대상):** activity.jsonl(plan별 시간 이벤트, 0029), notification read-state, login item, appearance settings.
- **이벤트 안전성:** `list --json` path는 network/fetch 없이 `git status --porcelain`만 사용(0015) → FS 이벤트 직후 재실행 안전.

## 결정 사항 (확정됨)

- [x] **monorepo 유지(분리하지 않음), deployable app은 `apps/*`로 정리.** 근거: companion↔CLI 결합이 런타임 process+JSON 뿐이라 toolchain 충돌 없음. 함께 진화해야 하는 단 하나가 JSON 스키마 → 분리 시 매 변경마다 cross-repo 조율 릴리스 부담. 1인 프로젝트. Bash CLI도 deployable app이므로 `apps/workbranch-cli`, Tauri companion은 `apps/workbranch-companion`, shared contract는 `packages/contract`로 둔다. **분리 트리거(미해당):** App Store 등 별도 배포 채널 + CLI를 건드리면 안 되는 별도 CI, 또는 별도 소유 팀.
- [x] **Bash CLI 유지(재작성하지 않음), 위치만 `apps/workbranch-cli`로 migration.** 경계가 JSON이라 supplier BC가 bash인 채로 완전 동작. 30+ plan 이력 보존. 설치되는 command 이름은 계속 `workbranch`이며 Homebrew/root installer는 새 app path를 참조하도록 갱신한다. 내부 path/layout 변경만으로 CLI major를 강제하지 않는다. CLI major는 public command/argv/installer compatibility가 깨지는 경우에만 별도 정당화한다.
- [x] **companion 스택 = Tauri v2 + React/TS.** footprint 때문에 Electron 기각. Swift companion 대체와 app path 변경은 companion의 semver 판단에서 major 후보가 될 수 있지만, CLI와 같은 버전으로 맞추는 요구는 없다.
- [x] **2 BC + Published Language + ACL.** 계약은 `packages/contract/` JSON Schema 단일 원천. companion infrastructure에 ACL을 두어 DTO가 domain/UI로 새지 않게 한다.
- [x] **companion = presentation-first consumer + 제한된 CLI 위임.** query=`list --global --json`, command=현재 Swift companion parity allowlist(`memo`, `noti clear`, Finder/IDE/terminal launch, copy path, open config, refresh/quit, local status-read). companion은 markdown/state 파일을 직접 쓰지 않는다. task lifecycle·Git mutation(`add`/`done`/`land`/`push`)은 v1에서 제외한다.
- [x] **도메인 모델 = Task▶Plan▶Step, status는 Plan에 귀속.** Task는 aggregate root(식별자=workspace 이름), Plan은 entity(식별자=`(title, index)`, status enum 보유), Step은 value object(`text`/`checked`/`depth`, 중첩). Task 차원 status/progress는 active Plan에서 **파생**(저장 안 함). 0029 파생 규칙 그대로 소비.
- [x] **Rust는 도메인 무지(thin port).** subprocess/FS watch/tray만. JSON 문자열 pass-through, 파싱·번역은 TS ACL 1곳.
- [x] **`list --json` 스키마는 본 계획에서 변경하지 않는다(schemaVersion 1).** 순수 consumer 재구현 + 계약 박제만 한다.

## Decision Gates

- [x] Companion v1 command surface
  - Impact: IPC security boundary, user-visible mutation behavior, lifecycle/Git side effects.
  - Current evidence: `docs/COMPANION-INTEGRATION-PLAN.md` keeps task creation/deletion in the CLI and removes `New workspace` UI; current `MenuAction` exposes only memo, status-read, notification clear, Finder/IDE/terminal, copy path, config, refresh, quit.
  - Resolved: A — Tauri v1 keeps the current Swift companion parity action set.
  - Consequence: `workbranch_run` must use a typed allowlist and must not expose arbitrary argv or `add`/`done`/`land`/`push`/`pull`/`finalize` in v1. Those lifecycle/Git mutations require a separate plan/decision gate.

- [x] Monorepo app/package layout
  - Impact: directory ownership, package/export surface, CI/release/Homebrew path migration, Swift↔Tauri coexistence window.
  - Current evidence: pnpm workspace/Turbo-style monorepo convention uses `apps/*` for deployable apps and `packages/*` for shared libraries; current repo has deployable Bash CLI plus deployable companion; Swift companion must coexist until parity is proven. Turbo itself remains optional unless it reduces root orchestration complexity.
  - Resolved: A — use `apps/workbranch-cli` for the Bash CLI app, `apps/workbranch-companion` for the Tauri app, and `packages/contract` for the Published Language package.
  - Consequence: move CLI-owned source/build/test/install files under `apps/workbranch-cli`, keep public `workbranch` command compatibility, update Homebrew formula/release-please/CI/docs/root install entrypoint to the new paths, and keep old Swift `companion/` only until Slice H removal.

- [x] Release/version policy
  - Impact: public package identity, release tags, Homebrew formula/cask versions, user upgrade expectation, and compatibility with `docs/plans/0022-independent-release-please-prs.md`.
  - Current evidence: 0022 intentionally split root CLI and companion release PRs/versions; current release-please config uses `separate-pull-requests: true` and package keys `.` + `companion`. The CLI command name/argv/output stay unchanged in this plan, while companion runtime/package technology changes from Swift to Tauri.
  - Resolved: preserve independent release-please versioning. Do **not** force CLI and companion to share one version. CLI semver follows public CLI/installer compatibility; companion semver follows companion package/runtime changes.
  - Consequence: CLI major is only justified if public behavior or supported install path compatibility breaks. If root `install.sh`, Homebrew formula, `workbranch` command name, argv, and raw-install compatibility are preserved, CLI may remain on a normal release-please minor/patch line. Companion may independently take a major release if the Tauri replacement is treated as a package/runtime breaking change. `.release-please-manifest.json` must migrate paths without artificial version convergence.

## 용어 계약

- **Workbranch BC (Supplier):** worktree/task/plan/step/git을 소유하는 Bash CLI. 외부 계약은 `list --json`(query) + 명령 argv(command).
- **Companion BC (Consumer):** menu bar 표현·activity 추적·liveness를 소유하는 Tauri/React app. Workbranch BC에 대해 downstream.
- **Published Language:** `workbranch list --json` / `list --global --json` 스키마. Bash CLI 출력이 supplier 정본이고, `packages/contract/`의 JSON Schema는 그 현재 출력에 대한 consumer-facing contract snapshot이다. `schemaVersion`으로 호환 게이트하고, live CLI 출력이 schema를 만족하는지 Slice B부터 검증해 drift를 차단한다.
- **ACL (Anti-Corruption Layer):** companion `infrastructure/`에서 CLI JSON DTO를 companion domain(Task/Plan/Step)으로 번역하는 경계. DTO 타입은 ACL 밖으로 나가지 않는다.
- **Port (Rust):** `src-tauri`가 노출하는 `#[tauri::command]`/event. 도메인 지식 없음. `workbranch_list`, `workbranch_run`, `watch_roots`.
- **Query / Command:** Query=상태 조회(`list --global --json` 기본, 필요 시 `list --json`). Command=허용된 운영 action(`memo`, `noti clear`, Finder/IDE/terminal launch)만 CLI 경유. task lifecycle·Git mutation command는 v1 companion 범위 밖이다.

## public / 내부 contract

### Published Language — `packages/contract/`

`list --json`/`list --global --json`의 현재 출력(schemaVersion 1)을 **그대로** 기술하는 JSON Schema를 박제한다. 신규 정의가 아니라 **기존 CLI 출력의 문서화**이며, schema 자체가 supplier를 대체하지 않는다. Slice B부터 fixture뿐 아니라 테스트 fixture에서 실제 CLI를 실행한 출력도 schema로 검증한다.

```
packages/contract/
├── schema/workbranch-list.schema.json        # task/plan/step/repo, schemaVersion 1
├── schema/workbranch-list-global.schema.json  # projects[] + errors[]
├── src/index.ts                               # 스키마에서 생성/유도된 TS DTO 타입 export
└── fixtures/*.json                            # 실제 `list --json` 캡처 샘플(테스트 골든)
```

- TS DTO 타입은 스키마에서 생성(`json-schema-to-typescript` 등)하거나 손으로 두고 스키마와 일치 테스트. companion ACL은 **이 DTO 타입만** import한다.
- fixture는 실제 CLI 출력(빈 plans / 암묵 단일 plan / 동명 plan `index` 분리 / global errors 포함)을 캡처해 ACL 회귀 테스트의 골든으로 쓴다.

### Rust port — `apps/workbranch-companion/src-tauri`

```
#[tauri::command] workbranch_list(root: String)         -> Result<String>   // `workbranch list --json` stdout 그대로
#[tauri::command] workbranch_list_global()              -> Result<String>   // `workbranch list --global --json`
#[tauri::command] workbranch_run(action: CompanionCommand, cwd: String) -> Result<RunResult>  // command side, typed allowlist → argv 배열(shell interpolation 금지)
                  watch_roots(roots: Vec<String>)        -> emits "roots-changed" {root}  // notify crate, debounce
                  // tray icon + popover 창 토글(tauri-plugin-positioner)
```

- `workbranch_run`은 typed allowlist를 argv 배열 + 명시적 `cwd`로 변환해 실행한다(memo/path를 shell string에 절대 interpolate 금지 — 0019 보안 원칙). v1 허용 command는 `memo <task> <text>|--clear`, `noti clear <task>`, `finder|ide|terminal <task>`뿐이다. copy path는 `/usr/bin/pbcopy` stdin으로 처리하고, `add`/`done`/`land`/`push`/`pull`/`finalize`는 v1 IPC에 넣지 않는다.
- watcher가 놓칠 때 대비 TS application 레벨에서 느린 heartbeat(예: 5분) fallback 재조회.

### Companion domain (TS, `apps/workbranch-companion/src/domain`)

```ts
// 순수. Tauri/DTO/React 의존 0.
type PlanStatus = 'todo'|'planning'|'in-progress'|'review'|'blocked'|'done'
interface Step  { text: string; checked: boolean; depth: number; children: Step[] }
interface Plan  { title: string; index: number; status: PlanStatus; steps: Step[];
                  progressDone: number; progressTotal: number; currentItem: string }
interface Repo  { name: string; branch: string; dirty: boolean }
interface Task  { name: string; path: string; memoTitle: string; notiCount: number;
                  plans: Plan[]; repos: Repo[]; updatedAt: number }
// 파생: activeStatus = activePlan.status, progress = activePlan.done/total
```

### Companion 내부 영속(계약 아님, 재구현)

- **activity.jsonl** (`~/.local/state/workbranch/activity.jsonl`): 현재 Swift `ActivityEvent` v1 encoded shape를 **그대로 유지**해 기존 기록과 연속성 보존. 필수/현재 필드는 `v`/`editedAt`/`observedAt`/`root`/`project`/`task`/`plan`/`planIndex`/`planTitle`/`planStatus`/`status`/`taskProgressDone`/`taskProgressTotal`/`progressDone`/`progressTotal`이며, `items[]`는 non-empty step snapshot일 때 encode되고 empty snapshot은 기존 step rows를 지우는 의미를 가진다. 구버전 라인(`plan`/`planIndex`/`planStatus`/`taskProgress*`/`items` 없음)은 기존 fallback처럼 읽는다. Tauri 앱이 동일 포맷으로 append. 세션 롤업(idle gap 25분, lead pad 5분)·report 집계 로직을 TS로 포팅한다.
- notification read-state, login item(자동 시작), appearance 설정: companion 내부 관심사로 TS/Rust에 재구현.

### 변경하지 않는 것

- `workbranch list --json`/`--global --json` 스키마(schemaVersion 1), 모든 CLI 명령 동작·argv, 설치 후 command 이름 `workbranch`.
- task 편집 프로토콜(agent가 brief 직접 편집), `updatedAt`=brief mtime 권위값.
- `TASK-WORKBRANCH.md`/`notifications.jsonl` 포맷, AGENTS.md 작성 규칙.
- activity.jsonl 라인 포맷(연속성 위해 동일 유지).

## 파일 구조

```text
# monorepo 루트
package.json                     # pnpm workspace 루트 scripts; Turbo는 유효할 때만 사용
pnpm-workspace.yaml              # apps/*, packages/*
turbo.json                       # 선택적 JS/TS/Tauri task orchestration/cache(복잡도 대비 이득 검증)

apps/
├── workbranch-cli/              # Bash CLI app (Supplier BC)
│   ├── src/workbranch/**
│   ├── bin/workbranch            # generated single-file distribution
│   ├── scripts/build-workbranch.sh
│   ├── scripts/workbranch-sources.txt
│   ├── tests/run.sh
│   ├── tests/cases/**
│   └── install.sh                # CLI-local installer implementation
└── workbranch-companion/         # 새 Tauri + React 앱 (Consumer BC)
    ├── src-tauri/                # Rust port: subprocess / notify watch / tray / positioner
    │   └── src/lib.rs, main.rs, tauri.conf.json
    └── src/
        ├── domain/               # Task/Plan/Step (순수)
        ├── application/          # use case: refreshStatus, runAction, recordActivity, buildReport
        ├── infrastructure/       # ACL(DTO→domain), tauri invoke 래퍼, activity store, watcher 구독
        └── ui/                   # React: 메뉴바 popover, Plan▶Step 트리, activity report, settings

packages/
└── contract/                     # Published Language (JSON Schema + TS DTO + fixtures)

install.sh                        # public/root compatibility entrypoint → apps/workbranch-cli/install.sh
packaging/homebrew/workbranch.rb  # formula installs apps/workbranch-cli/bin/workbranch
companion/                        # 기존 Swift — 패리티 달성 후 제거(Slice H)
```

## 구현 작업 (TDD: 먼저 빨갛게)

### Slice A — Monorepo workspace 골격 + CLI app path migration
- pnpm workspace 구성: `pnpm-workspace.yaml`은 `apps/*`, `packages/*`; root `package.json`은 `private`, `packageManager`, `build`/`test`/`typecheck`/`lint`/`cli:*` scripts를 둔다. 내부 TS package 의존성은 `workspace:*`를 사용한다. Turborepo는 root orchestration/cache가 실제로 단순화될 때만 도입한다. 도입 시 `turbo.json`은 `build`, `test`, `typecheck`, `lint`, `dev` task와 outputs/cache를 정의한다. TS app 1개 + contract 1개 + Bash CLI 1개 수준에서 Turbo가 오히려 복잡도를 늘리면 plain pnpm workspace scripts로 유지한다.
- Bash CLI를 deployable app으로 `apps/workbranch-cli/` 아래 이동한다: 현재 root `src/workbranch/**`, `bin/workbranch`, `scripts/build-workbranch.sh`, `scripts/workbranch-sources.txt`, `tests/run.sh`, `tests/cases/**`, CLI-local `install.sh`를 새 경로로 옮긴다. public/root `install.sh`는 compatibility entrypoint로 남겨 내부에서 `apps/workbranch-cli/install.sh`를 호출한다.
- **installer compatibility가 Slice A의 release blocker다.** root `install.sh`의 checkout install source는 `apps/workbranch-cli/bin/workbranch`로 갱신한다. 동시에 curl/raw standalone install path도 명시적으로 갱신하거나, 기존 `bin/workbranch` raw URL을 보존할 compatibility artifact(copy/shim)를 유지한다. release 전 검증은 `WORKBRANCH_RAW_BASE_URL`을 local fixture/raw mirror로 지정해 root `install.sh`가 실제로 새 CLI artifact를 내려받는지 확인해야 한다. `curl https://.../install.sh | bash` 계약을 깨뜨리는 상태로 릴리스하지 않는다.
- root scripts는 JS/Tauri orchestration과 CLI 검증을 함께 제공한다: 예) `cli:build=apps/workbranch-cli/scripts/build-workbranch.sh`, `cli:test=apps/workbranch-cli/tests/run.sh`, `build=pnpm -r run build` 또는 `turbo run build`, `test=pnpm -r run test && pnpm run cli:test` 또는 동등한 명시적 CI command. Bash CLI를 npm package로 억지 publishing하지 않는다.
- 기존 Swift `companion/`은 Slice H까지 그대로 공존한다.
- 검증: `pnpm install`, workspace typecheck/test, `apps/workbranch-cli/scripts/build-workbranch.sh`, `apps/workbranch-cli/tests/run.sh`, root `install.sh` checkout smoke, `WORKBRANCH_RAW_BASE_URL` 기반 raw-install smoke, Homebrew formula 경로 smoke.

### Slice B — `packages/contract` Published Language 박제
- red: `cmd_list_json`/`cmd_list_global_json` 실제 출력을 fixture로 캡처하고, fixture가 스키마를 만족하는지 검증하는 테스트 추가(빈 plans / 암묵 단일 plan / 동명 plan `index` 분리 / global `errors[]` 케이스). 같은 테스트에서 fixture setup으로 실제 `apps/workbranch-cli/bin/workbranch list --json`/`list --global --json`을 실행한 stdout도 schema 검증해 CLI↔contract drift를 Slice B부터 차단한다.
- green: `workbranch-list.schema.json`/`workbranch-list-global.schema.json` 작성, TS DTO 타입 export. schema↔타입 일치 테스트 green.
- 검증: `pnpm --filter @workbranch/contract test`.

### Slice C — Rust port (subprocess / watch / tray)
- `apps/workbranch-companion` Tauri v2 scaffold. `workbranch_list`/`workbranch_list_global`/`workbranch_run`(typed allowlist, no shell interpolation)/`watch_roots`(notify + debounce) 구현. tray icon + popover 창 토글(positioner). `workbranch` 바이너리 탐색은 기존 Swift `locateWorkbranch` 후보 경로(`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`) 포팅한다. 개발 중 local CLI fallback은 `apps/workbranch-cli/bin/workbranch`를 명시적으로 opt-in할 수 있게 하되, release app은 installed `workbranch` command를 우선한다.
- Tauri config는 Vite dev server 기준 `devUrl`/`frontendDist`와 `beforeDevCommand`/`beforeBuildCommand`를 app-local pnpm scripts로 연결한다. Turbo를 쓰더라도 root orchestration일 뿐이며, Tauri hook은 app-local scripts를 호출한다.
- 검증: `cargo test`(argv builder/typed allowlist/경로 탐색 단위), `pnpm --filter @workbranch/companion tauri dev`로 tray 표시 + `workbranch_list_global` 호출 수동 확인.

### Slice D — ACL + domain (순수 TS, TDD 핵심)
- red: `packages/contract` fixture를 입력으로 `mapListDocumentToTasks(dto) -> Task[]` 테스트 — Plan▶Step 트리 복원(depth 중첩), `(title,index)` identity, active plan 파생 status/progress, 빈/암묵 plan, 동명 plan 분리.
- green: `infrastructure/acl.ts` + `domain/*` 구현. DTO 타입은 ACL 안에만.
- 검증: `pnpm --filter @workbranch/companion test`.

### Slice E — application + 라이브 모니터 UI
- application: `refreshStatus`는 기본적으로 `workbranch_list_global()` 1회 → global wrapper DTO → ACL → store로 갱신한다. `watch_roots` 이벤트는 refresh trigger와 watcher 재구성에만 쓰고, 변경 root만 부분 refresh하는 최적화는 후속으로 둔다. global wrapper `errors[]`는 error row와 true-deletion grace/self-heal 판단에 사용한다. 5분 heartbeat fallback 유지.
- UI: 메뉴바 popover에 task 목록(memoTitle/notiCount/dirty), `RowView` 대응 Plan▶Step 트리(0029 렌더 규칙: 단일 Plan은 헤더 접기, 다중 Plan은 `Plan header → Step`). memo 인라인 편집, noti clear, Finder/IDE/terminal launch, copy path, open config, refresh/quit, status-read/read-state 처리를 구현한다. **New workspace 생성 UI와 `add`/`done`/`land`/`push` 같은 lifecycle/Git mutation action은 v1에서 제외한다.**
- 검증: `pnpm --filter @workbranch/companion tauri dev` 수동 시각 확인(캡처 메모), application 로직 vitest.

### Slice F — Activity 추적 + report
- red: 현재 Swift `ActivityEvent.swift`/`ActivityReport.swift` 동작을 근거로 만든 v1 JSONL 골든 라인열을 입력으로 plan별 세션 롤업(`(root,project,task,plan,planIndex)` grouping, idle gap 25분/lead pad 5분), task.seconds=union 유지, `planStatus`와 task `status` 분리, `taskProgressDone`/`taskProgressTotal` 유지, `items[]` 최신 step snapshot 및 empty snapshot clearing, 구버전 라인(`plan`/`planIndex`/`planStatus`/`taskProgress*`/`items` 없음) fallback 테스트. 특히 empty `items[]` snapshot이 기존 step rows를 지우는 의미인지 `ActivityReport.swift`의 rollup/step snapshot 로직으로 먼저 확정하고 테스트명에 그 계약을 드러낸다.
- green: `application/recordActivity`(brief 변경 감지 → 동일 포맷 append) + `buildReport`(롤업) + report UI(Today=plan 상세, Week/Month=task 합계). 기존 activity.jsonl과 연속성 확인.
- 검증: `pnpm --filter @workbranch/companion test`, report 뷰 수동 확인.

### Slice G — 시스템 통합 (login item / 설정 / 패키징)
- 자동 시작(login item), appearance/설정 영속, `LSUIElement` 상당(Dock 미표시), 앱 번들/서명/배포 경로(packaging) 정리. 기존 `packaging/`·cask 흐름과 정합.
- release/CI path migration을 이 Slice의 필수 산출물로 둔다. 영향을 받는 workflow는 최소 `.github/workflows/ci.yml`, `.github/workflows/release-please.yml`, `.github/workflows/homebrew-bump.yml`, `.github/workflows/companion-ci.yml`, `.github/workflows/companion-release.yml`이다.
  - `.github/workflows/ci.yml`은 `apps/workbranch-cli/**`를 감지하고 `apps/workbranch-cli/scripts/build-workbranch.sh`/`apps/workbranch-cli/tests/run.sh`를 실행해야 한다.
  - `.github/workflows/release-please.yml`은 기존 0022 결정(`separate-pull-requests: true`)을 유지한 채 config/manifest path migration을 읽어야 한다.
  - `.github/workflows/homebrew-bump.yml`은 root CLI release tag와 moved formula build/install path가 맞는지 확인해야 한다.
  - `.github/workflows/companion-ci.yml`은 `apps/workbranch-companion/**`와 `packages/contract/**` 변경을 감지하고 pnpm/Tauri 검증을 실행해야 한다.
  - `.github/workflows/companion-release.yml`은 `apps/workbranch-companion` 산출물 경로와 Tauri bundle/zip 경로를 사용해야 하며, Swift 전용 `companion/scripts/build-app.sh`와 `companion/dist/WorkbranchCompanion.app` 참조를 제거/대체해야 한다.
- `release-please-config.json`/`.release-please-manifest.json` migration은 명시적으로 처리한다. Root CLI package key `.`는 root release tag(`vX.Y.Z`)와 Homebrew formula 흐름을 유지하기 위해 보존하는 것을 기본값으로 한다; root package의 `extra-files`는 `apps/workbranch-cli/bin/workbranch`(그리고 root compatibility artifact를 유지한다면 그 artifact)로 갱신한다. Companion package key는 기존 `companion`에서 `apps/workbranch-companion`으로 옮기고 manifest version 값을 carry-over한다. Companion Swift 전용 extra-files(`scripts/build-app.sh`)는 Tauri version source(`apps/workbranch-companion/src-tauri/tauri.conf.json`, 필요 시 `package.json`/`Cargo.toml`)로 대체하거나 제거한다. Root package `exclude-paths`는 `apps/workbranch-companion/**`·`packages/contract/**` 기준으로 갱신한다.
- 검증: `pnpm --filter @workbranch/companion tauri build` 산출 앱 실행, 로그인 항목 등록/해제 수동 확인, release-please dry-run 또는 config invariant test, Homebrew formula/cask source invariant test. 검증은 버전 문자열 수렴이 아니라 package key/path/extra-files/workflow path가 실제 새 layout을 가리키는지 확인한다.

### Slice H — Swift companion 제거 + 문서 동기화
- 패리티 체크리스트 통과 확인 후 legacy `companion/`(Swift) 디렉터리·SwiftPM·관련 CI 제거. README(EN/KO)·`docs/architecture.md`·legacy `companion/README.md` 내용·릴리스/패키징 문서를 Tauri 스택과 monorepo 레이아웃에 맞춰 갱신. 0019를 superseded로 상호 링크.
- 검증: `apps/workbranch-cli/tests/run.sh`(CLI 무영향), `pnpm -r test`, `git diff --check`, 문서 EN/KO 동기화 확인.

## 최종 검증

```bash
# CLI 무영향 (수정 안 함을 확인)
/bin/bash -n apps/workbranch-cli/bin/workbranch install.sh apps/workbranch-cli/install.sh apps/workbranch-cli/tests/run.sh
apps/workbranch-cli/scripts/build-workbranch.sh
apps/workbranch-cli/tests/run.sh
# Workspace
pnpm install
pnpm run build               # pnpm workspace scripts 또는 turbo run build
pnpm run typecheck           # pnpm workspace scripts 또는 turbo run typecheck
pnpm run lint                # pnpm workspace scripts 또는 turbo run lint
pnpm run test                # workspace tests + contract/companion vitest
# Tauri
cargo test --manifest-path apps/workbranch-companion/src-tauri/Cargo.toml
pnpm --filter @workbranch/companion tauri build  # 번들 산출 + 실행 수동 확인
# Packaging / release compatibility
ruby -c packaging/homebrew/workbranch.rb
grep -q 'apps/workbranch-cli/bin/workbranch' packaging/homebrew/workbranch.rb
grep -q 'apps/workbranch-cli/bin/workbranch' install.sh
grep -q 'WORKBRANCH_RAW_BASE_URL' install.sh
# release metadata must preserve independent packages and point to moved paths, not force equal versions
grep -q '"\."' .release-please-manifest.json
grep -q 'apps/workbranch-companion' .release-please-manifest.json release-please-config.json
grep -q 'separate-pull-requests' release-please-config.json
grep -q 'apps/workbranch-cli/bin/workbranch' release-please-config.json
! grep -q 'companion/scripts/build-app.sh' release-please-config.json .github/workflows/companion-release.yml
git diff --check
```

## 롤아웃 / 호환성

- **점진 패리티 → 교체.** Slice A–G 동안 Swift `companion/`과 Tauri `apps/workbranch-companion/`이 공존한다. 사용자는 둘 중 하나만 실행하면 된다(둘 다 동일 CLI를 read-only로 소비하므로 상태 손상 없음). 패리티 확인 후 Slice H에서 Swift 제거.
- **activity.jsonl 연속성.** 동일 포맷·동일 경로를 유지하므로 기존 시간 기록이 새 앱에서 그대로 집계된다. 마이그레이션 불필요.
- **CLI public surface 무변경 + installer compatibility 우선.** CLI source path는 `apps/workbranch-cli`로 이동하지만 설치되는 command 이름, `workbranch` argv, raw/root installer, Homebrew formula behavior는 유지한다. repo layout/release path 변화만으로 CLI major를 강제하지 않는다. CLI major는 `curl | bash`/Homebrew/raw artifact 같은 지원 install path를 보존할 수 없을 때만 별도 결정으로 정당화한다. 구/신 companion 어느 쪽이든 같은 `list --json`/`list --global --json`(schemaVersion 1)을 본다. 계약 박제(Slice B)는 출력 변경이 아니므로 회귀 위험 없음.
- **Companion release는 독립 semver.** Swift companion에서 Tauri companion으로 stack/runtime/package path가 바뀌므로 companion은 독립 release-please package에서 semver를 결정한다. major release가 타당할 수 있지만 CLI 버전과 동기화하지 않는다.
- **두 앱 동시 실행 시 activity.jsonl 중복 append 가능** → 패리티 기간엔 한 번에 하나만 실행하도록 안내(롤아웃 노트).

## 미해결 / 후속

- **CLI 명령 결과의 구조화.** command side는 현재 사람이 읽는 출력/exit code만 본다. v1 companion은 `memo`/`noti clear`/launch action의 success/failure 정도만 표시한다. `done`/`land`/`push` 같은 lifecycle/Git mutation을 companion에 추가하려면 `--json` 결과 모드와 confirm/cancel UX가 필요할 수 있음(별도 plan, 계약 확장).
- **Tauri 트레이 UX 미세조정.** macOS menu bar 정렬·다크모드·다중 디스플레이 동작은 Slice E/G에서 수동 검증 후 별도 다듬기.
- **Windows/Linux.** Tauri는 크로스플랫폼이지만 본 계획은 macOS만 대상. 타 OS는 후속.

## 실행 결과

진행 상태(2026-06-16): Slice A-H를 구현했다.

- Slice A: repo를 pnpm workspace monorepo로 정리하고 Bash CLI source/build/test/install surface를 `apps/workbranch-cli/**`로 이동했다. Root `bin/workbranch`는 raw/curl installer compatibility artifact로 유지한다. Root `install.sh`는 checkout install에서는 `apps/workbranch-cli/bin/workbranch`를 우선하고, raw download에서는 새 경로를 먼저 시도한 뒤 기존 `bin/workbranch`로 fallback한다. Homebrew formula, CI, release-please extra-files도 새 CLI app path를 가리킨다.
- Slice B: `packages/contract`에 `list --json`/`list --global --json` schema, readonly TS DTO, fixtures, live CLI drift tests를 추가했다.
- Slice C-F: `apps/workbranch-companion`에 Tauri v2 + React/TypeScript companion을 추가했다. Rust port는 typed allowlist subprocess, `/usr/bin/pbcopy` stdin copy, installed/local `workbranch` lookup, tray icon/window toggle, notify 기반 root watcher를 제공하고 JSON은 TS ACL로 넘긴다. TS domain/application/UI는 Task▶Plan▶Step, ACL mapping, menu state, activity rollup, empty `items[]` snapshot clearing, React task rows를 구현했다.
- Slice G: companion CI/release workflow를 pnpm/Tauri bundle path로 전환했고, release-please companion package key를 `apps/workbranch-companion`으로 migration했다. Bundle name은 기존 cask 호환을 위해 `WorkbranchCompanion.app`으로 유지한다.
- Slice H: legacy Swift `companion/` directory를 제거하고 README EN/KO, `docs/architecture.md`, `docs/git-operations.md`, app README를 Tauri/monorepo layout으로 갱신했다.

검증 완료:

```bash
/bin/bash -n bin/workbranch install.sh apps/workbranch-cli/install.sh apps/workbranch-cli/tests/run.sh apps/workbranch-cli/scripts/build-workbranch.sh
apps/workbranch-cli/scripts/build-workbranch.sh
cmp apps/workbranch-cli/bin/workbranch bin/workbranch
apps/workbranch-cli/tests/run.sh                    # 257 tests passed
pnpm run build
pnpm run typecheck
pnpm run lint                                      # passed with Biome infos only in runtime parser guards
pnpm run test                                      # contract + companion + CLI tests passed
cargo test --manifest-path apps/workbranch-companion/src-tauri/Cargo.toml
cargo clippy --manifest-path apps/workbranch-companion/src-tauri/Cargo.toml --all-targets -- -D warnings
pnpm --filter @workbranch/companion tauri build    # emitted WorkbranchCompanion.app
ruby -c packaging/homebrew/workbranch.rb
ruby -ryaml -e "YAML.load_file('.github/workflows/ci.yml'); YAML.load_file('.github/workflows/companion-ci.yml'); YAML.load_file('.github/workflows/companion-release.yml'); YAML.load_file('.github/workflows/homebrew-bump.yml'); YAML.load_file('.github/workflows/release-please.yml')"
# checkout/raw installer smoke: both installed `workbranch 1.24.1`
git diff --check
```

남은 수동 확인/후속:

- 실제 macOS menu bar 위치/다크모드/다중 디스플레이 UX는 bundle build까지만 자동 검증했고, 사람 눈으로 실행 확인이 필요하다.
- Login item toggle과 appearance setting UI는 Tauri follow-up으로 남긴다.
- Published release signing/notarization은 기존 workflow secret이 있는 GitHub Actions에서 검증해야 한다.
