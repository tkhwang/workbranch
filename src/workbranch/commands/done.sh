cmd_done() {
  require_project
  [ $# -eq 1 ] || die "usage: workbranch done <task>"
  task=$(normalize_task_argument "$1")
  require_known_task_workspace "done" "$task"
  archive_current_plan "$task" "done"
}
