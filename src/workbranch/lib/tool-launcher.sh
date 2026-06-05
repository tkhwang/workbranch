print_tool_preset() {
  number=$1
  name=$2
  command=$3
  if color_stderr_enabled; then
    printf '    %s) %s%s%s (%s)\n' "$number" "$WB_ERR_CYAN" "$name" "$WB_ERR_RESET" "$command" >&2
  else
    printf '    %s) %s (%s)\n' "$number" "$name" "$command" >&2
  fi
}

print_editor_presets() {
  info "Editor command:"
  print_tool_preset 1 "Cursor" 'open -na Cursor --args --new-window'
  print_tool_preset 2 "Antigravity IDE" 'open -na "Antigravity IDE" --args --new-window'
  print_tool_preset 3 "VS Code" 'open -na "Visual Studio Code" --args --new-window'
  print_tool_preset 4 "Windsurf" 'open -na Windsurf --args --new-window'
  print_tool_preset 5 "Zed" 'open -na Zed --args --new-window'
  printf '    6) Custom command\n' >&2
  printf '    7) Clear\n' >&2
}

editor_preset_command() {
  case "$1" in
    1) printf '%s' 'open -na Cursor --args --new-window' ;;
    2) printf '%s' 'open -na "Antigravity IDE" --args --new-window' ;;
    3) printf '%s' 'open -na "Visual Studio Code" --args --new-window' ;;
    4) printf '%s' 'open -na Windsurf --args --new-window' ;;
    5) printf '%s' 'open -na Zed --args --new-window' ;;
    *) return 1 ;;
  esac
}

print_terminal_presets() {
  info "Terminal command:"
  print_tool_preset 1 "Terminal.app" 'open -a Terminal'
  print_tool_preset 2 "iTerm2" 'open -a iTerm'
  print_tool_preset 3 "Warp" 'open -a Warp'
  print_tool_preset 4 "Ghostty" 'open -a Ghostty'
  print_tool_preset 5 "cmux" 'cmux'
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
  task_dir="$PROJECT_ROOT/$task"
  [ -d "$task_dir" ] || die "task workspace not found: $task"
  repo_path=$(task_repo_path "$task" "$repo")
  [ -d "$repo_path" ] || die "task repo not found: $task/$repo"
  is_registered_worktree_path "$repo_path" "$(base_repo_path "$repo")" \
    || die "task repo not found or not a registered worktree: $task/$repo"
  is_task_workspace_path "$task_dir" || die "task workspace not found: $task"
  RESOLVED_PATH=$(canonical_path "$repo_path") || die "task repo not found: $task/$repo"
}

run_tool_command() {
  tool_label=$1
  command=$2
  path=$3
  [ -n "$command" ] || die "$tool_label command is not configured; run workbranch config $tool_label"
  if [ "$tool_label" = "editor" ]; then
    case "$command" in
      'open -a "Visual Studio Code"'|'open -na "Visual Studio Code"') command='open -na "Visual Studio Code" --args --new-window' ;;
      'open -a Cursor'|'open -na Cursor'|'open -a "Cursor"'|'open -na "Cursor"') command='open -na Cursor --args --new-window' ;;
      'open -a "Antigravity IDE"'|'open -na "Antigravity IDE"') command='open -na "Antigravity IDE" --args --new-window' ;;
      'open -a Windsurf'|'open -na Windsurf'|'open -a "Windsurf"'|'open -na "Windsurf"') command='open -na Windsurf --args --new-window' ;;
      'open -a Zed'|'open -na Zed'|'open -a "Zed"'|'open -na "Zed"') command='open -na Zed --args --new-window' ;;
    esac
  fi
  (
    cd "$path" || exit 1
    WORKBRANCH_TOOL_PATH=$path
    export WORKBRANCH_TOOL_PATH
    sh -c "$command \"\$WORKBRANCH_TOOL_PATH\""
  )
}
