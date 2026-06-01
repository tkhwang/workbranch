# workbranch

Simplify Git worktree workspaces and branch operations.

`workbranch` has two main features:

1. create task-oriented Git worktree workspaces
2. simplify branch operations between remote, base worktree, and feature worktrees

## 1. Worktree workspace

`workbranch` organizes linked worktrees by task/feature. A task such as `login` or `payment` gets its own folder, and each configured repo gets a linked worktree inside that folder.

```text
workbranch init              clone main worktrees from .workbranch.config
workbranch add <task>        create linked worktrees for a task
workbranch remove <task>     remove task worktrees
```

For a single repo:

`workbranch` still uses `<task>/<repo>`. The extra repo directory keeps the layout consistent with multi-repo projects, but single-repo users usually work from `<task>/<repo>`.

```text
my-app-workspace
├── .workbranch.config
├── _base
│   └── my-app              // base worktree
├── login
│   └── my-app              // feature worktree
└── payment
    └── my-app              // feature worktree
```

For multi-repo:
In multi-repo work, the feature folder gives one shared workspace/session context for all repos in that task.

```text
my-app-workspace
├── .workbranch.config
├── _base
│   ├── frontend            // base worktree: frontend
│   └── backend             // base worktree: backend
├── login                   // run one AI agent here
│   ├── frontend            // feature worktree: frontend
│   └── backend             // feature worktree: backend
└── payment
    ├── frontend            // feature worktree: frontend
    └── backend             // feature worktree: backend
```



## 2. Worktree branch operations

`workbranch` keeps Git operations in two directions:

- vertical: remote base branch `<->` local base worktree
- horizontal: local base worktree `<->` feature worktrees

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

Commands:

```text
vertical
  workbranch pull             origin/<base> -> _base/<repo>
  workbranch push             _base/<repo>  -> origin/<base>

  workbranch push <feature>   feature branch -> origin/<feature-branch>
  workbranch push task1       push every repo task1 branch
  workbranch push task1 --repo frontend
                              push only frontend task1 branch

horizontal
  workbranch update           _base/<repo>  -> every feature worktree
  workbranch update <feature> _base/<repo>  -> one feature worktree
  workbranch land <feature>   feature       -> _base/<repo>
```

#### Safety

Before mutating worktrees, `workbranch` checks for common unsafe states:

- dirty worktrees
- wrong current branch
- rebase in progress
- missing repos or task worktrees
- non-fast-forward pull, push, or land paths

## Install

### Homebrew 

planned install shape:

```bash
brew tap tkhwang/workbranch
brew install workbranch
```

### Installer:

```bash
curl -fsSL https://raw.githubusercontent.com/tkhwang/workbranch/main/install.sh | WORKBRANCH_RAW_BASE_URL=https://raw.githubusercontent.com/tkhwang/workbranch/main bash
```
