# workbranch

**한국어** | [English](README.md)

[![CI](https://github.com/tkhwang/workbranch/actions/workflows/ci.yml/badge.svg)](https://github.com/tkhwang/workbranch/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/tkhwang/workbranch?sort=semver)](https://github.com/tkhwang/workbranch/releases)
[![License: MIT](https://img.shields.io/github/license/tkhwang/workbranch)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-informational)

`git worktree` 명령을 매번 기억하지 않아도 task 단위 worktree를 관리할 수 있습니다.

`workbranch`는 feature마다 하나의 task 폴더를 만들고, single repo와 multi-repo 프로젝트 모두에서 짧고 안전한 branch refresh 명령을 제공합니다.

> 🖥️ **GUI를 선호하나요?** [WorkbranchCompanion](#native-menu-bar-companion)은 task 상태, 진행률, 알림을 메뉴바에서 한눈에 보여주는 macOS 네이티브 메뉴바 앱입니다.

![workbranch demo](./docs/figs/workbranch-demo.gif)

## Install

### Homebrew

```bash
brew install tkhwang/tap/workbranch
```

tap을 먼저 추가하는 방식을 선호한다면:

```bash
brew tap tkhwang/tap
brew install workbranch
```

### curl installer

```bash
curl -fsSL https://raw.githubusercontent.com/tkhwang/workbranch/main/install.sh | bash
```

Homebrew는 published release를 설치하고, curl installer는 `main`을 따라갑니다.

## Repo top에서 build/run

Monorepo root script로 두 deployable app을 모두 build/run할 수 있습니다.

```bash
pnpm install
pnpm cli:build
pnpm cli:run -- version
pnpm companion:build
pnpm companion:run
```

명시적 app alias도 제공합니다: `pnpm apps:cli:build`, `pnpm apps:cli:run -- <args>`, `pnpm apps:companion:build`, `pnpm apps:companion:run`.

## Quick start

`workbranch init`이 설정을 안내하고, 첫 task까지 바로 만들 수 있습니다.

```bash
workbranch init
# 프로젝트 이름 입력 후 repo 하나 등록 (이름 + Git URL + base branch)
# "Add another repo?"    -> N       # 시작은 repo 하나면 충분합니다
# "Add your first task?" -> login   # feat-login workspace 생성
```

추가적인 task가 필요하면 언제든 `workbranch add`로 만들 수 있습니다.

```bash
workbranch add login # (branch) feat/login
                     # (folder) feat-login/<repo>
```

이 quick-start 예시는 `main`/`master` base 기준입니다. 모든 repo가 `feature/cpq` 같은 동일 parent feature branch를 base로 쓰면 `workbranch add login`은 task name만 묻고 folder `feature-cpq-login/<repo>`, branch `feature/cpq-login`을 만듭니다.

## 생성되는 구조

각 task마다 하나의 공유 task 디렉토리 아래에 linked worktree가 만들어집니다.

```text
my-app-workspace
├── .workbranch.config
├── _base
│   ├── frontend
│   └── backend
└── feat-login          // task root: git 미관리, 여기서 AI agent 실행
    ├── frontend        // Git repo worktree
    └── backend         // Git repo worktree
```

`workbranch`는 mono-repo가 아니라 repo가 여러 개인 제품에서, agent가 필요한 모든 repo를 하나의 task 폴더에 모아줍니다. 서로 다른 clone이나 관련 없는 worktree를 오가는 것보다 AI agent session을 시작하고, 확인하고, 정리하기 훨씬 쉽습니다.

agent가 작업을 시작하기 전에 `workbranch refresh <task>` 한 번이면 task 안의 모든 repo가 최신 base로 맞춰집니다 — repo마다 따로 pull하거나 rebase할 필요가 없습니다.

multi-repo에서의 장점은 [AI agent workflow](docs/ai-agents.ko.md)를 참고하세요.

## 작업 흐름

이제 task workspace에서 작업하세요. task root(`<task>`)는 git으로 관리되지 않는 workbranch metadata/agent 작업 공간이고, 실제 Git repo는 `<task>/<repo>` 아래에 있습니다. Repo를 수정하기 전에는 해당 repo 안의 `AGENTS.md`, `CLAUDE.md`, `.claude/` 같은 repo-local agent 지침을 찾아 읽고 따르세요.

```bash
# macOS: IDE는 code repo를 열고, terminal은 task root를 엽니다
workbranch ide feat-login        # feat-login/<repo> worktree 열기
workbranch terminal feat-login   # feat-login task root 열기

# 또는 어디서나
cd feat-login/<repo>
# 코드 변경과 git 명령은 repo 안에서 실행
```

작업 중 최신 base가 필요하면 [최신화](#최신화)를, 작업이 끝나면 [두 가지 ship 방식](#두-가지-ship-방식)을 참고하세요.

## 최신화

특정 task만 최신 base로 맞추려면, `pull`로 base를 remote에서 당기고 `update <task>`로 task에 반영합니다.

```bash
workbranch pull               # 모든 base를 remote에서 pull
workbranch update feat-login  # local base를 task의 모든 repo에 반영

# combined: pull + update를 한 번에
workbranch refresh feat-login
```

동시에 여러 task에서 작업 중이라면, task 이름 없이 실행해 모든 task를 한 번에 최신화할 수 있습니다.

```bash
workbranch pull      # base 최신 update
workbranch update    # local base를 모든 task에 반영

# combined
workbranch refresh   # base를 pull한 뒤 모든 task update
```

base를 최신화하고 task에 반영한 뒤 land까지 한 번에 하려면 `finalize`를 씁니다.

```bash
workbranch finalize feat-login   # base pull → feat-login update → land
```

## 두 가지 ship 방식

`push`가 무엇을 올리는지는 base branch에 따라 달라집니다.

|                    | Feature flow                 | Stacked flow                                            |
| ------------------ | ---------------------------- | ------------------------------------------------------- |
| Base branch        | `main` / `master`            | feature branch (예: `feat/login`)                       |
| Task branch (폴더) | `feat/login` (`feat-login`)  | `feat/login-part1` (`feat-login-part1`)                 |
| 반영               | task branch를 push, PR 생성  | base에 land 후 base push                                |
| 명령               | `workbranch push feat-login` | `workbranch land feat-login-part1`<br>`workbranch push` |
| push 대상          | task branch                  | base branch                                             |

### Feature flow

```bash
# edit code in feat-login/<repo>

workbranch push feat-login # local feat/login -> origin/feat/login
```

### Stacked flow

```bash
# edit code in feat-login-part1/<repo>

workbranch land feat-login-part1 # feat/login-part1을 local base(feat/login)에 fast-forward 반영
workbranch push                  # local feat/login -> origin/feat/login
```

## 주요 명령어

| Command                    | 용도                                                    |
| -------------------------- | ------------------------------------------------------- |
| `workbranch init`          | config 기준으로 base worktree 생성 또는 clone           |
| `workbranch add [<task>]`  | task workspace 생성                                     |
| `workbranch list [--json]` | repo와 task workspace 목록 확인; `--json`은 machine-readable 출력 |
| `workbranch memo [task]`   | `TASK-WORKBRANCH.md` task brief 확인/작성/삭제          |
| `workbranch noti ...`       | task notification 추가/목록/삭제                        |
| `workbranch status`        | base remote diff, task diff, dirty state 확인           |
| `workbranch update [task]` | local base 기준으로 task의 모든 repo update (pull 없음) |
| `workbranch land <task>`   | task 작업을 local base branch로 fast-forward 반영       |
| `workbranch done <task>`   | 현재 Plan을 done 처리하고 archive로 이동                |
| `workbranch push [task]`   | base 또는 task branch push                              |
| `workbranch doctor [--fix]` | project health 진단; safe fix는 stale worktree prune과 brief H1 repair 포함 |

Combined flow shortcut:

| Command                      | 용도                                                       |
| ---------------------------- | ---------------------------------------------------------- |
| `workbranch refresh [task]`  | base branch를 pull한 뒤 task workspace update              |
| `workbranch finalize <task>` | base branch를 pull하고 하나의 task를 update한 뒤 land      |
| `workbranch prune`           | local base branch에 이미 merge된 clean task workspace 정리 |

![img](./docs/figs/workbranch-git-flow.png)

## Task brief & notifications

`workbranch add <task>`는 repo worktree 밖의 task root에 workbranch-managed state를 생성합니다.

- `<task>/TASK-WORKBRANCH.md`는 사람/AI agent가 함께 갱신하는 현재 Plan brief입니다. 생성 템플릿은 `# <plan>` H1을 Plan 이름으로 쓰고, 바로 아래 Plan-local `status: todo|planning|in-progress|review|blocked|done` 줄과 Markdown checklist Step을 둡니다. `plan:`과 `## Plan:`은 더 이상 지원 brief 형식이 아닙니다. `workbranch done <task>`는 현재 Plan을 done 처리한 뒤 `.workbranch/plans/done/<timestamp>-<slug>.md`로 이동하고 brief를 다음 Plan용으로 비웁니다. `land`/`finalize` 성공 후와 `pull` 뒤 안전하게 merged task를 감지했을 때도 확인 프롬프트 후 같은 archive 동작을 수행합니다. `workbranch memo <task> [text]`로 읽거나 덮어쓰고, `workbranch memo <task> --clear`로 삭제합니다. Task workspace 안에서는 읽기일 때만 `workbranch memo`처럼 `<task>`를 생략할 수 있습니다.
- `<task>/AGENTS.md`는 `<task>` 또는 `<task>/<repo>`에서 실행되는 AI agent가 같은 task brief를 갱신하도록 안내합니다. 갱신 시점은 시작/재개, active step 변경, 검증 전후, blocked, final response 직전입니다. 또한 repo 수정 전에 repo-local 지침을 읽도록 안내합니다.
- `<task>/.workbranch/notifications.jsonl`은 append-only local inbox입니다. `workbranch noti add/list/clear`가 관리하고, `workbranch list --json`은 companion app용 `notiCount`, `plans`, `planTitle`, `status`, `progressDone`, `progressTotal`, `currentItem`, `updatedAt`을 노출합니다.

`workbranch remove <task>`는 workspace 제거가 성공한 뒤 known workbranch task state(`TASK-WORKBRANCH.md`, generated `AGENTS.md`, `.workbranch/`, `.workbranch.task`)를 삭제합니다. 그 외 task root에 남은 항목은 `.omx/`, `.omc/` 같은 agent runtime folder를 포함해 git으로 관리되지 않는 잔여물입니다. Normal remove는 이 목록을 보여주고 task root 전체를 삭제할지 한 번 묻습니다. `workbranch remove <task> --force`는 일반 safety preflight 통과 후 묻지 않고 task root를 제거합니다.

`workbranch doctor`는 task brief format도 확인합니다. `status:` 또는 checklist item이 있는데 `# <plan>` H1이 없는 brief는 zero Plan으로 parse되어 CLI HUD와 companion app에서 보이지 않으므로 issue로 보고합니다. `workbranch doctor --fix`는 brief 본문을 rewrite하지 않고 맨 앞에 `# <task>` heading 한 줄만 추가할 수 있습니다. Backup은 만들지 않으며, 되돌리려면 삽입된 첫 줄을 삭제하면 됩니다. Checklist item이 계속 `##` note section 아래에 남아 있으면 intended Plan을 `# ` heading으로 승격하라는 manual follow-up을 보고하고, 그 조치가 끝날 때까지 non-zero로 종료합니다.

## Native menu bar companion

`apps/companion/`에는 Tauri v2 + React 기반 macOS menu bar app인 `WorkbranchCompanion.app`이 있습니다. 이 앱은 typed Tauri command 경계로 `workbranch list --global --json`을 호출하고, `packages/contract` Published Language를 통해 CLI JSON contract를 번역합니다. 범위는 기존 companion과 같은 presentation-first 운영 기능입니다: task status/progress, Plan/Step 표시, notification, memo edit, Finder/IDE/terminal launch, copy path, refresh/quit, local activity report. `add`, `done`, `land`, `push` 같은 task lifecycle/Git mutation은 계속 CLI 전용입니다.

Activity history는 `~/.local/state/workbranch/activity.jsonl`에 저장되고, 관련 repo/task workspace가 나중에 제거되어도 보존됩니다. Root 설정은 `~/.config/workbranch-companion/projects.md`에서 합니다.

Published release 설치:

```bash
brew tap tkhwang/tap
brew install --cask tkhwang/tap/workbranch-companion
```

Published companion release는 Developer ID 인증서로 서명되고 notarization을 거치므로, Gatekeeper quarantine 우회 flag가 필요하지 않습니다.

Local build:

```bash
pnpm install
pnpm --filter @workbranch/companion test
pnpm --filter @workbranch/companion tauri build
open "apps/companion/src-tauri/target/release/bundle/macos/WorkbranchCompanion.app"
```

## More docs

- [Task identity와 branch 이름](docs/task-identity.ko.md)
- [Usage details](docs/usage.ko.md)
- [AI agent workflow](docs/ai-agents.ko.md)
- [Architecture](docs/architecture.md)
- [Git operations](docs/git-operations.md)
- [MVP spec](docs/specs/0001-workbranch-mvp.md)
