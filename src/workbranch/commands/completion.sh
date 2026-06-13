cmd_complete_tasks() {
  find_project_root || return 0
  parse_project_config 2>/dev/null || return 0
  for path in "$PROJECT_ROOT"/*; do
    is_task_workspace_path "$path" || continue
    printf '%s\n' "${path##*/}"
  done
}

cmd_complete_repos() {
  find_project_root || return 0
  parse_project_config 2>/dev/null || return 0
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    repo_name_at "$i"
    printf '\n'
    i=$((i + 1))
  done
}

cmd_complete_commands() {
  printf '%s\n' add completion config destroy doctor finalize finder help ide init land list memo noti path prune pull push refresh remove status terminal update version
}

print_completion_bash() {
  cat <<'BASH'
# bash completion for workbranch
_workbranch() {
  local cur prev cmd wb_bin words
  wb_bin=${WORKBRANCH:-workbranch}
  COMPREPLY=()
  cur=${COMP_WORDS[COMP_CWORD]:-}
  if [ "$COMP_CWORD" -gt 0 ]; then
    prev=${COMP_WORDS[COMP_CWORD-1]}
  else
    prev=
  fi
  cmd=${COMP_WORDS[1]:-}

  if [ "$COMP_CWORD" -eq 1 ]; then
    words=$($wb_bin __complete-commands 2>/dev/null || true)
    COMPREPLY=( $(compgen -W "$words" -- "$cur") )
    return 0
  fi

  case "$prev" in
    --repo)
      words=$($wb_bin __complete-repos 2>/dev/null || true)
      COMPREPLY=( $(compgen -W "$words" -- "$cur") )
      return 0
      ;;
    --from)
      return 0
      ;;
  esac

  if [ "$cmd" = "noti" ] && [ "$COMP_CWORD" -eq 2 ]; then
    words='add list clear'
    COMPREPLY=( $(compgen -W "$words" -- "$cur") )
    return 0
  fi
  if [ "$cmd" = "noti" ] && [ "$COMP_CWORD" -eq 3 ]; then
    words=$($wb_bin __complete-tasks 2>/dev/null || true)
    COMPREPLY=( $(compgen -W "$words" -- "$cur") )
    return 0
  fi

  case "$cur" in
    -*)
      case "$cmd" in
        add) words='--from' ;;
        list) words='--json --global' ;;
        memo) words='--clear' ;;
        config) words='--rewrite' ;;
        remove|destroy) words='--force' ;;
        doctor) words='--fix --repo' ;;
        update) words='--all --repo' ;;
        status|pull|push|land|finalize|refresh|path|finder|ide|terminal) words='--repo' ;;
        *) words='' ;;
      esac
      COMPREPLY=( $(compgen -W "$words" -- "$cur") )
      return 0
      ;;
  esac

  case "$cmd" in
    memo|remove|update|push|land|finalize|refresh|path|finder|ide|terminal)
      words=$($wb_bin __complete-tasks 2>/dev/null || true)
      COMPREPLY=( $(compgen -W "$words" -- "$cur") )
      return 0
      ;;
  esac

  return 0
}
complete -F _workbranch workbranch
BASH
}

print_completion_zsh() {
  cat <<'ZSH'
#compdef workbranch
# zsh completion for workbranch
_workbranch() {
  local -a commands tasks repos flags noti_commands
  local cmd prev cur wb_bin
  wb_bin=${WORKBRANCH:-workbranch}
  cur=${words[CURRENT]:-}
  prev=${words[CURRENT-1]:-}
  cmd=${words[2]:-}

  if (( CURRENT == 2 )); then
    commands=(${(f)"$($wb_bin __complete-commands 2>/dev/null)"})
    _describe 'workbranch command' commands
    return
  fi

  if [[ "$prev" == "--repo" ]]; then
    repos=(${(f)"$($wb_bin __complete-repos 2>/dev/null)"})
    _describe 'repo' repos
    return
  fi

  if [[ "$cmd" == "noti" && $CURRENT == 3 ]]; then
    noti_commands=(add list clear)
    _describe 'noti command' noti_commands
    return
  fi

  if [[ "$cmd" == "noti" && $CURRENT == 4 ]]; then
    tasks=(${(f)"$($wb_bin __complete-tasks 2>/dev/null)"})
    _describe 'task' tasks
    return
  fi

  if [[ "$cur" == -* ]]; then
    case "$cmd" in
      add) flags=(--from) ;;
      list) flags=(--json --global) ;;
      memo) flags=(--clear) ;;
      config) flags=(--rewrite) ;;
      remove|destroy) flags=(--force) ;;
      doctor) flags=(--fix --repo) ;;
      update) flags=(--all --repo) ;;
      status|pull|push|land|finalize|refresh|path|finder|ide|terminal) flags=(--repo) ;;
      *) flags=() ;;
    esac
    _describe 'option' flags
    return
  fi

  case "$cmd" in
    memo|remove|update|push|land|finalize|refresh|path|finder|ide|terminal)
      tasks=(${(f)"$($wb_bin __complete-tasks 2>/dev/null)"})
      _describe 'task' tasks
      return
      ;;
  esac
}
compdef _workbranch workbranch
ZSH
}

