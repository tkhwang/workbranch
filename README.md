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
└── feat-login          // task root: not git-managed; run your AI agent here
    ├── frontend        // git repo worktree
    └── backend         // git repo worktree
```

For multi-repo products, `workbranch` gathers every repo an agent needs into one task folder. That makes AI-agent sessions easier to start, inspect, and clean up than juggling separate clones or unrelated worktrees.

Before an agent starts, `workbranch refresh <task>` brings every repo in the task up to the latest base in one command — no per-repo pulling or rebasing.

See [AI agent workflows](docs/ai-agents.md) for the multi-repo benefits.

## Working on a task

Now work inside the task workspace. The task root (`<task>`) is a non-git workbranch metadata/agent workspace; the actual Git repos live under `<task>/<repo>`.

```bash
# macOS: open code repos in the IDE, and the task root in the terminal
workbranch ide feat-login        # opens feat-login/<repo> worktrees
workbranch terminal feat-login   # opens feat-login task root

# or anywhere
cd feat-login/<repo>
# edit code and run git commands in the repo
```

Need the latest base while you work? See [Staying up to date](#staying-up-to-date). When the work is done, [ship it](#two-ways-to-ship).

## Staying up to date

To bring a single task up to the latest base, `pull` the base from its remote and `update <task>` to apply it to the task.

```bash
workbranch pull               # pull base latest update
workbranch update feat-login  # apply local base update to feat-login task 

# combined: pull + update in one step
workbranch refresh feat-login
```

Working in several tasks at once? Run them without a task name to refresh every task in one go.

```bash
workbranch pull      # pull base latest update
workbranch update    # apply local base to every task

# combined
workbranch refresh   # pull base latest update, then update all tasks
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
| `workbranch list [--json]` | Show repos and task workspaces; `--json` is machine-readable |
| `workbranch memo [task]`   | Show, write, or clear the task brief in `TASK-WORKBRANCH.md` |
| `workbranch noti ...`       | Add, list, or clear task notifications                  |
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

## Task brief & notifications

`workbranch add <task>` creates task-root state outside the repo worktrees:

- `<task>/TASK-WORKBRANCH.md` is the human/agent-editable task brief. The generated template uses a first `#` heading, an optional `status: planning|in-progress|review|blocked|done` line, and Markdown checklist items for progress. `workbranch memo <task> [text]` reads or overwrites it, and `workbranch memo <task> --clear` removes it. Inside a task workspace, `workbranch memo` may omit `<task>` for reading only.
- `<task>/AGENTS.md` tells AI agents running from either `<task>` or `<task>/<repo>` to keep the task brief current, including when starting/resuming, changing the active step, before/after verification, when blocked, and before the final response.
- `<task>/.workbranch/notifications.jsonl` is an append-only local inbox. `workbranch noti add/list/clear` manages it, and `workbranch list --json` exposes `notiCount`, `status`, `progressDone`, `progressTotal`, `currentItem`, and `updatedAt` for companion apps.

`workbranch remove <task>` deletes known workbranch task state after successful workspace removal: `TASK-WORKBRANCH.md`, generated `AGENTS.md`, `.workbranch/`, and `.workbranch.task`. Everything else left in the task root, including agent runtime folders such as `.omx/` and `.omc/`, is not git-managed. Normal remove lists those leftovers and asks once whether to delete the entire task root. `workbranch remove <task> --force` removes the task root without prompting after the normal safety preflights pass.

## Native menu bar companion

`companion/` contains a local native macOS menu bar app, `WorkbranchCompanion.app`, that consumes `workbranch list --json` and provides a task cockpit for task status/progress, an always-visible warm-colored current-work/status line with `HH:mm` update time under repo/branch identity, repo child rows with branch identity, inline memo edits, notification clearing, and existing Finder/IDE/terminal launch actions. If a configured project root is truly deleted while its parent still exists, the app forgets that root after two consecutive failed refreshes and sends one notification.

Install published releases with Homebrew:

```bash
brew tap tkhwang/tap
brew install --cask tkhwang/tap/workbranch-companion
```

Published companion releases are signed with a Developer ID certificate and notarized, so Gatekeeper quarantine bypass flags are not required.

Build it locally:

```bash
cd companion
swift build
swift run CompanionCoreTestRunner
./scripts/build-app.sh
open dist/WorkbranchCompanion.app
```

Configure roots in `~/.config/workbranch-companion/config.json`.

## More docs

- [Task identity and branch names](docs/task-identity.md)
- [Usage details](docs/usage.md)
- [AI agent workflows](docs/ai-agents.md)
- [Architecture](docs/architecture.md)
- [Git operations](docs/git-operations.md)
- [MVP spec](docs/specs/0001-workbranch-mvp.md)
