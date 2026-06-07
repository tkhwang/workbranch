cmd_refresh() {
  require_project
  parse_repo_option "$@"
  [ ${#ARGS[@]} -le 1 ] || die "usage: workbranch refresh [task] [--repo <repo>]"
  if [ ${#ARGS[@]} -eq 1 ]; then
    task=$(normalize_task_argument "${ARGS[0]}")
    validate_task_folder_name "$task"
    reset_preflight
    preflight_update_task "$task"
    preflight_die_if_errors "update"
  else
    collect_update_all_tasks
    preflight_update_all_tasks
    preflight_die_if_errors "update"
  fi
  section "Pulling base branches"
  run_pull
  printf '\n'
  if [ ${#ARGS[@]} -eq 1 ]; then
    section "Updating task workspace"
    update_task "$task"
  else
    section "Updating task workspaces"
    execute_update_all_tasks
  fi
}
