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
  commit_to_remote_branch "$name" master "$msg"
}

commit_to_remote_branch() {
  name=$1
  branch=$2
  msg=$3
  clone="$TMP_ROOT/upstream-$name-$branch-$msg"
  git clone "$TMP_ROOT/remotes/$name.git" "$clone" >/dev/null 2>&1
  git -C "$clone" config user.name "Monotree Test"
  git -C "$clone" config user.email "monotree-test@example.com"
  git -C "$clone" checkout -B "$branch" "origin/$branch" >/dev/null 2>&1 || git -C "$clone" checkout -b "$branch" >/dev/null 2>&1
  printf '%s\n' "$msg" > "$clone/$msg.txt"
  git -C "$clone" add "$msg.txt"
  git -C "$clone" commit -m "$msg" >/dev/null
  git -C "$clone" push origin "$branch" >/dev/null 2>&1
}

new_fixture() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t monotree-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/fullstack"
  frontend_remote=$(make_repo frontend)
  backend_remote=$(make_repo backend)
  cat > "$TMP_ROOT/fullstack/.monotree.config" <<CONFIG
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

test_invalid_config_rejected_without_execution() {
  new_fixture
  project="$FIXTURE_PROJECT"
  rm -rf "$project/_base"
  cat > "$project/.monotree.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature
REPO frontend $TMP_ROOT/remotes/frontend.git master
CONFIG
  printf 'unknown $(touch %s)\n' "$TMP_ROOT/pwned" >> "$project/.monotree.config"
  out=$(cd "$project" && run_expect_fail "$MONOTREE" list)
  assert_contains "$out" "unknown directive"
  assert_not_exists "$TMP_ROOT/pwned"
}

test_legacy_split_repo_base_config_is_accepted() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cat > "$project/.monotree.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git
WORKFLOW frontend feature master
REPO backend $TMP_ROOT/remotes/backend.git
WORKFLOW backend stacked feature/cpq
CONFIG
  commit_to_remote_branch backend feature/cpq parent-backend
  out=$(cd "$project" && run_expect_success "$MONOTREE" init)
  assert_contains "$out" "Initialized"
  assert_branch "$project/_base/frontend" "master"
  assert_branch "$project/_base/backend" "feature/cpq"
}

test_mixed_legacy_and_current_config_is_accepted_when_base_matches() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cat > "$project/.monotree.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git master
WORKFLOW frontend feature master
REPO backend $TMP_ROOT/remotes/backend.git master
WORKFLOW backend feature master
CONFIG
  out=$(cd "$project" && run_expect_success "$MONOTREE" init)
  assert_contains "$out" "Initialized"
  assert_branch "$project/_base/frontend" "master"
  assert_branch "$project/_base/backend" "master"
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
  cat > "$project/.monotree.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git master
REPO missing $TMP_ROOT/remotes/missing.git master
CONFIG
  out=$(cd "$project" && run_expect_fail "$MONOTREE" init)
  assert_contains "$out" "failed to clone repo 'missing'"
  assert_not_exists "$project/_base/frontend"
  assert_not_exists "$project/_base"
}

test_failed_init_reports_git_clone_reason() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cat > "$project/.monotree.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git does-not-exist
CONFIG
  out=$(cd "$project" && run_expect_fail "$MONOTREE" init)
  assert_contains "$out" "failed to clone repo 'frontend'"
  assert_contains "$out" "Remote branch does-not-exist not found"
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
  run_expect_success "$MONOTREE" pull >/dev/null
  assert_file "$project/_base/frontend/upstream-change.txt"
  assert_not_exists "$project/login/frontend/upstream-change.txt"

  run_expect_success "$MONOTREE" rebase login >/dev/null
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

