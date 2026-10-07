# 사용 상세

[README](../README.ko.md) | [English](usage.md)

## Platform 지원

기본 workbranch 명령은 macOS, Linux, WSL에서 지원합니다. Tool app launcher는 macOS 전용입니다. 내장 app preset이 macOS `open`과 macOS app 이름을 사용하기 때문입니다.

공통 지원: Git/worktree 명령, `path`, `list`, `memo`, `noti`, `status`, `config`, `init`, generated CLI 검증.

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
| `workbranch config language`             | generated task guidance 선호 언어 수정                             |
| `workbranch add [<task>] [--from <ref>]` | task workspace 생성                                                |
| `workbranch list [--json]`               | repo와 task workspace 목록 확인; `--json`은 companion용 contract 출력 |
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
| `workbranch stash [-m <msg>]` | 현재 worktree 변경사항을 그 branch 이름으로 보관 |
| `workbranch stash pop`     | 현재 branch에 보관한 변경사항 복원                |

`git stash` 목록은 repo의 모든 worktree가 함께 쓰므로, 인자 없는 `git stash pop`은 다른 worktree가 넣은 항목을 꺼낼 수 있습니다. `workbranch stash`는 현재 worktree에서 실행되며 tracked, staged, untracked 변경을 공유 stash 목록이 아니라 `refs/workbranch/stash/<branch>`에 저장합니다. `pop`과 `apply`는 `--branch <branch>`를 주지 않는 한 현재 branch의 항목만 복원합니다. `list`, `show [-p]`, `drop`으로 확인하거나 버릴 수 있습니다. branch마다 한 번에 하나만 보관합니다.

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
| `workbranch terminal <task>` | 설정된 terminal로 task root 열기          |

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

## Agent runtime과 migration

`workbranch add`는 작업 공간 지침과 metadata를 만들며 task brief는 생성하지 않습니다. agent가 상태를 직접 기록할 필요가 없습니다. Rust 수집기는 hook 관측값을 `~/.workbranch/runtime/state.sqlite3`에 저장하며 별도 DB 서버·Node·sqlite3 설치가 필요 없습니다. `workbranch runtime --json`은 Git 조회 없이 최신 session을 읽습니다. `list --json`은 schema 2이며 CLI와 Companion을 함께 업데이트합니다.

`workbranch hooks install --provider claude` 또는 `--provider codex` / `--provider grok`로 설치합니다. provider의 hook trust를 확인하고 agent session을 다시 시작하세요. `hooks status`는 provider manager 상태를 보여주며 첫 이벤트 수신으로 실제 수집을 확인합니다. `hooks uninstall`은 선택한 plugin만 제거합니다.

`workbranch migrate agent-runtime --dry-run --global`로 구 자료/지침 대상을 확인하고 `--apply --global`로 정리합니다. Companion도 같은 migration을 감지하고 전환 선택 시 CLI를 실행합니다. `memo`, `done`, Plan 보관 질문은 제거되었습니다. 일반 저장소 Plan 문서는 독립적으로 유지합니다. 구 brief 내용을 현재 runtime 상태로 변환하지 않습니다.

알림은 기존 `<task>/.workbranch/notifications.jsonl`과 `noti add|list|clear`, `notiCount` 계약을 유지합니다.

`workbranch remove <task>`는 task worktree, local task branch, known generated task-root state(`TASK-WORKBRANCH.md`, generated `AGENTS.md`, `.workbranch/`, `.workbranch.task`)를 제거합니다. 그 밖에 task root에 남은 항목은 `.omx/`, `.omc/`를 포함해 git으로 관리되지 않는 잔여물입니다. Normal remove는 남은 항목 이름을 출력하고, interactive shell에서는 task root 전체를 삭제할지 한 번 묻습니다. No/EOF는 task root를 보존합니다. `workbranch remove <task> --force`는 일반 safety preflight를 그대로 실행한 뒤 묻지 않고 task root를 삭제합니다.

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

프로젝트에서 공통으로 사용할 IDE/terminal 명령과 generated task guidance 언어를 설정합니다.

```bash
workbranch config ide
workbranch config terminal
workbranch config language
```

Task surface를 엽니다.

```bash
workbranch finder login      # Finder로 task root 열기
workbranch ide login         # IDE로 repo worktree 열기
workbranch terminal login    # terminal로 task root 열기
```

