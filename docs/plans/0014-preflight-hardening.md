# 0014 Preflight Hardening Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` before every behavior change. Make source changes under `src/workbranch/**`, rebuild with `scripts/build-workbranch.sh`, then verify syntax checks, targeted tests, `./tests/run.sh`, and `git diff --check`. Do not edit `bin/workbranch` by hand.

**Goal:** Strengthen preflight coverage for two mutating/recovery paths: `workbranch remove <task>` should fail before any partial cleanup when a configured base repo is missing, and `workbranch init` partial recovery should reject existing base repos that are on the wrong branch or mid-rebase.

**Architecture:** Keep the existing command-specific preflight style. `remove` gets a small aggregate base-repo existence check in its existing preflight loop before branch-safety or worktree-removal operations. `init` keeps its partial-clone recovery contract, but validates all already-existing base repos before cloning any missing base repo so recovery failures do not create new partial state.

**Tech Stack:** Portable Bash, Git worktrees, line-oriented `.workbranch.config`, generated single-file CLI via `scripts/build-workbranch.sh`, integration tests in `tests/run.sh` / `tests/cases/*.sh`.

---

## Problem Statement

Current Git-mutating commands generally preflight dirty state, wrong branch, missing repos, rebase state, and non-fast-forward paths before changing worktrees. Two gaps remain:

1. `workbranch remove <task>` does not explicitly preflight that each configured base repo exists before deleting task worktrees and local task branches. If a base repo is missing, the command can reach `git -C "$base" worktree remove` or branch-deletion code after earlier repos have already been removed.
2. `workbranch init` is intentionally both first-run setup and partial base-clone recovery. During recovery, `clone_base_repos` accepts an existing `_base/<repo>` as long as it is any Git repo. It does not verify that the existing base repo is on the configured base branch or that it is not in the middle of a rebase.

The hardening should preserve existing UX: `init` still repairs missing base clones, `remove --force` still discards dirty task worktrees, and the project should not gain new prompts or new persistent config. The init recovery implementation must validate existing base repos before cloning missing ones; otherwise a missing repo earlier in config order could be cloned before a later broken existing repo aborts recovery.

## Current Repo Evidence

- `src/workbranch/commands/remove.sh` preflights task repo current branch, task dirty state unless `--force`, and branch-delete safety unless `--force`, then removes worktrees repo-by-repo. It does not first reject a missing `base` path in the normal non-stale path.
- `src/workbranch/lib/status-format.sh` already has stronger stale-directory removal preflight: `preflight_stale_task_directory_removal` reports `$BASE_DIR/$name missing git repo` before branch deletion.
- `src/workbranch/lib/project.sh` `clone_base_repos` treats an existing target directory as acceptable when `git -C "$target" rev-parse --git-dir` succeeds, then prints `Base repo exists: $BASE_DIR/$name`. New clone failures use `fail_with_rollback`, but a later `die` after an earlier successful clone would not roll back that earlier clone.
- `src/workbranch/commands/init.sh` rejects fully initialized projects only when `all_configured_base_git_repos_exist` is true. Otherwise it calls `clone_base_repos`, preserving partial recovery.
- Existing tests cover partial clone recovery (`test_init_completes_partial_base_clones`), non-Git existing base targets, remove safety, stale task directories, and continued remove failure handling.

## Decision Gates

- [x] `remove --force` still needs base-repo existence preflight.
  - Reason: `--force` bypasses dirty/unmerged safeguards, but it still relies on `git -C "$base" worktree remove` and local branch deletion. Missing base repos are not a user-requested destructive override; they are broken project state.

- [x] Init recovery should fail on wrong branch / rebase, not auto-checkout or auto-fix.
  - Reason: `workbranch init` recovery currently clones missing bases, not reconfigures existing bases. Existing branch changes belong to `workbranch config base`, which already has fetch/checkout/pull preflight behavior.

- [x] No remote URL validation in this slice.
  - Reason: URL comparison can be noisy because Git normalizes or aliases remotes (`git@github.com:x/y.git` vs `https://github.com/x/y`). Wrong-branch and rebase-state checks provide immediate safety without introducing false positives.

- [x] Init recovery keeps first-error failure instead of aggregate preflight output.
  - Reason: init recovery currently clones missing repos and is not structured around the aggregate `PREFLIGHT_ERRORS` reporter used by Git operation commands. This slice prevents new partial clone side effects by validating existing repos before clone, but it does not redesign init output into a multi-error report.

