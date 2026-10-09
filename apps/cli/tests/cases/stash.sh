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

test_stash_preserves_external_files_when_reset_restores_symlink() {
  stash_fixture_with_two_tasks
  outside="$TMP_ROOT/outside"
  mkdir -p "$outside"
  printf 'external sentinel\n' > "$outside/file with spaces.txt"
  ln -s "$outside" "$wt_b/link"
  git -C "$wt_b" add link
  git -C "$wt_b" commit -m 'track external symlink' >/dev/null
  rm "$wt_b/link"
  mkdir "$wt_b/link"
  printf 'captured contents\n' > "$wt_b/link/file with spaces.txt"

  (cd "$wt_b" && run_expect_success "$WORKBRANCH" stash) >/dev/null || return 1
  [ "$(cat "$outside/file with spaces.txt")" = 'external sentinel' ] || fail 'external file changed'
  [ -L "$wt_b/link" ] || fail 'tracked symlink was not restored'
  assert_clean "$wt_b"
  saved=$(git -C "$wt_b" rev-parse refs/workbranch/stash-v2/feature%2Ftask-b)
  [ "$(git -C "$wt_b" show "$saved^3:link/file with spaces.txt")" = 'captured contents' ] || fail 'captured file missing from stash'
  # Git cannot restore the untracked directory over the tracked symlink.
  # Preserve the slot on conflict, then remove only the link and retry.
  out=$(cd "$wt_b" && run_expect_fail "$WORKBRANCH" stash pop)
  assert_contains "$out" 'the stash is kept'
  [ "$(git -C "$wt_b" rev-parse refs/workbranch/stash-v2/feature%2Ftask-b)" = "$saved" ] || fail 'conflict lost stash'
  [ "$(cat "$outside/file with spaces.txt")" = 'external sentinel' ] || fail 'failed restore changed external file'
  rm "$wt_b/link"
  (cd "$wt_b" && run_expect_success "$WORKBRANCH" stash pop) >/dev/null || return 1
  [ ! -L "$wt_b/link" ] || fail 'expected restored directory'
  [ "$(cat "$wt_b/link/file with spaces.txt")" = 'captured contents' ] || fail 'captured file not restored'
  [ "$(cat "$outside/file with spaces.txt")" = 'external sentinel' ] || fail 'restore changed external file'
}

test_stash_encoded_refs_avoid_prefix_and_escape_collisions() {
  stash_fixture_with_two_tasks
  for branch in foo foo/bar foo%2Fbar; do
    git -C "$wt_b" branch -m "$branch" || return 1
    printf '%s\n' "$branch" > "$wt_b/saved.txt"
    (cd "$wt_b" && run_expect_success "$WORKBRANCH" stash) >/dev/null || return 1
  done
  out=$(cd "$wt_b" && run_expect_success "$WORKBRANCH" stash list)
  for branch in foo foo/bar foo%2Fbar; do
    assert_contains "$out" "$branch"
    (cd "$wt_b" && run_expect_success "$WORKBRANCH" stash pop --branch "$branch") >/dev/null || return 1
    [ "$(cat "$wt_b/saved.txt")" = "$branch" ] || fail "wrong stash restored for $branch"
    rm "$wt_b/saved.txt"
  done
  out=$(cd "$wt_b" && run_expect_success "$WORKBRANCH" stash list)
  assert_contains "$out" 'No workbranch stashes'
}

test_stash_legacy_slots_remain_accessible() {
  stash_fixture_with_two_tasks
  git -C "$wt_b" branch -m foo
  printf 'legacy change\n' >> "$wt_b/README.md"
  saved=$(git -C "$wt_b" stash create)
  git -C "$wt_b" update-ref refs/workbranch/stash/foo "$saved"
  git -C "$wt_b" reset --hard -q
  printf 'new change\n' > "$wt_b/new.txt"
  out=$(cd "$wt_b" && run_expect_fail "$WORKBRANCH" stash)
  assert_contains "$out" 'already has a workbranch stash'
  assert_file "$wt_b/new.txt"
  rm "$wt_b/new.txt"
  git -C "$wt_b" branch -m foo/bar
  printf 'new change\n' > "$wt_b/new.txt"
  (cd "$wt_b" && run_expect_success "$WORKBRANCH" stash) >/dev/null || return 1
  out=$(cd "$wt_b" && run_expect_success "$WORKBRANCH" stash list)
  assert_contains "$out" 'foo'
  assert_contains "$out" 'foo/bar'
  out=$(cd "$wt_b" && run_expect_success "$WORKBRANCH" stash show -p --branch foo)
  assert_contains "$out" '+legacy change'
  (cd "$wt_b" && run_expect_success "$WORKBRANCH" stash apply --branch foo) >/dev/null || return 1
  assert_contains "$(cat "$wt_b/README.md")" 'legacy change'
  [ "$(git -C "$wt_b" rev-parse refs/workbranch/stash/foo)" = "$saved" ] || fail 'apply removed legacy slot'
  (cd "$wt_b" && run_expect_success "$WORKBRANCH" stash drop --branch foo) >/dev/null || return 1
  git -C "$wt_b" update-ref refs/workbranch/stash/foo "$saved"
  git -C "$wt_b" reset --hard -q
  (cd "$wt_b" && run_expect_success "$WORKBRANCH" stash pop --branch foo) >/dev/null || return 1
  assert_contains "$(cat "$wt_b/README.md")" 'legacy change'
  if git -C "$wt_b" rev-parse --verify refs/workbranch/stash/foo >/dev/null 2>&1; then
    fail 'pop did not remove legacy slot'
  fi
}

