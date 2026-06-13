# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.
test_remove_deletes_overridden_task_branches() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(printf 'tk/login-frontend\ntk/login-backend\n' | "$WORKBRANCH" add login 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "add failed: $out"

  out=$("$WORKBRANCH" remove login --force 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "remove failed: $out"

  if git -C "$project/_base/frontend" show-ref --verify --quiet refs/heads/tk/login-frontend; then
    fail "expected remove to delete overridden frontend branch"
  fi
  if git -C "$project/_base/backend" show-ref --verify --quiet refs/heads/tk/login-backend; then
    fail "expected remove to delete overridden backend branch"
  fi
}

test_remove_accepts_completion_trailing_slash_for_task_key() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '\n\n' | run_expect_success "$WORKBRANCH" add feat-branch-name >/dev/null

  out=$(run_expect_success "$WORKBRANCH" remove feat-branch-name/ --force)
  assert_contains "$out" "Removed: feat-branch-name/frontend"
  assert_contains "$out" "Removed: feat-branch-name/backend"
  assert_not_exists "$project/feat-branch-name"
  if git -C "$project/_base/frontend" show-ref --verify --quiet refs/heads/feat/branch-name; then
    fail "expected remove to delete frontend feat/branch-name branch"
  fi
}

test_remove_deletes_overridden_task_branches_when_task_dir_missing() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(printf 'tk/login-frontend\ntk/login-backend\n' | "$WORKBRANCH" add login 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "add failed: $out"

  rm -rf "$project/login"
  out=$("$WORKBRANCH" remove login --force 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "remove failed: $out"
  assert_contains "$out" "Worktree already removed: login/frontend"
  assert_contains "$out" "Worktree already removed: login/backend"

  if git -C "$project/_base/frontend" show-ref --verify --quiet refs/heads/tk/login-frontend; then
    fail "expected missing-worktree remove to delete overridden frontend branch"
  fi
  if git -C "$project/_base/backend" show-ref --verify --quiet refs/heads/tk/login-backend; then
    fail "expected missing-worktree remove to delete overridden backend branch"
  fi
}

test_remove_deletes_task_branch_when_worktree_missing() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  rm -rf "$project/login"
  out=$(run_expect_success "$WORKBRANCH" remove login)
  assert_contains "$out" "Worktree already removed: login/frontend"
  assert_contains "$out" "Worktree already removed: login/backend"
  if git -C "$project/_base/frontend" show-ref --verify --quiet refs/heads/feature/login; then
    fail "expected remove to delete stale frontend feature/login branch"
  fi
  if git -C "$project/_base/backend" show-ref --verify --quiet refs/heads/feature/login; then
    fail "expected remove to delete stale backend feature/login branch"
  fi

  run_expect_success "$WORKBRANCH" add login >/dev/null
  assert_branch "$project/login/frontend" "feature/login"
  assert_branch "$project/login/backend" "feature/login"
}

test_remove_force_discards_dirty_task() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  printf '%s\n' "dirty task" > "$project/login/frontend/dirty.txt"

  out=$(run_expect_success "$WORKBRANCH" remove login --force)
  assert_contains "$out" "Removed: login/frontend"
  assert_contains "$out" "Removed: login/backend"
  assert_not_exists "$project/login"
  if git -C "$project/_base/frontend" show-ref --verify --quiet refs/heads/feature/login; then
    fail "expected force remove to delete frontend feature/login branch"
  fi
  if git -C "$project/_base/backend" show-ref --verify --quiet refs/heads/feature/login; then
    fail "expected force remove to delete backend feature/login branch"
  fi
}

test_remove_rejects_unmerged_task_branch_without_force() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  git -C "$project/login/frontend" config user.name "Workbranch Test"
  git -C "$project/login/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "local task commit" > "$project/login/frontend/task-only.txt"
  git -C "$project/login/frontend" add task-only.txt
  git -C "$project/login/frontend" commit -m "local task commit" >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" remove login)
  assert_contains "$out" "Cannot remove: preflight failed"
  assert_contains "$out" "login/frontend task branch feature/login is not fully merged; use workbranch remove login --force to discard it"
  assert_dir "$project/login/frontend"
  assert_dir "$project/login/backend"
  git -C "$project/_base/frontend" rev-parse --verify feature/login >/dev/null ||
    fail "expected remove to keep unmerged frontend feature/login branch"
  git -C "$project/_base/backend" rev-parse --verify feature/login >/dev/null ||
    fail "expected remove to keep backend feature/login branch"
}

