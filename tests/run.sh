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

REPO frontend $frontend_remote
WORKFLOW frontend feature master
REPO backend $backend_remote
WORKFLOW backend feature master
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
REPO frontend $TMP_ROOT/remotes/frontend.git
WORKFLOW frontend feature master
CONFIG
  printf 'unknown $(touch %s)\n' "$TMP_ROOT/pwned" >> "$project/.monotree.config"
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
  cat > "$project/.monotree.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git
WORKFLOW frontend feature master
REPO missing $TMP_ROOT/remotes/missing.git
WORKFLOW missing feature master
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

REPO frontend $TMP_ROOT/remotes/frontend.git
WORKFLOW frontend feature does-not-exist
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

test_merge_requires_stacked_workflow() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$MONOTREE" init >/dev/null
  run_expect_success "$MONOTREE" add login >/dev/null

  git -C "$project/login/frontend" config user.name "Monotree Test"
  git -C "$project/login/frontend" config user.email "monotree-test@example.com"
  git -C "$project/login/backend" config user.name "Monotree Test"
  git -C "$project/login/backend" config user.email "monotree-test@example.com"

  printf '%s\n' "merge frontend" > "$project/login/frontend/merge.txt"
  git -C "$project/login/frontend" add merge.txt
  git -C "$project/login/frontend" commit -m "merge frontend" >/dev/null
  printf '%s\n' "merge backend" > "$project/login/backend/merge.txt"
  git -C "$project/login/backend" add merge.txt
  git -C "$project/login/backend" commit -m "merge backend" >/dev/null

  run_expect_success "$MONOTREE" push login >/dev/null
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" master merge.txt
  out=$(run_expect_fail "$MONOTREE" merge login)
  assert_contains "$out" "no stacked workflow repos to merge"
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" master merge.txt
  assert_remote_missing_file "$TMP_ROOT/remotes/backend.git" master merge.txt
}

test_stacked_workflow_rebases_pushes_feature_and_merges_parent_feature() {
  new_fixture
  project="$FIXTURE_PROJECT"
  commit_to_remote_branch frontend feature/cpq parent-frontend
  cat > "$project/.monotree.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git
WORKFLOW frontend stacked feature/cpq
REPO backend $TMP_ROOT/remotes/backend.git
WORKFLOW backend feature master
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
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" feature/cpq-ui stacked.txt
  assert_remote_file "$TMP_ROOT/remotes/backend.git" feature/ui normal.txt "feature backend"
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" feature/cpq stacked.txt
  run_expect_success "$MONOTREE" merge ui >/dev/null
  assert_branch "$project/_base/frontend" "feature/cpq"
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" feature/cpq stacked.txt "stacked frontend"
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" master stacked.txt
  assert_remote_missing_file "$TMP_ROOT/remotes/backend.git" master normal.txt
}

test_push_requires_feature_workflow() {
  new_fixture
  project="$FIXTURE_PROJECT"
  commit_to_remote_branch frontend feature/cpq parent-frontend
  cat > "$project/.monotree.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git
WORKFLOW frontend stacked feature/cpq
CONFIG
  cd "$project" || return 1
  run_expect_success "$MONOTREE" init >/dev/null
  run_expect_success "$MONOTREE" add cpq-ui >/dev/null
  out=$(run_expect_fail "$MONOTREE" push cpq-ui)
  assert_contains "$out" "no feature workflow repos to push"
}

test_free_workflow_uses_git_directly_for_git_operations() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cat > "$project/.monotree.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git
WORKFLOW frontend free master
CONFIG
  cd "$project" || return 1
  run_expect_success "$MONOTREE" init >/dev/null
  run_expect_success "$MONOTREE" add scratch >/dev/null
  assert_branch "$project/scratch/frontend" "feature/scratch"

  out=$(run_expect_fail "$MONOTREE" pull)
  assert_contains "$out" "use git directly for free workflow repos"
  out=$(run_expect_fail "$MONOTREE" rebase scratch)
  assert_contains "$out" "use git directly for free workflow repos"
  out=$(run_expect_fail "$MONOTREE" push scratch)
  assert_contains "$out" "no feature workflow repos to push"
  out=$(run_expect_fail "$MONOTREE" merge scratch)
  assert_contains "$out" "no stacked workflow repos to merge"
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
feature

