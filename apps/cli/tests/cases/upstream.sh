# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

# Project whose repos use feature/cpq as base branch. master stays origin's
# default branch, so it is the upstream that `workbranch upstream` detects.
upstream_fixture() {
  new_fixture
  project="$FIXTURE_PROJECT"
  commit_to_remote_branch frontend feature/cpq cpq-frontend
  commit_to_remote_branch backend feature/cpq cpq-backend
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git feature/cpq
REPO backend $TMP_ROOT/remotes/backend.git feature/cpq
CONFIG
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  for repo in frontend backend; do
    git -C "$project/_base/$repo" config user.name "Workbranch Test"
    git -C "$project/_base/$repo" config user.email "workbranch-test@example.com"
  done
}

# Commit one file with the given content to a remote branch.
upstream_commit_file_to_remote() {
  name=$1
  branch=$2
  file=$3
  content=$4
  clone="$TMP_ROOT/upstream-file-$name-$RANDOM"
  git clone "$TMP_ROOT/remotes/$name.git" "$clone" >/dev/null 2>&1
  git -C "$clone" config user.name "Workbranch Test"
  git -C "$clone" config user.email "workbranch-test@example.com"
  git -C "$clone" checkout -B "$branch" "origin/$branch" >/dev/null 2>&1
  mkdir -p "$(dirname "$clone/$file")"
  printf '%s\n' "$content" > "$clone/$file"
  git -C "$clone" add -f "$file"
  git -C "$clone" commit -m "$branch edits $file" >/dev/null
  git -C "$clone" push origin "$branch" >/dev/null 2>&1
}

# Leave Git no committer identity for one base repo: none in its config, none
# inherited from the machine or the environment, and no guessing from the host.
upstream_remove_git_identity() {
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  git -C "$1" config --unset user.name
  git -C "$1" config --unset user.email
  git -C "$1" config user.useConfigOnly true
  if git -C "$1" var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
    fail "Git still has a committer identity in $1"
  fi
}

# Hooks in the repo's own hooks directory, whatever core.hooksPath the machine sets.
upstream_install_hook() {
  git -C "$1" config core.hooksPath "$1/.git/hooks"
  mkdir -p "$1/.git/hooks"
  printf '%s\n' '#!/bin/sh' "$3" > "$1/.git/hooks/$2"
  chmod +x "$1/.git/hooks/$2"
}

test_upstream_merges_default_branch_into_local_feature_base() {
  upstream_fixture || return 1
  run_expect_success "$WORKBRANCH" add task-a >/dev/null

  commit_to_remote_master frontend upstream-frontend
  commit_to_remote_master backend upstream-backend
  remote_master=$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse master)
  remote_base_before=$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse feature/cpq)

  out=$(run_expect_success "$WORKBRANCH" upstream)
  assert_contains "$out" "Merging frontend: origin/master -> feature/cpq"
  assert_contains "$out" "Merged: frontend"
  assert_contains "$out" "Merging backend: origin/master -> feature/cpq"
  assert_contains "$out" "Merged: backend"
  assert_branch "$project/_base/frontend" feature/cpq
  assert_clean "$project/_base/frontend"
  assert_file "$project/_base/frontend/cpq-frontend.txt"
  assert_file "$project/_base/frontend/upstream-frontend.txt"
  assert_file "$project/_base/backend/upstream-backend.txt"
  git -C "$project/_base/frontend" merge-base --is-ancestor "$remote_master" HEAD || fail "base does not contain origin/master"
  parents=$(git -C "$project/_base/frontend" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')
  [ "$parents" -eq 3 ] || fail "expected a merge commit on the base branch"
  subject=$(git -C "$project/_base/frontend" log -1 --format=%s)
  [ "$subject" = "Merge remote-tracking branch 'origin/master' into feature/cpq" ] || fail "unexpected merge message: $subject"

  # Local base only: tasks and the remote base branch are left alone.
  assert_not_exists "$project/task-a/frontend/upstream-frontend.txt"
  [ "$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse feature/cpq)" = "$remote_base_before" ] || fail "upstream pushed the base branch"

  head_after=$(git -C "$project/_base/frontend" rev-parse HEAD)
  out=$(run_expect_success "$WORKBRANCH" upstream)
  assert_contains "$out" "Already up to date: frontend"
  assert_not_contains "$out" "Merged: frontend"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$head_after" ] || fail "second upstream changed the base"
}

