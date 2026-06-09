# workbranch

**한국어** | [English](README.md)

[![CI](https://github.com/tkhwang/workbranch/actions/workflows/ci.yml/badge.svg)](https://github.com/tkhwang/workbranch/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/tkhwang/workbranch?sort=semver)](https://github.com/tkhwang/workbranch/releases)
[![License: MIT](https://img.shields.io/github/license/tkhwang/workbranch)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-informational)

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

repo 하나로 시작하세요. `workbranch init`이 설정을 안내하고, 첫 task까지 바로 만들어 줍니다.

```bash
workbranch init
# 프로젝트 이름 입력 후 repo 하나 등록 (이름 + Git URL + base branch)
# "Add another repo?"    -> N       # 시작은 repo 하나면 충분합니다
# "Add your first task?" -> login   # feat-login workspace 생성
```

이제 task workspace에서 작업하고 반영하세요.

```bash
# feat-login/<repo>에서 코드 작업

workbranch refresh feat-login   # base branch를 pull한 뒤 task update
workbranch land feat-login      # task 작업을 base branch로 fast-forward 반영
workbranch push                 # base branch push
```

repo가 여러 개인 제품인가요? `workbranch`는 그 repo들을 하나의 task 폴더에 모아줍니다 — [생성되는 구조](#생성되는-구조) 참고.

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

| Command                   | 용도                                              |
| ------------------------- | ------------------------------------------------- |
| `workbranch init`         | config 기준으로 base worktree 생성 또는 clone     |
| `workbranch add [<task>]` | task workspace 생성                               |
| `workbranch list`         | repo와 task workspace 목록 확인                   |
| `workbranch status`       | base remote diff, task diff, dirty state 확인     |
| `workbranch land <task>`  | task 작업을 local base branch로 fast-forward 반영 |
| `workbranch push [task]`  | base 또는 task branch push                        |
| `workbranch path <task>`  | task workspace 또는 repo 경로 출력                |

Combined flow shortcut:

| Command                      | 용도                                                       |
| ---------------------------- | ---------------------------------------------------------- |
| `workbranch refresh [task]`  | base branch를 pull한 뒤 task workspace update              |
| `workbranch finalize <task>` | base branch를 pull하고 하나의 task를 update한 뒤 land      |
| `workbranch prune`           | local base branch에 이미 merge된 clean task workspace 정리 |

## Multi-repo AI agent workflow

```
└── feat-login      // run AI agent here!!!
    ├── frontend
    └── backend
```

multi-repo 제품에서는 agent가 필요한 모든 repo를 하나의 task workspace 안에 모아둘 수 있습니다. 서로 다른 clone이나 관련 없는 worktree를 오가게 하는 것보다 AI agent session을 시작하고, 확인하고, 정리하기 쉽습니다.

multi-repo에서의 장점은 [AI agent workflow](docs/ai-agents.ko.md)를 참고하세요.

## More docs

- [Task identity와 branch 이름](docs/task-identity.ko.md)
- [Usage details](docs/usage.ko.md)
- [AI agent workflow](docs/ai-agents.ko.md)
- [Architecture](docs/architecture.md)
- [Git operations](docs/git-operations.md)
- [MVP spec](docs/specs/0001-workbranch-mvp.md)
