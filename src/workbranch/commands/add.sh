prompt_task_branches_for_add() {
  task=$1
  reset_task_metadata_cache
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base_branch=$(repo_base_branch_at "$i")
    default_branch=$(default_repo_task_branch_at "$i" "$task")
    printf '\n' >&2
    printf '%s[*]%s Repo %s\n' "$WB_ERR_BLUE" "$WB_ERR_RESET" "$(color_repo_name "$name")" >&2
    printf '%s[*]%s   base branch: %s\n' "$WB_ERR_BLUE" "$WB_ERR_RESET" "$(color_branch_name "$base_branch")" >&2
    branch=$(prompt_read "[*]   task repo branch [$(color_branch_name "$default_branch")]: ")
    prompt_status=$?
    [ "$prompt_status" -eq 0 ] || printf '\n' >&2
    [ -n "$branch" ] || branch=$default_branch
    validate_branch_name "task branch" "$branch"
    printf '%s[*]%s   task repo folder: %s\n' "$WB_ERR_BLUE" "$WB_ERR_RESET" "$(format_repo_target "$task" "$name")" >&2
    set_task_metadata_branch "$name" "$branch"
    i=$((i + 1))
  done
}

prompt_task_identity_for_add() {
  local default_detail type detail task
  default_detail=${1:-}
  printf '%s[*]%s Task type examples: feat, fix, chore, docs, refactor, test, perf, ci, build, revert\n' "$WB_ERR_BLUE" "$WB_ERR_RESET" >&2
  type=$(prompt_with_default "Task type" "feat")
  validate_task_type "$type"
  if [ -n "$default_detail" ]; then
    detail=$(prompt_with_default "Task detail name" "$default_detail")
  else
    detail=$(prompt_required "Task detail name")
  fi
  validate_task_detail_name "$detail" "$type"
  task=$(task_folder_from_identity "$type" "$detail")
  printf '%s[*]%s Task folder: %s\n' "$WB_ERR_BLUE" "$WB_ERR_RESET" "$task" >&2
  printf '%s' "$task"
}

resolve_task_for_add() {
  local candidate
  if [ ${#ARGS[@]} -eq 0 ]; then
    prompt_task_identity_for_add
    return 0
  fi

  candidate=$(normalize_task_argument "${ARGS[0]}")
  validate_task_folder_name "$candidate"
  if task_identity_has_delimiter "$candidate"; then
    printf '%s' "$candidate"
    return 0
  fi

  if [ -t 0 ]; then
    prompt_task_identity_for_add "$candidate"
  else
    printf '%s' "$candidate"
  fi
}

parse_add_options() {
  ADD_FROM_REF=""
  ARGS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --from)
        [ $# -ge 2 ] || die "missing value for --from"
        ADD_FROM_REF=$2
        shift 2
        ;;
      --from=*)
        ADD_FROM_REF=${1#--from=}
        [ -n "$ADD_FROM_REF" ] || die "missing value for --from"
        shift
        ;;
      --*)
        die "usage: workbranch add [<task>] [--from <ref>]"
        ;;
      *)
        ARGS[${#ARGS[@]}]=$1
        shift
        ;;
    esac
  done

  [ ${#ARGS[@]} -le 1 ] || die "usage: workbranch add [<task>] [--from <ref>]"
  if [ -n "$ADD_FROM_REF" ]; then
    validate_nonempty_no_space "source ref" "$ADD_FROM_REF"
  fi
}

resolve_add_source_ref() {
  base=$1
  requested=$2
  case "$requested" in
    "")
      printf 'HEAD'
      return 0
      ;;
    origin/*|refs/*|HEAD)
      git_ref_exists "$base" "$requested" || return 1
      printf '%s' "$requested"
      return 0
      ;;
  esac

  if git_ref_exists "$base" "origin/$requested"; then
    printf 'origin/%s' "$requested"
    return 0
  fi
  git_ref_exists "$base" "$requested" || return 1
  printf '%s' "$requested"
}

cmd_add() {
  parse_add_options "$@"
  require_project
  task=$(resolve_task_for_add) || return 1
  validate_task_folder_name "$task"
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

  if [ -n "$ADD_FROM_REF" ]; then
    reset_preflight
    i=0
    while [ $i -lt ${#REPO_NAMES[@]} ]; do
      name=$(repo_name_at "$i")
      base=$(base_repo_path "$name")
      base_label="$BASE_DIR/$name"
      preflight_fetch_origin "$base_label" "$base"
      if ! resolve_add_source_ref "$base" "$ADD_FROM_REF" >/dev/null; then
        preflight_error "$base_label missing source ref: $ADD_FROM_REF"
      fi
      i=$((i + 1))
    done
    preflight_die_if_errors "add"
  fi

  prompt_task_branches_for_add "$task"
  ADD_SOURCE_REFS=()

  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base=$(base_repo_path "$name")
    base_label="$BASE_DIR/$name"
    branch=$(metadata_task_branch_for_repo "$name") || branch=$(default_repo_task_branch_at "$i" "$task")
    workbranch_git_add_fetch_base "$base" || die "failed to fetch repo '$name'"
    source_ref=$(resolve_add_source_ref "$base" "$ADD_FROM_REF") || die "$base_label missing source ref: $ADD_FROM_REF"
    ADD_SOURCE_REFS[$i]=$source_ref
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
  write_default_task_state "$task"

  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base=$(base_repo_path "$name")
    base_branch=$(repo_base_branch_at "$i")
    branch=$(metadata_task_branch_for_repo "$name") || branch=$(default_repo_task_branch_at "$i" "$task")
    source_ref=${ADD_SOURCE_REFS[$i]:-HEAD}
    target=$(task_repo_path "$task" "$name")
    track_branch "$base" "$branch"
    track_worktree "$target" "$base"
    workbranch_git_add_new_task_worktree "$base" "$target" "$branch" "$source_ref" || fail_with_rollback "failed to create worktree for repo '$name'"
    printf '\n'
    success_repo_target "Created" "$task" "$name"
    if [ -n "$ADD_FROM_REF" ]; then
      success "  [source] $(color_branch_name "$source_ref") -> [task repo] $(color_branch_name "$branch")"
    else
      success "  [base repo] $(color_branch_name "$base_branch") -> [task repo] $(color_branch_name "$branch")"
    fi
    i=$((i + 1))
  done
  if has_task_setups; then
    printf '\n'
    if ! run_task_setups "$task"; then
      printf '%s[-] Error:%s task setup failed\n' "$WB_ERR_RED" "$WB_ERR_RESET" >&2
      printf '%s[*]%s Worktrees were created. Fix setup with:\n' "$WB_ERR_BLUE" "$WB_ERR_RESET" >&2
      printf '    %sworkbranch config%s\n' "$WB_ERR_GRAY" "$WB_ERR_RESET" >&2
      printf '%s[*]%s Then rerun the setup command shown above, or remove and add the task again.\n' "$WB_ERR_BLUE" "$WB_ERR_RESET" >&2
      return 1
    fi
  fi
}
