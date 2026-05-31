# 0001 Monotree MVP Implementation Plan

## Objective

Build a dependency-free Bash CLI that creates one multi-repo task workspace and runs common Git worktree operations across every configured repo.

## Source contract

Spec: `docs/specs/0001-monotree-mvp.md`

## Config

Use one config file at the project root:

```text
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend git@github.com:example/frontend.git master
REPO backend git@github.com:example/backend.git feature/cpq
```

Parser rules:

- line-oriented format
- comments start with `#`
- no quoting
- values cannot contain whitespace
- `REPO` requires name, URL, and base branch

## Implementation phases

### 1. Config and project discovery

- Find `.monotree.config` by walking upward from the current directory.
- Parse project name, main worktrees directory, branch prefix, and repos.
- Validate safe names and required fields.

### 2. Config and init

- `config`: show the multi-repo AI problem and target folder structure, ask for target directory, project name, main worktrees directory, default base branch, branch prefix, and repos, then write `.monotree.config` without cloning.
- `init`: read `.monotree.config` and clone base worktrees into `_base/<repo>`.
- If `init` runs without an existing config, use the same interactive setup as `config`, then clone.
- Roll back command-created paths on clone failure.

### 3. Workspace commands

- `list`: show configured repos and task workspaces.
- `status`: show clean/dirty state for base and task worktrees with aligned columns.
- `add <task>`: create linked worktrees for all repos.
- `remove <task>`: remove linked worktrees without deleting branches.

### 4. Git commands

- `pull`: run `git pull --ff-only origin <base-branch>` in each base worktree.
- `rebase`: rebase every task worktree onto `origin/<base-branch>`.
- `rebase <task>`: rebase one task workspace onto `origin/<base-branch>`.
- `push`: push each base branch to origin.
- `push <task>`: push each task branch to origin.
- `merge <task>`: fast-forward each local base branch from its task branch.
- `--repo <repo>`: limit supported Git commands to one repo.

### 5. Branch naming

- Base branch starts with `<BRANCH_PREFIX>/`: task branch is `<base-branch>-<task>`.
- Otherwise: task branch is `<BRANCH_PREFIX>/<task>`.

### 6. Safety

- Fail on dirty worktrees before pull, rebase, merge, or remove.
- Use `--ff-only` for pull and merge.
- Do not create merge commits.
- Do not overwrite existing branches or paths.
- Roll back command-created paths and branches on add/init failure.

### 7. Tests

Use `tests/run.sh` with temporary local bare remotes.

Cover:

- config parsing and invalid config rejection
- config without clone
- init and rollback
- interactive init
- branch naming for main and parent feature base branches
- add/list/status/remove
- pull/rebase/rebase-one/push-base/push-task/merge/repo-scope
- dirty worktree safety
- installer behavior

## Acceptance evidence

Run:

```bash
/bin/bash -n bin/monotree install.sh tests/run.sh
git diff --check
/bin/bash ./tests/run.sh
```
