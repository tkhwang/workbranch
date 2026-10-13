UPDATE_AUTOSTASH_MESSAGE="autostash: workbranch update"

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
    task_dirty=0
    is_git_dirty "$task_path" && task_dirty=1
    if [ "$task_dirty" -eq 1 ]; then
      case "$UPDATE_AUTOSTASH" in
        1) ;;
        0) preflight_error "$label dirty worktree; retry with --autostash to set local changes aside" ;;
        *) preflight_error "$label dirty worktree" ;;
      esac
    fi
    preflight_require_no_rebase "$label" "$task_path"
    base_head=$(git -C "$base" rev-parse HEAD 2>/dev/null) || base_head=""
    if [ -n "$base_head" ] &&       [ "$(branch_or_unknown "$base")" = "$base_branch" ] &&       [ "$(branch_or_unknown "$task_path")" = "$branch" ] &&       ! is_rebase_in_progress "$base" &&       ! is_rebase_in_progress "$task_path"; then
      if [ "$task_dirty" -eq 0 ]; then
        preflight_update_rebase_clean "$label" "$task_path" "$base_label" "$base_head"
      elif [ "$UPDATE_AUTOSTASH" = 1 ]; then
        preflight_update_autostash "$label" "$task_path" "$branch" "$base_label" "$base_head"
      fi
    fi
    i=$((i + 1))
  done
}

# Replay the autostash sequence (save, rebase, restore --index) in a scratch
# worktree so rebase and restore conflicts surface before any task changes.
preflight_update_autostash() {
  local label task_path branch base_label base_ref saved
  label=$1
  task_path=$2
  branch=$3
  base_label=$4
  base_ref=$5
  STASH_TOP=$task_path

  if stash_operation_in_progress; then
    preflight_error "$label merge, cherry-pick, or revert in progress"
    return 0
  fi
  if stash_existing_commit "$branch" >/dev/null; then
    preflight_error "$label already has a workbranch stash for $branch; run workbranch stash pop or drop in $PROJECT_ROOT/$label first"
    return 0
  fi

  git_ref_exists "$task_path" HEAD || return 0
  git_ref_exists "$task_path" "$base_ref" || return 0
  # Nothing to rebase: local changes stay in place.
  git_is_ancestor "$task_path" "$base_ref" HEAD && return 0

  saved=$(stash_build_commit "$branch" "$UPDATE_AUTOSTASH_MESSAGE" 2>/dev/null) || {
    preflight_error "$label cannot prepare autostash preflight"
    return 0
  }
  preflight_update_rebase_clean "$label" "$task_path" "$base_label" "$base_ref" "$saved"
}

# Set local changes aside in the branch's workbranch stash slot, rebase, then
# restore them with --index so staged and unstaged changes keep their split.
update_task_repo_autostash() {
  local task_path branch base_ref ref saved short output
  task_path=$1
  branch=$2
  base_ref=$3
  STASH_TOP=$task_path

  if git_is_ancestor "$task_path" "$base_ref" HEAD; then
    info "Already up to date; local changes left in place"
    return 0
  fi

  stash_require_no_operation_in_progress
  ref=$(stash_ref_for_branch "$branch") || exit 1
  ! stash_existing_commit "$branch" >/dev/null ||
    die "branch '$branch' already has a workbranch stash; run workbranch stash pop or drop in $task_path first"
  saved=$(stash_build_commit "$branch" "$UPDATE_AUTOSTASH_MESSAGE") || exit 1
  if [ -z "$saved" ]; then
    workbranch_git_update_task "$task_path" "$base_ref"
    return 0
  fi
  stash_save_commit "$branch" "$ref" "$saved"
  short=$(git -C "$task_path" rev-parse --short "$saved")
  info "Stashed local changes as $short"

  if ! workbranch_git_rebase_task "$task_path" "$base_ref"; then
    git -C "$task_path" rebase --abort >/dev/null 2>&1 || true
    if output=$(cd "$task_path" && git stash apply --index "$saved" 2>&1); then
      git -C "$task_path" update-ref -d "$ref" "$saved" ||
        die "rebase aborted and local changes restored, but failed to drop $ref"
      die "update failed in $task_path; rebase aborted and local changes restored"
    fi
    printf '%s\n' "$output" >&2
    die "update failed in $task_path; rebase aborted but stash $short did not restore cleanly and is kept. Resolve the changes, then run: (cd $task_path && workbranch stash drop)"
  fi

  if ! output=$(cd "$task_path" && git stash apply --index "$saved" 2>&1); then
    printf '%s\n' "$output" >&2
    die "updated $task_path but stash $short did not restore cleanly and is kept. Resolve the changes, then run: (cd $task_path && workbranch stash drop)"
  fi
  git -C "$task_path" update-ref -d "$ref" "$saved" ||
    die "restored $short but failed to drop $ref"
  success "Restored local changes from $short"
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
    if [ "$UPDATE_AUTOSTASH" = 1 ] && is_git_dirty "$task_path"; then
      update_task_repo_autostash "$task_path" "$branch" "$(head_commit_full "$base")"
    else
      ensure_clean_worktree "$task_path"
      workbranch_git_update_task "$task_path" "$(head_commit_full "$base")"
    fi
    success_repo_target "Updated" "$task" "$name"
    repo_log_seen=1
    i=$((i + 1))
  done
}

is_update_task_workspace_path() {
  local path dir_name i name selected_count
  path=$1
  if [ -z "$FILTER_REPO" ]; then
    is_task_workspace_path "$path"
    return $?
  fi

  [ -d "$path" ] || return 1
  dir_name=${path##*/}
  [ "$dir_name" = "$BASE_DIR" ] && return 1
  case "$dir_name" in .*) return 1 ;; esac

  selected_count=0
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    selected_count=$((selected_count + 1))
    is_registered_worktree_path "$path/$name" "$(base_repo_path "$name")" || return 1
    i=$((i + 1))
  done
  [ "$selected_count" -gt 0 ]
}

collect_update_all_tasks() {
  tasks_to_update=()
  for path in "$PROJECT_ROOT"/*; do
    is_update_task_workspace_path "$path" || continue
    task_name=${path##*/}
    tasks_to_update[${#tasks_to_update[@]}]="$task_name"
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

# Remove --autostash from ARGS (left by parse_repo_option) and record it.
parse_autostash_option() {
  local remaining arg
  UPDATE_AUTOSTASH=0
  remaining=()
  for arg in ${ARGS[@]+"${ARGS[@]}"}; do
    if [ "$arg" = "--autostash" ]; then
      UPDATE_AUTOSTASH=1
    else
      remaining[${#remaining[@]}]=$arg
    fi
  done
  ARGS=(${remaining[@]+"${remaining[@]}"})
}

cmd_update() {
  require_project
  parse_repo_option "$@"
  parse_autostash_option
  [ ${#ARGS[@]} -le 1 ] || die "usage: workbranch update [task] [--repo <repo>] [--autostash]"
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
