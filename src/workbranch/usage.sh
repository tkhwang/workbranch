usage() {
  cat <<USAGE
Usage:
  workbranch <command> [args]
Workspace:
  init              Initialize a workbranch project
  list              List configured repos and task workspaces
  config            Create or rewrite .workbranch.config without cloning repos
  setup             Add or change task setup command
  setup --clear     Remove task setup command
  add <task>        Create a task workspace
  setup <task>      Run task setup for existing task workspace
  remove <task>     Remove task worktrees without deleting branches
Git:
  status            Show commits, diff, and dirty state
  // vertical
  pull              Pull remote base branches into main worktrees
  push              Push base branches to origin
  push <task>       Push task branches to origin
  // horizontal
  update            Update every task workspace from local base worktrees
  update --all      Update every task workspace from local base worktrees
  update <task>     Update one task workspace from local base worktrees
  land <task>       Land task branches into base branches
  // common
  --repo <repo>     Limit operation to one repo; otherwise all repos
Other:
  help              Show this help
USAGE
}
