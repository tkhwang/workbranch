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

print_ide_presets() {
  info "IDE command:"
  print_tool_preset 1 "Cursor" 'open -na Cursor --args --new-window'
  print_tool_preset 2 "Antigravity" 'open -na "Antigravity IDE" --args --new-window'
  print_tool_preset 3 "Windsurf" 'open -na Windsurf --args --new-window'
  print_tool_preset 4 "Zed" 'open -na Zed'
  print_tool_preset 5 "Sublime Text" 'open -na "Sublime Text"'
  print_tool_preset 6 "Xcode" 'open -na Xcode'
  print_tool_preset 7 "VS Code" 'open -na "Visual Studio Code" --args --new-window'
  printf '    8) Custom command\n' >&2
  printf '    9) Clear\n' >&2
}

ide_preset_command() {
  case "$1" in
    1) printf '%s' 'open -na Cursor --args --new-window' ;;
    2) printf '%s' 'open -na "Antigravity IDE" --args --new-window' ;;
    3) printf '%s' 'open -na Windsurf --args --new-window' ;;
    4) printf '%s' 'open -na Zed' ;;
    5) printf '%s' 'open -na "Sublime Text"' ;;
    6) printf '%s' 'open -na Xcode' ;;
    7) printf '%s' 'open -na "Visual Studio Code" --args --new-window' ;;
    *) return 1 ;;
  esac
}

print_terminal_presets() {
  info "Terminal command:"
  print_tool_preset 1 "iTerm" 'open -a iTerm'
  print_tool_preset 2 "Warp" 'open -a Warp'
  print_tool_preset 3 "Terminal.app" 'open -a Terminal'
  print_tool_preset 4 "Ghostty" 'open -a Ghostty'
  printf '    5) Custom command\n' >&2
  printf '    6) Clear\n' >&2
}

terminal_preset_command() {
  case "$1" in
    1) printf '%s' 'open -a iTerm' ;;
    2) printf '%s' 'open -a Warp' ;;
    3) printf '%s' 'open -a Terminal' ;;
    4) printf '%s' 'open -a Ghostty' ;;
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
  case "$tool_label" in
    ide)
      case "$command" in
        'open -a "Visual Studio Code"'|'open -na "Visual Studio Code"') command='open -na "Visual Studio Code" --args --new-window' ;;
        'open -a Cursor'|'open -na Cursor'|'open -a "Cursor"'|'open -na "Cursor"') command='open -na Cursor --args --new-window' ;;
        'open -a "Antigravity IDE"'|'open -na "Antigravity IDE"') command='open -na "Antigravity IDE" --args --new-window' ;;
        'open -a Windsurf'|'open -na Windsurf'|'open -a "Windsurf"'|'open -na "Windsurf"') command='open -na Windsurf --args --new-window' ;;
      esac
      ;;
  esac
  (
    cd "$path" || exit 1
    WORKBRANCH_TOOL_PATH=$path
    export WORKBRANCH_TOOL_PATH
    sh -c "$command \"\$WORKBRANCH_TOOL_PATH\""
  )
}

run_finder_command() {
  path=$1
  (
    # Keep cwd aligned with the opened absolute path so tests can observe it via fake open.
    cd "$path" || exit 1
    open "$path"
  )
}
