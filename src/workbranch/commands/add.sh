cmd_add() {
  [ $# -eq 1 ] || die "usage: workbranch add <task>"
  task=$1
  validate_safe_name "task" "$task"
  require_project
  CREATED_PATHS=()
  CREATED_WORKTREES=()
  CREATED_WORKTREE_BASES=()
  CREATED_BRANCH_REPOS=()
  CREATED_BRANCH_NAMES=()
  task_dir="$PROJECT_ROOT/$task"
  [ ! -e "$task_dir" ] || die "task directory already exists: $task_dir"

  reset_preflight
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base=$(base_repo_path "$name")
    base_branch=$(repo_base_branch_at "$i")
    base_label="$BASE_DIR/$name"
    if [ ! -d "$base/.git" ] && [ ! -f "$base/.git" ]; then
      preflight_error "$base_label missing git repo"
      i=$((i + 1))
      continue
    fi
    preflight_require_current_branch "$base_label" "$base" "$base_branch"
    preflight_require_clean "$base_label" "$base"
    preflight_require_no_rebase "$base_label" "$base"
    i=$((i + 1))
  done
  preflight_die_if_errors "add"

  mkdir -p "$task_dir" || die "failed to create task directory: $task_dir"
  track_path "$task_dir"

  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base=$(base_repo_path "$name")
    base_branch=$(repo_base_branch_at "$i")
    branch=$(repo_task_branch_at "$i" "$task")
    target=$(task_repo_path "$task" "$name")
    if branch_exists "$base" "$branch"; then
      track_worktree "$target" "$base"
      workbranch_git_add_existing_task_worktree "$base" "$target" "$branch" || fail_with_rollback "failed to create worktree for repo '$name'"
    else
      track_branch "$base" "$branch"
      track_worktree "$target" "$base"
      workbranch_git_add_fetch_base "$base" || fail_with_rollback "failed to fetch repo '$name'"
      workbranch_git_add_new_task_worktree "$base" "$target" "$branch" || fail_with_rollback "failed to create worktree for repo '$name'"
    fi
    success "Created: $task/$name"
    success "  [base repo] $base_branch -> [task repo] $branch"
    i=$((i + 1))
  done
  if has_task_setups; then
    if run_task_setups "$task"; then
      :
    else
      printf '[-] Error: task setup failed\n' >&2
      printf '[*] Worktrees were created. Fix setup with:\n' >&2
      printf '    workbranch config\n' >&2
      printf '[*] Then rerun the setup command shown above, or remove and add the task again.\n' >&2
      return 1
    fi
  fi
}