test_remove_rejects_task_repo_on_unexpected_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  git -C "$project/login/frontend" config user.name "Workbranch Test"
  git -C "$project/login/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "local task commit" > "$project/login/frontend/task-only.txt"
  git -C "$project/login/frontend" add task-only.txt
  git -C "$project/login/frontend" commit -m "local task commit" >/dev/null
  git -C "$project/login/frontend" checkout -b scratch master >/dev/null 2>&1

  out=$(run_expect_fail "$WORKBRANCH" remove login)
  assert_contains "$out" "Cannot remove: preflight failed"
  assert_contains "$out" "login/frontend expected branch feature/login, got scratch"
  assert_dir "$project/login/frontend"
  assert_dir "$project/login/backend"
  git -C "$project/_base/frontend" rev-parse --verify feature/login >/dev/null ||
    fail "expected remove to keep frontend feature/login branch"
  git -C "$project/_base/backend" rev-parse --verify feature/login >/dev/null ||
    fail "expected remove to keep backend feature/login branch"
}

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

test_dirty_worktree_safety() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  printf '%s\n' "dirty base" > "$project/_base/frontend/dirty.txt"
  out=$(run_expect_fail "$WORKBRANCH" pull)
  assert_contains "$out" "dirty worktree"
  rm "$project/_base/frontend/dirty.txt"
  assert_clean "$project/_base/frontend"

  printf '%s\n' "dirty task" > "$project/login/frontend/dirty.txt"
  out=$(run_expect_fail "$WORKBRANCH" update login)
  assert_contains "$out" "dirty worktree"
  out=$(run_expect_fail "$WORKBRANCH" remove login)
  assert_contains "$out" "dirty worktree"
  assert_file "$project/login/frontend/.git"
}

test_remove_reports_kept_task_directory_with_extra_files() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  printf '%s\n' "task notes" > "$project/login/notes.txt"

  out=$(printf 'n
' | run_expect_success "$WORKBRANCH" remove login)
  assert_not_exists "$project/login/frontend"
  assert_not_exists "$project/login/backend"
  assert_file "$project/login/notes.txt"
  assert_contains "$out" "Unknown task-root items remain for login"
  assert_contains "$out" "notes.txt"
}

test_remove_treats_missing_worktree_as_already_removed() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  rm -rf "$project/login/frontend"

  out=$(run_expect_success "$WORKBRANCH" remove login)
  assert_contains "$out" "Worktree already removed: login/frontend"
  assert_not_exists "$project/login/backend"
  assert_not_exists "$project/login"
}

test_remove_cleans_stale_task_directory() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  rm -f "$project/login/frontend/.git" "$project/login/backend/.git"

  out=$(run_expect_success "$WORKBRANCH" remove login)
  assert_contains "$out" "Removed stale task directory: login"
  assert_not_exists "$project/login"
  if git -C "$project/_base/frontend" show-ref --verify --quiet refs/heads/feature/login; then
    fail "expected stale remove to delete frontend feature/login branch"
  fi
  if git -C "$project/_base/backend" show-ref --verify --quiet refs/heads/feature/login; then
    fail "expected stale remove to delete backend feature/login branch"
  fi
}

test_remove_continues_after_worktree_remove_failure() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  project_real=$(pwd -P)

  real_git=$(command -v git)
  fakebin="$TMP_ROOT/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/git" <<'GIT'
#!/usr/bin/env bash
if [ "${1:-}" = "-C" ] && [ "${3:-}" = "worktree" ] && [ "${4:-}" = "remove" ] && [ "${5:-}" = "$FAIL_REMOVE_PATH" ]; then
  printf '%s
' "fake worktree remove failure" >&2
  exit 1
fi
exec "$REAL_GIT" "$@"
GIT
  chmod +x "$fakebin/git"

  old_path=$PATH
  export REAL_GIT=$real_git
  export FAIL_REMOVE_PATH="$project_real/login/frontend"
  PATH="$fakebin:$PATH"
  out=$("$WORKBRANCH" remove login 2>&1)
  status=$?
  PATH=$old_path
  unset REAL_GIT FAIL_REMOVE_PATH
  [ $status -ne 0 ] || fail "expected remove to fail after worktree removal failure"

  assert_contains "$out" "[-] Error: failed to remove worktree (continuing): login/frontend"
  assert_not_exists "$project/login/backend"
  assert_dir "$project/login/frontend"
  assert_file "$project/login/.workbranch.task"
  assert_contains "$out" "Task directory kept because it is not empty: login"
}

