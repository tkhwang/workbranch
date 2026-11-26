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
  printf '%s\n' "$content" > "$clone/$file"
  git -C "$clone" add -f "$file"
  git -C "$clone" commit -m "$branch edits $file" >/dev/null
  git -C "$clone" push origin "$branch" >/dev/null 2>&1
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

  # No committer identity is configured for this base: a fast-forward needs none.
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
  git -C "$project/_base/frontend" config --unset user.name
  git -C "$project/_base/frontend" config --unset user.email
  # Without a usable identity anywhere, Git refuses to create the merge commit.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  git -C "$project/_base/frontend" config user.useConfigOnly true
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

test_upstream_detects_default_branch_without_origin_head() {
  upstream_fixture || return 1
  git -C "$project/_base/frontend" remote set-head origin -d >/dev/null 2>&1
  commit_to_remote_master frontend upstream-no-head

  out=$(run_expect_success "$WORKBRANCH" upstream --repo frontend)
  assert_contains "$out" "Merging frontend: origin/master -> feature/cpq"
  assert_file "$project/_base/frontend/upstream-no-head.txt"
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
