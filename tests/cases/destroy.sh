# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

test_destroy_force_removes_project_and_registry() {
  new_fixture
  project="$FIXTURE_PROJECT"
  xdg="$TMP_ROOT/xdg"
  cd "$project" || return 1
  run_expect_success env XDG_CONFIG_HOME="$xdg" "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  project_real=$(cd "$project" && pwd -P)

  out=$(run_expect_success env XDG_CONFIG_HOME="$xdg" "$WORKBRANCH" destroy --force)
  assert_contains "$out" "Destroyed workbranch project"
  assert_not_exists "$project_real"
  registry="$xdg/workbranch-companion/projects.md"
  if [ -f "$registry" ]; then
    assert_not_contains "$(cat "$registry")" "- $project_real"
  fi
}

test_destroy_blocks_dirty_without_force() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  printf '%s\n' dirty > "$project/login/frontend/dirty.txt"

  out=$(run_expect_fail "$WORKBRANCH" destroy)
  assert_contains "$out" "Cannot destroy: preflight failed"
  assert_contains "$out" "login/frontend dirty worktree"
  assert_dir "$project"
}


test_destroy_blocks_dirty_partial_task_without_force() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  rm -rf "$project/login/frontend"
  printf '%s\n' dirty > "$project/login/backend/dirty.txt"

  out=$(run_expect_fail "$WORKBRANCH" destroy)
  assert_contains "$out" "Cannot destroy: preflight failed"
  assert_contains "$out" "login/backend dirty worktree"
  assert_dir "$project"
  assert_file "$project/login/backend/dirty.txt"
}

test_destroy_rejects_keep_files_and_forget_absent() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" destroy --keep-files)
  assert_contains "$out" "usage: workbranch destroy [--force]"
  out=$(run_expect_fail "$WORKBRANCH" forget)
  assert_contains "$out" "unknown command: forget"
}

test_destroy_skips_unpushed_check_when_base_repo_is_detached_head() {
  new_fixture
  project="$FIXTURE_PROJECT"
  xdg="$TMP_ROOT/xdg"
  cd "$project" || return 1
  run_expect_success env XDG_CONFIG_HOME="$xdg" "$WORKBRANCH" init >/dev/null
  git -C "$project/_base/frontend" config user.name "Workbranch Test"
  git -C "$project/_base/frontend" config user.email "workbranch-test@example.com"
  git -C "$project/_base/frontend" checkout --detach >/dev/null 2>&1
  printf '%s\n' detached-change > "$project/_base/frontend/detached.txt"
  git -C "$project/_base/frontend" add detached.txt
  git -C "$project/_base/frontend" commit -m detached-change >/dev/null

  out=$(printf 'y\n' | run_expect_success env XDG_CONFIG_HOME="$xdg" WORKBRANCH_ALLOW_NON_TTY_PROMPT=1 "$WORKBRANCH" destroy)
  assert_contains "$out" "Destroyed workbranch project"
  assert_not_contains "$out" "has unpushed commits"
  assert_not_exists "$project"
}

test_destroy_force_continues_when_base_repo_is_missing() {
  new_fixture
  project="$FIXTURE_PROJECT"
  xdg="$TMP_ROOT/xdg"
  cd "$project" || return 1
  run_expect_success env XDG_CONFIG_HOME="$xdg" "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  project_real=$(cd "$project" && pwd -P)
  rm -rf "$project/_base/frontend"

  out=$(run_expect_success env XDG_CONFIG_HOME="$xdg" "$WORKBRANCH" destroy --force)
  assert_contains "$out" "Warning: _base/frontend missing git repo; continuing forced destroy"
  assert_contains "$out" "Destroyed workbranch project"
  assert_not_exists "$project_real"
}
