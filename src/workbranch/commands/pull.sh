cmd_pull() {
  require_project
  parse_repo_option "$@"
  [ ${#ARGS[@]} -eq 0 ] || die "usage: workbranch pull [--repo <repo>]"
  reset_preflight
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    base=$(base_repo_path "$name")
    branch=$(repo_base_branch_at "$i")
    label="$BASE_DIR/$name"
    if [ ! -d "$base/.git" ] && [ ! -f "$base/.git" ]; then
      preflight_error "$label missing git repo"
      i=$((i + 1))
      continue
    fi
    preflight_require_current_branch "$label" "$base" "$branch"
    preflight_require_clean "$label" "$base"
    preflight_require_no_rebase "$label" "$base"
    preflight_fetch_origin "$label" "$base"
    preflight_remote_branch_exists "$label" "$base" "$branch"
    preflight_pull_fast_forwardable "$label" "$base" "$branch"
    i=$((i + 1))
  done
  preflight_die_if_errors "pull"

  i=0
  repo_log_seen=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    branch=$(repo_base_branch_at "$i")
    base=$(base_repo_path "$name")
    repo_log_separator "$repo_log_seen"
    info_repo_branch "Pulling" "" "$name" "$branch"
    ensure_current_branch "$base" "$branch"
    workbranch_git_pull_base "$name" "$base" "$branch"
    repo_log_seen=1
    i=$((i + 1))
  done
}
