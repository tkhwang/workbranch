print_banner() {
  printf '%s' "$WB_PURPLE_BOLD"
  cat <<'BANNER'
__        __         _    _                         _
\ \      / /__  _ __| | _| |__  _ __ __ _ _ __   ___| |__
 \ \ /\ / / _ \| '__| |/ / '_ \| '__/ _` | '_ \ / __| '_ \
  \ V  V / (_) | |  |   <| |_) | | | (_| | | | | (__| | | |
   \_/\_/ \___/|_|  |_|\_\_.__/|_|  \__,_|_| |_|\___|_| |_|
BANNER
  printf '%s' "$WB_RESET"
  printf '\n'
  printf '%s                       Task-based Git worktrees, made easy.%s\n' "$WB_GRAY" "$WB_RESET"
}

usage_plain() {
  cat <<USAGE
Usage:
  workbranch <command> [args]
Workspace:
  init              Initialize a workbranch project
  list              List configured repos and task workspaces
  add [<task>] [--from <ref>]  Create a task workspace
  remove <task>     Remove task worktrees and local task branches
Git:
  status            Show remote diff, task diff, and dirty state
  vertical
  pull              Pull remote base branches into main worktrees
  push              Push base branches to origin
  push <task>       Push task branches to origin
  horizontal
  update            Update every task workspace from local base worktrees
  update --all      Update every task workspace from local base worktrees
  update <task>     Update one task workspace from local base worktrees
  land <task>       Land task branches into base branches
  common
  --repo <repo>     Limit operation to one repo; otherwise all repos
Tool:
  path <task>       Print a task workspace path
  finder <task>     Open a task workspace in Finder
  ide <task>        Open task repo worktrees in the configured IDE
  terminal <task>   Open task repo worktrees in the configured terminal
Config:
  config            Create or update .workbranch.config without cloning repos
  config ide        Update only the configured IDE command
  config terminal   Update only the configured terminal command
  config --rewrite  Rewrite config to current format without prompts
Completion:
  completion <shell>   Print a shell completion script (bash, zsh, fish)
Other:
  help              Show this help
  -v, --version     Show the installed workbranch version
  version           Show the installed workbranch version
USAGE
}

usage_enhanced() {
  print_banner
  printf '\n%sUsage:%s\n' "$WB_BOLD" "$WB_RESET"
  printf '  workbranch <command> [args]\n'
  section "Workspace"
  printf '  init              Initialize a workbranch project\n'
  printf '  list              List configured repos and task workspaces\n'
  printf '  add [<task>] [--from <ref>]  Create a task workspace\n'
  printf '  remove <task>     Remove task worktrees and local task branches\n'
  section "Git"
  printf '  status            Show remote diff, task diff, and dirty state\n'
  printf '%s  vertical%s\n' "$WB_GRAY" "$WB_RESET"
  printf '  pull              Pull remote base branches into main worktrees\n'
  printf '  push              Push base branches to origin\n'
  printf '  push <task>       Push task branches to origin\n'
  printf '%s  horizontal%s\n' "$WB_GRAY" "$WB_RESET"
  printf '  update            Update every task workspace from local base worktrees\n'
  printf '  update --all      Update every task workspace from local base worktrees\n'
  printf '  update <task>     Update one task workspace from local base worktrees\n'
  printf '  land <task>       Land task branches into base branches\n'
  printf '%s  common%s\n' "$WB_GRAY" "$WB_RESET"
  printf '  --repo <repo>     Limit operation to one repo; otherwise all repos\n'
  section "Tool"
  printf '  path <task>       Print a task workspace path\n'
  printf '  finder <task>     Open a task workspace in Finder\n'
  printf '  ide <task>        Open task repo worktrees in the configured IDE\n'
  printf '  terminal <task>   Open task repo worktrees in the configured terminal\n'
  section "Config"
  printf '  config            Create or update .workbranch.config without cloning repos\n'
  printf '  config ide        Update only the configured IDE command\n'
  printf '  config terminal   Update only the configured terminal command\n'
  printf '  config --rewrite  Rewrite config to current format without prompts\n'
  section "Completion"
  printf '  completion <shell>   Print a shell completion script (bash, zsh, fish)\n'
  section "Other"
  printf '  help              Show this help\n'
  printf '  -v, --version     Show the installed workbranch version\n'
  printf '  version           Show the installed workbranch version\n'
}

usage() {
  if color_enabled; then
    usage_enhanced
  else
    usage_plain
  fi
}
