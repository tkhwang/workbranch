cmd_remove() {
  [ $# -eq 1 ] || die "usage: workbranch remove <task>"
  task=$1
  validate_safe_name "task" "$task"
  require_project
  require_task_repos_clean "$task"
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    path=$(task_repo_path "$task" "$name")
    if [ ! -d "$path" ]; then
      info "Worktree already removed: $task/$name"
      i=$((i + 1))
      continue
    fi
    base=$(base_repo_path "$name")
    git -C "$base" worktree remove "$path" || info "failed to remove worktree (continuing): $task/$name"
    i=$((i + 1))
  done
  if rmdir "$PROJECT_ROOT/$task" 2>/dev/null; then
    :
  elif [ -d "$PROJECT_ROOT/$task" ]; then
    info "Task directory kept because it is not empty: $task"
  fi
}
