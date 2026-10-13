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
  assert_contains "$out" "payment/backend dirty worktree; retry with --autostash"
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

autostash_fixture() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  run_expect_success "$WORKBRANCH" add payment >/dev/null
  export GIT_AUTHOR_NAME="Workbranch Test" GIT_AUTHOR_EMAIL="workbranch-test@example.com"
  export GIT_COMMITTER_NAME="Workbranch Test" GIT_COMMITTER_EMAIL="workbranch-test@example.com"
}

commit_to_local_base() {
  printf '%s\n' "$3" > "$project/_base/$1/$2"
  git -C "$project/_base/$1" add "$2"
  git -C "$project/_base/$1" commit -m "base edits $2" >/dev/null
}

assert_no_workbranch_stash() {
  refs=$(git -C "$1" for-each-ref refs/workbranch)
  [ -z "$refs" ] || fail "expected no workbranch stash refs in $1, got: $refs"
  shared=$(git -C "$1" stash list)
  [ -z "$shared" ] || fail "expected shared git stash list to stay empty, got: $shared"
}

# Fails `git rebase` or `git stash apply` in the real login/frontend worktree
# only; preflight replays in a scratch worktree and is unaffected.
install_autostash_git_mock() {
  mkdir -p "$TMP_ROOT/mock-bin"
  export AUTOSTASH_TEST_REAL_GIT
  AUTOSTASH_TEST_REAL_GIT=$(command -v git)
  export AUTOSTASH_TEST_FAIL=$1
  cat > "$TMP_ROOT/mock-bin/git" <<'SCRIPT'
#!/usr/bin/env bash
case "$AUTOSTASH_TEST_FAIL:${1:-}:${2:-}:${3:-}:${4:-}" in
  rebase:-C:*/login/frontend:rebase:--abort) ;;
  rebase:-C:*/login/frontend:rebase:*) echo "mock rebase failure" >&2; exit 1 ;;
  apply:stash:apply:*)
    case "$PWD" in */login/frontend) echo "mock apply failure" >&2; exit 1 ;; esac
    ;;
esac
exec "$AUTOSTASH_TEST_REAL_GIT" "$@"
SCRIPT
  chmod +x "$TMP_ROOT/mock-bin/git"
}

test_update_autostash_restores_dirty_changes_across_tasks() {
  autostash_fixture || return 1
  commit_to_local_base backend base-backend.txt "base backend"
  login_be="$project/login/backend"
  printf 'login tracked\n' >> "$login_be/README.md"
  printf 'login staged\n' > "$login_be/staged.txt"
  git -C "$login_be" add staged.txt
  mkdir -p "$login_be/notes"
  printf 'login untracked\n' > "$login_be/notes/todo.md"
  printf 'payment tracked\n' >> "$project/payment/backend/README.md"
  printf 'idle frontend\n' >> "$project/login/frontend/README.md"
  login_fe_head=$(git -C "$project/login/frontend" rev-parse HEAD)

  out=$(run_expect_success "$WORKBRANCH" update --autostash)
  assert_contains "$out" "Stashed local changes as"
  assert_contains "$out" "Restored local changes from"
  assert_contains "$out" "Already up to date; local changes left in place"
  assert_contains "$out" "Updated: payment/frontend"

  assert_file "$login_be/base-backend.txt"
  assert_file "$project/payment/backend/base-backend.txt"
  assert_contains "$(cat "$login_be/README.md")" "login tracked"
  assert_file "$login_be/notes/todo.md"
  staged=$(git -C "$login_be" diff --cached --name-only)
  [ "$staged" = "staged.txt" ] || fail "expected staged.txt to stay staged, got: $staged"
  unstaged=$(git -C "$login_be" diff --name-only)
  [ "$unstaged" = "README.md" ] || fail "expected README.md to stay unstaged, got: $unstaged"
  assert_contains "$(cat "$project/payment/backend/README.md")" "payment tracked"
  assert_contains "$(cat "$project/login/frontend/README.md")" "idle frontend"
  [ "$(git -C "$project/login/frontend" rev-parse HEAD)" = "$login_fe_head" ] || fail "up-to-date task HEAD moved"
  assert_no_workbranch_stash "$login_be"
}

