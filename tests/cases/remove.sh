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

  out=$(run_expect_success "$WORKBRANCH" remove login)
  assert_not_exists "$project/login/frontend"
  assert_not_exists "$project/login/backend"
  assert_file "$project/login/notes.txt"
  assert_contains "$out" "Task directory kept because it is not empty: login"
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

