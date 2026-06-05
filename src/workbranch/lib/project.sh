find_project_root() {
  dir=$(pwd -P)
  while :; do
    if [ -f "$dir/.workbranch.config" ]; then
      PROJECT_ROOT=$dir
      CONFIG_FILE="$dir/.workbranch.config"
      CONFIG_TYPE=workbranch
      return 0
    fi
    if [ -f "$dir/.tasktree.config" ]; then
      PROJECT_ROOT=$dir
      CONFIG_FILE="$dir/.tasktree.config"
      CONFIG_TYPE=legacy
      return 0
    fi
    if [ -f "$dir/.monotree.config" ]; then
      PROJECT_ROOT=$dir
      CONFIG_FILE="$dir/.monotree.config"
      CONFIG_TYPE=legacy
      return 0
    fi
    [ "$dir" = "/" ] && return 1
    dir=$(dirname "$dir")
  done
}

parse_project_config() {
  case "$CONFIG_TYPE" in
    workbranch) parse_config "$CONFIG_FILE" ;;
    legacy) parse_config_for_rewrite "$CONFIG_FILE" ;;
    *) die "unknown config type for: $CONFIG_FILE" ;;
  esac
}

require_project() {
  find_project_root || die "not inside a workbranch project (missing .workbranch.config)"
  parse_project_config
}

base_repo_path() { printf '%s/%s/%s' "$PROJECT_ROOT" "$BASE_DIR" "$1"; }

task_repo_path() { printf '%s/%s/%s' "$PROJECT_ROOT" "$1" "$2"; }

default_branch_prefix() {
  if [ -n "$BRANCH_PREFIX" ]; then
    printf '%s' "$BRANCH_PREFIX"
  else
    printf 'feature'
  fi
}

default_feature_branch_for_task() { printf '%s/%s' "$(default_branch_prefix)" "$1"; }

base_prefixed_branch_for_task() {
  local parent task
  parent=$1
  task=$2
  printf '%s-%s' "$parent" "$task"
}

base_branch_looks_like_parent_task_branch() {
  local base_branch prefix
  base_branch=$1
  prefix=$(default_branch_prefix)
  case "$base_branch" in
    feature/*|feat/*) return 0 ;;
    "$prefix"/*) return 0 ;;
    *) return 1 ;;
  esac
}

default_repo_task_branch_at() {
  local index task base_branch
  index=$1
  task=$2
  base_branch=$(repo_base_branch_at "$index")
  if base_branch_looks_like_parent_task_branch "$base_branch"; then
    base_prefixed_branch_for_task "$base_branch" "$task"
  else
    default_feature_branch_for_task "$task"
  fi
}

registered_task_branch_at() {
  local index task name base target line match branch
  index=$1
  task=$2
  name=$(repo_name_at "$index")
  base=$(base_repo_path "$name")
  target=$(task_repo_path "$task" "$name")
  [ -d "$base/.git" ] || [ -f "$base/.git" ] || return 1

  match=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      worktree\ *)
        if [ "${line#worktree }" = "$target" ]; then
          match=1
        else
          match=0
        fi
        ;;
      branch\ refs/heads/*)
        if [ "$match" -eq 1 ]; then
          branch=${line#branch refs/heads/}
          [ -n "$branch" ] || return 1
          printf '%s' "$branch"
          return 0
        fi
        ;;
      "")
        match=0
        ;;
    esac
  done <<EOF_WORKTREE_LIST
$(git -C "$base" worktree list --porcelain 2>/dev/null || true)
EOF_WORKTREE_LIST
  return 1
}

repo_task_branch_at() {
  local index task name path current
  index=$1
  task=$2
  name=$(repo_name_at "$index")
  load_task_metadata "$task"
  if metadata_task_branch_for_repo "$name"; then
    return 0
  fi
  path=$(task_repo_path "$task" "$name")
  if [ -d "$path/.git" ] || [ -f "$path/.git" ]; then
    current=$(git -C "$path" branch --show-current 2>/dev/null || printf '')
    if [ -n "$current" ]; then
      printf '%s' "$current"
      return 0
    fi
  fi
  if registered_task_branch_at "$index" "$task"; then
    return 0
  fi
  default_repo_task_branch_at "$index" "$task"
}

clone_base_repos() {
  base_root="$PROJECT_ROOT/$BASE_DIR"
  if [ ! -e "$base_root" ]; then
    mkdir -p "$base_root" || fail_with_rollback "failed to create base directory: $base_root"
    track_path "$base_root"
  else
    [ -d "$base_root" ] || die "base path exists but is not a directory: $base_root"
  fi
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    url=$(repo_url_at "$i")
    branch=$(repo_base_branch_at "$i")
    target=$(base_repo_path "$name")
    if [ -d "$target" ]; then
      git -C "$target" rev-parse --git-dir >/dev/null 2>&1 || die "base repo path exists but is not a git repo: $BASE_DIR/$name"
      info "Base repo exists: $BASE_DIR/$name"
    elif [ -e "$target" ] || [ -L "$target" ]; then
      die "base repo path exists but is not a directory: $BASE_DIR/$name"
    else
      clone_output=$(git clone --branch "$branch" "$url" "$target" 2>&1)
      clone_status=$?
      if [ $clone_status -ne 0 ]; then
        fail_with_rollback "failed to clone repo '$name' from $url branch $branch
$clone_output"
      fi
      track_path "$target"
      success "Cloned: $BASE_DIR/$name"
    fi
    i=$((i + 1))
  done
}
