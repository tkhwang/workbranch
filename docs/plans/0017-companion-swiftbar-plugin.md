# 0017 메모 우선 Companion SwiftBar Plugin 계획

> **상태: [0019](0019-companion-native-menubar-app.md)로 대체됨 (superseded). 이 계획을 실행하지 않는다.**
> SwiftBar/TypeScript/polling 스택 결정은 폐기되었다. 이유: SwiftBar 일반 plugin은 polling이 강제되고, 이를 피하는 streamable 구성은 native app과 아키텍처가 같으면서 SwiftBar/Node 의존만 남는다. memo-first UI, CLI contract(`list --json`), action execution boundary, multi-root config 등 제품 결정은 0019가 계승한다. 이 문서는 결정 이력 보존용이다.

> **agentic worker 지침:** 실행 시 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용한다. renderer, config loading, action arg-building, command execution boundary는 TDD로 구현한다. companion 코드는 `companion/**`에만 둔다. Bash CLI 코드(`src/workbranch/**`)를 수정하지 않는다. unit test는 `osascript`나 SwiftBar를 직접 실행하지 않는다.
>
> **시리즈 위치:** menu bar companion의 핵심 제품 단계다. 현재 순서: 0015 memo/noti/json → **0017 local 메모 우선 companion** → 0018 배포 배관. hard dependency는 0015의 `workbranch list --json`, `workbranch memo`, `workbranch noti`뿐이다. focus/open-warp와 release plumbing은 dependency가 아니다.

**목표:** SwiftBar companion을 local로 제공한다. menu bar에서 task workspace 목록, memo title, notification count를 보여주고, memo 수정, notification clear, 새 workspace 생성, 기존 `workbranch finder` / `ide` / `terminal` launch action을 제공한다.

**아키텍처:** companion은 workbranch CLI의 presentation-only client다. refresh마다 configured project root별로 `workbranch list --json`을 실행하고 SwiftBar menu line을 렌더링한다. menu click은 `workbranch-companion action <verb> ...`로 들어오고 action runner는 argv array와 explicit `cwd`로만 CLI를 실행한다. memo text나 path를 shell string에 interpolate하지 않는다. `render.ts`, `actions.ts`는 pure module로 unit test하고, `exec.ts`, `index.ts`, `cli.ts`는 얇은 IO wrapper로 둔다.

**기술 스택:** TypeScript, Node 20+, esbuild single-file bundle, vitest, SwiftBar, `osascript` dialog/notification, 기존 Bash `workbranch` CLI contract.

**제품 관점:** companion의 핵심 가치는 terminal focus가 아니라 task cockpit이다. “어떤 task가 있고, 각 task가 무엇이며, 어떤 task에 알림이 있고, 메모를 어떻게 갱신할지”를 menu bar에서 빠르게 볼 수 있어야 한다.

---

## 문제

0015로 `list --json`, `memo`, `noti`가 생겼지만 아직 사용자는 task 상태를 보려면 terminal로 돌아가야 한다. 여러 task를 동시에 돌릴 때 필요한 것은 terminal focus보다 task 상태의 glanceability와 빠른 메모 수정이다.

기존 `finder`, `ide`, `terminal` 명령이 이미 열기 action을 제공하므로, v1 companion은 focus/open-warp에 의존하지 않는다.

## 현재 repo 근거

- `workbranch list --json` shape:
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
- `workbranch finder`, `workbranch ide`, `workbranch terminal`은 v1 secondary launch action으로 충분하다.
- SwiftBar plugin은 executable file이 stdout menu line을 출력하는 방식이다. `---`가 title/dropdown을 나누고, `bash=`, `param1=`, `terminal=false`, `refresh=true` 같은 params로 click action을 연결한다.

## 결정 사항

- [x] **memo-first UI.**
  - task row primary action은 `edit-memo`다. launch action은 submenu/secondary action이다.

- [x] **0016 focus/open-warp dependency 없음.**
  - `workbranch focus` / `workbranch open warp`를 v1 contract에서 제거한다.
  - launch는 기존 `finder`, `ide`, `terminal`을 사용한다.

- [x] **SwiftBar 먼저, native SwiftUI는 나중.**
  - 빠르게 검증하고, CLI contract를 유지하면 나중에 Raycast/native app으로 옮기기 쉽다.

- [x] **TypeScript/Node 사용.**
  - JSON rendering, multi-root aggregation, quoting, unit test를 Bash보다 안전하게 다룰 수 있다.

