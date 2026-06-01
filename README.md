# workbranch

Task-based Git worktree workspaces for one repo or many repos.

`git worktree` is powerful, but task setup gets repetitive. AI agents also work best when they can see the whole task from one directory. That becomes especially painful when one feature spans multiple repos:

```text
frontend/   -> run AI agent here
backend/    -> run AI agent again here
infra/      -> run AI agent again here
```

Each repo has its own session, context, file search, and Git state. The agent cannot easily reason about the whole change.

`workbranch` keeps each repo as normal Git, but places task worktrees under one task folder:

```text
fullstack                     // workbranch project
├── .workbranch.config          // repo list and base branches
├── _base                     // main worktrees
│   ├── frontend              // main: frontend
│   └── backend               // main: backend
└── login                     // task workspace
    ├── frontend              // linked: frontend
    └── backend               // linked: backend
```

Run your AI agent from the task workspace:

```bash
cd fullstack/login
codex
# or claude
```

For one repo, the same layout is used with one repo directory:

```text
my-app-workspace
├── .workbranch.config
├── _base
│   └── my-app
└── login
    └── my-app
```

Run your AI agent from `login/my-app` for one repo, or from `login` when a task spans multiple repos.

Now the agent can search and edit configured repos in one session:

```text
@frontend/src/...
@backend/app/...
```

## Workspace commands

Workspace commands work for every configured repo.

```text
workbranch config            create or rewrite .workbranch.config without cloning repos
workbranch setup             add or change task setup command
workbranch init              clone main worktrees from .workbranch.config
workbranch list              show repos and task workspaces
workbranch status            show commits, diff, and dirty state
workbranch add <task>        create linked worktrees for a task
workbranch setup <task>      run task setup for an existing task
workbranch remove <task>     remove task worktrees
```

## Git commands

`workbranch` runs familiar Git operations across every repo in `.workbranch.config`.

```text
git       = current repo only
workbranch  = all configured repos
```

```text
remote
  base branch  <---------------- PR / merge outside workbranch ----- task branch
      |                                                      ^
      | workbranch pull                                       | workbranch push <task>
      v                                                      |
local
  base worktree  -- workbranch add <task> -->  task worktree --+
      ^                                      |
      |                                      |
      +--------- workbranch update [<task>] ---+

optional local fast-forward:
  task worktree  -- workbranch land <task> -->  base worktree  -- workbranch push -->  remote base branch
  (fast-forward only, no merge commit)
```

Commands:

```text
workbranch pull             remote base -> local base
workbranch update           local base -> every task worktree
workbranch update <task>    local base -> one task worktree
workbranch land <task>      task worktree -> local base
workbranch push             local base -> remote base
workbranch push <task>      task worktree -> remote task branch
```

`pull` is the command that reads remote base branches. `update` and `land` use only local worktrees:

```text
Vertical:
  pull        origin/<base> -> _base/<repo>
  push        _base/<repo>  -> origin/<base>

Horizontal:
  update      _base/<repo>  -> <task>/<repo>
  land        <task>/<repo> -> _base/<repo>

Optional:
  push <task> <task>/<repo> -> origin/<task-branch>
```

`update` uses the local `_base/<repo>` HEAD and requires that base worktree to be on its configured base branch.

For the exact Git commands used by each operation, see [`docs/git-operations.md`](docs/git-operations.md).

`land <task>` is useful when a base repo branch is already a parent feature branch:

```text
base repo branch: feature/cpq
task branch: feature/cpq-task1
```

In that case, `workbranch land task1` fast-forwards local `feature/cpq` to include `feature/cpq-task1`. Run `workbranch push` after that to push the base repo branch.

Add `--repo <name>` to supported Git commands when you want to run against one repo only:

```bash
workbranch pull --repo frontend
workbranch update login --repo frontend
workbranch push login --repo frontend
workbranch land login --repo backend
workbranch push --repo backend
```

## Install

For users:

```bash
curl -fsSL https://raw.githubusercontent.com/tkhwang/workbranch/main/install.sh | WORKBRANCH_RAW_BASE_URL=https://raw.githubusercontent.com/tkhwang/workbranch/main bash
```

The installer downloads `workbranch`, asks where to install it, and defaults to:

```text
~/.local/bin/workbranch
```

If the target directory is not on `PATH`, the installer can add it to your shell profile.

Reviewing the script before running it is recommended.

## Config

Create `.workbranch.config` in a project root, or run `workbranch config`. Then run `workbranch init` to clone main worktrees.

If an existing config uses an older format or the old `.tasktree.config` / `.monotree.config` name, run `workbranch config` inside the project to rewrite it to `.workbranch.config` without cloning repos again.

```text
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature
TASK_SETUP sh scripts/workbranch-setup.sh

REPO frontend git@github.com:example/frontend.git master
REPO backend git@github.com:example/backend.git feature/cpq
REPO scripts git@github.com:example/scripts.git master
```

Config format:

```text
TASK_SETUP <command>
REPO <name> <git-url> <base-repo-branch>
```

`TASK_SETUP` is optional. `workbranch add <task>` runs it after all task worktrees are created. You can add or change it later:

```bash
workbranch setup
workbranch setup --clear
workbranch setup <task>
```

Task setup runs from the project root with:

```text
WORKBRANCH_PROJECT_ROOT
WORKBRANCH_TASK
WORKBRANCH_TASK_DIR
WORKBRANCH_BASE_DIR
WORKBRANCH_REPOS
```

Task branch names:

```text
[base repo] main        -> task1 -> [task repo] feature/task1
[base repo] feature/XXX -> task1 -> [task repo] feature/XXX-task1
```

## Development

Install from this repo checkout:

```bash
./install.sh
```

```bash
./tests/run.sh
```

Spec and plan:

```text
docs/specs/0001-workbranch-mvp.md
docs/plans/0001-workbranch-mvp-implementation.md
```
