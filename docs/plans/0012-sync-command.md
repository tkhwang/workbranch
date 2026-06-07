# 0012 Sync Command Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` before every behavior change. Make source changes under `src/workbranch/**`, register new modules in `scripts/workbranch-sources.txt`, rebuild with `scripts/build-workbranch.sh`, then verify syntax checks, targeted tests, `./tests/run.sh`, and `git diff --check`. Do not edit `bin/workbranch` by hand.

**Goal:** Add `workbranch sync` that runs the most common daily routine in one command: pull remote base branches into the base worktrees, then rebase every task workspace onto the refreshed local bases.

**Architecture:** `sync` is a composition of the existing `pull` and `update --all` behaviors, not new git logic. Extract the post-argument bodies of `cmd_pull` and `cmd_update` into reusable functions so `sync` can parse options once and invoke both in order, preserving the existing preflight-then-execute safety model.

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

## Product Decisions

1. **Order is pull then update.**
   - Refresh local bases from origin first, then rebase tasks onto the new base HEAD. This matches the documented manual workflow.

2. **`sync` updates all tasks.**
   - `workbranch sync` always targets every task workspace (equivalent to `pull` + `update --all`). A single-task variant is out of scope for this slice.

3. **`--repo <repo>` is supported and scopes both phases.**
   - `workbranch sync --repo backend` pulls only `backend`'s base and updates only `backend`'s task worktrees.

