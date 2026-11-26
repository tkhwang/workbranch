# -----------------------------------------------------------------------------
# Git operation definitions
# -----------------------------------------------------------------------------
# These helpers define the Git commands documented in docs/git-operations.md.

workbranch_git_add_fetch_base() {
  base_path=$1
  git -C "$base_path" fetch origin >/dev/null 2>&1
}

workbranch_git_prune_stale_worktrees() {
  base_path=$1
  git -C "$base_path" worktree prune >/dev/null 2>&1
}

workbranch_git_add_existing_task_worktree() {
  base_path=$1
  target_path=$2
  task_branch=$3
  workbranch_git_prune_stale_worktrees "$base_path" || return 1
  git -C "$base_path" worktree add "$target_path" "$task_branch" >/dev/null 2>&1
}

workbranch_git_add_new_task_worktree() {
  base_path=$1
  target_path=$2
  task_branch=$3
  source_ref=${4:-HEAD}
  workbranch_git_prune_stale_worktrees "$base_path" || return 1
  git -C "$base_path" worktree add "$target_path" -b "$task_branch" "$source_ref" >/dev/null 2>&1 || return 1
  if [ "$source_ref" != "HEAD" ]; then
    git -C "$target_path" branch --unset-upstream >/dev/null 2>&1 || true
  fi
}

workbranch_git_delete_task_branch() {
  base_path=$1
  task_branch=$2
  force=${3:-0}
  workbranch_git_prune_stale_worktrees "$base_path" || return 1
  branch_exists "$base_path" "$task_branch" || return 0
  if [ "$force" -eq 1 ]; then
    git -C "$base_path" branch -D "$task_branch" >/dev/null 2>&1
  else
    git -C "$base_path" branch -d "$task_branch" >/dev/null 2>&1
  fi
}

# Names the remote-tracking ref in full: a tag or branch called origin/<branch>
# would otherwise win the lookup. Fails if Git cannot set up the upstream.
workbranch_git_create_task_branch_from_remote() {
  base_path=$1
  task_branch=$2
  workbranch_git_prune_stale_worktrees "$base_path" || return 1
  git -C "$base_path" branch --track "$task_branch" "refs/remotes/origin/$task_branch" >/dev/null 2>&1
}

workbranch_git_create_task_branch_from_base() {
  base_path=$1
  task_branch=$2
  workbranch_git_prune_stale_worktrees "$base_path" || return 1
  git -C "$base_path" branch --no-track "$task_branch" HEAD >/dev/null 2>&1
}

# Asks origin itself, because a remote-tracking ref outlives a branch deleted on
# origin until someone prunes it. Returns 0 when origin has the branch, 1 when it
# does not, and 2 when origin could not be asked.
workbranch_git_remote_branch_state() {
  local remote_refs remote_ref tab
  base_path=$1
  task_branch=$2
  tab=$(printf '\t')
  remote_refs=$(git -C "$base_path" ls-remote --heads origin "refs/heads/$task_branch" 2>/dev/null) || return 2
  # ls-remote matches the pattern against the tail of a ref, so
  # refs/heads/x/refs/heads/<branch> would match too; compare the full name.
  while IFS= read -r remote_ref || [ -n "$remote_ref" ]; do
    [ "${remote_ref#*"$tab"}" = "refs/heads/$task_branch" ] && return 0
  done <<EOF_REMOTE_REFS
$remote_refs
EOF_REMOTE_REFS
  return 1
}

workbranch_git_pull_base() {
  repo_name=$1
  base_path=$2
  base_branch=$3
  git -C "$base_path" pull --ff-only origin "$base_branch" || die "failed to pull repo '$repo_name'"
}

# Merges the commit preflight replayed rather than the ref name, which a fetch
# could have moved since. Options that merge.ff or branch.<name>.mergeOptions
# can preset are spelled out, so success always means the base advanced.
# --no-overwrite-ignore backs up the preflight scan; Git honors it only when
# fast-forwarding.
workbranch_git_merge_upstream() {
  repo_name=$1
  base_path=$2
  source_commit=$3
  source_name=$4
  merge_message=$5
  git -C "$base_path" merge --ff --commit --no-squash --no-overwrite-ignore --no-edit -m "$merge_message" "$source_commit" ||
    die "failed to merge $source_name in repo '$repo_name'; if the merge stopped midway, resolve it in $base_path and commit, or run: git -C $(shell_quote "$base_path") merge --abort"
}

workbranch_git_checkout_base_branch() {
  repo_name=$1
  base_path=$2
  base_branch=$3
  if branch_exists "$base_path" "$base_branch"; then
    git -C "$base_path" checkout "$base_branch" >/dev/null 2>&1 || die "failed to checkout base branch for repo '$repo_name': $base_branch"
  else
    git -C "$base_path" checkout -b "$base_branch" "origin/$base_branch" >/dev/null 2>&1 || die "failed to checkout base branch for repo '$repo_name': $base_branch"
  fi
}

workbranch_git_rebase_task() {
  git -C "$1" rebase "$2"
}

workbranch_git_update_task() {
  task_path=$1
  local_base_head=$2
  workbranch_git_rebase_task "$task_path" "$local_base_head" || die "update failed in $task_path; resolve conflicts manually"
}

workbranch_git_push_base() {
  repo_name=$1
  base_path=$2
  base_branch=$3
  git -C "$base_path" push origin "$base_branch" || die "failed to push base branch for repo '$repo_name': $base_branch"
}

workbranch_git_push_task() {
  repo_name=$1
  task_path=$2
  task_branch=$3
  git -C "$task_path" push -u origin "$task_branch" || die "failed to push repo '$repo_name'"
}

workbranch_git_land_checkout_base() {
  repo_name=$1
  base_path=$2
  base_branch=$3
  git -C "$base_path" checkout "$base_branch" >/dev/null 2>&1 || die "failed to checkout base branch for repo '$repo_name': $base_branch"
}

workbranch_git_land_pull_base() {
  repo_name=$1
  base_path=$2
  base_branch=$3
  git -C "$base_path" pull --ff-only origin "$base_branch" || die "failed to update base branch for repo '$repo_name': $base_branch"
}

workbranch_git_land_task() {
  repo_name=$1
  base_path=$2
  task_branch=$3
  task=$4
  git -C "$base_path" merge --ff-only "$task_branch" || die "failed to land repo '$repo_name'; run workbranch update $task and resolve conflicts first"
}
