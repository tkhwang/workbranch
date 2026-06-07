# workbranch

**한국어** | [English](README.md)

`git worktree` 명령을 매번 기억하지 않아도 task 단위 worktree를 관리할 수 있습니다.

`workbranch`는 feature마다 하나의 task 폴더를 만들고, single repo와 multi-repo 프로젝트 모두에서 짧고 안전한 branch sync 명령을 제공합니다.

핵심 흐름은 task workspace를 만들고 제거하는 **Workspace lifecycle**과 task branch를 update, land, push하는 **Branch workflow** 두 가지입니다.

![img](./docs/figs/workbranch-git-flow.png)

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

## Quick start

```bash
workbranch init
workbranch add
cd feat-login/<repo>
# task 작업
workbranch update feat-login
workbranch push feat-login
workbranch remove feat-login
```

## Task identity와 branch 이름

새 task 생성은 두 값을 묻습니다.

| Prompt | 예시 | 사용처 |
| --- | --- | --- |
| Task type | `feat` | Git branch prefix |
| Task detail name | `login` | folder/branch detail |

`workbranch`는 다음 값을 파생합니다.

- task folder: `feat-login`
- repo별 default Git branch:
  - base `main` 또는 `master` -> `feat/login`
  - base `feature/cpq` -> `feature/cpq-login`

Folder 이름과 branch 이름은 분리됩니다. folder는 path-safe해야 하고 Git branch는 보통 `/`를 사용하기 때문입니다. `workbranch`는 folder-safe type/detail separator로 `-`를 사용하므로 `feat-login`은 `feat/login`의 task-folder 형태입니다. Repo별 task branch prompt에서 기본값은 여전히 overwrite할 수 있습니다.

Interactive `workbranch add <detail>`도 같은 생성 flow로 들어가며, `<detail>`을 Task detail name의 기본값으로 사용합니다. 예를 들어 `workbranch add login`은 Task type을 묻고 `login`을 수정 가능한 detail 기본값으로 보여주며 folder `feat-login`을 추천합니다. 이후 각 repo가 configured base branch 기준으로 task branch를 제안합니다. `workbranch add feat-login`은 conventional task key의 direct shorthand로 계속 동작합니다. Non-interactive script에서는 conventional `type-` prefix가 없는 task key도 계속 넘길 수 있고, 이 legacy explicit key는 compatibility를 위해 branch-prefix default를 유지합니다.

기본적으로 `workbranch add`는 local `_base/<repo>` worktree의 현재 HEAD에서 task branch를 만듭니다. remote base branch를 자동으로 pull하지 않습니다. 최신 remote base에서 시작하려면 다음 순서로 실행하세요.

```bash
workbranch pull
workbranch add
```

다른 source ref에서 새 task branch를 시작하려면 `workbranch add [<task>] --from <ref>`를 사용하세요. 예를 들어 `workbranch add task1 --from feat/XXX`는 origin을 fetch한 뒤 `origin/feat/XXX`가 있으면 그것을 우선 사용하고, prompt로 정한 task branch 이름은 그대로 유지한 채 linked task worktree를 만듭니다. 이후 `workbranch status`는 여전히 task branch를 현재 local base와 비교하며, source ref는 생성 시점 정보일 뿐 지속적인 status 기준이 아닙니다.

repo를 다시 clone하지 않고 project 설정, base branch, IDE/terminal 실행 명령, repo별 setup command를 수정하려면 `workbranch config`를 사용합니다.

## 생성되는 구조

각 task마다 하나의 공유 task 디렉토리 아래에 linked worktree가 만들어집니다.

```text
my-app-workspace
├── .workbranch.config
├── _base
│   ├── frontend
│   └── backend
└── login
    ├── frontend
    └── backend
```

Single-repo 프로젝트도 같은 구조를 사용하며, 각 task 안에 repo 디렉토리가 하나만 들어갑니다.

## Platform 지원

기본 workbranch 명령은 macOS, Linux, WSL에서 지원합니다. Tool app launcher는 macOS 전용입니다. 내장 app preset이 macOS `open`과 macOS app 이름을 사용하기 때문입니다.

공통 지원: Git/worktree 명령, `path`, `list`, `status`, `config`, `init`, generated CLI 검증.

macOS 전용: `finder`, `ide`, `terminal`, `config ide`, `config terminal`. Linux/WSL에서 전체 `workbranch config`와 `workbranch init`은 계속 사용할 수 있으며 tool app prompt를 건너뜁니다.

## 주요 명령어

### Workspace lifecycle

