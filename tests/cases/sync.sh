# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

test_sync_pulls_base_then_updates_tasks() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null

  commit_to_remote_master frontend sync-upstream
  remote_base_head=$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse master)
  assert_not_exists "$project/_base/frontend/sync-upstream.txt"
  assert_not_exists "$project/feat-login/frontend/sync-upstream.txt"

  out=$(run_expect_success "$WORKBRANCH" sync)
  assert_contains "$out" "Pulling frontend"
  assert_contains "$out" "Updating feat-login/frontend"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$remote_base_head" ] || fail "base did not advance"
  git -C "$project/feat-login/frontend" merge-base --is-ancestor "$remote_base_head" HEAD || fail "task was not rebased onto remote base"
  assert_file "$project/_base/frontend/sync-upstream.txt"
  assert_file "$project/feat-login/frontend/sync-upstream.txt"
}

test_sync_repo_scope_limits_pull_and_update() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null

  commit_to_remote_master frontend sync-frontend
  commit_to_remote_master backend sync-backend

  out=$(run_expect_success "$WORKBRANCH" sync --repo frontend)
  assert_contains "$out" "Pulling frontend"
  assert_not_contains "$out" "Pulling backend"
  assert_contains "$out" "Updating feat-login/frontend"
  assert_not_contains "$out" "Updating feat-login/backend"
  assert_file "$project/_base/frontend/sync-frontend.txt"
  assert_file "$project/feat-login/frontend/sync-frontend.txt"
  assert_not_exists "$project/_base/backend/sync-backend.txt"
  assert_not_exists "$project/feat-login/backend/sync-backend.txt"
}

test_sync_no_tasks_fails_before_pull() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  before_head=$(git -C "$project/_base/frontend" rev-parse HEAD)
  commit_to_remote_master frontend sync-no-task
  remote_head=$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse master)
  [ "$before_head" != "$remote_head" ] || fail "expected remote to advance"

  out=$(run_expect_fail "$WORKBRANCH" sync)
  assert_contains "$out" "no task workspaces to update"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$before_head" ] || fail "base advanced before no-task failure"
  assert_not_exists "$project/_base/frontend/sync-no-task.txt"
}

test_sync_update_preflight_failure_blocks_pull() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  before_head=$(git -C "$project/_base/frontend" rev-parse HEAD)
  commit_to_remote_master frontend sync-dirty-task
  printf '%s\n' "dirty task" > "$project/feat-login/backend/dirty.txt"

  out=$(run_expect_fail "$WORKBRANCH" sync)
  assert_contains "$out" "Cannot update: preflight failed"
  assert_contains "$out" "feat-login/backend dirty worktree"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$before_head" ] || fail "base advanced before update preflight failure"
  assert_not_exists "$project/_base/frontend/sync-dirty-task.txt"
  assert_not_exists "$project/feat-login/frontend/sync-dirty-task.txt"
}

test_sync_rejects_unexpected_positional_arg() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_fail "$WORKBRANCH" sync feat-login)
  assert_contains "$out" "usage: workbranch sync [--repo <repo>]"
}
