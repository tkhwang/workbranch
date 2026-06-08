# workbranch

**English** | [한국어](README.ko.md)

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

`workbranch init` clones base repos and can create your first task during setup.

```bash
workbranch init
# choose to add the first task: login

# work in feat-login/<repo>

workbranch refresh feat-login
workbranch land feat-login
workbranch push
```

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
