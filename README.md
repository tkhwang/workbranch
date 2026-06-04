# workbranch

**English** | [한국어](README.ko.md)

Manage Git worktree task spaces without memorizing `git worktree` commands.

`workbranch` creates one task folder per feature, works with one repo or many repos, and keeps branch sync commands short and safe.

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

```bash
workbranch init
workbranch add login
cd login/<repo>
# work on the task
workbranch update login
workbranch push login
workbranch remove login
```

`workbranch add <task>` uses `<task>` as the folder name, then prompts for each repo's task branch. Press Enter to accept the default branch name. Defaults are `feature/<task>` from main-style base branches and `<base-branch>-<task>` from `feature/*`, `feat/*`, or the configured legacy prefix.

Task branches are created from the current HEAD of your local `_base/<repo>` worktrees. `workbranch add` does not pull remote base branches automatically. To start from the latest remote base, run:

```bash
workbranch pull
workbranch add <task>
```

Use `workbranch config` when you want to update project settings, base branches, or per-repo setup commands without cloning repos again.

## What it creates

For every task, `workbranch` creates linked worktrees under one shared task directory:

```text
my-app-workspace
├── .workbranch.config
├── _base
│   ├── frontend
│   └── backend
└── login
    ├── frontend
    └── backend
```

Single-repo projects use the same shape with one repo directory inside each task.

## Common commands

| Command | Use it to |
| --- | --- |
| `workbranch init` | Create or clone base worktrees from config |
| `workbranch config` | Edit project settings, base branches, and repo setup commands |
| `workbranch add <task>` | Create a task workspace |
| `workbranch resume <task>` | Restore existing local or remote task branches |
| `workbranch list` | Show repos and task workspaces |
| `workbranch status` | Show branch, diff, and dirty state |
| `workbranch update [task]` | Merge local base changes into task worktrees |
| `workbranch pull` | Pull remote base branches into `_base/<repo>` |
| `workbranch push [task]` | Push base branches or task branches |
| `workbranch land <task>` | Fast-forward task work back into local base branches |
| `workbranch remove <task>` | Remove task worktrees and local task branches |
| `workbranch -v` | Show the installed version |

Add `--repo <repo>` to supported Git commands when you want to operate on one repo only.

## Setup commands

`workbranch config` can store a setup command per repo. When you run `workbranch add <task>`, each setup command runs inside `<task>/<repo>`.

See the [MVP spec](docs/specs/0001-workbranch-mvp.md) for the config format and setup environment variables.

## Safety

Before changing worktrees, `workbranch` checks for dirty worktrees, wrong branches, rebase state, missing repos, and non-fast-forward Git paths.

## More docs

- [Architecture](docs/architecture.md)
- [Git operations](docs/git-operations.md)
- [MVP spec](docs/specs/0001-workbranch-mvp.md)