- [x] Land atomicity is out of scope.
  - Reason: `land` has its own execute-phase partial-mutation risks if state changes after preflight. That is the same broad safety family, but it needs a separate slice because it affects pull/merge execution semantics rather than missing-base or init-recovery validation.

## Product Decisions

1. **Normal `remove` fails before any repo cleanup when a base repo is missing.**
   - Applies to both `workbranch remove <task>` and `workbranch remove <task> --force`.
   - Error shape should reuse existing aggregate preflight output: `Cannot remove: preflight failed` followed by `_base/<repo> missing git repo`.

2. **Stale-directory remove keeps its existing behavior.**
   - It already preflights missing base repos through `preflight_stale_task_directory_removal`; do not refactor that path unless needed for duplication removal.

3. **`init` partial recovery accepts healthy existing bases only.**
   - Existing base repo must be a Git repo.
   - Existing base repo must be checked out to the configured base branch.
   - Existing base repo must not have a rebase in progress.
   - Dirty base repos are allowed during `init` recovery. Existing tests intentionally write an untracked marker file into an existing base clone and expect recovery to leave it untouched. Do not add a clean-worktree requirement to `init`.

4. **Existing-base validation happens before any missing-base clone.**
   - This prevents a config-order edge case where repo A is missing and gets cloned, then repo B is discovered to be on the wrong branch and aborts the command, leaving repo A as a new partial side effect.

5. **No new public command surface.**
   - No new flags, docs tables, completions, or config directives.
   - This is behavior hardening only.

## Target File Structure

```text
src/workbranch/commands/remove.sh   # add base repo existence check to normal remove preflight loop
src/workbranch/lib/project.sh       # validate existing base repos before clone_base_repos clones missing repos
src/workbranch/lib/preflight.sh     # no required changes; use existing is_rebase_in_progress / branch_or_unknown helpers
tests/cases/remove.sh               # add missing-base preflight tests for normal and --force remove
tests/cases/init.sh                 # add existing-base wrong-branch and rebase-state recovery tests
tests/run.sh                        # register new tests near related remove/init tests
bin/workbranch                      # regenerated only by scripts/build-workbranch.sh
```

No README or spec changes are required unless implementation changes user-facing wording beyond existing error strings.

## Implementation Tasks

### Task 1: Add remove preflight for missing base repos

**Files:**
- Modify: `tests/cases/remove.sh`
- Modify: `tests/run.sh`
- Modify: `src/workbranch/commands/remove.sh`
- Regenerate: `bin/workbranch`

- [x] **Step 1: Write the failing normal-remove test**

Add this test in `tests/cases/remove.sh` near the other remove preflight tests, after `test_remove_rejects_task_repo_on_unexpected_branch`:

```bash
test_remove_rejects_missing_base_repo_before_partial_cleanup() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  rm -rf "$project/login/frontend"
  rm -rf "$project/_base/frontend"

  out=$(run_expect_fail "$WORKBRANCH" remove login)
  assert_contains "$out" "Cannot remove: preflight failed"
  assert_contains "$out" "_base/frontend missing git repo"
  assert_dir "$project/login/backend"
  assert_dir "$project/_base/backend/.git"
}
```

Register it in `tests/run.sh` immediately after `run_test test_remove_rejects_task_repo_on_unexpected_branch`:

```bash
  run_test test_remove_rejects_missing_base_repo_before_partial_cleanup
```

- [x] **Step 2: Run the focused failing test**

Run:

```bash
./tests/run.sh
```

Expected before implementation: the new test fails because current `remove` does not aggregate `_base/frontend missing git repo` before attempting cleanup. The test removes `login/frontend` as well as `_base/frontend` so it exercises the normal partial-workspace remove path instead of the already-covered stale-directory path.

If full suite runtime is inconvenient during RED, it is acceptable to run the full suite once and inspect the single new failure because `tests/run.sh` is the supported entrypoint and does not have built-in single-test filtering.

- [x] **Step 3: Implement the minimal normal-remove preflight**

In `src/workbranch/commands/remove.sh`, update the normal path preflight loop so it checks the base repo before task worktree branch checks or branch-delete safety.

Replace the current loop body start:

```bash
    name=$(repo_name_at "$i")
    path=$(task_repo_path "$task" "$name")
    branch=$(repo_task_branch_at "$i" "$task")
    base=$(base_repo_path "$name")
    label="$task/$name"
    if [ -d "$path/.git" ] || [ -f "$path/.git" ]; then
```

with:

