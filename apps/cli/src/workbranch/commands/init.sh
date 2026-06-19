cmd_init_interactive() {
  clone_after=${1:-yes}
  register_companion=${2:-yes}
  reset_config
  if color_enabled; then
    print_banner
  fi
  section "Create a new workbranch project"
  printf '
' >&2
  section "After workbranch"
  cat >&2 <<'AFTER'
    fullstack                     // workbranch project
    ├── .workbranch.config        // config
    ├── _base                     // main worktrees: _base
    │   ├── frontend              // - base frontend repo
    │   └── backend               // - base backend repo
    └── login                     // task workspace
        ├── frontend              // - task frontend repo
        ├── backend               // - task backend repo
        └── <work here>           // use AI Agents in here

    Result: branch operations stay grouped by feature workspace.
    Multi-repo bonus: use one directory for shared AI session context.
AFTER
  printf '
' >&2
  section "Setup guide"
  item_detail "Project name      directory name for this workbranch workspace"
  item_detail "Main worktrees    directory for each repo main worktree"
  item_detail "Repositories      Git repos included in each task workspace"
  printf '
' >&2
  prompt_read "[*] Press Enter to continue..." >/dev/null || true
  printf '

' >&2
  section "Project"
  target_dir_input=$(prompt_with_default "Target directory" ".")
  TARGET_DIR=$(expand_path "$target_dir_input")
  PROJECT_NAME=$(prompt_with_default "Project name" "fullstack")
  validate_safe_name "project" "$PROJECT_NAME"
  BASE_DIR=$(prompt_with_default "Main worktrees directory" "_base")
  validate_safe_name "MAIN_WORKTREES_DIR" "$BASE_DIR"
  BRANCH_PREFIX="feature"

  if [ "$clone_after" != "yes" ]; then
    printf '
' >&2
    configure_tool_prompts_if_macos
  fi

  printf '
' >&2
  section "Repositories"

  repo_number=1
  repo_branch_default="main"
  while :; do
    printf '
' >&2
    section "Repo #$repo_number"
    repo_name=$(prompt_required "Repository name")
    validate_safe_name "repo name" "$repo_name"
    repo_url=$(prompt_required "Git URL")
    validate_nonempty_no_space "git-url" "$repo_url"
    repo_branch=$(prompt_with_default "Base repo branch" "$repo_branch_default")
    add_repo_config "$repo_name" "$repo_url" "$repo_branch"
    configure_repo_setup_prompt "$repo_name"
    repo_branch_default=$repo_branch
    answer=$(prompt_read "[*] Add another repo? [y/N]: ") || answer=""
    case "$answer" in
      y|Y|yes|YES) repo_number=$((repo_number + 1)); continue ;;
      *) break ;;
    esac
  done

  printf '
' >&2
  section "Summary"
  info "Project: $PROJECT_NAME"
  info "Main worktrees dir: $BASE_DIR"
  if [ "$clone_after" != "yes" ]; then
    info "IDE:"
    if [ -n "$IDE_COMMAND" ]; then
      info "  $IDE_COMMAND"
    else
      info "  (none)"
    fi
    info "Terminal:"
    if [ -n "$TERMINAL_COMMAND" ]; then
      info "  $TERMINAL_COMMAND"
    else
      info "  (none)"
    fi
  fi
  info "Repositories:"
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    info "  - $(repo_name_at "$i") $(repo_url_at "$i") base repo branch=$(repo_base_branch_at "$i")"
    i=$((i + 1))
  done
  info "Task identity:"
  info "  - New tasks can be created with workbranch add."
  info "  - workbranch asks for task type and detail name, then derives folder type-detail."
  info "  - Each repo suggests a task branch from its base branch, and you can override it."
  printf '
' >&2
  if [ "$clone_after" = "yes" ]; then
    confirm_answer=$(prompt_read "[*] Create project now? [Y/n]: ")
  else
    confirm_answer=$(prompt_read "[*] Write config now? [Y/n]: ")
  fi
  case "$confirm_answer" in
    n|N|no|NO|cancel|CANCEL|c|C)
      info "Cancelled."
      return 0
      ;;
  esac
  printf '
