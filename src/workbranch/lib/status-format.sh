branch_or_unknown() {
  path=$1
  if [ -d "$path" ]; then
    git -C "$path" branch --show-current 2>/dev/null || printf '?'
  else
    printf 'missing'
  fi
}

worktree_status_label() {
  path=$1
  [ -d "$path" ] || { printf 'missing'; return 0; }
  status=$(git -C "$path" status --porcelain 2>/dev/null) || { printf 'missing'; return 0; }
  [ -n "$status" ] || { printf 'clean'; return 0; }

  modified=0
  untracked=0
  old_ifs=$IFS
  IFS='
'
  for line in $status; do
    case "$line" in
      \?\?\ *) untracked=1 ;;
      *) modified=1 ;;
    esac
  done
  IFS=$old_ifs

  if [ $modified -eq 1 ] && [ $untracked -eq 1 ]; then
    printf 'modified, untracked'
  elif [ $modified -eq 1 ]; then
    printf 'modified'
  else
    printf 'untracked'
  fi
}

head_commit_short() {
  path=$1
  [ -d "$path" ] || { printf 'missing'; return 0; }
  git -C "$path" rev-parse --short=9 HEAD 2>/dev/null || printf '?'
}

head_commit_full() {
  path=$1
  [ -d "$path" ] || { printf 'missing'; return 0; }
  git -C "$path" rev-parse HEAD 2>/dev/null || printf '?'
}

commit_diff_label() {
  path=$1
  base_commit=$2
  [ -d "$path" ] || { printf 'missing'; return 0; }
  case "$base_commit" in
    missing|\?) printf '?' ; return 0 ;;
  esac

  counts=$(git -C "$path" rev-list --left-right --count "$base_commit...HEAD" 2>/dev/null) || { printf '?'; return 0; }
  set -- $counts
  left=${1:-0}
  right=${2:-0}

  if [ "$left" = 0 ] && [ "$right" = 0 ]; then
    printf '0'
  elif [ "$left" = 0 ]; then
    printf '+%s' "$right"
  elif [ "$right" = 0 ]; then
    printf -- '-%s' "$left"
  else
    printf '±%s/%s' "$left" "$right"
  fi
}

next_action_for_diff() {
  diff_label=$1
  case "$diff_label" in
    0) printf '-' ;;
    +*) printf 'land' ;;
    -*) printf 'update' ;;
    ±*) printf 'update' ;;
    *) printf 'check' ;;
  esac
}

print_base_status_header() {
  printf '    %-11s %-16s %-10s %s\n' "repo" "branch" "commit" "status"
}

print_base_status_item() {
  name=$1
  branch=$2
  commit=$3
  state=$4
  printf '    %-11s %-16s %-10s %s\n' "$name" "$branch" "$commit" "$state"
}

print_task_status_header() {
  printf '    %-11s %-10s %-10s %-5s %-9s %s\n' "repo" "base" "task" "diff" "status" "next"
}

print_task_status_item() {
  name=$1
  base_commit=$2
  task_commit=$3
  diff_label=$4
  state=$5
  next_action=$6
  printf '    %-11s %-10s %-10s %-5s %-9s %s\n' "$name" "$base_commit" "$task_commit" "$diff_label" "$state" "$next_action"
}

print_next_legend() {
  cat <<'LEGEND'
[*] Next
    land    task has commits not in base: workbranch land <task>
    update  task is behind base: workbranch update <task>
LEGEND
}

is_task_workspace_path() {
  path=$1
  [ -d "$path" ] || return 1
  dir_name=${path##*/}
  [ "$dir_name" = "$BASE_DIR" ] && return 1
  case "$dir_name" in .*) return 1 ;; esac

  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    [ -d "$path/$name" ] || return 1
    i=$((i + 1))
  done
  return 0
}
