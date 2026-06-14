# AI agent workflow

[README](../README.ko.md) | [English](ai-agents.md)

하나의 제품 변경이 여러 repo에 걸쳐 있을 때 `workbranch`는 AI agent 작업에 유용합니다.

```
└── feat-login      // task root: AI agent 실행 위치, Git repo 아님
    ├── frontend    // 실제 Git repo worktree
    └── backend     // 실제 Git repo worktree
```

## multi-repo workspace가 도움이 되는 이유

- 하나의 task folder 안에 변경에 필요한 모든 repo가 들어가므로, agent가 frontend, backend, shared library, docs를 함께 확인할 수 있습니다.
- repo마다 Git branch와 worktree는 계속 분리되므로, 변경사항은 repo 단위로 review할 수 있습니다.
- `workbranch refresh <task>`로 agent가 계속 작업하기 전에 전체 task workspace를 최신 base 기준으로 갱신할 수 있습니다.
- `workbranch status`로 review나 handoff 전에 여러 repo의 dirty state와 base/task diff를 함께 확인할 수 있습니다.
- `workbranch path`, `workbranch ide`, `workbranch terminal`로 맞는 표면을 쉽게 열 수 있습니다. IDE는 repo worktree를 열고, terminal은 기본적으로 task root를 열며, `--repo`로 둘 다 특정 repo에 scope할 수 있습니다.
- `workbranch remove <task>`로 land되었거나 중단된 multi-repo task workspace를 한 번에 정리할 수 있습니다.

## mono-repo와 다른 점

mono-repo에서는 checkout 하나가 이미 agent에게 하나의 project surface를 제공합니다. multi-repo에서는 agent가 여러 독립 checkout, branch, update step을 맞춰야 합니다. `workbranch`는 Git에서는 repo를 분리한 채 유지하면서, disk에서는 하나의 task workspace처럼 다룰 수 있게 합니다.

## Task root 규약

Agent session은 기본적으로 `<task>`에서 실행합니다. 그래야 agent가 `AGENTS.md`, `TASK-WORKBRANCH.md`, task 아래 모든 repo를 볼 수 있습니다. Task root 자체는 git으로 관리되지 않습니다. 코드 변경과 Git 명령은 `<task>/<repo>` 안에서 수행하세요. `.omx/`, `.omc/` 같은 runtime state는 git 미관리 task-root 잔여물로 취급되며 `workbranch remove <task>`가 삭제 전에 목록으로 보여줍니다.
