# 0001 Workbranch MVP Spec

## Goal

Workbranch creates AI-friendly task workspaces for one repo or many independent Git repositories.

It keeps every repo as a normal Git repo, then uses `git worktree` so one task folder can contain linked worktrees for all configured repos.

```text
fullstack
├── .workbranch.config
├── _base
│   ├── frontend
│   └── backend
└── login
    ├── frontend
    └── backend
```

Run the AI agent from the task folder:

```bash
cd fullstack/login
codex
```

## Config

The config file is `.workbranch.config` in the project root.

```text
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature
TASK_SETUP sh scripts/workbranch-setup.sh

REPO frontend git@github.com:example/frontend.git master
REPO backend git@github.com:example/backend.git feature/cpq
```

Format:

```text
TASK_SETUP <command>
REPO <name> <git-url> <base-repo-branch>
```

Rules:

- `PROJECT_NAME` must be a safe directory name.
- `MAIN_WORKTREES_DIR` must be a safe directory name.
- `BRANCH_PREFIX` must be non-empty and contain no whitespace.
- `TASK_SETUP` is optional. It stores the command text after the directive.
- `REPO` requires name, URL, and base repo branch.
- Repo names must be unique safe names.
- Git URLs and branch names must be non-empty and contain no whitespace.
- Config values are split on whitespace except `TASK_SETUP`, which preserves the command text after the directive.
- The file is not a shell script.

## Branch names

Task branch names are derived from the configured base repo branch.

```text
base repo branch master       + task login  -> feature/login
base repo branch feature/cpq  + task task1  -> feature/cpq-task1
```

Rule:

- If the base repo branch starts with `<BRANCH_PREFIX>/`, task branch is `<base-branch>-<task>`.
- Otherwise, task branch is `<BRANCH_PREFIX>/<task>`.

Git operation internals are defined in [`docs/git-operations.md`](../git-operations.md).

## Commands

### `workbranch config`

Create or rewrite config without cloning repos.

If `.workbranch.config` or legacy `.tasktree.config` / `.monotree.config` already exists in the current project, rewrite it to `.workbranch.config` using the existing values. Legacy `WORKFLOW` directives are removed.

If no config exists, run interactive config setup:

1. Ask for target directory, default `.`.
2. Ask for project name, default `fullstack`.
3. Ask for main worktrees directory, default `_base`.
4. Ask for branch prefix, default `feature`.
5. Explain that each repo base repo branch is checked out in `_base/<repo>` and task branches are derived from it.
6. Ask for one or more repos: name, Git URL, base branch for this repo.
7. Write `.workbranch.config`.

### `workbranch init`

Initialize main worktrees from config.

- If `.workbranch.config` exists in the current directory, read it and clone each repo into `_base/<repo>` on its base repo branch. Legacy `.tasktree.config` / `.monotree.config` are also accepted and can be rewritten with `workbranch config`.
- If `.workbranch.config` does not exist, run the same interactive setup as `workbranch config`, then clone repos.
- If cloning fails, remove paths created by the failed command.

### `workbranch list`

Show configured repos, base branches, current branches, and task workspaces.

### `workbranch status`

Show commit position, clean/dirty state, and the next suggested action for task worktrees.

```text
[*] Base worktrees
    repo        branch           commit     status
    frontend    master           a1b2c3d4e  clean
    backend     master           f6e7d8c9a  untracked

[*] Task workspaces
[*] login
    repo        base       task       diff  status    next
    frontend    a1b2c3d4e  f6e7d8c9a  +3    clean     land
    backend     a1b2c3d4e  a1b2c3d4e  0     modified  -

[*] Next
    land    task has commits not in base: workbranch land <task>
    update  task is behind base: workbranch update <task>
```

### `workbranch add <task>`

Create one task workspace with one linked worktree per repo.

For each repo:

