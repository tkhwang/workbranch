# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.
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

  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature
REPO .workbranch $TMP_ROOT/remotes/frontend.git master
CONFIG
  out=$(run_expect_fail "$WORKBRANCH" list)
  assert_contains "$out" "invalid repo name '.workbranch'"
}

test_add_uses_feat_parent_branch_as_default() {
  new_fixture
  project="$FIXTURE_PROJECT"
  commit_to_remote_branch frontend feat/cpq parent-frontend
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git feat/cpq
CONFIG
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf '\n' | "$WORKBRANCH" add ui 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "add failed: $out"
  assert_contains "$out" "Repo frontend"
  assert_contains "$out" "  base branch: feat/cpq"
  assert_contains "$out" "  task repo branch [feat/cpq-ui]"
  assert_contains "$out" "  task repo folder: ui/frontend"
  assert_branch "$project/ui/frontend" "feat/cpq-ui"
}


test_add_derives_branch_from_conventional_task_folder() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf '\n\n' | "$WORKBRANCH" add feat-branch-name 2>&1)
  status=$?

  [ "$status" -eq 0 ] || fail "add with conventional task folder failed: $out"
  assert_contains "$out" "Repo frontend"
  assert_contains "$out" "  task repo branch [feat/branch-name]"
  assert_contains "$out" "  task repo folder: feat-branch-name/frontend"
  assert_contains "$out" "Repo backend"
  assert_contains "$out" "  task repo branch [feat/branch-name]"
  assert_contains "$out" "  task repo folder: feat-branch-name/backend"
  assert_branch "$project/feat-branch-name/frontend" "feat/branch-name"
  assert_branch "$project/feat-branch-name/backend" "feat/branch-name"
  assert_contains "$(cat "$project/feat-branch-name/.workbranch.task")" "REPO_BRANCH frontend feat/branch-name"
  assert_contains "$(cat "$project/feat-branch-name/.workbranch.task")" "REPO_BRANCH backend feat/branch-name"
}

test_add_derives_conventional_branch_from_parent_feature_base() {
  new_fixture
  project="$FIXTURE_PROJECT"
  commit_to_remote_branch frontend feature/cpq parent-frontend
  commit_to_remote_branch backend feature/cpq parent-backend
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git feature/cpq
REPO backend $TMP_ROOT/remotes/backend.git feature/cpq
CONFIG
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf '\n\n' | "$WORKBRANCH" add feat-task1 2>&1)
  status=$?

  [ "$status" -eq 0 ] || fail "add with conventional task on feature base failed: $out"
  assert_not_contains "$out" "Default task branch:"
  assert_contains "$out" "  base branch: feature/cpq"
  assert_contains "$out" "  task repo branch [feature/cpq-task1]"
  assert_contains "$out" "  task repo folder: feat-task1/frontend"
  assert_branch "$project/feat-task1/frontend" "feature/cpq-task1"
  assert_branch "$project/feat-task1/backend" "feature/cpq-task1"
  assert_contains "$(cat "$project/feat-task1/.workbranch.task")" "REPO_BRANCH frontend feature/cpq-task1"
  assert_contains "$(cat "$project/feat-task1/.workbranch.task")" "REPO_BRANCH backend feature/cpq-task1"
}

test_add_parent_slug_task_folder_maps_to_parent_prefixed_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  commit_to_remote_branch frontend feature/cpq parent-frontend
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git feature/cpq
CONFIG
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf '\n' | "$WORKBRANCH" add feature-cpq-task1 2>&1)
  status=$?

  [ "$status" -eq 0 ] || fail "add with parent-slug task folder failed: $out"
  assert_contains "$out" "  task repo branch [feature/cpq-task1]"
  assert_contains "$out" "  task repo folder: feature-cpq-task1/frontend"
  assert_not_contains "$out" "feature/cpq-feature-cpq-task1"
  assert_branch "$project/feature-cpq-task1/frontend" "feature/cpq-task1"
  assert_contains "$(cat "$project/feature-cpq-task1/.workbranch.task")" "REPO_BRANCH frontend feature/cpq-task1"
}

with_project_identity_libs() {
  (
    . "$REPO_ROOT/apps/cli/src/workbranch/lib/output.sh"
    . "$REPO_ROOT/apps/cli/src/workbranch/lib/validation.sh"
    . "$REPO_ROOT/apps/cli/src/workbranch/lib/config.sh"
    . "$REPO_ROOT/apps/cli/src/workbranch/lib/task-identity.sh"
    . "$REPO_ROOT/apps/cli/src/workbranch/lib/project.sh"
    "$@"
  )
}

