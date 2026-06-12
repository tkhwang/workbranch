# 0019 Native SwiftUI Menu Bar Companion 계획

> **agentic worker 지침:** 실행 시 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용한다. CompanionCore(menu model 파생, JSON decode, argv builder, config 검증, debounce 정책)는 TDD로 구현하고 `swift test`로 검증한다. unit test에서 FSEvents, `Process` 실행, SwiftUI rendering을 직접 수행하지 않는다. companion 코드는 `companion/**`에만 둔다. Bash CLI 코드(`src/workbranch/**`)와 `bin/workbranch`를 수정하지 않는다.
>
> **시리즈 위치:** menu bar companion의 핵심 제품 단계다. **이 계획은 0017(SwiftBar plugin)을 대체한다(supersede).** 0017의 제품 결정(memo-first UI, CLI contract, action execution boundary, multi-root config)은 계승하고, 기술 스택 결정(SwiftBar, TypeScript/Node, polling)은 폐기한다. 현재 순서: 0015 memo/noti/json(완료) → **0019 native menu bar companion** → 0018 배포 배관(cask 기준으로 재작성 필요). hard dependency는 0015의 `workbranch list --json`, `workbranch memo`, `workbranch noti`뿐이다.

**목표:** native SwiftUI menu bar app(`WorkbranchCompanion.app`)을 local로 제공한다. menu bar에서 task workspace 목록, memo title, notification count, dirty 상태를 보여주고, popover에서 memo inline 수정, notification clear, 새 workspace 생성, 기존 `workbranch finder` / `ide` / `terminal` launch action을 제공한다. polling 없이 FSEvents 기반 event-driven으로 갱신한다.

**아키텍처:** companion은 workbranch CLI의 presentation-only client다. 상태 전달은 pull(`workbranch list --json`이 유일한 source of truth), 변경 감지는 push(FSEvents)로 분리한다. root별 FSEvents watcher가 변경을 감지하면 debounce 후 **변경된 root만** `list --json`을 재실행해 UI를 갱신하고, watcher가 놓치는 경우를 대비해 느린 heartbeat(5분)를 fallback으로 둔다. 모든 mutation은 `Process` + argv array + explicit `cwd`로 CLI를 호출하며, memo text나 path를 shell string에 interpolate하지 않는다. 순수 로직은 `CompanionCore` 모듈로 분리해 unit test하고, FSEvents/`Process`/SwiftUI는 얇은 IO wrapper로 둔다.

**기술 스택:** Swift 5.9+, SwiftUI `MenuBarExtra`(macOS 13+, `.window` style), FSEvents, `UserNotifications`, Swift Package Manager(Xcode project 없음), XCTest, 기존 Bash `workbranch` CLI contract.

**제품 관점:** companion의 핵심 가치는 task cockpit이다. "어떤 task가 있고, 각 task가 무엇이며, 어떤 task에 알림이 있고, 메모를 어떻게 갱신할지"를 menu bar에서 즉시(이벤트 발생 직후) 볼 수 있어야 한다. idle 상태에서 비용이 거의 없어야 한다.

---

## 문제

0015로 `list --json`, `memo`, `noti`가 생겼지만 사용자는 task 상태를 보려면 terminal로 돌아가야 한다. 0017은 SwiftBar plugin으로 이를 풀려 했지만 설계 검토에서 구조적 한계가 드러났다.

- SwiftBar 일반 plugin은 실행-종료 모델이라 polling이 강제된다. idle 상태에서도 interval마다 Node process + root별 `list --json` + task×repo 수만큼의 `git status`가 돈다.
- polling을 피하려면 SwiftBar streamable plugin(상주 process + FSEvents)이 필요한데, 그 시점엔 native app과 아키텍처가 같으면서 SwiftBar/Node 의존만 남는다.
- memo 편집이 `osascript display dialog`에 갇힌다(0017 위험 섹션에 명시된 한계).
- 배포가 SwiftBar 설치 + plugin 설치 + Node bundle의 3단 의존이 된다. native app은 cask 하나다.

