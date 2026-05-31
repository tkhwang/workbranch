# Monotree MVP Spec

## Goal

Monotree is a shell-based CLI utility that lets a user work with multiple independent Git repositories as one AI-friendly workspace.

The primary use case is a full-stack task where frontend and backend live in separate repositories, but the user wants to run an AI coding assistant from one task directory and mention files naturally as `@frontend/...` and `@backend/...`.

Monotree uses Git worktrees internally so multiple feature tasks can be developed in parallel without manually cloning or wiring every repository for each task.

## Runtime

The MVP CLI is a single `bash` executable.

Runtime constraints:

- Use `#!/usr/bin/env bash`.
- Stay compatible with macOS default Bash 3.2.
- Do not require Bash 4+ features such as associative arrays.
- Users may invoke `monotree` from any interactive shell, including `zsh`; the implementation runtime remains Bash.

## Non-Goals for MVP

- Monotree does not turn repositories into a real Git monorepo.
- Monotree does not rewrite repository history.
- Monotree does not manage package manager workspaces.
- Monotree does not create pull requests in the MVP.
- Monotree does not require a fixed frontend/backend repository pair; any number of repositories may be configured.
- Monotree does not reuse existing feature branches when creating a new task workspace.
- Monotree does not provide force cleanup options in the MVP.

## Directory Layout

A monotree project has one top-level project directory.

```text
/fullstack
  /.monotree.config
  /_base
    /frontend
    /backend
  /login
    /frontend
    /backend
  /payment
    /frontend
    /backend
```

### `_base`

`_base` contains the main worktree for each configured repository.

It is named `_base` instead of `base` so it sorts near the top in common file browsers and terminal listings while remaining visible.

Main worktrees are used as stable reference checkouts for each repo's workflow base branch. They are not the primary place for feature development.

### Task Directories

Each task directory contains one worktree per configured repository.

Example:

```text
/fullstack/login/frontend
/fullstack/login/backend
```

The expected AI workflow is:

```bash
cd /fullstack/login
codex
# or claude
```

From there, the AI assistant sees a compact task-local workspace:

```text
./frontend
./backend
```

## Configuration

Configuration is stored at:

```text
/fullstack/.monotree.config
```

The format is a small line-oriented declarative format. It is not shell code and must not be loaded with `source`.

Example:

```text
# Monotree config
# You may edit this file manually.
# This file is read by monotree. It is not a shell script.

PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

# REPO <name> <git-url>
# WORKFLOW <repo-name> free <base-branch>
# WORKFLOW <repo-name> feature <main-branch>
# WORKFLOW <repo-name> stacked <parent-feature-branch>
REPO frontend git@github.com:example/frontend.git
WORKFLOW frontend feature master
REPO backend git@github.com:example/backend.git
WORKFLOW backend stacked feature/cpq
```

### Config Directives

Supported directives:

```text
PROJECT_NAME <name>
MAIN_WORKTREES_DIR <dir>
BRANCH_PREFIX <prefix>
REPO <repo-name> <git-url>
WORKFLOW <repo-name> free <base-branch>
WORKFLOW <repo-name> feature <main-branch>
WORKFLOW <repo-name> stacked <parent-feature-branch>
```

Parsing rules:

- Blank lines are allowed.
- Lines beginning with `#` are comments.
- Unknown directives fail with a clear error.
- Duplicate singleton directives fail with a clear error.
- Duplicate `REPO` names fail with a clear error.
- Every `REPO` must have exactly one `WORKFLOW`.
- Values do not support shell expansion, command substitution, or general shell quoting.
- `REPO` lines are the only source of the configured repository list.

Validation rules:

- `PROJECT_NAME`, `MAIN_WORKTREES_DIR`, repository names, and task names must match:

  ```text
  [A-Za-z0-9._-]+
  ```

- `BRANCH_PREFIX` must be non-empty and must not contain whitespace.
- `git-url` must be non-empty and must not contain whitespace.
- `WORKFLOW` must be `free`, `feature`, or `stacked`.
- workflow branch values must be non-empty and must not contain whitespace.

A repository may use the interactive setup's default main branch. The generated config still writes the resolved workflow branch explicitly on each `WORKFLOW` line so later commands do not need inference.

The generated Git branch name may contain `/` because it is built from `BRANCH_PREFIX/task-name`.

## Commands

### `monotree init`

Initializes a monotree project.

Execution location rules:

- If the current directory already contains `.monotree.config`, treat the current directory as the project root and initialize from that config.
- If no config exists, interactive setup asks for a target directory, default `.`, then creates a new project directory named from `PROJECT_NAME` under that target directory.
- The MVP does not initialize into an arbitrary non-empty current directory unless that directory already has `.monotree.config`.

Behavior:

