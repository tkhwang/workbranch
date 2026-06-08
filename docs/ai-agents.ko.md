# AI agent workflow

[README](../README.ko.md) | [English](ai-agents.md)

하나의 제품 변경이 여러 repo에 걸쳐 있을 때 `workbranch`는 AI agent 작업에 유용합니다.

```
└── feat-login      // run AI agent here!!!
    ├── frontend
    └── backend
```

## multi-repo workspace가 도움이 되는 이유

- 하나의 task folder 안에 변경에 필요한 모든 repo가 들어가므로, agent가 frontend, backend, shared library, docs를 함께 확인할 수 있습니다.
- repo마다 Git branch와 worktree는 계속 분리되므로, 변경사항은 repo 단위로 review할 수 있습니다.
- `workbranch refresh <task>`로 agent가 계속 작업하기 전에 전체 task workspace를 최신 base 기준으로 갱신할 수 있습니다.
- `workbranch status`로 review나 handoff 전에 여러 repo의 dirty state와 base/task diff를 함께 확인할 수 있습니다.
- `workbranch path`, `workbranch ide`, `workbranch terminal`로 같은 task context를 외부 도구에서 쉽게 열 수 있습니다.
- `workbranch remove <task>`로 land되었거나 중단된 multi-repo task workspace를 한 번에 정리할 수 있습니다.

## mono-repo와 다른 점

mono-repo에서는 checkout 하나가 이미 agent에게 하나의 project surface를 제공합니다. multi-repo에서는 agent가 여러 독립 checkout, branch, update step을 맞춰야 합니다. `workbranch`는 Git에서는 repo를 분리한 채 유지하면서, disk에서는 하나의 task workspace처럼 다룰 수 있게 합니다.
