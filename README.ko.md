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
workbranch add login
cd login/<repo>
# task 작업
workbranch update login
workbranch push login
workbranch remove login
```

`workbranch add <task>`는 local `_base/<repo>` worktree의 현재 HEAD에서 task branch를 만듭니다. remote base branch를 자동으로 pull하지 않습니다. 최신 remote base에서 시작하려면 다음 순서로 실행하세요.

```bash
workbranch pull
workbranch add <task>
```

repo를 다시 clone하지 않고 project 설정, branch prefix, base branch, editor/terminal 실행 명령, repo별 setup command를 수정하려면 `workbranch config`를 사용합니다.

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

## 주요 명령어

### Workspace lifecycle

| Command | 용도 |
| --- | --- |
| `workbranch init` | config 기준으로 base worktree 생성 또는 clone |
| `workbranch config` | project 설정, base branch, tool command, repo setup command 수정 |
| `workbranch config editor` | editor 명령만 수정 |
| `workbranch config terminal` | terminal 명령만 수정 |
| `workbranch add <task>` | task workspace 생성 |
| `workbranch list` | repo와 task workspace 목록 확인 |
| `workbranch remove <task>` | task worktree와 local task branch 제거 |

### Branch workflow

| Command | 용도 |
| --- | --- |
| `workbranch status` | branch, diff, dirty state 확인 |
| `workbranch pull` | remote base branch를 `_base/<repo>`로 pull |
| `workbranch update [task]` | local base 변경사항을 task worktree에 merge |
| `workbranch push` | base branch push |
| `workbranch push <task>` | task branch push |
| `workbranch land <task>` | task 작업을 local base branch로 fast-forward 반영 |

### Tool commands

| Command | 용도 |
| --- | --- |
| `workbranch path <task>` | task workspace 또는 repo 경로 출력 |
| `workbranch editor <task>` | 설정된 editor로 task repo worktree 열기 |
| `workbranch terminal <task>` | 설정된 terminal로 task repo worktree 열기 |

### Other

| Command | 용도 |
| --- | --- |
| `workbranch -v` | 설치된 version 확인 |

지원되는 Branch workflow 및 Tool 명령에 `--repo <repo>`를 붙이면 특정 repo 하나만 대상으로 실행합니다.

## 작업 workspace 열기

프로젝트에서 공통으로 사용할 editor와 terminal 명령을 설정합니다.

```bash
workbranch config editor
workbranch config terminal
```

작업 workspace 안의 모든 repo를 엽니다.

```bash
workbranch editor login
workbranch terminal login
```

필요하면 repo 하나로 제한합니다.

```bash
workbranch editor login --repo frontend
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