1. Detect whether the current directory already has `.monotree.config`.
2. If config exists, read it and initialize `_base` from it.
3. If no config exists, run an interactive setup.
4. Ask for:
   - target directory, default `.`, where the project directory is created
   - project name
   - main worktrees directory, default `_base`
   - default main branch, default `main`
   - branch prefix, default `feature`
   - one or more repositories
5. For each repository, ask for:
   - repo name
   - Git URL
   - workflow, default `free`
   - for `free`: base branch, defaulting to the interactive default main branch
   - for `feature`: main branch, defaulting to the interactive default main branch
   - for `stacked`: parent feature branch
6. Create the project root directory under the selected target directory when running interactive setup without an existing config.
7. Create the project structure.
8. Write `.monotree.config` using the declarative config format.
9. Clone each configured repository into the configured main worktrees directory, `MAIN_WORKTREES_DIR/<repoName>`.

MVP clone strategy:

```text
/fullstack/_base/<repoName>
```

is a normal Git clone, not a bare repository hidden under the config file or another metadata directory.

Rationale: normal clones are easier to understand, inspect, and debug for an early shell-based CLI.

### `monotree add <task>`

Creates a task workspace containing one worktree per configured repository.

Example:

```bash
monotree add login
```

Creates:

```text
/fullstack/login/frontend
/fullstack/login/backend
```

Default task branch naming:

```text
feature/free workflow: <BRANCH_PREFIX>/<task>
stacked workflow:      <parent-feature-branch>-<task>
```

With the default config and a stacked parent `feature/cpq`:

```text
feature/login
feature/cpq-ui
```

For each repository, Monotree creates a worktree from that repository's workflow base branch.

Workflow rules:

```text
feature flow : main -> feature -> PR -> main
stacked flow : feature -> feature-1 -> feature
```

For `free`, the workflow base is used only to create and update worktrees; use Git directly for publishing.
For `feature`, the workflow base is the configured main branch. Monotree does not merge feature workflow branches into main; use the Git hosting pull request flow.
For `stacked`, the workflow base and merge target are the configured parent feature branch.

Conceptual command:

```bash
git -C _base/frontend fetch origin
git -C _base/frontend worktree add ../../login/frontend -b feature/login origin/master
```

If the target task directory or branch already exists, MVP behavior is to fail with a clear error instead of reusing or overwriting anything.

Branch collision policy:

- If the target feature branch already exists in any configured repository, the whole `add` command fails.
- MVP `add` does not check out or reuse existing feature branches.
- Existing-branch restoration may be added later as an explicit command or option.

### `monotree list`

Lists detected task directories and configured repositories.

MVP output should distinguish:

- main worktrees directory
- task directories
- repository names
- current branch for each repo worktree when available

### `monotree pull`

Updates all base worktrees from their configured remotes using fast-forward-only pulls.

Conceptual command per repository:

```bash
git -C _base/frontend pull --ff-only origin master
```

`pull` is for workflow base branches only. It should not modify task worktrees. Free workflow repos are skipped because users manage Git directly there.

### `monotree rebase <task>`

Rebases each repository worktree inside a task onto that repository's latest remote workflow base branch.

Conceptual command per repository:

```bash
git -C login/frontend fetch origin
git -C login/frontend rebase origin/master
```

This keeps each task current with its workflow base branch.

If a rebase conflict occurs, Monotree stops and reports the repository path that needs manual resolution.

### `monotree push <task>`

Pushes feature workflow repository worktrees inside a task to their own remote task branches for pull requests.

Conceptual command per repository:

```bash
git -C login/frontend push -u origin feature/login
```

Push happens from feature/task worktrees, not from `_base`.

`push` is feature-workflow only:

- `feature`: pushes `feature/login` from `login/<repo>` to `origin/feature/login`.
- `stacked`: skipped because local stacked child branches such as `feature/cpq-1` are not published directly.
- If a task has no feature workflow repos, `push` fails with a clear error.

### `monotree merge <task>`

Merges each local stacked task branch into its parent feature branch from the main worktree, then pushes the parent feature branch.

`merge` is stacked-only:

- `feature` workflow repos are skipped because feature branches should go through the Git hosting pull request flow.
- `free` workflow repos are skipped because users manage Git directly there.
- If a task has no stacked workflow repos, `merge` fails with a clear error.
- The parent feature branch push is run from `MAIN_WORKTREES_DIR/<repo>`, not from the task worktree.

Conceptual command per repository:

```bash
git -C _base/frontend checkout feature/cpq
git -C _base/frontend pull --ff-only origin feature/cpq
git -C _base/frontend merge --ff-only feature/cpq-1
git -C _base/frontend push origin feature/cpq
```

For stacked flow:

