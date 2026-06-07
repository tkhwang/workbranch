preflight_update_task() {
  task=$1
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    base=$(base_repo_path "$name")
    task_path=$(task_repo_path "$task" "$name")
    base_branch=$(repo_base_branch_at "$i")
    branch=$(repo_task_branch_at "$i" "$task")
    label="$task/$name"
    base_label="$BASE_DIR/$name"
    if [ ! -d "$base/.git" ] && [ ! -f "$base/.git" ]; then
      preflight_error "$base_label missing git repo"
    else
      preflight_require_current_branch "$base_label" "$base" "$base_branch"
      preflight_require_no_rebase "$base_label" "$base"
    fi
    if [ ! -d "$task_path/.git" ] && [ ! -f "$task_path/.git" ]; then
      preflight_error "$label missing git repo"
      i=$((i + 1))
      continue
    fi
    preflight_require_current_branch "$label" "$task_path" "$branch"
    preflight_require_clean "$label" "$task_path"
    preflight_require_no_rebase "$label" "$task_path"
    i=$((i + 1))
  done
}

update_task() {
  task=$1
  i=0
  repo_log_seen=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    base=$(base_repo_path "$name")
    base_branch=$(repo_base_branch_at "$i")
    branch=$(repo_task_branch_at "$i" "$task")
    task_path=$(task_repo_path "$task" "$name")
    [ -d "$base/.git" ] || [ -f "$base/.git" ] || die "base repo missing for '$name': $base"
    [ -d "$task_path/.git" ] || [ -f "$task_path/.git" ] || die "task repo missing for '$name': $task_path"
    repo_log_separator "$repo_log_seen"
    info_repo_branch "Updating" "$task" "$name" "$branch"
    ensure_current_branch "$base" "$base_branch"
    ensure_clean_worktree "$task_path"
    workbranch_git_update_task "$task_path" "$(head_commit_full "$base")"
    success_repo_target "Updated" "$task" "$name"
    repo_log_seen=1
    i=$((i + 1))
  done
}

collect_update_all_tasks() {
  tasks_to_update=()
  for path in "$PROJECT_ROOT"/*; do
    is_task_workspace_path "$path" || continue
    task_name=${path##*/}
    tasks_to_update[${#tasks_to_update[@]}]=$task_name
  done
  [ ${#tasks_to_update[@]} -gt 0 ] || die "no task workspaces to update"
}

preflight_update_all_tasks() {
  reset_preflight
  task_i=0
  while [ $task_i -lt ${#tasks_to_update[@]} ]; do
    preflight_update_task "${tasks_to_update[$task_i]}"
    task_i=$((task_i + 1))
  done
  preflight_die_if_errors "update"
}

execute_update_all_tasks() {
  task_i=0
  while [ $task_i -lt ${#tasks_to_update[@]} ]; do
    update_task "${tasks_to_update[$task_i]}"
    task_i=$((task_i + 1))
  done
}

run_update_all() {
  collect_update_all_tasks
  preflight_update_all_tasks
  execute_update_all_tasks
}

cmd_update() {
  require_project
  parse_repo_option "$@"
  [ ${#ARGS[@]} -le 1 ] || die "usage: workbranch update [task] [--repo <repo>]"
  if [ ${#ARGS[@]} -eq 1 ] && [ "${ARGS[0]}" != "--all" ]; then
    task=$(normalize_task_argument "${ARGS[0]}")
    validate_task_folder_name "$task"
    reset_preflight
    preflight_update_task "$task"
    preflight_die_if_errors "update"
    update_task "$task"
    return 0
  fi

  run_update_all
}