4. **Fail fast as a whole.**
   - If the pull phase aborts via `preflight_die_if_errors`, the process exits before any task update runs (the existing `die`/`exit 1` semantics already provide this).
   - The update phase keeps its own batch preflight: all tasks are validated before any is rebased.

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
src/workbranch/commands/update.sh   # extract run_update_all (body after parse) reused by sync
src/workbranch/commands/sync.sh     # new: cmd_sync orchestrates pull then update-all
src/workbranch/main.sh              # dispatch sync
src/workbranch/usage.sh             # document sync under the Git horizontal group
scripts/workbranch-sources.txt      # register sync.sh after update.sh / push.sh
tests/cases/sync.sh                 # new integration tests
tests/run.sh                        # register sync tests
README.md                           # document sync in quick start / branch workflow
README.ko.md                        # Korean mirror
bin/workbranch                      # regenerated only by scripts/build-workbranch.sh
```

## Implementation Tasks

### Task 1: Extract reusable pull and update-all bodies

**Files:**
- Modify: `src/workbranch/commands/pull.sh`, `src/workbranch/commands/update.sh`

- [ ] Refactor `cmd_pull` so the logic after `require_project`/`parse_repo_option`/arg-check lives in a new `run_pull` function:

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

- [ ] Refactor `cmd_update`'s `--all`/no-arg branch into `run_update_all`:

  ```bash
  run_update_all() {
    found=0
    tasks_to_update=()
    reset_preflight
    for path in "$PROJECT_ROOT"/*; do
      is_task_workspace_path "$path" || continue
      found=1
      tasks_to_update[${#tasks_to_update[@]}]=${path##*/}
      preflight_update_task "${path##*/}"
    done
    [ $found -eq 1 ] || die "no task workspaces to update"
    preflight_die_if_errors "update"
    task_i=0
    while [ $task_i -lt ${#tasks_to_update[@]} ]; do
      update_task "${tasks_to_update[$task_i]}"
      task_i=$((task_i + 1))
    done
  }
  ```
  Keep `cmd_update` behavior identical by calling `run_update_all` from the batch branch.

- [ ] Rebuild and run `./tests/run.sh`; existing pull/update tests must still pass (pure refactor, no behavior change).

### Task 2: Add `cmd_sync` with focused tests

**Files:**
- Create: `src/workbranch/commands/sync.sh`
- Modify: `src/workbranch/main.sh`, `scripts/workbranch-sources.txt`, `tests/cases/sync.sh`, `tests/run.sh`

- [ ] Add a failing integration test proving sync advances a task to the freshly pulled base in one command.

  Test shape (mirroring `tests/cases/update.sh` / `git-flow.sh` fixtures): create a task, push a new commit to the base remote, then assert `workbranch sync` both fast-forwards the base worktree and rebases the task worktree onto the new base HEAD.

  ```bash
  test_sync_pulls_base_then_updates_tasks() {
    # ... set up fixture with a task and a new remote base commit ...
    out=$("$WORKBRANCH" sync 2>&1)
    status=$?
    [ "$status" -eq 0 ] || fail "sync failed: $out"
    # base worktree now at remote head
    assert_commit_equals "$base_frontend" "$remote_base_head"
    # task worktree rebased onto the new base head (contains the base commit)
    assert_task_contains_base_commit "$project/feat-login/frontend" "$remote_base_head"
  }
  ```

- [ ] Register the test in `tests/run.sh` near the update tests.

- [ ] Implement `src/workbranch/commands/sync.sh`:

  ```bash
  cmd_sync() {
    require_project
    parse_repo_option "$@"
    [ ${#ARGS[@]} -eq 0 ] || die "usage: workbranch sync [--repo <repo>]"
    section "Pulling base branches"
    run_pull
    printf '\n'
    section "Updating task workspaces"
    run_update_all
  }
  ```

- [ ] Dispatch `sync` in `src/workbranch/main.sh`:

  ```bash
  sync) cmd_sync "$@" ;;
  ```

- [ ] Add `src/workbranch/commands/sync.sh` to `scripts/workbranch-sources.txt` after `src/workbranch/commands/update.sh` (and after `pull.sh`/`push.sh`) so `run_pull`/`run_update_all` are defined first.

- [ ] Rebuild and run the suite.

### Task 3: `--repo` scoping and no-task safety tests

**Files:**
- Modify: `tests/cases/sync.sh`, `tests/run.sh`

- [ ] Add a test that `workbranch sync --repo <repo>` only touches the named repo's base and task worktrees.

- [ ] Add a test that `workbranch sync` in a project with no task workspaces fails with the existing `no task workspaces to update` message **after** the pull phase has run (decide and assert: pull still happens, then update aborts). If that ordering is undesirable, gate `run_update_all`'s empty case to a warning instead of `die`; document the chosen behavior in the test.

- [ ] Add a test that an unexpected positional arg prints `usage: workbranch sync [--repo <repo>]`.

- [ ] Rebuild and run the suite.

### Task 4: Docs, usage, full verification

**Files:**
- Modify: `src/workbranch/usage.sh`, `README.md`, `README.ko.md`, `tests/cases/meta.sh`
- Generated: `bin/workbranch`

- [ ] Add the `sync` line to both `usage_plain` and `usage_enhanced` under the Git `horizontal` group.

- [ ] Update `tests/cases/meta.sh:test_help_groups_commands` to assert the sync usage line.

- [ ] Document `sync` in `README.md` (quick start and branch workflow) and mirror in `README.ko.md`, e.g. replace the two-step `pull` + `update` example with `workbranch sync` where appropriate while keeping the individual commands documented.

- [ ] Rebuild: `scripts/build-workbranch.sh`.

- [ ] Syntax: `/bin/bash -n bin/workbranch install.sh tests/run.sh`.

- [ ] Full suite: `./tests/run.sh` (report final `Tests passed: N`).

- [ ] Whitespace: `git diff --check`.

- [ ] Manual smoke: in a fixture with a stale base and a task, run `workbranch sync` and confirm both phases run in order.

## Acceptance Criteria

- `workbranch sync` pulls base branches, then rebases every task workspace onto the refreshed bases, in that order.
- `--repo <repo>` scopes both phases.
- The pull phase's preflight failure aborts before any task update.
- `cmd_pull` and `cmd_update` behavior is unchanged (verified by their existing tests after the refactor).
- No new `workbranch_git_*` operations are introduced.
- Help/usage and README document `sync`.
- `bin/workbranch` is regenerated from source; syntax checks, full `./tests/run.sh`, and `git diff --check` pass.

## Non-Goals

- Do not add `workbranch sync <task>` for a single task in this slice.
- Do not change `pull` or `update` semantics beyond extracting reusable bodies.
- Do not add push to `sync` (syncing is inbound; pushing stays explicit).
- Do not introduce non-Bash dependencies.
