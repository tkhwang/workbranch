# 0014 Rename Command Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` before every behavior change. Make source changes under `src/workbranch/**`, register new modules in `scripts/workbranch-sources.txt`, rebuild with `scripts/build-workbranch.sh`, then verify syntax checks, targeted tests, `./tests/run.sh`, and `git diff --check`. Do not edit `bin/workbranch` by hand. **This is the highest-risk command in the tool — it moves worktree directories and renames branches. Resolve the Decision Gate before writing code.**

**Goal:** Add `workbranch rename <task> <new-task>` to rename a task workspace and its per-repo task branches in one safe, all-or-nothing operation: move each repo's worktree directory under the new task folder, rename the local git branch, and rewrite task metadata.

**Architecture:** Rename follows the established preflight-then-execute-with-rollback model used by `add`. A full preflight validates every repo before any mutation; execution moves worktrees (`git worktree move`), renames branches (`git branch -m`), writes new metadata, and removes the old directory. Any failure mid-way triggers a reverse rollback. Remote branches are intentionally left untouched (consistent with `remove`/`land`, which never mutate remotes).

**Tech Stack:** Portable Bash, Git worktrees, line-oriented `.workbranch.config`, task metadata in `<task>/.workbranch.task`, generated single-file CLI via `scripts/build-workbranch.sh`, integration tests in `tests/run.sh`.

---

## Problem Statement

Task identity (`feat-login`) is chosen at `add` time and is effectively permanent: to "rename" a task today a user must `remove` it (losing local work unless pushed) and `add` it again under a new name. There is no in-place rename of the folder + branches. `rename` makes task identity editable without destroying work.

## Current Repo Evidence

- Task folder ↔ branch derivation: `src/workbranch/lib/task-identity.sh` (`task_folder_from_identity`, `task_branch_from_folder_identity`, delimiter is `-`, e.g. `feat-login` ↔ `feat/login`), `src/workbranch/lib/project.sh` (`default_repo_task_branch_at`, `repo_task_branch_at`).
- Per-repo task branch source of truth: `.workbranch.task` via `src/workbranch/lib/task-metadata.sh` (`load_task_metadata`, `metadata_task_branch_for_repo`, `write_task_metadata`, `set_task_metadata_branch`, `reset_task_metadata_cache`).
- Worktree creation/branch ops: `src/workbranch/git-ops.sh` (`workbranch_git_add_new_task_worktree`, `workbranch_git_delete_task_branch`, `workbranch_git_prune_stale_worktrees`).
- Preflight predicates: `src/workbranch/lib/preflight.sh` (`preflight_require_current_branch`, `preflight_require_clean`, `preflight_require_no_rebase`, `branch_exists`, `git_ref_exists`).
- Rollback pattern: `src/workbranch/lib/rollback.sh` (`track_path`, `track_worktree`, `track_branch`, `fail_with_rollback`, `rollback_created`) — currently models *created* artifacts; rename needs an analogous reverse-move tracker.
- `add` (`src/workbranch/commands/add.sh`) is the closest reference flow: preflight all repos, then create dir + metadata + per-repo worktrees with rollback.
- `remove` (`src/workbranch/commands/remove.sh`) shows safe per-repo worktree teardown and "continue but report" failure handling.
- Argument normalization: `normalize_task_argument` + `validate_task_folder_name` for every task arg.
- `git worktree move <old> <new>` relocates a linked worktree and updates its gitdir pointer; `git branch -m <old> <new>` renames a local branch (and its config/reflog).

## Decision Gate (resolve before coding)

