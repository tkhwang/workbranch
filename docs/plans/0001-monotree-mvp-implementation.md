# Monotree MVP Implementation Plan

## Source Contract

- Spec: `docs/specs/0001-monotree-mvp.md`
- Goal: implement a Bash CLI that manages multiple independent Git repositories as one task-local AI workspace.

## Resolved Decision Gates

- Runtime: `#!/usr/bin/env bash`, compatible with macOS Bash 3.2.
- Config format: line-oriented declarative `.monotree.config`; do not `source` config files.
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
  - detect `.monotree.config` in current directory
  - parse config
  - clone each repo into the configured main worktrees directory, `<MAIN_WORKTREES_DIR>/<repo>`
- Interactive path:
  - ask target directory, project name, main worktrees directory, default main branch, branch prefix, and repo entries
  - ask each repo's workflow: `free`, `feature` (`main -> feature -> PR -> main`), or `stacked` (`feature -> feature-1 -> feature`)
  - create project root under the selected target directory and write `.monotree.config`
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
  - create task worktrees using workflow-specific branch names: `<BRANCH_PREFIX>/<task>` for free/feature and `<parent-feature-branch>-<task>` for stacked
  - rollback command-created worktrees/directories on failure
- Implement `list`:
  - show main worktrees directory
  - show configured repositories
  - show detected task directories
  - show current branch for each repo worktree when available

Acceptance checks:

- `add login` creates one worktree per repo.
- Duplicate `add login` fails clearly.
- Existing branch in any repo fails the whole `add`.
- `list` distinguishes base, tasks, repos, and branches.

### Phase 4 — `pull`, `rebase`, `push`, `merge`, `remove`

- Implement `pull`:
  - fail on dirty base repos
  - run fast-forward-only pull for each base repo
- Implement `rebase <task>`:
  - fail on dirty task repos
  - fetch and rebase each task repo onto its configured remote workflow base branch
  - stop and report repo path on conflict
- Implement `push <task>`:
  - operate on feature workflow repos only
  - push each feature task repo branch to origin with upstream for pull requests
  - fail if no feature workflow repo exists in the task
- Implement `merge <task>`:
  - operate on stacked workflow repos only
  - fail if no stacked workflow repo exists in the task
  - fail on dirty stacked task or stacked base repos
  - merge each local stacked task branch into its parent feature branch from the main worktree
  - push each stacked parent feature branch to origin from the main worktree
- Implement `remove <task>`:
  - do not force dirty worktrees
  - remove each configured repo worktree
  - remove empty task directory
  - do not delete branches

Acceptance checks:

- `pull` updates base repos only.
- `rebase login` rebases task branches onto updated remote workflow base refs.
- `push login` creates or updates remote task branches for feature workflow repos only.
- `merge login` rejects non-stacked tasks and pushes stacked parent feature branches from main worktrees.
- `remove login` removes worktrees and leaves branches intact.

### Phase 5 — installer

- Create `install.sh`.
- Ask for a target directory, defaulting to `${HOME}/.local/bin`.
- Install `bin/monotree` to `<target-directory>/monotree`.
- Create the chosen target directory if missing.
- Mark installed executable as executable.
- Check whether the chosen target directory is on `PATH` after installation.
- If not on `PATH`, ask whether to add it now.
- If accepted, append the chosen target directory to `~/.zshrc` for zsh or `~/.bash_profile` for bash.
- If declined, print direct-run and manual PATH guidance.
- Do not automatically edit shell startup files without confirmation.
- Do not auto-edit startup files for shells other than zsh/bash in the MVP.

Acceptance checks:

- Installer defaults to `~/.local/bin/monotree`.
- Installer can install to a custom target directory.
- Installed CLI can print help and run commands.
- Installer warns when the chosen install directory is not on `PATH`.
- Installer can append a PATH entry to `~/.zshrc` after confirmation.
- Installer prints direct-run guidance when PATH setup is declined.

TODO: Revisit public-distribution install target and PATH onboarding after MVP, including non-interactive `--prefix`, Homebrew, or broader shell-profile support.

### Phase 6 — integration tests

- Create `tests/run.sh` with no external test framework dependency.
- Use `mktemp -d` and local bare Git remotes.
- Configure local Git user name/email inside fixtures.
- Exercise real Git `clone`, `worktree`, `pull --ff-only`, `rebase`, `merge --ff-only`, `push`, and `worktree remove`.

Core scenarios:

- valid and invalid config parsing
- `init` with existing config
- `add login`
- duplicate `add login`
- `list`
- `pull`
- `rebase login`
- `push login`
- `merge login`
- `remove login`
- dirty worktree safety for `pull`, `rebase`, stacked `merge`, and `remove`

## Follow-ups Outside MVP

- Restore or attach workspaces from existing feature branches.
- Explicit `--force` or branch deletion options.
- Pull request creation.
- Homebrew tap.
- Package-manager workspace integration.