- [x] **multi-project config.**
  - config path: `~/.config/workbranch-companion/config.json`
  - shape: `{"roots": ["/abs/path", ...]}`
  - SwiftBar는 workbranch project cwd에서 실행되지 않으므로 root list가 필요하다.

- [x] **action execution boundary.**
  - `workbranch`는 core worktree/task CLI로 유지한다.
  - `workbranch-companion`은 menu bar display/action 앱이다.
  - build output은 `companion/dist/workbranch-companion`과 `companion/dist/workbranch.5s.js` 두 개로 둔다.
  - local install은 `companion/dist/workbranch-companion`을 `~/.local/bin/workbranch-companion`에 설치하고, SwiftBar plugin은 이 executable을 action runner로 호출한다.
  - SwiftBar line은 `workbranch-companion action <verb> --root <root> --task <task>`를 호출한다.
  - action runner는 `child_process.spawn` / `spawnSync`와 argv array만 사용한다.
  - shell interpolation 금지.

- [x] **CLI contract는 feature detect.**
  - release version이 정해지기 전에는 semver minimum보다 `list --json` 실행/JSON parse 실패를 user-facing error로 보여준다.

- [x] **새 workspace 생성은 detached.**
  - `workbranch-companion action add --root <root> --task <name>`
  - task name regex: `^[a-z0-9][a-z0-9-]*$`
  - log path: `/tmp/workbranch-add-<root-hash>-<name>.log`
  - 완료/실패는 notification으로 알린다.

- [x] **release plumbing은 scope 밖.**
  - local package와 local SwiftBar install만 제공한다.
  - public Homebrew distribution은 0018에서 한다.

- [ ] **notification producer hook은 follow-up.**
  - 이 계획은 existing/manual notification을 표시/clear한다. agent hook 자동 연결은 별도 계획이다.

- [ ] **Raycast/native app은 scope 밖.**

## 제품 동작

1. **bar title**
   - 예: `wb 4 🔔2`
   - 4 tasks, notification 있는 task 2개
   - 전체 실패 시 `wb !`

2. **dropdown**
   - project root별 header
   - task row 예:
     ```text
     task3 — draft-tree 가이드 작성 🔔2 ●
     ```
   - `🔔N`: notification count
   - `●`: repo 중 하나라도 dirty
   - task row click: edit memo

3. **task submenu/action**
   - `Edit memo…`
   - `Clear notifications`
   - `Open terminal`
   - `Open in IDE`
   - `Reveal in Finder`
   - `Copy task path`

4. **global action**
   - `New workspace…`
   - `Refresh now`
   - `Open config`
   - `Doctor`

5. **failure visibility**
   - root별 `workbranch` 실패는 stderr를 menu item으로 보여준다.
   - 실패해도 empty menu를 출력하지 않는다.

6. **installer CLI**
   - `workbranch-companion`은 menu bar companion의 public local executable이다.
   - `workbranch-companion install`
   - `workbranch-companion uninstall`
   - `workbranch-companion init`
   - `workbranch-companion doctor`
   - `workbranch-companion action ...`

## 파일 구조

```text
companion/package.json              # deps/scripts: build, typecheck, test
companion/package-lock.json          # npm ci lockfile
companion/tsconfig.json
companion/src/index.ts              # config -> list --json per root -> render -> stdout
companion/src/render.ts             # pure SwiftBar renderer
companion/src/actions.ts            # pure action param/argv builders
companion/src/action-runner.ts      # argv/cwd 기반 action 실행
companion/src/cli.ts                # workbranch-companion executable entry: install/uninstall/init/doctor/action router
companion/src/config.ts             # config load/validate/write skeleton
companion/src/exec.ts               # child_process wrapper, test에서 mock
companion/test/render.test.ts       # memo/no-memo/noti/dirty/error fixtures
companion/test/actions.test.ts      # params/argv/escaping tests
companion/test/config.test.ts       # config validation/init tests
companion/README.md                 # local install/troubleshooting
README.md
README.ko.md
```

## 구현 작업

### Task 1: package scaffold와 renderer

- [ ] `companion/package.json`, `package-lock.json`, `tsconfig.json` 생성.
- [ ] script 추가:
  - `build`: `dist/workbranch-companion`과 `dist/workbranch.5s.js` 생성
  - `typecheck`
  - `test`