내장 macOS IDE preset은 VS Code 계열 app에서 repo path마다 별도 IDE window를 엽니다. config directive는 `IDE <command>`입니다. preset 순서는 Cursor, Antigravity, Windsurf, Zed, Sublime Text, Xcode, VS Code입니다. VS Code 계열 preset(Cursor, Antigravity, Windsurf, VS Code)은 `workbranch ide` 실행 시 설치된 app 안의 CLI(`<App>.app/Contents/Resources/app/bin/<cli>`, `/Applications` 다음 `~/Applications` 순으로 탐색)를 `<cli> --new-window <repo-path>`로 실행합니다. 해당 IDE가 이미 실행 중이면 CLI가 띄운 임시 helper 인스턴스가 종료된 뒤 `open -a <App>.app`으로 앱을 앞으로 가져옵니다. 그 helper가 종료되면서 macOS 포커스가 호출한 쪽으로 돌아가고, 이미 IDE의 key window인 repo 창만 focus해서는 앱이 앞으로 나오지 않기 때문입니다. 이미 열린 repo는 기존 window가 focus되면서 IDE가 앞으로 나오고, 열리지 않은 repo는 새 window로 열리며, IDE가 실행 중이 아니면 새로 시작합니다. 이 경로는 번들 CLI가 끝나기를 기다린 뒤 활성화까지 확인하므로 `workbranch ide`가 repo당 약 3~4초 뒤에 반환됩니다. repo 창 자체는 약 1초 안에 나타납니다. 번들 CLI를 찾지 못하거나 실행 권한이 없으면 설정된 `open -na ... --args --new-window` 명령을 그대로 실행합니다. `IDE open -a Cursor`, `IDE open -a "Antigravity IDE"`, `IDE open -a "Visual Studio Code"`, `IDE open -a Windsurf` 형태도 같은 방식으로 보정됩니다. Zed는 검증 전까지 `open -na Zed`로 유지합니다.

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

`workbranch ide <task>`는 repo별로 실행됩니다. `workbranch terminal <task>`는 agent가 `AGENTS.md`, 모든 repo를 볼 수 있도록 task root를 한 번 엽니다. 의도적으로 repo 하나만 열 때는 `--repo`를 사용하세요.

## Setup command

`workbranch config`는 repo별 setup command를 저장할 수 있습니다. `workbranch add <task>`를 실행하면 각 setup command가 `<task>/<repo>` 안에서 실행됩니다.

config format과 setup 환경변수는 [MVP spec](specs/0001-workbranch-mvp.md)을 참고하세요.

## Safety

`workbranch`는 worktree를 변경하기 전에 dirty worktree, 잘못된 branch, rebase 상태, 누락된 repo, fast-forward가 아닌 Git 경로를 확인합니다.

preflight에서 rebase conflict나 diverged pull 경로를 감지하면 대상 worktree를 변경하기 전에 중단하고, 해당 repo에서 확인하거나 해결할 수 있는 수동 Git command를 출력합니다. conflict를 `workbranch` 밖에서 해결한 뒤 원래 `workbranch` command를 다시 실행하세요.


## Companion 설치와 agent 연결

Homebrew로 Companion을 설치한 뒤 첫 실행의 시작하기 또는 Settings의 설치 및 agent 연결을 사용합니다.

```sh
brew install --cask tkhwang/tap/workbranch-companion
```

CLI 설치 버튼은 `brew install tkhwang/tap/workbranch`로 CLI와 수집기를 준비합니다. 업데이트/복구는 해당 formula만 대상으로 실행하며, 기존 수동 설치만 있다면 먼저 Homebrew 설치로 전환합니다. 버전과 실제 사용 경로는 패널에서 확인할 수 있습니다.

Claude Code, Codex, Grok Build를 개별적으로 연결하거나 해제합니다. agent 프로그램 자체 설치와 계정 로그인은 별도입니다. native hook trust를 확인하고 session을 다시 시작하세요. 설정 완료와 실제 이벤트 수신은 구별되며 재연결 전의 기록은 이전 수신 기록으로 표시합니다. CLI가 없어도 설치 화면은 열리고, 사용자가 버튼을 누르기 전에는 설치/연결을 변경하지 않습니다.

고급 CLI 사용자는 `workbranch hooks install --provider claude|codex|grok`를 사용합니다. 개발 checkout에서는 로컬 plugin source를 자동 선택하며 `--source <checkout>`으로 명시할 수 있습니다. 연결 시 `~/.workbranch/runtime/hook-collector`에 자동 실행용 수집기 링크를 등록해 GUI PATH 차이를 줄입니다. 이 파일은 agent가 작성하는 상태 문서가 아닙니다.


Grok plugin 설치는 명시적 신뢰 승인이 필요합니다. Companion의 Grok 연결 버튼은 설치 경로와 실행 권한을 먼저 보여주며, `신뢰하고 설치`를 선택한 경우에만 승인된 경로에 `--trust`를 적용합니다. CLI에서는 `workbranch hooks describe --provider grok`로 대상을 확인한 뒤, 신뢰하는 경우 `workbranch hooks install --provider grok --trust`를 실행할 수 있습니다. 자동 승인이나 다른 agent에 대한 trust 확장은 하지 않습니다.
