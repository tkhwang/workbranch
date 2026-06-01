cmd_config() {
  [ $# -eq 0 ] || die "usage: workbranch config"
  CREATED_PATHS=()
  CREATED_WORKTREES=()
  CREATED_WORKTREE_BASES=()
  CREATED_BRANCH_REPOS=()
  CREATED_BRANCH_NAMES=()
  if find_project_root; then
    parse_config_for_rewrite "$CONFIG_FILE"
    CONFIG_FILE="$PROJECT_ROOT/.workbranch.config"
    write_config "$CONFIG_FILE"
    success "Config rewritten: $CONFIG_FILE"
  else
    cmd_init_interactive no
  fi
}
