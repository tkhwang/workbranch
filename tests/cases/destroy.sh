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
