# 0013 Doctor Command Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` before every behavior change. Make source changes under `src/workbranch/**`, register new modules in `scripts/workbranch-sources.txt`, rebuild with `scripts/build-workbranch.sh`, then verify syntax checks, targeted tests, `./tests/run.sh`, and `git diff --check`. Do not edit `bin/workbranch` by hand.

**Goal:** Add `workbranch doctor` to diagnose a project's health — broken/missing worktrees, stale and partial task directories, prunable git worktree registrations, and base/task branch drift — and optionally apply safe automatic repairs with `--fix`.

**Architecture:** Doctor is read-only by default. It reuses the existing detection helpers (`is_task_workspace_path`, `is_stale_task_directory_path`, `is_git_dirty`, `is_rebase_in_progress`, branch checks) to report findings grouped by severity, and exits non-zero when problems are found. `--fix` performs only non-destructive repairs (`git worktree prune`); destructive cleanup (deleting stale directories) stays behind explicit existing commands and is only *suggested*, never auto-run.

**Tech Stack:** Portable Bash, Git worktrees, line-oriented `.workbranch.config`, generated single-file CLI via `scripts/build-workbranch.sh`, integration tests in `tests/run.sh`.

---

## Problem Statement

Worktree-based workflows accumulate drift: a task directory whose worktrees were removed by hand, a base repo left on the wrong branch, a worktree registration pointing at a deleted directory, an interrupted `add` that left a partial workspace. Today `workbranch status` surfaces some of this (stale directories, dirty state), but there is no single "is my project healthy, and can you fix the safe stuff" command. `doctor` consolidates diagnosis and one-command safe cleanup.

## Current Repo Evidence

- `src/workbranch/lib/status-format.sh` already classifies directories: `is_task_shaped_directory_path`, `is_task_workspace_path` (all repo worktrees registered), `is_stale_task_directory_path` (task-shaped but not a valid workspace), and `remove_stale_task_directory_path`.
- `src/workbranch/commands/status.sh` reports stale directories in a dedicated section and computes base remote diffs and worktree state.
- `src/workbranch/lib/preflight.sh` provides reusable predicates: `is_git_dirty`, `is_rebase_in_progress`, `git_dir_for_path`, and `branch_or_unknown` (via config) for current-branch checks.
- `src/workbranch/git-ops.sh` provides `workbranch_git_prune_stale_worktrees` (`git worktree prune`), already used inside add/remove flows.
- `remove` already handles stale-directory removal via `is_stale_task_directory_path` + `remove_stale_task_directory_path` and a `--force` gate.
- Commands dispatch in `src/workbranch/main.sh`; usage in `src/workbranch/usage.sh`. `doctor` is platform-agnostic (no app launchers), so it goes through the normal `require_core_supported_platform` path like other core commands.

## Product Decisions

1. **Read-only by default, exit code signals health.**
   - `workbranch doctor` prints findings and exits `0` when healthy, non-zero when any problem is found. This makes it CI-friendly.

2. **`--fix` performs only safe repairs.**
   - Safe = `git worktree prune` on each base repo (removes registrations for deleted worktree dirs). Idempotent and non-destructive.
   - `--fix` never deletes task directories or branches. For those it prints the exact existing command to run (`workbranch remove <task>`, `workbranch remove <task> --force`).

3. **`--repo <repo>` scopes checks** to one repo, consistent with other commands.

4. **Findings are grouped by category, each with a remediation hint.**
   - Categories (first slice):
     - Base repo issues: missing git repo, not on configured base branch, rebase in progress, dirty.
     - Prunable worktrees: base repos with stale `git worktree` registrations (detectable via `git worktree list` entries marked `prunable`).
     - Stale task directories: task-shaped dirs that are not valid workspaces.
     - Partial task workspaces: task dirs where some but not all repo worktrees are registered.

5. **No new persistent state.**
   - Doctor computes everything live from the filesystem and git; it writes nothing except the `git worktree prune` side effect under `--fix`.

## Target UX

```bash
$ workbranch doctor
[*] Base repos
    [+] frontend  on main, clean
    [-] backend   not on configured branch (expected master, got hotfix)

[*] Task workspaces
    [+] feat+login  healthy
    [-] feat+wip    partial: backend worktree not registered

[*] Stale directories
    [-] old-task    task-shaped directory but no registered worktrees
                    fix: workbranch remove old-task

[*] Prunable worktrees
    [-] frontend    1 stale worktree registration
                    fix: workbranch doctor --fix

[-] doctor found 4 issue(s)

$ workbranch doctor --fix
[+] Pruned stale worktree registrations: frontend
[*] Remaining issues require manual action:
    backend not on configured branch (expected master, got hotfix)
    feat+wip partial workspace
    old-task stale directory -> workbranch remove old-task
[-] doctor fixed 1 issue(s); 3 require manual action
```