test_prune_removes_only_fully_merged_tasks() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '\n\n' | run_expect_success "$WORKBRANCH" add feat-done >/dev/null
  printf '\n\n' | run_expect_success "$WORKBRANCH" add feat-live >/dev/null

  git -C "$project/feat-done/frontend" config user.name "Workbranch Test"
  git -C "$project/feat-done/frontend" config user.email "workbranch-test@example.com"
  git -C "$project/feat-done/backend" config user.name "Workbranch Test"
  git -C "$project/feat-done/backend" config user.email "workbranch-test@example.com"
  printf '%s\n' "done frontend" > "$project/feat-done/frontend/done-frontend.txt"
  git -C "$project/feat-done/frontend" add done-frontend.txt
  git -C "$project/feat-done/frontend" commit -m "done frontend" >/dev/null
  printf '%s\n' "done backend" > "$project/feat-done/backend/done-backend.txt"
  git -C "$project/feat-done/backend" add done-backend.txt
  git -C "$project/feat-done/backend" commit -m "done backend" >/dev/null
  run_expect_success "$WORKBRANCH" land feat-done >/dev/null

  git -C "$project/feat-live/frontend" config user.name "Workbranch Test"
  git -C "$project/feat-live/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "live frontend" > "$project/feat-live/frontend/live-frontend.txt"
  git -C "$project/feat-live/frontend" add live-frontend.txt
  git -C "$project/feat-live/frontend" commit -m "live frontend" >/dev/null

  out=$(run_expect_success "$WORKBRANCH" prune)
  assert_contains "$out" "Pruning merged task: feat-done"
  assert_contains "$out" "Skipped: feat-live (feat-live/frontend not merged into master)"
  assert_not_exists "$project/feat-done"
  assert_dir "$project/feat-live"
  if git -C "$project/_base/frontend" show-ref --verify --quiet refs/heads/feat/done; then
    fail "expected prune to delete merged frontend branch"
  fi
  if git -C "$project/_base/backend" show-ref --verify --quiet refs/heads/feat/done; then
    fail "expected prune to delete merged backend branch"
  fi
  git -C "$project/_base/frontend" show-ref --verify --quiet refs/heads/feat/live ||
    fail "expected prune to keep unmerged frontend branch"
}

test_prune_skips_dirty_merged_task() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '\n\n' | run_expect_success "$WORKBRANCH" add feat-dirty >/dev/null

  git -C "$project/feat-dirty/frontend" config user.name "Workbranch Test"
  git -C "$project/feat-dirty/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "dirty done" > "$project/feat-dirty/frontend/dirty-done.txt"
  git -C "$project/feat-dirty/frontend" add dirty-done.txt
  git -C "$project/feat-dirty/frontend" commit -m "dirty done" >/dev/null
  run_expect_success "$WORKBRANCH" land feat-dirty >/dev/null
  printf '%s\n' "dirty worktree" > "$project/feat-dirty/frontend/dirty.txt"

  out=$(run_expect_success "$WORKBRANCH" prune)
  assert_contains "$out" "Skipped: feat-dirty (feat-dirty/frontend dirty worktree)"
  assert_dir "$project/feat-dirty"
  git -C "$project/_base/frontend" show-ref --verify --quiet refs/heads/feat/dirty ||
    fail "expected prune to keep dirty merged frontend branch"
}

test_prune_reports_partial_and_stale_task_skips() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '\n\n' | run_expect_success "$WORKBRANCH" add feat-partial >/dev/null
  printf '\n\n' | run_expect_success "$WORKBRANCH" add feat-stale >/dev/null

  git -C "$project/_base/backend" worktree remove --force "$project/feat-partial/backend" >/dev/null 2>&1
  rm -f "$project/feat-stale/frontend/.git" "$project/feat-stale/backend/.git"

  out=$(run_expect_success "$WORKBRANCH" prune)
  assert_contains "$out" "Skipped: feat-partial (feat-partial/backend missing git repo)"
  assert_contains "$out" "Skipped: feat-stale (feat-stale/frontend missing git repo)"
  assert_contains "$out" "No merged tasks to prune"
  assert_dir "$project/feat-partial"
  assert_dir "$project/feat-stale"
}

test_prune_returns_failure_after_remove_failure_and_continues() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '\n\n' | run_expect_success "$WORKBRANCH" add feat-broken >/dev/null
  printf '\n\n' | run_expect_success "$WORKBRANCH" add feat-clean >/dev/null
  project_real=$(pwd -P)

  for task in feat-broken feat-clean; do
    git -C "$project/$task/frontend" config user.name "Workbranch Test"
    git -C "$project/$task/frontend" config user.email "workbranch-test@example.com"
    git -C "$project/$task/backend" config user.name "Workbranch Test"
    git -C "$project/$task/backend" config user.email "workbranch-test@example.com"
    printf '%s\n' "$task frontend" > "$project/$task/frontend/$task-frontend.txt"
    git -C "$project/$task/frontend" add "$task-frontend.txt"
    git -C "$project/$task/frontend" commit -m "$task frontend" >/dev/null
    printf '%s\n' "$task backend" > "$project/$task/backend/$task-backend.txt"
    git -C "$project/$task/backend" add "$task-backend.txt"
    git -C "$project/$task/backend" commit -m "$task backend" >/dev/null
    run_expect_success "$WORKBRANCH" update "$task" >/dev/null
    run_expect_success "$WORKBRANCH" land "$task" >/dev/null
  done

  real_git=$(command -v git)
  fakebin="$TMP_ROOT/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/git" <<'GIT'
