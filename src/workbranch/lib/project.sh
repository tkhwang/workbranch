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

feature_branch_for_task() { printf '%s/%s' "$BRANCH_PREFIX" "$1"; }

base_prefixed_branch_for_task() {
  parent=$1
  task=$2
  printf '%s-%s' "$parent" "$task"
}

repo_task_branch_at() {
  index=$1
  task=$2
  base_branch=$(repo_base_branch_at "$index")
  case "$base_branch" in
    "$BRANCH_PREFIX"/*) base_prefixed_branch_for_task "$base_branch" "$task" ;;
    *) feature_branch_for_task "$task" ;;
  esac
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
    if [ -e "$target" ]; then
      git -C "$target" rev-parse --git-dir >/dev/null 2>&1 || die "base repo path exists but is not a git repo: $BASE_DIR/$name"
      info "Base repo exists: $BASE_DIR/$name"
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
