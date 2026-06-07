# 0012 Sync Command Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` before every behavior change. Make source changes under `src/workbranch/**`, register new modules in `scripts/workbranch-sources.txt`, rebuild with `scripts/build-workbranch.sh`, then verify syntax checks, targeted tests, `./tests/run.sh`, and `git diff --check`. Do not edit `bin/workbranch` by hand.

**Goal:** Add `workbranch sync` that runs the most common daily routine in one command: pull remote base branches into the base worktrees, then rebase every task workspace onto the refreshed local bases.

**Architecture:** `sync` composes the existing `pull` and `update --all` behaviors without new git logic, but it must preserve command-level safety by preflighting the update phase before mutating base worktrees. Extract the reusable pull body and split update-all into reusable collect/preflight/execute helpers so `sync` can parse options once, verify update eligibility, pull bases, then rebase tasks in order.

**Tech Stack:** Portable Bash, Git worktrees, line-oriented `.workbranch.config`, generated single-file CLI via `scripts/build-workbranch.sh`, integration tests in `tests/run.sh`.

---

## Problem Statement

The README teaches "to start from the latest remote base, run `workbranch pull` then `workbranch add`," and the normal mid-task refresh is `workbranch pull` followed by `workbranch update`. Users run these two commands back-to-back constantly. A single `workbranch sync` collapses the round trip and reduces the chance of forgetting the second step.

## Current Repo Evidence

- `src/workbranch/commands/pull.sh` (`cmd_pull`): `require_project` → `parse_repo_option` → reject extra args → per-repo preflight (`require_current_branch`, `require_clean`, `require_no_rebase`, `fetch_origin`, `remote_branch_exists`, `pull_fast_forwardable`) → `preflight_die_if_errors "pull"` → execute (`ensure_current_branch`, `workbranch_git_pull_base`).
- `src/workbranch/commands/update.sh` (`cmd_update`): for `--all`/no-arg it builds `tasks_to_update` from `"$PROJECT_ROOT"/*` filtered by `is_task_workspace_path`, runs `preflight_update_task` for each, `preflight_die_if_errors "update"`, then `update_task` for each (which rebases each task repo onto the local base HEAD).
- Both call `require_project` and `parse_repo_option` themselves, so `sync` must avoid double-parsing by calling extracted bodies.
- `parse_repo_option` sets `FILTER_REPO`/`ARGS`; `repo_matches_filter` is honored throughout both flows, so `--repo` scoping carries into `sync` for free once parsed once.
- Commands are dispatched in `src/workbranch/main.sh`; usage lives in `src/workbranch/usage.sh`.

## Decision Gates

- [x] Sync failure atomicity
  - Impact: user-visible lifecycle/state semantics.
  - Current evidence: current `pull` mutates base worktrees; current `update` preflights task worktrees immediately before rebasing.
  - Resolved: `sync` must preflight update eligibility before pulling bases. Dirty/missing/wrong-branch task worktrees abort `sync` before any base pull.

- [x] New sync artifact placement
  - Impact: source module ordering, generated CLI surface, and test harness registration.
  - Current evidence: command modules live under `src/workbranch/commands/*.sh`; generated order is controlled by `scripts/workbranch-sources.txt`; integration cases live under `tests/cases/*.sh` and are explicitly registered in `tests/run.sh`.
  - Resolved: add `src/workbranch/commands/sync.sh` and `tests/cases/sync.sh`; do not fold sync implementation into `pull.sh`/`update.sh` or sync tests into `git-flow.sh`.

## Product Decisions

1. **Order is pull then update.**
   - Refresh local bases from origin first, then rebase tasks onto the new base HEAD. This matches the documented manual workflow.

2. **`sync` updates all tasks.**
   - `workbranch sync` always targets every task workspace. On success it has the same end state as `pull` + `update --all`, while preflighting update eligibility before pulling for safer failure behavior. A single-task variant is out of scope for this slice.

3. **`--repo <repo>` is supported and scopes both phases.**
   - `workbranch sync --repo backend` pulls only `backend`'s base and updates only `backend`'s task worktrees.

4. **Fail before base mutation when task updates cannot run.**
   - `sync` first validates the `update --all` target set and task/base preconditions without rebasing anything. If any task workspace is dirty, missing, on the wrong branch, or otherwise not updateable, `sync` exits before running `pull`.
   - After the update preflight passes, `sync` runs the pull phase. If pull preflight or execution fails, no task update runs.
   - After pull succeeds, `sync` executes the already-collected update set against the refreshed local base HEADs. This preserves the update phase's batch behavior while avoiding a partial "base pulled but tasks not updateable" sync failure.

5. **No new git operations.**
   - `sync` only orchestrates existing helpers; it must not introduce new `workbranch_git_*` functions.

## Target UX

```bash
$ workbranch sync
# --- Pulling base branches ---
[*] Pulling frontend (main)
[+] ...
# --- Updating task workspaces ---
[*] Updating feat-login/frontend ...
[+] Updated: feat-login/frontend

$ workbranch sync --repo backend   # scope both phases to one repo
```

