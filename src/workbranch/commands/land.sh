cmd_land() {
  require_project
  parse_repo_option "$@"
  [ ${#ARGS[@]} -eq 1 ] || die "usage: workbranch land <task> [--repo <repo>]"
  task=${ARGS[0]}
  validate_safe_name "task" "$task"

  reset_preflight
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    base=$(base_repo_path "$name")
    path=$(task_repo_path "$task" "$name")
    branch=$(repo_task_branch_at "$i" "$task")
    base_branch=$(repo_base_branch_at "$i")
    label="$task/$name"
    base_label="$BASE_DIR/$name"
    if [ ! -d "$path/.git" ] && [ ! -f "$path/.git" ]; then
      preflight_error "$label missing git repo"
      i=$((i + 1))
      continue
    fi
    preflight_require_current_branch "$label" "$path" "$branch"
    preflight_require_clean "$label" "$path"
    preflight_require_no_rebase "$label" "$path"
    if [ ! -d "$base/.git" ] && [ ! -f "$base/.git" ]; then
      preflight_error "$base_label missing git repo"
      i=$((i + 1))
      continue
    fi
    preflight_require_current_branch "$base_label" "$base" "$base_branch"
    preflight_require_clean "$base_label" "$base"
    preflight_require_no_rebase "$base_label" "$base"
    preflight_fetch_origin "$base_label" "$base"
    preflight_remote_branch_exists "$base_label" "$base" "$base_branch"
    preflight_pull_fast_forwardable "$base_label" "$base" "$base_branch"
    land_label="$task/$name"
    task_branch_for_land=$(repo_task_branch_at "$i" "$task")
    preflight_land_fast_forwardable "$land_label" "$base" "$base_branch" "$task_branch_for_land"
    i=$((i + 1))
  done
  preflight_die_if_errors "land"

  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    base=$(base_repo_path "$name")
    branch=$(repo_task_branch_at "$i" "$task")
    base_branch=$(repo_base_branch_at "$i")
    workbranch_git_land_checkout_base "$name" "$base" "$base_branch"
    ensure_current_branch "$base" "$base_branch"
    workbranch_git_land_pull_base "$name" "$base" "$base_branch"
    workbranch_git_land_task "$name" "$base" "$branch" "$task"
    success "Landed: $task/$name -> $base_branch"
    i=$((i + 1))
  done
}
