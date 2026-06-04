resume_needs_branch_prompt() {
  task=$1
  stale=$2
  task_dir_exists=$3
  [ "$stale" -eq 1 ] && return 0
  [ "$task_dir_exists" -eq 0 ] && return 0
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    target=$(task_repo_path "$task" "$name")
    if [ ! -d "$target/.git" ] && [ ! -f "$target/.git" ]; then
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

prompt_task_branches_for_resume() {
  task=$1
  load_task_metadata "$task"
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    current=$(metadata_task_branch_for_repo "$name" || true)
    if [ -z "$current" ]; then
      current=$(default_repo_task_branch_at "$i" "$task")
    fi
    branch=$(prompt_with_default "Task branch for $name" "$current")
    validate_branch_name "task branch" "$branch"
    set_task_metadata_branch "$name" "$branch"
    i=$((i + 1))
  done
}

cmd_resume() {
  [ $# -eq 1 ] || die "usage: workbranch resume <task>"
  task=$1
  validate_safe_name "task" "$task"
  require_project
  CREATED_PATHS=()
  CREATED_WORKTREES=()
  CREATED_WORKTREE_BASES=()
  CREATED_BRANCH_REPOS=()
  CREATED_BRANCH_NAMES=()
  task_dir="$PROJECT_ROOT/$task"
  task_dir_exists=0
  if [ -e "$task_dir" ] || [ -L "$task_dir" ]; then
    [ -d "$task_dir" ] || die "task path exists but is not a directory: $task_dir"
    task_dir_exists=1
  fi

  reset_preflight
  stale_task_dir=0
  if is_stale_task_directory_path "$task_dir"; then
    stale_task_dir=1
  fi
  prompted_task_branches=0
  if resume_needs_branch_prompt "$task" "$stale_task_dir" "$task_dir_exists"; then
    prompt_task_branches_for_resume "$task"
    prompted_task_branches=1
  else
    load_task_metadata "$task"
  fi
  if [ "$stale_task_dir" -eq 1 ]; then
    preflight_stale_task_directory_removal "$task" 0
  fi
  found_task_branch=0
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base=$(base_repo_path "$name")
    base_branch=$(repo_base_branch_at "$i")
    branch=$(metadata_task_branch_for_repo "$name") || branch=$(repo_task_branch_at "$i" "$task")
    base_label="$BASE_DIR/$name"
    target=$(task_repo_path "$task" "$name")
    label="$task/$name"
    if [ ! -d "$base/.git" ] && [ ! -f "$base/.git" ]; then
      preflight_error "$base_label missing git repo"
      i=$((i + 1))
      continue
    fi
    if [ "$stale_task_dir" -eq 0 ] && { [ -e "$target" ] || [ -L "$target" ]; }; then
      if [ -d "$target/.git" ] || [ -f "$target/.git" ]; then
        preflight_require_current_branch "$label" "$target" "$branch"
        preflight_require_no_rebase "$label" "$target"
      else
        preflight_error "$label path exists but is not a git repo"
      fi
    fi
    preflight_require_current_branch "$base_label" "$base" "$base_branch"
    preflight_require_clean "$base_label" "$base"
    preflight_require_no_rebase "$base_label" "$base"
    if branch_exists "$base" "$branch"; then
      found_task_branch=1
    else
      git -C "$base" fetch origin >/dev/null 2>&1 || true
      if git_ref_exists "$base" "origin/$branch"; then
        found_task_branch=1
      fi
    fi
    i=$((i + 1))
  done
  if [ "$found_task_branch" -ne 1 ] && [ "$stale_task_dir" -ne 1 ]; then
    preflight_error "no local or remote task branch found for $task"
  fi
  preflight_die_if_errors "resume"

  if [ "$stale_task_dir" -eq 1 ]; then
    remove_stale_task_directory_path "$task_dir" 0 || fail_with_rollback "failed to remove stale task directory: $task"
    task_dir_exists=0
  fi

  if [ "$task_dir_exists" -eq 0 ]; then
    mkdir -p "$task_dir" || die "failed to create task directory: $task_dir"
    track_path "$task_dir"
  fi
  if [ "$prompted_task_branches" -eq 1 ]; then
    write_task_metadata "$task"
  fi

  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base=$(base_repo_path "$name")
    base_branch=$(repo_base_branch_at "$i")
    branch=$(metadata_task_branch_for_repo "$name") || branch=$(repo_task_branch_at "$i" "$task")
    target=$(task_repo_path "$task" "$name")
    if [ -d "$target/.git" ] || [ -f "$target/.git" ]; then
      info "Worktree already exists: $task/$name"
    elif branch_exists "$base" "$branch"; then
      track_worktree "$target" "$base"
      workbranch_git_add_existing_task_worktree "$base" "$target" "$branch" || fail_with_rollback "failed to create worktree for repo '$name'"
    elif git_ref_exists "$base" "origin/$branch"; then
      track_branch "$base" "$branch"
      workbranch_git_create_task_branch_from_remote "$base" "$branch" || fail_with_rollback "failed to create task branch for repo '$name'"
      track_worktree "$target" "$base"
      workbranch_git_add_existing_task_worktree "$base" "$target" "$branch" || fail_with_rollback "failed to create worktree for repo '$name'"
    else
      track_branch "$base" "$branch"
      track_worktree "$target" "$base"
      workbranch_git_add_new_task_worktree "$base" "$target" "$branch" || fail_with_rollback "failed to create worktree for repo '$name'"
    fi
    success "Resumed: $task/$name"
    success "  [base repo] $base_branch -> [task repo] $branch"
    i=$((i + 1))
  done
  if has_task_setups && ! run_task_setups "$task"; then
    printf '[-] Error: task setup failed\n' >&2
    printf '[*] Worktrees were created. Fix setup with:\n' >&2
    printf '    workbranch config\n' >&2
    printf '[*] Then rerun the setup command shown above, or remove and resume the task again.\n' >&2
    return 1
  fi
}
