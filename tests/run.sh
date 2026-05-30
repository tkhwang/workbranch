#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)
MONOTREE="$REPO_ROOT/bin/monotree"

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
assert_branch() {
  got=$(git -C "$1" branch --show-current 2>/dev/null) || fail "could not read branch in $1"
  [ "$got" = "$2" ] || fail "expected branch $2 in $1, got $got"
}
assert_clean() {
  got=$(git -C "$1" status --porcelain) || fail "could not read status in $1"
  [ -z "$got" ] || fail "expected clean worktree in $1, got: $got"
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
  git -C "$seed" config user.name "Monotree Test"
  git -C "$seed" config user.email "monotree-test@example.com"
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
  clone="$TMP_ROOT/upstream-$name-$msg"
  git clone "$TMP_ROOT/remotes/$name.git" "$clone" >/dev/null 2>&1
  git -C "$clone" config user.name "Monotree Test"
  git -C "$clone" config user.email "monotree-test@example.com"
  printf '%s\n' "$msg" > "$clone/$msg.txt"
  git -C "$clone" add "$msg.txt"
  git -C "$clone" commit -m "$msg" >/dev/null
  git -C "$clone" push origin master >/dev/null 2>&1
}

new_fixture() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t monotree-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/fullstack/.monotree"
  frontend_remote=$(make_repo frontend)
  backend_remote=$(make_repo backend)
  cat > "$TMP_ROOT/fullstack/.monotree/config" <<CONFIG
project fullstack
base_dir _base
branch_prefix feature

repo frontend $frontend_remote master
repo backend $backend_remote master
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

test_invalid_config_rejected_without_execution() {
  new_fixture
  project="$FIXTURE_PROJECT"
  rm -rf "$project/_base"
  cat > "$project/.monotree/config" <<CONFIG
project fullstack
base_dir _base
branch_prefix feature
repo frontend $TMP_ROOT/remotes/frontend.git master
CONFIG
  printf 'unknown $(touch %s)\n' "$TMP_ROOT/pwned" >> "$project/.monotree/config"
  out=$(cd "$project" && run_expect_fail "$MONOTREE" list)
  assert_contains "$out" "unknown directive"
  assert_not_exists "$TMP_ROOT/pwned"
}

test_init_existing_config_clones_base_repos() {
  new_fixture
  project="$FIXTURE_PROJECT"
  out=$(cd "$project" && run_expect_success "$MONOTREE" init)
  assert_contains "$out" "Initialized"
  assert_dir "$project/_base/frontend/.git"
  assert_dir "$project/_base/backend/.git"
  assert_branch "$project/_base/frontend" "master"
  assert_branch "$project/_base/backend" "master"
}

test_failed_init_rolls_back_command_created_base_paths() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cat > "$project/.monotree/config" <<CONFIG
project fullstack
base_dir _base
branch_prefix feature

repo frontend $TMP_ROOT/remotes/frontend.git master
repo missing $TMP_ROOT/remotes/missing.git master
CONFIG
  out=$(cd "$project" && run_expect_fail "$MONOTREE" init)
  assert_contains "$out" "failed to clone repo 'missing'"
  assert_not_exists "$project/_base/frontend"
  assert_not_exists "$project/_base"
}

