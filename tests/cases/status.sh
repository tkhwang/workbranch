# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.
test_list_shows_overridden_task_branches() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(printf 'tk/login-frontend\ntk/login-backend\n' | "$WORKBRANCH" add login 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "add failed: $out"

  out=$("$WORKBRANCH" list 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "list failed: $out"
  assert_contains "$out" "tk/login-frontend"
  assert_contains "$out" "tk/login-backend"
}

test_status_reports_base_task_diff_and_worktree_state() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  git -C "$project/login/frontend" config user.name "Workbranch Test"
  git -C "$project/login/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "task frontend" > "$project/login/frontend/task.txt"
  git -C "$project/login/frontend" add task.txt
  git -C "$project/login/frontend" commit -m "task frontend" >/dev/null

  printf '%s\n' "local note" > "$project/_base/frontend/local.txt"
  printf '%s\n' "changed" >> "$project/login/backend/README.md"

  base_frontend=$(git -C "$project/_base/frontend" rev-parse --short=9 HEAD)
  base_backend=$(git -C "$project/_base/backend" rev-parse --short=9 HEAD)
  task_frontend=$(git -C "$project/login/frontend" rev-parse --short=9 HEAD)
  task_backend=$(git -C "$project/login/backend" rev-parse --short=9 HEAD)

  out=$(run_expect_success "$WORKBRANCH" status)
  assert_contains "$out" "[*] Base worktrees"
  assert_contains "$out" "    repo        branch           commit     status"
  assert_contains "$out" "$(printf '    %-11s %-16s %-10s %s' frontend master "$base_frontend" untracked)"
  assert_contains "$out" "$(printf '    %-11s %-16s %-10s %s' backend master "$base_backend" clean)"
  case "$out" in
    *"$(printf '    %-11s %-16s %-10s %s' backend master "$base_backend" clean)"$'\n\n'"[*] Task workspaces"*) ;;
    *) fail "expected blank line between base worktrees and task workspaces; got: $out" ;;
  esac
  assert_contains "$out" "[*] Task workspaces"
  assert_contains "$out" "[*] login"
  assert_contains "$out" "    repo        base       task       diff  status    next"
  assert_contains "$out" "$(printf '    %-11s %-10s %-10s %-5s %-9s %s' frontend "$base_frontend" "$task_frontend" +1 clean land)"
  assert_contains "$out" "$(printf '    %-11s %-10s %-10s %-5s %-9s %s' backend "$base_backend" "$task_backend" 0 modified -)"
  assert_contains "$out" "[*] Next"
  assert_contains "$out" "land    task has commits not in base: workbranch land <task>"
  assert_contains "$out" "update  task is behind base: workbranch update <task>"
  assert_not_contains "$out" "Task summary"
}

test_status_repo_filter_skips_tasks_without_matching_rows() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  rm -rf "$project/login/frontend"

  out=$(run_expect_success "$WORKBRANCH" status --repo frontend)
  assert_contains "$out" "[*] Task workspaces"
  assert_contains "$out" "[*] (none)"
  assert_not_contains "$out" "[*] login"
  assert_not_contains "$out" "    repo        base       task       diff  status    next"
  assert_not_contains "$out" "[*] Next"
}

test_status_reports_stale_task_shaped_directories_separately() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  mkdir -p "$project/login/frontend" "$project/login/backend"

  out=$(run_expect_success "$WORKBRANCH" status)
  assert_contains "$out" "[*] Task workspaces"
  assert_contains "$out" "[*] (none)"
  assert_contains "$out" "[*] Stale directories"
  assert_contains "$out" "login    directory exists but no registered worktrees"
  assert_not_contains "$out" "    repo        base       task       diff  status    next"
}

test_status_reports_standalone_repo_task_dirs_as_stale() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  mkdir -p "$project/login/frontend" "$project/login/backend"
  git -C "$project/login/frontend" init -q >/dev/null
  git -C "$project/login/frontend" config user.name "Workbranch Test"
  git -C "$project/login/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "standalone frontend" > "$project/login/frontend/README.md"
  git -C "$project/login/frontend" add README.md
  git -C "$project/login/frontend" commit -m "standalone frontend" >/dev/null
  git -C "$project/login/backend" init -q >/dev/null
  git -C "$project/login/backend" config user.name "Workbranch Test"
  git -C "$project/login/backend" config user.email "workbranch-test@example.com"
  printf '%s\n' "standalone backend" > "$project/login/backend/README.md"
  git -C "$project/login/backend" add README.md
  git -C "$project/login/backend" commit -m "standalone backend" >/dev/null

  out=$(run_expect_success "$WORKBRANCH" status)
  assert_contains "$out" "[*] Task workspaces"
  assert_contains "$out" "[*] (none)"
  assert_contains "$out" "[*] Stale directories"
  assert_contains "$out" "login    directory exists but no registered worktrees"
  assert_not_contains "$out" "[*] login"
}

test_status_skips_partial_task_workspaces() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  rm -rf "$project/login/frontend"

  out=$(run_expect_success "$WORKBRANCH" status)
  assert_contains "$out" "[*] Task workspaces"
  assert_contains "$out" "[*] (none)"
  assert_not_contains "$out" "[*] login"
  assert_not_contains "$out" "[*] Next"
}

