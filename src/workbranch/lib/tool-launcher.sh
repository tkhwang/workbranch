print_editor_presets() {
  info "Editor command:"
  printf '    1) VS Code (open -a "Visual Studio Code")\n' >&2
  printf '    2) Cursor (open -a Cursor)\n' >&2
  printf '    3) Antigravity IDE (open -a "Antigravity IDE")\n' >&2
  printf '    4) Custom command\n' >&2
  printf '    5) Clear\n' >&2
}

editor_preset_command() {
  case "$1" in
    1) printf '%s' 'open -a "Visual Studio Code"' ;;
    2) printf '%s' 'open -a Cursor' ;;
    3) printf '%s' 'open -a "Antigravity IDE"' ;;
    *) return 1 ;;
  esac
}

print_terminal_presets() {
  info "Terminal command:"
  printf '    1) Terminal.app (open -a Terminal)\n' >&2
  printf '    2) iTerm2 (open -a iTerm)\n' >&2
  printf '    3) Warp (open -a Warp)\n' >&2
  printf '    4) Ghostty (open -a Ghostty)\n' >&2
  printf '    5) cmux (cmux)\n' >&2
  printf '    6) Custom command\n' >&2
  printf '    7) Clear\n' >&2
}

terminal_preset_command() {
  case "$1" in
    1) printf '%s' 'open -a Terminal' ;;
    2) printf '%s' 'open -a iTerm' ;;
    3) printf '%s' 'open -a Warp' ;;
    4) printf '%s' 'open -a Ghostty' ;;
    5) printf '%s' 'cmux' ;;
    *) return 1 ;;
  esac
}

canonical_path() {
  path=$1
  (cd "$path" 2>/dev/null && pwd -P) || return 1
}

resolve_task_path() {
  task=$1
  task_dir="$PROJECT_ROOT/$task"
  is_task_workspace_path "$task_dir" || die "task workspace not found: $task"
  RESOLVED_PATH=$(canonical_path "$task_dir") || die "task workspace not found: $task"
}

resolve_task_repo_path() {
  task=$1
  repo=$2
  repo_path=$(task_repo_path "$task" "$repo")
  [ -d "$repo_path" ] || die "task repo not found: $task/$repo"
  RESOLVED_PATH=$(canonical_path "$repo_path") || die "task repo not found: $task/$repo"
}

run_tool_command() {
  tool_label=$1
  command=$2
  path=$3
  [ -n "$command" ] || die "$tool_label command is not configured; run workbranch config $tool_label"
  (
    cd "$path" || exit 1
    WORKBRANCH_TOOL_PATH=$path
    export WORKBRANCH_TOOL_PATH
    sh -c "$command \"\$WORKBRANCH_TOOL_PATH\""
  )
}