assert_shared_parent_feature_base() {
  expected=$1
  shift
  REPO_NAMES=()
  REPO_BASE_BRANCHES=()
  BRANCH_PREFIX=feature
  for base in "$@"; do
    REPO_NAMES[${#REPO_NAMES[@]}]="repo${#REPO_NAMES[@]}"
    REPO_BASE_BRANCHES[${#REPO_BASE_BRANCHES[@]}]=$base
  done
  got=$(all_repos_share_parent_feature_base) || fail "expected shared parent feature base for: $*"
  [ "$got" = "$expected" ] || fail "expected shared parent feature base $expected, got $got"
}

assert_no_shared_parent_feature_base() {
  REPO_NAMES=()
  REPO_BASE_BRANCHES=()
  BRANCH_PREFIX=feature
  for base in "$@"; do
    REPO_NAMES[${#REPO_NAMES[@]}]="repo${#REPO_NAMES[@]}"
    REPO_BASE_BRANCHES[${#REPO_BASE_BRANCHES[@]}]=$base
  done
  if got=$(all_repos_share_parent_feature_base); then
    fail "expected no shared parent feature base for '$*', got $got"
  fi
}

test_all_repos_share_parent_feature_base_detects_only_identical_parent_bases() {
  with_project_identity_libs assert_shared_parent_feature_base feature/cpq feature/cpq || return 1
  with_project_identity_libs assert_shared_parent_feature_base feature/cpq feature/cpq feature/cpq || return 1
  with_project_identity_libs assert_no_shared_parent_feature_base feature/cpq main || return 1
  with_project_identity_libs assert_no_shared_parent_feature_base feature/cpq feature/xyz || return 1
  with_project_identity_libs assert_no_shared_parent_feature_base main || return 1
}

test_add_prompts_for_task_type_and_detail_without_task_argument() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf 'feat\nbranch-name\n\n\n' | "$WORKBRANCH" add 2>&1)
  status=$?

  [ "$status" -eq 0 ] || fail "interactive add failed: $out"
  assert_contains "$out" "Task type examples: feat, fix, chore, docs, refactor, test, perf, ci, build, revert"
  assert_contains "$out" "Task type [feat]"
  assert_contains "$out" "Task detail name"
  assert_contains "$out" "Task folder: feat-branch-name"
  assert_not_contains "$out" "Default task branch:"
  assert_branch "$project/feat-branch-name/frontend" "feat/branch-name"
  assert_branch "$project/feat-branch-name/backend" "feat/branch-name"
}

test_add_prompts_for_task_name_only_on_shared_parent_feature_base() {
  new_fixture
  project="$FIXTURE_PROJECT"
  commit_to_remote_branch frontend feature/cpq parent-frontend
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git feature/cpq
CONFIG
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf 'task1\n\n' | "$WORKBRANCH" add 2>&1)
  status=$?

  [ "$status" -eq 0 ] || fail "name-only add on shared parent feature base failed: $out"
  assert_contains "$out" "Task name"
  assert_not_contains "$out" "Task type"
  assert_not_contains "$out" "Task detail name"
  assert_contains "$out" "Task folder: feature-cpq-task1"
  assert_contains "$out" "  task repo branch [feature/cpq-task1]"
  assert_contains "$out" "  task repo folder: feature-cpq-task1/frontend"
  assert_branch "$project/feature-cpq-task1/frontend" "feature/cpq-task1"
}

test_add_bare_tty_name_prefills_task_name_on_shared_parent_feature_base() {
  new_fixture
  project="$FIXTURE_PROJECT"
  commit_to_remote_branch frontend feature/cpq parent-frontend
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git feature/cpq
CONFIG
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf '\n\n' | run_with_pty sh -c 'cd "$1" && shift && exec "$@"' sh "$project" "$WORKBRANCH" add task1 2>&1)
  status=$?

  [ "$status" -eq 0 ] || fail "TTY bare-name add on shared parent feature base failed: $out"
  assert_contains "$out" "Task name [task1]"
  assert_not_contains "$out" "Task type"
  assert_not_contains "$out" "Task detail name"
  assert_contains "$out" "Task folder: feature-cpq-task1"
  assert_contains "$out" "  task repo branch [feature/cpq-task1]"
  assert_branch "$project/feature-cpq-task1/frontend" "feature/cpq-task1"
  assert_not_exists "$project/task1"
}

test_add_mixed_bases_keep_conventional_task_identity_prompt() {
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

  out=$(printf 'feat\ntask1\n\n\n' | "$WORKBRANCH" add 2>&1)
  status=$?

  [ "$status" -eq 0 ] || fail "mixed-base interactive add failed: $out"
  assert_contains "$out" "Task type [feat]"
  assert_contains "$out" "Task detail name"
  assert_contains "$out" "Task folder: feat-task1"
  assert_contains "$out" "  task repo branch [feature/cpq-task1]"
  assert_contains "$out" "  task repo branch [feat/task1]"
  assert_branch "$project/feat-task1/frontend" "feature/cpq-task1"
  assert_branch "$project/feat-task1/backend" "feat/task1"
}

test_add_noninteractive_bare_name_keeps_legacy_folder_on_parent_feature_base() {
  new_fixture
  project="$FIXTURE_PROJECT"
  commit_to_remote_branch frontend feature/cpq parent-frontend
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git feature/cpq
CONFIG
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf '\n' | "$WORKBRANCH" add task1 2>&1)
  status=$?

  [ "$status" -eq 0 ] || fail "non-interactive bare-name add on parent feature base failed: $out"
  assert_not_contains "$out" "Task name"
  assert_not_contains "$out" "Task type"
  assert_contains "$out" "  task repo branch [feature/cpq-task1]"
  assert_contains "$out" "  task repo folder: task1/frontend"
  assert_branch "$project/task1/frontend" "feature/cpq-task1"
  assert_not_exists "$project/feature-cpq-task1"
}

test_add_parent_feature_base_with_unsafe_folder_slug_keeps_legacy_default() {
  new_fixture
  project="$FIXTURE_PROJECT"
  commit_to_remote_branch frontend 'feature/cpq+exp' parent-frontend
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git feature/cpq+exp
CONFIG
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf '\n' | "$WORKBRANCH" add task1 2>&1)
  status=$?

  [ "$status" -eq 0 ] || fail "add with folder-unsafe parent base failed: $out"
  assert_not_contains "$out" "parent branch folder slug"
  assert_contains "$out" "  task repo branch [feature/cpq+exp-task1]"
  assert_contains "$out" "  task repo folder: task1/frontend"
  assert_branch "$project/task1/frontend" "feature/cpq+exp-task1"
}

test_add_task_argument_prefills_interactive_task_detail() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf '\n\n\n\n' | run_with_pty sh -c 'cd "$1" && shift && exec "$@"' sh "$project" "$WORKBRANCH" add implement-login 2>&1)
  status=$?

  [ "$status" -eq 0 ] || fail "interactive add with default detail failed: $out"
  assert_contains "$out" "Task type examples: feat, fix, chore, docs, refactor, test, perf, ci, build, revert"
  assert_contains "$out" "Task type [feat]"
  assert_contains "$out" "Task detail name [implement-login]"
  assert_contains "$out" "Task folder: feat-implement-login"
  assert_not_contains "$out" "Default task branch:"
  assert_branch "$project/feat-implement-login/frontend" "feat/implement-login"
  assert_branch "$project/feat-implement-login/backend" "feat/implement-login"
  assert_not_exists "$project/implement-login"
}