처음 개발을 시작하는 시점이므로 중간 단계(SwiftBar) 없이 최종형(native)으로 바로 간다.

## 현재 repo 근거

- `workbranch list --json` shape (`schemaVersion: 1`):
  - `project`
  - `root`
  - `tasks[].name`
  - `tasks[].path`
  - `tasks[].memoTitle`
  - `tasks[].notiCount`
  - `tasks[].repos[].name/branch/dirty`
- `workbranch memo`는 `<task>/TASK-WORKBRANCH.md`를 읽고/쓰고/삭제한다.
- `workbranch noti add/list/clear`는 `<task>/.workbranch/notifications.jsonl`을 관리한다.
- `workbranch add <task>`는 repo setup command 때문에 오래 걸릴 수 있어 detached spawn이 필요하다.
- `workbranch finder`, `workbranch ide`, `workbranch terminal`이 launch action을 제공한다.
- JSON path는 network/Git fetch 없이 `git status --porcelain`만 사용하므로(0015 결정) 이벤트 직후 재실행해도 안전하다.
- task 상태가 전부 파일(`TASK-WORKBRANCH.md`, `.workbranch/notifications.jsonl`, repo worktree)이므로 FSEvents가 producer 협조 없이 모든 변경(agent 직접 쓰기, 사람 수동 편집, CLI 호출)을 감지한다.

## 결정 사항

- [x] **SwiftBar 폐기, native SwiftUI `MenuBarExtra` 채택.** (0017 stack 결정 대체)
  - 최소 지원: macOS 13 Ventura.
  - `LSUIElement = true`로 Dock 아이콘 없는 menu bar 전용 app.

- [x] **repo는 분리하지 않는다. 이 repo의 `companion/` 하위 패키지로 개발한다.**
  - companion은 `list --json` contract(schemaVersion)의 소비자다. contract 변경(예: 향후 `memoUpdatedAt` 확장)을 CLI 수정 + companion 대응 + 양쪽 테스트가 **한 PR**로 landing되어야 drift가 없다. repo를 나누면 contract 변경마다 cross-repo PR 조율과 버전 호환성 매트릭스 관리가 생긴다.
  - companion 통합 테스트는 repo 안의 실제 `bin/workbranch`를 temp project에 실행해 `list --json` 출력을 fixture로 쓸 수 있다. 분리 repo에서는 fixture 복제본이 조용히 drift한다.
  - nx/turborepo 같은 monorepo 도구는 도입하지 않는다. "한 repo + 패키지 두 개"이며 추가 tooling이 필요한 규모가 아니다.
  - **배포까지 고려해도 분리가 불필요하다:**
    - release cadence 분리는 release-please component tag로 해결한다 — root는 plain `v*`(CLI formula), companion은 `workbranch-companion-v*`(app cask). 0018의 two-package 방향을 그대로 사용한다.
    - changelog/commit 분리는 `feat(companion): ...` scope와 `companion/CHANGELOG.md`로 한다.
    - Homebrew 채널은 어차피 별도 repo인 `tkhwang/homebrew-tap`이 `Formula/workbranch.rb`(CLI)와 `Casks/workbranch-companion.rb`(app)를 나란히 담는다. 소스 repo 분리를 요구하지 않는다.
    - CI는 path-filtered workflow로 분리한다: 기존 `ci.yml`은 Bash suite 전용 유지, `companion-ci.yml`(`companion/**` trigger, macOS runner, `swift build`/`swift test`)을 추가한다. 구체 wiring은 재작성될 0018 범위다.
  - 분리 재검토 신호(그 전까지는 유지): companion에 별도 기여자/이슈 트래커/권한 분리가 필요해질 때, 서명·공증 secrets와 macOS 파이프라인이 CLI repo CI를 무겁게 만들 때, companion이 workbranch 외 대상을 다루는 독립 제품이 될 때. 분리는 `git filter-repo`로 `companion/` 히스토리만 추출하면 되므로 나중에 해도 비용이 낮다.

