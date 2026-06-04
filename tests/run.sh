#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)
WORKBRANCH="$REPO_ROOT/bin/workbranch"

PASS=0
FAIL=0
TMP_ROOT=""
FIXTURE_PROJECT=""

log() { printf '%s\n' "$*"; }
fail() { log "FAIL: $*"; exit 1; }

assert_file() { [ -f "$1" ] || fail "expected file: $1"; }
assert_dir() { [ -d "$1" ] || fail "expected dir: $1"; }
assert_not_exists() { [ ! -e "$1" ] || fail "expected missing: $1"; }
assert_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) fail "expected output to contain '$2'; got: $1" ;;
  esac
}
assert_not_contains() {
  case "$1" in
    *"$2"*) fail "expected output not to contain '$2'; got: $1" ;;
    *) return 0 ;;
  esac
}
assert_branch() {
  got=$(git -C "$1" branch --show-current 2>/dev/null) || fail "could not read branch in $1"
  [ "$got" = "$2" ] || fail "expected branch $2 in $1, got $got"
}
assert_clean() {
  got=$(git -C "$1" status --porcelain) || fail "could not read status in $1"
  [ -z "$got" ] || fail "expected clean worktree in $1, got: $got"
}
assert_remote_file() {
  got=$(git --git-dir="$1" show "$2:$3" 2>/dev/null) || fail "expected $3 in $2 at $1"
  [ "$got" = "$4" ] || fail "expected $2:$3 to be '$4', got '$got'"
}
assert_remote_missing_file() {
  if git --git-dir="$1" show "$2:$3" >/dev/null 2>&1; then
    fail "expected missing $3 in $2 at $1"
  fi
}

manifest_version() {
  sed -n 's/.*"[.]": *"\([^"]*\)".*/\1/p' "$REPO_ROOT/.release-please-manifest.json"
}

run_expect_success() {
  out=$("$@" 2>&1)
  status=$?
  [ $status -eq 0 ] || fail "expected success: $*\n$out"
  printf '%s' "$out"
}

run_expect_fail() {
  out=$("$@" 2>&1)
  status=$?
  [ $status -ne 0 ] || fail "expected failure: $*"
  printf '%s' "$out"
}

make_repo() {
  name=$1
  seed="$TMP_ROOT/seeds/$name"
  remote="$TMP_ROOT/remotes/$name.git"
  mkdir -p "$seed"
  git -C "$seed" init -q >/dev/null
  git -C "$seed" config user.name "Workbranch Test"
  git -C "$seed" config user.email "workbranch-test@example.com"
  printf '%s\n' "initial $name" > "$seed/README.md"
  git -C "$seed" add README.md
  git -C "$seed" commit -m "initial $name" >/dev/null
  git -C "$seed" branch -M master
  git clone --bare "$seed" "$remote" >/dev/null 2>&1
  printf '%s' "$remote"
}

commit_to_remote_master() {
  name=$1
  msg=$2
  commit_to_remote_branch "$name" master "$msg"
}

commit_to_remote_branch() {
  name=$1
  branch=$2
  msg=$3
  clone="$TMP_ROOT/upstream-$name-$branch-$msg"
  git clone "$TMP_ROOT/remotes/$name.git" "$clone" >/dev/null 2>&1
  git -C "$clone" config user.name "Workbranch Test"
  git -C "$clone" config user.email "workbranch-test@example.com"
  git -C "$clone" checkout -B "$branch" "origin/$branch" >/dev/null 2>&1 || git -C "$clone" checkout -b "$branch" >/dev/null 2>&1
  printf '%s\n' "$msg" > "$clone/$msg.txt"
  git -C "$clone" add "$msg.txt"
  git -C "$clone" commit -m "$msg" >/dev/null
  git -C "$clone" push origin "$branch" >/dev/null 2>&1
}

new_fixture() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/fullstack"
  frontend_remote=$(make_repo frontend)
  backend_remote=$(make_repo backend)
  cat > "$TMP_ROOT/fullstack/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $frontend_remote master
REPO backend $backend_remote master
CONFIG
  FIXTURE_PROJECT="$TMP_ROOT/fullstack"
}

cleanup_fixture() {
  cd "$REPO_ROOT" 2>/dev/null || true
  if [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT"
  fi
  TMP_ROOT=""
}

run_test() {
  test_name=$1
  log "==> $test_name"
  if "$test_name"; then
    PASS=$((PASS + 1))
    log "PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    log "FAIL: $test_name"
  fi
  cleanup_fixture
}

test_generated_workbranch_is_up_to_date() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  generated="$TMP_ROOT/workbranch.generated"
  "$REPO_ROOT/scripts/build-workbranch.sh" "$generated" >/dev/null
  cmp "$generated" "$WORKBRANCH" >/dev/null || fail "bin/workbranch is stale; run scripts/build-workbranch.sh"
}

test_safe_names_reject_dot_and_dotdot() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME .
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature
REPO frontend $TMP_ROOT/remotes/frontend.git master
CONFIG
  out=$(run_expect_fail "$WORKBRANCH" list)
  assert_contains "$out" "invalid PROJECT_NAME '.'"

  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR ..
BRANCH_PREFIX feature
REPO frontend $TMP_ROOT/remotes/frontend.git master
CONFIG
  out=$(run_expect_fail "$WORKBRANCH" list)
  assert_contains "$out" "invalid MAIN_WORKTREES_DIR '..'"

  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature
REPO . $TMP_ROOT/remotes/frontend.git master
CONFIG
  out=$(run_expect_fail "$WORKBRANCH" list)
  assert_contains "$out" "invalid repo name '.'"
}

test_invalid_config_rejected_without_execution() {
  new_fixture
  project="$FIXTURE_PROJECT"
  rm -rf "$project/_base"
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature
REPO frontend $TMP_ROOT/remotes/frontend.git master
CONFIG
  printf 'unknown $(touch %s)\n' "$TMP_ROOT/pwned" >> "$project/.workbranch.config"
  out=$(cd "$project" && run_expect_fail "$WORKBRANCH" list)
  assert_contains "$out" "unknown directive"
  assert_not_exists "$TMP_ROOT/pwned"
}

test_init_existing_config_clones_base_repos() {
  new_fixture
  project="$FIXTURE_PROJECT"
  out=$(cd "$project" && run_expect_success "$WORKBRANCH" init)
  assert_contains "$out" "Initialized"
  assert_dir "$project/_base/frontend/.git"
  assert_dir "$project/_base/backend/.git"
  assert_branch "$project/_base/frontend" "master"
  assert_branch "$project/_base/backend" "master"
}

test_init_completes_partial_base_clones() {
  new_fixture
  project="$FIXTURE_PROJECT"
  (cd "$project" && run_expect_success "$WORKBRANCH" init >/dev/null)
  printf '%s\n' "keep existing frontend clone" > "$project/_base/frontend/untouched.txt"
  rm -rf "$project/_base/backend"

  out=$(cd "$project" && run_expect_success "$WORKBRANCH" init)
  assert_contains "$out" "Base repo exists: _base/frontend"
  assert_contains "$out" "Cloned: _base/backend"
  assert_file "$project/_base/frontend/untouched.txt"
  assert_dir "$project/_base/frontend/.git"
  assert_dir "$project/_base/backend/.git"
  assert_branch "$project/_base/frontend" "master"
  assert_branch "$project/_base/backend" "master"
}

test_init_rejects_already_initialized_workbranch_project() {
  new_fixture
  project="$FIXTURE_PROJECT"
  (cd "$project" && run_expect_success "$WORKBRANCH" init >/dev/null)
  project_real=$(cd "$project" && pwd -P)

  out=$(cd "$project" && run_expect_fail "$WORKBRANCH" init)
  assert_contains "$out" "workbranch project already initialized: $project_real"
  assert_contains "$out" "To edit project settings: workbranch config"
}

test_init_from_project_subdir_uses_parent_config() {
  new_fixture
  project="$FIXTURE_PROJECT"
  mkdir -p "$project/docs"
  input=$(cat <<INPUT

.
nested
_base
feature
frontend
$TMP_ROOT/remotes/frontend.git
master
n

n
INPUT
)

  project_real=$(cd "$project" && pwd -P)
  out=$(cd "$project/docs" && printf '%s' "$input" | run_expect_success "$WORKBRANCH" init)
  assert_contains "$out" "Initialized workbranch project: $project_real"
  assert_not_contains "$out" "Create a new workbranch project"
  assert_dir "$project/_base/frontend/.git"
  assert_dir "$project/_base/backend/.git"
  assert_not_exists "$project/docs/nested"
}

test_init_rejects_existing_non_git_base_target() {
  new_fixture
  project="$FIXTURE_PROJECT"
  mkdir -p "$project/_base/frontend"
  printf '%s\n' "not a git repo" > "$project/_base/frontend/README.txt"

  out=$(cd "$project" && run_expect_fail "$WORKBRANCH" init)
  assert_contains "$out" "base repo path exists but is not a git repo: _base/frontend"
  assert_not_exists "$project/_base/backend"
}

