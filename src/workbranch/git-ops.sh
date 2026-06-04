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
  workbranch_git_prune_stale_worktrees "$base_path" || return 1
  git -C "$base_path" worktree add "$target_path" -b "$task_branch" HEAD >/dev/null 2>&1
}

workbranch_git_delete_task_branch() {
  base_path=$1
  task_branch=$2
  workbranch_git_prune_stale_worktrees "$base_path" || return 1
  branch_exists "$base_path" "$task_branch" || return 0
  git -C "$base_path" branch -D "$task_branch" >/dev/null 2>&1
}

workbranch_git_create_task_branch_from_remote() {
  base_path=$1
  task_branch=$2
  git -C "$base_path" branch --track "$task_branch" "origin/$task_branch" >/dev/null 2>&1 ||
    git -C "$base_path" branch "$task_branch" "origin/$task_branch" >/dev/null 2>&1
}

workbranch_git_pull_base() {
  repo_name=$1
  base_path=$2
  base_branch=$3
  git -C "$base_path" pull --ff-only origin "$base_branch" || die "failed to pull repo '$repo_name'"
}

workbranch_git_update_task() {
  task_path=$1
  local_base_head=$2
  git -C "$task_path" rebase "$local_base_head" || die "update failed in $task_path; resolve conflicts manually"
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