```bash
    name=$(repo_name_at "$i")
    path=$(task_repo_path "$task" "$name")
    branch=$(repo_task_branch_at "$i" "$task")
    base=$(base_repo_path "$name")
    label="$task/$name"
    if [ ! -d "$base/.git" ] && [ ! -f "$base/.git" ]; then
      preflight_error "$BASE_DIR/$name missing git repo"
      i=$((i + 1))
      continue
    fi
    if [ -d "$path/.git" ] || [ -f "$path/.git" ]; then
```

- [x] **Step 4: Verify the normal-remove test passes**

Run:

```bash
scripts/build-workbranch.sh
./tests/run.sh
```

Expected: the new normal-remove test passes and existing remove tests still pass.

- [x] **Step 5: Add the `--force` coverage**

Add this test directly after `test_remove_rejects_missing_base_repo_before_partial_cleanup`:

```bash
test_remove_force_rejects_missing_base_repo_before_partial_cleanup() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  rm -rf "$project/login/frontend"
  rm -rf "$project/_base/frontend"

  out=$(run_expect_fail "$WORKBRANCH" remove login --force)
  assert_contains "$out" "Cannot remove: preflight failed"
  assert_contains "$out" "_base/frontend missing git repo"
  assert_dir "$project/login/backend"
  assert_dir "$project/_base/backend/.git"
}
```

Register it in `tests/run.sh` immediately after the normal missing-base test:

```bash
  run_test test_remove_force_rejects_missing_base_repo_before_partial_cleanup
```

- [x] **Step 6: Verify remove hardening**

Run:

```bash
scripts/build-workbranch.sh
/bin/bash -n bin/workbranch install.sh tests/run.sh tests/cases/remove.sh src/workbranch/commands/remove.sh
./tests/run.sh
```

Expected: all tests pass.

Evidence: RED `./tests/run.sh` failed with the two new remove tests before implementation (`Tests failed: 2`). After adding the base-repo preflight to `src/workbranch/commands/remove.sh` and rebuilding, `scripts/build-workbranch.sh && ./tests/run.sh` passed with `Tests passed: 185`.

### Task 2: Pre-validate existing base repos before init recovery clones missing repos

**Files:**
- Modify: `tests/cases/init.sh`
- Modify: `tests/run.sh`
- Modify: `src/workbranch/lib/project.sh`
- Regenerate: `bin/workbranch`

- [x] **Step 1: Write the failing wrong-branch recovery test**

Add this test in `tests/cases/init.sh` after `test_init_completes_partial_base_clones`:

```bash
test_init_rejects_existing_base_repo_on_wrong_branch_during_recovery() {
  new_fixture
  project="$FIXTURE_PROJECT"
  (cd "$project" && run_expect_success "$WORKBRANCH" init >/dev/null)

  git -C "$project/_base/frontend" checkout -b wrong-base >/dev/null 2>&1
  rm -rf "$project/_base/backend"

  out=$(cd "$project" && run_expect_fail "$WORKBRANCH" init)
  assert_contains "$out" "base repo _base/frontend expected branch master, got wrong-base"
  assert_not_exists "$project/_base/backend"
  assert_branch "$project/_base/frontend" "wrong-base"
}
```

Register it in `tests/run.sh` immediately after `run_test test_init_completes_partial_base_clones`:

```bash
  run_test test_init_rejects_existing_base_repo_on_wrong_branch_during_recovery
```

- [x] **Step 2: Write the failing missing-first/wrong-second recovery test**

Add this test directly after `test_init_rejects_existing_base_repo_on_wrong_branch_during_recovery`:

```bash
test_init_validates_existing_base_repos_before_cloning_missing_repos() {
  new_fixture
  project="$FIXTURE_PROJECT"
  (cd "$project" && run_expect_success "$WORKBRANCH" init >/dev/null)

  rm -rf "$project/_base/frontend"
  git -C "$project/_base/backend" checkout -b wrong-base >/dev/null 2>&1

  out=$(cd "$project" && run_expect_fail "$WORKBRANCH" init)
  assert_contains "$out" "base repo _base/backend expected branch master, got wrong-base"
  assert_not_exists "$project/_base/frontend"
  assert_branch "$project/_base/backend" "wrong-base"
}
```

Register it in `tests/run.sh` immediately after the wrong-branch recovery test:

```bash
  run_test test_init_validates_existing_base_repos_before_cloning_missing_repos
```