test_add_without_task_argument_supports_from_ref() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feat/parent seeded-frontend
  commit_to_remote_branch backend feat/parent seeded-backend

  out=$(printf 'feat\nbranch-name\n\n\n' | "$WORKBRANCH" add --from feat/parent 2>&1)
  status=$?

  [ "$status" -eq 0 ] || fail "interactive add --from failed: $out"
  assert_branch "$project/feat-branch-name/frontend" "feat/branch-name"
  assert_branch "$project/feat-branch-name/backend" "feat/branch-name"
  assert_file "$project/feat-branch-name/frontend/seeded-frontend.txt"
  assert_file "$project/feat-branch-name/backend/seeded-backend.txt"
  assert_contains "$out" "[source] origin/feat/parent -> [task repo] feat/branch-name"
  if git -C "$project/feat-branch-name/frontend" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
    fail "expected add --from not to set frontend upstream"
  fi
}

test_add_explicit_task_without_conventional_prefix_keeps_legacy_default() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf '\n\n' | "$WORKBRANCH" add implement-login 2>&1)
  status=$?

  [ "$status" -eq 0 ] || fail "legacy explicit add failed: $out"
  assert_contains "$out" "  task repo branch [feature/implement-login]"
  assert_contains "$out" "  task repo folder: implement-login/frontend"
  assert_branch "$project/implement-login/frontend" "feature/implement-login"
}