- [x] **polling 제거: FSEvents + debounce + per-root re-pull + heartbeat.**
  - root별 FSEvents stream(recursive)으로 변경 감지.
  - refresh trigger는 worktree/task-state 변경에 집중하고 `.git/` 내부 이벤트는 초기 구현부터 제외한다. Git 내부 bookkeeping 이벤트 폭주가 native app 비용을 키우지 않게 하기 위함이다.
  - root별 1–2초 debounce로 이벤트 폭주를 coalesce한다.
  - root별 in-flight refresh는 하나만 허용한다. refresh 실행 중 추가 이벤트가 들어오면 pending flag를 세우고 완료 후 한 번 더 coalesce된 refresh를 실행한다.
  - 변경이 감지된 root만 `list --json` 재실행.
  - fallback heartbeat: 5분 간격 전체 re-pull (watcher 누락 보험).
  - 상태 자체를 push로 나르지 않는다. 신호는 "다시 pull할 타이밍"만 알린다.

- [x] **memo-first UI.** (0017 계승)
  - task row primary action은 memo 편집이다. popover 안 inline TextField로 편집하고 저장 시 `workbranch memo <task> <text>`를 호출한다. osascript dialog를 사용하지 않는다.

- [x] **CLI가 유일한 contract.** (0017 계승)
  - companion은 config parsing과 Git 상태 판단을 재구현하지 않는다.
  - `schemaVersion` 확인 + `list --json` 실행/JSON parse 실패를 feature detection으로 삼아 user-facing error row로 보여준다.
  - notification 감지도 jsonl 직접 읽기가 아니라 `list --json`의 `notiCount` 증가로 판단한다.

- [x] **action execution boundary.** (0017 계승)
  - 모든 CLI 호출은 `Process` + argv array + explicit `cwd`.
  - shell interpolation 금지. Hangul/space/quote가 포함된 memo text와 path를 그대로 전달한다.

- [x] **multi-project config.** (0017 계승)
  - config path: `~/.config/workbranch-companion/config.json`
  - shape: `{"roots": ["/abs/path", ...], "workbranchBin": "/optional/abs/path"}`

- [x] **binary 탐색은 config 우선, 알려진 경로 fallback.**
  - GUI app은 shell PATH를 상속하지 않으므로 0017의 `WORKBRANCH_BIN`/`command -v` 방식은 동작하지 않는다.
  - 순서: config `workbranchBin` → `/opt/homebrew/bin/workbranch` → `/usr/local/bin/workbranch` → `~/.local/bin/workbranch`.
  - 못 찾으면 menu에 설치 안내 error row를 보여준다.
  - launch action 실행 시 PATH에 위 디렉토리들을 보강해 넘긴다(`workbranch terminal` 등이 내부에서 외부 도구를 찾을 수 있도록).

- [x] **SPM-only, Xcode project 없음.**
  - `companion/Package.swift` 하나로 core library + app executable target을 관리한다.
  - `.app` bundle은 `companion/scripts/build-app.sh`가 조립한다(Info.plist 생성, binary 배치, ad-hoc codesign).
  - 이유: pbxproj 없이 전부 텍스트 파일이라 agent/CI 친화적이고 diff 리뷰가 가능하다.

- [x] **core/IO 분리.**
  - `CompanionCore`: JSON decode model, menu state 파생, action argv builder, config 검증, debounce 정책. `Process`/FSEvents/SwiftUI import 금지. 전부 unit test.
  - `CompanionApp`: SwiftUI UI, FSEvents wrapper, `Process` wrapper, UserNotifications. 얇게 유지.

