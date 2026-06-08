# 사용 상세

[README](../README.ko.md) | [English](usage.md)

## Platform 지원

기본 workbranch 명령은 macOS, Linux, WSL에서 지원합니다. Tool app launcher는 macOS 전용입니다. 내장 app preset이 macOS `open`과 macOS app 이름을 사용하기 때문입니다.

공통 지원: Git/worktree 명령, `path`, `list`, `status`, `config`, `init`, generated CLI 검증.

macOS 전용: `finder`, `ide`, `terminal`, `config ide`, `config terminal`. Linux/WSL에서 전체 `workbranch config`와 `workbranch init`은 계속 사용할 수 있으며 tool app prompt를 건너뜁니다.

## 주요 명령어

### Workspace lifecycle

| Command                                  | 용도                                                               |
| ---------------------------------------- | ------------------------------------------------------------------ |
| `workbranch init`                        | config 기준으로 base worktree 생성 또는 clone                      |
| `workbranch config`                      | project 설정, base branch, tool command, repo setup command 수정   |
| `workbranch config base`                 | base branch 설정만 수정하고 base worktree checkout                 |
| `workbranch config ide`                  | IDE 명령만 수정                                                    |
| `workbranch config terminal`             | terminal 명령만 수정                                               |
| `workbranch add [<task>] [--from <ref>]` | task workspace 생성                                                |
| `workbranch list`                        | repo와 task workspace 목록 확인                                    |
| `workbranch remove <task>`               | task worktree와 local task branch 제거                             |
| `workbranch doctor [--fix]`              | project health 진단; `--fix`는 stale worktree registration만 prune |

### Branch workflow

| Command                    | 용도                                              |
| -------------------------- | ------------------------------------------------- |
| `workbranch status`        | base remote diff, task diff, dirty state 확인     |
| `workbranch pull`          | remote base branch를 `_base/<repo>`로 pull        |
| `workbranch update [task]` | local base 변경사항을 task worktree에 rebase (`git rebase <_base/repo HEAD>`) |
| `workbranch push`          | base branch push                                  |
| `workbranch push <task>`   | task branch push                                  |
| `workbranch land <task>`   | task 작업을 local base branch로 fast-forward 반영 |

### Combined flow

| Command                      | 용도                                                                      |
| ---------------------------- | ------------------------------------------------------------------------- |
| `workbranch refresh`         | base branch를 pull한 뒤 모든 task workspace update                        |
| `workbranch refresh <task>`  | base branch를 pull한 뒤 하나의 task workspace update                      |
| `workbranch finalize <task>` | base branch를 pull하고 하나의 task를 update한 뒤 local base branch로 반영 |
| `workbranch prune`           | local base branch에 이미 merge된 clean task workspace 정리                |

### Tool commands

| Command                      | 용도                                      |
| ---------------------------- | ----------------------------------------- |
| `workbranch path <task>`     | task workspace 또는 repo 경로 출력        |
| `workbranch finder <task>`   | Finder로 task workspace folder 열기       |
| `workbranch ide <task>`      | 설정된 IDE로 task repo worktree 열기      |
| `workbranch terminal <task>` | 설정된 terminal로 task repo worktree 열기 |

### Other

| Command         | 용도                |
| --------------- | ------------------- |
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

## Project health

`workbranch doctor`는 base worktree drift, partial task workspace, stale task directory, stale Git worktree registration을 진단합니다. 기본 동작은 read-only이고 issue가 있으면 non-zero로 종료하므로 local check나 CI에서 사용할 수 있습니다.

안전한 자동 복구만 원하면 `workbranch doctor --fix`를 사용하세요. 이 명령은 in-scope base repo에 대해 `git worktree prune`만 실행하며 task directory나 branch는 삭제하지 않습니다. 삭제가 필요한 정리는 출력되는 `workbranch remove <task>` 또는 `workbranch remove <task> --force` 안내를 사용자가 직접 실행해야 합니다. `--repo <repo>`를 붙이면 특정 repo만 진단하고 prune합니다.

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

config format과 setup 환경변수는 [MVP spec](specs/0001-workbranch-mvp.md)을 참고하세요.

## Safety

`workbranch`는 worktree를 변경하기 전에 dirty worktree, 잘못된 branch, rebase 상태, 누락된 repo, fast-forward가 아닌 Git 경로를 확인합니다.
