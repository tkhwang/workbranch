cmd_sync() {
  require_project
  parse_repo_option "$@"
  [ ${#ARGS[@]} -eq 0 ] || die "usage: workbranch sync [--repo <repo>]"
  collect_update_all_tasks
  preflight_update_all_tasks
  section "Pulling base branches"
  run_pull
  printf '\n'
  section "Updating task workspaces"
  execute_update_all_tasks
}
