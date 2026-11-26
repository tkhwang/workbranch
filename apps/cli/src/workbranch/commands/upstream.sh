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

# Print the remote-tracking ref of origin's default branch, such as
# origin/master. origin/HEAD is missing when the base repo was not created by
# `git clone`, so fall back to asking the remote.
upstream_default_ref() {
  local base ref branch
  base=$1
  ref=$(git -C "$base" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) || ref=""
  ref=${ref#refs/remotes/}
  if [ -n "$ref" ] && git_ref_exists "$base" "$ref"; then
    printf '%s' "$ref"
    return 0
  fi
  branch=$(git -C "$base" ls-remote --symref origin HEAD 2>/dev/null |
    sed -n 's|^ref: refs/heads/\(.*\)[[:space:]]HEAD$|\1|p' | head -n 1)
  [ -n "$branch" ] || return 1
  git_ref_exists "$base" "origin/$branch" || return 1
  printf 'origin/%s' "$branch"
}

upstream_source_ref() {
  local base
  base=$1
  if [ -n "$UPSTREAM_FROM_REF" ]; then
    resolve_add_source_ref "$base" "$UPSTREAM_FROM_REF"
    return $?
  fi
  upstream_default_ref "$base"
}

# upstream never pulls the base branch. Merging into a base that lacks remote
# base commits would leave it diverged from origin, which pull and push
# (ff-only) reject. Merging the remote base branch itself has no such gap.
preflight_upstream_base_current() {
  local label name base base_branch source_ref remote
  label=$1
  name=$2
  base=$3
  base_branch=$4
  source_ref=$5
  remote="origin/$base_branch"
  [ "$source_ref" != "$remote" ] || return 0
  git_ref_exists "$base" "$remote" || return 0
  git_is_ancestor "$base" "$remote" HEAD && return 0
  if git_is_ancestor "$base" HEAD "$remote"; then
    preflight_error "$label is behind $remote; run workbranch pull --repo $name first"
  else
    preflight_error "$(preflight_pull_diverged_message "$label" HEAD "$remote")"
  fi
  return 1
}

preflight_upstream_conflict_message() {
  local label source_ref base_path
  label=$1
  source_ref=$2
  base_path="$PROJECT_ROOT/$label"
  printf '%s\n' \
    "$label cannot merge $source_ref without conflicts" \
    "Resolve manually:" \
    "  git -C $base_path merge $source_ref" \
    "  git -C $base_path add <resolved-files>" \
    "  git -C $base_path commit --no-edit"
}

# Replay the merge in a scratch worktree so conflicts, and ignored files the
# merge would silently overwrite, surface before the base worktree changes.
preflight_upstream_merge_clean() {
  local label base source_ref tmp_parent tmp_path merged overwritten
  label=$1
  base=$2
  source_ref=$3

  git_ref_exists "$base" HEAD || return 0
  # Nothing to merge.
  git_is_ancestor "$base" "$source_ref" HEAD && return 0
  # Only a merge commit needs an identity; a fast-forward does not.
  if ! git_is_ancestor "$base" HEAD "$source_ref" &&
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
    rm -rf "$tmp_parent"
    preflight_error "$label cannot prepare merge preflight"
    return 0
  fi

  # --no-ff makes a fast-forwardable source take the same path. Git checks the
  # committer identity even with --no-commit, so the replay gets a placeholder.
  if ! git -C "$tmp_path" -c user.name=workbranch -c user.email=workbranch@localhost \
    merge --no-commit --no-ff "$source_ref" >/dev/null 2>&1; then
    preflight_error "$(preflight_upstream_conflict_message "$label" "$source_ref")"
  else
    merged=$(git -C "$tmp_path" write-tree 2>/dev/null) || merged=""
    if [ -n "$merged" ]; then
      overwritten=$(preflight_update_overwritten_paths "$base" "$merged")
      [ -z "$overwritten" ] || preflight_error "$(preflight_overwrite_message "$label" "$source_ref" "$overwritten")"
    fi
  fi

  git -C "$tmp_path" merge --abort >/dev/null 2>&1 || true
  git -C "$base" worktree remove --force "$tmp_path" >/dev/null 2>&1 || rm -rf "$tmp_path"
  rm -rf "$tmp_parent"
}

preflight_upstream_repos() {
  local i name base base_branch label source_ref
  UPSTREAM_SOURCE_REFS=()
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
    preflight_require_no_merge "$label" "$base"
    preflight_fetch_origin "$label" "$base"

    if ! source_ref=$(upstream_source_ref "$base"); then
      if [ -n "$UPSTREAM_FROM_REF" ]; then
        preflight_error "$label missing source ref: $UPSTREAM_FROM_REF"
      else
        preflight_error "$label cannot detect origin's default branch; pass --from <ref>"
      fi
      i=$((i + 1))
      continue
    fi
    UPSTREAM_SOURCE_REFS[$i]=$source_ref

    if [ "$(branch_or_unknown "$base")" = "$base_branch" ] &&
      ! is_git_dirty "$base" &&
      ! is_rebase_in_progress "$base" &&
      ! is_merge_in_progress "$base" &&
      preflight_upstream_base_current "$label" "$name" "$base" "$base_branch" "$source_ref"; then
      preflight_upstream_merge_clean "$label" "$base" "$source_ref"
    fi
    i=$((i + 1))
  done
}

execute_upstream_repos() {
  local i name base base_branch source_ref seen
  i=0
  seen=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    base=$(base_repo_path "$name")
    base_branch=$(repo_base_branch_at "$i")
    source_ref=${UPSTREAM_SOURCE_REFS[$i]:-}
    repo_log_separator "$seen"
    seen=1
    i=$((i + 1))
    info "Merging $(color_repo_name "$name"): $(color_branch_name "$source_ref") -> $(color_branch_name "$base_branch")"
    ensure_current_branch "$base" "$base_branch"
    if git_is_ancestor "$base" "$source_ref" HEAD; then
      success_repo_target "Already up to date" "" "$name"
      continue
    fi
    workbranch_git_merge_upstream "$name" "$base" "$source_ref"
    success_repo_target "Merged" "" "$name"
  done
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
