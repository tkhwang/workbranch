preflight_pull_repos() {
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
}

execute_pull_repos() {
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

pull_archive_capture_candidates() {
  local task_dir task i name base base_branch branch old_base_head commit_count matched repos ok candidate_index
  PULL_ARCHIVE_TASKS=()
  PULL_ARCHIVE_REPOS=()
  for task_dir in "$PROJECT_ROOT"/*; do
    [ -d "$task_dir" ] || continue
    is_task_workspace_path "$task_dir" || continue
    task=${task_dir##*/}
    i=0
    matched=0
    repos=""
    ok=1
    while [ $i -lt ${#REPO_NAMES[@]} ]; do
      name=$(repo_name_at "$i")
      repo_matches_filter "$name" || { i=$((i + 1)); continue; }
      matched=$((matched + 1))
      base=$(base_repo_path "$name")
      base_branch=$(repo_base_branch_at "$i")
      branch=$(repo_task_branch_at "$i" "$task")
      if [ ! -d "$base/.git" ] && [ ! -f "$base/.git" ]; then
        ok=0
        i=$((i + 1))
        continue
      fi
      old_base_head=$(git -C "$base" rev-parse --verify --quiet "$base_branch^{commit}" 2>/dev/null) || old_base_head=""
      if [ -z "$old_base_head" ] || ! branch_exists "$base" "$branch"; then
        ok=0
        i=$((i + 1))
        continue
      fi
      commit_count=$(git -C "$base" rev-list --count "$old_base_head..$branch" 2>/dev/null) || commit_count=0
      if [ "$commit_count" -le 0 ]; then
        ok=0
      fi
      repos="$repos $name"
      i=$((i + 1))
    done
    if [ "$matched" -gt 0 ] && [ "$ok" -eq 1 ]; then
      candidate_index=${#PULL_ARCHIVE_TASKS[@]}
      PULL_ARCHIVE_TASKS[$candidate_index]=$task
      PULL_ARCHIVE_REPOS[$candidate_index]=$repos
    fi
  done
}

pull_archive_prompt_candidates() {
  local candidate_count candidate_index task repos name repo_index base base_branch branch ok
  candidate_count=${#PULL_ARCHIVE_TASKS[@]}
  candidate_index=0
  while [ $candidate_index -lt "$candidate_count" ]; do
    task=${PULL_ARCHIVE_TASKS[$candidate_index]}
    repos=${PULL_ARCHIVE_REPOS[$candidate_index]}
    ok=1
    for name in $repos; do
      repo_index=$(repo_index_by_name "$name") || { ok=0; continue; }
      base=$(base_repo_path "$name")
      base_branch=$(repo_base_branch_at "$repo_index")
      branch=$(repo_task_branch_at "$repo_index" "$task")
      if ! git_is_ancestor "$base" "$branch" "$base_branch"; then
        ok=0
      fi
    done
    if [ "$ok" -eq 1 ]; then
      archive_prompt_current_plan "$task" pull
    fi
    candidate_index=$((candidate_index + 1))
  done
}

run_pull() {
  reset_preflight
  preflight_pull_repos
  preflight_die_if_errors "pull"
  pull_archive_capture_candidates
  execute_pull_repos
  pull_archive_prompt_candidates
}

cmd_pull() {
  require_project
  parse_repo_option "$@"
  [ ${#ARGS[@]} -eq 0 ] || die "usage: workbranch pull [--repo <repo>]"
  run_pull
}
