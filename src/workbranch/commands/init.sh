cmd_init_interactive() {
  clone_after=${1:-yes}
  reset_config
  info "Create a new workbranch project"
  printf '
' >&2
  info "After workbranch"
  cat >&2 <<'AFTER'
    fullstack                     // workbranch project
    ├── .workbranch.config          // config
    ├── _base                     // main worktrees
    │   ├── frontend              // main worktree: frontend
    │   └── backend               // main worktree: backend
    └── login                     // task workspace
        ├── frontend              // linked worktree: frontend
        ├── backend               // linked worktree: backend
        └── <work here>           // cd login for this feature

    Result: branch operations stay grouped by feature workspace.
    Multi-repo bonus: use one directory for shared AI session context.
AFTER
  printf '
' >&2
  info "Setup guide"
  printf '    Project name      directory name for this workbranch workspace
' >&2
  printf '    Main worktrees    directory for each repo main worktree
' >&2
  printf '    Branch prefix     task branch prefix, e.g. feature/login
' >&2
  printf '    Repositories      Git repos included in each task workspace
' >&2
  printf '
[*] Press Enter to continue...' >&2
  IFS= read -r _continue || _continue=""
  printf '

' >&2
  info "Project"
  target_dir_input=$(prompt_with_default "Target directory" ".")
  TARGET_DIR=$(expand_path "$target_dir_input")
  PROJECT_NAME=$(prompt_with_default "Project name" "fullstack")
  validate_safe_name "project" "$PROJECT_NAME"
  BASE_DIR=$(prompt_with_default "Main worktrees directory" "_base")
  validate_safe_name "MAIN_WORKTREES_DIR" "$BASE_DIR"
  BRANCH_PREFIX=$(prompt_with_default "Branch prefix" "feature")
  validate_nonempty_no_space "branch_prefix" "$BRANCH_PREFIX"

  printf '
' >&2
  configure_editor_prompt
  configure_terminal_prompt

  printf '
' >&2
  info "Repositories"

  repo_number=1
  repo_branch_default="main"
  while :; do
    printf '
' >&2
    info "Repo #$repo_number"
    repo_name=$(prompt_required "Repository name")
    validate_safe_name "repo name" "$repo_name"
    repo_url=$(prompt_required "Git URL")
    validate_nonempty_no_space "git-url" "$repo_url"
    repo_branch=$(prompt_with_default "Base repo branch" "$repo_branch_default")
    add_repo_config "$repo_name" "$repo_url" "$repo_branch"
    configure_repo_setup_prompt "$repo_name"
    repo_branch_default=$repo_branch
    printf '[*] Add another repo? [y/N]: ' >&2
    IFS= read -r answer || answer=""
    case "$answer" in
      y|Y|yes|YES) repo_number=$((repo_number + 1)); continue ;;
      *) break ;;
    esac
  done

  printf '
' >&2
  configure_task_setup_prompt

  printf '
' >&2
  info "Summary"
  info "Project: $PROJECT_NAME"
  info "Main worktrees dir: $BASE_DIR"
  info "Branch prefix: $BRANCH_PREFIX"
  info "Editor:"
  if [ -n "$EDITOR_COMMAND" ]; then
    info "  $EDITOR_COMMAND"
  else
    info "  (none)"
  fi
  info "Terminal:"
  if [ -n "$TERMINAL_COMMAND" ]; then
    info "  $TERMINAL_COMMAND"
  else
    info "  (none)"
  fi
  info "Task setup:"
  if [ -n "$TASK_SETUP" ]; then
    info "  $TASK_SETUP"
  else
    info "  (none)"
  fi
  info "Repositories:"
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    info "  - $(repo_name_at "$i") $(repo_url_at "$i") base repo branch=$(repo_base_branch_at "$i")"
    i=$((i + 1))
  done
  info "Branch policy:"
  info "  - [base repo] main        -> task1 -> [task repo] ${BRANCH_PREFIX}/task1"
  info "  - [base repo] ${BRANCH_PREFIX}/XXX -> task1 -> [task repo] ${BRANCH_PREFIX}/XXX-task1"
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base_branch=$(repo_base_branch_at "$i")
    if [ "$base_branch" = "$BRANCH_PREFIX" ] || [ "${base_branch#"$BRANCH_PREFIX"/}" != "$base_branch" ]; then
      task_example="${base_branch}-<task>"
    else
      task_example="${BRANCH_PREFIX}/<task>"
    fi
    info "  - $name: base=$base_branch task=$task_example"
    i=$((i + 1))
  done
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
  else
    success "Config written: $CONFIG_FILE"
  fi
}

cmd_init() {
  [ $# -eq 0 ] || die "usage: workbranch init"
  CREATED_PATHS=()
  CREATED_WORKTREES=()
  CREATED_WORKTREE_BASES=()
  CREATED_BRANCH_REPOS=()
  CREATED_BRANCH_NAMES=()
  if find_project_root; then
    if [ "$(basename "$CONFIG_FILE")" = ".workbranch.config" ]; then
      parse_config "$CONFIG_FILE"
    elif [ "$(basename "$CONFIG_FILE")" = ".tasktree.config" ]; then
      parse_config_for_rewrite "$CONFIG_FILE"
    else
      parse_config_for_rewrite "$CONFIG_FILE"
    fi
    clone_base_repos
    success "Initialized workbranch project: $PROJECT_ROOT"
  else
    cmd_init_interactive yes
  fi
}