Y
backend
$backend_remote
feature
master
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
  assert_contains "$out" "[*] Workflow [free/feature/stacked] [free]:"
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
  assert_contains "$(cat "$project/.monotree.config")" "REPO frontend $frontend_remote"
  assert_contains "$(cat "$project/.monotree.config")" "WORKFLOW frontend feature master"
  assert_contains "$(cat "$project/.monotree.config")" "REPO backend $backend_remote"
  assert_contains "$(cat "$project/.monotree.config")" "WORKFLOW backend feature master"
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
feature

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
feature

n
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | run_expect_success "$MONOTREE" init)
  assert_contains "$out" "[+] Initialized"
  assert_contains "$(cat "$TMP_ROOT/work/fullstack/.monotree.config")" "WORKFLOW frontend feature feature/cpq"
  assert_branch "$TMP_ROOT/work/fullstack/_base/frontend" "feature/cpq"
}

test_interactive_init_writes_stacked_workflow() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t monotree-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work"
  frontend_remote=$(make_repo frontend)
  commit_to_remote_branch frontend feature/cpq parent-frontend
  input=$(cat <<INPUT

.
fullstack
_base
master
feature
frontend
$frontend_remote
stacked
feature/cpq
n
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | run_expect_success "$MONOTREE" init)
  assert_contains "$out" "[*] Workflow [free/feature/stacked] [free]:"
  assert_contains "$out" "[*] Parent feature branch:"
  project="$TMP_ROOT/work/fullstack"
  assert_contains "$(cat "$project/.monotree.config")" "WORKFLOW frontend stacked feature/cpq"
  assert_branch "$project/_base/frontend" "feature/cpq"
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
  assert_contains "$out" "Git workflow:"
  assert_contains "$out" "Free workflow:"
  assert_contains "$out" "Feature workflow:"
  assert_contains "$out" "Stacked workflow:"
  assert_contains "$out" "Other:"
  assert_contains "$out" "pull              Pull workflow base branches"
  assert_contains "$out" "rebase <task>     Rebase task branches onto workflow base branches"
  assert_contains "$out" "push <task>       Push task branches for pull requests"
  assert_contains "$out" "merge <task>      Merge local task branches into parent feature branches"
  case "$out" in
    *"Workspace:"*"Git workflow:"*"Free workflow:"*"Feature workflow:"*"Stacked workflow:"*"Other:"*) ;;
    *) fail "expected grouped help ordering; got: $out" ;;
  esac
}

main() {
  [ -x "$MONOTREE" ] || fail "missing executable: $MONOTREE"
  git --version >/dev/null || fail "git is required"

  run_test test_help_groups_commands
  run_test test_invalid_config_rejected_without_execution
  run_test test_init_existing_config_clones_base_repos
  run_test test_failed_init_rolls_back_command_created_base_paths
  run_test test_failed_init_reports_git_clone_reason
  run_test test_full_git_flow
  run_test test_merge_requires_stacked_workflow
  run_test test_stacked_workflow_rebases_pushes_feature_and_merges_parent_feature
  run_test test_push_requires_feature_workflow
  run_test test_free_workflow_uses_git_directly_for_git_operations
  run_test test_branch_collision_fails_whole_add
  run_test test_dirty_worktree_safety
  run_test test_interactive_init_writes_config_and_clones
  run_test test_interactive_init_can_create_project_in_custom_target_directory
  run_test test_interactive_init_accepts_slash_default_main_branch
  run_test test_interactive_init_writes_stacked_workflow
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
