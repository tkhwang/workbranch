# workbranch

**English** | [한국어](README.ko.md)

[![CI](https://github.com/tkhwang/workbranch/actions/workflows/ci.yml/badge.svg)](https://github.com/tkhwang/workbranch/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/tkhwang/workbranch?sort=semver)](https://github.com/tkhwang/workbranch/releases)
[![License: MIT](https://img.shields.io/github/license/tkhwang/workbranch)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-informational)

Manage Git worktree task spaces without memorizing `git worktree` commands.

`workbranch` creates one task folder per feature, works with one repo or many repos, and keeps branch refresh commands short and safe.

![workbranch demo](./docs/figs/workbranch-demo.gif)

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

`workbranch init` walks you through setup and can create your first task on the spot.

```bash
workbranch init
# Project name, then register one repo (name + Git URL + base branch)
# "Add another repo?"    -> N       # one repo is all you need to start
# "Add your first task?" -> login   # creates the feat-login workspace
```

Need another task later? Create one anytime with `workbranch add`.

```bash
workbranch add login # (branch) feat/login
                     # (folder) feat-login/<repo>
```

## What it creates

For every task, `workbranch` creates linked worktrees under one shared task directory:

```text
my-app-workspace
├── .workbranch.config
├── _base
│   ├── frontend
│   └── backend
└── feat-login          // run your AI agent here!
    ├── frontend
    └── backend
```

For multi-repo products, `workbranch` gathers every repo an agent needs into one task folder. That makes AI-agent sessions easier to start, inspect, and clean up than juggling separate clones or unrelated worktrees.

Before an agent starts, `workbranch refresh <task>` brings every repo in the task up to the latest base in one command — no per-repo pulling or rebasing.

See [AI agent workflows](docs/ai-agents.md) for the multi-repo benefits.

## Working on a task

Now work inside the task workspace. On macOS, open it directly with `workbranch ide` / `workbranch terminal`; elsewhere, just `cd` in.

```bash
# macOS: open the task workspace in your configured IDE / terminal
workbranch ide feat-login
workbranch terminal feat-login

# or anywhere
cd feat-login/<repo>
# edit code in repo
```

Need the latest base while you work? See [Staying up to date](#staying-up-to-date). When the work is done, [ship it](#two-ways-to-ship).

## Staying up to date

To bring a single task up to the latest base, `pull` the base from its remote and `update <task>` to apply it to the task.

```bash
workbranch pull               # pull every base from its remote
workbranch update feat-login  # apply local base to every repo in the task

# combined: pull + update in one step
workbranch refresh feat-login
```

Working in several tasks at once? Run them without a task name to refresh every task in one go.

```bash
workbranch pull      # pull every base from its remote
workbranch update    # apply local base to every repo in every task

# combined
workbranch refresh   # pull every base, then update every task
```

To refresh the base, apply it to a task, and land in one step, use `finalize`.

```bash
workbranch finalize feat-login   # base pull → feat-login update → land
```

## Two ways to ship

What `push` publishes depends on your base branch.

|                      | Feature flow                    | Stacked flow                                            |
| -------------------- | ------------------------------- | ------------------------------------------------------- |
| Base branch          | `main` / `master`               | a feature branch, e.g. `feat/login`                     |
| Task branch (folder) | `feat/login` (`feat-login`)     | `feat/login-part1` (`feat-login-part1`)                 |
| Ship                 | push the task branch, open a PR | land into base, then push the base                      |
| Command              | `workbranch push feat-login`    | `workbranch land feat-login-part1`<br>`workbranch push` |
| Pushes               | task branch                     | base branch                                             |

### Feature flow

```bash
# edit code in feat-login/<repo>

workbranch push feat-login   # local feat/login -> origin/feat/login
```

### Stacked flow

```bash
# edit code in feat-login-part1/<repo>

workbranch land feat-login-part1   # fast-forward feat/login-part1 into local base (feat/login)
workbranch push                    # local feat/login -> origin/feat/login
```

## Commands

| Command                    | Use it to                                               |
| -------------------------- | ------------------------------------------------------- |
| `workbranch init`          | Create or clone base worktrees from config              |
| `workbranch add [<task>]`  | Create a task workspace                                 |
| `workbranch list`          | Show repos and task workspaces                          |
| `workbranch status`        | Show base remote diff, task diff, and dirty state       |
| `workbranch update [task]` | Update every repo in the task from local base (no pull) |
| `workbranch land <task>`   | Fast-forward task work into local base branches         |
| `workbranch push [task]`   | Push base or task branches                              |

Combined flow shortcuts:

| Command                      | Use it to                                                            |
| ---------------------------- | -------------------------------------------------------------------- |
| `workbranch refresh [task]`  | Pull base branches, then update task workspaces                      |
| `workbranch finalize <task>` | Pull base branches, update one task, then land it                    |
| `workbranch prune`           | Remove clean task workspaces already merged into local base branches |

![img](./docs/figs/workbranch-git-flow.png)

## More docs

- [Task identity and branch names](docs/task-identity.md)
- [Usage details](docs/usage.md)
- [AI agent workflows](docs/ai-agents.md)
- [Architecture](docs/architecture.md)
- [Git operations](docs/git-operations.md)
- [MVP spec](docs/specs/0001-workbranch-mvp.md)
