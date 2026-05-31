# monotree

Multi-repo workspaces for AI coding agents.

`git` works in one repository at a time. AI agents also work best when they can see the whole task from one directory. That becomes painful when one feature spans multiple repos:

```text
frontend/   -> run AI agent here
backend/    -> run AI agent again here
infra/      -> run AI agent again here
```

Each repo has its own session, context, file search, and Git state. The agent cannot easily reason about the whole change.

`monotree` keeps your repos separate, but places their worktrees under one task folder:

```text
fullstack                     // monotree project
├── .monotree.config          // repo list and base branches
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

Now the agent can search and edit both repos in one session:

```text
@frontend/src/...
@backend/app/...
```

## Workspace commands

Workspace commands work for every configured repo.

```text
monotree config            create .monotree.config without cloning repos
monotree init              clone main worktrees from .monotree.config
monotree list              show repos and task workspaces
monotree status            show modified/untracked files in base and tasks
monotree add <task>        create linked worktrees for a task
monotree remove <task>     remove task worktrees
```

## Git commands

`monotree` runs familiar Git operations across every repo in `.monotree.config`.

```text
git       = current repo only
monotree  = all configured repos
```

```text
remote
  base branch  <---------------- PR / merge outside monotree ----- task branch
      |                                                      ^
      | monotree pull                                       | monotree push <task>
      v                                                      |
local
  base worktree  -- monotree add <task> -->  task worktree --+
      ^                                      |
      |                                      |
      +--------- monotree rebase [<task>] ---+

optional local fast-forward:
  task worktree  -- monotree merge <task> -->  base worktree  -- monotree push -->  remote base branch
  (fast-forward only, no merge commit)
```

Commands:

```text
monotree pull             update local base branches from remote
monotree rebase           run git rebase <base> inside every task worktree
monotree rebase <task>    run git rebase <base> inside one task worktree
monotree push             push each base branch to origin
monotree push <task>      push each task branch to origin
monotree merge <task>     fast-forward merge each task branch into its base branch
```

`merge <task>` is useful when a base branch is already a parent feature branch:

```text
base branch: feature/cpq
task branch: feature/cpq-task1
```

In that case, `monotree merge task1` fast-forwards local `feature/cpq` to include `feature/cpq-task1`. Run `monotree push` after that to push the base branch.

Add `--repo <name>` to supported Git commands when you want to run against one repo only:

```bash
monotree pull --repo frontend
monotree rebase login --repo frontend
monotree push login --repo frontend
monotree merge login --repo backend
monotree push --repo backend
```

## Install

From this repo:

```bash
./install.sh
```

The installer asks where to install `monotree`. The default is:

```text
~/.local/bin/monotree
```

If the target directory is not on `PATH`, the installer can add it to your shell profile.

## Config

Create `.monotree.config` in a project root, or run `monotree config`. Then run `monotree init` to clone main worktrees.

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

```bash
./tests/run.sh
```

Spec and plan:

```text
docs/specs/0001-monotree-mvp.md
docs/plans/0001-monotree-mvp-implementation.md
```