test_upstream_result_reaches_tasks_and_remote_through_update_and_push() {
  upstream_fixture || return 1
  run_expect_success "$WORKBRANCH" add task-a >/dev/null
  commit_to_remote_master frontend upstream-flow

  run_expect_success "$WORKBRANCH" upstream --repo frontend >/dev/null
  run_expect_success "$WORKBRANCH" update task-a --repo frontend >/dev/null
  assert_file "$project/task-a/frontend/upstream-flow.txt"
  run_expect_success "$WORKBRANCH" push --repo frontend >/dev/null
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" feature/cpq upstream-flow.txt upstream-flow
}

test_upstream_from_ref_merges_named_branch() {
  upstream_fixture || return 1
  commit_to_remote_branch frontend develop develop-frontend
  commit_to_remote_master frontend master-only
  commit_to_remote_branch backend release release-backend

  out=$(run_expect_success "$WORKBRANCH" upstream --from develop --repo frontend)
  assert_contains "$out" "Merging frontend: origin/develop -> feature/cpq"
  assert_file "$project/_base/frontend/develop-frontend.txt"
  assert_not_exists "$project/_base/frontend/master-only.txt"

  out=$(run_expect_success "$WORKBRANCH" upstream --repo backend --from=origin/release)
  assert_contains "$out" "Merging backend: origin/release -> feature/cpq"
  assert_file "$project/_base/backend/release-backend.txt"
}

test_upstream_repo_scope_limits_merge() {
  upstream_fixture || return 1
  commit_to_remote_master frontend scoped-frontend
  commit_to_remote_master backend scoped-backend
  backend_before=$(git -C "$project/_base/backend" rev-parse HEAD)

  out=$(run_expect_success "$WORKBRANCH" upstream --repo frontend)
  assert_contains "$out" "Merging frontend"
  assert_not_contains "$out" "backend"
  assert_file "$project/_base/frontend/scoped-frontend.txt"
  [ "$(git -C "$project/_base/backend" rev-parse HEAD)" = "$backend_before" ] || fail "filtered-out repo was merged"
}

test_upstream_fast_forwards_base_without_own_commits() {
  new_fixture
  project="$FIXTURE_PROJECT"
  commit_to_remote_branch frontend feature/cpq cpq-frontend
  # master moves past the point feature/cpq branched from and absorbs it.
  clone="$TMP_ROOT/upstream-absorb"
  git clone "$TMP_ROOT/remotes/frontend.git" "$clone" >/dev/null 2>&1
  git -C "$clone" config user.name "Workbranch Test"
  git -C "$clone" config user.email "workbranch-test@example.com"
  git -C "$clone" merge --ff-only origin/feature/cpq >/dev/null 2>&1
  printf '%s\n' "after" > "$clone/after-cpq.txt"
  git -C "$clone" add after-cpq.txt
  git -C "$clone" commit -m "after cpq" >/dev/null
  git -C "$clone" push origin master >/dev/null 2>&1
  remote_master=$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse master)
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git feature/cpq
CONFIG
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  # A fast-forward creates no commit, so it must work without an identity.
  upstream_remove_git_identity "$project/_base/frontend"
  out=$(run_expect_success "$WORKBRANCH" upstream)
  assert_contains "$out" "Merged: frontend"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$remote_master" ] || fail "base was not fast-forwarded to origin/master"
}

test_upstream_on_default_branch_base_fast_forwards_like_pull() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_master frontend upstream-on-master
  remote_master=$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse master)

  out=$(run_expect_success "$WORKBRANCH" upstream)
  assert_contains "$out" "Merging frontend: origin/master -> master"
  assert_contains "$out" "Merged: frontend"
  assert_contains "$out" "Already up to date: backend"
  assert_not_contains "$out" "Skipping"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$remote_master" ] || fail "master base was not fast-forwarded to origin/master"
  assert_file "$project/_base/frontend/upstream-on-master.txt"
}