- [x] **새 workspace 생성은 detached.** (0017 계승, 이름 계약은 0019에서 수정)
  - task name validation은 companion 전용 lowercase regex를 두지 않고 CLI의 task-folder 계약과 맞춘다.
  - 기준: `workbranch add <task>`가 받는 task folder semantics와 동일하게 non-empty, slash 없음, `.`/`..` 금지, `[A-Za-z0-9._-]+`, conventional prefix(`feat-...`, `fix-...` 등) 해석을 허용한다.
  - companion은 CLI보다 좁은 `^[a-z0-9][a-z0-9-]*$` 같은 별도 regex를 적용하지 않는다.
  - log path: `/tmp/workbranch-add-<root-hash>-<name>.log`
  - 완료/실패는 `UserNotifications`로 알린다.

- [x] **배포는 Homebrew cask. 0018은 재작성 필요.**
  - 이 계획은 local build/install만 다룬다.
  - 0018의 npm/SwiftBar/formula 전제는 stale하다. public 배포 전 0018을 "GitHub release에 `.app` zip + 개인 tap `Casks/workbranch-companion.rb` + `swift build` CI" 기준으로 재작성한다.
  - 서명: local 단계는 ad-hoc codesign으로 충분하다. 공개 배포 시 Developer ID + notarization은 재작성된 0018 범위다.

- [ ] **notification producer hook은 follow-up.** (0017 계승)
  - 이 계획은 existing/manual notification을 표시/clear한다. Claude Code hook → `workbranch noti add` 자동 연결은 별도 계획이다.

- [ ] **`list --json` contract 확장(`memoUpdatedAt`, `lastNotiAt` 등 timestamp)은 별도 CLI 계획.**
  - companion이 memo 신선도를 표시하려면 필요하지만, 이 계획은 CLI를 수정하지 않는다.

- [ ] **Raycast extension은 scope 밖.**

## 제품 동작

1. **menu bar item**
   - template icon + task count. 예: `⎇ 4` (notification 있으면 badge 색 변경 또는 `⎇ 4 🔔2`)
   - 전체 실패 시 경고 상태 표시.

2. **popover (window style)**
   - project root별 section header.
   - task row:
     ```text
     task3 — draft-tree 가이드 작성   🔔2 ●
     ```
   - `🔔N`: notification count, `●`: repo 중 하나라도 dirty.
   - task row click → memo inline 편집 모드 (TextField + 저장/취소). 저장 시 `workbranch memo`, 빈 텍스트 저장은 `--clear`.

3. **task별 secondary actions**
   - `Clear notifications`
   - `Open terminal`
   - `Open in IDE`
   - `Reveal in Finder`
   - `Copy task path`

4. **global actions**
   - `New workspace…` (root 선택 + task name 입력, detached add)
   - `Refresh now`
   - `Open config`: config 파일이 없으면 `~/.config/workbranch-companion/config.json`에 빈 `roots: []` skeleton을 생성한 뒤 Finder/default editor로 연다. GUI app은 terminal cwd가 없으므로 현재 project root 추론은 하지 않는다.
   - `Quit`

5. **failure visibility**
   - root별 `workbranch` 실패는 stderr 요약을 해당 section의 error row로 보여준다.
   - 실패해도 빈 popover를 보여주지 않는다. 마지막 성공 상태 + error를 함께 표시한다.
   - binary 미발견, config 없음/invalid도 각각 안내 row로 표시한다.

6. **notifications**
   - 첫 load/config reload/root 추가 시에는 task별 `notiCount`를 baseline으로만 저장하고 macOS notification을 발송하지 않는다.
   - 이후 같은 root/task의 `notiCount`가 이전 baseline보다 증가할 때만 macOS notification을 발송한다.
   - `notiCount`가 감소하거나 0이 되면(예: `clear notifications`) baseline을 새 값으로 갱신한다. 기존 미확인 알림은 popover의 `🔔N`으로만 표시한다.

## 파일 구조

