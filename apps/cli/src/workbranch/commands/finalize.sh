cmd_finalize() {
  require_project
  parse_repo_option "$@"
  [ ${#ARGS[@]} -eq 1 ] || die "usage: workbranch finalize <task> [--repo <repo>]"
  task=$(normalize_task_argument "${ARGS[0]}")
  validate_task_folder_name "$task"

  reset_preflight
  preflight_pull_repos
  preflight_update_task "$task"
  preflight_die_if_errors "finalize"

  section "Pulling base branches"
  execute_pull_repos
  printf '\n'

  reset_preflight
  preflight_update_task "$task"
  preflight_die_if_errors "finalize"

  section "Updating task workspace"
  update_task "$task"
  printf '\n'

  reset_preflight
  preflight_land_task "$task"
  preflight_die_if_errors "finalize"

  section "Landing task"
  execute_land_task "$task" finalize
}
