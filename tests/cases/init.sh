# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.
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