test_update_autostash_preflight_blocks_restore_conflict_before_changes() {
  autostash_fixture || return 1
  project_root=$(cd "$project" && pwd -P) || return 1
  commit_to_local_base frontend README.md "base readme"
  commit_to_local_base backend base-backend.txt "base backend"
  wt="$project/login/frontend"
  printf 'local readme\n' > "$wt/README.md"
  head_before=$(git -C "$wt" rev-parse HEAD)

  out=$(run_expect_fail "$WORKBRANCH" update --autostash)
  assert_contains "$out" "Cannot update: preflight failed"
  assert_contains "$out" "login/frontend local changes conflict with _base/frontend after rebase"
  assert_contains "$out" "(cd $project_root/login/frontend && workbranch stash)"
  assert_contains "$out" "workbranch update login --repo frontend"
  [ "$(git -C "$wt" rev-parse HEAD)" = "$head_before" ] || fail "task HEAD changed after autostash preflight"
  [ "$(cat "$wt/README.md")" = "local readme" ] || fail "local change lost after autostash preflight"
  assert_not_exists "$project/payment/backend/base-backend.txt"
  assert_no_workbranch_stash "$wt"
  worktrees=$(git -C "$wt" worktree list --porcelain | grep -c '^worktree ')
  [ "$worktrees" -eq 3 ] || fail "expected scratch worktree cleanup, got $worktrees worktrees"
}

test_update_autostash_preflight_blocks_occupied_stash_slot() {
  autostash_fixture || return 1
  commit_to_local_base frontend base-frontend.txt "base frontend"
  wt="$project/login/frontend"
  printf 'parked\n' >> "$wt/README.md"
  (cd "$wt" && run_expect_success "$WORKBRANCH" stash) >/dev/null || return 1
  printf 'new local\n' > "$wt/new.txt"

  out=$(run_expect_fail "$WORKBRANCH" update login --autostash)
  assert_contains "$out" "login/frontend already has a workbranch stash"
  assert_file "$wt/new.txt"
  assert_not_exists "$wt/base-frontend.txt"
}

test_update_autostash_restores_changes_when_rebase_fails() {
  autostash_fixture || return 1
  commit_to_local_base frontend base-frontend.txt "base frontend"
  wt="$project/login/frontend"
  printf 'local\n' >> "$wt/README.md"
  printf 'untracked\n' > "$wt/untracked.txt"
  head_before=$(git -C "$wt" rev-parse HEAD)
  install_autostash_git_mock rebase

  out=$(PATH="$TMP_ROOT/mock-bin:$PATH" run_expect_fail "$WORKBRANCH" update login --repo frontend --autostash)
  assert_contains "$out" "rebase aborted and local changes restored"
  [ "$(git -C "$wt" rev-parse HEAD)" = "$head_before" ] || fail "task HEAD changed after failed rebase"
  assert_contains "$(cat "$wt/README.md")" "local"
  assert_file "$wt/untracked.txt"
  assert_no_workbranch_stash "$wt"
}

test_update_autostash_keeps_stash_when_restore_fails() {
  autostash_fixture || return 1
  commit_to_local_base frontend base-frontend.txt "base frontend"
  wt="$project/login/frontend"
  printf 'local\n' >> "$wt/README.md"
  install_autostash_git_mock apply

  out=$(PATH="$TMP_ROOT/mock-bin:$PATH" run_expect_fail "$WORKBRANCH" update login --repo frontend --autostash)
  assert_contains "$out" "did not restore cleanly and is kept"
  assert_file "$wt/base-frontend.txt"
  git -C "$wt" rev-parse --verify -q refs/workbranch/stash-v2/feature%2Flogin >/dev/null || fail "stash slot was dropped"

  (cd "$wt" && run_expect_success "$WORKBRANCH" stash pop) >/dev/null || return 1
  assert_contains "$(cat "$wt/README.md")" "local"
  assert_no_workbranch_stash "$wt"
}

