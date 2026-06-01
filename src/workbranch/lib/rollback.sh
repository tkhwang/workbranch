rollback_created() {
  # Remove command-created worktrees first, then command-created branches, then plain paths.
  i=$((${#CREATED_WORKTREES[@]} - 1))
  while [ $i -ge 0 ]; do
    wt=${CREATED_WORKTREES[$i]}
    if [ -e "$wt" ]; then
      base=${CREATED_WORKTREE_BASES[$i]}
      git -C "$base" worktree remove "$wt" >/dev/null 2>&1 || rm -rf "$wt"
    fi
    i=$((i - 1))
  done

  i=$((${#CREATED_BRANCH_REPOS[@]} - 1))
  while [ $i -ge 0 ]; do
    repo=${CREATED_BRANCH_REPOS[$i]}
    branch=${CREATED_BRANCH_NAMES[$i]}
    if [ -d "$repo/.git" ] && branch_exists "$repo" "$branch"; then
      git -C "$repo" branch -D "$branch" >/dev/null 2>&1 || true
    fi
    i=$((i - 1))
  done

  i=$((${#CREATED_PATHS[@]} - 1))
  while [ $i -ge 0 ]; do
    path=${CREATED_PATHS[$i]}
    [ -e "$path" ] && rm -rf "$path"
    i=$((i - 1))
  done
}

fail_with_rollback() {
  msg=$1
  rollback_created
  die "$msg"
}

track_path() { CREATED_PATHS[${#CREATED_PATHS[@]}]=$1; }

track_worktree() {
  CREATED_WORKTREES[${#CREATED_WORKTREES[@]}]=$1
  CREATED_WORKTREE_BASES[${#CREATED_WORKTREE_BASES[@]}]=$2
}

track_branch() {
  CREATED_BRANCH_REPOS[${#CREATED_BRANCH_REPOS[@]}]=$1
  CREATED_BRANCH_NAMES[${#CREATED_BRANCH_NAMES[@]}]=$2
}
