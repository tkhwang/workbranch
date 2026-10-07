# -----------------------------------------------------------------------------
# Branch-scoped stash
# -----------------------------------------------------------------------------
# Git keeps refs/stash in the common git directory, so every worktree of a repo
# shares one stash list and a bare `git stash pop` can take another worktree's
# entry. workbranch stash builds the same stash-shaped commit (HEAD, index,
# optional untracked parent) without touching refs/stash and stores it under
# refs/workbranch/stash/<branch>, one slot per branch.

WORKBRANCH_STASH_REF_PREFIX=refs/workbranch/stash

cmd_stash_usage() {
  die "usage: workbranch stash [push [-m <message>]] | pop [--index] | apply [--index] | show [-p] | drop | list  (pop/apply/show/drop accept --branch <branch>)"
}

stash_require_repo() {
  STASH_TOP=$(git rev-parse --show-toplevel 2>/dev/null) || die "workbranch stash must run inside a git worktree"
}

stash_current_branch() {
  local branch
  branch=$(git -C "$STASH_TOP" symbolic-ref --short -q HEAD) || die "detached HEAD; check out a branch before using workbranch stash"
  printf '%s' "$branch"
}

stash_ref_for_branch() {
  git check-ref-format --branch "$1" >/dev/null 2>&1 || die "invalid branch name: $1"
  printf '%s/%s' "$WORKBRANCH_STASH_REF_PREFIX" "$1"
}

stash_saved_commit() {
  git -C "$STASH_TOP" rev-parse -q --verify "$1^{commit}" 2>/dev/null
}

stash_require_no_operation_in_progress() {
  local git_dir
  git_dir=$(git_dir_for_path "$STASH_TOP") || die "failed to resolve git dir: $STASH_TOP"
  if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ] || [ -f "$git_dir/MERGE_HEAD" ] || [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then
    die "a rebase, merge, or cherry-pick is in progress in $STASH_TOP; finish or abort it first"
  fi
}

stash_has_untracked() {
  [ -n "$(git -C "$STASH_TOP" ls-files --others --exclude-standard | head -n 1)" ]
}

# Build a parentless commit holding the untracked (non-ignored) files, in the
# same shape `git stash push -u` uses for its third parent.
stash_create_untracked_commit() {
  local branch tmp_dir tree commit
  branch=$1
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/workbranch-stash.XXXXXX") || return 1
  if ! git -C "$STASH_TOP" ls-files -z --others --exclude-standard |
    (cd "$STASH_TOP" && GIT_INDEX_FILE="$tmp_dir/index" git update-index -z --add --remove --stdin); then
    rm -rf "$tmp_dir"
    return 1
  fi
  tree=$(cd "$STASH_TOP" && GIT_INDEX_FILE="$tmp_dir/index" git write-tree) || { rm -rf "$tmp_dir"; return 1; }
  rm -rf "$tmp_dir"
  commit=$(printf 'untracked files on %s\n' "$branch" | git -C "$STASH_TOP" commit-tree "$tree") || return 1
  printf '%s' "$commit"
}

