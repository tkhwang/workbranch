is_git_dirty() {
  local path status
  path=$1
  [ -d "$path" ] || return 1
  status=$(git -C "$path" status --porcelain 2>/dev/null) || return 1
  [ -n "$status" ]
}

ensure_clean_worktree() {
  local path
  path=$1
  if is_git_dirty "$path"; then
    die "dirty worktree: $path"
  fi
}

reset_preflight() {
  PREFLIGHT_ERRORS=()
}

preflight_error() {
  PREFLIGHT_ERRORS[${#PREFLIGHT_ERRORS[@]}]=$1
}

preflight_die_if_errors() {
  local operation i
  operation=$1
  if [ ${#PREFLIGHT_ERRORS[@]} -eq 0 ]; then
    return 0
  fi

  printf '[-] Error: Cannot %s: preflight failed\n' "$operation" >&2
  printf '[*] Fix these worktrees, then retry:\n' >&2
  i=0
  while [ $i -lt ${#PREFLIGHT_ERRORS[@]} ]; do
    printf '    %s\n' "${PREFLIGHT_ERRORS[$i]}" >&2
    i=$((i + 1))
  done
  exit 1
}

git_dir_for_path() {
  local path git_dir
  path=$1
  git_dir=$(git -C "$path" rev-parse --git-dir 2>/dev/null) || return 1
  case "$git_dir" in
    /*) printf '%s' "$git_dir" ;;
    *) printf '%s/%s' "$path" "$git_dir" ;;
  esac
}

is_rebase_in_progress() {
  local path git_dir
  path=$1
  git_dir=$(git_dir_for_path "$path") || return 1
  [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]
}

preflight_require_clean() {
  local label path
  label=$1
  path=$2
  if is_git_dirty "$path"; then
    preflight_error "$label dirty worktree"
  fi
}

preflight_require_no_rebase() {
  local label path
  label=$1
  path=$2
  if is_rebase_in_progress "$path"; then
    preflight_error "$label rebase in progress"
  fi
}

preflight_require_current_branch() {
  local label path expected actual
  label=$1
  path=$2
  expected=$3
  actual=$(branch_or_unknown "$path")
  if [ "$actual" != "$expected" ]; then
    preflight_error "$label expected branch $expected, got $actual"
  fi
}

git_ref_exists() {
  local path ref
  path=$1
  ref=$2
  git -C "$path" rev-parse --verify --quiet "$ref^{commit}" >/dev/null 2>&1
}

git_is_ancestor() {
  local path ancestor descendant
  path=$1
  ancestor=$2
  descendant=$3
  git -C "$path" merge-base --is-ancestor "$ancestor" "$descendant" >/dev/null 2>&1
}

preflight_fetch_origin() {
  local label path
  label=$1
  path=$2
  git -C "$path" fetch origin >/dev/null 2>&1 || preflight_error "$label failed to fetch origin"
}

preflight_remote_branch_exists() {
  local label path branch
  label=$1
  path=$2
  branch=$3
  git_ref_exists "$path" "origin/$branch" || preflight_error "$label missing remote origin/$branch"
}

preflight_pull_fast_forwardable() {
  local label path branch remote
  label=$1
  path=$2
  branch=$3
  remote="origin/$branch"
  git_ref_exists "$path" "$remote" || return 0
  if git_is_ancestor "$path" HEAD "$remote" || git_is_ancestor "$path" "$remote" HEAD; then
    return 0
  fi
  preflight_error "$label cannot fast-forward pull: HEAD and $remote diverged"
}

preflight_push_fast_forwardable() {
  local label path branch remote
  label=$1
  path=$2
  branch=$3
  remote="origin/$branch"
  git_ref_exists "$path" "$remote" || return 0
  if git_is_ancestor "$path" "$remote" "$branch"; then
    return 0
  fi
  preflight_error "$label cannot fast-forward push: $remote has commits not in $branch"
}

preflight_land_fast_forwardable() {
  local label path base_branch task_branch remote base_ref
  label=$1
  path=$2
  base_branch=$3
  task_branch=$4
  remote="origin/$base_branch"
  git_ref_exists "$path" "$remote" || return 0
  if git_is_ancestor "$path" HEAD "$remote"; then
    base_ref=$remote
  elif git_is_ancestor "$path" "$remote" HEAD; then
    base_ref=HEAD
  else
    preflight_error "$label cannot fast-forward pull: HEAD and $remote diverged"
    return 0
  fi

  if git_is_ancestor "$path" "$base_ref" "$task_branch"; then
    return 0
  fi
  preflight_error "$label cannot fast-forward land; run workbranch update ${label%%/*} --repo ${label#*/} first"
}

branch_exists() {
  local repo_path branch
  repo_path=$1
  branch=$2
  git -C "$repo_path" show-ref --verify --quiet "refs/heads/$branch"
}

ensure_current_branch() {
  local path expected actual
  path=$1
  expected=$2
  actual=$(branch_or_unknown "$path")
  [ "$actual" = "$expected" ] || die "unexpected branch in $path: expected $expected, got $actual"
}

require_task_repos_clean() {
  task=$1
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    path=$(task_repo_path "$task" "$name")
    if [ -d "$path" ]; then
      ensure_clean_worktree "$path"
    fi
    i=$((i + 1))
  done
}