#!/usr/bin/env bash
if [ "${1:-}" = "-C" ] && [ "${3:-}" = "worktree" ] && [ "${4:-}" = "remove" ] && [ "${5:-}" = "--force" ] && [ "${6:-}" = "$FAIL_REMOVE_PATH" ]; then
  printf '%s
' "fake worktree remove failure" >&2
  exit 1
fi
exec "$REAL_GIT" "$@"
GIT
  chmod +x "$fakebin/git"

  old_path=$PATH
  export REAL_GIT=$real_git
  export FAIL_REMOVE_PATH="$project_real/feat-broken/frontend"
  PATH="$fakebin:$PATH"
  out=$("$WORKBRANCH" prune 2>&1)
  status=$?
  PATH=$old_path
  unset REAL_GIT FAIL_REMOVE_PATH
  [ "$status" -ne 0 ] || fail "expected prune to return failure after remove failure"

  assert_contains "$out" "Pruning merged task: feat-broken"
  assert_contains "$out" "[-] Error: failed to remove worktree (continuing): feat-broken/frontend"
  assert_contains "$out" "Pruning merged task: feat-clean"
  assert_dir "$project/feat-broken/frontend"
  assert_not_exists "$project/feat-clean"
}


test_remove_cleans_known_generated_task_state() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  mkdir -p "$project/login/.omx" "$project/login/.omc"
  printf '%s\n' state > "$project/login/.omx/state.txt"
  printf '%s\n' state > "$project/login/.omc/state.txt"

  out=$(run_expect_success "$WORKBRANCH" remove login)
  assert_contains "$out" "Removed: login/frontend"
  assert_contains "$out" "Removed: login/backend"
  assert_not_exists "$project/login"
}

test_remove_prompts_before_deleting_unknown_task_root_files() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  printf '%s\n' keep > "$project/login/notes.txt"

  out=$(printf 'n\n' | WORKBRANCH_ALLOW_NON_TTY_PROMPT=1 run_expect_success "$WORKBRANCH" remove login)
  assert_contains "$out" "Unknown task-root items remain for login"
  assert_contains "$out" "notes.txt"
  assert_contains "$out" "Delete remaining task root now? [y/N]"
}

test_remove_keeps_unknown_files_when_prompt_declined() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  printf '%s\n' keep > "$project/login/notes.txt"

  printf 'n\n' | WORKBRANCH_ALLOW_NON_TTY_PROMPT=1 run_expect_success "$WORKBRANCH" remove login >/dev/null
  assert_file "$project/login/notes.txt"
  assert_not_exists "$project/login/frontend"
  assert_not_exists "$project/login/backend"
}

test_remove_noninteractive_unknown_files_keeps_without_prompt() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  printf '%s\n' keep > "$project/login/notes.txt"

  out=$(WORKBRANCH_TEST_FORCE_TTY_STDIN=1 run_expect_success "$WORKBRANCH" remove login)
  assert_contains "$out" "Unknown task-root items remain for login"
  assert_not_contains "$out" "Delete remaining task root now?"
  assert_file "$project/login/notes.txt"
}

test_remove_deletes_unknown_files_when_prompt_confirmed() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  printf '%s\n' delete > "$project/login/notes.txt"

  out=$(printf 'y\n' | WORKBRANCH_ALLOW_NON_TTY_PROMPT=1 run_expect_success "$WORKBRANCH" remove login)
  assert_contains "$out" "Unknown task-root items remain for login"
  assert_contains "$out" "Removed task directory: login"
  assert_not_exists "$project/login"
}

test_remove_force_purges_without_prompt() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  mkdir -p "$project/login/.omx"
  printf '%s\n' delete > "$project/login/notes.txt"
  printf '%s\n' delete > "$project/login/.omx/state.txt"

  out=$(run_expect_success "$WORKBRANCH" remove login --force)
  assert_not_contains "$out" "Delete remaining task root now?"
  assert_not_exists "$project/login"
}

test_manual_task_dir_delete_vanishes_from_json() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  rm -rf "$project/login"

  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d["tasks"] == [], d'
}