Usage line:

```text
doctor            Diagnose project health; --fix applies safe repairs
```

## Target File Structure

```text
src/workbranch/commands/doctor.sh   # new: cmd_doctor (+ check/report helpers)
src/workbranch/lib/status-format.sh # optional: add is_partial_task_workspace_path / prunable detection helper
src/workbranch/main.sh              # dispatch doctor
src/workbranch/usage.sh             # document doctor under Other (or a Maintenance group)
scripts/workbranch-sources.txt      # register doctor.sh among the command modules
tests/cases/doctor.sh               # new integration tests
tests/run.sh                        # register doctor tests
README.md                           # document doctor
README.ko.md                        # Korean mirror
bin/workbranch                      # regenerated only by scripts/build-workbranch.sh
```

## Implementation Tasks

### Task 1: Detection helpers with focused tests

**Files:**
- Modify: `src/workbranch/lib/status-format.sh`, `tests/cases/doctor.sh`, `tests/run.sh`

- [ ] Add a failing test that a task directory with one missing repo worktree is detected as partial (not a healthy workspace, not stale).

  ```bash
  test_doctor_detects_partial_workspace() {
    new_fixture
    cd "$FIXTURE_PROJECT" || fail "cd project failed"
    run_expect_success "$WORKBRANCH" init >/dev/null
    printf '\n\n' | "$WORKBRANCH" add feat+login >/dev/null 2>&1 || fail "add failed"
    # remove one repo worktree out-of-band to create a partial workspace
    git -C "$FIXTURE_PROJECT/_base/backend" worktree remove --force "$FIXTURE_PROJECT/feat+login/backend"

    out=$("$WORKBRANCH" doctor 2>&1; echo "status=$?")
    assert_contains "$out" "feat+login"
    assert_contains "$out" "partial"
    assert_contains "$out" "status=1"
  }
  ```

- [ ] Add `is_partial_task_workspace_path` to `status-format.sh`: task-shaped, at least one repo worktree registered, but not all registered (distinct from `is_stale_task_directory_path`, which is task-shaped with no valid full workspace).

  ```bash
  is_partial_task_workspace_path() {
    local path i name any=0 all=1
    path=$1
    is_task_shaped_directory_path "$path" || return 1
    i=0
    while [ $i -lt ${#REPO_NAMES[@]} ]; do
      name=$(repo_name_at "$i")
      if is_registered_worktree_path "$path/$name" "$(base_repo_path "$name")"; then
        any=1
      else
        all=0
      fi
      i=$((i + 1))
    done
    [ "$any" -eq 1 ] && [ "$all" -eq 0 ]
  }
  ```

- [ ] Add a helper to detect prunable worktree registrations per base, parsing `git -C "$base" worktree list --porcelain` for `prunable` lines (or comparing registered `worktree` paths against existing directories).

- [ ] Register the test in `tests/run.sh`. Rebuild and run.

### Task 2: Read-only `cmd_doctor` with grouped report and exit code

**Files:**
- Create: `src/workbranch/commands/doctor.sh`
- Modify: `src/workbranch/main.sh`, `scripts/workbranch-sources.txt`, `tests/cases/doctor.sh`, `tests/run.sh`

- [ ] Add failing tests for: healthy project exits 0; base-branch drift reported and exits non-zero; stale directory reported with `workbranch remove` hint.

  ```bash
  test_doctor_healthy_project_exits_zero() {
    new_fixture
    cd "$FIXTURE_PROJECT" || fail "cd project failed"
    run_expect_success "$WORKBRANCH" init >/dev/null
    printf '\n\n' | "$WORKBRANCH" add feat+login >/dev/null 2>&1 || fail "add failed"
    out=$("$WORKBRANCH" doctor 2>&1; echo "status=$?")
    assert_contains "$out" "status=0"
  }

  test_doctor_reports_stale_directory_with_remove_hint() {
    # create a task-shaped dir with no registered worktrees, like status.sh stale tests
    ...
    out=$("$WORKBRANCH" doctor 2>&1; echo "status=$?")
    assert_contains "$out" "workbranch remove"
    assert_contains "$out" "status=1"
  }
  ```