test_full_git_flow() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$MONOTREE" init >/dev/null
  run_expect_success "$MONOTREE" add login >/dev/null
  assert_file "$project/login/frontend/.git"
  assert_file "$project/login/backend/.git"
  assert_branch "$project/login/frontend" "feature/login"
  assert_branch "$project/login/backend" "feature/login"

  out=$(run_expect_fail "$MONOTREE" add login)
  assert_contains "$out" "already exists"

  out=$(run_expect_success "$MONOTREE" list)
  assert_contains "$out" "Base: _base"
  assert_contains "$out" "Repo: frontend"
  assert_contains "$out" "Task: login"
  assert_contains "$out" "feature/login"

  commit_to_remote_master frontend upstream-change
  run_expect_success "$MONOTREE" sync >/dev/null
  assert_file "$project/_base/frontend/upstream-change.txt"
  assert_not_exists "$project/login/frontend/upstream-change.txt"

  run_expect_success "$MONOTREE" update login >/dev/null
  assert_file "$project/login/frontend/upstream-change.txt"

  git -C "$project/login/frontend" config user.name "Monotree Test"
  git -C "$project/login/frontend" config user.email "monotree-test@example.com"
  git -C "$project/login/backend" config user.name "Monotree Test"
  git -C "$project/login/backend" config user.email "monotree-test@example.com"

  printf '%s\n' "task frontend" > "$project/login/frontend/task.txt"
  git -C "$project/login/frontend" add task.txt
  git -C "$project/login/frontend" commit -m "task frontend" >/dev/null
  printf '%s\n' "task backend" > "$project/login/backend/task.txt"
  git -C "$project/login/backend" add task.txt
  git -C "$project/login/backend" commit -m "task backend" >/dev/null
  run_expect_success "$MONOTREE" push login >/dev/null
  git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse --verify refs/heads/feature/login >/dev/null
  git --git-dir="$TMP_ROOT/remotes/backend.git" rev-parse --verify refs/heads/feature/login >/dev/null

  run_expect_success "$MONOTREE" remove login >/dev/null
  assert_not_exists "$project/login"
  git -C "$project/_base/frontend" rev-parse --verify feature/login >/dev/null
}

test_branch_collision_fails_whole_add() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$MONOTREE" init >/dev/null
  git -C "$project/_base/frontend" branch feature/login
  out=$(run_expect_fail "$MONOTREE" add login)
  assert_contains "$out" "branch already exists"
  assert_not_exists "$project/login"
}

test_dirty_worktree_safety() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$MONOTREE" init >/dev/null
  run_expect_success "$MONOTREE" add login >/dev/null

  printf '%s\n' "dirty base" > "$project/_base/frontend/dirty.txt"
  out=$(run_expect_fail "$MONOTREE" sync)
  assert_contains "$out" "dirty worktree"
  rm "$project/_base/frontend/dirty.txt"
  assert_clean "$project/_base/frontend"

  printf '%s\n' "dirty task" > "$project/login/frontend/dirty.txt"
  out=$(run_expect_fail "$MONOTREE" update login)
  assert_contains "$out" "dirty worktree"
  out=$(run_expect_fail "$MONOTREE" remove login)
  assert_contains "$out" "dirty worktree"
  assert_file "$project/login/frontend/.git"
}

test_interactive_init_writes_config_and_clones() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t monotree-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work"
  frontend_remote=$(make_repo frontend)
  backend_remote=$(make_repo backend)
  input=$(cat <<INPUT
fullstack
_base
master
feature
frontend
$frontend_remote

Y
backend
$backend_remote
master
n
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | run_expect_success "$MONOTREE" init)
  assert_contains "$out" "Initialized"
  project="$TMP_ROOT/work/fullstack"
  assert_file "$project/.monotree/config"
  assert_contains "$(cat "$project/.monotree/config")" "repo frontend $frontend_remote master"
  assert_contains "$(cat "$project/.monotree/config")" "repo backend $backend_remote master"
  assert_dir "$project/_base/frontend/.git"
  assert_dir "$project/_base/backend/.git"
}

test_installer_installs_executable() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t monotree-test)
  out=$(HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" "$REPO_ROOT/install.sh" 2>&1)
  assert_contains "$out" "Installed monotree"
  assert_contains "$out" "not on your PATH"
  assert_file "$TMP_ROOT/home/.local/bin/monotree"
  [ -x "$TMP_ROOT/home/.local/bin/monotree" ] || fail "installed monotree is not executable"
  out=$(HOME="$TMP_ROOT/home" "$TMP_ROOT/home/.local/bin/monotree" help 2>&1)
  assert_contains "$out" "Usage: monotree"
}

main() {
  [ -x "$MONOTREE" ] || fail "missing executable: $MONOTREE"
  git --version >/dev/null || fail "git is required"

  run_test test_invalid_config_rejected_without_execution
  run_test test_init_existing_config_clones_base_repos
  run_test test_failed_init_rolls_back_command_created_base_paths
  run_test test_full_git_flow
  run_test test_branch_collision_fails_whole_add
  run_test test_dirty_worktree_safety
  run_test test_interactive_init_writes_config_and_clones
  run_test test_installer_installs_executable

  log "Tests passed: $PASS"
  if [ "$FAIL" -ne 0 ]; then
    log "Tests failed: $FAIL"
    exit 1
  fi
}

main "$@"