```text
feature/cpq -> feature/cpq-ui -> feature/cpq
```

`merge` is the command that updates `feature/cpq`. Local stacked child branches such as `feature/cpq-1` are not pushed directly.

### `monotree remove <task>`

Removes task worktrees for each configured repository.

MVP behavior:

- remove worktrees
- remove the empty task directory
- do not delete local or remote branches by default
- do not force remove dirty worktrees

Branch deletion may be added later as an explicit option such as `--delete-branch`.

## Safety and Failure Policy

Mutation commands use a preflight-first, command-local rollback policy.

Rules:

- Before mutating, commands validate names, config, expected repository paths, target paths, and known branch collisions when applicable.
- If a command fails after creating new files, directories, clones, or worktrees, Monotree removes only resources created by that command invocation.
- Monotree does not remove or alter pre-existing user resources during rollback.
- If rollback also fails, Monotree reports the remaining paths that require manual cleanup.

Dirty worktree policy:

- `pull` fails before pulling if any base repository is dirty.
- `rebase <task>` fails before rebasing if any target task repository is dirty.
- `merge <task>` fails if any stacked workflow base repository or stacked workflow task repository is dirty.
- `remove <task>` does not remove dirty worktrees.
- MVP has no `--force` option.

## Git Flow

The intended flow is:

```text
feature flow:

origin/master
   ↓ pull
_base/frontend       branch: master
   ↓ add/rebase
login/frontend       branch: feature/login
   ↓ push
origin/feature/login
   ↓ pull request outside monotree
origin/master

stacked flow:

origin/feature/cpq
   ↓ pull
_base/frontend       branch: feature/cpq
   ↓ add/rebase
ui/frontend          branch: feature/cpq-ui
   ↓ merge
origin/feature/cpq
```

Rules:

- `_base/<repo>` tracks and updates the configured workflow base branch.
- Feature/task worktrees use their own branches.
- Base updates use fast-forward-only pull.
- Task updates use rebase onto the remote workflow base branch.
- Feature workflow branches are pushed from task worktrees.
- Local stacked child branches are not pushed directly.
- Stacked workflow target branches are updated only by `merge`, which pushes from main worktrees.
- Feature workflow target branches are not updated by Monotree; use pull requests.

This matches common Git worktree usage: the base worktree is a reference checkout, while task worktrees are where feature development and feature branch pushes happen.

## Project Root Detection

Monotree commands should work from the project root or from inside a task/repository subdirectory.

A command locates the project root by walking upward until it finds:

```text
.monotree.config
```

If no config is found, the command fails with a clear message.

## Distribution

MVP distribution uses a curl-based installer.

Example:

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/monotree/main/install.sh | bash
```

The installer asks for a target directory and defaults to:

```text
~/.local/bin
```

With the default answer, the executable is installed at:

```text
~/.local/bin/monotree
```

Installer PATH behavior:

- The installer must not assume the chosen target directory is already on every user's `PATH`.
- MVP installer behavior is to install the executable, then check whether the chosen install directory is on `PATH`.
- If the chosen directory is not on `PATH`, the installer asks before editing any shell startup file.
- When the user answers yes, zsh writes to `~/.zshrc` and bash writes to `~/.bash_profile`.
- Other shells do not receive automatic profile edits in the MVP.
- PATH guidance must use the chosen target directory, not a hardcoded default.
- If the user declines profile edits, the installer prints direct-run and manual PATH guidance.

TODO: Revisit install target and PATH onboarding before public distribution. Options include a non-interactive `--prefix`, Homebrew packaging, or broader shell-profile support.

The CLI is invoked as:

```bash
monotree init
monotree add login
monotree list
monotree pull
monotree rebase login
monotree push login
monotree merge cpq-1   # stacked workflow only
monotree remove login
```

A Homebrew tap can be added after the CLI stabilizes.

Future Homebrew usage:

```bash
brew tap <owner>/monotree
brew install monotree
```

## MVP Success Criteria

The MVP is successful when a user can:

1. Install `monotree` as a shell command.
2. Run `monotree init` and create a compact `.monotree.config` interactively.
3. Initialize `_base` clones for an arbitrary set of repositories.
4. Run `monotree add login` and get one task worktree per configured repository.
5. Start an AI assistant from the task directory and access all repos through simple relative paths.
6. Run `monotree pull` to update base repositories.
7. Run `monotree rebase login` to rebase task branches onto their remote workflow base branches.
8. Run `monotree push login` to push feature workflow task branches for pull requests.
9. Run `monotree merge cpq-1` to merge stacked task branches into parent feature branches and push the parents.
10. Run `monotree list` to inspect configured repos and task workspaces.
11. Run `monotree remove login` to remove task worktrees without deleting branches by default.
12. Run the local integration test suite without external network access.
