# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.
test_path_prints_task_and_repo_paths() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  canonical_project=$(pwd -P)
  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '

' | run_expect_success "$WORKBRANCH" add login >/dev/null

  out=$(run_expect_success "$WORKBRANCH" path login)
  [ "$out" = "$canonical_project/login" ] || fail "expected task path, got: $out"

  out=$(run_expect_success "$WORKBRANCH" path login --repo frontend)
  [ "$out" = "$canonical_project/login/frontend" ] || fail "expected frontend path, got: $out"

  out=$(run_expect_fail "$WORKBRANCH" path missing)
  assert_contains "$out" "task workspace not found: missing"

  out=$(run_expect_fail "$WORKBRANCH" path login --repo unknown)
  assert_contains "$out" "unknown repo: unknown"
}

test_scoped_tool_paths_reject_stale_task_directories() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  fake_tool="$TMP_ROOT/fake-tool.sh"
  append_fake_tool_script "$fake_tool"
  export WORKBRANCH_FAKE_TOOL_LOG="$TMP_ROOT/tool.log"

  cat >> "$project/.workbranch.config" <<CONFIG
IDE $fake_tool
CONFIG

  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '

' | run_expect_success "$WORKBRANCH" add login >/dev/null
  git -C "$project/_base/frontend" worktree remove --force "$project/login/frontend"
  git -C "$project/_base/backend" worktree remove --force "$project/login/backend"
  mkdir -p "$project/login/frontend" "$project/login/backend"

  out=$(run_expect_fail "$WORKBRANCH" path login --repo frontend)
  assert_contains "$out" "task repo not found or not a registered worktree: login/frontend"

  out=$(run_expect_fail "$WORKBRANCH" ide login --repo frontend)
  assert_contains "$out" "task repo not found or not a registered worktree: login/frontend"
  assert_not_exists "$WORKBRANCH_FAKE_TOOL_LOG"
}