Usage line:

```text
sync              Pull base branches, then update every task workspace
```

## Target File Structure

```text
src/workbranch/commands/pull.sh     # extract run_pull (body after parse) reused by sync
src/workbranch/commands/update.sh   # split update-all collect/preflight/execute helpers reused by sync
src/workbranch/commands/sync.sh     # new: cmd_sync orchestrates pull then update-all
src/workbranch/main.sh              # dispatch sync
src/workbranch/usage.sh             # document sync under the Git horizontal group
src/workbranch/commands/completion.sh # add sync command and --repo completion
scripts/workbranch-sources.txt      # register sync.sh after update.sh / push.sh
tests/cases/sync.sh                 # new integration tests
tests/cases/completion.sh           # sync command/flag completion tests
tests/run.sh                        # register sync tests
README.md                           # document sync in quick start / branch workflow
README.ko.md                        # Korean mirror
bin/workbranch                      # regenerated only by scripts/build-workbranch.sh
```

## Implementation Tasks

### Task 1: Extract reusable pull and update-all bodies

**Files:**
- Modify: `src/workbranch/commands/pull.sh`, `src/workbranch/commands/update.sh`

- [x] Refactor `cmd_pull` so the logic after `require_project`/`parse_repo_option`/arg-check lives in a new `run_pull` function:

  ```bash
  run_pull() {
    reset_preflight
    # ... existing per-repo preflight loop ...
    preflight_die_if_errors "pull"
    # ... existing execute loop ...
  }

  cmd_pull() {
    require_project
    parse_repo_option "$@"
    [ ${#ARGS[@]} -eq 0 ] || die "usage: workbranch pull [--repo <repo>]"
    run_pull
  }
  ```

- [x] Refactor `cmd_update`'s `--all`/no-arg branch into update-all helpers that can preflight separately from execution:

  ```bash
  collect_update_all_tasks() {
    tasks_to_update=()
    for path in "$PROJECT_ROOT"/*; do
      is_task_workspace_path "$path" || continue
      task_name=${path##*/}
      tasks_to_update[${#tasks_to_update[@]}]=$task_name
    done
    [ ${#tasks_to_update[@]} -gt 0 ] || die "no task workspaces to update"
  }

  preflight_update_all_tasks() {
    reset_preflight
    task_i=0
    while [ $task_i -lt ${#tasks_to_update[@]} ]; do
      preflight_update_task "${tasks_to_update[$task_i]}"
      task_i=$((task_i + 1))
    done
    preflight_die_if_errors "update"
  }

  execute_update_all_tasks() {
    task_i=0
    while [ $task_i -lt ${#tasks_to_update[@]} ]; do
      update_task "${tasks_to_update[$task_i]}"
      task_i=$((task_i + 1))
    done
  }

  run_update_all() {
    collect_update_all_tasks
    preflight_update_all_tasks
    execute_update_all_tasks
  }
  ```
  Keep `cmd_update` behavior identical by calling `run_update_all` from the batch branch. `sync` must call `collect_update_all_tasks` + `preflight_update_all_tasks` before `run_pull`, then `execute_update_all_tasks` after `run_pull`.

- [x] Rebuild and run `./tests/run.sh`; existing pull/update tests must still pass (pure refactor, no behavior change).

### Task 2: Add `cmd_sync` with focused tests

**Files:**
- Create: `src/workbranch/commands/sync.sh`
- Modify: `src/workbranch/main.sh`, `scripts/workbranch-sources.txt`, `tests/cases/sync.sh`, `tests/run.sh`

- [x] Add a failing integration test proving sync advances a task to the freshly pulled base in one command.

  Test shape (mirroring `tests/cases/update.sh` and `tests/cases/git-flow.sh` fixtures): create a task, push a new commit to the base remote, then assert `workbranch sync` both fast-forwards the base worktree and rebases the task worktree onto the new base HEAD. Use existing helper style (`run_expect_success`, `assert_file`, `assert_not_exists`) plus direct Git assertions such as `git rev-parse` or `git merge-base --is-ancestor`; do not assume new assertion helpers exist.

  ```bash
  test_sync_pulls_base_then_updates_tasks() {
    # ... set up fixture with a task and a new remote base commit ...
    remote_base_head=$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse master)
    out=$(run_expect_success "$WORKBRANCH" sync)
    assert_contains "$out" "Pulling frontend"
    assert_contains "$out" "Updating feat-login/frontend"
    [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$remote_base_head" ] || fail "base did not advance"
    git -C "$project/feat-login/frontend" merge-base --is-ancestor "$remote_base_head" HEAD || fail "task was not rebased onto remote base"
  }
  ```

- [x] Register the test in `tests/run.sh` near the update tests.

- [x] Implement `src/workbranch/commands/sync.sh`:

  ```bash
  cmd_sync() {
    require_project
    parse_repo_option "$@"
    [ ${#ARGS[@]} -eq 0 ] || die "usage: workbranch sync [--repo <repo>]"
    collect_update_all_tasks
    preflight_update_all_tasks
    section "Pulling base branches"
    run_pull
    printf '\n'
    section "Updating task workspaces"
    execute_update_all_tasks
  }
  ```

