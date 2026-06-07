cmd_path() {
  require_project
  parse_repo_option "$@"
  [ ${#ARGS[@]} -eq 1 ] || die "usage: workbranch path <task> [--repo <repo>]"
  task=$(normalize_task_argument "${ARGS[0]}")
  validate_task_folder_name "$task"

  # Keep stdout path-only: do not call info/success in this command.
  if [ -n "$FILTER_REPO" ]; then
    resolve_task_repo_path "$task" "$FILTER_REPO"
  else
    resolve_task_path "$task"
  fi
  printf '%s\n' "$RESOLVED_PATH"
}
