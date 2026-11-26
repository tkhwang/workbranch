# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

assert_upstream() {
  got=$(git -C "$1" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || fail "expected upstream $2 in $1, got none"
  [ "$got" = "$2" ] || fail "expected upstream $2 in $1, got $got"
}

assert_no_upstream() {
  if got=$(git -C "$1" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null); then
    fail "expected no upstream in $1, got $got"
  fi
}

assert_no_local_branch() {
  if git -C "$1" show-ref --verify --quiet "refs/heads/$2"; then
    fail "expected no local branch $2 in $1"
  fi
}

test_checkout_tracks_remote_branch_in_every_repo() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feat/login remote-frontend
  commit_to_remote_branch backend feat/login remote-backend

  out=$(run_expect_success "$WORKBRANCH" checkout feat/login)

  assert_branch "$project/feat-login/frontend" "feat/login"
  assert_branch "$project/feat-login/backend" "feat/login"
  assert_file "$project/feat-login/frontend/remote-frontend.txt"
  assert_file "$project/feat-login/backend/remote-backend.txt"
  assert_upstream "$project/feat-login/frontend" "origin/feat/login"
  assert_upstream "$project/feat-login/backend" "origin/feat/login"
  assert_contains "$out" "[+] Created: feat-login/frontend"
  assert_contains "$out" "[+] Created: feat-login/backend"
  assert_contains "$out" "[remote] origin/feat/login -> [task repo] feat/login"
  assert_not_contains "$out" "not on origin"
  metadata=$(cat "$project/feat-login/.workbranch.task")
  assert_contains "$metadata" "REPO_BRANCH frontend feat/login"
  assert_contains "$metadata" "REPO_BRANCH backend feat/login"
  assert_file "$project/feat-login/AGENTS.md"
}

test_checkout_starts_new_branch_in_repos_without_the_remote_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feat/login remote-frontend

  out=$(run_expect_success "$WORKBRANCH" checkout feat/login)

  assert_upstream "$project/feat-login/frontend" "origin/feat/login"
  assert_branch "$project/feat-login/backend" "feat/login"
  assert_no_upstream "$project/feat-login/backend"
  base_head=$(git -C "$project/_base/backend" rev-parse HEAD)
  task_head=$(git -C "$project/feat-login/backend" rev-parse HEAD)
  [ "$task_head" = "$base_head" ] || fail "expected backend task branch to start from base HEAD $base_head, got $task_head"
  assert_contains "$out" "[remote] origin/feat/login -> [task repo] feat/login"
  assert_contains "$out" "[base repo] master -> [task repo] feat/login (new; not on origin)"
}

test_checkout_task_pushes_to_tracked_branch_and_removes_cleanly() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feat/login remote-frontend
  run_expect_success "$WORKBRANCH" checkout feat/login >/dev/null

  git -C "$project/feat-login/frontend" config user.name "Workbranch Test"
  git -C "$project/feat-login/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "local work" > "$project/feat-login/frontend/local-work.txt"
  git -C "$project/feat-login/frontend" add local-work.txt
  git -C "$project/feat-login/frontend" commit -m "local work" >/dev/null

  run_expect_success "$WORKBRANCH" push feat-login >/dev/null
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" feat/login local-work.txt "local work"
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" feat/login remote-frontend.txt "remote-frontend"
  assert_remote_file "$TMP_ROOT/remotes/backend.git" feat/login README.md "initial backend"

  run_expect_success "$WORKBRANCH" remove feat-login >/dev/null
  assert_not_exists "$project/feat-login"
  assert_no_local_branch "$project/_base/frontend" feat/login
  assert_no_local_branch "$project/_base/backend" feat/login
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" feat/login local-work.txt "local work"
}

test_checkout_accepts_origin_prefix_and_explicit_task_folder() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend tk/login-fix remote-frontend

  run_expect_success "$WORKBRANCH" checkout origin/tk/login-fix review/ >/dev/null

  assert_branch "$project/review/frontend" "tk/login-fix"
  assert_branch "$project/review/backend" "tk/login-fix"
  assert_upstream "$project/review/frontend" "origin/tk/login-fix"
  assert_not_exists "$project/tk-login-fix"
  out=$(run_expect_success "$WORKBRANCH" list)
  assert_contains "$out" "tk/login-fix"
}

