# Monotree MVP Implementation Plan

## Source Contract

- Spec: `docs/specs/0001-monotree-mvp.md`
- Goal: implement a Bash CLI that manages multiple independent Git repositories as one task-local AI workspace.

## Resolved Decision Gates

- Runtime: `#!/usr/bin/env bash`, compatible with macOS Bash 3.2.
- Config format: line-oriented declarative `.monotree/config`; do not `source` config files.
- Failure policy: preflight-first and command-local rollback of resources created by the current invocation only.
- Dirty worktree policy: no force behavior in MVP; dirty base/task repos fail with clear errors before destructive or history-changing operations.
- Branch collision policy: `monotree add <task>` fails the whole command if the target feature branch already exists in any configured repository.
- Init scope: support both existing-config initialization and interactive setup; implement config-first, interactive-second.
- Implementation layout: `bin/monotree`, `install.sh`, `tests/run.sh`.
- Test strategy: dependency-free integration tests using temporary local bare remotes and real Git operations.

## File Layout

```text
bin/monotree
install.sh
tests/run.sh
```

## Implementation Phases

### Phase 1 — CLI skeleton and shared utilities

- Create `bin/monotree` with Bash 3.2-compatible structure.
- Implement command dispatch and help output.
- Implement `die`, `info`, path helpers, name validation, and project-root detection.
- Implement declarative config parser.

Acceptance checks:

- Unknown command fails clearly.
- Commands outside a monotree project fail clearly, except `init` interactive setup.
- Invalid config lines fail clearly without executing shell code.

### Phase 2 — `init`

- Existing config path:
  - detect `.monotree/config` in current directory
  - parse config
  - clone each repo into `<base_dir>/<repo>`
- Interactive path:
  - ask project name, base dir, default base branch, branch prefix, and repo entries
  - create project root and `.monotree/config`
  - reuse the existing config initialization path
- Track created paths for rollback.

Acceptance checks:

- Existing config initializes `_base` clones.
- Interactive setup writes the declarative config format.
- Failed clone rolls back only paths created by that invocation.

### Phase 3 — `add` and `list`

- Implement `add <task>`:
  - validate task name
  - preflight target task directory and target branch collisions across all repos
  - fetch each base repo
  - create task worktrees using `<branch_prefix>/<task>`
  - rollback command-created worktrees/directories on failure
- Implement `list`:
  - show base directory
  - show configured repositories
  - show detected task directories
  - show current branch for each repo worktree when available

Acceptance checks:

- `add login` creates one worktree per repo.
- Duplicate `add login` fails clearly.
- Existing branch in any repo fails the whole `add`.
- `list` distinguishes base, tasks, repos, and branches.

### Phase 4 — `sync`, `update`, `push`, `remove`

- Implement `sync`:
  - fail on dirty base repos
  - run fast-forward-only pull for each base repo
- Implement `update <task>`:
  - fail on dirty task repos
  - fetch and rebase each task repo onto its configured remote base branch
  - stop and report repo path on conflict
- Implement `push <task>`:
  - push each task repo branch to origin with upstream
- Implement `remove <task>`:
  - do not force dirty worktrees
  - remove each configured repo worktree
  - remove empty task directory
  - do not delete branches

Acceptance checks:

- `sync` updates base repos only.
- `update login` rebases task branches onto updated remote base refs.
- `push login` creates or updates remote feature branches.
- `remove login` removes worktrees and leaves branches intact.

### Phase 5 — installer

- Create `install.sh`.
- Install `bin/monotree` to `${HOME}/.local/bin/monotree`.
- Create `${HOME}/.local/bin` if missing.
- Mark installed executable as executable.
- Check whether `${HOME}/.local/bin` is on `PATH` after installation.
- If not on `PATH`, print a warning with zsh/bash guidance.
- Do not automatically edit shell startup files in the MVP.

Acceptance checks:

- Installer places the CLI at `~/.local/bin/monotree`.
- Installed CLI can print help and run commands.
- Installer warns when the install directory is not on `PATH`.

TODO: Revisit public-distribution PATH onboarding after MVP, including `--prefix`, Homebrew, or opt-in shell-profile updates.

### Phase 6 — integration tests

- Create `tests/run.sh` with no external test framework dependency.
- Use `mktemp -d` and local bare Git remotes.
- Configure local Git user name/email inside fixtures.
- Exercise real Git `clone`, `worktree`, `pull --ff-only`, `rebase`, `push`, and `worktree remove`.

Core scenarios:

- valid and invalid config parsing
- `init` with existing config
- `add login`
- duplicate `add login`
- `list`
- `sync`
- `update login`
- `push login`
- `remove login`
- dirty worktree safety for `sync`, `update`, and `remove`

## Follow-ups Outside MVP

- Restore or attach workspaces from existing feature branches.
- Explicit `--force` or branch deletion options.
- Pull request creation.
- Homebrew tap.
- Package-manager workspace integration.