test_upstream_on_default_branch_base_merges_where_pull_stops() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  base="$project/_base/frontend"
  git -C "$base" config user.name "Workbranch Test"
  git -C "$base" config user.email "workbranch-test@example.com"
  printf '%s\n' "local" > "$base/local-only.txt"
  git -C "$base" add local-only.txt
  git -C "$base" commit -m "local only" >/dev/null
  commit_to_remote_master frontend remote-only

  out=$(run_expect_fail "$WORKBRANCH" pull --repo frontend)
  assert_contains "$out" "cannot fast-forward pull"

  run_expect_success "$WORKBRANCH" upstream --repo frontend >/dev/null
  assert_file "$base/local-only.txt"
  assert_file "$base/remote-only.txt"
  run_expect_success "$WORKBRANCH" push --repo frontend >/dev/null
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" master local-only.txt local
}

test_upstream_preflight_requires_identity_only_for_a_merge_commit() {
  upstream_fixture || return 1
  # Without a usable identity anywhere, Git refuses to create the merge commit.
  upstream_remove_git_identity "$project/_base/frontend"
  commit_to_remote_master frontend upstream-needs-identity
  commit_to_remote_master backend upstream-backend-identity
  backend_before=$(git -C "$project/_base/backend" rev-parse HEAD)

  out=$(run_expect_fail "$WORKBRANCH" upstream)
  assert_contains "$out" "_base/frontend needs Git user.name and user.email to create the merge commit"
  assert_not_contains "$out" "without conflicts"
  [ "$(git -C "$project/_base/backend" rev-parse HEAD)" = "$backend_before" ] || fail "repo with an identity was merged despite a preflight failure"
}

test_upstream_preflight_blocks_conflict_without_touching_any_base() {
  upstream_fixture || return 1
  project_root=$(cd "$project" && pwd -P) || return 1
  printf '%s\n' "cpq change" > "$project/_base/frontend/README.md"
  git -C "$project/_base/frontend" commit -am "cpq edits readme" >/dev/null
  upstream_commit_file_to_remote frontend master README.md "master change"
  commit_to_remote_master backend upstream-clean-backend
  frontend_before=$(git -C "$project/_base/frontend" rev-parse HEAD)
  backend_before=$(git -C "$project/_base/backend" rev-parse HEAD)

  out=$(run_expect_fail "$WORKBRANCH" upstream)
  assert_contains "$out" "Cannot merge upstream: preflight failed"
  assert_contains "$out" "_base/frontend cannot merge origin/master without conflicts"
  assert_contains "$out" "Resolve manually:"
  assert_contains "$out" "git -C $project_root/_base/frontend merge origin/master"
  assert_contains "$out" "git -C $project_root/_base/frontend commit --no-edit"
  assert_not_contains "$out" "Merging"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$frontend_before" ] || fail "conflicting base changed"
  [ "$(git -C "$project/_base/backend" rev-parse HEAD)" = "$backend_before" ] || fail "clean repo was merged despite a preflight failure"
  assert_clean "$project/_base/frontend"
  assert_not_exists "$project/_base/frontend/.git/MERGE_HEAD"
  [ "$(git -C "$project/_base/frontend" worktree list | wc -l | tr -d ' ')" -eq 1 ] || fail "scratch worktree was left registered"

  # Following the printed guidance leaves a merge to conclude.
  git -C "$project/_base/frontend" merge origin/master >/dev/null 2>&1 && fail "expected the manual merge to conflict"
  out=$(run_expect_fail "$WORKBRANCH" upstream --repo frontend)
  assert_contains "$out" "_base/frontend merge in progress"
}