```text
companion/Package.swift                          # CompanionCore + CompanionApp targets
companion/Sources/CompanionCore/Models.swift      # list --json decode (schemaVersion 검증)
companion/Sources/CompanionCore/MenuState.swift   # root/task 상태 -> menu model 파생
companion/Sources/CompanionCore/Actions.swift     # action argv builder
companion/Sources/CompanionCore/Config.swift      # config load/validate/init skeleton
companion/Sources/CompanionCore/Debounce.swift    # debounce/coalesce 정책 (시계 주입)
companion/Sources/CompanionApp/CompanionApp.swift # @main MenuBarExtra entry
companion/Sources/CompanionApp/StateStore.swift   # observable state, refresh orchestration
companion/Sources/CompanionApp/RootWatcher.swift  # FSEvents 얇은 wrapper
companion/Sources/CompanionApp/CLIClient.swift    # Process 얇은 wrapper (timeout, argv)
companion/Sources/CompanionApp/Views/             # popover UI
companion/Tests/CompanionCoreTests/               # models/menu-state/actions/config/debounce tests
companion/scripts/build-app.sh                    # .app bundle 조립 + ad-hoc codesign
companion/README.md                               # local build/install/troubleshooting
README.md
README.ko.md
docs/plans/0017-companion-swiftbar-plugin.md      # superseded 표기
docs/plans/0018-companion-release-plumbing.md     # 재작성 필요 표기
```

## 구현 작업

### Task 1: package scaffold와 CompanionCore model/menu state

- [x] `companion/Package.swift` 생성: `CompanionCore` library + `CompanionApp` executable + test target.
- [x] RED: `list --json` decode fixture tests.
  - 정상 shape (memo 있음/없음, notiCount, dirty repo)
  - `schemaVersion` 불일치
  - malformed JSON
- [x] RED: menu state 파생 fixture tests.
  - empty config
  - root는 있지만 task 없음
  - per-root command failure (마지막 성공 상태 유지 + error row)
  - all-roots failure
  - notification baseline 정책: 첫 load/root 추가는 발송 없음, 같은 root/task의 `notiCount` 증가분만 발송, 감소/clear는 baseline 갱신
- [x] GREEN: `Models.swift`, `MenuState.swift` 구현. `Process`/FSEvents/SwiftUI import 금지.
- [x] 검증: `cd companion && swift build && swift test` + `swift run CompanionCoreTestRunner` 통과.

### Task 2: config, action builder, debounce 정책

- [x] RED: config tests — load, absolute root 검증, `workbranchBin` override, init skeleton(cwd에 `.workbranch.config`가 있으면 현재 root 포함), GUI `Open config` skeleton(파일 없으면 빈 `roots: []` 생성), invalid JSON.
- [x] RED: action argv builder tests — `edit-memo`(Hangul/space/quote 포함), `memo --clear`, `clear-noti`, `open-terminal`/`open-ide`/`reveal-finder`, `copy-path`, `add`(CLI-compatible task folder validation: 대문자/`.`/`_`/conventional prefix 허용, slash/empty/`.`/`..` 거부), shell interpolation 없음 확인.
- [x] RED: debounce/refresh 정책 tests — 주입된 시계 기준 coalesce, root별 독립 invalidation, `.git/` 내부 이벤트 제외, root별 in-flight refresh 중복 방지, refresh 중 pending 이벤트의 후속 1회 refresh.
- [x] GREEN: `Config.swift`, `Actions.swift`, `Debounce.swift` 구현.
- [x] 검증: `swift run CompanionCoreTestRunner`, `swift build`, `swift test` 통과.

### Task 3: app walking skeleton

- [x] `CompanionApp.swift`: `MenuBarExtra` + `.menuBarExtraStyle(.window)` + 최소 popover.
- [x] `CLIClient.swift`: binary 탐색(config → 알려진 경로), timeout, stdout/stderr/exit code structured result.
- [x] `StateStore.swift`: 시작 시 + `Refresh now` 클릭 시 root별 `list --json` 실행 → menu state 갱신.
- [x] `companion/scripts/build-app.sh`: SPM release build → `companion/dist/WorkbranchCompanion.app` 조립(Info.plist `LSUIElement=true`, minimum system version 13.0) → ad-hoc codesign.
- [x] 수동 검증 준비: `./scripts/build-app.sh`, executable bit, codesign, `LSUIElement=true`, minimum system 13.0 확인. 실제 popover smoke는 최종 manual QA에서 수행.