test_stash_rejects_revert_without_changing_state() {
  stash_fixture_with_two_tasks
  printf 'saved change\n' >> "$wt_b/README.md"
  (cd "$wt_b" && run_expect_success "$WORKBRANCH" stash) >/dev/null || return 1
  printf 'revert me\n' > "$wt_b/revert.txt"
  git -C "$wt_b" add revert.txt
  git -C "$wt_b" commit -m 'revert target' >/dev/null
  git -C "$wt_b" revert --no-commit HEAD || return 1
  revert_head=$(git -C "$wt_b" rev-parse --verify REVERT_HEAD) || return 1
  before_index=$(git -C "$wt_b" write-tree)
  before_status=$(git -C "$wt_b" status --porcelain)
  slot=refs/workbranch/stash-v2/feature%2Ftask-b
  saved=$(git -C "$wt_b" rev-parse "$slot") || return 1
  git -C "$wt_b" update-ref -d "$slot" "$saved" || return 1
  for command in push apply pop; do
    # Push has no occupied slot, so only the operation guard can stop it.
    if [ "$command" = apply ]; then
      git -C "$wt_b" update-ref "$slot" "$saved" || return 1
    fi
    before_refs=$(git -C "$wt_b" for-each-ref refs/workbranch)
    out=$(cd "$wt_b" && run_expect_fail "$WORKBRANCH" stash "$command")
    assert_contains "$out" 'revert is in progress'
    [ "$(git -C "$wt_b" rev-parse REVERT_HEAD)" = "$revert_head" ] || fail 'REVERT_HEAD changed'
    [ "$(git -C "$wt_b" write-tree)" = "$before_index" ] || fail 'index changed'
    [ "$(git -C "$wt_b" status --porcelain)" = "$before_status" ] || fail 'worktree changed'
    [ "$(git -C "$wt_b" for-each-ref refs/workbranch)" = "$before_refs" ] || fail 'stash refs changed'
  done
  git -C "$wt_b" revert --abort || return 1
  assert_clean "$wt_b"
}

test_stash_cleanup_failure_keeps_saved_ref_and_skips_reset() {
  stash_fixture_with_two_tasks
  printf 'tracked change\n' >> "$wt_b/README.md"
  printf 'untracked change\n' > "$wt_b/blocked.txt"
  mkdir "$TMP_ROOT/mock-bin"
  real_rm=$(command -v rm)
  export STASH_TEST_REAL_RM="$real_rm" STASH_TEST_BLOCKED="$wt_b/blocked.txt"
  cat > "$TMP_ROOT/mock-bin/rm" <<'SCRIPT'
#!/usr/bin/env bash
for arg in "$@"; do
  [ "$arg" != "$STASH_TEST_BLOCKED" ] || exit 1
done
exec "$STASH_TEST_REAL_RM" "$@"
SCRIPT
  chmod +x "$TMP_ROOT/mock-bin/rm"
  out=$(cd "$wt_b" && PATH="$TMP_ROOT/mock-bin:$PATH" run_expect_fail "$WORKBRANCH" stash)
  assert_contains "$out" 'stash kept and reset skipped'
  assert_contains "$(cat "$wt_b/README.md")" 'tracked change'
  assert_file "$wt_b/blocked.txt"
  saved=$(git -C "$wt_b" rev-parse refs/workbranch/stash-v2/feature%2Ftask-b) || return 1
  [ "$(git -C "$wt_b" show "$saved^3:blocked.txt")" = 'untracked change' ] || fail 'saved untracked data missing'
}