test_update_preflight_protects_ignored_files_from_base() {
  autostash_fixture || return 1
  wt="$project/login/frontend"
  printf 'local.env\n' >> "$(git -C "$wt" rev-parse --git-common-dir)/info/exclude"
  printf 'MY SECRET\n' > "$wt/local.env"
  printf 'BASE\n' > "$project/_base/frontend/local.env"
  git -C "$project/_base/frontend" add -f local.env
  git -C "$project/_base/frontend" commit -m "base tracks local.env" >/dev/null
  head_before=$(git -C "$wt" rev-parse HEAD)

  out=$(run_expect_fail "$WORKBRANCH" update login --repo frontend)
  assert_contains "$out" "login/frontend has local files that _base/frontend would overwrite"
  assert_contains "$out" "  local.env"
  [ "$(cat "$wt/local.env")" = "MY SECRET" ] || fail "ignored file overwritten by update"

  printf 'dirty\n' >> "$wt/README.md"
  out=$(run_expect_fail "$WORKBRANCH" update login --repo frontend --autostash)
  assert_contains "$out" "login/frontend has local files that _base/frontend would overwrite"
  [ "$(cat "$wt/local.env")" = "MY SECRET" ] || fail "ignored file overwritten by autostash update"
  [ "$(git -C "$wt" rev-parse HEAD)" = "$head_before" ] || fail "task HEAD changed after overwrite preflight"
  assert_no_workbranch_stash "$wt"
}

test_update_autostash_preflight_blocks_embedded_repo_it_cannot_save() {
  autostash_fixture || return 1
  wt="$project/login/frontend"
  mkdir -p "$project/_base/frontend/vendor/lib"
  commit_to_local_base frontend vendor/lib/lib.txt "base lib"
  git init -q "$wt/vendor/lib"
  printf 'nested\n' > "$wt/vendor/lib/lib.txt"
  commit_to_local_base backend base-backend.txt "base backend"

  out=$(run_expect_fail "$WORKBRANCH" update --autostash)
  assert_contains "$out" "login/frontend has local files that _base/frontend would overwrite"
  assert_contains "$out" "  vendor/lib/lib.txt"
  [ "$(cat "$wt/vendor/lib/lib.txt")" = "nested" ] || fail "embedded repository file changed"
  assert_not_exists "$project/payment/backend/base-backend.txt"
  assert_no_workbranch_stash "$wt"
}

test_update_preflight_keeps_other_branch_refs_with_update_refs() {
  autostash_fixture || return 1
  wt="$project/login/frontend"
  printf 'task\n' > "$wt/task.txt"
  git -C "$wt" add task.txt
  git -C "$wt" commit -m "task commit" >/dev/null
  git -C "$wt" branch side HEAD
  git -C "$wt" config rebase.updateRefs true
  side_before=$(git -C "$wt" rev-parse side)
  commit_to_local_base frontend base-frontend.txt "base frontend"

  # login/frontend replays its rebase in a scratch worktree; the dirty
  # payment/backend then fails preflight, so nothing should change.
  printf 'dirty payment\n' >> "$project/payment/backend/README.md"
  run_expect_fail "$WORKBRANCH" update >/dev/null
  [ "$(git -C "$wt" rev-parse side)" = "$side_before" ] || fail "rebase preflight moved branch side"

  # Same with the autostash replay; an occupied slot fails payment/backend.
  printf 'dirty\n' >> "$wt/README.md"
  (cd "$project/payment/backend" && run_expect_success "$WORKBRANCH" stash) >/dev/null || return 1
  printf 'dirty payment again\n' >> "$project/payment/backend/README.md"
  out=$(run_expect_fail "$WORKBRANCH" update --autostash)
  assert_contains "$out" "payment/backend already has a workbranch stash"
  [ "$(git -C "$wt" rev-parse side)" = "$side_before" ] || fail "autostash preflight moved branch side"
}