test_init_rejects_existing_non_directory_base_target() {
  new_fixture
  project="$FIXTURE_PROJECT"
  mkdir -p "$project/_base"
  printf '%s\n' "not a directory" > "$project/_base/frontend"

  out=$(cd "$project" && run_expect_fail "$WORKBRANCH" init)
  assert_contains "$out" "base repo path exists but is not a directory: _base/frontend"
  assert_not_exists "$project/_base/backend"

  rm -f "$project/_base/frontend"
  ln -s "$project/_base/missing-target" "$project/_base/frontend"
  out=$(cd "$project" && run_expect_fail "$WORKBRANCH" init)
  assert_contains "$out" "base repo path exists but is not a directory: _base/frontend"
  assert_not_exists "$project/_base/backend"
}

test_failed_init_rolls_back_command_created_base_paths() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git master
REPO missing $TMP_ROOT/remotes/missing.git master
CONFIG
  out=$(cd "$project" && run_expect_fail "$WORKBRANCH" init)
  assert_contains "$out" "failed to clone repo 'missing'"
  assert_not_exists "$project/_base/frontend"
  assert_not_exists "$project/_base"
}

test_failed_init_reports_git_clone_reason() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git does-not-exist
CONFIG
  out=$(cd "$project" && run_expect_fail "$WORKBRANCH" init)
  assert_contains "$out" "failed to clone repo 'frontend'"
  assert_contains "$out" "Remote branch does-not-exist not found"
}

test_full_git_flow() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_success "$WORKBRANCH" add login)
  assert_contains "$out" "[+] Created: login/frontend"
  assert_contains "$out" "[+]   [base repo] master -> [task repo] feature/login"
  assert_contains "$out" "[+] Created: login/backend"
  assert_contains "$out" "[+]   [base repo] master -> [task repo] feature/login"
  assert_file "$project/login/frontend/.git"
  assert_file "$project/login/backend/.git"
  assert_branch "$project/login/frontend" "feature/login"
  assert_branch "$project/login/backend" "feature/login"

  out=$(run_expect_fail "$WORKBRANCH" add login)
  assert_contains "$out" "already exists"

  out=$(run_expect_success "$WORKBRANCH" list)
  assert_contains "$out" "Base: _base"
  assert_contains "$out" "    repo        base             current"
  assert_contains "$out" "$(printf '    %-11s %-16s %s' frontend master master)"
  assert_contains "$out" "$(printf '    %-11s %-16s %s' backend master master)"
  assert_contains "$out" "[*] login"
  assert_not_contains "$out" "Task: login"
  assert_contains "$out" "    repo        branch"
  assert_contains "$out" "$(printf '    %-11s %s' frontend feature/login)"
  assert_contains "$out" "$(printf '    %-11s %s' backend feature/login)"

  commit_to_remote_master frontend upstream-change
  run_expect_success "$WORKBRANCH" pull >/dev/null
  assert_file "$project/_base/frontend/upstream-change.txt"
  assert_not_exists "$project/login/frontend/upstream-change.txt"

  run_expect_success "$WORKBRANCH" update login >/dev/null
  assert_file "$project/login/frontend/upstream-change.txt"

  git -C "$project/login/frontend" config user.name "Workbranch Test"
  git -C "$project/login/frontend" config user.email "workbranch-test@example.com"
  git -C "$project/login/backend" config user.name "Workbranch Test"
  git -C "$project/login/backend" config user.email "workbranch-test@example.com"

  printf '%s\n' "task frontend" > "$project/login/frontend/task.txt"
  git -C "$project/login/frontend" add task.txt
  git -C "$project/login/frontend" commit -m "task frontend" >/dev/null
  printf '%s\n' "task backend" > "$project/login/backend/task.txt"
  git -C "$project/login/backend" add task.txt
  git -C "$project/login/backend" commit -m "task backend" >/dev/null
  run_expect_success "$WORKBRANCH" push login >/dev/null
  git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse --verify refs/heads/feature/login >/dev/null
  git --git-dir="$TMP_ROOT/remotes/backend.git" rev-parse --verify refs/heads/feature/login >/dev/null

  run_expect_success "$WORKBRANCH" remove login >/dev/null
  assert_not_exists "$project/login"
  if git -C "$project/_base/frontend" show-ref --verify --quiet refs/heads/feature/login; then
    fail "expected remove to delete local frontend feature/login branch"
  fi
  if git -C "$project/_base/backend" show-ref --verify --quiet refs/heads/feature/login; then
    fail "expected remove to delete local backend feature/login branch"
  fi
  git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse --verify refs/heads/feature/login >/dev/null
  git --git-dir="$TMP_ROOT/remotes/backend.git" rev-parse --verify refs/heads/feature/login >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" add login)
  assert_contains "$out" "task branch already exists for repo 'frontend': feature/login"
  assert_contains "$out" "To resume it: workbranch resume login"

  out=$(run_expect_success "$WORKBRANCH" resume login)
  assert_contains "$out" "[+] Resumed: login/frontend"
  assert_contains "$out" "[+]   [base repo] master -> [task repo] feature/login"
  assert_contains "$out" "[+] Resumed: login/backend"
  assert_contains "$out" "[+]   [base repo] master -> [task repo] feature/login"
  assert_file "$project/login/frontend/.git"
  assert_file "$project/login/backend/.git"
  assert_file "$project/login/frontend/task.txt"
  assert_file "$project/login/backend/task.txt"
}

test_update_all_updates_every_task_workspace() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  run_expect_success "$WORKBRANCH" add payment >/dev/null

  commit_to_remote_master frontend upstream-all
  run_expect_success "$WORKBRANCH" pull >/dev/null
  assert_not_exists "$project/login/frontend/upstream-all.txt"
  assert_not_exists "$project/payment/frontend/upstream-all.txt"

  git -C "$project/_base/backend" config user.name "Workbranch Test"
  git -C "$project/_base/backend" config user.email "workbranch-test@example.com"
  printf '%s\n' "local base only" > "$project/_base/backend/local-base-only.txt"
  git -C "$project/_base/backend" add local-base-only.txt
  git -C "$project/_base/backend" commit -m "local base only" >/dev/null
  assert_not_exists "$project/login/backend/local-base-only.txt"
  assert_not_exists "$project/payment/backend/local-base-only.txt"

  run_expect_success "$WORKBRANCH" update >/dev/null
  assert_file "$project/login/frontend/upstream-all.txt"
  assert_file "$project/payment/frontend/upstream-all.txt"
  assert_file "$project/login/backend/local-base-only.txt"
  assert_file "$project/payment/backend/local-base-only.txt"

  printf '%s\n' "local base alias" > "$project/_base/backend/local-base-alias.txt"
  git -C "$project/_base/backend" add local-base-alias.txt
  git -C "$project/_base/backend" commit -m "local base alias" >/dev/null
  assert_not_exists "$project/login/backend/local-base-alias.txt"
  assert_not_exists "$project/payment/backend/local-base-alias.txt"

  run_expect_success "$WORKBRANCH" update --all >/dev/null
  assert_file "$project/login/backend/local-base-alias.txt"
  assert_file "$project/payment/backend/local-base-alias.txt"
}

test_update_accepts_gitfile_base_worktree() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null

  moved_git_dir="$TMP_ROOT/frontend-base.git"
  mv "$project/_base/frontend/.git" "$moved_git_dir"
  printf '%s\n' "gitdir: $moved_git_dir" > "$project/_base/frontend/.git"

  run_expect_success "$WORKBRANCH" add login >/dev/null

  git -C "$project/_base/frontend" config user.name "Workbranch Test"
  git -C "$project/_base/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "base gitfile update" > "$project/_base/frontend/base-gitfile.txt"
  git -C "$project/_base/frontend" add base-gitfile.txt
  git -C "$project/_base/frontend" commit -m "base gitfile update" >/dev/null

  out=$(run_expect_success "$WORKBRANCH" update login --repo frontend)
  assert_contains "$out" "Updated: login/frontend"
  assert_file "$project/login/frontend/base-gitfile.txt"
}

test_update_preflight_blocks_batch_before_changes() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  run_expect_success "$WORKBRANCH" add payment >/dev/null

  commit_to_remote_master frontend upstream-blocked
  run_expect_success "$WORKBRANCH" pull --repo frontend >/dev/null
  printf '%s\n' "dirty payment backend" > "$project/payment/backend/dirty.txt"

  out=$(run_expect_fail "$WORKBRANCH" update)
  assert_contains "$out" "Cannot update: preflight failed"
  assert_contains "$out" "payment/backend dirty worktree"
  assert_not_exists "$project/login/frontend/upstream-blocked.txt"
  assert_not_exists "$project/payment/frontend/upstream-blocked.txt"
}

test_update_preflight_requires_base_worktree_on_configured_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  git -C "$project/_base/frontend" config user.name "Workbranch Test"
  git -C "$project/_base/frontend" config user.email "workbranch-test@example.com"
  git -C "$project/_base/frontend" checkout -b unrelated >/dev/null 2>&1
  printf '%s\n' "wrong base" > "$project/_base/frontend/wrong-base.txt"
  git -C "$project/_base/frontend" add wrong-base.txt
  git -C "$project/_base/frontend" commit -m "wrong base" >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" update login --repo frontend)
  assert_contains "$out" "Cannot update: preflight failed"
  assert_contains "$out" "_base/frontend expected branch master, got unrelated"
  assert_not_exists "$project/login/frontend/wrong-base.txt"
}