test_rebase_all_updates_every_task_workspace() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$MONOTREE" init >/dev/null
  run_expect_success "$MONOTREE" add login >/dev/null
  run_expect_success "$MONOTREE" add payment >/dev/null

  commit_to_remote_master frontend upstream-all
  run_expect_success "$MONOTREE" pull >/dev/null
  assert_not_exists "$project/login/frontend/upstream-all.txt"
  assert_not_exists "$project/payment/frontend/upstream-all.txt"

  run_expect_success "$MONOTREE" rebase >/dev/null
  assert_file "$project/login/frontend/upstream-all.txt"
  assert_file "$project/payment/frontend/upstream-all.txt"
}

test_repo_scope_limits_git_commands_to_one_repo() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$MONOTREE" init >/dev/null
  run_expect_success "$MONOTREE" add login >/dev/null

  commit_to_remote_master frontend frontend-upstream
  commit_to_remote_master backend backend-upstream
  run_expect_success "$MONOTREE" pull --repo frontend >/dev/null
  assert_file "$project/_base/frontend/frontend-upstream.txt"
  assert_not_exists "$project/_base/backend/backend-upstream.txt"

  run_expect_success "$MONOTREE" rebase login --repo frontend >/dev/null
  assert_file "$project/login/frontend/frontend-upstream.txt"
  assert_not_exists "$project/login/backend/backend-upstream.txt"

  git -C "$project/login/frontend" config user.name "Monotree Test"
  git -C "$project/login/frontend" config user.email "monotree-test@example.com"
  git -C "$project/login/backend" config user.name "Monotree Test"
  git -C "$project/login/backend" config user.email "monotree-test@example.com"
  printf '%s
' "frontend scoped" > "$project/login/frontend/scoped.txt"
  git -C "$project/login/frontend" add scoped.txt
  git -C "$project/login/frontend" commit -m "frontend scoped" >/dev/null
  printf '%s
' "backend scoped" > "$project/login/backend/scoped.txt"
  git -C "$project/login/backend" add scoped.txt
  git -C "$project/login/backend" commit -m "backend scoped" >/dev/null

  run_expect_success "$MONOTREE" push login --repo frontend >/dev/null
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" feature/login scoped.txt "frontend scoped"
  assert_remote_missing_file "$TMP_ROOT/remotes/backend.git" feature/login scoped.txt

  run_expect_success "$MONOTREE" merge login --repo frontend >/dev/null
  run_expect_success "$MONOTREE" push --repo frontend >/dev/null
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" master scoped.txt "frontend scoped"
  assert_remote_missing_file "$TMP_ROOT/remotes/backend.git" master scoped.txt
}

test_push_supports_task_and_base_branches_after_fast_forward_merge() {
  new_fixture
  project="$FIXTURE_PROJECT"
  commit_to_remote_branch frontend feature/cpq parent-frontend
  cat > "$project/.monotree.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git feature/cpq
REPO backend $TMP_ROOT/remotes/backend.git master
CONFIG
  cd "$project" || return 1
  run_expect_success "$MONOTREE" init >/dev/null
  run_expect_success "$MONOTREE" add ui >/dev/null
  assert_branch "$project/ui/frontend" "feature/cpq-ui"
  assert_branch "$project/ui/backend" "feature/ui"
  assert_file "$project/ui/frontend/parent-frontend.txt"

  git -C "$project/ui/frontend" config user.name "Monotree Test"
  git -C "$project/ui/frontend" config user.email "monotree-test@example.com"
  git -C "$project/ui/backend" config user.name "Monotree Test"
  git -C "$project/ui/backend" config user.email "monotree-test@example.com"
  printf '%s\n' "stacked frontend" > "$project/ui/frontend/stacked.txt"
  git -C "$project/ui/frontend" add stacked.txt
  git -C "$project/ui/frontend" commit -m "stacked frontend" >/dev/null
  printf '%s\n' "feature backend" > "$project/ui/backend/normal.txt"
  git -C "$project/ui/backend" add normal.txt
  git -C "$project/ui/backend" commit -m "feature backend" >/dev/null

  run_expect_success "$MONOTREE" push ui >/dev/null
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" feature/cpq-ui stacked.txt "stacked frontend"
  assert_remote_file "$TMP_ROOT/remotes/backend.git" feature/ui normal.txt "feature backend"
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" feature/cpq stacked.txt
  run_expect_success "$MONOTREE" merge ui >/dev/null
  assert_branch "$project/_base/frontend" "feature/cpq"
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" feature/cpq stacked.txt
  assert_remote_missing_file "$TMP_ROOT/remotes/backend.git" master normal.txt

  run_expect_success "$MONOTREE" push >/dev/null
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" feature/cpq stacked.txt "stacked frontend"
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" master stacked.txt
  assert_remote_file "$TMP_ROOT/remotes/backend.git" master normal.txt "feature backend"
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

test_status_reports_base_and_task_dirty_state() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$MONOTREE" init >/dev/null
  run_expect_success "$MONOTREE" add login >/dev/null

  printf '%s\n' "local note" > "$project/_base/frontend/local.txt"
  printf '%s\n' "changed" >> "$project/login/backend/README.md"

  out=$(run_expect_success "$MONOTREE" status)
  assert_contains "$out" "[*] Base worktrees"
  assert_contains "$out" "    frontend    master           untracked"
  assert_contains "$out" "    backend     master           clean"
  case "$out" in
    *"backend     master           clean"$'\n\n'"[*] Task workspaces"*) ;;
    *) fail "expected blank line between base worktrees and task workspaces; got: $out" ;;
  esac
  assert_contains "$out" "[*] Task workspaces"
  assert_contains "$out" "[*] login"
  assert_contains "$out" "    frontend    feature/login    clean"
  assert_contains "$out" "    backend     feature/login    modified"
}

