usage() {
  cat <<USAGE
Usage:
  workbranch <command> [args]
Workspace lifecycle:
  init              Initialize a workbranch project
  list              List configured repos and task workspaces
  config            Create or update .workbranch.config without cloning repos
  config --rewrite  Rewrite config to current format without prompts
  add <task>        Create a task workspace
  remove <task>     Remove task worktrees and local task branches
  resume <task>     Restore existing local or remote task branches
Branch workflow:
  status            Show commits, diff, and dirty state
  pull              Pull remote base branches into main worktrees
  push              Push base branches to origin
  push <task>       Push task branches to origin
  update            Update every task workspace from local base worktrees
  update --all      Update every task workspace from local base worktrees
  update <task>     Update one task workspace from local base worktrees
  land <task>       Land task branches into base branches
  Options:
    --repo <repo>   Limit branch workflow to one repo; otherwise all repos
Other:
  help              Show this help
  version           Show the installed workbranch version
  -v, --version     Show the installed workbranch version
USAGE
}
