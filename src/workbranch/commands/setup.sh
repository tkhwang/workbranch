cmd_setup() {
  require_project
  case $# in
    0)
      value=$(prompt_read "[*] Task setup command [$TASK_SETUP]: ")
      if [ -n "$value" ]; then
        TASK_SETUP=$value
      fi
      CONFIG_FILE="$PROJECT_ROOT/.workbranch.config"
      write_config "$CONFIG_FILE"
      if [ -n "$TASK_SETUP" ]; then
        success "Task setup command: $TASK_SETUP"
      else
        success "Task setup command: (none)"
      fi
      ;;
    1)
      case "$1" in
        --clear)
          TASK_SETUP=""
          CONFIG_FILE="$PROJECT_ROOT/.workbranch.config"
          write_config "$CONFIG_FILE"
          success "Task setup command removed"
          ;;
        *)
          task=$1
          validate_safe_name "task" "$task"
          info "Running task setup: $TASK_SETUP"
          run_task_setup "$task" || die "task setup failed: $TASK_SETUP"
          success "Task setup completed: $task"
          ;;
      esac
      ;;
    *)
      die "usage: workbranch setup [task|--clear]"
      ;;
  esac
}
