prompt_task_branches_for_add() {
  task=$1
  reset_task_metadata_cache
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base_branch=$(repo_base_branch_at "$i")
    default_branch=$(default_repo_task_branch_at "$i" "$task")
    info "Repo $name base branch: $base_branch"
    branch=$(prompt_with_default "Task branch for $name" "$default_branch")
    validate_branch_name "task branch" "$branch"
    set_task_metadata_branch "$name" "$branch"
    i=$((i + 1))
  done
}

cmd_add() {
  [ $# -eq 1 ] || die "usage: workbranch add <task>"
  task=$1
  validate_safe_name "task" "$task"
  require_project
  CREATED_PATHS=()
  CREATED_WORKTREES=()
  CREATED_WORKTREE_BASES=()
  CREATED_BRANCH_REPOS=()
  CREATED_BRANCH_NAMES=()
  task_dir="$PROJECT_ROOT/$task"
  [ ! -e "$task_dir" ] || die "task directory already exists: $task_dir"

  reset_preflight
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base=$(base_repo_path "$name")
    base_branch=$(repo_base_branch_at "$i")
    base_label="$BASE_DIR/$name"
    if [ ! -d "$base/.git" ] && [ ! -f "$base/.git" ]; then
      preflight_error "$base_label missing git repo"
      i=$((i + 1))
      continue
    fi
    preflight_require_current_branch "$base_label" "$base" "$base_branch"
    preflight_require_clean "$base_label" "$base"
    preflight_require_no_rebase "$base_label" "$base"
    i=$((i + 1))
  done
  preflight_die_if_errors "add"

  prompt_task_branches_for_add "$task"

  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base=$(base_repo_path "$name")
    branch=$(metadata_task_branch_for_repo "$name") || branch=$(default_repo_task_branch_at "$i" "$task")
    workbranch_git_add_fetch_base "$base" || die "failed to fetch repo '$name'"
    local_branch_exists=0
    remote_branch_exists=0
    branch_exists "$base" "$branch" && local_branch_exists=1
    git_ref_exists "$base" "origin/$branch" && remote_branch_exists=1
    if [ "$local_branch_exists" -eq 1 ] || [ "$remote_branch_exists" -eq 1 ]; then
      printf "[-] Error: task branch already exists for repo '%s': %s\n" "$name" "$branch" >&2
      if [ "$local_branch_exists" -eq 1 ]; then
        printf '[*] To delete the local branch first: workbranch remove %s\n' "$task" >&2
      fi
      if [ "$remote_branch_exists" -eq 1 ]; then
        printf '[*] Remote origin/%s exists; delete it outside workbranch before adding again.\n' "$branch" >&2
      fi
      exit 1
    fi
    i=$((i + 1))
  done

  mkdir -p "$task_dir" || die "failed to create task directory: $task_dir"
  track_path "$task_dir"
  write_task_metadata "$task"

  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base=$(base_repo_path "$name")
    base_branch=$(repo_base_branch_at "$i")
    branch=$(metadata_task_branch_for_repo "$name") || branch=$(default_repo_task_branch_at "$i" "$task")
    target=$(task_repo_path "$task" "$name")
    track_branch "$base" "$branch"
    track_worktree "$target" "$base"
    workbranch_git_add_new_task_worktree "$base" "$target" "$branch" || fail_with_rollback "failed to create worktree for repo '$name'"
    success "Created: $task/$name"
    success "  [base repo] $base_branch -> [task repo] $branch"
    i=$((i + 1))
  done
  if has_task_setups && ! run_task_setups "$task"; then
    printf '[-] Error: task setup failed\n' >&2
    printf '[*] Worktrees were created. Fix setup with:\n' >&2
    printf '    workbranch config\n' >&2
    printf '[*] Then rerun the setup command shown above, or remove and add the task again.\n' >&2
    return 1
  fi
}
