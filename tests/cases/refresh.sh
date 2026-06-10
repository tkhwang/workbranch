# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

test_refresh_pulls_base_then_updates_tasks() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null

  commit_to_remote_master frontend refresh-upstream
  remote_base_head=$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse master)
  assert_not_exists "$project/_base/frontend/refresh-upstream.txt"
  assert_not_exists "$project/feat-login/frontend/refresh-upstream.txt"

  out=$(run_expect_success "$WORKBRANCH" refresh)
  assert_contains "$out" "Pulling frontend"
  assert_contains "$out" "Updating feat-login/frontend"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$remote_base_head" ] || fail "base did not advance"
  git -C "$project/feat-login/frontend" merge-base --is-ancestor "$remote_base_head" HEAD || fail "task was not rebased onto remote base"
  assert_file "$project/_base/frontend/refresh-upstream.txt"
  assert_file "$project/feat-login/frontend/refresh-upstream.txt"
}

test_refresh_repo_scope_limits_pull_and_update() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null

  commit_to_remote_master frontend refresh-frontend
  commit_to_remote_master backend refresh-backend

  out=$(run_expect_success "$WORKBRANCH" refresh --repo frontend)
  assert_contains "$out" "Pulling frontend"
  assert_not_contains "$out" "Pulling backend"
  assert_contains "$out" "Updating feat-login/frontend"
  assert_not_contains "$out" "Updating feat-login/backend"
  assert_file "$project/_base/frontend/refresh-frontend.txt"
  assert_file "$project/feat-login/frontend/refresh-frontend.txt"
  assert_not_exists "$project/_base/backend/refresh-backend.txt"
  assert_not_exists "$project/feat-login/backend/refresh-backend.txt"
}

test_refresh_repo_scope_collects_tasks_with_only_selected_repo_healthy() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  git -C "$project/_base/backend" worktree remove --force "$project/feat-login/backend" >/dev/null 2>&1

  commit_to_remote_master frontend refresh-scoped-partial
  remote_base_head=$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse master)

  out=$(run_expect_success "$WORKBRANCH" refresh --repo frontend)
  assert_contains "$out" "Pulling frontend"
  assert_contains "$out" "Updating feat-login/frontend"
  assert_not_contains "$out" "no task workspaces to update"
  assert_not_contains "$out" "feat-login/backend"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$remote_base_head" ] || fail "scoped base did not advance"
  assert_file "$project/feat-login/frontend/refresh-scoped-partial.txt"
}

test_refresh_task_pulls_base_then_updates_one_task() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '\n\n' | run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  printf '\n\n' | run_expect_success "$WORKBRANCH" add feat-search >/dev/null

  commit_to_remote_master frontend refresh-one-task
  remote_base_head=$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse master)

  out=$(run_expect_success "$WORKBRANCH" refresh feat-login)
  assert_contains "$out" "Pulling frontend"
  assert_contains "$out" "Updating feat-login/frontend"
  assert_not_contains "$out" "Updating feat-search/frontend"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$remote_base_head" ] || fail "base did not advance"
  assert_file "$project/feat-login/frontend/refresh-one-task.txt"
  assert_not_exists "$project/feat-search/frontend/refresh-one-task.txt"
}

test_refresh_no_tasks_fails_before_pull() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  before_head=$(git -C "$project/_base/frontend" rev-parse HEAD)
  commit_to_remote_master frontend refresh-no-task
  remote_head=$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse master)
  [ "$before_head" != "$remote_head" ] || fail "expected remote to advance"

  out=$(run_expect_fail "$WORKBRANCH" refresh)
  assert_contains "$out" "no task workspaces to update"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$before_head" ] || fail "base advanced before no-task failure"
  assert_not_exists "$project/_base/frontend/refresh-no-task.txt"
}

test_refresh_update_preflight_failure_blocks_pull() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  before_head=$(git -C "$project/_base/frontend" rev-parse HEAD)
  commit_to_remote_master frontend refresh-dirty-task
  printf '%s\n' "dirty task" > "$project/feat-login/backend/dirty.txt"

  out=$(run_expect_fail "$WORKBRANCH" refresh)
  assert_contains "$out" "Cannot update: preflight failed"
  assert_contains "$out" "feat-login/backend dirty worktree"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$before_head" ] || fail "base advanced before update preflight failure"
  assert_not_exists "$project/_base/frontend/refresh-dirty-task.txt"
  assert_not_exists "$project/feat-login/frontend/refresh-dirty-task.txt"
}

test_refresh_task_update_preflight_failure_blocks_pull() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  before_head=$(git -C "$project/_base/frontend" rev-parse HEAD)
  commit_to_remote_master frontend refresh-one-dirty-task
  printf '%s\n' "dirty task" > "$project/feat-login/backend/dirty.txt"

  out=$(run_expect_fail "$WORKBRANCH" refresh feat-login)
  assert_contains "$out" "Cannot update: preflight failed"
  assert_contains "$out" "feat-login/backend dirty worktree"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$before_head" ] || fail "base advanced before task update preflight failure"
  assert_not_exists "$project/_base/frontend/refresh-one-dirty-task.txt"
  assert_not_exists "$project/feat-login/frontend/refresh-one-dirty-task.txt"
}

test_sync_command_is_removed() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_fail "$WORKBRANCH" sync)
  assert_contains "$out" "unknown command: sync"
}

test_refresh_preflight_blocks_rebase_conflict_after_pull_without_touching_task() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  git -C "$project/login/frontend" config user.name "Workbranch Test"
  git -C "$project/login/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "task change" > "$project/login/frontend/README.md"
  git -C "$project/login/frontend" add README.md
  git -C "$project/login/frontend" commit -m "task edits readme" >/dev/null
  task_head_before=$(git -C "$project/login/frontend" rev-parse HEAD)

  clone="$TMP_ROOT/upstream-refresh-conflict"
  git clone "$TMP_ROOT/remotes/frontend.git" "$clone" >/dev/null 2>&1
  git -C "$clone" config user.name "Workbranch Test"
  git -C "$clone" config user.email "workbranch-test@example.com"
  printf '%s\n' "base change" > "$clone/README.md"
  git -C "$clone" add README.md
  git -C "$clone" commit -m "base edits readme" >/dev/null
  git -C "$clone" push origin master >/dev/null 2>&1
  remote_head=$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse master)

  out=$(run_expect_fail "$WORKBRANCH" refresh login --repo frontend)
  assert_contains "$out" "Pulling base branches"
  assert_contains "$out" "Cannot update: preflight failed"
  assert_contains "$out" "login/frontend cannot rebase onto _base/frontend"
  assert_not_contains "$out" "Updating task workspace"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$remote_head" ] || fail "base did not pull before refresh conflict preflight"
  [ "$(git -C "$project/login/frontend" rev-parse HEAD)" = "$task_head_before" ] || fail "task HEAD changed after refresh conflict preflight"
  assert_clean "$project/login/frontend"
}