This test proves that existing base repos are checked before cloning missing repos. In the fixture config, `frontend` is first and `backend` is second. Before the implementation, current `clone_base_repos` clones missing `frontend` before it ever notices that existing `backend` is broken, so this test should fail.

- [x] **Step 3: Run the focused failing tests**

Run:

```bash
./tests/run.sh
```

Expected before implementation: the new tests fail because `clone_base_repos` currently accepts existing Git repos regardless of current branch and clones missing repos as it encounters them.

- [x] **Step 4: Add existing-base validation helpers**

In `src/workbranch/lib/project.sh`, add these helpers before `clone_base_repos()`:

```bash
validate_existing_base_repo_for_init() {
  local name target branch actual
  name=$1
  target=$2
  branch=$3
  git -C "$target" rev-parse --git-dir >/dev/null 2>&1 || die "base repo path exists but is not a git repo: $BASE_DIR/$name"
  actual=$(branch_or_unknown "$target")
  [ "$actual" = "$branch" ] || die "base repo $BASE_DIR/$name expected branch $branch, got $actual"
}

preflight_existing_base_repos_for_init() {
  local i name branch target
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    branch=$(repo_base_branch_at "$i")
    target=$(base_repo_path "$name")
    if [ -d "$target" ]; then
      validate_existing_base_repo_for_init "$name" "$target" "$branch"
    elif [ -e "$target" ] || [ -L "$target" ]; then
      die "base repo path exists but is not a directory: $BASE_DIR/$name"
    fi
    i=$((i + 1))
  done
}
```

Then call the preflight helper immediately after the `base_root` directory check in `clone_base_repos()` and before the clone loop:

```bash
  preflight_existing_base_repos_for_init
```

Finally update the existing-directory branch in the clone loop so it no longer repeats the Git-repo validation.

Replace:

```bash
    if [ -d "$target" ]; then
      git -C "$target" rev-parse --git-dir >/dev/null 2>&1 || die "base repo path exists but is not a git repo: $BASE_DIR/$name"
      info "Base repo exists: $BASE_DIR/$name"
```

with:

```bash
    if [ -d "$target" ]; then
      info "Base repo exists: $BASE_DIR/$name"
```

- [x] **Step 5: Verify wrong-branch hardening and partial recovery compatibility**

Run:

```bash
scripts/build-workbranch.sh
/bin/bash -n bin/workbranch install.sh tests/run.sh tests/cases/init.sh src/workbranch/lib/project.sh
./tests/run.sh
```

Expected: all tests pass, including all three:

```text
test_init_completes_partial_base_clones
test_init_rejects_existing_base_repo_on_wrong_branch_during_recovery
test_init_validates_existing_base_repos_before_cloning_missing_repos
```

The existing `test_init_completes_partial_base_clones` must continue to pass even though it leaves an untracked marker file in the existing frontend base clone.

Evidence: RED `./tests/run.sh` failed with the two new init recovery tests before implementation (`Tests failed: 2`). After adding `validate_existing_base_repo_for_init` / `preflight_existing_base_repos_for_init`, running `scripts/build-workbranch.sh && /bin/bash -n ... && ./tests/run.sh` passed with `Tests passed: 187`.

### Task 3: Harden init partial recovery for existing base rebase state

**Files:**
- Modify: `tests/cases/init.sh`
- Modify: `tests/run.sh`
- Modify: `src/workbranch/lib/project.sh`
- Regenerate: `bin/workbranch`

- [x] **Step 1: Write the failing rebase-state recovery test**

Add this test directly after `test_init_validates_existing_base_repos_before_cloning_missing_repos`:

```bash
test_init_rejects_existing_base_repo_rebase_in_progress_during_recovery() {
  new_fixture
  project="$FIXTURE_PROJECT"
  (cd "$project" && run_expect_success "$WORKBRANCH" init >/dev/null)

  git_dir=$(cd "$project/_base/frontend" && git rev-parse --git-dir)
  case "$git_dir" in
    /*) ;;
    *) git_dir="$project/_base/frontend/$git_dir" ;;
  esac
  mkdir -p "$git_dir/rebase-merge"
  rm -rf "$project/_base/backend"

  out=$(cd "$project" && run_expect_fail "$WORKBRANCH" init)
  assert_contains "$out" "base repo _base/frontend rebase in progress"
  assert_not_exists "$project/_base/backend"
  rm -rf "$git_dir/rebase-merge"
}
```

Register it in `tests/run.sh` immediately after the missing-first/wrong-second recovery test:

