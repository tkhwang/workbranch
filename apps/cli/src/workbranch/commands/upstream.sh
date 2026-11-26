# Remove --from <ref> from ARGS (left by parse_repo_option) and record it.
parse_upstream_from_option() {
  local remaining arg want_value
  UPSTREAM_FROM_REF=""
  remaining=()
  want_value=0
  for arg in ${ARGS[@]+"${ARGS[@]}"}; do
    if [ "$want_value" -eq 1 ]; then
      [ -n "$arg" ] || die "missing value for --from"
      UPSTREAM_FROM_REF=$arg
      want_value=0
      continue
    fi
    case "$arg" in
      --from)
        want_value=1
        ;;
      --from=*)
        UPSTREAM_FROM_REF=${arg#--from=}
        [ -n "$UPSTREAM_FROM_REF" ] || die "missing value for --from"
        ;;
      *)
        remaining[${#remaining[@]}]=$arg
        ;;
    esac
  done
  [ "$want_value" -eq 0 ] || die "missing value for --from"
  ARGS=(${remaining[@]+"${remaining[@]}"})
  if [ -n "$UPSTREAM_FROM_REF" ]; then
    validate_nonempty_no_space "source ref" "$UPSTREAM_FROM_REF"
  fi
}

# Print the remote-tracking ref of origin's default branch in full, such as
# refs/remotes/origin/master. The remote is asked first: a fetch keeps an
# existing origin/HEAD, so the cached ref goes stale when origin's default
# branch changes. origin/HEAD is the fallback for a remote that does not
# report where its HEAD points; a failed query never falls back to it.
upstream_default_ref() {
  local base ref branch remote_head
  base=$1
  remote_head=$(git -C "$base" ls-remote --symref origin HEAD 2>/dev/null) || return 1
  branch=$(printf '%s\n' "$remote_head" |
    sed -n 's|^ref: refs/heads/\(.*\)[[:space:]]HEAD$|\1|p' | head -n 1)
  if [ -n "$branch" ]; then
    ref="refs/remotes/origin/$branch"
  else
    ref=$(git -C "$base" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) || return 1
  fi
  git_ref_exists "$base" "$ref" || return 1
  printf '%s' "$ref"
}

# Print the ref to merge for --from <ref>. A branch name prefers its
# remote-tracking ref, named in full because a tag or local branch called
# origin/<branch> would otherwise win the lookup. Anything else goes to Git as
# given.
upstream_from_ref() {
  local base requested
  base=$1
  requested=$2
  case "$requested" in
    refs/*|HEAD) ;;
    origin/*)
      if git_ref_exists "$base" "refs/remotes/$requested"; then
        printf 'refs/remotes/%s' "$requested"
        return 0
      fi
      ;;
    *)
      if git_ref_exists "$base" "refs/remotes/origin/$requested"; then
        printf 'refs/remotes/origin/%s' "$requested"
        return 0
      fi
      ;;
  esac
  git_ref_exists "$base" "$requested" || return 1
  printf '%s' "$requested"
}

upstream_source_ref() {
  local base
  base=$1
  if [ -n "$UPSTREAM_FROM_REF" ]; then
    upstream_from_ref "$base" "$UPSTREAM_FROM_REF"
    return $?
  fi
  upstream_default_ref "$base"
}

# The name shown to the user: origin/master for refs/remotes/origin/master.
upstream_source_name() {
  printf '%s' "${1#refs/remotes/}"
}

# Git's own wording for a remote-tracking branch. The merge names a commit id,
# which Git would otherwise put in the message.
upstream_merge_message() {
  local source_ref base_branch
  source_ref=$1
  base_branch=$2
  case "$source_ref" in
    refs/remotes/*) printf "Merge remote-tracking branch '%s' into %s" "${source_ref#refs/remotes/}" "$base_branch" ;;
    *) printf "Merge '%s' into %s" "$source_ref" "$base_branch" ;;
  esac
}

# upstream never pulls the base branch. Merging into a base that lacks remote
# base commits would leave it diverged from origin, which pull and push
# (ff-only) reject. A source that is the remote base branch's own commit has no
# such gap, whichever name selected it.
preflight_upstream_base_current() {
  local label name base base_branch source_commit remote remote_commit
  label=$1
  name=$2
  base=$3
  base_branch=$4
  source_commit=$5
  remote="origin/$base_branch"
  remote_commit=$(git -C "$base" rev-parse --verify --quiet "refs/remotes/$remote^{commit}") || return 0
  [ "$source_commit" != "$remote_commit" ] || return 0
  git_is_ancestor "$base" "$remote_commit" HEAD && return 0
  if git_is_ancestor "$base" HEAD "$remote_commit"; then
    preflight_error "$label is behind $remote; run workbranch pull --repo $name first"
  else
    preflight_error "$(preflight_pull_diverged_message "$label" HEAD "$remote")"
  fi
  return 1
}

preflight_upstream_conflict_message() {
  local label source_name base_path
  label=$1
  source_name=$2
  base_path=$(shell_quote "$PROJECT_ROOT/$label")
  printf '%s\n' \
    "$label cannot merge $source_name without conflicts" \
    "Resolve manually:" \
    "  git -C $base_path merge $(shell_quote "$source_name")" \
    "  git -C $base_path add <resolved-files>" \
    "  git -C $base_path commit --no-edit"
}

# Replay the merge in a scratch worktree so conflicts, and local files the
# merge would silently overwrite, surface before the base worktree changes.
preflight_upstream_merge_clean() {
  local label base source_commit source_name tmp_parent tmp_path merged overwritten
  label=$1
  base=$2
  source_commit=$3
  source_name=$4
  # $5 is the repo index the checked merge result is recorded under.

  git_ref_exists "$base" HEAD || return 0
  # Nothing to merge.
  git_is_ancestor "$base" "$source_commit" HEAD && return 0
  # Only a merge commit needs an identity; a fast-forward does not.
  if ! git_is_ancestor "$base" HEAD "$source_commit" &&
    ! git -C "$base" var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
    preflight_error "$label needs Git user.name and user.email to create the merge commit"
    return 0
  fi

  tmp_parent=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-merge-check) || {
    preflight_error "$label cannot prepare merge preflight"
    return 0
  }
  tmp_path="$tmp_parent/worktree"

  if ! git -C "$base" worktree add --quiet --detach "$tmp_path" HEAD >/dev/null 2>&1; then
    # A failing post-checkout hook fails the command but keeps the registration.
    git -C "$base" worktree remove --force "$tmp_path" >/dev/null 2>&1 || true
    rm -rf "$tmp_parent"
    preflight_error "$label cannot prepare merge preflight"
    return 0
  fi

  # --no-ff makes a fast-forwardable source take the same path. Git checks the
  # committer identity even with --no-commit, so the replay gets a placeholder.
  if ! git -C "$tmp_path" -c user.name=workbranch -c user.email=workbranch@localhost \
    merge --no-commit --no-ff "$source_commit" >/dev/null 2>&1; then
    preflight_error "$(preflight_upstream_conflict_message "$label" "$source_name")"
  elif ! merged=$(git -C "$tmp_path" write-tree 2>/dev/null) || [ -z "$merged" ] ||
    ! overwritten=$(preflight_update_overwritten_paths "$base" "$merged"); then
    # An unreadable result is not an empty one: the merge stays unchecked.
    preflight_error "$label cannot inspect the merge result for overwritten files"
  elif [ -n "$overwritten" ]; then
    preflight_error "$(preflight_overwrite_message "$label" "$source_name" "$overwritten")"
  else
    UPSTREAM_MERGED_TREES[$5]=$merged
  fi

  git -C "$tmp_path" merge --abort >/dev/null 2>&1 || true
  git -C "$base" worktree remove --force "$tmp_path" >/dev/null 2>&1 || rm -rf "$tmp_path"
  rm -rf "$tmp_parent"
}

preflight_upstream_repos() {
  local i name base base_branch label source_ref source_commit
  UPSTREAM_SOURCE_REFS=()
  UPSTREAM_SOURCE_COMMITS=()
  UPSTREAM_BASE_HEADS=()
  UPSTREAM_MERGED_TREES=()
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    base=$(base_repo_path "$name")
    base_branch=$(repo_base_branch_at "$i")
    label="$BASE_DIR/$name"
    if [ ! -d "$base/.git" ] && [ ! -f "$base/.git" ]; then
      preflight_error "$label missing git repo"
      i=$((i + 1))
      continue
    fi
    preflight_require_current_branch "$label" "$base" "$base_branch"
    preflight_require_clean "$label" "$base"
    preflight_require_no_rebase "$label" "$base"
    preflight_require_no_pending_operation "$label" "$base"
    preflight_fetch_origin "$label" "$base"

    # Pin the commit now: execution merges what preflight checked, even if a
    # fetch moves the ref in between.
    if ! source_ref=$(upstream_source_ref "$base") ||
      ! source_commit=$(git -C "$base" rev-parse --verify --quiet "$source_ref^{commit}"); then
      if [ -n "$UPSTREAM_FROM_REF" ]; then
        preflight_error "$label missing source ref: $UPSTREAM_FROM_REF"
      else
        preflight_error "$label cannot detect origin's default branch; pass --from <ref>"
      fi
      i=$((i + 1))
      continue
    fi
    UPSTREAM_SOURCE_REFS[$i]=$source_ref
    UPSTREAM_SOURCE_COMMITS[$i]=$source_commit
    UPSTREAM_BASE_HEADS[$i]=$(git -C "$base" rev-parse --verify --quiet HEAD) || UPSTREAM_BASE_HEADS[$i]=""

    if [ "$(branch_or_unknown "$base")" = "$base_branch" ] &&
      ! is_git_dirty "$base" &&
      ! is_rebase_in_progress "$base" &&
      ! git_pending_operation "$base" >/dev/null &&
      preflight_upstream_base_current "$label" "$name" "$base" "$base_branch" "$source_commit"; then
      preflight_upstream_merge_clean "$label" "$base" "$source_commit" "$(upstream_source_name "$source_ref")" "$i"
    fi
    i=$((i + 1))
  done
}

execute_upstream_repos() {
  local i name base base_branch source_ref source_commit source_name seen
  i=0
  seen=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    base=$(base_repo_path "$name")
    base_branch=$(repo_base_branch_at "$i")
    source_ref=${UPSTREAM_SOURCE_REFS[$i]:-}
    source_commit=${UPSTREAM_SOURCE_COMMITS[$i]:-}
    source_name=$(upstream_source_name "$source_ref")
    repo_log_separator "$seen"
    seen=1
    i=$((i + 1))
    info "Merging $(color_repo_name "$name"): $(color_branch_name "$source_name") -> $(color_branch_name "$base_branch")"
    ensure_current_branch "$base" "$base_branch"
    if git_is_ancestor "$base" "$source_commit" HEAD; then
      success_repo_target "Already up to date" "" "$name"
      continue
    fi
    upstream_require_base_unchanged "$name" "$base" "${UPSTREAM_BASE_HEADS[$((i - 1))]:-}" "${UPSTREAM_MERGED_TREES[$((i - 1))]:-}"
    workbranch_git_merge_upstream "$name" "$base" "$source_commit" "$source_name" "$(upstream_merge_message "$source_ref" "$base_branch")"
    success_repo_target "Merged" "" "$name"
  done
}

# Preflight checks every repo before the first merge, so a base can change
# in between. Merge only the base preflight checked: same HEAD, still clean,
# and no new local file in the merge's way.
upstream_require_base_unchanged() {
  local name base checked_head merged_tree overwritten
  name=$1
  base=$2
  checked_head=$3
  merged_tree=$4
  [ "$(git -C "$base" rev-parse --verify --quiet HEAD)" = "$checked_head" ] ||
    die "base repo '$name' changed after preflight; rerun workbranch upstream"
  ! is_git_dirty "$base" ||
    die "base repo '$name' has local changes since preflight; rerun workbranch upstream"
  [ -n "$merged_tree" ] || die "base repo '$name' has no checked merge result; rerun workbranch upstream"
  overwritten=$(preflight_update_overwritten_paths "$base" "$merged_tree") ||
    die "base repo '$name': cannot inspect the merge result for overwritten files"
  [ -z "$overwritten" ] ||
    die "base repo '$name' has local files the merge would overwrite since preflight: $(printf '%s' "$overwritten" | tr '\n' ' ')"
}

cmd_upstream() {
  require_project
  parse_repo_option "$@"
  parse_upstream_from_option
  [ ${#ARGS[@]} -eq 0 ] || die "usage: workbranch upstream [--from <ref>] [--repo <repo>]"

  reset_preflight
  preflight_upstream_repos
  preflight_die_if_errors "merge upstream"
  execute_upstream_repos
}
