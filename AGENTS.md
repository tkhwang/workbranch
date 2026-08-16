# Repository Guidelines

## Project Structure & Module Organization

This repository is a Bash CLI for managing Git worktree task spaces. Edit source modules under `src/workbranch/`; `bin/workbranch` is the generated single-file distribution. Keep the generation order in `scripts/workbranch-sources.txt`. Tests live in `tests/run.sh` and build tooling lives in `scripts/`. User-facing docs are in `README.md`, with design notes under `docs/architecture.md`, Git behavior in `docs/git-operations.md`, specs in `docs/specs/`, and implementation plans in `docs/plans/`. Packaging assets, such as the Homebrew formula, live in `packaging/`.

## Build, Test, and Development Commands

- `scripts/build-workbranch.sh`: rebuilds `bin/workbranch` from `src/workbranch/**` and runs `bash -n` on the generated file.
- `./tests/run.sh`: runs the integration suite against temporary Git remotes and checks that `bin/workbranch` is up to date.
- `/bin/bash -n bin/workbranch install.sh tests/run.sh`: fast syntax check for the main executable, installer, and test runner.
- `git diff --check`: catches whitespace errors before commit.

## Coding Style & Naming Conventions

Write portable Bash with explicit quoting, small functions, and clear failure paths. Existing code uses snake_case function names such as `preflight_require_clean` and `cmd_add`. Keep user-facing status messages consistent with the current prefixes: `[*]` for progress, `[+]` for success, and `[-] Error:` for failures. Do not edit `bin/workbranch` directly; change `src/workbranch/**`, then rebuild.

## Testing Guidelines

Add integration coverage in `tests/run.sh` for CLI behavior, Git safety checks, config parsing, and generated-file freshness. Name tests as `test_<behavior>` and run them through the existing `run_test` harness. Prefer temporary repos and bare remotes, as the current suite does, so tests do not depend on local Git state.

## Commit & Pull Request Guidelines

Use plain Conventional Commit style with scopes, without emoji prefixes, for example `feat(config): add repo-level setup commands` and `fix(validation): improve name validation`. Keep commit subjects short and action-oriented. Pull requests should state the user-visible behavior, list touched commands or files, and include verification output from `./tests/run.sh` plus any syntax or diff checks.

## Agent-Specific Instructions

For generated-surface changes, update source first, rebuild `bin/workbranch`, then verify both syntax and tests. Keep docs and specs synchronized when command behavior changes.
When updating generated task guidance, keep task status values synchronized as `todo | planning | in-progress | review | blocked | done`. Update only the `status:` line when the stage changes through `todo → planning → in-progress → review → done`; meaningful work, including planning, moves `todo` to `planning` immediately. `blocked` is an execution-only pause entered from `in-progress` and restores to `in-progress` when unblocked.
Generated task briefs start with `# <task>` and `status: todo`; the H1 may become the current Plan title. Add checklist Steps or notes only when the user explicitly requests them. Completed Plans move to `.workbranch/plans/done/` through `workbranch done` or confirmed land/finalize/pull archive prompts.