test_upstream_guidance_quotes_paths_with_spaces() {
  new_fixture
  commit_to_remote_branch frontend feature/cpq cpq-frontend
  project="$TMP_ROOT/full stack"
  mv "$FIXTURE_PROJECT" "$project"
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git feature/cpq
CONFIG
  cd "$project" || return 1
  project_root=$(pwd -P)
  run_expect_success "$WORKBRANCH" init >/dev/null
  base="$project/_base/frontend"
  git -C "$base" config user.name "Workbranch Test"
  git -C "$base" config user.email "workbranch-test@example.com"
  printf '%s\n' "cpq change" > "$base/README.md"
  git -C "$base" commit -am "cpq edits readme" >/dev/null
  upstream_commit_file_to_remote frontend master README.md "master change"

  out=$(run_expect_fail "$WORKBRANCH" upstream)
  assert_contains "$out" "git -C '$project_root/_base/frontend' merge origin/master"
  assert_contains "$out" "git -C '$project_root/_base/frontend' commit --no-edit"
}

test_upstream_preflight_blocks_unfinished_cherry_pick_before_any_merge() {
  upstream_fixture || return 1
  commit_to_remote_master frontend upstream-before-cherry-pick
  commit_to_remote_master backend upstream-cherry-pick
  # Re-picking HEAD stops on an empty commit: clean worktree, pick unfinished.
  git -C "$project/_base/backend" cherry-pick HEAD >/dev/null 2>&1 && fail "fixture: cherry-pick did not stop"
  assert_clean "$project/_base/backend"
  frontend_before=$(git -C "$project/_base/frontend" rev-parse HEAD)

  out=$(run_expect_fail "$WORKBRANCH" upstream)
  assert_contains "$out" "Cannot merge upstream: preflight failed"
  assert_contains "$out" "_base/backend cherry-pick in progress"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$frontend_before" ] || fail "another repo was merged before the cherry-pick was reported"
}

test_upstream_preflight_removes_scratch_worktree_when_hook_fails() {
  upstream_fixture || return 1
  base="$project/_base/frontend"
  commit_to_remote_master frontend upstream-hook-fails
  upstream_install_hook "$base" post-checkout 'exit 1'

  out=$(run_expect_fail "$WORKBRANCH" upstream --repo frontend)
  assert_contains "$out" "_base/frontend cannot prepare merge preflight"
  [ "$(git -C "$base" worktree list | wc -l | tr -d ' ')" -eq 1 ] || fail "scratch worktree was left registered: $(git -C "$base" worktree list)"
}

test_upstream_preflight_requires_base_to_contain_remote_base() {
  upstream_fixture || return 1
  commit_to_remote_branch frontend feature/cpq teammate-work
  commit_to_remote_master frontend upstream-after-pull
  before=$(git -C "$project/_base/frontend" rev-parse HEAD)

  out=$(run_expect_fail "$WORKBRANCH" upstream --repo frontend)
  assert_contains "$out" "Cannot merge upstream: preflight failed"
  assert_contains "$out" "_base/frontend is behind origin/feature/cpq; run workbranch pull --repo frontend first"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$before" ] || fail "base changed while behind its remote"

  run_expect_success "$WORKBRANCH" pull --repo frontend >/dev/null
  run_expect_success "$WORKBRANCH" upstream --repo frontend >/dev/null
  assert_file "$project/_base/frontend/teammate-work.txt"
  assert_file "$project/_base/frontend/upstream-after-pull.txt"
}

test_upstream_preflight_blocks_dirty_base_and_missing_ref() {
  upstream_fixture || return 1
  commit_to_remote_master frontend upstream-blocked
  before=$(git -C "$project/_base/frontend" rev-parse HEAD)

  out=$(run_expect_fail "$WORKBRANCH" upstream --from no-such-branch)
  assert_contains "$out" "_base/frontend missing source ref: no-such-branch"
  assert_contains "$out" "_base/backend missing source ref: no-such-branch"

  printf '%s\n' "dirty" > "$project/_base/frontend/dirty.txt"
  out=$(run_expect_fail "$WORKBRANCH" upstream)
  assert_contains "$out" "_base/frontend dirty worktree"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$before" ] || fail "dirty base was merged"
  assert_not_exists "$project/_base/frontend/upstream-blocked.txt"
}

