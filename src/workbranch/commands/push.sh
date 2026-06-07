cmd_push_base() {
  reset_preflight
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    branch=$(repo_base_branch_at "$i")
    base=$(base_repo_path "$name")
    label="$BASE_DIR/$name"
    if [ ! -d "$base/.git" ] && [ ! -f "$base/.git" ]; then
      preflight_error "$label missing git repo"
      i=$((i + 1))
      continue
    fi
    preflight_require_current_branch "$label" "$base" "$branch"
    preflight_require_no_rebase "$label" "$base"
    preflight_fetch_origin "$label" "$base"
    preflight_push_fast_forwardable "$label" "$base" "$branch"
    i=$((i + 1))
  done
  preflight_die_if_errors "push"

  i=0
  repo_log_seen=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    branch=$(repo_base_branch_at "$i")
    base=$(base_repo_path "$name")
    repo_log_separator "$repo_log_seen"
    info_repo_branch "Pushing" "" "$name" "$branch"
    workbranch_git_push_base "$name" "$base" "$branch"
    repo_log_seen=1
    i=$((i + 1))
  done
}

cmd_push_task() {
  task=$1
  reset_preflight
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    branch=$(repo_task_branch_at "$i" "$task")
    path=$(task_repo_path "$task" "$name")
    label="$task/$name"
    if [ ! -d "$path/.git" ] && [ ! -f "$path/.git" ]; then
      preflight_error "$label missing git repo"
      i=$((i + 1))
      continue
    fi
    preflight_require_current_branch "$label" "$path" "$branch"
    preflight_require_no_rebase "$label" "$path"
    preflight_fetch_origin "$label" "$path"
    preflight_push_fast_forwardable "$label" "$path" "$branch"
    i=$((i + 1))
  done
  preflight_die_if_errors "push"

  i=0
  repo_log_seen=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    branch=$(repo_task_branch_at "$i" "$task")
    path=$(task_repo_path "$task" "$name")
    repo_log_separator "$repo_log_seen"
    info_repo_branch "Pushing" "$task" "$name" "$branch"
    workbranch_git_push_task "$name" "$path" "$branch"
    repo_log_seen=1
    i=$((i + 1))
  done
}

cmd_push() {
  require_project
  parse_repo_option "$@"
  [ ${#ARGS[@]} -le 1 ] || die "usage: workbranch push [task] [--repo <repo>]"
  if [ ${#ARGS[@]} -eq 0 ]; then
    cmd_push_base
    return 0
  fi

  task=$(normalize_task_argument "${ARGS[0]}")
  validate_task_folder_name "$task"
  cmd_push_task "$task"
}
