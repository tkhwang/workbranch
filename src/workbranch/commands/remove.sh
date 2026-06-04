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
  [ "$force" -eq 1 ] || require_task_repos_clean "$task"
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    path=$(task_repo_path "$task" "$name")
    branch=$(repo_task_branch_at "$i" "$task")
    base=$(base_repo_path "$name")
    if [ ! -d "$path" ]; then
      info "Worktree already removed: $task/$name"
      workbranch_git_delete_task_branch "$base" "$branch" || die "failed to delete task branch for repo '$name': $branch"
      success "Removed: $task/$name"
    else
      if [ "$force" -eq 1 ]; then
        git -C "$base" worktree remove --force "$path"
        remove_status=$?
      else
        git -C "$base" worktree remove "$path"
        remove_status=$?
      fi
      if [ "$remove_status" -eq 0 ]; then
        workbranch_git_delete_task_branch "$base" "$branch" || die "failed to delete task branch for repo '$name': $branch"
        success "Removed: $task/$name"
      else
        info "failed to remove worktree (continuing): $task/$name"
      fi
    fi
    i=$((i + 1))
  done
  if rmdir "$PROJECT_ROOT/$task" 2>/dev/null; then
    :
  elif [ -d "$PROJECT_ROOT/$task" ]; then
    info "Task directory kept because it is not empty: $task"
  fi
}
