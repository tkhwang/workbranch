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
├── .monotree.config          // repo list and workflow rules
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
monotree init              create .monotree.config
monotree list              show repos and task workspaces
monotree add <task>        create linked worktrees for a task
monotree remove <task>     remove task worktrees
```

## Git workflow commands

`monotree` does not replace Git. It runs a small set of Git operations across the repos in `.monotree.config`.

```text
git       = current repo only
monotree  = all configured repos
```

Each repo chooses one workflow.

### Free workflow

Use monotree only for workspace layout. Use `git` directly inside each repo.

```text
local repo  -- git pull / git push / git rebase / git merge -->  remote
```

### Feature workflow

Use a task branch and open a PR back to the base branch.

```text
remote    base  <-- PR --------  feature
            |                       ^
            | pull                  | push <task>
            v                       |
local     base  --add <task>-->  feature
            \                       ^
             \-- rebase <task> ----/
```

Commands:

```text
monotree pull             update local base branches from remote
monotree rebase <task>    run git rebase <base> inside each task worktree
monotree push <task>      push each task branch to origin
```

### Stacked workflow

Use a local child branch on top of a parent feature branch, then merge it back into the parent feature branch.

```text
remote    base  <-- PR --------  parent feature
                                ^
                                | push parent feature
                                |
local     base              parent feature  --add <task>-->  feature local
                              ^      ^                            |
                              | pull |                            | merge <task>
                              |      \----------------------------/
```

Commands:

```text
monotree pull             update local parent feature branches from remote
monotree rebase <task>    run git rebase <parent-feature> inside each task worktree
monotree merge <task>     merge each task branch into its parent feature branch
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

Create `.monotree.config` in a project root, or run `monotree init`.

```text
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend git@github.com:example/frontend.git
WORKFLOW frontend feature master

REPO backend git@github.com:example/backend.git
WORKFLOW backend stacked feature/cpq

REPO scripts git@github.com:example/scripts.git
WORKFLOW scripts free master
```

Workflow format:

```text
WORKFLOW <repo-name> free <base-branch>
WORKFLOW <repo-name> feature <main-branch>
WORKFLOW <repo-name> stacked <parent-feature-branch>
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
