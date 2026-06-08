# workbranch

**한국어** | [English](README.md)

`git worktree` 명령을 매번 기억하지 않아도 task 단위 worktree를 관리할 수 있습니다.

`workbranch`는 feature마다 하나의 task 폴더를 만들고, single repo와 multi-repo 프로젝트 모두에서 짧고 안전한 branch refresh 명령을 제공합니다.

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

`workbranch init`은 base repo를 clone하고, setup 중 첫 task를 만들지 물어봅니다.

```bash
workbranch init
# 첫 task 추가 선택: login

# feat-login/<repo>에서 작업

workbranch refresh feat-login
workbranch land feat-login
workbranch push
```

## 생성되는 구조

각 task마다 하나의 공유 task 디렉토리 아래에 linked worktree가 만들어집니다.

```text
my-app-workspace
├── .workbranch.config
├── _base
│   ├── frontend
│   └── backend
└── feat-login
    ├── frontend
    └── backend
```

Single-repo 프로젝트도 같은 구조를 사용하며, 각 task 안에 repo 디렉토리가 하나만 들어갑니다.

## 주요 명령어

| Command | 용도 |
| ------- | ---- |
| `workbranch init` | config 기준으로 base worktree 생성 또는 clone |
| `workbranch add [<task>]` | task workspace 생성 |
| `workbranch list` | repo와 task workspace 목록 확인 |
| `workbranch status` | base remote diff, task diff, dirty state 확인 |
| `workbranch land <task>` | task 작업을 local base branch로 fast-forward 반영 |
| `workbranch push [task]` | base 또는 task branch push |
| `workbranch path <task>` | task workspace 또는 repo 경로 출력 |

Combined flow shortcut:

| Command | 용도 |
| ------- | ---- |
| `workbranch refresh [task]` | base branch를 pull한 뒤 task workspace update |
| `workbranch finalize <task>` | base branch를 pull하고 하나의 task를 update한 뒤 land |
| `workbranch prune` | local base branch에 이미 merge된 clean task workspace 정리 |

## Multi-repo AI agent workflow

multi-repo 제품에서는 agent가 필요한 모든 repo를 하나의 task workspace 안에 모아둘 수 있습니다. 서로 다른 clone이나 관련 없는 worktree를 오가게 하는 것보다 AI agent session을 시작하고, 확인하고, 정리하기 쉽습니다.

multi-repo에서의 장점은 [AI agent workflow](docs/ai-agents.ko.md)를 참고하세요.

## More docs

- [Task identity와 branch 이름](docs/task-identity.ko.md)
- [Usage details](docs/usage.ko.md)
- [AI agent workflow](docs/ai-agents.ko.md)
- [Architecture](docs/architecture.md)
- [Git operations](docs/git-operations.md)
- [MVP spec](docs/specs/0001-workbranch-mvp.md)
