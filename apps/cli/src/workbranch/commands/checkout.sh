parse_checkout_options() {
  CHECKOUT_BRANCH=""
  CHECKOUT_TASK=""
  ARGS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -*)
        die "usage: workbranch checkout <branch> [<task>]"
        ;;
      *)
        ARGS[${#ARGS[@]}]=$1
        shift
        ;;
    esac
  done

  if [ ${#ARGS[@]} -lt 1 ] || [ ${#ARGS[@]} -gt 2 ]; then
    die "usage: workbranch checkout <branch> [<task>]"
  fi
  CHECKOUT_BRANCH=${ARGS[0]#origin/}
  validate_branch_name "branch" "$CHECKOUT_BRANCH"
  if [ ${#ARGS[@]} -eq 2 ]; then
    validate_task_folder_name "${ARGS[1]}"
    CHECKOUT_TASK=$(normalize_task_argument "${ARGS[1]}")
    # Commands that find task workspaces skip dot-prefixed folders.
    case "$CHECKOUT_TASK" in
      .*) die "invalid task '$CHECKOUT_TASK': a task folder cannot start with '.'" ;;
    esac
  fi
}

# Prints the worktree that has the branch checked out, if any.
checkout_worktree_path_for_branch() {
  local base branch line path
  base=$1
  branch=$2
  path=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      worktree\ *) path=${line#worktree } ;;
      "branch refs/heads/$branch")
        [ -n "$path" ] || return 1
        printf '%s' "$path"
        return 0
        ;;
      "") path="" ;;
    esac
  done <<EOF_WORKTREE_LIST
$(git -C "$base" worktree list --porcelain 2>/dev/null || true)
EOF_WORKTREE_LIST
  return 1
}

checkout_local_branch_exists_message() {
  local base_label base branch worktree
  base_label=$1
  base=$2
  branch=$3
  if worktree=$(checkout_worktree_path_for_branch "$base" "$branch"); then
    printf '%s\n' "$base_label branch $branch is already checked out at ${worktree#"$PROJECT_ROOT"/}"
    return 0
  fi
  printf '%s\n' \
    "$base_label local branch $branch already exists" \
    "Delete it, then retry:" \
    "  git -C $(shell_quote "$base") branch -d $(shell_quote "$branch")"
}

checkout_stale_remote_ref_message() {
  local base_label base branch
  base_label=$1
  base=$2
  branch=$3
  printf '%s\n' \
    "$base_label has a stale origin/$branch; origin no longer has that branch" \
    "Drop the stale ref, then retry:" \
    "  git -C $(shell_quote "$base") branch -dr $(shell_quote "origin/$branch")"
}

# Decide how one repo joins the task: "track" when origin has the branch,
# "create" when it does not and the branch starts from the local base worktree.
# An empty mode means the repo is blocked by an error of its own.
preflight_checkout_repo() {
  local index branch name base base_branch base_label state errors_before
  index=$1
  branch=$2
  name=$(repo_name_at "$index")
  base=$(base_repo_path "$name")
  base_branch=$(repo_base_branch_at "$index")
  base_label="$BASE_DIR/$name"
  CHECKOUT_REPO_MODES[$index]=""

  if [ ! -d "$base/.git" ] && [ ! -f "$base/.git" ]; then
    preflight_error "$base_label missing git repo"
    CHECKOUT_REPO_BLOCKED=1
    return 0
  fi
  if [ "$branch" = "$base_branch" ]; then
    preflight_error "$base_label $branch is the configured base branch"
    CHECKOUT_REPO_BLOCKED=1
    return 0
  fi
  if branch_exists "$base" "$branch"; then
    preflight_error "$(checkout_local_branch_exists_message "$base_label" "$base" "$branch")"
    CHECKOUT_REPO_BLOCKED=1
    return 0
  fi
  if ! workbranch_git_add_fetch_base "$base"; then
    preflight_error "$base_label failed to fetch origin"
    CHECKOUT_REPO_BLOCKED=1
    return 0
  fi

  workbranch_git_remote_branch_state "$base" "$branch"
  state=$?
  case "$state" in
    0)
      if git_ref_exists "$base" "refs/remotes/origin/$branch"; then
        CHECKOUT_REPO_MODES[$index]=track
        CHECKOUT_REMOTE_FOUND=1
      else
        preflight_error "$base_label origin has $branch, but fetch did not create origin/$branch; check the remote fetch refspec"
        CHECKOUT_REPO_BLOCKED=1
      fi
      ;;
    1)
      if git_ref_exists "$base" "refs/remotes/origin/$branch"; then
        preflight_error "$(checkout_stale_remote_ref_message "$base_label" "$base" "$branch")"
        CHECKOUT_REPO_BLOCKED=1
        return 0
      fi
      CHECKOUT_REPO_MODES[$index]=create
      errors_before=${#PREFLIGHT_ERRORS[@]}
      preflight_require_current_branch "$base_label" "$base" "$base_branch"
      preflight_require_clean "$base_label" "$base"
      preflight_require_no_rebase "$base_label" "$base"
      if [ ${#PREFLIGHT_ERRORS[@]} -gt "$errors_before" ]; then
        preflight_error "$base_label has no origin/$branch, so its task branch starts from the local base worktree"
      fi
      ;;
    *)
      preflight_error "$base_label failed to ask origin for branch $branch"
      CHECKOUT_REPO_BLOCKED=1
      ;;
  esac
}

preflight_checkout() {
  local branch i
  branch=$1
  CHECKOUT_REPO_MODES=()
  CHECKOUT_REMOTE_FOUND=0
  CHECKOUT_REPO_BLOCKED=0
  reset_preflight
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    preflight_checkout_repo "$i" "$branch"
    i=$((i + 1))
  done

  # When every repo simply lacks the branch, nothing to check out is the real
  # problem, and base worktree errors in repos that would only have received a
  # new branch are noise next to it. A blocked repo keeps its own error: the
  # advice below would run into the same block.
  if [ "$CHECKOUT_REMOTE_FOUND" -eq 0 ] && [ "$CHECKOUT_REPO_BLOCKED" -eq 0 ]; then
    printf '%s[-] Error:%s no repo has remote branch origin/%s\n' "$WB_ERR_RED" "$WB_ERR_RESET" "$branch" >&2
    printf '%s[*]%s To start a new task branch instead: workbranch add\n' "$WB_ERR_BLUE" "$WB_ERR_RESET" >&2
    exit 1
  fi
  preflight_die_if_errors "checkout"
}

cmd_checkout() {
  parse_checkout_options "$@"
  require_project
  branch=$CHECKOUT_BRANCH
  if [ -n "$CHECKOUT_TASK" ]; then
    task=$CHECKOUT_TASK
  else
    task=$(task_folder_from_branch "$branch") || die "cannot derive a task folder from branch '$branch'; name one: workbranch checkout $(shell_quote "$branch") <task>"
  fi
  CREATED_PATHS=()
  CREATED_WORKTREES=()
  CREATED_WORKTREE_BASES=()
  CREATED_BRANCH_REPOS=()
  CREATED_BRANCH_NAMES=()
  task_dir="$PROJECT_ROOT/$task"
  [ ! -e "$task_dir" ] || die "task directory already exists: $task_dir"

  preflight_checkout "$branch"

  reset_task_metadata_cache
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    set_task_metadata_branch "$(repo_name_at "$i")" "$branch"
    i=$((i + 1))
  done

  # Plain mkdir fails if another process claimed the directory after the check
  # above, so rollback only ever removes a directory this command created.
  mkdir "$task_dir" 2>/dev/null || die "failed to create task directory: $task_dir"
  track_path "$task_dir"
  # The writers exit on failure; the subshell turns that into a status so the
  # task directory is rolled back instead of blocking the retry.
  (write_task_metadata "$task" && write_default_task_state "$task") || fail_with_rollback "failed to initialize task workspace: $task"

  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base=$(base_repo_path "$name")
    base_branch=$(repo_base_branch_at "$i")
    target=$(task_repo_path "$task" "$name")
    if [ "${CHECKOUT_REPO_MODES[$i]}" = "track" ]; then
      workbranch_git_create_task_branch_from_remote "$base" "$branch" || fail_with_rollback "failed to create task branch for repo '$name'"
    else
      workbranch_git_create_task_branch_from_base "$base" "$branch" || fail_with_rollback "failed to create task branch for repo '$name'"
    fi
    # Registered only now: a branch someone else created in the meantime made
    # the step above fail, and rollback must not delete it.
    track_branch "$base" "$branch"
    track_worktree "$target" "$base"
    workbranch_git_add_existing_task_worktree "$base" "$target" "$branch" || fail_with_rollback "failed to create worktree for repo '$name'"
    printf '\n'
    success_repo_target "Created" "$task" "$name"
    if [ "${CHECKOUT_REPO_MODES[$i]}" = "track" ]; then
      success "  [remote] $(color_branch_name "origin/$branch") -> [task repo] $(color_branch_name "$branch")"
    else
      success "  [base repo] $(color_branch_name "$base_branch") -> [task repo] $(color_branch_name "$branch") (new; not on origin)"
    fi
    i=$((i + 1))
  done
  run_new_task_setups "$task" "check out"
}