| Command | 용도 |
| --- | --- |
| `workbranch init` | config 기준으로 base worktree 생성 또는 clone |
| `workbranch config` | project 설정, base branch, tool command, repo setup command 수정 |
| `workbranch config ide` | IDE 명령만 수정 |
| `workbranch config terminal` | terminal 명령만 수정 |
| `workbranch add [<task>] [--from <ref>]` | task workspace 생성 |
| `workbranch list` | repo와 task workspace 목록 확인 |
| `workbranch remove <task>` | task worktree와 local task branch 제거 |

### Branch workflow

| Command | 용도 |
| --- | --- |
| `workbranch status` | base remote diff, task diff, dirty state 확인 |
| `workbranch pull` | remote base branch를 `_base/<repo>`로 pull |
| `workbranch update [task]` | local base 변경사항을 task worktree에 merge |
| `workbranch push` | base branch push |
| `workbranch push <task>` | task branch push |
| `workbranch land <task>` | task 작업을 local base branch로 fast-forward 반영 |

### Tool commands

| Command | 용도 |
| --- | --- |
| `workbranch path <task>` | task workspace 또는 repo 경로 출력 |
| `workbranch finder <task>` | Finder로 task workspace folder 열기 |
| `workbranch ide <task>` | 설정된 IDE로 task repo worktree 열기 |
| `workbranch terminal <task>` | 설정된 terminal로 task repo worktree 열기 |

### Other

| Command | 용도 |
| --- | --- |
| `workbranch -v` | 설치된 version 확인 |

지원되는 Branch workflow 및 Tool 명령에 `--repo <repo>`를 붙이면 특정 repo 하나만 대상으로 실행합니다.

## CLI 표시

대화형 터미널에서는 `workbranch`가 색상, help/init 화면의 compact banner, section title을 사용해 출력이 더 잘 보이도록 합니다. 캡처되거나 pipe된 출력은 기본적으로 plain text를 유지하므로 script와 test에 ANSI escape sequence가 들어가지 않습니다.

색상 제어:

```bash
NO_COLOR=1 workbranch help              # 항상 plain
WORKBRANCH_COLOR=never workbranch help  # 항상 plain
WORKBRANCH_COLOR=always workbranch help # enhanced display 강제
```

`workbranch path <task>`와 `workbranch path <task> --repo <repo>`는 scripting을 위해 계속 plain path만 stdout에 출력합니다.

## Shell completion

`workbranch completion <shell>`로 shell completion script를 생성합니다. 이 script는 shell을 통해 command, task key, repo, option completion을 제공합니다. 후보 표시 색상이나 흐린 preview 스타일은 shell, completion framework, terminal theme이 담당합니다.

```bash
# bash
workbranch completion bash > ~/.local/share/bash-completion/completions/workbranch

# zsh: fpath에 포함된 directory에 저장
workbranch completion zsh > "${fpath[1]}/_workbranch"

# fish
workbranch completion fish > ~/.config/fish/completions/workbranch.fish
```

## 작업 workspace 열기

프로젝트에서 공통으로 사용할 IDE와 terminal 명령을 설정합니다.

```bash
workbranch config ide
workbranch config terminal
```

작업 workspace 안의 모든 repo를 엽니다.

```bash
workbranch finder login
workbranch ide login
workbranch terminal login
```

내장 macOS IDE preset은 VS Code 계열 app에서 repo path마다 별도 IDE window를 엽니다. config directive는 `IDE <command>`입니다. preset 순서는 Cursor, Antigravity, Windsurf, Zed, Sublime Text, Xcode, VS Code입니다. `IDE open -a Cursor`, `IDE open -a "Antigravity IDE"`, `IDE open -a "Visual Studio Code"`, `IDE open -a Windsurf` 형태는 실행 시 `open -na ... --args --new-window`로 보정됩니다. Zed는 검증 전까지 `open -na Zed`로 유지합니다.

필요하면 repo 하나로 제한합니다.

```bash
workbranch ide login --repo frontend
workbranch terminal login --repo backend
```

스크립트에서 사용할 전체 경로를 출력합니다.

```bash
workbranch path login
workbranch path login --repo frontend
```

Launcher 명령은 repo별로 순서대로 실행됩니다. foreground에 계속 머무는 TUI terminal 명령은 `--repo`를 쓰거나 non-blocking custom wrapper로 설정하세요.

## Setup command

`workbranch config`는 repo별 setup command를 저장할 수 있습니다. `workbranch add <task>`를 실행하면 각 setup command가 `<task>/<repo>` 안에서 실행됩니다.

config format과 setup 환경변수는 [MVP spec](docs/specs/0001-workbranch-mvp.md)을 참고하세요.

## Safety

`workbranch`는 worktree를 변경하기 전에 dirty worktree, 잘못된 branch, rebase 상태, 누락된 repo, fast-forward가 아닌 Git 경로를 확인합니다.

## More docs

- [Architecture](docs/architecture.md)
- [Git operations](docs/git-operations.md)
- [MVP spec](docs/specs/0001-workbranch-mvp.md)
