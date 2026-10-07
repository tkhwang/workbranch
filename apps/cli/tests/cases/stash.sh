# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

stash_fixture_with_two_tasks() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '\n\n' | run_expect_success "$WORKBRANCH" add task-b >/dev/null
  printf '\n\n' | run_expect_success "$WORKBRANCH" add task-c >/dev/null
  export GIT_AUTHOR_NAME="Workbranch Test" GIT_AUTHOR_EMAIL="workbranch-test@example.com"
  export GIT_COMMITTER_NAME="Workbranch Test" GIT_COMMITTER_EMAIL="workbranch-test@example.com"
  wt_b="$project/task-b/frontend"
  wt_c="$project/task-c/frontend"
}

test_stash_keeps_worktree_changes_separate() {
  stash_fixture_with_two_tasks
  printf 'B change\n' >> "$wt_b/README.md"
  mkdir -p "$wt_b/plans/new"
  printf 'b plan\n' > "$wt_b/plans/new/b.md"
  printf 'C change\n' >> "$wt_c/README.md"

  out=$(cd "$wt_b" && run_expect_success "$WORKBRANCH" stash -m "b wip")
  assert_contains "$out" "Saved local changes on feature/task-b"
  assert_clean "$wt_b"
  assert_not_exists "$wt_b/plans"
  (cd "$wt_c" && run_expect_success "$WORKBRANCH" stash) >/dev/null
  assert_clean "$wt_c"

  shared=$(git -C "$wt_b" stash list)
  [ -z "$shared" ] || fail "expected shared git stash list to stay empty, got: $shared"

  out=$(cd "$wt_b" && run_expect_success "$WORKBRANCH" stash list)
  assert_contains "$out" "feature/task-b"
  assert_contains "$out" "On feature/task-b: b wip"
  assert_contains "$out" "feature/task-c"

  (cd "$wt_b" && run_expect_success "$WORKBRANCH" stash pop) >/dev/null
  content=$(cat "$wt_b/README.md")
  assert_contains "$content" "B change"
  assert_not_contains "$content" "C change"
  assert_file "$wt_b/plans/new/b.md"

  out=$(cd "$wt_b" && run_expect_fail "$WORKBRANCH" stash pop)
  assert_contains "$out" "no workbranch stash for branch 'feature/task-b'"

  (cd "$wt_c" && run_expect_success "$WORKBRANCH" stash pop) >/dev/null
  content=$(cat "$wt_c/README.md")
  assert_contains "$content" "C change"
  assert_not_contains "$content" "B change"

  out=$(cd "$wt_c" && run_expect_success "$WORKBRANCH" stash list)
  assert_contains "$out" "No workbranch stashes"
}

test_stash_restores_after_base_moves_and_from_subdirectory() {
  stash_fixture_with_two_tasks
  mkdir -p "$wt_b/src"
  printf 'tracked\n' > "$wt_b/src/keep.txt"
  git -C "$wt_b" add src/keep.txt
  git -C "$wt_b" commit -m "add src" >/dev/null
  printf 'staged\n' > "$wt_b/staged.txt"
  git -C "$wt_b" add staged.txt
  printf 'untracked\n' > "$wt_b/src/new.txt"

  (cd "$wt_b/src" && run_expect_success "$WORKBRANCH" stash) >/dev/null
  assert_clean "$wt_b"
  assert_file "$wt_b/src/keep.txt"

  printf 'more\n' > "$wt_b/other.txt"
  git -C "$wt_b" add other.txt
  git -C "$wt_b" commit -m "move head" >/dev/null

  (cd "$wt_b/src" && run_expect_success "$WORKBRANCH" stash pop --index) >/dev/null
  assert_file "$wt_b/src/new.txt"
  staged=$(git -C "$wt_b" diff --cached --name-only)
  [ "$staged" = "staged.txt" ] || fail "expected staged.txt to stay staged, got: $staged"
}

test_stash_refuses_second_slot_and_keeps_stash_on_conflict() {
  stash_fixture_with_two_tasks
  out=$(cd "$wt_b" && run_expect_success "$WORKBRANCH" stash)
  assert_contains "$out" "No local changes to save"

  printf 'stashed\n' > "$wt_b/README.md"
  (cd "$wt_b" && run_expect_success "$WORKBRANCH" stash) >/dev/null
  printf 'second\n' > "$wt_b/README.md"
  out=$(cd "$wt_b" && run_expect_fail "$WORKBRANCH" stash)
  assert_contains "$out" "already has a workbranch stash"

  git -C "$wt_b" commit -am "conflicting" >/dev/null
  out=$(cd "$wt_b" && run_expect_fail "$WORKBRANCH" stash pop)
  assert_contains "$out" "the stash is kept"
  git -C "$wt_b" reset --hard -q
  out=$(cd "$wt_b" && run_expect_success "$WORKBRANCH" stash show -p)
  assert_contains "$out" "+stashed"

  out=$(cd "$wt_c" && run_expect_success "$WORKBRANCH" stash drop --branch feature/task-b)
  assert_contains "$out" "Dropped workbranch stash for feature/task-b"
  out=$(cd "$wt_b" && run_expect_fail "$WORKBRANCH" stash apply)
  assert_contains "$out" "no workbranch stash"
}

test_stash_rejects_detached_head_and_non_repo() {
  stash_fixture_with_two_tasks
  git -C "$wt_b" checkout -q --detach
  out=$(cd "$wt_b" && run_expect_fail "$WORKBRANCH" stash)
  assert_contains "$out" "detached HEAD"
  out=$(cd "$project" && run_expect_fail "$WORKBRANCH" stash)
  assert_contains "$out" "must run inside a git worktree"
}