- [x] Dispatch `sync` in `src/workbranch/main.sh`:

  ```bash
  sync) cmd_sync "$@" ;;
  ```

- [x] Add `src/workbranch/commands/sync.sh` to `scripts/workbranch-sources.txt` after `src/workbranch/commands/update.sh` (and after `pull.sh`/`push.sh`) so `run_pull`/`run_update_all` are defined first.

- [x] Rebuild and run the suite.

### Task 3: `--repo` scoping and no-task safety tests

**Files:**
- Modify: `tests/cases/sync.sh`, `tests/run.sh`

- [x] Add a test that `workbranch sync --repo <repo>` only touches the named repo's base and task worktrees.

- [x] Add a test that `workbranch sync` in a project with no task workspaces fails with the existing `no task workspaces to update` message **before** the pull phase mutates base worktrees. Prove this by creating a remote base commit, running `workbranch sync`, asserting the failure message, and asserting `_base/<repo>` did not advance to the remote commit.

- [x] Add a test that `workbranch sync` exits before pulling when any task update preflight fails, for example a dirty task worktree. Assert the dirty-task preflight message and assert the stale base did not advance.

- [x] Add a test that an unexpected positional arg prints `usage: workbranch sync [--repo <repo>]`.

- [x] Rebuild and run the suite.

### Task 4: Docs, usage, completion, full verification

**Files:**
- Modify: `src/workbranch/usage.sh`, `src/workbranch/commands/completion.sh`, `README.md`, `README.ko.md`, `docs/git-operations.md`, `tests/cases/meta.sh`, `tests/cases/completion.sh`
- Generated: `bin/workbranch`

- [x] Add the `sync` line to both `usage_plain` and `usage_enhanced` under the Git `horizontal` group.

- [x] Update `tests/cases/meta.sh:test_help_groups_commands` to assert the sync usage line.

- [x] Add `sync` to `cmd_complete_commands`, bash/zsh/fish `--repo` completion, and completion tests. `sync` should complete `--repo` but should not complete task names.

- [x] Document `sync` in `README.md` (quick start and branch workflow) and mirror in `README.ko.md`, e.g. replace the mid-task two-step `pull` + `update` example with `workbranch sync` where appropriate while keeping the individual commands documented.

- [x] Update `docs/git-operations.md` with `sync` in the direction model and command section. Document that `sync` preflights update eligibility before pulling, then pulls bases, then rebases the collected task set.

- [x] Rebuild: `scripts/build-workbranch.sh`.

- [x] Syntax: `/bin/bash -n bin/workbranch install.sh tests/run.sh`.

- [x] Full suite: `./tests/run.sh` (report final `Tests passed: N`).

- [x] Whitespace: `git diff --check`.

- [x] Manual smoke: in a fixture with a stale base and a task, run `workbranch sync` and confirm both phases run in order. Also smoke a dirty-task fixture to confirm `sync` refuses before pulling.

## Verification Evidence

- RED: new sync tests failed before implementation because `workbranch sync` was an unknown command; new completion tests failed because `sync` was absent from command/flag completion.
- Targeted sync tests: `test_sync_pulls_base_then_updates_tasks`, `test_sync_repo_scope_limits_pull_and_update`, `test_sync_no_tasks_fails_before_pull`, `test_sync_update_preflight_failure_blocks_pull`, `test_sync_rejects_unexpected_positional_arg` passed.
- Targeted completion tests: sync command listing, bash `--repo` completion, no task-name completion for `sync`, and fish `--repo` completion passed.
- Regression checks: selected update/pull regression tests passed.
- Build/syntax: `scripts/build-workbranch.sh` and `/bin/bash -n bin/workbranch install.sh tests/run.sh scripts/build-workbranch.sh` passed.
- Full suite: `./tests/run.sh` passed with `Tests passed: 157`.
- Whitespace: `git diff --check` passed.
- Manual smoke: direct `workbranch sync` fixture confirmed pull-then-update success; dirty task fixture confirmed sync aborts before pulling.

## Acceptance Criteria

- `workbranch sync` first preflights that every target task workspace can update, then pulls base branches, then rebases every collected task workspace onto the refreshed bases, in that order.
- `--repo <repo>` scopes both phases.
- Update preflight failure aborts before any base pull. The pull phase's preflight or execution failure aborts before any task update.
- `cmd_pull` and `cmd_update` behavior is unchanged (verified by their existing tests after the refactor).
- No new `workbranch_git_*` operations are introduced.
- Help/usage, shell completion, README, README.ko.md, and docs/git-operations.md document `sync`.
- `bin/workbranch` is regenerated from source; syntax checks, full `./tests/run.sh`, and `git diff --check` pass.

## Non-Goals

- Do not add `workbranch sync <task>` for a single task in this slice.
- Do not change `pull` or `update` semantics beyond extracting reusable bodies.
- Do not add push to `sync` (syncing is inbound; pushing stays explicit).
- Do not introduce non-Bash dependencies.