- [ ] render fixture 작성:
  - empty config
  - root는 있지만 task 없음
  - memo 있음/없음
  - notification count 있음
  - dirty repo 있음
  - per-root command failure
  - all-roots failure
- [ ] `render.ts` 구현.
  - input: companion state
  - output: SwiftBar menu lines
  - `child_process`, `fs`, osascript helper import 금지
- [ ] 검증:
  - `cd companion && npm run typecheck`
  - `cd companion && npm test`

### Task 2: config와 data loading

- [ ] `config.ts` 구현.
  - `~/.config/workbranch-companion/config.json` load
  - absolute root validation
  - cwd에 `.workbranch.config`가 있으면 `init` skeleton에 현재 root를 넣는다.
- [ ] `exec.ts` 구현.
  - timeout 지원
  - stdout/stderr/exit code structured result
- [ ] `index.ts` 구현.
  - `WORKBRANCH_BIN`
  - `command -v workbranch`
  - common Homebrew paths 순서로 binary locate
  - root별 `cwd`에서 `workbranch list --json` 실행
  - success/failure aggregate 후 render
- [ ] unit test:
  - success
  - timeout
  - malformed JSON
  - missing CLI
  - partial multi-root failure

### Task 3: memo-first actions

- [ ] `actions.ts` builder 구현.
  - `edit-memo`
  - `clear-noti`
  - `open-terminal`
  - `open-ide`
  - `reveal-finder`
  - `copy-path`
  - `add`
  - `refresh`
  - `doctor`
- [ ] `action-runner.ts` 구현.
  - edit memo: `osascript display dialog` 후 `workbranch memo <task> <answer>`
  - cancel: no-op
  - clear notifications: `workbranch noti clear`
  - launch: `workbranch terminal` / `ide` / `finder`
  - copy path: `pbcopy`
  - add workspace: detached spawn + log + notification
- [ ] unit test:
  - Hangul
  - spaces
  - quotes
  - cancelled dialog
  - invalid task name
  - root/task argv construction
  - shell interpolation 없음

### Task 4: installer와 doctor CLI

- [ ] `cli.ts` command router 구현.
- [ ] `install`:
  - `defaults read com.ameba.SwiftBar PluginDirectory`
  - fallback: `~/Library/Application Support/SwiftBar/Plugins`
  - `dist/workbranch.5s.js`를 SwiftBar plugin dir에 copy
  - `dist/workbranch-companion`을 `~/.local/bin/workbranch-companion`에 copy 또는 symlink
  - 두 파일 모두 executable bit 설정
- [ ] `uninstall`: SwiftBar plugin file과 `~/.local/bin/workbranch-companion` 제거.
- [ ] `init`: config skeleton 작성.
- [ ] `doctor`:
  - SwiftBar 존재 여부
  - plugin install path
  - `~/.local/bin/workbranch-companion` 설치 여부
  - config validity
  - `workbranch` binary availability
  - 각 root에서 `workbranch list --json` 가능 여부
- [ ] manual QA:
  - build
  - install
  - real project task render
  - memo edit
  - notification clear
  - launch action 1개
  - test workspace add 1개
  - uninstall

### Task 5: docs와 local handoff

- [ ] `companion/README.md` 작성.
  - local install
  - config
  - SwiftBar setup
  - troubleshooting
  - known limits
  - release status
- [ ] root `README.md` / `README.ko.md`에 companion preview section 추가.
- [ ] plan에 manual QA evidence 기록.

## 검증

```bash
cd companion && npm ci
cd companion && npm run typecheck
cd companion && npm test
cd companion && npm run build
```

추가 manual verification:

```bash
workbranch-companion install
test -x ~/.local/bin/workbranch-companion
workbranch-companion doctor
workbranch-companion uninstall
```

실제 SwiftBar smoke:

- memo 있는 task 표시
- memo 없는 task 표시
- notification count 표시
- dirty repo marker 표시
- memo edit round-trip
- clear notifications round-trip
- launch action 동작

## 위험과 완화

- **5초 polling 비용:** 느리면 SwiftBar interval을 늘린다. 새 CLI fast mode는 나중에 판단한다.
- **osascript dialog UX 한계:** v1에서는 허용한다. rich editor는 native app 후속 범위다.
- **SwiftBar plugin directory drift:** `install`과 `doctor`가 실제 경로를 resolve/report한다.
- **old CLI contract:** feature detection으로 명확한 error menu를 보여준다.
- **detached add 실패:** root/task scoped log와 notification으로 추적 가능하게 한다.
