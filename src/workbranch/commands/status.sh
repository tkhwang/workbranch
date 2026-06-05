cmd_status() {
  require_project
  parse_repo_option "$@"
  [ ${#ARGS[@]} -eq 0 ] || die "usage: workbranch status [--repo <repo>]"

  section "Base worktrees"
  print_base_status_header
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    path=$(base_repo_path "$name")
    print_base_status_item "$name" "$(branch_or_unknown "$path")" "$(head_commit_short "$path")" "$(worktree_status_label "$path")"
    i=$((i + 1))
  done

  printf '\n'
  section "Task workspaces"
  found=0
  for path in "$PROJECT_ROOT"/*; do
    is_task_workspace_path "$path" || continue
    task_printed=0
    task=${path##*/}
    i=0
    while [ $i -lt ${#REPO_NAMES[@]} ]; do
      name=$(repo_name_at "$i")
      repo_matches_filter "$name" || { i=$((i + 1)); continue; }
      repo_path="$path/$name"
      [ -d "$repo_path" ] || { i=$((i + 1)); continue; }
      base_path=$(base_repo_path "$name")
      base_commit=$(head_commit_full "$base_path")
      diff_label=$(commit_diff_label "$repo_path" "$base_commit")
      if [ $task_printed -eq 0 ]; then
        section "$task"
        print_task_status_header
      fi
      print_task_status_item "$name" "$(head_commit_short "$base_path")" "$(head_commit_short "$repo_path")" "$diff_label" "$(worktree_status_label "$repo_path")" "$(next_action_for_diff "$diff_label")"
      task_printed=1
      i=$((i + 1))
    done
    [ $task_printed -eq 1 ] && found=1
  done
  if [ $found -eq 1 ]; then
    printf '\n'
    print_next_legend
  fi
  [ $found -eq 1 ] || info "(none)"

  stale_found=0
  for path in "$PROJECT_ROOT"/*; do
    is_stale_task_directory_path "$path" || continue
    if [ $stale_found -eq 0 ]; then
      printf '\n'
      section "Stale directories"
    fi
    printf '    %-8s %s\n' "${path##*/}" "directory exists but no registered worktrees"
    stale_found=1
  done
}
