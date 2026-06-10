# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.
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


test_update_preflight_blocks_rebase_conflict_without_touching_task() {
  new_fixture
  project="$FIXTURE_PROJECT"
  project_root=$(cd "$project" && pwd -P) || return 1
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  git -C "$project/login/frontend" config user.name "Workbranch Test"
  git -C "$project/login/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "task change" > "$project/login/frontend/README.md"
  git -C "$project/login/frontend" add README.md
  git -C "$project/login/frontend" commit -m "task edits readme" >/dev/null
  task_head_before=$(git -C "$project/login/frontend" rev-parse HEAD)

  git -C "$project/_base/frontend" config user.name "Workbranch Test"
  git -C "$project/_base/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "base change" > "$project/_base/frontend/README.md"
  git -C "$project/_base/frontend" add README.md
  git -C "$project/_base/frontend" commit -m "base edits readme" >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" update login --repo frontend)
  assert_contains "$out" "Cannot update: preflight failed"
  assert_contains "$out" "login/frontend cannot rebase onto _base/frontend"
  assert_contains "$out" "Resolve manually:"
  assert_contains "$out" "git -C $project_root/login/frontend rebase \"\$(git -C $project_root/_base/frontend rev-parse HEAD)\""
  assert_contains "$out" "git -C $project_root/login/frontend add <resolved-files>"
  assert_contains "$out" "git -C $project_root/login/frontend rebase --continue"
  assert_contains "$out" "workbranch update login --repo frontend"
  [ "$(git -C "$project/login/frontend" rev-parse HEAD)" = "$task_head_before" ] || fail "task HEAD changed after update conflict preflight"
  assert_clean "$project/login/frontend"
}

test_update_preflight_guidance_uses_project_root_from_subdirectory() {
  new_fixture
  project="$FIXTURE_PROJECT"
  project_root=$(cd "$project" && pwd -P) || return 1
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  git -C "$project/login/frontend" config user.name "Workbranch Test"
  git -C "$project/login/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "task change" > "$project/login/frontend/README.md"
  git -C "$project/login/frontend" add README.md
  git -C "$project/login/frontend" commit -m "task edits readme" >/dev/null

  git -C "$project/_base/frontend" config user.name "Workbranch Test"
  git -C "$project/_base/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "base change" > "$project/_base/frontend/README.md"
  git -C "$project/_base/frontend" add README.md
  git -C "$project/_base/frontend" commit -m "base edits readme" >/dev/null

  cd "$project/login/frontend" || return 1
  out=$(run_expect_fail "$WORKBRANCH" update login --repo frontend)
  assert_contains "$out" "Cannot update: preflight failed"
  assert_contains "$out" "git -C $project_root/login/frontend rebase \"\$(git -C $project_root/_base/frontend rev-parse HEAD)\""
  assert_not_contains "$out" "git -C login/frontend rebase"
}
