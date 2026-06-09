# workbranch

**English** | [한국어](README.ko.md)

[![CI](https://github.com/tkhwang/workbranch/actions/workflows/ci.yml/badge.svg)](https://github.com/tkhwang/workbranch/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/tkhwang/workbranch?sort=semver)](https://github.com/tkhwang/workbranch/releases)
[![License: MIT](https://img.shields.io/github/license/tkhwang/workbranch)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-informational)

Manage Git worktree task spaces without memorizing `git worktree` commands.

`workbranch` creates one task folder per feature, works with one repo or many repos, and keeps branch refresh commands short and safe.

![img](./docs/figs/workbranch-git-flow.png)

## Install

### Homebrew

```bash
brew install tkhwang/tap/workbranch
```

If you prefer to add the tap first:

```bash
brew tap tkhwang/tap
brew install workbranch
```

### curl installer

```bash
curl -fsSL https://raw.githubusercontent.com/tkhwang/workbranch/main/install.sh | bash
```

Homebrew installs published releases. The curl installer tracks `main`.

## Quick start

Start with a single repo — `workbranch init` walks you through setup and can create your first task on the spot.

```bash
workbranch init
# Project name, then register one repo (name + Git URL + base branch)
# "Add another repo?"    -> N       # one repo is all you need to start
# "Add your first task?" -> login   # creates the feat-login workspace
```

Then work inside the task workspace and ship it:

```bash
# edit code in feat-login/<repo>

workbranch pull                # pull remote base branches
workbranch update feat-login   # update the task from local base
workbranch land feat-login     # land the task into base
workbranch push                # push the base branch
```

Or do it all with one combined command:

```bash
workbranch refresh feat-login   # pull + update
workbranch land feat-login

workbranch finalize feat-login  # pull + update + land
```

```bash
workbranch push
```

Working across more than one repo? `workbranch` groups them all in one task folder — see [What it creates](#what-it-creates).

## What it creates

For every task, `workbranch` creates linked worktrees under one shared task directory:

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

Single-repo projects use the same shape with one repo directory inside each task.

## Common commands

| Command                   | Use it to                                            |
| ------------------------- | ---------------------------------------------------- |
| `workbranch init`         | Create or clone base worktrees from config           |
| `workbranch add [<task>]` | Create a task workspace                              |
| `workbranch list`         | Show repos and task workspaces                       |
| `workbranch status`       | Show base remote diff, task diff, and dirty state    |
| `workbranch land <task>`  | Fast-forward task work back into local base branches |
| `workbranch push [task]`  | Push base or task branches                           |
| `workbranch path <task>`  | Print a task workspace or repo path                  |

Combined flow shortcuts:

| Command                      | Use it to                                                            |
| ---------------------------- | -------------------------------------------------------------------- |
| `workbranch refresh [task]`  | Pull base branches, then update task workspaces                      |
| `workbranch finalize <task>` | Pull base branches, update one task, then land it                    |
| `workbranch prune`           | Remove clean task workspaces already merged into local base branches |

## Multi-repo AI agent workflows

```
└── feat-login      // run AI agent here!!!
    ├── frontend
    └── backend
```

For multi-repo products, `workbranch` gives each task one shared workspace containing every repo the agent needs. That makes AI-agent sessions easier to start, inspect, and clean up than juggling separate clones or unrelated worktrees.

See [AI agent workflows](docs/ai-agents.md) for the multi-repo benefits.

## More docs

- [Task identity and branch names](docs/task-identity.md)
- [Usage details](docs/usage.md)
- [AI agent workflows](docs/ai-agents.md)
- [Architecture](docs/architecture.md)
- [Git operations](docs/git-operations.md)
- [MVP spec](docs/specs/0001-workbranch-mvp.md)
