cmd_config() {
  rewrite_only=0
  config_target="all"
  case $# in
    0) ;;
    1)
      case "$1" in
        --rewrite) rewrite_only=1 ;;
        base) config_target="base" ;;
        ide) config_target="ide" ;;
        terminal) config_target="terminal" ;;
        language) config_target="language" ;;
        *) die "usage: workbranch config [base|ide|terminal|language|--rewrite]" ;;
      esac
      ;;
    *) die "usage: workbranch config [base|ide|terminal|language|--rewrite]" ;;
  esac
  case "$config_target" in
    ide|terminal) require_macos_tool_platform "config $config_target" ;;
    *) require_core_supported_platform ;;
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
      case "$config_target" in
        all) configure_existing_project ;;
        base) configure_base_branches ;;
        ide) configure_ide_prompt ;;
        terminal) configure_terminal_prompt ;;
        language) configure_preferred_language_prompt ;;
      esac
    fi
    if [ "$rewrite_only" -eq 0 ]; then
      case "$config_target" in
        all)
          if [ ${#CONFIG_BRANCH_CHANGE_REPOS[@]} -gt 0 ]; then
            apply_configured_base_branches changed
            CONFIG_BASE_BRANCHES_AUTO_APPLIED=1
          fi
          ;;
        base)
          if [ ${#CONFIG_BRANCH_CHANGE_REPOS[@]} -gt 0 ]; then
            apply_configured_base_branches changed
          else
            apply_configured_base_branches all
          fi
          ;;
      esac
    fi
    write_config "$CONFIG_FILE"
    if [ "$rewrite_only" -eq 1 ]; then
      success "Config rewritten: $CONFIG_FILE"
    else
      success "Config updated: $CONFIG_FILE"
      if [ "$config_target" = "all" ]; then
        print_config_next_steps
      fi
    fi
  else
    [ "$rewrite_only" -eq 0 ] || die "no enclosing workbranch project found"
    [ "$config_target" = "all" ] || die "no enclosing workbranch project found"
    cmd_init_interactive no
  fi
}

CONFIG_BRANCH_CHANGE_REPOS=()
CONFIG_BRANCH_CHANGE_OLD=()
CONFIG_BRANCH_CHANGE_NEW=()
CONFIG_BASE_DIR_OLD=""
CONFIG_BASE_DIR_NEW=""
CONFIG_BASE_BRANCHES_AUTO_APPLIED=0

record_config_branch_change() {
  name=$1
  old=$2
  new=$3
  CONFIG_BRANCH_CHANGE_REPOS[${#CONFIG_BRANCH_CHANGE_REPOS[@]}]=$name
  CONFIG_BRANCH_CHANGE_OLD[${#CONFIG_BRANCH_CHANGE_OLD[@]}]=$old
  CONFIG_BRANCH_CHANGE_NEW[${#CONFIG_BRANCH_CHANGE_NEW[@]}]=$new
}

config_repo_branch_changed() {
  local target config_change_i
  target=$1
  config_change_i=0
  while [ $config_change_i -lt ${#CONFIG_BRANCH_CHANGE_REPOS[@]} ]; do
    [ "${CONFIG_BRANCH_CHANGE_REPOS[$config_change_i]}" = "$target" ] && return 0
    config_change_i=$((config_change_i + 1))
  done
  return 1
}

print_config_next_steps() {
  if [ -n "$CONFIG_BASE_DIR_OLD" ]; then
    info "Main worktrees dir change was saved in config only."
    info "Existing cloned base worktrees were not moved automatically."
    printf '    %s -> %s\n' "$CONFIG_BASE_DIR_OLD" "$CONFIG_BASE_DIR_NEW" >&2
  fi

  [ ${#CONFIG_BRANCH_CHANGE_REPOS[@]} -gt 0 ] || return 0
  [ "$CONFIG_BASE_BRANCHES_AUTO_APPLIED" -eq 0 ] || return 0

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

# shellcheck disable=SC2120 # optional allow_eof argument is passed from init.sh in generated build
configure_ide_prompt() {
  allow_eof=${1:-no}
  print_ide_presets
  current=${IDE_COMMAND:-keep}
  if ! value=$(prompt_read "[*] Choose IDE [$current]: "); then
    [ "$allow_eof" = "yes" ] && return 2
    die "input aborted"
  fi
  case "$value" in
    "") ;;
    1|2|3|4|5|6|7) set_ide_command "$(ide_preset_command "$value")" ;;
    8)
      custom=$(prompt_required "Custom IDE command")
      set_ide_command "$custom"
      ;;
    9|--clear) clear_ide_command ;;
    *) die "invalid IDE choice: $value" ;;
  esac
}

# shellcheck disable=SC2120 # optional allow_eof argument is passed from init.sh in generated build
configure_terminal_prompt() {
  allow_eof=${1:-no}
  print_terminal_presets
  current=${TERMINAL_COMMAND:-keep}
  if ! value=$(prompt_read "[*] Choose terminal [$current]: "); then
    [ "$allow_eof" = "yes" ] && return 2
    die "input aborted"
  fi
  case "$value" in
    "") ;;
    1|2|3|4) set_terminal_command "$(terminal_preset_command "$value")" ;;
    5)
      custom=$(prompt_required "Custom terminal command")
      set_terminal_command "$custom"
      ;;
    6|--clear) clear_terminal_command ;;
    *) die "invalid terminal choice: $value" ;;
  esac
}

# shellcheck disable=SC2120 # optional allow_eof argument is passed from init.sh in generated build
configure_preferred_language_prompt() {
  allow_eof=${1:-no}
  info "Preferred language"
  current=$(preferred_language_label)
  if ! value=$(prompt_read "[*] Preferred language for generated task guidance [$current]: "); then
    [ "$allow_eof" = "yes" ] && return 2
    die "input aborted"
  fi
  normalized=$(normalize_preferred_language_choice "$value") || return 1
  set_preferred_language "$normalized"
}

configure_base_branches() {
  info "Base branches"
  CONFIG_BRANCH_CHANGE_REPOS=()
  CONFIG_BRANCH_CHANGE_OLD=()
  CONFIG_BRANCH_CHANGE_NEW=()
  CONFIG_BASE_DIR_OLD=""
  CONFIG_BASE_DIR_NEW=""

  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    current_branch=$(repo_base_branch_at "$i")
    base_path=$(base_repo_path "$name")
    if [ -d "$base_path/.git" ] || [ -f "$base_path/.git" ]; then
      checked_out=$(git -C "$base_path" branch --show-current 2>/dev/null || printf '?')
      info "$BASE_DIR/$name current branch: $checked_out"
    fi
    branch=$(prompt_with_default "Base repo branch for $name" "$current_branch")
    if [ "$branch" != "$current_branch" ]; then
      record_config_branch_change "$name" "$current_branch" "$branch"
    fi
    update_repo_base_branch "$name" "$branch"
    printf '\n'
    i=$((i + 1))
  done
}

apply_configured_base_branches() {
  local apply_scope
  apply_scope=${1:-all}
  reset_preflight
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    if [ "$apply_scope" = "changed" ] && ! config_repo_branch_changed "$name"; then
      i=$((i + 1))
      continue
    fi
    base_path=$(base_repo_path "$name")
    branch=$(repo_base_branch_at "$i")
    label="$BASE_DIR/$name"
    if [ ! -d "$base_path/.git" ] && [ ! -f "$base_path/.git" ]; then
      i=$((i + 1))
      continue
    fi
    preflight_require_clean "$label" "$base_path"
    preflight_require_no_rebase "$label" "$base_path"
    preflight_fetch_origin "$label" "$base_path"
    preflight_remote_branch_exists "$label" "$base_path" "$branch"
    preflight_pull_ref_fast_forwardable "$label" "$base_path" "$branch" "origin/$branch" "$branch" "origin/$branch"
    i=$((i + 1))
  done
  preflight_die_if_errors "config base"

  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    if [ "$apply_scope" = "changed" ] && ! config_repo_branch_changed "$name"; then
      i=$((i + 1))
      continue
    fi
    base_path=$(base_repo_path "$name")
    branch=$(repo_base_branch_at "$i")
    label="$BASE_DIR/$name"
    if [ ! -d "$base_path/.git" ] && [ ! -f "$base_path/.git" ]; then
      i=$((i + 1))
      continue
    fi
    checked_out=$(git -C "$base_path" branch --show-current 2>/dev/null || printf '')
    if [ "$checked_out" != "$branch" ]; then
      workbranch_git_checkout_base_branch "$name" "$base_path" "$branch"
    fi
    workbranch_git_pull_base "$name" "$base_path" "$branch"
    success "Base branch ready: $label -> $(color_branch_name "$branch")"
    i=$((i + 1))
  done
}

configure_tool_prompts_if_macos() {
  if is_macos_platform; then
    configure_ide_prompt
    configure_terminal_prompt
  else
    info_skip_tool_prompts_for_platform
  fi
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
  info "Legacy branch prefix: $BRANCH_PREFIX (kept for existing shorthand defaults)"
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
  configure_tool_prompts_if_macos

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
