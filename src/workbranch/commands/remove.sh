cmd_remove() {
  [ $# -eq 1 ] || [ $# -eq 2 ] || die "usage: workbranch remove <task> [--force]"
  task=$1
  force=0
  if [ $# -eq 2 ]; then
    [ "$2" = "--force" ] || die "usage: workbranch remove <task> [--force]"
    force=1
  fi
  validate_safe_name "task" "$task"
  require_project
  reset_preflight
  task_dir="$PROJECT_ROOT/$task"
  if is_stale_task_directory_path "$task_dir"; then
    preflight_stale_task_directory_removal "$task" "$force"
    preflight_die_if_errors "remove"
    remove_stale_task_directory_path "$task_dir" "$force" || die "failed to remove stale task directory: $task"
    return 0
  fi
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    path=$(task_repo_path "$task" "$name")
    branch=$(repo_task_branch_at "$i" "$task")
    base=$(base_repo_path "$name")
    label="$task/$name"
    if [ -d "$path/.git" ] || [ -f "$path/.git" ]; then
      preflight_require_current_branch "$label" "$path" "$branch"
      if [ "$force" -ne 1 ]; then
        preflight_require_clean "$label" "$path"
      fi
    fi
    if [ "$force" -ne 1 ]; then
      preflight_require_task_branch_safe_to_delete "$label" "$base" "$branch" "$task"
    fi
    i=$((i + 1))
  done
  preflight_die_if_errors "remove"

  had_failure=0
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    path=$(task_repo_path "$task" "$name")
    branch=$(repo_task_branch_at "$i" "$task")
    base=$(base_repo_path "$name")
    if [ ! -d "$path" ]; then
      info "Worktree already removed: $task/$name"
      if workbranch_git_delete_task_branch "$base" "$branch" "$force"; then
        success "Removed: $task/$name"
      else
        printf '[-] Error: failed to delete task branch (continuing): %s/%s %s\n' "$task" "$name" "$branch" >&2
        had_failure=1
      fi
    else
      if [ "$force" -eq 1 ]; then
        git -C "$base" worktree remove --force "$path"
        remove_status=$?
      else
        git -C "$base" worktree remove "$path"
        remove_status=$?
      fi
      if [ "$remove_status" -eq 0 ]; then
        if workbranch_git_delete_task_branch "$base" "$branch" "$force"; then
          success "Removed: $task/$name"
        else
          printf '[-] Error: failed to delete task branch (continuing): %s/%s %s\n' "$task" "$name" "$branch" >&2
          had_failure=1
        fi
      else
        printf '[-] Error: failed to remove worktree (continuing): %s/%s\n' "$task" "$name" >&2
        had_failure=1
      fi
    fi
    i=$((i + 1))
  done
  metadata_file=$(task_metadata_file "$task")
  if [ -f "$metadata_file" ]; then
    rm -f "$metadata_file" || die "failed to remove task metadata: $metadata_file"
  fi
  if rmdir "$PROJECT_ROOT/$task" 2>/dev/null; then
    :
  elif [ -d "$PROJECT_ROOT/$task" ]; then
    info "Task directory kept because it is not empty: $task"
  fi
  [ "$had_failure" -eq 0 ] || return 1
}