# Remove exactly the untracked files captured in the stash, plus directories
# left empty by that removal. Files created after the capture stay untouched.
stash_remove_captured_untracked() {
  local untracked path dir
  untracked=$1
  git -C "$STASH_TOP" ls-tree -r -z --name-only "$untracked" |
    while IFS= read -r -d '' path; do
      rm -f -- "$STASH_TOP/$path"
      dir=${path%/*}
      while [ "$dir" != "$path" ] && [ -n "$dir" ]; do
        rmdir -- "$STASH_TOP/$dir" 2>/dev/null || break
        case "$dir" in
          */*) dir=${dir%/*} ;;
          *) break ;;
        esac
      done
    done
}

cmd_stash_push() {
  local message branch ref head existing tracked untracked index_commit final subject short
  message=
  while [ $# -gt 0 ]; do
    case "$1" in
      -m|--message)
        [ $# -ge 2 ] || cmd_stash_usage
        message=$2
        shift 2
        ;;
      *) cmd_stash_usage ;;
    esac
  done

  branch=$(stash_current_branch) || exit 1
  ref=$(stash_ref_for_branch "$branch") || exit 1
  stash_require_no_operation_in_progress
  head=$(git -C "$STASH_TOP" rev-parse -q --verify HEAD) || die "branch '$branch' has no commits yet"

  if existing=$(stash_saved_commit "$ref"); then
    die "branch '$branch' already has a workbranch stash ($(git -C "$STASH_TOP" rev-parse --short "$existing")); run workbranch stash pop or drop first"
  fi

  if [ -n "$message" ]; then
    tracked=$(cd "$STASH_TOP" && git stash create "$message") || die "failed to create stash commit in $STASH_TOP"
  else
    tracked=$(cd "$STASH_TOP" && git stash create) || die "failed to create stash commit in $STASH_TOP"
  fi

  untracked=
  if stash_has_untracked; then
    untracked=$(stash_create_untracked_commit "$branch") || die "failed to capture untracked files in $STASH_TOP"
  fi

  if [ -z "$tracked" ] && [ -z "$untracked" ]; then
    info "No local changes to save on $branch"
    return 0
  fi

  if [ -z "$tracked" ]; then
    subject=$(git -C "$STASH_TOP" log -1 --format='%h %s' "$head")
    index_commit=$(printf 'index on %s: %s\n' "$branch" "$subject" | git -C "$STASH_TOP" commit-tree "$head^{tree}" -p "$head") ||
      die "failed to create stash commit in $STASH_TOP"
    if [ -n "$message" ]; then
      subject="On $branch: $message"
    else
      subject="WIP on $branch: $subject"
    fi
    final=$(printf '%s\n' "$subject" | git -C "$STASH_TOP" commit-tree "$head^{tree}" -p "$head" -p "$index_commit" -p "$untracked") ||
      die "failed to create stash commit in $STASH_TOP"
  elif [ -n "$untracked" ]; then
    final=$(git -C "$STASH_TOP" log -1 --format=%B "$tracked" |
      git -C "$STASH_TOP" commit-tree "$tracked^{tree}" -p "$tracked^1" -p "$tracked^2" -p "$untracked") ||
      die "failed to create stash commit in $STASH_TOP"
  else
    final=$tracked
  fi

  # Empty old value: fail instead of overwriting a slot created concurrently.
  git -C "$STASH_TOP" update-ref -m "workbranch stash push" "$ref" "$final" "" ||
    die "failed to save workbranch stash for branch '$branch'"

  git -C "$STASH_TOP" reset --hard -q || die "saved $final but failed to reset $STASH_TOP; restore with: workbranch stash apply"
  if [ -n "$untracked" ]; then
    stash_remove_captured_untracked "$untracked"
  fi

  short=$(git -C "$STASH_TOP" rev-parse --short "$final")
  success "Saved local changes on $branch as $short"
  printf '    restore with: workbranch stash pop\n'
}

stash_resolve_target() {
  local branch
  branch=
  STASH_INDEX_FLAG=
  STASH_SHOW_ARGS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch)
        [ $# -ge 2 ] || cmd_stash_usage
        branch=$2
        shift 2
        ;;
      --index)
        [ "$STASH_SUBCMD" = "pop" ] || [ "$STASH_SUBCMD" = "apply" ] || cmd_stash_usage
        STASH_INDEX_FLAG=--index
        shift
        ;;
      -p|--patch|--stat|-u|--include-untracked)
        [ "$STASH_SUBCMD" = "show" ] || cmd_stash_usage
        STASH_SHOW_ARGS[${#STASH_SHOW_ARGS[@]}]=$1
        shift
        ;;
      *) cmd_stash_usage ;;
    esac
  done
  [ -n "$branch" ] || branch=$(stash_current_branch) || exit 1
  STASH_BRANCH=$branch
  STASH_REF=$(stash_ref_for_branch "$branch") || exit 1
  STASH_COMMIT=$(stash_saved_commit "$STASH_REF") || die "no workbranch stash for branch '$branch'"
}

cmd_stash_restore() {
  local short
  stash_require_no_operation_in_progress
  short=$(git -C "$STASH_TOP" rev-parse --short "$STASH_COMMIT")
  info "Restoring $short from $STASH_BRANCH"
  if ! (cd "$STASH_TOP" && git stash apply $STASH_INDEX_FLAG "$STASH_COMMIT"); then
    die "failed to restore $short cleanly; the stash is kept. Resolve the changes, then run: $(stash_drop_hint)"
  fi
  if [ "$STASH_SUBCMD" = "pop" ]; then
    git -C "$STASH_TOP" update-ref -d "$STASH_REF" "$STASH_COMMIT" ||
      die "restored $short but failed to drop $STASH_REF"
    success "Restored and dropped $short ($STASH_COMMIT)"
  else
    success "Restored $short; stash kept for $STASH_BRANCH"
  fi
}

stash_drop_hint() {
  if [ "$STASH_BRANCH" = "$(git -C "$STASH_TOP" symbolic-ref --short -q HEAD || true)" ]; then
    printf 'workbranch stash drop'
  else
    printf 'workbranch stash drop --branch %s' "$STASH_BRANCH"
  fi
}

cmd_stash_drop() {
  git -C "$STASH_TOP" update-ref -d "$STASH_REF" "$STASH_COMMIT" || die "failed to drop $STASH_REF"
  success "Dropped workbranch stash for $STASH_BRANCH ($STASH_COMMIT)"
}

cmd_stash_list() {
  local current branch rest marker found
  [ $# -eq 0 ] || cmd_stash_usage
  current=$(git -C "$STASH_TOP" symbolic-ref --short -q HEAD || true)
  found=0
  while IFS=$'\t' read -r branch rest; do
    [ -n "$branch" ] || continue
    found=1
    marker=' '
    [ "$branch" = "$current" ] && marker='*'
    printf '%s %s\t%s\n' "$marker" "$(color_branch_name "$branch")" "$rest"
  done <<EOF
$(git -C "$STASH_TOP" for-each-ref --sort=-committerdate \
    --format='%(refname:lstrip=3)%09%(objectname:short)%09%(committerdate:relative)%09%(subject)' \
    "$WORKBRANCH_STASH_REF_PREFIX/")
EOF
  [ "$found" -eq 1 ] || info "No workbranch stashes"
}

cmd_stash() {
  stash_require_repo
  STASH_SUBCMD=${1:-push}
  case "$STASH_SUBCMD" in
    -*) STASH_SUBCMD=push ;;
    *) [ $# -eq 0 ] || shift ;;
  esac
  case "$STASH_SUBCMD" in
    push|save) cmd_stash_push "$@" ;;
    pop|apply)
      stash_resolve_target "$@"
      cmd_stash_restore
      ;;
    show)
      stash_resolve_target "$@"
      (cd "$STASH_TOP" && git stash show ${STASH_SHOW_ARGS[@]+"${STASH_SHOW_ARGS[@]}"} "$STASH_COMMIT")
      ;;
    drop)
      stash_resolve_target "$@"
      cmd_stash_drop
      ;;
    list) cmd_stash_list "$@" ;;
    *) cmd_stash_usage ;;
  esac
}
