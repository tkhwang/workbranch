# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

doctor_with_status() {
  "$WORKBRANCH" doctor "$@" 2>&1
  printf 'status=%s' "$?"
}

test_doctor_healthy_project_exits_zero() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null

  out=$(doctor_with_status)
  assert_contains "$out" "Base repos"
  assert_contains "$out" "Task workspaces"
  assert_contains "$out" "feat-login"
  assert_contains "$out" "healthy"
  assert_contains "$out" "doctor found no issues"
  assert_contains "$out" "status=0"
}

test_doctor_detects_partial_workspace() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  git -C "$project/_base/backend" worktree remove --force "$project/feat-login/backend" >/dev/null 2>&1

  out=$(doctor_with_status)
  assert_contains "$out" "feat-login"
  assert_contains "$out" "partial"
  assert_contains "$out" "backend worktree missing"
  assert_contains "$out" "status=1"
}

test_doctor_repo_scope_ignores_filtered_out_task_damage() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  git -C "$project/_base/frontend" worktree remove --force "$project/feat-login/frontend" >/dev/null 2>&1

  out=$(doctor_with_status --repo backend)
  assert_contains "$out" "feat-login"
  assert_contains "$out" "healthy"
  assert_not_contains "$out" "frontend worktree missing"
  assert_contains "$out" "status=0"

  git -C "$project/_base/backend" worktree remove --force "$project/feat-login/backend" >/dev/null 2>&1
  out=$(doctor_with_status --repo backend)
  assert_contains "$out" "feat-login"
  assert_contains "$out" "backend"
  assert_contains "$out" "status=1"
}

test_doctor_reports_registered_task_worktree_on_wrong_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  git -C "$project/feat-login/backend" checkout -b wrong-doctor-branch >/dev/null 2>&1

  out=$(doctor_with_status)
  assert_contains "$out" "feat-login"
  assert_contains "$out" "partial"
  assert_contains "$out" "backend expected branch feat/login, got wrong-doctor-branch"
  assert_contains "$out" "status=1"
}

test_doctor_reports_base_branch_drift() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  git -C "$project/_base/backend" checkout -b hotfix >/dev/null 2>&1

  out=$(doctor_with_status)
  assert_contains "$out" "backend"
  assert_contains "$out" "expected master, got hotfix"
  assert_contains "$out" "status=1"
}

test_doctor_reports_stale_directory_with_remove_hint() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  mkdir -p "$project/old-task/frontend" "$project/old-task/backend"

  out=$(doctor_with_status)
  assert_contains "$out" "old-task"
  assert_contains "$out" "stale"
  assert_contains "$out" "workbranch remove old-task"
  assert_contains "$out" "status=1"
}

test_doctor_rejects_unexpected_args_and_flags() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_fail "$WORKBRANCH" doctor feat-login)
  assert_contains "$out" "usage: workbranch doctor [--fix] [--repo <repo>]"

  out=$(run_expect_fail "$WORKBRANCH" doctor --bad)
  assert_contains "$out" "usage: workbranch doctor [--fix] [--repo <repo>]"
}

test_doctor_fix_prunes_stale_worktree_registration() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  git -C "$project/_base/frontend" worktree add "$TMP_ROOT/ghost-frontend" -b ghost-doctor HEAD >/dev/null 2>&1
  rm -rf "$TMP_ROOT/ghost-frontend"

  out=$(doctor_with_status)
  assert_contains "$out" "Prunable worktrees"
  assert_contains "$out" "frontend"
  assert_contains "$out" "workbranch doctor --fix"
  assert_contains "$out" "status=1"

  fix_out=$(doctor_with_status --fix --repo frontend)
  assert_contains "$fix_out" "Pruned stale worktree registrations: frontend"
  assert_contains "$fix_out" "status=0"
  worktrees=$(git -C "$project/_base/frontend" worktree list --porcelain)
  assert_not_contains "$worktrees" "prunable"
}

test_doctor_fix_does_not_delete_stale_task_directory() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  mkdir -p "$project/old-task/frontend" "$project/old-task/backend"

  out=$(doctor_with_status --fix)
  assert_contains "$out" "old-task"
  assert_contains "$out" "workbranch remove old-task"
  assert_contains "$out" "status=1"
  assert_dir "$project/old-task"
}