```bash
  run_test test_init_rejects_existing_base_repo_rebase_in_progress_during_recovery
```

- [x] **Step 2: Run the focused failing test**

Run:

```bash
./tests/run.sh
```

Expected before implementation: the new rebase-state test fails because Task 2 only added Git-repo and branch validation, not rebase-state validation.

- [x] **Step 3: Add rebase-state validation to the helper**

In `src/workbranch/lib/project.sh`, update `validate_existing_base_repo_for_init()` by adding the rebase check after the branch check:

```bash
  if is_rebase_in_progress "$target"; then
    die "base repo $BASE_DIR/$name rebase in progress"
  fi
```

The helper should now be:

```bash
validate_existing_base_repo_for_init() {
  local name target branch actual
  name=$1
  target=$2
  branch=$3
  git -C "$target" rev-parse --git-dir >/dev/null 2>&1 || die "base repo path exists but is not a git repo: $BASE_DIR/$name"
  actual=$(branch_or_unknown "$target")
  [ "$actual" = "$branch" ] || die "base repo $BASE_DIR/$name expected branch $branch, got $actual"
  if is_rebase_in_progress "$target"; then
    die "base repo $BASE_DIR/$name rebase in progress"
  fi
}
```

- [x] **Step 4: Verify init recovery hardening**

Run:

```bash
scripts/build-workbranch.sh
/bin/bash -n bin/workbranch install.sh tests/run.sh tests/cases/init.sh src/workbranch/lib/project.sh
./tests/run.sh
```

Expected: all tests pass, including:

```text
test_init_rejects_existing_base_repo_rebase_in_progress_during_recovery
```

Evidence: RED `./tests/run.sh` failed with the new rebase-state test before implementation (`Tests failed: 1`). After adding `is_rebase_in_progress` validation to `validate_existing_base_repo_for_init`, running `scripts/build-workbranch.sh && /bin/bash -n ... && ./tests/run.sh` passed with `Tests passed: 188`.

### Task 4: Final generated-surface and whitespace verification

**Files:**
- Regenerate: `bin/workbranch`
- Verify all touched tests and generated artifact

- [x] **Step 1: Rebuild generated executable**

Run:

```bash
scripts/build-workbranch.sh
```

Expected: command exits `0`; `bin/workbranch` is regenerated from `src/workbranch/**`.

- [x] **Step 2: Syntax-check touched surfaces**

Run:

```bash
/bin/bash -n bin/workbranch install.sh tests/run.sh tests/cases/init.sh tests/cases/remove.sh src/workbranch/commands/remove.sh src/workbranch/lib/project.sh
```

Expected: command exits `0` with no output.

- [x] **Step 3: Run full integration suite**

Run:

```bash
./tests/run.sh
```

Expected: all tests pass.

- [x] **Step 4: Check whitespace**

Run:

```bash
git diff --check
```

Expected: command exits `0` with no whitespace errors.

Evidence: Final verification command `scripts/build-workbranch.sh && /bin/bash -n bin/workbranch install.sh tests/run.sh tests/cases/init.sh tests/cases/remove.sh src/workbranch/commands/remove.sh src/workbranch/lib/project.sh && ./tests/run.sh && git diff --check` exited `0`; full suite reported `Tests passed: 188`, and `git diff --check` produced no errors.

## Acceptance Criteria

- `workbranch remove <task>` fails before removing any task worktree when any configured base repo is missing.
- `workbranch remove <task> --force` has the same missing-base preflight behavior.
- `workbranch init` still completes partial base clones when existing base repos are healthy.
- `workbranch init` rejects recovery when an existing base repo is on the wrong configured branch.
- `workbranch init` validates existing base repos before cloning missing base repos, so a missing-first/wrong-second config order does not create a new clone before failing.
- `workbranch init` rejects recovery when an existing base repo has a rebase in progress.
- Existing dirty existing-base partial recovery remains allowed.
- `bin/workbranch` is rebuilt from source.
- `/bin/bash -n ...`, `./tests/run.sh`, and `git diff --check` pass.

## Self-Review

- Spec coverage: remove missing-base preflight is covered by Task 1; init wrong-branch and pre-clone validation ordering are covered by Task 2; init rebase-state recovery is covered by Task 3; generated/test verification is covered by Task 4.
- Placeholder scan: no `TBD`, `TODO`, or unspecified "add tests" steps remain; test bodies and implementation snippets are included inline.
- Scope check: no new commands, flags, config directives, prompts, or broad URL-validation behavior are introduced.