test_update_preflight_blocks_base_rebase_in_progress() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  git_dir=$(git -C "$project/_base/frontend" rev-parse --git-dir)
  case "$git_dir" in
    /*) git_dir_path=$git_dir ;;
    *) git_dir_path="$project/_base/frontend/$git_dir" ;;
  esac
  mkdir -p "$git_dir_path/rebase-merge"

  out=$(run_expect_fail "$WORKBRANCH" update login --repo frontend)
  assert_contains "$out" "Cannot update: preflight failed"
  assert_contains "$out" "_base/frontend rebase in progress"
}

test_repo_scope_limits_git_commands_to_one_repo() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  commit_to_remote_master frontend frontend-upstream
  commit_to_remote_master backend backend-upstream
  run_expect_success "$WORKBRANCH" pull --repo frontend >/dev/null
  assert_file "$project/_base/frontend/frontend-upstream.txt"
  assert_not_exists "$project/_base/backend/backend-upstream.txt"

  run_expect_success "$WORKBRANCH" update login --repo frontend >/dev/null
  assert_file "$project/login/frontend/frontend-upstream.txt"
  assert_not_exists "$project/login/backend/backend-upstream.txt"

  git -C "$project/login/frontend" config user.name "Workbranch Test"
  git -C "$project/login/frontend" config user.email "workbranch-test@example.com"
  git -C "$project/login/backend" config user.name "Workbranch Test"
  git -C "$project/login/backend" config user.email "workbranch-test@example.com"
  printf '%s\n' "frontend scoped" > "$project/login/frontend/scoped.txt"
  git -C "$project/login/frontend" add scoped.txt
  git -C "$project/login/frontend" commit -m "frontend scoped" >/dev/null
  printf '%s\n' "backend scoped" > "$project/login/backend/scoped.txt"
  git -C "$project/login/backend" add scoped.txt
  git -C "$project/login/backend" commit -m "backend scoped" >/dev/null

  run_expect_success "$WORKBRANCH" push login --repo frontend >/dev/null
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" feature/login scoped.txt "frontend scoped"
  assert_remote_missing_file "$TMP_ROOT/remotes/backend.git" feature/login scoped.txt

  run_expect_success "$WORKBRANCH" land login --repo frontend >/dev/null
  run_expect_success "$WORKBRANCH" push --repo frontend >/dev/null
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" master scoped.txt "frontend scoped"
  assert_remote_missing_file "$TMP_ROOT/remotes/backend.git" master scoped.txt
}

test_land_preflight_blocks_all_repos_before_partial_land() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  git -C "$project/login/frontend" config user.name "Workbranch Test"
  git -C "$project/login/frontend" config user.email "workbranch-test@example.com"
  git -C "$project/login/backend" config user.name "Workbranch Test"
  git -C "$project/login/backend" config user.email "workbranch-test@example.com"
  git -C "$project/_base/backend" config user.name "Workbranch Test"
  git -C "$project/_base/backend" config user.email "workbranch-test@example.com"

  printf '%s\n' "frontend task" > "$project/login/frontend/frontend-task.txt"
  git -C "$project/login/frontend" add frontend-task.txt
  git -C "$project/login/frontend" commit -m "frontend task" >/dev/null

  printf '%s\n' "backend task" > "$project/login/backend/backend-task.txt"
  git -C "$project/login/backend" add backend-task.txt
  git -C "$project/login/backend" commit -m "backend task" >/dev/null

  printf '%s\n' "backend base" > "$project/_base/backend/backend-base.txt"
  git -C "$project/_base/backend" add backend-base.txt
  git -C "$project/_base/backend" commit -m "backend base" >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" land login)
  assert_contains "$out" "Cannot land: preflight failed"
  assert_contains "$out" "login/backend cannot fast-forward land"
  assert_contains "$out" "workbranch update login --repo backend"
  assert_not_exists "$project/_base/frontend/frontend-task.txt"
  assert_not_exists "$project/_base/backend/backend-task.txt"
}

test_push_supports_task_and_base_branches_after_fast_forward_merge() {
  new_fixture
  project="$FIXTURE_PROJECT"
  commit_to_remote_branch frontend feature/cpq parent-frontend
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git feature/cpq
REPO backend $TMP_ROOT/remotes/backend.git master
CONFIG
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add ui >/dev/null
  assert_branch "$project/ui/frontend" "feature/cpq-ui"
  assert_branch "$project/ui/backend" "feature/ui"
  assert_file "$project/ui/frontend/parent-frontend.txt"

  git -C "$project/ui/frontend" config user.name "Workbranch Test"
  git -C "$project/ui/frontend" config user.email "workbranch-test@example.com"
  git -C "$project/ui/backend" config user.name "Workbranch Test"
  git -C "$project/ui/backend" config user.email "workbranch-test@example.com"
  printf '%s\n' "landed frontend" > "$project/ui/frontend/landed.txt"
  git -C "$project/ui/frontend" add landed.txt
  git -C "$project/ui/frontend" commit -m "landed frontend" >/dev/null
  printf '%s\n' "feature backend" > "$project/ui/backend/normal.txt"
  git -C "$project/ui/backend" add normal.txt
  git -C "$project/ui/backend" commit -m "feature backend" >/dev/null

  run_expect_success "$WORKBRANCH" push ui >/dev/null
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" feature/cpq-ui landed.txt "landed frontend"
  assert_remote_file "$TMP_ROOT/remotes/backend.git" feature/ui normal.txt "feature backend"
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" feature/cpq landed.txt
  run_expect_success "$WORKBRANCH" land ui >/dev/null
  assert_branch "$project/_base/frontend" "feature/cpq"
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" feature/cpq landed.txt
  assert_remote_missing_file "$TMP_ROOT/remotes/backend.git" master normal.txt

  run_expect_success "$WORKBRANCH" push >/dev/null
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" feature/cpq landed.txt "landed frontend"
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" master landed.txt
  assert_remote_file "$TMP_ROOT/remotes/backend.git" master normal.txt "feature backend"
}

test_add_rejects_existing_task_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  git -C "$project/_base/frontend" branch feature/login

  out=$(run_expect_fail "$WORKBRANCH" add login)
  assert_contains "$out" "task branch already exists for repo 'frontend': feature/login"
  assert_contains "$out" "To resume it: workbranch resume login"
  assert_contains "$out" "To delete it first: workbranch remove login"
  assert_not_exists "$project/login"
}

test_add_rejects_remote_only_task_branch_without_remove_advice() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feature/login remote-frontend

  out=$(run_expect_fail "$WORKBRANCH" add login)
  assert_contains "$out" "task branch already exists for repo 'frontend': feature/login"
  assert_contains "$out" "To resume it: workbranch resume login"
  assert_contains "$out" "Remote origin/feature/login exists; delete it outside workbranch before adding again."
  assert_not_contains "$out" "workbranch remove login"
  assert_not_exists "$project/login"
}

test_resume_recovers_manually_deleted_task_workspace() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  git -C "$project/login/frontend" config user.name "Workbranch Test"
  git -C "$project/login/frontend" config user.email "workbranch-test@example.com"
  git -C "$project/login/backend" config user.name "Workbranch Test"
  git -C "$project/login/backend" config user.email "workbranch-test@example.com"
  printf '%s\n' "manual delete frontend" > "$project/login/frontend/manual-delete.txt"
  git -C "$project/login/frontend" add manual-delete.txt
  git -C "$project/login/frontend" commit -m "manual delete frontend" >/dev/null
  printf '%s\n' "manual delete backend" > "$project/login/backend/manual-delete.txt"
  git -C "$project/login/backend" add manual-delete.txt
  git -C "$project/login/backend" commit -m "manual delete backend" >/dev/null

  rm -rf "$project/login"
  git -C "$project/_base/frontend" worktree list --porcelain | grep -F "$project/login/frontend" >/dev/null ||
    fail "expected manually deleted frontend worktree registration to remain stale"

  out=$(run_expect_success "$WORKBRANCH" resume login)
  assert_contains "$out" "[+] Resumed: login/frontend"
  assert_contains "$out" "[+] Resumed: login/backend"
  assert_file "$project/login/frontend/.git"
  assert_file "$project/login/backend/.git"
  assert_file "$project/login/frontend/manual-delete.txt"
  assert_file "$project/login/backend/manual-delete.txt"
  assert_branch "$project/login/frontend" "feature/login"
  assert_branch "$project/login/backend" "feature/login"
}

test_resume_local_task_branch_does_not_require_origin() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  rm -rf "$project/login"
  git -C "$project/_base/frontend" remote set-url origin "$TMP_ROOT/remotes/missing-frontend.git"
  git -C "$project/_base/backend" remote set-url origin "$TMP_ROOT/remotes/missing-backend.git"

  out=$(run_expect_success "$WORKBRANCH" resume login)
  assert_contains "$out" "[+] Resumed: login/frontend"
  assert_contains "$out" "[+] Resumed: login/backend"
  assert_branch "$project/login/frontend" "feature/login"
  assert_branch "$project/login/backend" "feature/login"
}

test_resume_repairs_partial_task_directory() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  rm -rf "$project/login/frontend"

  out=$(run_expect_fail "$WORKBRANCH" add login)
  assert_contains "$out" "task directory already exists"

  out=$(run_expect_success "$WORKBRANCH" resume login)
  assert_contains "$out" "[+] Resumed: login/frontend"
  assert_file "$project/login/frontend/.git"
  assert_file "$project/login/backend/.git"
  assert_branch "$project/login/frontend" "feature/login"
  assert_branch "$project/login/backend" "feature/login"
}

test_resume_repairs_stale_task_directory() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  rm -f "$project/login/frontend/.git" "$project/login/backend/.git"

  out=$(run_expect_success "$WORKBRANCH" resume login)
  assert_contains "$out" "Removed stale task directory: login"
  assert_contains "$out" "[+] Resumed: login/frontend"
  assert_contains "$out" "[+] Resumed: login/backend"
  assert_file "$project/login/frontend/.git"
  assert_file "$project/login/backend/.git"
  assert_branch "$project/login/frontend" "feature/login"
  assert_branch "$project/login/backend" "feature/login"
}

test_resume_fetches_remote_task_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feature/login remote-frontend
  commit_to_remote_branch backend feature/login remote-backend

  out=$(run_expect_success "$WORKBRANCH" resume login)
  assert_contains "$out" "[+] Resumed: login/frontend"
  assert_contains "$out" "[+] Resumed: login/backend"
  assert_file "$project/login/frontend/remote-frontend.txt"
  assert_file "$project/login/backend/remote-backend.txt"
  assert_branch "$project/login/frontend" "feature/login"
  assert_branch "$project/login/backend" "feature/login"
}

test_resume_prunes_before_creating_remote_task_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feature/login remote-frontend
  commit_to_remote_branch backend feature/login remote-backend

  real_git=$(command -v git)
  fakebin="$TMP_ROOT/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/git" <<'GIT'
#!/usr/bin/env bash
if [ "${1:-}" = "-C" ] && [ "${2:-}" = "$CHECK_PRUNE_BASE" ] && [ "${3:-}" = "worktree" ] && [ "${4:-}" = "prune" ]; then
  touch "$PRUNE_MARKER"
fi
if [ "${1:-}" = "-C" ] && [ "${2:-}" = "$CHECK_PRUNE_BASE" ] && [ "${3:-}" = "branch" ]; then
  case "${4:-}" in
    --track)
      [ -f "$PRUNE_MARKER" ] || exit 1
      ;;
    feature/login)
      [ -f "$PRUNE_MARKER" ] || exit 1
      ;;
  esac
fi
exec "$REAL_GIT" "$@"
GIT
  chmod +x "$fakebin/git"

  old_path=$PATH
  export REAL_GIT=$real_git
  export CHECK_PRUNE_BASE=$(cd "$project/_base/frontend" && pwd -P)
  export PRUNE_MARKER="$TMP_ROOT/pruned-before-branch"
  PATH="$fakebin:$PATH"
  out=$(run_expect_success "$WORKBRANCH" resume login)
  PATH=$old_path
  unset REAL_GIT CHECK_PRUNE_BASE PRUNE_MARKER

  assert_contains "$out" "[+] Resumed: login/frontend"
  assert_branch "$project/login/frontend" "feature/login"
}

test_resume_recreates_missing_repo_after_scoped_task_push() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  git -C "$project/login/frontend" config user.name "Workbranch Test"
  git -C "$project/login/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "frontend scoped" > "$project/login/frontend/scoped.txt"
  git -C "$project/login/frontend" add scoped.txt
  git -C "$project/login/frontend" commit -m "frontend scoped" >/dev/null

  run_expect_success "$WORKBRANCH" push login --repo frontend >/dev/null
  run_expect_success "$WORKBRANCH" remove login >/dev/null
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" feature/login scoped.txt "frontend scoped"
  assert_remote_missing_file "$TMP_ROOT/remotes/backend.git" feature/login scoped.txt

  out=$(run_expect_fail "$WORKBRANCH" add login)
  assert_contains "$out" "task branch already exists for repo 'frontend': feature/login"
  assert_contains "$out" "To resume it: workbranch resume login"

  out=$(run_expect_success "$WORKBRANCH" resume login)
  assert_contains "$out" "[+] Resumed: login/frontend"
  assert_contains "$out" "[+] Resumed: login/backend"
  assert_file "$project/login/frontend/scoped.txt"
  assert_not_exists "$project/login/backend/scoped.txt"
  assert_branch "$project/login/frontend" "feature/login"
  assert_branch "$project/login/backend" "feature/login"
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

test_add_rolls_back_branch_when_new_worktree_helper_fails() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  real_git=$(command -v git)
  fakebin="$TMP_ROOT/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/git" <<'GIT'
#!/usr/bin/env bash
if [ "${1:-}" = "-C" ] && [ "${2:-}" = "$FAIL_WORKTREE_BASE" ] && [ "${3:-}" = "worktree" ] && [ "${4:-}" = "add" ]; then
  target=$5
  branch=$7
  "$REAL_GIT" -C "$FAIL_WORKTREE_BASE" branch "$branch" HEAD >/dev/null 2>&1 || true
  mkdir -p "$target"
  exit 1
fi
exec "$REAL_GIT" "$@"
GIT
  chmod +x "$fakebin/git"

  old_path=$PATH
  export REAL_GIT=$real_git
  export FAIL_WORKTREE_BASE=$(cd "$project/_base/backend" && pwd -P)
  PATH="$fakebin:$PATH"
  out=$(run_expect_fail "$WORKBRANCH" add login)
  PATH=$old_path
  unset REAL_GIT FAIL_WORKTREE_BASE

  assert_contains "$out" "failed to create worktree for repo 'backend'"
  assert_not_exists "$project/login"
  if git -C "$project/_base/backend" show-ref --verify --quiet refs/heads/feature/login; then
    fail "expected failed add to roll back backend feature/login branch"
  fi
}

test_add_rolls_back_dirty_worktree_registration() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  real_git=$(command -v git)
  fakebin="$TMP_ROOT/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/git" <<'GIT'
#!/usr/bin/env bash
if [ "${1:-}" = "-C" ] && [ "${2:-}" = "$FAIL_WORKTREE_BASE" ] && [ "${3:-}" = "worktree" ] && [ "${4:-}" = "add" ]; then
  printf '%s\n' "dirty rollback marker" > "$DIRTY_WORKTREE_PATH/rollback-dirty.txt"
  exit 1
fi
exec "$REAL_GIT" "$@"
GIT
  chmod +x "$fakebin/git"

  old_path=$PATH
  export REAL_GIT=$real_git
  export FAIL_WORKTREE_BASE=$(cd "$project/_base/backend" && pwd -P)
  export DIRTY_WORKTREE_PATH="$project/login/frontend"
  PATH="$fakebin:$PATH"
  out=$(run_expect_fail "$WORKBRANCH" add login)
  PATH=$old_path
  unset REAL_GIT FAIL_WORKTREE_BASE DIRTY_WORKTREE_PATH

  assert_contains "$out" "failed to create worktree for repo 'backend'"
  assert_not_exists "$project/login"
  if git -C "$project/_base/frontend" worktree list --porcelain | grep -F "$project/login/frontend" >/dev/null; then
    fail "expected rollback to remove dirty frontend worktree registration"
  fi
}

test_add_branches_from_local_base_after_land_before_push() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add first >/dev/null

  git -C "$project/first/frontend" config user.name "Workbranch Test"
  git -C "$project/first/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "landed locally" > "$project/first/frontend/landed-local.txt"
  git -C "$project/first/frontend" add landed-local.txt
  git -C "$project/first/frontend" commit -m "landed locally" >/dev/null

  run_expect_success "$WORKBRANCH" land first --repo frontend >/dev/null
  assert_file "$project/_base/frontend/landed-local.txt"
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" master landed-local.txt

  run_expect_success "$WORKBRANCH" add second >/dev/null
  assert_file "$project/second/frontend/landed-local.txt"
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
  assert_contains "$out" "Task directory kept because it is not empty: login"
}

test_pull_preflight_requires_base_worktree_on_configured_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  git -C "$project/_base/frontend" checkout -b unrelated >/dev/null 2>&1
  commit_to_remote_master frontend pull-should-not-touch-unrelated

  out=$(run_expect_fail "$WORKBRANCH" pull --repo frontend)
  assert_contains "$out" "Cannot pull: preflight failed"
  assert_contains "$out" "_base/frontend expected branch master, got unrelated"
  assert_not_exists "$project/_base/frontend/pull-should-not-touch-unrelated.txt"
}

test_add_preflight_requires_clean_base_on_configured_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  git -C "$project/_base/frontend" checkout -b unrelated >/dev/null 2>&1
  printf '%s\n' "dirty base" > "$project/_base/frontend/dirty.txt"

  out=$(run_expect_fail "$WORKBRANCH" add login)
  assert_contains "$out" "Cannot add: preflight failed"
  assert_contains "$out" "_base/frontend expected branch master, got unrelated"
  assert_contains "$out" "_base/frontend dirty worktree"
  assert_not_exists "$project/login"
}

test_config_writes_config_without_cloning() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work"
  frontend_remote=$(make_repo frontend)
  input=$(cat <<INPUT

.
fullstack
_base
feature
frontend
$frontend_remote
master

n

Y
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "Config written"
  project="$TMP_ROOT/work/fullstack"
  assert_file "$project/.workbranch.config"
  assert_contains "$(cat "$project/.workbranch.config")" "REPO frontend $frontend_remote master"
  assert_not_exists "$project/_base"
}

test_config_rewrites_legacy_config_without_cloning() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  rm "$project/.workbranch.config"
  cat > "$project/.monotree.config" <<CONFIG
project fullstack
base_dir _base
branch_prefix feature

repo frontend $TMP_ROOT/remotes/frontend.git
base_branch frontend master
repo backend $TMP_ROOT/remotes/backend.git master
CONFIG

  out=$(run_expect_success "$WORKBRANCH" status)
  assert_contains "$out" "[*] Base worktrees"
  assert_contains "$out" "frontend    missing"

  out=$(run_expect_success "$WORKBRANCH" config --rewrite)
  assert_contains "$out" "[+] Config rewritten:"
  assert_file "$project/.workbranch.config"
  config=$(cat "$project/.workbranch.config")
  assert_contains "$config" "PROJECT_NAME fullstack"
  assert_contains "$config" "MAIN_WORKTREES_DIR _base"
  assert_contains "$config" "BRANCH_PREFIX feature"
  assert_contains "$config" "REPO frontend $TMP_ROOT/remotes/frontend.git master"
  assert_contains "$config" "REPO backend $TMP_ROOT/remotes/backend.git master"
  assert_not_exists "$project/_base"

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_success "$WORKBRANCH" status)
  assert_contains "$out" "[*] Base worktrees"
}

test_config_keeps_glob_characters_literal() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  : > "$project/maZZster"
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git ma*ster
REPO backend $TMP_ROOT/remotes/backend.git master
CONFIG

  out=$(run_expect_success "$WORKBRANCH" list)
  assert_contains "$out" "ma*ster"
  assert_not_contains "$out" "maZZster"
}

test_init_accepts_legacy_config_without_rewrite() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  rm "$project/.workbranch.config"
  cat > "$project/.monotree.config" <<CONFIG
project fullstack
base_dir _base
branch_prefix feature

repo frontend $TMP_ROOT/remotes/frontend.git
base_branch frontend master
repo backend $TMP_ROOT/remotes/backend.git master
CONFIG

  out=$(run_expect_success "$WORKBRANCH" init)
  assert_contains "$out" "Initialized workbranch project"
  assert_dir "$project/_base/frontend/.git"
  assert_dir "$project/_base/backend/.git"
  assert_branch "$project/_base/frontend" "master"
  assert_branch "$project/_base/backend" "master"
  assert_not_exists "$project/.workbranch.config"
}

test_legacy_config_supports_project_commands_without_rewrite() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  rm "$project/.workbranch.config"
  cat > "$project/.monotree.config" <<CONFIG
project fullstack
base_dir _base
branch_prefix feature

repo frontend $TMP_ROOT/remotes/frontend.git
base_branch frontend master
repo backend $TMP_ROOT/remotes/backend.git master
CONFIG

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_success "$WORKBRANCH" list)
  assert_contains "$out" "Project: fullstack"
  assert_contains "$out" "frontend    master"
  assert_contains "$out" "backend     master"
  assert_not_exists "$project/.workbranch.config"
}

test_config_rewrites_legacy_tasktree_config_without_cloning() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  mv "$project/.workbranch.config" "$project/.tasktree.config"

  out=$(run_expect_success "$WORKBRANCH" config --rewrite)
  assert_contains "$out" "[+] Config rewritten:"
  assert_file "$project/.workbranch.config"
  assert_contains "$(cat "$project/.workbranch.config")" "PROJECT_NAME fullstack"
  assert_contains "$(cat "$project/.workbranch.config")" "REPO frontend $TMP_ROOT/remotes/frontend.git master"
  assert_not_exists "$project/_base"
}

test_task_setup_can_be_configured_and_run() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  mkdir -p "$project/scripts"
  cat > "$project/scripts/workbranch-setup.sh" <<'SCRIPT'
#!/usr/bin/env sh
set -eu
printf '%s\n' "$WORKBRANCH_PROJECT_ROOT" > "$WORKBRANCH_TASK_DIR/setup-project-root.txt"
printf '%s\n' "$WORKBRANCH_TASK" > "$WORKBRANCH_TASK_DIR/setup-task.txt"
printf '%s\n' "$WORKBRANCH_REPOS" > "$WORKBRANCH_TASK_DIR/setup-repos.txt"
SCRIPT

  printf '\nTASK_SETUP sh scripts/workbranch-setup.sh\n' >> "$project/.workbranch.config"
  assert_contains "$(cat "$project/.workbranch.config")" "TASK_SETUP sh scripts/workbranch-setup.sh"
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(run_expect_success "$WORKBRANCH" list)
  assert_contains "$out" "[*] Task setup:"
  assert_contains "$out" "sh scripts/workbranch-setup.sh"

  out=$(run_expect_success "$WORKBRANCH" add login)
  assert_contains "$out" "[*] Running task setup: sh scripts/workbranch-setup.sh"
  assert_contains "$out" "[+] Task setup completed: login"
  assert_contains "$(cat "$project/login/setup-task.txt")" "login"
  assert_contains "$(cat "$project/login/setup-repos.txt")" "frontend backend"
}

test_setup_command_is_removed() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  out=$(run_expect_fail "$WORKBRANCH" setup login)
  assert_contains "$out" "unknown command: setup"
}

test_config_preserves_task_setup_while_prompting_repo_setup() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  printf '\nTASK_SETUP pnpm install\n' >> "$project/.workbranch.config"

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "" "" 'printf frontend > repo.txt' "" "" | run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[*] Project name [fullstack]:"
  assert_contains "$out" "[*] Main worktrees dir [_base]:"
  assert_contains "$out" "[*] Branch prefix [feature]:"
  assert_contains "$out" "[*] Base repo branch for frontend [master]:"
  assert_contains "$out" "[*] Repo setup command for frontend []:"
  assert_contains "$out" "[*] Base repo branch for backend [master]:"
  assert_contains "$out" "[*] Repo setup command for backend []:"
  assert_not_contains "$out" "Task setup command"
  assert_contains "$out" "$(printf '%s \n\n%s' "[*] Branch prefix [feature]:" "[*] Repositories")"
  assert_contains "$out" "$(printf '%s \n\n%s' "[*] Repo setup command for frontend []:" "[*] Base repo branch for backend [master]:")"
  assert_contains "$out" "$(printf '%s \n\n%s' "[*] Repo setup command for backend []:" "[+] Config updated:")"
  case "$out" in
    *"Base repo branch for frontend"*"Repo setup command for frontend"*"Base repo branch for backend"*"Repo setup command for backend"*) ;;
    *) fail "expected config to ask branch and setup per repo only; got: $out" ;;
  esac
  assert_contains "$out" "[+] Config updated:"
  config=$(cat "$project/.workbranch.config")
  assert_contains "$config" "REPO_SETUP frontend printf frontend > repo.txt"
  assert_contains "$config" "TASK_SETUP pnpm install"
}

test_config_can_change_branch_prefix_without_cloning() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "ticket" "" "" "" "" | run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[*] Branch prefix [feature]:"
  assert_contains "$out" "[+] Config updated:"
  config=$(cat "$project/.workbranch.config")
  assert_contains "$config" "BRANCH_PREFIX ticket"
  assert_dir "$project/_base/frontend/.git"

  out=$(run_expect_success "$WORKBRANCH" add login)
  assert_contains "$out" "[+] Created: login/frontend"
  assert_contains "$out" "[+] Created: login/backend"
  assert_branch "$project/login/frontend" "ticket/login"
  assert_branch "$project/login/backend" "ticket/login"
}

test_config_rejects_branch_prefix_change_when_task_workspaces_exist() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "ticket" "" "" "" "" | run_expect_fail "$WORKBRANCH" config)
  assert_contains "$out" "cannot change BRANCH_PREFIX while task workspaces exist"
  assert_contains "$out" "remove or migrate existing task workspaces before changing it"
  assert_contains "$(cat "$project/.workbranch.config")" "BRANCH_PREFIX feature"
  assert_not_contains "$(cat "$project/.workbranch.config")" "BRANCH_PREFIX ticket"

  out=$(run_expect_success "$WORKBRANCH" update login)
  assert_contains "$out" "[+] Updated: login/frontend"
  assert_contains "$out" "[+] Updated: login/backend"
}

test_config_rejects_branch_prefix_change_when_stale_task_directory_exists() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  rm -f "$project/login/frontend/.git" "$project/login/backend/.git"

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "ticket" "" "" "" "" | run_expect_fail "$WORKBRANCH" config)
  assert_contains "$out" "cannot change BRANCH_PREFIX while task workspaces exist"
  assert_contains "$(cat "$project/.workbranch.config")" "BRANCH_PREFIX feature"
  assert_not_contains "$(cat "$project/.workbranch.config")" "BRANCH_PREFIX ticket"

  out=$(run_expect_success "$WORKBRANCH" status)
  assert_contains "$out" "[*] Stale directories"
  assert_contains "$out" "login"
}

test_config_rejects_main_worktrees_dir_change_when_base_worktrees_exist() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "_main" "" "" "" "" "" | run_expect_fail "$WORKBRANCH" config)
  assert_contains "$out" "cannot change MAIN_WORKTREES_DIR while base worktrees exist: _base"
  assert_contains "$out" "remove or move existing base worktrees before changing it"
  assert_contains "$(cat "$project/.workbranch.config")" "MAIN_WORKTREES_DIR _base"
  assert_not_contains "$(cat "$project/.workbranch.config")" "MAIN_WORKTREES_DIR _main"

  out=$(run_expect_success "$WORKBRANCH" status)
  assert_contains "$out" "[*] Task workspaces"
  assert_contains "$out" "[*] (none)"
  assert_not_contains "$out" "[*] _base"
}

test_config_guides_base_branch_change_for_cloned_repo() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "" "develop" "" "" "" "" | run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[*] _base/frontend current branch: master"
  assert_contains "$out" "[+] Config updated:"
  assert_contains "$out" "[*] Base branch changes were saved in config only."
  assert_contains "$out" "_base/frontend"
  assert_contains "$out" "git checkout develop"
  assert_contains "$(cat "$project/.workbranch.config")" "REPO frontend $TMP_ROOT/remotes/frontend.git develop"
}

test_repo_setup_can_be_configured_and_run_per_repo() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  frontend_cmd='printf "%s:%s:%s\n" "$WORKBRANCH_REPO" "$WORKBRANCH_TASK" "$(basename "$PWD")" >> "$WORKBRANCH_TASK_DIR/setup.log"; printf "%s\n" "$WORKBRANCH_REPO_DIR" > repo-setup-dir.txt'
  backend_cmd='printf "%s:%s:%s\n" "$WORKBRANCH_REPO" "$WORKBRANCH_TASK" "$(basename "$PWD")" >> "$WORKBRANCH_TASK_DIR/setup.log"; printf "%s\n" "$WORKBRANCH_BASE_REPO_DIR" > repo-base-dir.txt'

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "" "" "$frontend_cmd" "" "$backend_cmd" | run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[+] Config updated:"
  config=$(cat "$project/.workbranch.config")
  assert_contains "$config" "REPO_SETUP frontend $frontend_cmd"
  assert_contains "$config" "REPO_SETUP backend $backend_cmd"

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_success "$WORKBRANCH" add login)
  assert_contains "$out" "[*] Running repo setup: login/frontend"
  assert_contains "$out" "[*] Running repo setup: login/backend"
  assert_contains "$out" "[+] Repo setup completed: login/frontend"
  assert_contains "$out" "[+] Repo setup completed: login/backend"
  assert_contains "$(cat "$project/login/setup.log")" "frontend:login:frontend"
  assert_contains "$(cat "$project/login/setup.log")" "backend:login:backend"
  assert_contains "$(cat "$project/login/frontend/repo-setup-dir.txt")" "$project/login/frontend"
  assert_contains "$(cat "$project/login/backend/repo-base-dir.txt")" "$project/_base/backend"

}

test_repo_setup_suppresses_legacy_task_setup_fallback() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  cat >> "$project/.workbranch.config" <<'CONFIG'
TASK_SETUP printf project >> "$WORKBRANCH_TASK_DIR/setup.log"
REPO_SETUP frontend printf frontend >> "$WORKBRANCH_TASK_DIR/setup.log"
REPO_SETUP backend printf backend >> "$WORKBRANCH_TASK_DIR/setup.log"
CONFIG

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_success "$WORKBRANCH" add login)
  assert_contains "$out" "[*] Running repo setup: login/frontend"
  assert_contains "$out" "[*] Running repo setup: login/backend"
  assert_not_contains "$out" "[*] Running task setup:"
  assert_contains "$(cat "$project/login/setup.log")" "frontend"
  assert_contains "$(cat "$project/login/setup.log")" "backend"
  assert_not_contains "$(cat "$project/login/setup.log")" "project"
}

test_task_setup_failure_reports_directory_and_command() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  canonical_project=$(pwd -P)
  printf '\nTASK_SETUP false\n' >> "$project/.workbranch.config"

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_fail "$WORKBRANCH" add login)
  assert_contains "$out" "task setup failed: login"
  assert_contains "$out" "Setup directory: $canonical_project"
  assert_contains "$out" "Setup command: false"
  assert_not_contains "$out" "in the task workspace"
}

test_repo_setup_failure_reports_directory_and_command() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  canonical_project=$(pwd -P)
  printf '\nREPO_SETUP frontend false\n' >> "$project/.workbranch.config"

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_fail "$WORKBRANCH" add login)
  assert_contains "$out" "repo setup failed: login/frontend"
  assert_contains "$out" "Setup directory: $canonical_project/login/frontend"
  assert_contains "$out" "Setup command: false"
  assert_not_contains "$out" "in the task workspace"
}

test_repo_setup_can_be_cleared_without_removing_other_repo_setup() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  cat >> "$project/.workbranch.config" <<'CONFIG'
REPO_SETUP frontend printf frontend > repo.txt
REPO_SETUP backend printf backend > repo.txt
CONFIG

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "" "" "--clear" "" "" | run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[+] Config updated:"
  config=$(cat "$project/.workbranch.config")
  assert_not_contains "$config" "REPO_SETUP frontend"
  assert_contains "$config" "REPO_SETUP backend printf backend > repo.txt"
}

test_interactive_init_writes_config_and_clones() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work"
  frontend_remote=$(make_repo frontend)
  backend_remote=$(make_repo backend)
  input=$(cat <<INPUT

.
fullstack
_base
feature
frontend
$frontend_remote
master

Y
backend
$backend_remote


n

Y
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | run_expect_success "$WORKBRANCH" init)
  assert_contains "$out" "[*] Create a new workbranch project"
  assert_not_contains "$out" "[*] Before workbranch"
  assert_not_contains "$out" "Problem: separate agents do not share context, session, or file search."
  assert_contains "$out" "[*] After workbranch"
  assert_contains "$out" "[*] Setup guide"
  case "$out" in
    *"[*] After workbranch"*"[*] Setup guide"*) ;;
    *) fail "expected after, then setup guide; got: $out" ;;
  esac
  assert_contains "$out" "Project name      directory name for this workbranch workspace"
  assert_contains "$out" "Main worktrees    directory for each repo main worktree"
  assert_not_contains "$out" "Default base repo checkout branch"
  assert_not_contains "$out" "Base branch is checked out in _base/<repo>."
  assert_not_contains "$out" "Task branch examples: master + login -> feature/login, feature/cpq + task1 -> feature/cpq-task1"
  assert_contains "$out" "[*] Base repo branch [main]:"
  assert_contains "$out" "[*] Base repo branch [master]:"
  assert_contains "$out" "[*] Repo setup command for frontend []:"
  assert_contains "$out" "[*] Repo setup command for backend []:"
  assert_contains "$out" "[*] Branch policy:"
  assert_contains "$out" "[base repo] main        -> task1 -> [task repo] feature/task1"
  assert_contains "$out" "[base repo] feature/XXX -> task1 -> [task repo] feature/XXX-task1"
  assert_contains "$out" "frontend: base=master task=feature/<task>"
  assert_contains "$out" "backend: base=master task=feature/<task>"
  assert_contains "$out" "[*] Main worktrees directory [_base]:"
  assert_contains "$out" "fullstack                     // workbranch project"
  assert_contains "$out" "├── .workbranch.config        // config"
  assert_contains "$out" "├── _base                     // main worktrees: _base"
  assert_contains "$out" "│   ├── frontend              // - base frontend repo"
  assert_contains "$out" "│   └── backend               // - base backend repo"
  assert_contains "$out" "└── login                     // task workspace"
  assert_contains "$out" "├── frontend              // - task frontend repo"
  assert_contains "$out" "├── backend               // - task backend repo"
  assert_contains "$out" "└── <work here>           // use AI Agents in here"
  assert_contains "$out" "Result: branch operations stay grouped by feature workspace."
  assert_contains "$out" "Multi-repo bonus: use one directory for shared AI session context."
  assert_contains "$out" "Press Enter to continue"
  assert_contains "$out" "[*] Project"
  assert_contains "$out" "[*] Repo #1"
  assert_contains "$out" "[*] Repo #2"
  assert_contains "$out" "[*] Task setup command []:"
  assert_contains "$out" "[*] Task setup:"
  assert_contains "$out" "[*]   (none)"
  assert_contains "$out" "[*] Summary"
  assert_contains "$out" "[*] Create project now? [Y/n]:"
  assert_contains "$out" "[+] Initialized"
  project="$TMP_ROOT/work/fullstack"
  assert_file "$project/.workbranch.config"
  assert_contains "$(cat "$project/.workbranch.config")" "REPO frontend $frontend_remote master"
  assert_contains "$(cat "$project/.workbranch.config")" "REPO backend $backend_remote master"
  assert_dir "$project/_base/frontend/.git"
  assert_dir "$project/_base/backend/.git"
}

test_interactive_init_can_cancel_before_creating_project() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work"
  frontend_remote=$(make_repo frontend)
  input=$(cat <<INPUT

.
fullstack
_base
feature
frontend
$frontend_remote
master

n

n
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | run_expect_success "$WORKBRANCH" init)
  assert_contains "$out" "[*] Summary"
  assert_contains "$out" "[*] Create project now? [Y/n]:"
  assert_contains "$out" "[*] Cancelled."
  assert_not_contains "$out" "[*] Creating project..."
  assert_not_contains "$out" "[+] Cloned:"
  assert_not_exists "$TMP_ROOT/work/fullstack"
}

test_interactive_init_can_create_project_in_custom_target_directory() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work" "$TMP_ROOT/target"
  frontend_remote=$(make_repo frontend)
  input=$(cat <<INPUT

$TMP_ROOT/target
fullstack
_base
feature
frontend
$frontend_remote
master

n

Y
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | run_expect_success "$WORKBRANCH" init)
  assert_contains "$out" "[+] Initialized"
  assert_file "$TMP_ROOT/target/fullstack/.workbranch.config"
  assert_dir "$TMP_ROOT/target/fullstack/_base/frontend/.git"
  assert_not_exists "$TMP_ROOT/work/fullstack"
}

test_interactive_init_accepts_slash_repo_base_branch() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work"
  frontend_remote=$(make_repo frontend)
  git --git-dir="$frontend_remote" branch feature/cpq master
  input=$(cat <<INPUT

.
fullstack
_base
feature
frontend
$frontend_remote
feature/cpq

n

Y
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | run_expect_success "$WORKBRANCH" init)
  assert_contains "$out" "[+] Initialized"
  assert_contains "$(cat "$TMP_ROOT/work/fullstack/.workbranch.config")" "REPO frontend $frontend_remote feature/cpq"
  assert_branch "$TMP_ROOT/work/fullstack/_base/frontend" "feature/cpq"
}

test_interactive_init_rejects_slash_in_main_worktrees_directory() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/work"
  input=$(cat <<INPUT

.
fullstack
feature/cpq
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | run_expect_fail "$WORKBRANCH" init)
  assert_contains "$out" "invalid MAIN_WORKTREES_DIR 'feature/cpq'"
}

test_interactive_init_eof_aborts_required_prompt() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/work"
  out_file="$TMP_ROOT/eof.out"
  status_file="$TMP_ROOT/eof.status"
  input=$(cat <<INPUT

.
fullstack
_base
feature
INPUT
)

  (
    cd "$TMP_ROOT/work" || exit 1
    printf '%s' "$input" | "$WORKBRANCH" init >"$out_file" 2>&1
    printf '%s' "$?" >"$status_file"
  ) &
  pid=$!
  waited=0
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 30 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    fail "expected init to abort on EOF instead of hanging"
  fi
  wait "$pid" 2>/dev/null || true

  status=$(cat "$status_file")
  [ "$status" -ne 0 ] || fail "expected EOF during required prompt to exit non-zero"
  out=$(cat "$out_file")
  assert_contains "$out" "input aborted"
}


test_installer_supports_pipe_to_bash() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/standalone" "$TMP_ROOT/server/bin"
  cp "$REPO_ROOT/install.sh" "$TMP_ROOT/standalone/install.sh"
  cp "$WORKBRANCH" "$TMP_ROOT/server/bin/workbranch"
  cd "$TMP_ROOT/server" || return 1
  python3 -m http.server 8765 >/tmp/workbranch-test-http.log 2>&1 &
  server_pid=$!
  cd "$TMP_ROOT/standalone" || return 1
  sleep 1
  out=$(HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" WORKBRANCH_RAW_BASE_URL="http://127.0.0.1:8765" bash < "$TMP_ROOT/standalone/install.sh" 2>&1)
  kill "$server_pid" 2>/dev/null || true
  assert_contains "$out" "Downloaded workbranch"
  assert_contains "$out" "Installed workbranch"
  assert_file "$TMP_ROOT/home/.local/bin/workbranch"
  [ -x "$TMP_ROOT/home/.local/bin/workbranch" ] || fail "pipe-to-bash installed workbranch is not executable"
  out=$(HOME="$TMP_ROOT/home" "$TMP_ROOT/home/.local/bin/workbranch" help 2>&1)
  assert_contains "$out" "Usage:"
  assert_contains "$out" "workbranch <command> [args]"
}

test_installer_pipe_to_bash_ignores_cwd_bin_workbranch() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/standalone/bin" "$TMP_ROOT/server/bin"
  cp "$REPO_ROOT/install.sh" "$TMP_ROOT/standalone/install.sh"
  cat > "$TMP_ROOT/standalone/bin/workbranch" <<'STALE'
#!/usr/bin/env sh
printf '%s\n' STALE
STALE
  chmod +x "$TMP_ROOT/standalone/bin/workbranch"
  mkdir -p "$TMP_ROOT/standalone/.git"
  : > "$TMP_ROOT/standalone/bash"
  cat > "$TMP_ROOT/server/bin/workbranch" <<'REMOTE'
#!/usr/bin/env sh
printf '%s\n' REMOTE
REMOTE
  chmod +x "$TMP_ROOT/server/bin/workbranch"

  cd "$TMP_ROOT/standalone" || return 1
  out=$(HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" WORKBRANCH_RAW_BASE_URL="file://$TMP_ROOT/server" bash < "$TMP_ROOT/standalone/install.sh" 2>&1)
  assert_contains "$out" "Downloaded workbranch"
  installed_out=$("$TMP_ROOT/home/.local/bin/workbranch")
  [ "$installed_out" = "REMOTE" ] || fail "expected pipe install to download REMOTE, got: $installed_out"
}

test_installer_downloads_cli_when_run_standalone() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/standalone/bin" "$TMP_ROOT/server/bin"
  cp "$REPO_ROOT/install.sh" "$TMP_ROOT/standalone/install.sh"
  cp "$WORKBRANCH" "$TMP_ROOT/server/bin/workbranch"
  cd "$TMP_ROOT/server" || return 1
  python3 -m http.server 8765 >/tmp/workbranch-test-http.log 2>&1 &
  server_pid=$!
  cd "$REPO_ROOT" || return 1
  sleep 1
  out=$(printf '\nn\n' | HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" WORKBRANCH_RAW_BASE_URL="http://127.0.0.1:8765" "$TMP_ROOT/standalone/install.sh" 2>&1)
  kill "$server_pid" 2>/dev/null || true
  assert_contains "$out" "Downloaded workbranch"
  assert_file "$TMP_ROOT/home/.local/bin/workbranch"
  [ -x "$TMP_ROOT/home/.local/bin/workbranch" ] || fail "standalone installed workbranch is not executable"
  out=$(HOME="$TMP_ROOT/home" "$TMP_ROOT/home/.local/bin/workbranch" help 2>&1)
  assert_contains "$out" "Usage:"
  assert_contains "$out" "workbranch <command> [args]"
}

test_installer_standalone_uses_embedded_raw_base_url() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/standalone" "$TMP_ROOT/server/bin"
  sed "s#https://raw.githubusercontent.com/tkhwang/workbranch/main#file://$TMP_ROOT/server#g" "$REPO_ROOT/install.sh" > "$TMP_ROOT/standalone/install.sh"
  chmod +x "$TMP_ROOT/standalone/install.sh"
  cat > "$TMP_ROOT/server/bin/workbranch" <<'REMOTE'
#!/usr/bin/env sh
printf '%s\n' EMBEDDED
REMOTE
  chmod +x "$TMP_ROOT/server/bin/workbranch"

  out=$(printf '\nn\n' | HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" "$TMP_ROOT/standalone/install.sh" 2>&1)
  assert_contains "$out" "Downloaded workbranch from file://$TMP_ROOT/server"
  assert_contains "$out" "Installed workbranch"
  installed_out=$("$TMP_ROOT/home/.local/bin/workbranch")
  [ "$installed_out" = "EMBEDDED" ] || fail "expected embedded default install to download EMBEDDED, got: $installed_out"
}

test_installer_installs_executable() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  out=$(printf '\nn\n' | HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" "$REPO_ROOT/install.sh" 2>&1)
  assert_contains "$out" "[*] Target directory"
  assert_contains "$out" "Installed workbranch"
  assert_contains "$out" "[*] Try it now:"
  assert_contains "$out" "workbranch help     show all commands"
  assert_contains "$out" "workbranch init     create your first workbranch project"
  assert_contains "$out" "not on your PATH"
  assert_contains "$out" "Add it to your PATH now? [y/N]"
  assert_contains "$out" "Run directly:"
  assert_file "$TMP_ROOT/home/.local/bin/workbranch"
  [ -x "$TMP_ROOT/home/.local/bin/workbranch" ] || fail "installed workbranch is not executable"
  out=$(HOME="$TMP_ROOT/home" "$TMP_ROOT/home/.local/bin/workbranch" help 2>&1)
  assert_contains "$out" "Usage:"
  assert_contains "$out" "workbranch <command> [args]"
}

test_installer_uses_custom_target_directory() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  custom_dir="$TMP_ROOT/custom-bin"
  out=$(printf '%s\nn\n' "$custom_dir" | HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" "$REPO_ROOT/install.sh" 2>&1)
  assert_contains "$out" "Installed workbranch to $custom_dir/workbranch"
  assert_contains "$out" "[*] Try it now:"
  assert_contains "$out" "$custom_dir is not on your PATH"
  assert_file "$custom_dir/workbranch"
  [ -x "$custom_dir/workbranch" ] || fail "custom installed workbranch is not executable"
  out=$("$custom_dir/workbranch" help 2>&1)
  assert_contains "$out" "Usage:"
}

test_installer_can_add_target_directory_to_zshrc() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  custom_dir="$TMP_ROOT/custom-bin"
  out=$(printf '%s\ny\n' "$custom_dir" | HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" "$REPO_ROOT/install.sh" 2>&1)
  assert_contains "$out" "Added PATH entry to $TMP_ROOT/home/.zshrc"
  assert_file "$TMP_ROOT/home/.zshrc"
  assert_contains "$(cat "$TMP_ROOT/home/.zshrc")" "export PATH=\"$custom_dir:\$PATH\""
}

test_help_groups_commands() {
  out=$(run_expect_success "$WORKBRANCH" help)
  assert_contains "$out" "Workspace lifecycle:"
  assert_contains "$out" "init              Initialize a workbranch project"
  assert_contains "$out" "list              List configured repos and task workspaces"
  assert_contains "$out" "config            Create or update .workbranch.config without cloning repos"
  assert_contains "$out" "config --rewrite  Rewrite config to current format without prompts"
  assert_contains "$out" "resume <task>     Restore existing local or remote task branches"
  assert_not_contains "$out" "setup             Add or change"
  assert_not_contains "$out" "setup --clear"
  assert_not_contains "$out" "setup repo <repo>"
  assert_not_contains "$out" "setup <task>"
  assert_contains "$out" "Branch workflow:"
  assert_contains "$out" "Other:"
  assert_contains "$out" "-v, --version     Show the installed workbranch version"
  assert_contains "$out" "version           Show the installed workbranch version"
  assert_contains "$out" "status            Show commits, diff, and dirty state"
  assert_contains "$out" "pull              Pull remote base branches into main worktrees"
  assert_contains "$out" "push              Push base branches to origin"
  assert_contains "$out" "push <task>       Push task branches to origin"
  assert_contains "$out" "update            Update every task workspace from local base worktrees"
  assert_contains "$out" "update --all      Update every task workspace from local base worktrees"
  assert_contains "$out" "update <task>     Update one task workspace from local base worktrees"
  assert_contains "$out" "land <task>       Land task branches into base branches"
  assert_contains "$out" "  Options:"
  assert_contains "$out" "    --repo <repo>   Limit branch workflow to one repo; otherwise all repos"
  assert_not_contains "$out" "  vertical"
  assert_not_contains "$out" "  horizontal"
  assert_not_contains "$out" "  common"
  case "$out" in
    *$'\n\n'*) fail "expected compact help without blank lines; got: $out" ;;
  esac
  case "$out" in
    *"Workspace lifecycle:"*"init              Initialize a workbranch project"*"list              List configured repos and task workspaces"*"config            Create or update .workbranch.config without cloning repos"*"config --rewrite  Rewrite config to current format without prompts"*"add <task>        Create a task workspace"*"remove <task>     Remove task worktrees and local task branches"*"resume <task>     Restore existing local or remote task branches"*"Branch workflow:"*"status            Show commits, diff, and dirty state"*"  Options:"*"Other:"*) ;;
    *) fail "expected workspace and group ordering; got: $out" ;;
  esac
  case "$out" in
    *"Other:"*"help              Show this help"*"version           Show the installed workbranch version"*"-v, --version     Show the installed workbranch version"*) ;;
    *) fail "expected version before -v/--version in Other commands; got: $out" ;;
  esac
}

test_version_reports_release_manifest_version() {
  expected=$(manifest_version)
  [ -n "$expected" ] || fail "could not read release manifest version"

  out=$(run_expect_success "$WORKBRANCH" version)
  [ "$out" = "workbranch $expected" ] || fail "expected version output 'workbranch $expected', got: $out"

  out=$(run_expect_success "$WORKBRANCH" --version)
  [ "$out" = "workbranch $expected" ] || fail "expected --version output 'workbranch $expected', got: $out"

  out=$(run_expect_success "$WORKBRANCH" -v)
  [ "$out" = "workbranch $expected" ] || fail "expected -v output 'workbranch $expected', got: $out"
}

main() {
  [ -x "$WORKBRANCH" ] || fail "missing executable: $WORKBRANCH"
  git --version >/dev/null || fail "git is required"

  run_test test_generated_workbranch_is_up_to_date
  run_test test_help_groups_commands
  run_test test_version_reports_release_manifest_version
  run_test test_safe_names_reject_dot_and_dotdot
  run_test test_invalid_config_rejected_without_execution
  run_test test_init_existing_config_clones_base_repos
  run_test test_init_completes_partial_base_clones
  run_test test_init_rejects_already_initialized_workbranch_project
  run_test test_init_from_project_subdir_uses_parent_config
  run_test test_init_rejects_existing_non_git_base_target
  run_test test_init_rejects_existing_non_directory_base_target
  run_test test_failed_init_rolls_back_command_created_base_paths
  run_test test_failed_init_reports_git_clone_reason
  run_test test_full_git_flow
  run_test test_update_all_updates_every_task_workspace
  run_test test_update_accepts_gitfile_base_worktree
  run_test test_update_preflight_blocks_batch_before_changes
  run_test test_update_preflight_requires_base_worktree_on_configured_branch
  run_test test_update_preflight_blocks_base_rebase_in_progress
  run_test test_repo_scope_limits_git_commands_to_one_repo
  run_test test_land_preflight_blocks_all_repos_before_partial_land
  run_test test_push_supports_task_and_base_branches_after_fast_forward_merge
  run_test test_add_rejects_existing_task_branch
  run_test test_add_rejects_remote_only_task_branch_without_remove_advice
  run_test test_resume_recovers_manually_deleted_task_workspace
  run_test test_resume_local_task_branch_does_not_require_origin
  run_test test_resume_repairs_partial_task_directory
  run_test test_resume_repairs_stale_task_directory
  run_test test_resume_fetches_remote_task_branch
  run_test test_resume_prunes_before_creating_remote_task_branch
  run_test test_resume_recreates_missing_repo_after_scoped_task_push
  run_test test_remove_deletes_task_branch_when_worktree_missing
  run_test test_remove_force_discards_dirty_task
  run_test test_remove_rejects_unmerged_task_branch_without_force
  run_test test_remove_rejects_task_repo_on_unexpected_branch
  run_test test_add_rolls_back_branch_when_new_worktree_helper_fails
  run_test test_add_rolls_back_dirty_worktree_registration
  run_test test_add_branches_from_local_base_after_land_before_push
  run_test test_status_reports_base_task_diff_and_worktree_state
  run_test test_status_repo_filter_skips_tasks_without_matching_rows
  run_test test_status_reports_stale_task_shaped_directories_separately
  run_test test_status_reports_standalone_repo_task_dirs_as_stale
  run_test test_status_skips_partial_task_workspaces
  run_test test_dirty_worktree_safety
  run_test test_remove_reports_kept_task_directory_with_extra_files
  run_test test_remove_treats_missing_worktree_as_already_removed
  run_test test_remove_cleans_stale_task_directory
  run_test test_remove_continues_after_worktree_remove_failure
  run_test test_pull_preflight_requires_base_worktree_on_configured_branch
  run_test test_add_preflight_requires_clean_base_on_configured_branch
  run_test test_config_writes_config_without_cloning
  run_test test_config_rewrites_legacy_config_without_cloning
  run_test test_config_keeps_glob_characters_literal
  run_test test_init_accepts_legacy_config_without_rewrite
  run_test test_legacy_config_supports_project_commands_without_rewrite
  run_test test_config_rewrites_legacy_tasktree_config_without_cloning
  run_test test_task_setup_can_be_configured_and_run
  run_test test_setup_command_is_removed
  run_test test_config_preserves_task_setup_while_prompting_repo_setup
  run_test test_config_can_change_branch_prefix_without_cloning
  run_test test_config_rejects_branch_prefix_change_when_task_workspaces_exist
  run_test test_config_rejects_branch_prefix_change_when_stale_task_directory_exists
  run_test test_config_rejects_main_worktrees_dir_change_when_base_worktrees_exist
  run_test test_config_guides_base_branch_change_for_cloned_repo
  run_test test_repo_setup_can_be_configured_and_run_per_repo
  run_test test_repo_setup_suppresses_legacy_task_setup_fallback
  run_test test_task_setup_failure_reports_directory_and_command
  run_test test_repo_setup_failure_reports_directory_and_command
  run_test test_repo_setup_can_be_cleared_without_removing_other_repo_setup
  run_test test_interactive_init_writes_config_and_clones
  run_test test_interactive_init_can_cancel_before_creating_project
  run_test test_interactive_init_can_create_project_in_custom_target_directory
  run_test test_interactive_init_accepts_slash_repo_base_branch
  run_test test_interactive_init_rejects_slash_in_main_worktrees_directory
  run_test test_interactive_init_eof_aborts_required_prompt
  run_test test_installer_downloads_cli_when_run_standalone
  run_test test_installer_standalone_uses_embedded_raw_base_url
  run_test test_installer_supports_pipe_to_bash
  run_test test_installer_pipe_to_bash_ignores_cwd_bin_workbranch
  run_test test_installer_installs_executable
  run_test test_installer_uses_custom_target_directory
  run_test test_installer_can_add_target_directory_to_zshrc

  log "Tests passed: $PASS"
  if [ "$FAIL" -ne 0 ]; then
    log "Tests failed: $FAIL"
    exit 1
  fi
}

main "$@"