' >&2
  if [ "$clone_after" = "yes" ]; then
    info "Creating project..."
  else
    info "Writing config..."
  fi

  PROJECT_ROOT="$TARGET_DIR/$PROJECT_NAME"
  [ ! -e "$PROJECT_ROOT" ] || die "project directory already exists: $PROJECT_ROOT"
  mkdir -p "$PROJECT_ROOT" || die "failed to create project directory: $PROJECT_ROOT"
  track_path "$PROJECT_ROOT"
  CONFIG_FILE="$PROJECT_ROOT/.workbranch.config"
  write_config "$CONFIG_FILE"
  if [ "$clone_after" = "yes" ]; then
    clone_base_repos
    success "Initialized workbranch project: $PROJECT_ROOT"
    if [ "$register_companion" = "yes" ]; then
      registry_add_root "$PROJECT_ROOT"
      if [ "${REGISTRY_ADD_ROOT_SKIPPED:-0}" != "1" ]; then
        info "Registered with companion: $PROJECT_ROOT"
      fi
    fi
    prompt_add_first_task_after_init || return 1
    prompt_language_config_after_init || return 1
    prompt_tool_config_after_init
  else
    success "Config written: $CONFIG_FILE"
  fi
}

prompt_add_first_task_after_init() {
  local answer status
  printf '\n' >&2
  answer=$(prompt_read "[*] Add your first task now? [Y/n]: ")
  status=$?
  if [ "$status" -ne 0 ]; then
    return 0
  fi
  case "$answer" in
    n|N|no|NO|cancel|CANCEL|c|C)
      info "Create one later with: workbranch add"
      return 0
      ;;
  esac

  (
    cd "$PROJECT_ROOT" || exit 1
    cmd_add
  )
}

prompt_language_config_after_init() {
  printf '
' >&2
  section "Generated task guidance"
  configure_preferred_language_prompt yes
  status=$?
  [ "$status" -ne 0 ] && [ "$status" -ne 2 ] && return "$status"
  write_config "$CONFIG_FILE"
}

prompt_tool_config_after_init() {
  local status
  printf '\n' >&2
  section "Tool config"
  if ! is_macos_platform; then
    info_skip_tool_prompts_for_platform
    return 0
  fi

  configure_ide_prompt yes
  status=$?
  [ "$status" -eq 2 ] && return 0

  configure_terminal_prompt yes
  status=$?
  [ "$status" -ne 0 ] && [ "$status" -ne 2 ] && return "$status"

  write_config "$CONFIG_FILE"
  success "Config updated: $CONFIG_FILE"
}

cmd_init() {
  register_companion=yes
  case "${1:-}" in
    "") ;;
    --no-companion) register_companion=no; shift ;;
    *) die "usage: workbranch init [--no-companion]" ;;
  esac
  [ $# -eq 0 ] || die "usage: workbranch init [--no-companion]"
  CREATED_PATHS=()
  CREATED_WORKTREES=()
  CREATED_WORKTREE_BASES=()
  CREATED_BRANCH_REPOS=()
  CREATED_BRANCH_NAMES=()
  if find_project_root; then
    if [ "$(basename "$CONFIG_FILE")" = ".workbranch.config" ]; then
      parse_config "$CONFIG_FILE"
      if all_configured_base_git_repos_exist; then
        printf '[-] Error: workbranch project already initialized: %s\n' "$PROJECT_ROOT" >&2
        printf '[*] To edit project settings: workbranch config\n' >&2
        exit 1
      fi
    elif [ "$(basename "$CONFIG_FILE")" = ".tasktree.config" ]; then
      parse_config_for_rewrite "$CONFIG_FILE"
    else
      parse_config_for_rewrite "$CONFIG_FILE"
    fi
    clone_base_repos
    success "Initialized workbranch project: $PROJECT_ROOT"
    if [ "$register_companion" = "yes" ]; then
      registry_add_root "$PROJECT_ROOT"
      if [ "${REGISTRY_ADD_ROOT_SKIPPED:-0}" != "1" ]; then
        info "Registered with companion: $PROJECT_ROOT"
      fi
    fi
  else
    cmd_init_interactive yes "$register_companion"
  fi
}

all_configured_base_git_repos_exist() {
  _init_i=0
  while [ $_init_i -lt ${#REPO_NAMES[@]} ]; do
    _init_name=$(repo_name_at "$_init_i")
    _init_target=$(base_repo_path "$_init_name")
    if [ ! -d "$_init_target/.git" ] && [ ! -f "$_init_target/.git" ]; then
      return 1
    fi
    _init_i=$((_init_i + 1))
  done
  return 0
}
