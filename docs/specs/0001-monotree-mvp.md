# 0001 Monotree MVP Spec

## Goal

Monotree creates one AI-friendly workspace from multiple independent Git repositories.

It keeps every repo as a normal Git repo, then uses `git worktree` so one task folder can contain linked worktrees for all repos.

```text
fullstack
├── .monotree.config
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

The config file is `.monotree.config` in the project root.

```text
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend git@github.com:example/frontend.git master
REPO backend git@github.com:example/backend.git feature/cpq
```

Format:

```text
REPO <name> <git-url> <base-branch>
```

Rules:

- `PROJECT_NAME` must be a safe directory name.
- `MAIN_WORKTREES_DIR` must be a safe directory name.
- `BRANCH_PREFIX` must be non-empty and contain no whitespace.
- `REPO` requires name, URL, and base branch.
- Repo names must be unique safe names.
- Git URLs and branch names must be non-empty and contain no whitespace.
- Config values are split on whitespace. Quoting is not supported.
- The file is not a shell script.

## Branch names

Task branch names are derived from the configured base branch.

```text
base branch master       + task login  -> feature/login
base branch feature/cpq  + task task1  -> feature/cpq-task1
```

Rule:

- If the base branch starts with `<BRANCH_PREFIX>/`, task branch is `<base-branch>-<task>`.
- Otherwise, task branch is `<BRANCH_PREFIX>/<task>`.

## Commands

### `monotree config`

Interactive config setup without cloning repos:

1. Ask for target directory, default `.`.
2. Ask for project name, default `fullstack`.
3. Ask for main worktrees directory, default `_base`.
4. Ask for default base branch, default `main`.
5. Ask for branch prefix, default `feature`.
6. Ask for one or more repos: name, Git URL, base branch.
7. Write `.monotree.config`.

### `monotree init`

Initialize main worktrees from config.

- If `.monotree.config` exists in the current directory, read it and clone each repo into `_base/<repo>` on its base branch.
- If `.monotree.config` does not exist, run the same interactive setup as `monotree config`, then clone repos.
- If cloning fails, remove paths created by the failed command.

### `monotree list`

Show configured repos, base branches, current branches, and task workspaces.

### `monotree status`

Show clean/dirty state for base worktrees and all task worktrees.

```text
[*] Base worktrees
    frontend    master           clean
    backend     master           untracked

[*] Task workspaces
[*] login
    frontend    feature/login    clean
    backend     feature/login    modified
```

### `monotree add <task>`

Create one task workspace with one linked worktree per repo.

For each repo:

1. Ensure `_base/<repo>` exists and is clean.
2. Derive the task branch name.
3. Fail if the branch or target path already exists.
4. Create a linked worktree at `<task>/<repo>`.

If any repo fails, roll back paths and branches created by the command.

### `monotree pull`

Update base worktrees from remote base branches.

For each repo:

```bash
cd _base/<repo>
git pull --ff-only origin <base-branch>
```

Fails if any base worktree is dirty.

### `monotree rebase`

Rebase every task worktree onto its remote base branch.

For each task and repo:

```bash
cd <task>/<repo>
git fetch origin
git rebase origin/<base-branch>
```

Fails if any target task worktree is dirty.

### `monotree rebase <task>`

Same as `monotree rebase`, but only for one task workspace.

### `monotree push`

Push base branches to origin.

For each repo:

```bash
cd _base/<repo>
git push origin <base-branch>
```

### `monotree push <task>`

Push task branches to origin.

For each repo in the task:

```bash
cd <task>/<repo>
git push -u origin <task-branch>
```

### `monotree merge <task>`

Fast-forward base branches from task branches. This must not create merge commits.

For each repo:

```bash
cd _base/<repo>
git checkout <base-branch>
git pull --ff-only origin <base-branch>
git merge --ff-only <task-branch>
```

This is useful when the base branch is already a parent feature branch, such as `feature/cpq`. Run `monotree push` afterward to push the updated base branch.

### `--repo <repo>`

Supported Git commands default to every configured repo. Add `--repo <repo>` to run one repo only.

Examples:

```bash
monotree pull --repo frontend
monotree rebase --repo frontend
monotree rebase login --repo frontend
monotree push --repo frontend
monotree push login --repo frontend
monotree merge login --repo frontend
```

### `monotree remove <task>`

Remove linked worktrees for a task without deleting branches.

Fails if any task worktree is dirty.

## Safety

- Do not overwrite existing config files, worktrees, or branches.
- Fail before destructive operations if a target worktree is dirty.
- Use `--ff-only` for pull and merge operations.
- On command-local creation failure, roll back paths and branches created by that command.
- Leave conflict resolution to Git and the user.

## Installer

`install.sh` copies `bin/monotree` to a target directory. The default is `~/.local/bin`.

If the target directory is not on `PATH`, the installer asks whether to add it to the user's shell profile.

- zsh: `~/.zshrc`
- bash: `~/.bash_profile`

If the user declines, print direct-run and manual PATH guidance.

## Acceptance checks

- `config` writes config without cloning base worktrees.
- `init` clones base worktrees from config, or writes config then clones when no config exists.
- `add` creates task worktrees with expected branch names.
- `status` shows base and task dirty state.
- `pull` fast-forwards base worktrees.
- `rebase` updates all task worktrees.
- `rebase <task>` updates one task workspace.
- `push` pushes base branches.
- `push <task>` pushes task branches.
- `merge <task>` fast-forwards local base branches without merge commits.
- `--repo <repo>` limits supported Git commands to one repo.
- `remove <task>` removes linked worktrees only.
- Dirty worktree checks prevent unsafe operations.
- Integration tests use temporary local bare remotes.
