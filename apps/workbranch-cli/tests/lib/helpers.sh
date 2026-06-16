# shellcheck shell=bash
# Shared test helpers: counters, assertions, fixtures, and the run_test driver.
# Sourced by tests/run.sh (which defines SCRIPT_DIR / REPO_ROOT / WORKBRANCH first).
PASS=0
FAIL=0
TMP_ROOT=""
FIXTURE_PROJECT=""

log() { printf '%s\n' "$*"; }
fail() { log "[-] Error: $*"; exit 1; }

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
  if [ -t 0 ] || [ "${WORKBRANCH_TEST_FORCE_TTY_STDIN:-}" = "1" ]; then
    out=$("$@" </dev/null 2>&1)
  else
    out=$("$@" 2>&1)
  fi
  status=$?
  [ $status -eq 0 ] || fail "expected success: $*\n$out"
  printf '%s' "$out"
}

run_expect_fail() {
  if [ -t 0 ] || [ "${WORKBRANCH_TEST_FORCE_TTY_STDIN:-}" = "1" ]; then
    out=$("$@" </dev/null 2>&1)
  else
    out=$("$@" 2>&1)
  fi
  status=$?
  [ $status -ne 0 ] || fail "expected failure: $*"
  printf '%s' "$out"
}

append_fake_tool_script() {
  script=$1
  cat > "$script" <<'SCRIPT'
#!/usr/bin/env sh
set -eu
printf '%s
' "$PWD|$1" >> "$WORKBRANCH_FAKE_TOOL_LOG"
SCRIPT
  chmod +x "$script"
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
  log "[*] $test_name"
  test_started=$(date +%s)
  if (
    test_xdg_config=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test-xdg)
    export XDG_CONFIG_HOME="$test_xdg_config"
    cleanup_test_env() {
      cleanup_fixture
      [ -z "${test_xdg_config:-}" ] || rm -rf "$test_xdg_config"
    }
    trap cleanup_test_env EXIT
    "$test_name"
  ); then
    test_finished=$(date +%s)
    test_elapsed=$((test_finished - test_started))
    PASS=$((PASS + 1))
    log "[+] (${test_elapsed}s)"
  else
    test_finished=$(date +%s)
    test_elapsed=$((test_finished - test_started))
    FAIL=$((FAIL + 1))
    log "[-] (${test_elapsed}s)"
  fi
}