test_dirty_worktree_safety() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$MONOTREE" init >/dev/null
  run_expect_success "$MONOTREE" add login >/dev/null

  printf '%s\n' "dirty base" > "$project/_base/frontend/dirty.txt"
  out=$(run_expect_fail "$MONOTREE" pull)
  assert_contains "$out" "dirty worktree"
  rm "$project/_base/frontend/dirty.txt"
  assert_clean "$project/_base/frontend"

  printf '%s\n' "dirty task" > "$project/login/frontend/dirty.txt"
  out=$(run_expect_fail "$MONOTREE" rebase login)
  assert_contains "$out" "dirty worktree"
  out=$(run_expect_fail "$MONOTREE" remove login)
  assert_contains "$out" "dirty worktree"
  assert_file "$project/login/frontend/.git"
}

test_config_writes_config_without_cloning() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t monotree-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work"
  frontend_remote=$(make_repo frontend)
  input=$(cat <<INPUT

.
fullstack
_base
master
feature
frontend
$frontend_remote

n
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | run_expect_success "$MONOTREE" config)
  assert_contains "$out" "Config written"
  project="$TMP_ROOT/work/fullstack"
  assert_file "$project/.monotree.config"
  assert_contains "$(cat "$project/.monotree.config")" "REPO frontend $frontend_remote master"
  assert_not_exists "$project/_base"
}