test_checkout_derives_task_folder_from_branch_name() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend tk/login-fix remote-frontend

  run_expect_success "$WORKBRANCH" checkout tk/login-fix >/dev/null
  assert_branch "$project/tk-login-fix/frontend" "tk/login-fix"

  out=$(run_expect_fail "$WORKBRANCH" checkout feat/login+v2)
  assert_contains "$out" "cannot derive a task folder from branch 'feat/login+v2'"
  assert_contains "$out" "workbranch checkout feat/login+v2 <task>"
}

test_checkout_fails_when_no_repo_has_the_remote_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '%s\n' "dirty base" > "$project/_base/backend/dirty.txt"

  out=$(run_expect_fail "$WORKBRANCH" checkout feat/missing)
  assert_contains "$out" "no repo has remote branch origin/feat/missing"
  assert_contains "$out" "To start a new task branch instead: workbranch add"
  assert_not_contains "$out" "preflight failed"
  assert_not_exists "$project/feat-missing"
  assert_no_local_branch "$project/_base/frontend" feat/missing
  assert_no_local_branch "$project/_base/backend" feat/missing
}

test_checkout_rejects_existing_local_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feat/login remote-frontend
  git -C "$project/_base/frontend" branch feat/login

  out=$(run_expect_fail "$WORKBRANCH" checkout feat/login)
  assert_contains "$out" "Cannot checkout: preflight failed"
  assert_contains "$out" "_base/frontend local branch feat/login already exists"
  assert_contains "$out" "branch -d feat/login"
  assert_not_exists "$project/feat-login"
  assert_no_local_branch "$project/_base/backend" feat/login
}

test_checkout_names_the_worktree_that_already_uses_the_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feat/login remote-frontend
  run_expect_success "$WORKBRANCH" checkout feat/login >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" checkout feat/login review)
  assert_contains "$out" "Cannot checkout: preflight failed"
  assert_contains "$out" "_base/frontend branch feat/login is already checked out at feat-login/frontend"
  assert_contains "$out" "_base/backend branch feat/login is already checked out at feat-login/backend"
  assert_not_exists "$project/review"
  assert_branch "$project/feat-login/frontend" "feat/login"
}

test_checkout_rejects_existing_task_directory() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feat/login remote-frontend
  mkdir "$project/feat-login"

  out=$(run_expect_fail "$WORKBRANCH" checkout feat/login)
  assert_contains "$out" "task directory already exists"
  assert_no_local_branch "$project/_base/frontend" feat/login
}

test_checkout_rejects_stale_remote_tracking_ref() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feat/login remote-frontend
  commit_to_remote_branch backend feat/login remote-backend
  # A user-level fetch.prune would drop the stale ref before checkout sees it.
  git -C "$project/_base/backend" config fetch.prune false
  git -C "$project/_base/backend" fetch origin >/dev/null 2>&1
  git --git-dir="$TMP_ROOT/remotes/backend.git" branch -D feat/login >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" checkout feat/login)
  assert_contains "$out" "Cannot checkout: preflight failed"
  assert_contains "$out" "_base/backend has a stale origin/feat/login; origin no longer has that branch"
  assert_contains "$out" "branch -dr origin/feat/login"
  assert_not_exists "$project/feat-login"
  assert_no_local_branch "$project/_base/frontend" feat/login

  git -C "$project/_base/backend" branch -dr origin/feat/login >/dev/null
  run_expect_success "$WORKBRANCH" checkout feat/login >/dev/null
  assert_upstream "$project/feat-login/frontend" "origin/feat/login"
  assert_no_upstream "$project/feat-login/backend"
  assert_not_exists "$project/feat-login/backend/remote-backend.txt"
}

