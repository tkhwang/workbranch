prune_skip_reason() {
  printf '%s' "$1"
}

prune_task_is_fully_merged() {
  local task i name base task_path base_branch branch label base_label
  task=$1
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base=$(base_repo_path "$name")
    task_path=$(task_repo_path "$task" "$name")
    base_branch=$(repo_base_branch_at "$i")
    branch=$(repo_task_branch_at "$i" "$task")
    label="$task/$name"
    base_label="$BASE_DIR/$name"

    if [ ! -d "$base/.git" ] && [ ! -f "$base/.git" ]; then
      prune_skip_reason "$base_label missing git repo"
      return 1
    fi
    if [ "$(branch_or_unknown "$base")" != "$base_branch" ]; then
      prune_skip_reason "$base_label expected branch $base_branch, got $(branch_or_unknown "$base")"
      return 1
    fi
    if is_rebase_in_progress "$base"; then
      prune_skip_reason "$base_label rebase in progress"
      return 1
    fi
    if [ ! -d "$task_path/.git" ] && [ ! -f "$task_path/.git" ]; then
      prune_skip_reason "$label missing git repo"
      return 1
    fi
    if [ "$(branch_or_unknown "$task_path")" != "$branch" ]; then
      prune_skip_reason "$label expected branch $branch, got $(branch_or_unknown "$task_path")"
      return 1
    fi
    if is_git_dirty "$task_path"; then
      prune_skip_reason "$label dirty worktree"
      return 1
    fi
    if is_rebase_in_progress "$task_path"; then
      prune_skip_reason "$label rebase in progress"
      return 1
    fi
    if ! branch_exists "$base" "$branch"; then
      prune_skip_reason "$label missing task branch $branch"
      return 1
    fi
    if ! git_is_ancestor "$base" "$branch" "$base_branch"; then
      prune_skip_reason "$label not merged into $base_branch"
      return 1
    fi
    i=$((i + 1))
  done
  return 0
}

collect_prune_tasks() {
  local path task reason
  tasks_to_prune=()
  tasks_to_skip=()
  prune_skip_reasons=()
  for path in "$PROJECT_ROOT"/*; do
    is_task_workspace_path "$path" || continue
    task=${path##*/}
    if reason=$(prune_task_is_fully_merged "$task"); then
      tasks_to_prune[${#tasks_to_prune[@]}]="$task"
    else
      tasks_to_skip[${#tasks_to_skip[@]}]="$task"
      prune_skip_reasons[${#prune_skip_reasons[@]}]="$reason"
    fi
  done
}

cmd_prune() {
  require_project
  [ $# -eq 0 ] || die "usage: workbranch prune"
  collect_prune_tasks

  i=0
  while [ $i -lt ${#tasks_to_skip[@]} ]; do
    info "Skipped: ${tasks_to_skip[$i]} (${prune_skip_reasons[$i]})"
    i=$((i + 1))
  done

  if [ ${#tasks_to_prune[@]} -eq 0 ]; then
    info "No merged tasks to prune"
    return 0
  fi

  i=0
  while [ $i -lt ${#tasks_to_prune[@]} ]; do
    task=${tasks_to_prune[$i]}
    info "Pruning merged task: $task"
    cmd_remove "$task" --force
    i=$((i + 1))
  done
}
