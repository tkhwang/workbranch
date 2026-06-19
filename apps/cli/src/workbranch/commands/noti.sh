cmd_noti_usage() { die "usage: workbranch noti <add|list|clear> <task> [text]"; }

cmd_noti() {
  local subcmd task text file dir ts escaped
  require_project
  [ $# -ge 2 ] || cmd_noti_usage
  subcmd=$1
  task=$(normalize_task_argument "$2")
  require_known_task_workspace noti "$task"
  file=$(task_noti_path "$task")
  case "$subcmd" in
    add)
      [ $# -eq 3 ] || cmd_noti_usage
      text=$3
      dir=$(dirname "$file")
      mkdir -p "$dir" || die "failed to create task notifications directory: $task"
      ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      escaped=$(printf '%s' "$text" | json_escape)
      printf '{"ts":"%s","text":"%s"}\n' "$ts" "$escaped" >> "$file" || die "failed to append task notification: $task"
      ;;
    list)
      [ $# -eq 2 ] || cmd_noti_usage
      [ -f "$file" ] || return 0
      sed -n 's/^.*,"text":"\(.*\)"}$/\1/p' "$file" | json_unescape
      ;;
    clear)
      [ $# -eq 2 ] || cmd_noti_usage
      dir=$(dirname "$file")
      mkdir -p "$dir" || die "failed to create task notifications directory: $task"
      : > "$file" || die "failed to clear task notifications: $task"
      ;;
    *)
      cmd_noti_usage
      ;;
  esac
}
