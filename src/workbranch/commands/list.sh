cmd_list() {
  require_project
  info "Project: $PROJECT_NAME"
  info "Base: $BASE_DIR"
  info "Editor:"
  if [ -n "$EDITOR_COMMAND" ]; then
    printf '    %s\n' "$EDITOR_COMMAND"
  else
    printf '    (none)\n'
  fi
  info "Terminal:"
  if [ -n "$TERMINAL_COMMAND" ]; then
    printf '    %s\n' "$TERMINAL_COMMAND"
  else
    printf '    (none)\n'
  fi
  if has_repo_setups; then
    info "Repo setup:"
    i=0
    while [ $i -lt ${#REPO_NAMES[@]} ]; do
      command=$(repo_setup_at "$i")
      if [ -n "$command" ]; then
        printf '    %s: %s\n' "$(repo_name_at "$i")" "$command"
      fi
      i=$((i + 1))
    done
  fi
  info "Repos:"
  printf '    %-11s %-16s %s\n' "repo" "base" "current"
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    branch=$(repo_base_branch_at "$i")
    current=$(branch_or_unknown "$(base_repo_path "$name")")
    printf '    %-11s %-16s %s\n' "$name" "$branch" "$current"
    i=$((i + 1))
  done
  info "Tasks:"
  found=0
  for path in "$PROJECT_ROOT"/*; do
    [ -d "$path" ] || continue
    dir_name=${path##*/}
    [ "$dir_name" = "$BASE_DIR" ] && continue
    case "$dir_name" in .*) continue ;; esac
    task_has_repo=0
    i=0
    while [ $i -lt ${#REPO_NAMES[@]} ]; do
      name=$(repo_name_at "$i")
      [ -d "$path/$name" ] && task_has_repo=1
      i=$((i + 1))
    done
    [ $task_has_repo -eq 1 ] || continue
    found=1
    info "$dir_name"
    printf '    %-11s %s\n' "repo" "branch"
    i=0
    while [ $i -lt ${#REPO_NAMES[@]} ]; do
      name=$(repo_name_at "$i")
      current=$(branch_or_unknown "$path/$name")
      printf '    %-11s %s\n' "$name" "$current"
      i=$((i + 1))
    done
  done
  [ $found -eq 1 ] || info "  (none)"
}
