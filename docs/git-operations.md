# Git operations

This file defines the Git commands behind each `workbranch` Git operation.

`workbranch` keeps the user-facing model small, but the implementation still uses ordinary Git commands. Use this file as the maintenance contract for Git behavior.

The source-level definitions live in `src/workbranch/git-ops.sh`.
`bin/workbranch` is the generated single-file install artifact.

## Direction model

```text
Vertical:
  pull        remote base -> local base
  push        local base  -> remote base

Horizontal:
  update      local base  -> task
  land        task        -> local base

Optional:
  push <task> task        -> remote task branch
```

## Commands

### `workbranch add <task>`

Direction: base -> task worktree.

Before creating worktrees, `workbranch add <task>` prompts for each repo's task branch. Press Enter to accept the default branch name. The chosen branches are saved in `<task>/.workbranch.task`.

For each repo:

```bash
cd _base/<repo>
git fetch origin
git worktree add <task>/<repo> -b <task-branch> HEAD
```

If the task branch already exists locally or remotely, `workbranch add <task>` fails and tells the user to use `workbranch resume <task>`.

### `workbranch resume <task>`

Direction: existing local or remote task branch -> task worktree.

When `resume` must create or restore missing task worktrees, it prompts for each repo's task branch before preflight branch-existence checks. Existing `<task>/.workbranch.task` entries are used as prompt defaults; otherwise the normal default branch rule is used.

If the task branch already exists locally, restore it:

```bash
cd _base/<repo>
git worktree add <task>/<repo> <task-branch>
```

If only the remote task branch exists, create the local task branch from it before adding the worktree:

```bash
cd _base/<repo>
git fetch origin
git branch --track <task-branch> origin/<task-branch>
git worktree add <task>/<repo> <task-branch>
```

Safety:

- Rolls back worktrees and new branches created by the command if worktree creation fails.
- Keeps created worktrees if a configured setup command fails, prints the failed setup directory and command, and tells the user to fix setup with `workbranch config`, then rerun the shown command or remove and add the task again.
- Uses the local base worktree HEAD, not `origin/<base-branch>`.
- `workbranch remove <task>` deletes local task branches, so adding the same task after remove starts from the current local base again.

### `workbranch pull`

Direction: remote base -> local base.

For each repo:

```bash
cd _base/<repo>
git pull --ff-only origin <base-branch>
```

Safety:

- Fails before running if the local base worktree is dirty.
- Uses `--ff-only`; no merge commit is created.

### `workbranch update`

Direction: local base -> every task.

For each task and repo:

```bash
cd <task>/<repo>
git rebase <_base/<repo> HEAD>
```

Safety:

- Fails before running if the task worktree is dirty.
- Uses the local base worktree HEAD, not `origin/<base-branch>`.
- Fails before running if `_base/<repo>` is not checked out to the configured base branch.
- Fails before running if `_base/<repo>` has a rebase in progress.
- Conflict resolution is left to Git and the user.

### `workbranch update <task>`

Direction: local base -> one task.

For each repo in the task:

```bash
cd <task>/<repo>
git rebase <_base/<repo> HEAD>
```

Safety is the same as `workbranch update`.

### `workbranch land <task>`

Direction: task -> local base.

For each repo in the task:

```bash
cd _base/<repo>
git checkout <base-branch>
git pull --ff-only origin <base-branch>
git merge --ff-only <task-branch>
```

Safety:

- Fails before running if the task worktree or local base worktree is dirty.
- Uses `--ff-only`; no merge commit is created.
- Updates the local base from remote before landing the task.

### `workbranch push`

Direction: local base -> remote base.

For each repo:

```bash
cd _base/<repo>
git push origin <base-branch>
```

### `workbranch push <task>`

Direction: task -> remote task branch.

For each repo in the task:

```bash
cd <task>/<repo>
git push -u origin <task-branch>
```

## Branch naming

For each repo, task branch names are explicit values chosen at `workbranch add` or restore-time `workbranch resume` prompts. Defaults are derived from the configured base branch:

```text
base branch master       + task login + default prompt -> feature/login
base branch feature/cpq  + task task1 + default prompt -> feature/cpq-task1
base branch master       + task login + override tk/login -> tk/login
```

Chosen branches are persisted in `<task>/.workbranch.task`. Later commands resolve task branches in this order:

1. `REPO_BRANCH <repo> <branch>` in `<task>/.workbranch.task`
2. The existing task repo's current branch
3. The default branch rule above
