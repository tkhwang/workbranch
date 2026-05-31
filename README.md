# tasktree

Task-based Git worktree workspaces for one repo or many repos.

`git worktree` is powerful, but task setup gets repetitive. AI agents also work best when they can see the whole task from one directory. That becomes especially painful when one feature spans multiple repos:

```text
frontend/   -> run AI agent here
backend/    -> run AI agent again here
infra/      -> run AI agent again here
```

Each repo has its own session, context, file search, and Git state. The agent cannot easily reason about the whole change.

`tasktree` keeps each repo as normal Git, but places task worktrees under one task folder:

```text
fullstack                     // tasktree project
├── .tasktree.config          // repo list and base branches
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
├── .tasktree.config
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
tasktree config            create or rewrite .tasktree.config without cloning repos
tasktree init              clone main worktrees from .tasktree.config
tasktree list              show repos and task workspaces
tasktree status            show commits, diff, and dirty state
tasktree add <task>        create linked worktrees for a task
tasktree remove <task>     remove task worktrees
```

## Git commands

`tasktree` runs familiar Git operations across every repo in `.tasktree.config`.

```text
git       = current repo only
tasktree  = all configured repos
```

```text
remote
  base branch  <---------------- PR / merge outside tasktree ----- task branch
      |                                                      ^
      | tasktree pull                                       | tasktree push <task>
      v                                                      |
local
  base worktree  -- tasktree add <task> -->  task worktree --+
      ^                                      |
      |                                      |
      +--------- tasktree update [<task>] ---+

optional local fast-forward:
  task worktree  -- tasktree land <task> -->  base worktree  -- tasktree push -->  remote base branch
  (fast-forward only, no merge commit)
```

Commands:

```text
tasktree pull             remote base -> local base
tasktree update           local base -> every task worktree
tasktree update <task>    local base -> one task worktree
tasktree land <task>      task worktree -> local base
tasktree push             local base -> remote base
tasktree push <task>      task worktree -> remote task branch
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

For the exact Git commands used by each operation, see [`docs/git-operations.md`](docs/git-operations.md).

`land <task>` is useful when a base branch is already a parent feature branch:

```text
base branch: feature/cpq
task branch: feature/cpq-task1
```

In that case, `tasktree land task1` fast-forwards local `feature/cpq` to include `feature/cpq-task1`. Run `tasktree push` after that to push the base branch.

Add `--repo <name>` to supported Git commands when you want to run against one repo only:

```bash
tasktree pull --repo frontend
tasktree update login --repo frontend
tasktree push login --repo frontend
tasktree land login --repo backend
tasktree push --repo backend
```

## Install

For users:

```bash
curl -fsSL https://raw.githubusercontent.com/tkhwang/tasktree/main/install.sh | bash
```

The installer downloads `tasktree`, asks where to install it, and defaults to:

```text
~/.local/bin/tasktree
```

If the target directory is not on `PATH`, the installer can add it to your shell profile.

Reviewing the script before running it is recommended.

## Config

Create `.tasktree.config` in a project root, or run `tasktree config`. Then run `tasktree init` to clone main worktrees.

If an existing config uses an older format or the old `.monotree.config` name, run `tasktree config` inside the project to rewrite it to `.tasktree.config` without cloning repos again.

```text
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend git@github.com:example/frontend.git master
REPO backend git@github.com:example/backend.git feature/cpq
REPO scripts git@github.com:example/scripts.git master
```

Config format:

```text
REPO <name> <git-url> <base-branch>
```

Task branch names:

```text
base branch master       + task login  -> feature/login
base branch feature/cpq  + task task1  -> feature/cpq-task1
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
docs/specs/0001-tasktree-mvp.md
docs/plans/0001-tasktree-mvp-implementation.md
```