### Task 4: FSEvents event-driven 갱신

- [x] `RootWatcher.swift`: config root별 recursive FSEvents stream. `.git/` 내부 이벤트 제외 → debounce 정책 → 해당 root invalidation → `StateStore` re-pull.
- [x] `StateStore` refresh orchestration: root별 in-flight refresh는 하나만 허용하고, 실행 중 들어온 이벤트는 pending으로 접어 완료 후 최대 1회 재실행한다.
- [x] heartbeat: 5분 간격 전체 re-pull.
- [x] config 파일 자체도 watch해 roots 변경 시 watcher 재구성.
- [x] 수동/대체 검증(최종 app smoke에서 수행, visual popover 직접 관찰은 자동화 한계로 제외):
  - app launch + 실제 `workbranch list --json` data source 연결 확인.
  - 임시 task에서 memo/noti/dirty-source JSON round-trip 확인.
  - `.git/` 내부 이벤트 제외와 root별 동시 `list --json` 1개 제한은 `CompanionCoreTestRunner` 정책 테스트로 확인.
  - 실제 popover 2초 반영/Activity Monitor idle CPU는 자동화 한계로 직접 관찰하지 못했으며, 최종 evidence에 한계로 기록.

### Task 5: memo-first actions와 notifications

- [x] popover task row inline memo 편집 → `workbranch memo` 호출 (빈 텍스트는 `--clear`).
- [x] `Clear notifications` → `workbranch noti clear <task>`.
- [x] launch actions: terminal/IDE/Finder/Copy path/Open config (PATH 보강 포함).
- [x] `Open config`: config 파일이 없으면 빈 `roots: []` skeleton을 생성한 뒤 Finder/default editor로 연다. 기존 config는 그대로 연다.
- [x] `New workspace…`: detached spawn + log + 완료/실패 `UserNotifications`.
- [x] `notiCount` 증가 시 macOS notification 발송 (권한 요청 포함). 첫 load는 baseline만 잡고 발송하지 않으며, 이후 같은 root/task의 증가분만 발송한다.
- [x] 수동 검증(최종 app smoke에서 수행): 임시 task add 1회, memo edit round-trip(Hangul/space/quote), notification clear round-trip, copy path action 1회, cleanup 완료. Finder/IDE/terminal launch는 외부 앱 방해를 피하기 위해 argv builder 검증으로 대체.

### Task 6: docs와 local handoff

- [x] `companion/README.md`: build, local install(`build-app.sh` + `/Applications` 복사 또는 `open dist/...`), 로그인 시 자동 시작 안내, config(`Open config`는 없으면 빈 `roots: []` skeleton 생성), troubleshooting(Gatekeeper 우회 포함), known limits, release status.
- [x] root `README.md` / `README.ko.md`에 companion preview section 추가.
- [x] `0017` 상단에 superseded 표기, `0018` 상단에 재작성 필요 표기.
- [x] plan에 manual QA evidence 기록.

## 검증

```bash
cd companion && swift build
cd companion && swift test
cd companion && ./scripts/build-app.sh
open companion/dist/WorkbranchCompanion.app
```

실제 smoke (수동):

