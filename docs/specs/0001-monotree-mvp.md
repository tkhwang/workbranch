# Monotree MVP Spec

## Goal

Monotree is a shell-based CLI utility that lets a user work with multiple independent Git repositories as one AI-friendly workspace.

The primary use case is a full-stack task where frontend and backend live in separate repositories, but the user wants to run an AI coding assistant from one task directory and mention files naturally as `@frontend/...` and `@backend/...`.

Monotree uses Git worktrees internally so multiple feature tasks can be developed in parallel without manually cloning or wiring every repository for each task.

## Non-Goals for MVP

- Monotree does not turn repositories into a real Git monorepo.
- Monotree does not rewrite repository history.
- Monotree does not manage package manager workspaces.
- Monotree does not create pull requests in the MVP.
- Monotree does not require a fixed frontend/backend repository pair; any number of repositories may be configured.

## Directory Layout

A monotree project has one top-level project directory.

```text
/fullstack
  /.monotree
    config
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

`_base` contains the base worktree for each configured repository.

It is named `_base` instead of `base` so it sorts near the top in common file browsers and terminal listings while remaining visible.

Base repositories are used as stable reference checkouts for each repo's base branch. They are not the primary place for feature development.

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
/fullstack/.monotree/config
```

The format is intentionally close to a simple `.env`/shell config file.

Example:

```bash
PROJECT_NAME=fullstack
BASE_DIR=_base
BASE_BRANCH=master
BRANCH_PREFIX=feature
REPOS="frontend backend"

frontend="git@github.com:example/frontend.git master"
backend="git@github.com:example/backend.git master"
```

### Config Fields

- `PROJECT_NAME`: Human-readable project name and default root directory name during interactive setup.
- `BASE_DIR`: Directory name for base worktrees. Default: `_base`.
- `BASE_BRANCH`: Default base branch for repositories. Default: `main` unless the user enters another value.
- `BRANCH_PREFIX`: Default branch prefix for tasks. Default: `feature`.
- `REPOS`: Space-separated list of repository names.
- `<repoName>`: Per-repository config value in the form `<git-url> <base-branch>`.

A repository may use the global `BASE_BRANCH` by accepting the default during interactive setup. The generated config should still write the resolved branch explicitly for each repo so later commands do not need inference.

Repository names must be directory-safe and match:

```text
[A-Za-z0-9._-]+
```

Task names must also match:

```text
[A-Za-z0-9._-]+
```

The generated Git branch name may contain `/` because it is built from `BRANCH_PREFIX/task-name`.

## Commands

### `monotree init`

Initializes a monotree project.

Execution location rules:

- If the current directory already contains `.monotree/config`, treat the current directory as the project root and initialize from that config.
- If no config exists, interactive setup creates a new project directory named from `PROJECT_NAME` under the current working directory.
- The MVP does not initialize into an arbitrary non-empty current directory unless that directory already has `.monotree/config`.

Behavior:

1. Detect whether the current directory already has `.monotree/config`.
2. If config exists, read it and initialize `_base` from it.
3. If no config exists, run an interactive setup.
4. Ask for:
   - project name
   - base directory, default `_base`
   - default base branch
   - branch prefix, default `feature`
   - one or more repositories
5. For each repository, ask for:
   - repo name
   - Git URL
   - base branch, defaulting to the global base branch
6. Create the project root directory when running interactive setup without an existing config.
7. Create the project structure.
8. Clone each configured repository into `BASE_DIR/<repoName>`.
9. Write `.monotree/config`.

MVP clone strategy:

```text
/fullstack/_base/<repoName>
```

is a normal Git clone, not a bare repository hidden under `.monotree`.

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

Default branch naming:

```text
<BRANCH_PREFIX>/<task>
```

With the default config:

```text
feature/login
```

For each repository, Monotree creates a worktree from that repository's remote base branch.

Conceptual command:

```bash
git -C _base/frontend fetch origin
git -C _base/frontend worktree add ../../login/frontend -b feature/login origin/master
```

If the target task directory or branch already exists, MVP behavior is to fail with a clear error instead of reusing or overwriting anything.

### `monotree list`

Lists detected task directories and configured repositories.

MVP output should distinguish:

- base directory
- task directories
- repository names
- current branch for each repo worktree when available

### `monotree sync`

Updates all base worktrees from their configured remotes using fast-forward-only pulls.

Conceptual command per repository:

```bash
git -C _base/frontend pull --ff-only origin master
```

`sync` is for base branches only. It should not modify task worktrees.

### `monotree update <task>`

Rebases each repository worktree inside a task onto that repository's latest remote base branch.

Conceptual command per repository:

```bash
git -C login/frontend fetch origin
git -C login/frontend rebase origin/master
```

This preserves the normal feature-branch workflow while keeping each task current with its base branch.

If a rebase conflict occurs, Monotree stops and reports the repository path that needs manual resolution.

### `monotree push <task>`

Pushes each repository worktree inside a task to its configured remote.

Conceptual command per repository:

```bash
git -C login/frontend push -u origin feature/login
```

Push happens from feature/task worktrees, not from `_base`.

### `monotree remove <task>`

Removes task worktrees for each configured repository.

MVP behavior:

- remove worktrees
- remove the empty task directory
- do not delete local or remote branches by default

Branch deletion may be added later as an explicit option such as `--delete-branch`.

## Git Flow

The intended flow is:

```text
origin/master
   ↓ sync
_base/frontend       branch: master
   ↓ add/update
login/frontend       branch: feature/login
   ↓ push
origin/feature/login
```

Rules:

- `_base/<repo>` tracks and updates the configured base branch.
- Feature/task worktrees use their own branches.
- Base updates use fast-forward-only pull.
- Task updates use rebase onto the remote base branch.
- Feature branches are pushed from task worktrees.

This matches common Git worktree usage: the base worktree is a reference checkout, while task worktrees are where feature development and feature branch pushes happen.

## Project Root Detection

Monotree commands should work from the project root or from inside a task/repository subdirectory.

A command locates the project root by walking upward until it finds:

```text
.monotree/config
```

If no config is found, the command fails with a clear message.

## Distribution

MVP distribution uses a curl-based installer.

Example:

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/monotree/main/install.sh | bash
```

The installer places the executable at:

```text
~/.local/bin/monotree
```

The CLI is invoked as:

```bash
monotree init
monotree add login
monotree list
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
2. Run `monotree init` and create a compact `.monotree/config` interactively.
3. Initialize `_base` clones for an arbitrary set of repositories.
4. Run `monotree add login` and get one task worktree per configured repository.
5. Start an AI assistant from the task directory and access all repos through simple relative paths.
6. Run `monotree sync` to update base repositories.
7. Run `monotree update login` to rebase task branches onto their remote base branches.
8. Run `monotree push login` to push feature branches.
9. Run `monotree list` to inspect configured repos and task workspaces.
10. Run `monotree remove login` to remove task worktrees without deleting branches by default.