test_interactive_init_writes_config_and_clones() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t monotree-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work"
  frontend_remote=$(make_repo frontend)
  backend_remote=$(make_repo backend)
  input=$(cat <<INPUT

.
fullstack
_base
master
feature
frontend
$frontend_remote

Y
backend
$backend_remote

n
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | run_expect_success "$MONOTREE" init)
  assert_contains "$out" "[*] Create a new monotree project"
  assert_contains "$out" "[*] Before monotree"
  assert_contains "$out" "frontend                    // repo"
  assert_contains "$out" "└── AI agent                // separate session/context"
  assert_contains "$out" "Problem: separate agents do not share context, session, or file search."
  assert_contains "$out" "[*] After monotree"
  assert_contains "$out" "[*] Setup guide"
  case "$out" in
    *"[*] Before monotree"*"[*] After monotree"*"[*] Setup guide"*) ;;
    *) fail "expected before, after, then setup guide; got: $out" ;;
  esac
  assert_contains "$out" "Project name      directory name for this monotree workspace"
  assert_contains "$out" "Main worktrees    directory for each repo main worktree"
  assert_contains "$out" "Default main      default branch for repo main worktrees"
  assert_contains "$out" "[*] Default main branch [main]:"
  assert_contains "$out" "[*] Base branch [master]:"
  assert_contains "$out" "[*] Main worktrees directory [_base]:"
  assert_contains "$out" "fullstack                     // monotree project"
  assert_contains "$out" "├── .monotree.config          // config"
  assert_contains "$out" "├── _base                     // main worktrees"
  assert_contains "$out" "│   ├── frontend              // main worktree: frontend"
  assert_contains "$out" "│   └── backend               // main worktree: backend"
  assert_contains "$out" "└── login                     // task workspace"
  assert_contains "$out" "├── frontend              // linked worktree: frontend"
  assert_contains "$out" "├── backend               // linked worktree: backend"
  assert_contains "$out" "└── <run AI agent here>   // cd login && run codex, claude code, ..."
  assert_contains "$out" "Result: one task workspace, one AI session, repo-local paths."
  assert_contains "$out" "Press Enter to continue"
  assert_contains "$out" "[*] Project"
  assert_contains "$out" "[*] Repo #1"
  assert_contains "$out" "[*] Repo #2"
  assert_contains "$out" "[*] Summary"
  assert_contains "$out" "[+] Initialized"
  project="$TMP_ROOT/work/fullstack"
  assert_file "$project/.monotree.config"
  assert_contains "$(cat "$project/.monotree.config")" "REPO frontend $frontend_remote master"
  assert_contains "$(cat "$project/.monotree.config")" "REPO backend $backend_remote master"
  assert_dir "$project/_base/frontend/.git"
  assert_dir "$project/_base/backend/.git"
}

test_interactive_init_can_create_project_in_custom_target_directory() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t monotree-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work" "$TMP_ROOT/target"
  frontend_remote=$(make_repo frontend)
  input=$(cat <<INPUT

$TMP_ROOT/target
fullstack
_base
master
feature
frontend
$frontend_remote

n
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | run_expect_success "$MONOTREE" init)
  assert_contains "$out" "[+] Initialized"
  assert_file "$TMP_ROOT/target/fullstack/.monotree.config"
  assert_dir "$TMP_ROOT/target/fullstack/_base/frontend/.git"
  assert_not_exists "$TMP_ROOT/work/fullstack"
}

test_interactive_init_accepts_slash_default_main_branch() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t monotree-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work"
  frontend_remote=$(make_repo frontend)
  git --git-dir="$frontend_remote" branch feature/cpq master
  input=$(cat <<INPUT

.
fullstack
_base
feature/cpq
feature
frontend
$frontend_remote

n
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | run_expect_success "$MONOTREE" init)
  assert_contains "$out" "[+] Initialized"
  assert_contains "$(cat "$TMP_ROOT/work/fullstack/.monotree.config")" "REPO frontend $frontend_remote feature/cpq"
  assert_branch "$TMP_ROOT/work/fullstack/_base/frontend" "feature/cpq"
}

test_interactive_init_rejects_slash_in_main_worktrees_directory() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t monotree-test)
  mkdir -p "$TMP_ROOT/work"
  input=$(cat <<INPUT

.
fullstack
feature/cpq
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | run_expect_fail "$MONOTREE" init)
  assert_contains "$out" "invalid MAIN_WORKTREES_DIR 'feature/cpq'"
}

test_installer_installs_executable() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t monotree-test)
  out=$(printf '\nn\n' | HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" "$REPO_ROOT/install.sh" 2>&1)
  assert_contains "$out" "[*] Target directory"
  assert_contains "$out" "Installed monotree"
  assert_contains "$out" "[*] Try it now:"
  assert_contains "$out" "monotree help     show all commands"
  assert_contains "$out" "monotree init     create your first monotree project"
  assert_contains "$out" "not on your PATH"
  assert_contains "$out" "Add it to your PATH now? [y/N]"
  assert_contains "$out" "Run directly:"
  assert_file "$TMP_ROOT/home/.local/bin/monotree"
  [ -x "$TMP_ROOT/home/.local/bin/monotree" ] || fail "installed monotree is not executable"
  out=$(HOME="$TMP_ROOT/home" "$TMP_ROOT/home/.local/bin/monotree" help 2>&1)
  assert_contains "$out" "Usage:"
}