- memo 있는 task / 없는 task 표시
- notification count, dirty marker 표시
- memo edit round-trip (Hangul/space/quote)
- clear notifications round-trip
- FSEvents 반영: CLI 호출, agent 직접 파일 쓰기, 사람 수동 편집 각각 2초 내 반영
- `.git/` 내부 이벤트 폭주 중에도 refresh coalesce/in-flight 제한으로 CPU/IO가 안정적임
- idle 상태에서 CPU 사용량 ~0% 확인 (Activity Monitor)
- root 하나의 `workbranch` 실패 시 error row + 나머지 root 정상 표시
- config 없음 상태에서 `Open config` 클릭 시 빈 `roots: []` skeleton 생성 + 파일 열림
- 기존 `notiCount > 0` 상태로 앱 시작 시 macOS notification 미발송 + popover badge 표시
- 새 `workbranch noti add` 이후 macOS notification 수신
- clear notifications 후 baseline 갱신, 이후 재증가 시 notification 수신
- detached add 완료 notification 수신

## Manual QA evidence

- `cd companion && swift run CompanionCoreTestRunner` 통과: JSON decode, schemaVersion reject, menu state, notification baseline, config validation, action argv, task validation, debounce/filter/in-flight 정책.
- `cd companion && swift build && swift test` 통과. 현재 CLT에서 XCTest/Testing import가 불가해 `swift test`는 placeholder test target build 확인으로 사용하고, 동작 검증은 `CompanionCoreTestRunner`가 수행한다.
- `cd companion && ./scripts/build-app.sh` 통과: `dist/WorkbranchCompanion.app` 생성, executable bit, ad-hoc codesign, `LSUIElement=true`, `LSMinimumSystemVersion=13.0` 확인.
- `open companion/dist/WorkbranchCompanion.app` 후 `pgrep -fl WorkbranchCompanion`로 app process launch 확인. 직접 실행 stderr 없음.
- default config가 없어서 `~/.config/workbranch-companion/config.json`에 현재 workbranch project root와 이 checkout의 `bin/workbranch`를 설정해 실제 data source를 연결했다.
- 실제 `workbranch list --json` source 확인: project `workbranch`, task `feat-setup-companion-part2`, dirty marker true.
- 임시 task `test-companion-smoke-*`로 add → memo(Hangul/space/quote) → noti add → `list --json` 확인 → noti clear → memo clear → copy path → remove --force cleanup round-trip 통과.
- Finder/IDE/terminal 실제 launch와 popover 시각 확인은 자동화/사용자 방해 리스크 때문에 수행하지 않고, argv builder 검증 및 app launch smoke로 대체했다.

## 위험과 완화

- **SPM-only `.app` 조립:** Xcode project 없이 bundle을 만드는 build script가 초기 비용이다. Info.plist/서명 문제가 생기면 script를 고치면 되고, 정 안 되면 최소 Xcode project로 전환할 수 있다(코드는 그대로 이식).
- **Gatekeeper:** local 단계는 ad-hoc sign + 직접 빌드라 문제없다. cask 배포 시 quarantine 차단은 재작성된 0018에서 Developer ID + notarization으로 해결한다(과도기는 `--no-quarantine` 안내).
- **FSEvents 이벤트 폭주:** agent가 활발히 작업하면 repo 쓰기 이벤트가 쏟아진다. `.git/` 내부 이벤트는 초기 구현부터 refresh trigger에서 제외하고, root별 debounce/coalesce + in-flight refresh 1개 제한을 1차 방어선으로 둔다. `list --json`이 fetch 없는 가벼운 명령이라(0015 결정) 재실행 비용은 낮고, `.git/` 필터로 놓치는 edge는 5분 heartbeat가 보완한다.
- **GUI app의 PATH 부재:** binary 탐색을 config + 알려진 경로로 해결하고, launch action에 PATH를 보강해 넘긴다. `doctor` 성격의 안내 row로 미발견 상태를 노출한다.
- **macOS 13+ 요구:** `MenuBarExtra` 최소 버전. 대상 사용자에게 현실적 제약이 아니다.
- **old CLI contract:** `schemaVersion` + parse 실패 feature detection으로 명확한 error row를 보여준다.
- **0018 drift:** npm/formula 전제가 stale하다. public 배포 전 재작성을 이 계획의 Task 6 표기로 강제한다.