test_add_rejects_legacy_plus_task_folder() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" add feat+branch-name)
  assert_contains "$out" "invalid task 'feat+branch-name' (expected [A-Za-z0-9._-]+)"
  assert_not_exists "$project/feat+branch-name"
}

test_add_rejects_conventional_detail_that_builds_invalid_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" add feat-bad.lock)
  assert_contains "$out" "invalid task detail name 'bad.lock': produces invalid branch 'feat/bad.lock'"
  assert_not_contains "$out" "invalid task ''"
  assert_not_contains "$out" "task repo branch"
  assert_not_exists "$project/feat-bad.lock"
}



test_add_rejects_empty_from_equals() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" add login --from=)
  assert_contains "$out" "missing value for --from"
  assert_not_exists "$project/login"
}

test_add_from_remote_ref_seeds_task_branch_from_origin_ref() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feat/parent seeded-frontend
  commit_to_remote_branch backend feat/parent seeded-backend

  out=$(printf '\n\n' | "$WORKBRANCH" add login --from feat/parent 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "add --from remote ref failed: $out"

  assert_branch "$project/login/frontend" "feature/login"
  assert_branch "$project/login/backend" "feature/login"
  assert_file "$project/login/frontend/seeded-frontend.txt"
  assert_file "$project/login/backend/seeded-backend.txt"
  assert_contains "$out" "[source] origin/feat/parent -> [task repo] feature/login"
  if git -C "$project/login/frontend" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
    fail "expected add --from not to set frontend upstream"
  fi
  if git -C "$project/login/backend" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
    fail "expected add --from not to set backend upstream"
  fi
  assert_not_contains "$(cat "$project/login/.workbranch.task")" "feat/parent"
}

test_add_from_missing_ref_fails_before_creating_task() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feat/parent seeded-frontend

  out=$(run_expect_fail "$WORKBRANCH" add login --from feat/parent)
  assert_contains "$out" "_base/backend missing source ref: feat/parent"
  assert_not_exists "$project/login"
}

test_add_task_branch_override_is_used_by_later_commands() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf 'tk/login-frontend\ntk/login-backend\n' | "$WORKBRANCH" add login 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "add with branch overrides failed: $out"

  assert_branch "$project/login/frontend" "tk/login-frontend"
  assert_branch "$project/login/backend" "tk/login-backend"
  assert_contains "$(cat "$project/login/.workbranch.task")" "REPO_BRANCH frontend tk/login-frontend"
  assert_contains "$(cat "$project/login/.workbranch.task")" "REPO_BRANCH backend tk/login-backend"

  git -C "$project/login/frontend" config user.name "Workbranch Test"
  git -C "$project/login/frontend" config user.email "workbranch-test@example.com"
  printf 'frontend scoped\n' > "$project/login/frontend/scoped.txt"
  git -C "$project/login/frontend" add scoped.txt
  git -C "$project/login/frontend" commit -m "frontend scoped" >/dev/null

  out=$("$WORKBRANCH" push login --repo frontend 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "push with branch override failed: $out"
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" tk/login-frontend scoped.txt "frontend scoped"
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" feature/login scoped.txt
}

test_add_rejects_existing_task_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  git -C "$project/_base/frontend" branch feature/login

  out=$(run_expect_fail "$WORKBRANCH" add login)
  assert_contains "$out" "task branch already exists for repo 'frontend': feature/login"
  assert_contains "$out" "To delete the local branch first: workbranch remove login"
  assert_not_contains "$out" "workbranch resume"
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
  assert_contains "$out" "Remote origin/feature/login exists; delete it outside workbranch before adding again."
  assert_not_contains "$out" "workbranch resume"
  assert_not_contains "$out" "workbranch remove login"
  assert_not_exists "$project/login"
}

test_add_rejects_invalid_task_branch_override() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf 'bad branch\n' | "$WORKBRANCH" add login 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "expected invalid task branch override to fail"
  assert_contains "$out" "invalid task branch 'bad branch'"
  assert_not_exists "$project/login"
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
