# Repository Guidelines

## Project Structure & Module Organization

This repository is a Bash CLI for managing Git worktree task spaces. Edit source modules under `apps/cli/src/workbranch/`; `bin/workbranch` is the generated single-file distribution. Keep the generation order in `apps/cli/scripts/workbranch-sources.txt`. Tests live in `apps/cli/tests/run.sh` and build tooling lives in `scripts/`. User-facing docs are in `README.md`, with design notes under `docs/architecture.md`, Git behavior in `docs/git-operations.md`, specs in `docs/specs/`, and implementation plans in `docs/plans/`. Packaging assets, such as the Homebrew formula, live in `packaging/`.

## Build, Test, and Development Commands

- `apps/cli/scripts/build-workbranch.sh`: rebuilds `bin/workbranch` from `apps/cli/src/workbranch/**` and runs `bash -n` on the generated file.
- `./apps/cli/tests/run.sh`: runs the integration suite against temporary Git remotes and checks that `bin/workbranch` is up to date.
- `/bin/bash -n bin/workbranch install.sh tests/run.sh`: fast syntax check for the main executable, installer, and test runner.
- `git diff --check`: catches whitespace errors before commit.

## Coding Style & Naming Conventions

Write portable Bash with explicit quoting, small functions, and clear failure paths. Existing code uses snake_case function names such as `preflight_require_clean` and `cmd_add`. Keep user-facing status messages consistent with the current prefixes: `[*]` for progress, `[+]` for success, and `[-] Error:` for failures. Do not edit `bin/workbranch` directly; change `apps/cli/src/workbranch/**`, then rebuild.

## Testing Guidelines

Add integration coverage in `apps/cli/tests/run.sh` for CLI behavior, Git safety checks, config parsing, and generated-file freshness. Name tests as `test_<behavior>` and run them through the existing `run_test` harness. Prefer temporary repos and bare remotes, as the current suite does, so tests do not depend on local Git state.

## Commit & Pull Request Guidelines

Use plain Conventional Commit style with scopes, without emoji prefixes, for example `feat(config): add repo-level setup commands` and `fix(validation): improve name validation`. Keep commit subjects short and action-oriented.

Releases are cut by release-please from the paths a commit changes, not from its scope. The repository root is the CLI package (tag `vX.Y.Z`, Homebrew formula, agent-runtime binaries); `apps/companion` is the companion package. A `feat` or `fix` commit releases every package it touches. The root's `exclude-paths` only match directories (`apps/companion`, `packages/contract`, `.github`, `docs`, `assets/readme`); top-level files such as `README.md`, `README.ko.md`, `DESIGN.md`, `AGENTS.md`, `package.json` and `pnpm-lock.yaml` always count as CLI changes. So commit edits to those files on their own with a type that publishes nothing (`docs`, `chore`, `build`), never inside a `feat` or `fix` commit and never as `feat(docs)` or `fix(docs)`; otherwise companion-only work publishes an empty CLI release. If such a commit already merged, add a `BEGIN_COMMIT_OVERRIDE` / `END_COMMIT_OVERRIDE` block with a `docs:` message to its pull request body before release-please runs again. Pull requests should state the user-visible behavior, list touched commands or files, and include verification output from `./apps/cli/tests/run.sh` plus any syntax or diff checks.

## Agent-Specific Instructions

For generated-surface changes, update source first, rebuild `bin/workbranch`, then verify both syntax and tests. Keep docs and specs synchronized when command behavior changes.
Agent runtime status is collected through provider hooks, never by asking agents to maintain TASK-WORKBRANCH.md. Preserve Git safety and generated CLI parity. Use the explicit runtime migration to remove legacy data and generated status-reporting instructions; keep unrelated user and tool instructions intact.

## Agent skills

### tk-workflow

Staged delivery workflow (intent → plan → implement → verify → signoff). Config: `docs/agents/tk-workflow.md`.