- [ ] Implement `cmd_doctor`:
  - `require_project`, `parse_repo_option`, reject positional args beyond options.
  - Track an `issues` counter (and a list of remediation lines).
  - Base repos section: for each repo (honoring `repo_matches_filter`), report missing git repo, expected-vs-actual branch (`preflight_require_current_branch` predicate logic, but as a non-fatal report), `is_rebase_in_progress`, `is_git_dirty`.
  - Task workspaces section: iterate `"$PROJECT_ROOT"/*`; healthy (`is_task_workspace_path`) vs partial (`is_partial_task_workspace_path`).
  - Stale directories section: `is_stale_task_directory_path`, with `fix: workbranch remove <task>` hint.
  - Prunable worktrees section: per-base prunable registrations, with `fix: workbranch doctor --fix` hint.
  - Print `doctor found N issue(s)` and `exit 1` when `issues > 0`, else success and `exit 0`.
  - Send all human-facing output through existing `section`/`info`/`success` and the `WB_ERR_*` colored error helpers, consistent with `status.sh`.

- [ ] Dispatch `doctor` in `src/workbranch/main.sh` and register `doctor.sh` in `scripts/workbranch-sources.txt` after `status.sh` (so it can reuse status-format helpers, already sourced earlier).

- [ ] Rebuild and run the suite.

### Task 3: `--fix` safe repair (worktree prune)

**Files:**
- Modify: `src/workbranch/commands/doctor.sh`, `tests/cases/doctor.sh`, `tests/run.sh`

- [ ] Add a failing test: a base with a stale worktree registration is cleaned by `workbranch doctor --fix`, and a subsequent `workbranch doctor` no longer reports it.

  ```bash
  test_doctor_fix_prunes_stale_worktree_registration() {
    # create a registered worktree, then `rm -rf` its directory directly
    ...
    "$WORKBRANCH" doctor --fix >/dev/null 2>&1
    out=$(git -C "$base_frontend" worktree list --porcelain)
    assert_not_contains "$out" "prunable"
  }
  ```

- [ ] Implement `--fix` parsing in `cmd_doctor`. When set:
  - Run `workbranch_git_prune_stale_worktrees` for each in-scope base and report which were pruned.
  - Re-evaluate remaining issues; print manual-action items (drift, partial, stale dir) with their hints.
  - Exit `0` only if no manual-action issues remain after the prune.

- [ ] Confirm `--fix` never deletes task directories or branches (assert in a test that a stale task directory still exists after `--fix`, with the `workbranch remove` hint shown).

- [ ] Rebuild and run the suite.

### Task 4: Usage, docs, full verification

**Files:**
- Modify: `src/workbranch/usage.sh`, `README.md`, `README.ko.md`, `tests/cases/meta.sh`
- Generated: `bin/workbranch`

- [ ] Add the `doctor` line to both `usage_plain` and `usage_enhanced`.

- [ ] Update `tests/cases/meta.sh:test_help_groups_commands` to assert the doctor usage line.

- [ ] Document `doctor` (and `--fix`) in `README.md`; mirror in `README.ko.md`.

- [ ] Rebuild: `scripts/build-workbranch.sh`.

- [ ] Syntax: `/bin/bash -n bin/workbranch install.sh tests/run.sh`.

- [ ] Full suite: `./tests/run.sh` (report final `Tests passed: N`).

- [ ] Whitespace: `git diff --check`.

- [ ] Manual smoke: induce drift (wrong base branch), a partial workspace, a stale dir, and a deleted-but-registered worktree; confirm `doctor` reports all four and `doctor --fix` prunes only the registration.

## Acceptance Criteria

- `workbranch doctor` reports base drift, partial workspaces, stale directories, and prunable worktrees, grouped with remediation hints.
- Exit code is `0` when healthy and non-zero when issues are found.
- `--fix` runs only `git worktree prune` (safe/idempotent) and never deletes directories or branches.
- `--repo <repo>` scopes the checks.
- Help/usage and README document `doctor`.
- `bin/workbranch` is regenerated from source; syntax checks, full `./tests/run.sh`, and `git diff --check` pass.

## Non-Goals

- Do not auto-delete stale task directories or branches (suggest `workbranch remove` instead).
- Do not auto-fix base branch drift or partial workspaces (report only).
- Do not add network repair (re-clone, re-fetch) in this slice.
- Do not introduce non-Bash dependencies or persistent health state.
