usage() {
  cat <<USAGE
Usage:
  workbranch <command> [args]
Workspace:
  init              Initialize a workbranch project
  list              List configured repos and task workspaces
  add <task>        Create a task workspace
  remove <task>     Remove task worktrees and local task branches
Git:
  status            Show commits, diff, and dirty state
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
  editor <task>     Open task repo worktrees in the configured editor
  terminal <task>   Open task repo worktrees in the configured terminal
Config:
  config            Create or update .workbranch.config without cloning repos
  config editor     Update only the configured editor command
  config terminal   Update only the configured terminal command
  config --rewrite  Rewrite config to current format without prompts
Other:
  help              Show this help
  -v, --version     Show the installed workbranch version
  version           Show the installed workbranch version
USAGE
}