test_upstream_preflight_protects_ignored_files_in_base() {
  upstream_fixture || return 1
  base="$project/_base/frontend"
  printf 'local.env\n' >> "$base/.git/info/exclude"
  printf 'MY SECRET\n' > "$base/local.env"
  assert_clean "$base"
  upstream_commit_file_to_remote frontend master local.env "TRACKED"
  before=$(git -C "$base" rev-parse HEAD)

  out=$(run_expect_fail "$WORKBRANCH" upstream --repo frontend)
  assert_contains "$out" "_base/frontend has local files that origin/master would overwrite"
  assert_contains "$out" "  local.env"
  [ "$(cat "$base/local.env")" = "MY SECRET" ] || fail "ignored file overwritten by upstream"
  [ "$(git -C "$base" rev-parse HEAD)" = "$before" ] || fail "base changed after overwrite preflight"
}

test_upstream_preflight_protects_ignored_file_at_parent_path() {
  upstream_fixture || return 1
  base="$project/_base/frontend"
  printf 'build\n' >> "$base/.git/info/exclude"
  printf 'MY SECRET\n' > "$base/build"
  assert_clean "$base"
  # The merge needs build/ as a directory; build/x.c itself does not exist yet.
  upstream_commit_file_to_remote frontend master build/x.c "TRACKED"
  upstream_commit_file_to_remote frontend master build/y.c "TRACKED"
  before=$(git -C "$base" rev-parse HEAD)

  out=$(run_expect_fail "$WORKBRANCH" upstream --repo frontend)
  assert_contains "$out" "_base/frontend has local files that origin/master would overwrite"
  assert_contains "$out" "  build"
  assert_not_contains "$out" "build/x.c"
  [ "$(printf '%s\n' "$out" | grep -c '^ *build$')" -eq 1 ] || fail "parent path reported more than once: $out"
  [ "$(cat "$base/build")" = "MY SECRET" ] || fail "ignored file replaced by a directory"
  [ "$(git -C "$base" rev-parse HEAD)" = "$before" ] || fail "base changed after overwrite preflight"
}

test_upstream_preflight_separates_tracked_directory_from_local_files_in_it() {
  upstream_fixture || return 1
  base="$project/_base/frontend"
  upstream_commit_file_to_remote frontend master docs/README "readme"
  run_expect_success "$WORKBRANCH" upstream --repo frontend >/dev/null
  assert_file "$base/docs/README"

  # master replaces the docs/ directory with a file named docs.
  clone="$TMP_ROOT/upstream-dir-to-file"
  git clone "$TMP_ROOT/remotes/frontend.git" "$clone" >/dev/null 2>&1
  git -C "$clone" config user.name "Workbranch Test"
  git -C "$clone" config user.email "workbranch-test@example.com"
  git -C "$clone" rm -rq docs
  printf '%s\n' "now a file" > "$clone/docs"
  git -C "$clone" add docs
  git -C "$clone" commit -m "docs becomes a file" >/dev/null
  git -C "$clone" push origin master >/dev/null 2>&1

  # An ignored file inside the directory would go with it.
  printf '*.log\n' >> "$base/.git/info/exclude"
  printf 'MY NOTES\n' > "$base/docs/local.log"
  assert_clean "$base"
  out=$(run_expect_fail "$WORKBRANCH" upstream --repo frontend)
  assert_contains "$out" "_base/frontend has local files that origin/master would overwrite"
  assert_contains "$out" "  docs"
  [ "$(cat "$base/docs/local.log")" = "MY NOTES" ] || fail "ignored file under the replaced directory was lost"

  # With only tracked files in it, the directory is Git's to replace.
  rm "$base/docs/local.log"
  out=$(run_expect_success "$WORKBRANCH" upstream --repo frontend)
  assert_contains "$out" "Merged: frontend"
  [ -f "$base/docs" ] || fail "docs was not replaced by the file from master"
}