1. Ensure `_base/<repo>` exists and is clean.
2. Derive the task branch name.
3. Reuse an existing task branch when present, or create it from the base branch.
4. Create a linked worktree at `<task>/<repo>`.
5. Run `TASK_SETUP` when configured.

If any repo fails, roll back paths and branches created by the command.
If `TASK_SETUP` fails, keep created worktrees and tell the user to rerun `workbranch setup <task>`.

### `workbranch setup`

Add or change the optional task setup command in `.workbranch.config`.

### `workbranch setup --clear`

Remove the task setup command from `.workbranch.config`.

### `workbranch setup <task>`

Run the configured task setup command for an existing task workspace.

The setup command runs from the project root with these environment variables:

```text
WORKBRANCH_PROJECT_ROOT
WORKBRANCH_TASK
WORKBRANCH_TASK_DIR
WORKBRANCH_BASE_DIR
WORKBRANCH_REPOS
```

### `workbranch pull`

Update base worktrees from remote base branches.

For each repo:

```bash
cd _base/<repo>
git pull --ff-only origin <base-branch>
```

Fails if any base worktree is dirty.

### `workbranch update`

Update every task worktree from its local base worktree.

For each task and repo:

```bash
cd <task>/<repo>
git rebase <_base/repo HEAD>
```

Fails if any target task worktree is dirty.

### `workbranch update <task>`

Same as `workbranch update`, but only for one task workspace.

### `workbranch push`

Push base branches to origin.

For each repo:

```bash
cd _base/<repo>
git push origin <base-branch>
```

### `workbranch push <task>`

Push task branches to origin.

For each repo in the task:

```bash
cd <task>/<repo>
git push -u origin <task-branch>
```

### `workbranch land <task>`

Land task branches into base branches. This must not create merge commits.

For each repo:

```bash
cd _base/<repo>
git checkout <base-branch>
git pull --ff-only origin <base-branch>
git merge --ff-only <task-branch>
```

This is useful when the base repo branch is already a parent feature branch, such as `feature/cpq`. Run `workbranch push` afterward to push the updated base repo branch.

### `--repo <repo>`

Git operations default to every configured repo. Add `--repo <repo>` to limit the operation to one repo.

Examples:

```bash
workbranch pull --repo frontend
workbranch update --repo frontend
workbranch update login --repo frontend
workbranch push --repo frontend
workbranch push login --repo frontend
workbranch land login --repo frontend
```

### `workbranch remove <task>`

Remove linked worktrees for a task without deleting branches.

Fails if any task worktree is dirty.

## Safety

- Do not overwrite existing worktrees or branches.
- `workbranch config` may rewrite an existing `.workbranch.config` to the current format without cloning repos.
- Fail before destructive operations if a target worktree is dirty.
- Use `--ff-only` for pull and merge operations.
- On command-local creation failure, roll back paths and branches created by that command.
- Leave conflict resolution to Git and the user.

## Installer

`install.sh` copies `bin/workbranch` to a target directory. The default is `~/.local/bin`.

If the target directory is not on `PATH`, the installer asks whether to add it to the user's shell profile.

- zsh: `~/.zshrc`
- bash: `~/.bash_profile`

If the user declines, print direct-run and manual PATH guidance.

## Acceptance checks

- `config` writes config without cloning base worktrees.
- `init` clones base worktrees from config, or writes config then clones when no config exists.
- `add` creates task worktrees with expected branch names.
- `status` shows base/task commits, diff, and dirty state.
- `pull` fast-forwards base worktrees.
- `update` updates all task worktrees.
- `update <task>` updates one task workspace.
- `push` pushes base branches.
- `push <task>` pushes task branches.
- `land <task>` lands task branches into local base branches without merge commits.
- `--repo <repo>` limits supported Git commands to one repo.
- `remove <task>` removes linked worktrees only.
- Dirty worktree checks prevent unsafe operations.
- Integration tests use temporary local bare remotes.
