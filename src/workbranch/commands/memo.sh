cmd_memo_usage() { die "usage: workbranch memo [<task>] [text|--clear]"; }

cmd_memo() {
  local task text file current_task
  require_project

  case $# in
    0)
      task=$(resolve_current_task_from_cwd) || cmd_memo_usage
      file=$(task_brief_path "$task")
      [ -f "$file" ] || return 0
      cat "$file"
      return 0
      ;;
    1)
      if [ "$1" = "--clear" ]; then
        task=$(resolve_current_task_from_cwd) || cmd_memo_usage
        rm -f "$(task_brief_path "$task")" || die "failed to clear task brief: $task"
        return 0
      fi
      if current_task=$(resolve_current_task_from_cwd); then
        text=$1
        file=$(task_brief_path "$current_task")
        printf '%s\n' "$text" > "$file" || die "failed to write task brief: $current_task"
        return 0
      fi
      task=$(normalize_task_argument "$1")
      require_known_task_workspace memo "$task"
      file=$(task_brief_path "$task")
      [ -f "$file" ] || return 0
      cat "$file"
      return 0
      ;;
    2)
      task=$(normalize_task_argument "$1")
      require_known_task_workspace memo "$task"
      if [ "$2" = "--clear" ]; then
        rm -f "$(task_brief_path "$task")" || die "failed to clear task brief: $task"
        return 0
      fi
      text=$2
      file=$(task_brief_path "$task")
      printf '%s\n' "$text" > "$file" || die "failed to write task brief: $task"
      return 0
      ;;
    *)
      cmd_memo_usage
      ;;
  esac
}