test_upstream_does_not_fall_back_when_origin_cannot_be_asked() {
  upstream_fixture || return 1
  base="$project/_base/frontend"
  commit_to_remote_master frontend upstream-unreachable
  git -C "$base" fetch origin >/dev/null 2>&1
  # fetch still works; only the HEAD query fails.
  before=$(git -C "$base" rev-parse HEAD)
  wrapper="$TMP_ROOT/git-wrapper"
  mkdir -p "$wrapper"
  real_git=$(command -v git)
  cat > "$wrapper/git" <<SCRIPT
#!/usr/bin/env bash
for arg in "\$@"; do [ "\$arg" != ls-remote ] || exit 128; done
exec "$real_git" "\$@"
SCRIPT
  chmod +x "$wrapper/git"

  out=$(PATH="$wrapper:$PATH" run_expect_fail "$WORKBRANCH" upstream --repo frontend)
  assert_contains "$out" "_base/frontend cannot detect origin's default branch; pass --from <ref>"
  [ "$(git -C "$base" rev-parse HEAD)" = "$before" ] || fail "merged the cached default branch after a failed query"
}

test_upstream_stops_when_a_base_changes_after_preflight() {
  upstream_fixture || return 1
  commit_to_remote_master frontend upstream-race-frontend
  commit_to_remote_master backend upstream-race-backend
  backend="$project/_base/backend"
  # Merging frontend runs its post-merge hook, which stands in for another
  # process committing to the backend base after preflight checked it.
  upstream_install_hook "$project/_base/frontend" post-merge "git -C '$backend' commit --allow-empty -qm moved"
  moved_from=$(git -C "$backend" rev-parse HEAD)

  out=$(run_expect_fail "$WORKBRANCH" upstream)
  assert_contains "$out" "Merged: frontend"
  assert_contains "$out" "base repo 'backend' changed after preflight; rerun workbranch upstream"
  [ "$(git -C "$backend" rev-parse HEAD^)" = "$moved_from" ] || fail "fixture: hook did not move backend"
  assert_not_exists "$backend/upstream-race-backend.txt"
}

test_upstream_detects_default_branch_without_origin_head() {
  upstream_fixture || return 1
  # Newer Git recreates a missing origin/HEAD on fetch; keep it absent so only
  # the remote can name the default branch.
  git -C "$project/_base/frontend" config remote.origin.followRemoteHEAD never
  git -C "$project/_base/frontend" remote set-head origin -d >/dev/null 2>&1
  commit_to_remote_master frontend upstream-no-head

  out=$(run_expect_success "$WORKBRANCH" upstream --repo frontend)
  assert_contains "$out" "Merging frontend: origin/master -> feature/cpq"
  assert_file "$project/_base/frontend/upstream-no-head.txt"
  if git -C "$project/_base/frontend" symbolic-ref --quiet refs/remotes/origin/HEAD >/dev/null 2>&1; then
    fail "origin/HEAD came back, so the remote lookup was not exercised"
  fi
}

test_upstream_follows_default_branch_change_on_origin() {
  upstream_fixture || return 1
  # origin switches its default to main and keeps master; the clone's cached
  # origin/HEAD still says master.
  commit_to_remote_branch frontend main on-main
  git --git-dir="$TMP_ROOT/remotes/frontend.git" symbolic-ref HEAD refs/heads/main
  commit_to_remote_master frontend on-old-master
  [ "$(git -C "$project/_base/frontend" symbolic-ref refs/remotes/origin/HEAD)" = "refs/remotes/origin/master" ] || fail "fixture: cached origin/HEAD is not stale"

  out=$(run_expect_success "$WORKBRANCH" upstream --repo frontend)
  assert_contains "$out" "Merging frontend: origin/main -> feature/cpq"
  assert_file "$project/_base/frontend/on-main.txt"
  assert_not_exists "$project/_base/frontend/on-old-master.txt"
}

test_upstream_uses_cached_origin_head_when_origin_reports_none() {
  upstream_fixture || return 1
  commit_to_remote_master frontend upstream-detached-remote
  # A remote whose HEAD is detached names no default branch.
  git --git-dir="$TMP_ROOT/remotes/frontend.git" update-ref --no-deref HEAD "$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse master)"

  out=$(run_expect_success "$WORKBRANCH" upstream --repo frontend)
  assert_contains "$out" "Merging frontend: origin/master -> feature/cpq"
  assert_file "$project/_base/frontend/upstream-detached-remote.txt"
}

