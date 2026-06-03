# workbranch

**한국어** | [English](README.md)

Git worktree workspace와 branch 작업을 단순하게 관리합니다.



## TL;DR

* Git worktree를 쓰고 싶지만, `git worktree` 명령어를 매번 기억하기 어렵다.
* 여러 feature worktree를 동시에 열어두면, base branch 변경사항을 각 workspace에 반영하는 일이 번거롭다.
* frontend와 backend가 서로 다른 repo에 있으면, AI 도구에 하나의 task context를 주기 어렵다.

#### Workbranch solution



`workbranch`는 Git worktree를 쓰고 싶지만 task workspace 생성, branch 동기화, multi-repo context 구성을 매번 직접 관리하고 싶지 않은 개발자를 위한 도구입니다.

* `workbranch init`을 한 번 실행한 뒤, `workbranch add`와 `workbranch remove`로 task workspace를 관리한다.
* `workbranch update`로 base branch 변경사항을 하나의 task workspace 또는 전체 task workspace에 반영한다.
* PR 리뷰가 필요하면 task branch를 push하고, feature 작업을 local base worktree로 가져오고 싶을 때는 `workbranch land`를 사용한다.
* frontend, backend, 기타 repo를 하나의 task 디렉토리 아래에 배치해서 AI 도구가 같은 context에서 작업하게 한다.

![img](./docs/figs/workbranch-git-flow.png)

`workbranch`의 핵심 기능은 두 가지입니다.

1. Task workspaces: task 단위의 Git worktree 폴더를 생성하고 제거한다.
2. Branch sync: base worktree와 task worktree 사이의 변경사항을 주고받는다.

## 1. Task workspaces

`workbranch`는 linked worktree를 task/feature 단위로 구성합니다. `login`, `payment` 같은 task마다 하나의 폴더가 생기고, 설정된 각 repo의 linked worktree가 그 폴더 안에 만들어집니다.

```text
workbranch init              .workbranch.config를 기준으로 main worktree clone
workbranch config            base branch와 repo별 setup command 수정
workbranch add <task>        task용 linked worktree 생성
workbranch remove <task>     task worktree 제거
```

Single repo의 경우:

`workbranch`는 single repo에서도 `<task>/<repo>` 구조를 사용합니다. repo 디렉토리를 한 단계 더 두면 multi-repo project와 같은 layout을 유지할 수 있고, single-repo 사용자는 보통 `<task>/<repo>`에서 작업합니다.

```text
my-app-workspace
├── .workbranch.config
├── _base                   // base worktree
│   └── my-app                 - repo: base
├── login                   // feature worktree              <-- AI agent
│   └── my-app                 - repo: login task
└── payment                 // feature worktree              <-- AI agent
    └── my-app                 - repo: payment task
```

![img](./docs/figs/workbranch-multi-repo.png)

Multi-repo의 경우:
Multi-repo 작업에서는 feature 폴더 하나가 해당 task에 속한 모든 repo의 shared workspace/session context가 됩니다.

```text
my-app-workspace
├── .workbranch.config
├── _base                   // base worktree
│   ├── frontend               - frontend repo: base
│   └── backend                - backend repo: base
├── login                   // feature worktree              <-- AI agent
│   ├── frontend               - frontend repo: login task
│   └── backend                - backend repo: login task
└── payment                 // feature worktree              <-- AI agent
    ├── frontend               - frontend repo: payment task
    └── backend                - backend repo: payment task
```

## 2. Branch sync

![img](./docs/figs/workbranch_feature_diagram.png)

`workbranch`는 Git branch 동기화 방향을 두 가지로 나눠서 관리합니다.

- vertical: remote base branch `<->` local base worktree
- horizontal: local base worktree `<->` feature worktree들

```text
remote:     origin/<base>                          origin/<task2>
                 ^                                      ^
                 | push                                 | push task2
                 |                                      |
                 | pull                                 |
                 v                                      |

local:      _base/<repo>      task1/<repo>      task2/<repo>      task3/<repo>
            base worktree     feature worktree  feature worktree  feature worktree
                 ^                  |                |                |
          land   |<----------------------------------|                |
                 |
                 |----------------->|                |                |
          update |---------------------------------->|                |
                 |--------------------------------------------------->|
```

일반적인 흐름:

```text
workbranch init or config
workbranch add <task>
workbranch update <task>      # base 변경사항을 task workspace에 반영
workbranch push <task>        # PR 리뷰를 위해 task branch push
workbranch land <task>        # 선택: task 작업을 local base로 반영
workbranch remove <task>
```

명령어:

```text
vertical
  workbranch pull             origin/<base> -> _base/<repo>
  workbranch push             _base/<repo>  -> origin/<base>

  workbranch push <feature>   feature branch -> origin/<feature-branch>
  workbranch push task1       task1의 모든 repo branch push
  workbranch push task1 --repo frontend
                              task1의 frontend branch만 push

horizontal
  workbranch update           _base/<repo>  -> 모든 feature worktree
  workbranch update <feature> _base/<repo>  -> 하나의 feature worktree
  workbranch land <feature>   feature       -> _base/<repo>
```

#### Safety

`workbranch`는 worktree를 변경하기 전에 흔한 unsafe state를 확인합니다.

- dirty worktree
- 현재 branch가 설정된 branch와 다른 상태
- rebase 진행 중
- 누락된 repo 또는 task worktree
- fast-forward가 아닌 pull, push, land 경로

## Per-repo setup

`workbranch config`를 사용하면 각 repo의 base branch와 setup command를 한 번에 수정할 수 있습니다.

```bash
workbranch config
workbranch add login
```

각 repo prompt에서 Enter를 누르면 현재 값을 유지합니다. setup prompt에서 `--clear`를 입력하면 해당 repo의 setup command를 제거합니다. repo가 이미 clone된 뒤 base branch를 변경하면, `workbranch config`는 기존 `_base/<repo>` worktree에서 실행해야 할 checkout command를 출력합니다.

Repo setup command는 `<task>/<repo>`에서 실행되며 아래 환경변수를 받습니다.

```text
WORKBRANCH_PROJECT_ROOT
WORKBRANCH_TASK
WORKBRANCH_TASK_DIR
WORKBRANCH_BASE_DIR
WORKBRANCH_REPOS
WORKBRANCH_REPO
WORKBRANCH_REPO_DIR
WORKBRANCH_BASE_REPO_DIR
```

## Install

### Homebrew

Homebrew tap에서 최신 versioned release를 설치합니다.

```bash
brew install tkhwang/tap/workbranch
```

Formula는 tagged source archive에서 generated `bin/workbranch`를 build한 뒤 설치합니다.

### curl installer

최신 `main` build를 바로 설치합니다.

```bash
curl -fsSL https://raw.githubusercontent.com/tkhwang/workbranch/main/install.sh | bash
```

curl installer는 `main`을 따라가고, Homebrew는 published GitHub Releases를 따라갑니다.
