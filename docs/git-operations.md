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

Composite:
  sync        remote base -> local base, then local base -> task

Maintenance:
  doctor      inspect project health; --fix prunes stale worktree registrations

Optional:
  push <task> task        -> remote task branch
```

## Commands

### `workbranch add [<task>] [--from <ref>]`

Direction: base/source ref -> task worktree.

Before creating worktrees, `workbranch add [<task>] [--from <ref>]` resolves the task key, shows each repo's configured base branch, then prompts for that repo's task branch. Without `<task>`, it asks for task type and detail name and derives the recommended task key `type-detail`. In an interactive terminal, `workbranch add <detail>` enters that same flow with `<detail>` prefilled as the editable detail default. `workbranch add type-detail` remains a direct conventional shorthand. For conventional task keys, each repo derives its default branch from its configured base branch: `main`/`master`-style bases use `type/detail`, while parent feature bases such as `feature/cpq` use `feature/cpq-detail`. Non-interactive task keys without the conventional `type-` prefix keep legacy defaults for script compatibility. The chosen task branches are saved in `<task>/.workbranch.task`; the optional `--from` ref is only the starting source, is not stored as the task branch, and does not become a persistent `status` comparison baseline.

For each repo:

```bash
cd _base/<repo>
git fetch origin
git worktree add <task>/<repo> -b <task-branch> HEAD
```

With `--from <ref>`, workbranch fetches origin and resolves the source ref per repo. Bare refs such as `feat/x` prefer `origin/feat/x` when present; explicit `origin/feat/x`, `refs/...`, `HEAD`, and existing local refs are also accepted.

```bash
git fetch origin
git worktree add <task>/<repo> -b <task-branch> <resolved-source-ref>
```

If the task branch already exists locally or remotely, `workbranch add [<task>]` fails. For local task branches, run `workbranch remove <task>` to delete the local branch before adding again. For remote-only task branches, delete or rename the remote branch outside workbranch before adding again.

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

### `workbranch sync`

Direction: remote base -> local base, then local base -> every task.

For each repo, `workbranch sync` first validates that every target task workspace can be updated. If there are no task workspaces, or any target task worktree is dirty, missing, on the wrong branch, or has a rebase in progress, the command fails before pulling base branches.

After update preflight passes, sync runs the same base pull behavior as `workbranch pull`:

```bash
cd _base/<repo>
git pull --ff-only origin <base-branch>
```

Then it runs the same task rebase behavior as `workbranch update` for the task set collected before the pull:

```bash
cd <task>/<repo>
git rebase <_base/<repo> HEAD>
```

Safety:

- Fails before pulling if task updates cannot run.
- Pull failures abort before any task update.
- Uses existing pull and update Git operations; sync does not introduce a separate Git primitive.

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

### `workbranch doctor [--fix]`

Direction: inspect local filesystem and Git worktree metadata. With `--fix`, prune stale worktree registrations only.

`workbranch doctor` reports base worktree issues, partial task workspaces, stale task directories, and prunable worktree registrations. It is read-only by default and exits `0` only when no issues are found.

With `--fix`, for each in-scope base repo:

```bash
cd _base/<repo>
git worktree prune
```

Safety:

- `--fix` never deletes task directories or branches.
- Stale task directories are reported with `workbranch remove <task>` guidance.
- Base branch drift, dirty worktrees, rebases in progress, and partial workspaces are reported only.
- `--repo <repo>` scopes both diagnosis and pruning to that repo.

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

For each repo, task branch names are explicit values chosen at `workbranch add` prompts. Recommended task keys use `type-detail`; their default branch depends on each repo's configured base branch. Interactive `add <detail>` pre-fills that detail in the creation flow; non-interactive task keys without the conventional `type-` prefix keep the legacy defaults:

```text
base master       + task key feat-login -> feat/login
base feature/cpq  + task key feat-task1 -> feature/cpq-task1
base master       + non-interactive login -> feature/login
base feature/cpq  + non-interactive task1 -> feature/cpq-task1
task key feat-login      + override tk/login -> tk/login
```

Chosen branches are persisted in `<task>/.workbranch.task`. Later commands resolve task branches in this order:

1. `REPO_BRANCH <repo> <branch>` in `<task>/.workbranch.task`
2. The existing task repo's current branch
3. Stale Git worktree registration for manually removed task directories
4. The default branch rule above

## Removal

### `workbranch remove <task>`

Remove linked worktrees and local task branches for a task. Remote task branches are not deleted.

If the task worktree directory was removed manually, `workbranch remove <task>` still deletes the local task branch when workbranch can identify it from metadata, an existing task worktree, stale Git worktree registration, or the default branch rule.

Fails if any task worktree is dirty. Use `workbranch remove <task> --force` to discard dirty local task worktrees and local task branches.