test_checkout_requires_clean_base_only_where_it_creates_the_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feat/login remote-frontend
  printf '%s\n' "dirty base" > "$project/_base/backend/dirty.txt"

  out=$(run_expect_fail "$WORKBRANCH" checkout feat/login)
  assert_contains "$out" "Cannot checkout: preflight failed"
  assert_contains "$out" "_base/backend dirty worktree"
  assert_contains "$out" "_base/backend has no origin/feat/login, so its task branch starts from the local base worktree"
  assert_not_exists "$project/feat-login"
  assert_no_local_branch "$project/_base/frontend" feat/login

  rm "$project/_base/backend/dirty.txt"
  printf '%s\n' "dirty base" > "$project/_base/frontend/dirty.txt"
  run_expect_success "$WORKBRANCH" checkout feat/login >/dev/null
  assert_upstream "$project/feat-login/frontend" "origin/feat/login"
  assert_file "$project/_base/frontend/dirty.txt"
}

test_checkout_rejects_configured_base_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" checkout master)
  assert_contains "$out" "Cannot checkout: preflight failed"
  assert_contains "$out" "_base/frontend master is the configured base branch"
  assert_contains "$out" "_base/backend master is the configured base branch"
  assert_not_exists "$project/master"
}

test_checkout_rejects_missing_or_extra_arguments() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  out=$(run_expect_fail "$WORKBRANCH" checkout)
  assert_contains "$out" "usage: workbranch checkout <branch> [<task>]"
  out=$(run_expect_fail "$WORKBRANCH" checkout feat/login review extra)
  assert_contains "$out" "usage: workbranch checkout <branch> [<task>]"
  out=$(run_expect_fail "$WORKBRANCH" checkout feat/login --from master)
  assert_contains "$out" "usage: workbranch checkout <branch> [<task>]"
  out=$(run_expect_fail "$WORKBRANCH" checkout "bad branch")
  assert_contains "$out" "invalid branch 'bad branch'"
}

test_checkout_rolls_back_when_worktree_creation_fails() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feat/login remote-frontend
  commit_to_remote_branch backend feat/login remote-backend

  real_git=$(command -v git)
  fakebin="$TMP_ROOT/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/git" <<'GIT'
#!/usr/bin/env bash
if [ "${1:-}" = "-C" ] && [ "${2:-}" = "$FAIL_WORKTREE_BASE" ] && [ "${3:-}" = "worktree" ] && [ "${4:-}" = "add" ]; then
  exit 1
fi
exec "$REAL_GIT" "$@"
GIT
  chmod +x "$fakebin/git"

  old_path=$PATH
  export REAL_GIT=$real_git
  export FAIL_WORKTREE_BASE=$(cd "$project/_base/backend" && pwd -P)
  PATH="$fakebin:$PATH"
  out=$(run_expect_fail "$WORKBRANCH" checkout feat/login)
  PATH=$old_path
  unset REAL_GIT FAIL_WORKTREE_BASE

  assert_contains "$out" "failed to create worktree for repo 'backend'"
  assert_not_exists "$project/feat-login"
  assert_no_local_branch "$project/_base/frontend" feat/login
  assert_no_local_branch "$project/_base/backend" feat/login
  if git -C "$project/_base/frontend" worktree list --porcelain | grep -F "$project/feat-login/frontend" >/dev/null; then
    fail "expected rollback to remove frontend worktree registration"
  fi
}

test_checkout_runs_configured_task_setup() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  mkdir -p "$project/scripts"
  cat > "$project/scripts/workbranch-setup.sh" <<'SCRIPT'
#!/usr/bin/env sh
set -eu
printf '%s\n' "$WORKBRANCH_TASK" > "$WORKBRANCH_TASK_DIR/setup-task.txt"
SCRIPT
  printf '\nTASK_SETUP sh scripts/workbranch-setup.sh\n' >> "$project/.workbranch.config"
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feat/login remote-frontend

  out=$(run_expect_success "$WORKBRANCH" checkout feat/login)
  assert_contains "$out" "[+] Task setup completed: feat-login"
  assert_contains "$(cat "$project/feat-login/setup-task.txt")" "feat-login"
}

test_checkout_setup_failure_keeps_worktrees_and_names_the_retry() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  printf '\nTASK_SETUP false\n' >> "$project/.workbranch.config"
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feat/login remote-frontend

  out=$(run_expect_fail "$WORKBRANCH" checkout feat/login)
  assert_contains "$out" "task setup failed"
  assert_contains "$out" "or remove and check out the task again."
  assert_branch "$project/feat-login/frontend" "feat/login"
}