test_installer_uses_custom_target_directory() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t monotree-test)
  custom_dir="$TMP_ROOT/custom-bin"
  out=$(printf '%s\nn\n' "$custom_dir" | HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" "$REPO_ROOT/install.sh" 2>&1)
  assert_contains "$out" "Installed monotree to $custom_dir/monotree"
  assert_contains "$out" "[*] Try it now:"
  assert_contains "$out" "$custom_dir is not on your PATH"
  assert_file "$custom_dir/monotree"
  [ -x "$custom_dir/monotree" ] || fail "custom installed monotree is not executable"
  out=$("$custom_dir/monotree" help 2>&1)
  assert_contains "$out" "Usage:"
}

test_installer_can_add_target_directory_to_zshrc() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t monotree-test)
  custom_dir="$TMP_ROOT/custom-bin"
  out=$(printf '%s\ny\n' "$custom_dir" | HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" "$REPO_ROOT/install.sh" 2>&1)
  assert_contains "$out" "Added PATH entry to $TMP_ROOT/home/.zshrc"
  assert_file "$TMP_ROOT/home/.zshrc"
  assert_contains "$(cat "$TMP_ROOT/home/.zshrc")" "export PATH=\"$custom_dir:\$PATH\""
}

test_help_groups_commands() {
  out=$(run_expect_success "$MONOTREE" help)
  assert_contains "$out" "Workspace:"
  assert_contains "$out" "config            Create .monotree.config without cloning repos"
  assert_contains "$out" "Git:"
  assert_contains "$out" "Other:"
  assert_contains "$out" "status            Show clean/dirty status for base and task worktrees"
  assert_contains "$out" "pull              Pull remote base branches into main worktrees"
  assert_contains "$out" "--repo <repo>     Limit supported commands to one repo"
  assert_contains "$out" "rebase <task>     Rebase one task workspace onto remote base branches"
  assert_contains "$out" "rebase            Rebase every task workspace onto remote base branches"
  assert_contains "$out" "push              Push base branches to origin"
  assert_contains "$out" "push <task>       Push task branches to origin"
  assert_contains "$out" "merge <task>      Fast-forward base branches from task branches"
  case "$out" in
    *"Workspace:"*"Git:"*"Other:"*) ;;
    *) fail "expected grouped help ordering; got: $out" ;;
  esac
}

main() {
  [ -x "$MONOTREE" ] || fail "missing executable: $MONOTREE"
  git --version >/dev/null || fail "git is required"

  run_test test_help_groups_commands
  run_test test_invalid_config_rejected_without_execution
  run_test test_legacy_split_repo_base_config_is_accepted
  run_test test_mixed_legacy_and_current_config_is_accepted_when_base_matches
  run_test test_init_existing_config_clones_base_repos
  run_test test_failed_init_rolls_back_command_created_base_paths
  run_test test_failed_init_reports_git_clone_reason
  run_test test_full_git_flow
  run_test test_rebase_all_updates_every_task_workspace
  run_test test_repo_scope_limits_git_commands_to_one_repo
  run_test test_push_supports_task_and_base_branches_after_fast_forward_merge
  run_test test_branch_collision_fails_whole_add
  run_test test_status_reports_base_and_task_dirty_state
  run_test test_dirty_worktree_safety
  run_test test_config_writes_config_without_cloning
  run_test test_interactive_init_writes_config_and_clones
  run_test test_interactive_init_can_create_project_in_custom_target_directory
  run_test test_interactive_init_accepts_slash_default_main_branch
  run_test test_interactive_init_rejects_slash_in_main_worktrees_directory
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