test_upstream_prefers_remote_tracking_branch_over_same_named_tag() {
  upstream_fixture || return 1
  base="$project/_base/frontend"
  commit_to_remote_master frontend upstream-not-the-tag
  # A tag called origin/master wins Git's lookup of the short name.
  git -C "$base" tag origin/master HEAD
  git -C "$base" tag origin/develop HEAD
  commit_to_remote_branch frontend develop upstream-develop-branch

  out=$(run_expect_success "$WORKBRANCH" upstream --repo frontend)
  assert_contains "$out" "Merged: frontend"
  assert_file "$base/upstream-not-the-tag.txt"

  run_expect_success "$WORKBRANCH" upstream --repo frontend --from origin/develop >/dev/null
  assert_file "$base/upstream-develop-branch.txt"
}

test_upstream_from_accepts_worktree_relative_and_full_ref_names() {
  upstream_fixture || return 1
  base="$project/_base/frontend"
  commit_to_remote_master frontend upstream-via-tracking
  git -C "$base" fetch origin >/dev/null 2>&1
  git -C "$base" branch --set-upstream-to=origin/master >/dev/null 2>&1

  # @{upstream} only resolves on the base branch, not in a detached replay.
  out=$(run_expect_success "$WORKBRANCH" upstream --repo frontend --from '@{upstream}')
  assert_contains "$out" "Merging frontend: @{upstream} -> feature/cpq"
  assert_contains "$out" "Merged: frontend"
  assert_file "$base/upstream-via-tracking.txt"
}

test_upstream_treats_full_remote_base_ref_like_its_short_name() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_master frontend upstream-full-ref
  remote_master=$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse master)

  # The base is behind origin/master, and origin/master is what gets merged.
  out=$(run_expect_success "$WORKBRANCH" upstream --repo frontend --from refs/remotes/origin/master)
  assert_contains "$out" "Merging frontend: origin/master -> master"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$remote_master" ] || fail "master base was not fast-forwarded"
}

test_upstream_merges_the_commit_preflight_checked() {
  upstream_fixture || return 1
  base="$project/_base/frontend"
  commit_to_remote_master frontend upstream-checked
  checked=$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse master)
  commit_to_remote_branch frontend later upstream-arrived-later
  git -C "$base" fetch origin >/dev/null 2>&1
  # Stand in for a fetch that lands between preflight and the merge: preflight
  # creates a scratch worktree, which runs this hook.
  upstream_install_hook "$base" post-checkout 'git update-ref refs/remotes/origin/master refs/remotes/origin/later'

  out=$(run_expect_success "$WORKBRANCH" upstream --repo frontend)
  assert_contains "$out" "Merged: frontend"
  [ "$(git -C "$base" rev-parse refs/remotes/origin/master)" != "$checked" ] || fail "fixture: the hook did not move origin/master"
  [ "$(git -C "$base" rev-parse HEAD^2)" = "$checked" ] || fail "merged a commit preflight did not check"
  assert_file "$base/upstream-checked.txt"
  assert_not_exists "$base/upstream-arrived-later.txt"
}

test_upstream_commits_the_merge_despite_branch_merge_options() {
  upstream_fixture || return 1
  base="$project/_base/frontend"
  git -C "$base" config branch.feature/cpq.mergeOptions "--no-commit"
  commit_to_remote_master frontend upstream-merge-options
  remote_master=$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse master)

  out=$(run_expect_success "$WORKBRANCH" upstream --repo frontend)
  assert_contains "$out" "Merged: frontend"
  [ "$(git -C "$base" rev-parse HEAD^2)" = "$remote_master" ] || fail "base did not advance to a merge commit"
  assert_not_exists "$base/.git/MERGE_HEAD"
  assert_clean "$base"
}

test_upstream_rejects_unexpected_arguments() {
  upstream_fixture || return 1

  out=$(run_expect_fail "$WORKBRANCH" upstream master)
  assert_contains "$out" "usage: workbranch upstream [--from <ref>] [--repo <repo>]"
  out=$(run_expect_fail "$WORKBRANCH" upstream --from)
  assert_contains "$out" "missing value for --from"
  out=$(run_expect_fail "$WORKBRANCH" upstream --from=)
  assert_contains "$out" "missing value for --from"
}
