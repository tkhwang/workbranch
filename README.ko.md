# workbranch

**한국어** | [English](README.md)

`git worktree` 명령을 매번 기억하지 않아도 task 단위 worktree를 관리할 수 있습니다.

`workbranch`는 feature마다 하나의 task 폴더를 만들고, single repo와 multi-repo 프로젝트 모두에서 짧고 안전한 branch sync 명령을 제공합니다.

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

repo를 다시 clone하지 않고 project 설정, branch prefix, base branch, repo별 setup command를 수정하려면 `workbranch config`를 사용합니다.

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

| Command | 용도 |
| --- | --- |
| `workbranch init` | config 기준으로 base worktree 생성 또는 clone |
| `workbranch config` | project 설정, branch prefix, base branch, repo setup command 수정 |
| `workbranch add <task>` | task workspace 생성 |
| `workbranch resume <task>` | 기존 local 또는 remote task branch 복구 |
| `workbranch list` | repo와 task workspace 목록 확인 |
| `workbranch status` | branch, diff, dirty state 확인 |
| `workbranch update [task]` | local base 변경사항을 task worktree에 merge |
| `workbranch pull` | remote base branch를 `_base/<repo>`로 pull |
| `workbranch push [task]` | base branch 또는 task branch push |
| `workbranch land <task>` | task 작업을 local base branch로 fast-forward 반영 |
| `workbranch remove <task>` | task worktree와 local task branch 제거 |
| `workbranch -v` | 설치된 version 확인 |

지원되는 Git 명령에 `--repo <repo>`를 붙이면 특정 repo 하나만 대상으로 실행합니다.

## Setup command

`workbranch config`는 repo별 setup command를 저장할 수 있습니다. `workbranch add <task>`를 실행하면 각 setup command가 `<task>/<repo>` 안에서 실행됩니다.

config format과 setup 환경변수는 [MVP spec](docs/specs/0001-workbranch-mvp.md)을 참고하세요.

## Safety

`workbranch`는 worktree를 변경하기 전에 dirty worktree, 잘못된 branch, rebase 상태, 누락된 repo, fast-forward가 아닌 Git 경로를 확인합니다.

## More docs

- [Architecture](docs/architecture.md)
- [Git operations](docs/git-operations.md)
- [MVP spec](docs/specs/0001-workbranch-mvp.md)
