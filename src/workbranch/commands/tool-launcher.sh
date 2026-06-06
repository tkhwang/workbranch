cmd_tool_launcher() {
  tool_label=$1
  shift
  require_macos_tool_platform "$tool_label"
  require_project
  case "$tool_label" in
    ide) command=$IDE_COMMAND ;;
    terminal) command=$TERMINAL_COMMAND ;;
    *) die "unknown tool launcher: $tool_label" ;;
  esac
  display_label=$tool_label
  case "$tool_label" in
    ide) display_label="IDE" ;;
  esac
  parse_repo_option "$@"
  [ ${#ARGS[@]} -eq 1 ] || die "usage: workbranch $tool_label <task> [--repo <repo>]"
  task=${ARGS[0]}
  validate_safe_name "task" "$task"

  if [ -n "$FILTER_REPO" ]; then
    resolve_task_repo_path "$task" "$FILTER_REPO"
    path=$RESOLVED_PATH
    info_tool_opening "$display_label" "$task/$FILTER_REPO"
    run_tool_command "$tool_label" "$command" "$path" || die "failed to open $tool_label: $task/$FILTER_REPO"
    return 0
  fi

  resolve_task_path "$task"
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    resolve_task_repo_path "$task" "$name"
    path=$RESOLVED_PATH
    info_tool_opening "$display_label" "$task/$name"
    run_tool_command "$tool_label" "$command" "$path" || die "failed to open $tool_label: $task/$name"
    i=$((i + 1))
  done
}

cmd_ide() {
  cmd_tool_launcher ide "$@"
}

cmd_terminal() {
  cmd_tool_launcher terminal "$@"
}

cmd_finder() {
  require_macos_tool_platform finder
  require_project
  parse_repo_option "$@"
  [ ${#ARGS[@]} -eq 1 ] || die "usage: workbranch finder <task> [--repo <repo>]"
  task=${ARGS[0]}
  validate_safe_name "task" "$task"

  if [ -n "$FILTER_REPO" ]; then
    resolve_task_repo_path "$task" "$FILTER_REPO"
    path=$RESOLVED_PATH
    info_tool_opening "Finder" "$task/$FILTER_REPO"
    run_finder_command "$path" || die "failed to open Finder: $task/$FILTER_REPO"
    return 0
  fi

  resolve_task_path "$task"
  path=$RESOLVED_PATH
  info_tool_opening "Finder" "$task"
  run_finder_command "$path" || die "failed to open Finder: $task"
}
