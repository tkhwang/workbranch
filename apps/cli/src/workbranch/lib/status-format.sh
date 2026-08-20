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
  counts=$(commit_diff_counts "$path" "$base_commit") || { printf '?'; return 0; }
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

commit_diff_counts() {
  path=$1
  base_commit=$2
  [ -d "$path" ] || return 1
  case "$base_commit" in
    missing|\?) return 1 ;;
  esac
  git -C "$path" rev-list --left-right --count "$base_commit...HEAD" 2>/dev/null
}

last_commit_record() {
  path=$1
  [ -d "$path" ] || return 1
  git -C "$path" log -1 --format='%ct%x1f%s' 2>/dev/null
}

remote_diff_label() {
  path=$1
  branch=$2
  [ -d "$path" ] || { printf 'missing'; return 0; }
  remote_ref="refs/remotes/origin/$branch"
  remote_commit=$(git -C "$path" rev-parse --verify --quiet "$remote_ref^{commit}" 2>/dev/null) || {
    printf 'missing'
    return 0
  }
  commit_diff_label "$path" "$remote_commit"
}

next_action_for_base_remote() {
  diff_label=$1
  case "$diff_label" in
    0) printf '-' ;;
    +*) printf 'push' ;;
    -*) printf 'pull' ;;
    ±*) printf 'check' ;;
    *) printf 'check' ;;
  esac
}

next_action_for_diff() {
  diff_label=$1
  case "$diff_label" in
    0) printf '-' ;;
    +*) printf 'land' ;;
    -*) printf 'update' ;;
    ±*) printf 'update -> land' ;;
    *) printf 'check' ;;
  esac
}

print_base_status_header() {
  printf '    %s %s %s %s %s %s\n' \
    "$(table_header 11 repo)" \
    "$(table_header 16 branch)" \
    "$(table_header 10 commit)" \
    "$(table_header 7 remote)" \
    "$(table_header 9 status)" \
    "$(color_text "$WB_GRAY" next)"
}

print_base_status_item() {
  name=$1
  branch=$2
  commit=$3
  remote_diff=$4
  state=$5
  next_action=$6
  printf '    %s %s %-10s %s %s %s\n' \
    "$(color_repo_cell 11 "$name")" \
    "$(color_branch_cell 16 "$branch")" \
    "$commit" \
    "$(color_cell "$(color_diff "$remote_diff")" 7 "$remote_diff")" \
    "$(color_cell "$(color_status "$state")" 9 "$state")" \
    "$(color_text "$(color_next_action "$next_action")" "$next_action")"
}

print_task_status_header() {
  printf '    %s %s %s %s %s %s\n' \
    "$(table_header 11 repo)" \
    "$(table_header 10 base)" \
    "$(table_header 10 task)" \
    "$(table_header 5 diff)" \
    "$(table_header 9 status)" \
    "$(color_text "$WB_GRAY" next)"
}

print_task_status_item() {
  name=$1
  base_commit=$2
  task_commit=$3
  diff_label=$4
  state=$5
  next_action=$6
  printf '    %s %-10s %-10s %s %s %s\n' \
    "$(color_repo_cell 11 "$name")" \
    "$base_commit" \
    "$task_commit" \
    "$(color_cell "$(color_diff "$diff_label")" 5 "$diff_label")" \
    "$(color_cell "$(color_status "$state")" 9 "$state")" \
    "$(color_text "$(color_next_action "$next_action")" "$next_action")"
}

print_next_legend() {
  show_base=${1:-0}
  show_task=${2:-0}
  section "Next"
  if [ "$show_base" -eq 1 ]; then
    item_detail "pull    base is behind remote: workbranch pull"
    item_detail "push    base has commits not in remote: workbranch push"
  fi
  if [ "$show_task" -eq 1 ]; then
    item_detail "land    task has commits not in base: workbranch land <task>"
    item_detail "update  task is behind base: workbranch update <task>"
  fi
}

is_task_workspace_path() {
  local path i name
  path=$1
  is_task_shaped_directory_path "$path" || return 1

  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    is_registered_worktree_path "$path/$name" "$(base_repo_path "$name")" || return 1
    i=$((i + 1))
  done
  return 0
}

is_task_shaped_directory_path() {
  local path dir_name i name
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

is_registered_worktree_path() {
  local path base_path path_real worktree_paths old_ifs worktree_path worktree_real
  path=$1
  base_path=$2
  [ -d "$path" ] || return 1
  git -C "$path" rev-parse --git-dir >/dev/null 2>&1 || return 1
  [ -d "$base_path/.git" ] || [ -f "$base_path/.git" ] || return 1
  path_real=$(cd "$path" && pwd -P) || return 1
  worktree_paths=$(git -C "$base_path" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p') || return 1
  old_ifs=$IFS
  IFS='
'
  for worktree_path in $worktree_paths; do
    if [ -d "$worktree_path" ]; then
      worktree_real=$(cd "$worktree_path" && pwd -P) || worktree_real=$worktree_path
    else
      worktree_real=$worktree_path
    fi
    if [ "$worktree_real" = "$path_real" ]; then
      IFS=$old_ifs
      return 0
    fi
  done
  IFS=$old_ifs
  return 1
}


doctor_task_candidate_path() {
  local path dir_name i name
  path=$1
  [ -d "$path" ] || return 1
  dir_name=${path##*/}
  [ "$dir_name" = "$BASE_DIR" ] && return 1
  case "$dir_name" in .*) return 1 ;; esac
  [ -f "$path/.workbranch.task" ] && return 0
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    [ -e "$path/$name" ] && return 0
    i=$((i + 1))
  done
  return 1
}

doctor_prunable_worktree_count() {
  local base_path count
  base_path=$1
  [ -d "$base_path/.git" ] || [ -f "$base_path/.git" ] || { printf '0'; return 0; }
  count=$(git -C "$base_path" worktree list --porcelain 2>/dev/null | grep -c '^prunable' || true)
  printf '%s' "$count"
}

is_stale_task_directory_path() {
  local path
  path=$1
  is_task_shaped_directory_path "$path" || return 1
  is_task_workspace_path "$path" && return 1
  return 0
}

preflight_stale_task_directory_removal() {
  local task force i name base branch label
  task=$1
  force=${2:-0}
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base=$(base_repo_path "$name")
    branch=$(metadata_task_branch_for_repo "$name") || branch=$(repo_task_branch_at "$i" "$task")
    label="$task/$name"
    if [ ! -d "$base/.git" ] && [ ! -f "$base/.git" ]; then
      preflight_error "$BASE_DIR/$name missing git repo"
    elif [ "$force" -ne 1 ]; then
      preflight_require_task_branch_safe_to_delete "$label" "$base" "$branch" "$task"
    fi
    i=$((i + 1))
  done
}

remove_stale_task_directory_path() {
  local task_dir force task i name path base branch
  task_dir=$1
  force=${2:-0}
  task=${task_dir##*/}
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    path="$task_dir/$name"
    base=$(base_repo_path "$name")
    branch=$(metadata_task_branch_for_repo "$name") || branch=$(repo_task_branch_at "$i" "$task")
    if [ -d "$path" ]; then
      if [ "$force" -eq 1 ]; then
        git -C "$base" worktree remove --force "$path" >/dev/null 2>&1 || true
      else
        git -C "$base" worktree remove "$path" >/dev/null 2>&1 || true
      fi
    fi
    workbranch_git_delete_task_branch "$base" "$branch" "$force" || return 1
    i=$((i + 1))
  done
  rm -rf "$task_dir" || return 1
  success "Removed stale task directory: $task"
}