- [ ] **How are the new per-repo branch names computed?**
  - Impact: correctness of the rename across repos that use overrides or parent-feature bases, and whether the command is interactive.
  - Options:
    - **(A) Derive from the new task identity, no prompts.** New branch per repo = `default_repo_task_branch_at <index> <new-task>` (same rule as `add`: `feat/login` on main-style bases, `<base>-detail` on parent-feature bases). Simple and non-interactive, but silently discards user branch overrides that diverged from the derived default.
    - **(B) Suffix-swap overrides, derive defaults.** If the old branch equals the old derived default, use the new derived default. If it was an override, keep the override's structure by swapping the old detail for the new detail where it appears; if it can't be mapped unambiguously, fall back to a prompt.
    - **(C) Prompt per repo (like `add`).** Show the proposed new branch (derived default) and let the user edit per repo, storing results via `set_task_metadata_branch`. Most flexible, matches `add`'s interactive feel, but makes scripting harder.
  - **Recommendation: (C) with a `--yes`/non-interactive fallback to (A).** Interactive `rename` proposes derived defaults and lets the user override per repo (consistent with `add`'s prompt model and override storage); non-interactive use derives defaults silently. Document the chosen rule in the plan and tests before implementing.
  - Rejected-by-default: pure (A) for interactive use, because it would silently drop deliberate overrides.

## Product Decisions

1. **All-or-nothing across repos.**
   - Preflight validates every repo first. If any repo fails preflight, nothing is mutated.
   - During execution, any failure triggers a rollback that reverses completed moves/renames.

2. **Local-only; remotes untouched.**
   - `rename` does not push, delete, or rename remote branches. If a task branch was already pushed, its remote name keeps the old value until the user re-pushes under the new name. Print a note when any in-scope branch has an `origin/<old-branch>`.

3. **Worktree moved in place, not recreated.**
   - Use `git worktree move` to preserve uncommitted-but-... no: require clean worktrees (see #4). Moving (not remove+add) preserves local commits and branch history without re-fetching.

4. **Clean worktrees required (no `--force` in slice 1).**
   - Each task repo must be clean, on its expected branch, and not mid-rebase. Dirty/unexpected state aborts in preflight with actionable messages, mirroring `update`/`land`.

5. **New task folder must not exist; new branches must be free.**
   - Reject if `$PROJECT_ROOT/<new-task>` exists, or if any computed new branch already exists locally or as `origin/<new-branch>` (same guard `add` uses).

6. **Whole-task only.**
   - `rename` always operates on every repo of the task. No `--repo` partial rename in this slice (a half-renamed task is an inconsistent identity).

7. **Metadata rewritten under the new key.**
   - Write `.workbranch.task` for `<new-task>` with the new per-repo branches; remove the old task's metadata file and directory.

## Target UX

```bash
$ workbranch rename feat-login feat-auth
[*] Renaming feat-login -> feat-auth
[*] Repo frontend
[*]   branch feat/login -> [feat/auth]:
[*] Repo backend
[*]   branch feature/cpq-login -> [feature/cpq-auth]:
[+] Moved worktree: feat-auth/frontend
[+] Renamed branch: feat/login -> feat/auth
[+] Moved worktree: feat-auth/backend
[+] Renamed branch: feature/cpq-login -> feature/cpq-auth
[*] Note: origin/feat/login still exists; re-push as feat/auth when ready.
[+] Renamed: feat-login -> feat-auth
```

Usage line:

```text
rename <task> <new>  Rename a task workspace and its task branches
```

## Target File Structure

```text
src/workbranch/commands/rename.sh    # new: cmd_rename (preflight, prompt/derive, execute, rollback)
src/workbranch/lib/rollback.sh       # add reverse-move tracking (track_move) + rollback_renamed
src/workbranch/git-ops.sh            # add workbranch_git_move_worktree + workbranch_git_rename_branch
src/workbranch/globals.sh            # add RENAMED_* tracking arrays
src/workbranch/main.sh               # dispatch rename
src/workbranch/usage.sh              # document rename under Workspace
scripts/workbranch-sources.txt       # rename.sh already covered by commands/* ordering; ensure registered
tests/cases/rename.sh                # new integration tests
tests/run.sh                         # register rename tests
README.md                            # document rename + remote caveat
README.ko.md                         # Korean mirror
bin/workbranch                       # regenerated only by scripts/build-workbranch.sh
```

## Implementation Tasks

### Task 1: Git move/rename helpers with focused tests

**Files:**
- Modify: `src/workbranch/git-ops.sh`, `tests/cases/rename.sh`, `tests/run.sh`

- [ ] Add failing tests proving the new helpers move a worktree dir and rename a local branch.

- [ ] Implement in `src/workbranch/git-ops.sh`:

  ```bash
  workbranch_git_move_worktree() {
    base_path=$1
    old_path=$2
    new_path=$3
    workbranch_git_prune_stale_worktrees "$base_path" || return 1
    git -C "$base_path" worktree move "$old_path" "$new_path" >/dev/null 2>&1
  }

  workbranch_git_rename_branch() {
    base_path=$1
    old_branch=$2
    new_branch=$3
    git -C "$base_path" branch -m "$old_branch" "$new_branch" >/dev/null 2>&1
  }
  ```

- [ ] Register tests in `tests/run.sh`. Rebuild and run.

### Task 2: Preflight with focused tests

**Files:**
- Create: `src/workbranch/commands/rename.sh`
- Modify: `src/workbranch/main.sh`, `scripts/workbranch-sources.txt`, `tests/cases/rename.sh`, `tests/run.sh`

- [ ] Add failing tests for the preflight guards:
  - rename of a non-existent task fails;
  - rename to an existing task folder fails;
  - rename when a computed new branch already exists (local or `origin/`) fails;
  - dirty / wrong-branch / rebase-in-progress task repo aborts before any mutation.

- [ ] Implement `cmd_rename` argument handling and preflight:

  ```bash
  cmd_rename() {
    require_project
    [ $# -eq 2 ] || die "usage: workbranch rename <task> <new>"
    task=$(normalize_task_argument "$1")
    new_task=$(normalize_task_argument "$2")
    validate_task_folder_name "$task"
    validate_task_folder_name "$new_task"
    [ "$task" != "$new_task" ] || die "new task name is the same as the current name: $task"

    task_dir="$PROJECT_ROOT/$task"
    new_dir="$PROJECT_ROOT/$new_task"
    is_task_workspace_path "$task_dir" || die "not a task workspace: $task"
    [ ! -e "$new_dir" ] || die "task directory already exists: $new_dir"

    reset_preflight
    # per repo: expected current branch, clean, no rebase; compute NEW branch (Decision Gate);
    # ensure NEW branch is free locally and as origin/<new>; collect old->new branch map.
    ...
    preflight_die_if_errors "rename"
  }
  ```
  Compute the new per-repo branch with the Decision Gate's resolved rule (recommended: prompt with derived default in a TTY, derive silently otherwise). Store the old→new mapping in parallel arrays for the execute phase.

- [ ] Dispatch `rename` in `src/workbranch/main.sh`; ensure `src/workbranch/commands/rename.sh` is listed in `scripts/workbranch-sources.txt` among the command modules (after `remove.sh` is fine).

- [ ] Rebuild and run the suite.

### Task 3: Execute with rollback

**Files:**
- Modify: `src/workbranch/commands/rename.sh`, `src/workbranch/lib/rollback.sh`, `src/workbranch/globals.sh`, `tests/cases/rename.sh`, `tests/run.sh`

- [ ] Add reverse-tracking to `src/workbranch/globals.sh` and `src/workbranch/lib/rollback.sh`:

  ```bash
  # globals.sh
  RENAMED_WORKTREE_BASES=(); RENAMED_WORKTREE_OLD=(); RENAMED_WORKTREE_NEW=()
  RENAMED_BRANCH_BASES=(); RENAMED_BRANCH_OLD=(); RENAMED_BRANCH_NEW=()

  # rollback.sh
  track_moved_worktree() { ... }   # record base, old, new
  track_renamed_branch() { ... }   # record base, old, new
  rollback_renamed() {             # reverse order: move new->old, branch -m new->old
    ...
  }
  fail_with_rename_rollback() { rollback_renamed; die "$1"; }
  ```

- [ ] Implement the execute phase in `cmd_rename`:
  - `mkdir -p "$new_dir"`.
  - For each repo: `workbranch_git_move_worktree "$base" "$old_repo_path" "$new_repo_path"` (track), then `workbranch_git_rename_branch "$base" "$old_branch" "$new_branch"` (track). On any failure, `fail_with_rename_rollback`.
  - Write new metadata: `reset_task_metadata_cache`, `set_task_metadata_branch <repo> <new_branch>` per repo, `write_task_metadata "$new_task"`.
  - Remove old metadata file and old (now-empty) directory.
  - Print the `origin/<old-branch>` note for any branch that had a remote counterpart.

- [ ] Add a failing-then-passing test that a forced mid-execute failure (e.g., second repo's move fails) rolls back the first repo's move and branch rename, leaving the original `<task>` intact and no `<new-task>` directory.

- [ ] Add an end-to-end happy-path test:

  ```bash
  test_rename_moves_worktrees_and_renames_branches() {
    new_fixture
    cd "$FIXTURE_PROJECT" || fail "cd project failed"
    run_expect_success "$WORKBRANCH" init >/dev/null
    printf '\n\n' | "$WORKBRANCH" add feat-login >/dev/null 2>&1 || fail "add failed"

    printf '\n\n' | "$WORKBRANCH" rename feat-login feat-auth >/dev/null 2>&1 || fail "rename failed"

    [ ! -e "$FIXTURE_PROJECT/feat-login" ] || fail "old task dir still exists"
    assert_branch "$FIXTURE_PROJECT/feat-auth/frontend" "feat/auth"
    assert_branch "$FIXTURE_PROJECT/feat-auth/backend" "feat/auth"
    meta=$(cat "$FIXTURE_PROJECT/feat-auth/.workbranch.task")
    assert_contains "$meta" "REPO_BRANCH frontend feat/auth"
    # downstream command works with the new key
    "$WORKBRANCH" path feat-auth >/dev/null || fail "path failed for renamed task"
  }
  ```

- [ ] Rebuild and run the suite.

### Task 4: Consumers, docs, full verification

**Files:**
- Modify: `src/workbranch/usage.sh`, `README.md`, `README.ko.md`, `tests/cases/meta.sh`
- Generated: `bin/workbranch`

- [ ] Add the `rename` line to both `usage_plain` and `usage_enhanced` under Workspace; update `tests/cases/meta.sh:test_help_groups_commands`.

- [ ] Add a test confirming the renamed task is fully usable by downstream commands: `status`, `path`, `push <new-task>` preflight, and `remove <new-task>`.

- [ ] Document `rename` in `README.md` including the explicit remote caveat (remote branches keep the old name until re-pushed); mirror in `README.ko.md`.

- [ ] Rebuild: `scripts/build-workbranch.sh`.

- [ ] Syntax: `/bin/bash -n bin/workbranch install.sh tests/run.sh`.

- [ ] Full suite: `./tests/run.sh` (report final `Tests passed: N`).

- [ ] Whitespace: `git diff --check`.

- [ ] Manual smoke: create `feat-login`, `rename` to `feat-auth`, verify folder/branches/metadata and that `status`/`path`/`remove` operate on the new key; verify a simulated mid-rename failure rolls back cleanly.

## Acceptance Criteria

- `workbranch rename <task> <new>` moves every repo worktree under `<new>`, renames each local task branch per the resolved Decision Gate rule, and rewrites `.workbranch.task` under the new key.
- The operation is all-or-nothing: preflight blocks all repos before any change, and a mid-execute failure rolls back completed moves/renames, leaving the original task intact and no partial `<new>` directory.
- Remote branches are never modified; a note is printed when an `origin/<old-branch>` exists.
- The renamed task is fully usable by `status`, `path`, `push`, `land`, and `remove`.
- Clean/expected-branch/no-rebase preconditions are enforced; new folder and new branches must be free.
- Help/usage and README (incl. remote caveat) document `rename`.
- `bin/workbranch` is regenerated from source; syntax checks, full `./tests/run.sh`, and `git diff --check` pass.

## Non-Goals

- Do not rename, push, or delete remote branches.
- Do not support `--repo` partial renames in this slice.
- Do not support renaming a dirty task (no `--force` yet).
- Do not migrate or rename across projects.
- Do not introduce non-Bash dependencies.
