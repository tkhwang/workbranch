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

For each repo:

```bash
cd _base/<repo>
git fetch origin
git worktree add <task>/<repo> -b <task-branch> HEAD
```

If the task branch already exists locally, reuse it:

```bash
cd _base/<repo>
git worktree add <task>/<repo> <task-branch>
```

Safety:

- Rolls back worktrees and new branches created by the command if repo setup fails.
- Uses the local base worktree HEAD, not `origin/<base-branch>`.
- Reuses existing task branches so removed worktrees can be recreated.

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

For each repo, task branch names are derived from the configured base branch:

```text
base branch master       + task login -> feature/login
base branch feature/cpq  + task task1 -> feature/cpq-task1
```
