cmd_config() {
  rewrite_only=0
  case $# in
    0) ;;
    1)
      [ "$1" = "--rewrite" ] || die "usage: workbranch config [--rewrite]"
      rewrite_only=1
      ;;
    *) die "usage: workbranch config [--rewrite]" ;;
  esac
  CREATED_PATHS=()
  CREATED_WORKTREES=()
  CREATED_WORKTREE_BASES=()
  CREATED_BRANCH_REPOS=()
  CREATED_BRANCH_NAMES=()
  if find_project_root; then
    parse_config_for_rewrite "$CONFIG_FILE"
    CONFIG_FILE="$PROJECT_ROOT/.workbranch.config"
    if [ "$rewrite_only" -eq 0 ]; then
      configure_existing_project
    fi
    write_config "$CONFIG_FILE"
    if [ "$rewrite_only" -eq 1 ]; then
      success "Config rewritten: $CONFIG_FILE"
    else
      success "Config updated: $CONFIG_FILE"
      print_config_next_steps
    fi
  else
    [ "$rewrite_only" -eq 0 ] || die "no enclosing workbranch project found"
    cmd_init_interactive no
  fi
}

CONFIG_BRANCH_CHANGE_REPOS=()
CONFIG_BRANCH_CHANGE_OLD=()
CONFIG_BRANCH_CHANGE_NEW=()
CONFIG_BASE_DIR_OLD=""
CONFIG_BASE_DIR_NEW=""

record_config_branch_change() {
  name=$1
  old=$2
  new=$3
  CONFIG_BRANCH_CHANGE_REPOS[${#CONFIG_BRANCH_CHANGE_REPOS[@]}]=$name
  CONFIG_BRANCH_CHANGE_OLD[${#CONFIG_BRANCH_CHANGE_OLD[@]}]=$old
  CONFIG_BRANCH_CHANGE_NEW[${#CONFIG_BRANCH_CHANGE_NEW[@]}]=$new
}

print_config_next_steps() {
  if [ -n "$CONFIG_BASE_DIR_OLD" ]; then
    info "Main worktrees dir change was saved in config only."
    info "Existing cloned base worktrees were not moved automatically."
    printf '    %s -> %s\n' "$CONFIG_BASE_DIR_OLD" "$CONFIG_BASE_DIR_NEW" >&2
  fi

  [ ${#CONFIG_BRANCH_CHANGE_REPOS[@]} -gt 0 ] || return 0

  info "Base branch changes were saved in config only."
  info "Existing cloned base worktrees are not checked out automatically."
  info "Update each changed base worktree before running git operations:"

  i=0
  while [ $i -lt ${#CONFIG_BRANCH_CHANGE_REPOS[@]} ]; do
    name=${CONFIG_BRANCH_CHANGE_REPOS[$i]}
    old=${CONFIG_BRANCH_CHANGE_OLD[$i]}
    new=${CONFIG_BRANCH_CHANGE_NEW[$i]}
    if [ -n "$CONFIG_BASE_DIR_OLD" ]; then
      path="$PROJECT_ROOT/$CONFIG_BASE_DIR_OLD/$name"
    else
      path=$(base_repo_path "$name")
    fi
    printf '    # %s: %s -> %s\n' "$name" "$old" "$new" >&2
    printf '    cd %s\n' "$path" >&2
    printf '    git fetch origin\n' >&2
    printf '    git checkout %s\n' "$new" >&2
    printf '    git pull --ff-only origin %s\n' "$new" >&2
    i=$((i + 1))
  done
}

configure_repo_setup_prompt() {
  name=$1
  idx=$(repo_index_by_name "$name") || die "unknown repo: $name"
  current=$(repo_setup_at "$idx")
  value=$(prompt_read "[*] Repo setup command for $name [$current]: ") || die "input aborted"
  case "$value" in
    "") ;;
    --clear) clear_repo_setup "$name" ;;
    *) set_repo_setup "$name" "$value" ;;
  esac
}

base_worktrees_exist_in_dir() {
  dir=$1
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    path="$PROJECT_ROOT/$dir/$name"
    if [ -d "$path/.git" ] || [ -f "$path/.git" ]; then
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

task_workspaces_exist() {
  for path in "$PROJECT_ROOT"/*; do
    is_task_workspace_path "$path" && return 0
    is_stale_task_directory_path "$path" && return 0
  done
  return 1
}

configure_project_settings() {
  current_project=$PROJECT_NAME
  current_base_dir=$BASE_DIR

  value=$(prompt_with_default "Project name" "$current_project")
  validate_safe_name "PROJECT_NAME" "$value"
  PROJECT_NAME=$value

  value=$(prompt_with_default "Main worktrees dir" "$current_base_dir")
  validate_safe_name "MAIN_WORKTREES_DIR" "$value"
  if [ "$value" != "$current_base_dir" ]; then
    if base_worktrees_exist_in_dir "$current_base_dir"; then
      die "cannot change MAIN_WORKTREES_DIR while base worktrees exist: $current_base_dir
remove or move existing base worktrees before changing it"
    fi
    CONFIG_BASE_DIR_OLD=$current_base_dir
    CONFIG_BASE_DIR_NEW=$value
  fi
  BASE_DIR=$value
  [ -n "$BRANCH_PREFIX" ] || BRANCH_PREFIX="feature"
}

configure_existing_project() {
  info "Config"
  info "Project: $PROJECT_NAME"
  info "Main worktrees dir: $BASE_DIR"
  info "Default task branch prefix: $BRANCH_PREFIX"
  info "Press Enter to keep a current value. Type --clear at a setup prompt to remove it."
  printf '\n'

  CONFIG_BRANCH_CHANGE_REPOS=()
  CONFIG_BRANCH_CHANGE_OLD=()
  CONFIG_BRANCH_CHANGE_NEW=()
  CONFIG_BASE_DIR_OLD=""
  CONFIG_BASE_DIR_NEW=""

  old_base_dir=$BASE_DIR
  configure_project_settings

  printf '\n'
  info "Repositories"

  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    current_branch=$(repo_base_branch_at "$i")
    if [ -n "$CONFIG_BASE_DIR_OLD" ]; then
      base_path="$PROJECT_ROOT/$old_base_dir/$name"
      display_base_dir=$old_base_dir
    else
      base_path=$(base_repo_path "$name")
      display_base_dir=$BASE_DIR
    fi
    if [ -d "$base_path/.git" ] || [ -f "$base_path/.git" ]; then
      checked_out=$(git -C "$base_path" branch --show-current 2>/dev/null || printf '?')
      info "$display_base_dir/$name current branch: $checked_out"
    fi
    branch=$(prompt_with_default "Base repo branch for $name" "$current_branch")
    if [ "$branch" != "$current_branch" ]; then
      record_config_branch_change "$name" "$current_branch" "$branch"
    fi
    update_repo_base_branch "$name" "$branch"
    configure_repo_setup_prompt "$name"
    printf '\n'
    i=$((i + 1))
  done

  # `workbranch config` is repo-scoped for new setup prompts, but existing
  # project-level TASK_SETUP remains a supported add-time hook. Preserve it
  # unless a flow explicitly clears or migrates it.
}