print_completion_fish() {
  cat <<'FISH'
# fish completion for workbranch
function __workbranch_bin
    if set -q WORKBRANCH
        echo $WORKBRANCH
    else
        echo workbranch
    end
end

function __workbranch_complete_commands
    (__workbranch_bin) __complete-commands 2>/dev/null
end

function __workbranch_complete_tasks
    (__workbranch_bin) __complete-tasks 2>/dev/null
end

function __workbranch_complete_repos
    (__workbranch_bin) __complete-repos 2>/dev/null
end

function __workbranch_seen_command
    set -l cmd $argv[1]
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2; and test $tokens[2] = $cmd
end

function __workbranch_completing_noti_subcommand
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2; and test $tokens[2] = noti; and test (count $tokens) -le 3
end

function __workbranch_completing_noti_task
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 3; and test $tokens[2] = noti; and contains -- $tokens[3] add list clear
end

function __workbranch_completing_command
    set -l tokens (commandline -opc)
    set -l current (commandline -ct)
    test (count $tokens) -le 1; and return 0
    test (count $tokens) -eq 2; and test -n "$current"
end

complete -c workbranch -f -n '__workbranch_completing_command' -a '(__workbranch_complete_commands)'
complete -c workbranch -f -n '__workbranch_seen_command update' -a '(__workbranch_complete_tasks)'
complete -c workbranch -f -n '__workbranch_seen_command memo' -a '(__workbranch_complete_tasks)'
complete -c workbranch -f -n '__workbranch_completing_noti_subcommand' -a 'add list clear'
complete -c workbranch -f -n '__workbranch_completing_noti_task' -a '(__workbranch_complete_tasks)'
complete -c workbranch -f -n '__workbranch_seen_command refresh' -a '(__workbranch_complete_tasks)'
complete -c workbranch -f -n '__workbranch_seen_command remove' -a '(__workbranch_complete_tasks)'
complete -c workbranch -f -n '__workbranch_seen_command push' -a '(__workbranch_complete_tasks)'
complete -c workbranch -f -n '__workbranch_seen_command land' -a '(__workbranch_complete_tasks)'
complete -c workbranch -f -n '__workbranch_seen_command finalize' -a '(__workbranch_complete_tasks)'
complete -c workbranch -f -n '__workbranch_seen_command path' -a '(__workbranch_complete_tasks)'
complete -c workbranch -f -n '__workbranch_seen_command finder' -a '(__workbranch_complete_tasks)'
complete -c workbranch -f -n '__workbranch_seen_command ide' -a '(__workbranch_complete_tasks)'
complete -c workbranch -f -n '__workbranch_seen_command terminal' -a '(__workbranch_complete_tasks)'
complete -c workbranch -f -n '__fish_seen_argument -l repo' -a '(__workbranch_complete_repos)'
complete -c workbranch -n '__workbranch_seen_command add' -l from -d 'Seed task branches from a source ref'
complete -c workbranch -n '__workbranch_seen_command list' -l json -d 'Print machine-readable JSON'
complete -c workbranch -n '__workbranch_seen_command list' -l global -d 'List every registered project'
complete -c workbranch -n '__workbranch_seen_command memo' -l clear -d 'Clear the task brief'
complete -c workbranch -n '__workbranch_seen_command config' -l rewrite -d 'Rewrite config to current format'
complete -c workbranch -n '__workbranch_seen_command remove' -l force -d 'Force removal'
complete -c workbranch -n '__workbranch_seen_command destroy' -l force -d 'Force destruction'
complete -c workbranch -n '__workbranch_seen_command doctor' -l fix -d 'Apply safe repairs'
complete -c workbranch -n '__workbranch_seen_command update' -l all -d 'Update every task workspace'
complete -c workbranch -n '__workbranch_seen_command update' -l repo -d 'Limit operation to one repo'
complete -c workbranch -n '__workbranch_seen_command status' -l repo -d 'Limit operation to one repo'
complete -c workbranch -n '__workbranch_seen_command pull' -l repo -d 'Limit operation to one repo'
complete -c workbranch -n '__workbranch_seen_command push' -l repo -d 'Limit operation to one repo'
complete -c workbranch -n '__workbranch_seen_command land' -l repo -d 'Limit operation to one repo'
complete -c workbranch -n '__workbranch_seen_command finalize' -l repo -d 'Limit operation to one repo'
complete -c workbranch -n '__workbranch_seen_command refresh' -l repo -d 'Limit operation to one repo'
complete -c workbranch -n '__workbranch_seen_command doctor' -l repo -d 'Limit operation to one repo'
complete -c workbranch -n '__workbranch_seen_command path' -l repo -d 'Limit operation to one repo'
complete -c workbranch -n '__workbranch_seen_command finder' -l repo -d 'Limit operation to one repo'
complete -c workbranch -n '__workbranch_seen_command ide' -l repo -d 'Limit operation to one repo'
complete -c workbranch -n '__workbranch_seen_command terminal' -l repo -d 'Limit operation to one repo'
FISH
}

cmd_completion() {
  [ $# -eq 1 ] || die "usage: workbranch completion <bash|zsh|fish>"
  case "$1" in
    bash) print_completion_bash ;;
    zsh) print_completion_zsh ;;
    fish) print_completion_fish ;;
    *) die "usage: workbranch completion <bash|zsh|fish>" ;;
  esac
}
