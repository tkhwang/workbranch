cmd_list() {
  require_project
  info "Project: $PROJECT_NAME"
  info "Base: $BASE_DIR"
  section "IDE"
  if [ -n "$IDE_COMMAND" ]; then
    printf '    %s\n' "$IDE_COMMAND"
  else
    printf '    (none)\n'
  fi
  section "Terminal"
  if [ -n "$TERMINAL_COMMAND" ]; then
    printf '    %s\n' "$TERMINAL_COMMAND"
  else
    printf '    (none)\n'
  fi
  if has_repo_setups; then
    section "Repo setup"
    i=0
    while [ $i -lt ${#REPO_NAMES[@]} ]; do
      command=$(repo_setup_at "$i")
      if [ -n "$command" ]; then
        printf '    %s: %s\n' "$(repo_name_at "$i")" "$command"
      fi
      i=$((i + 1))
    done
  fi
  section "Repos"
  printf '    %s %s %s\n' "$(table_header 11 repo)" "$(table_header 16 base)" "$(color_text "$WB_GRAY" current)"
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    branch=$(repo_base_branch_at "$i")
    current=$(branch_or_unknown "$(base_repo_path "$name")")
    printf '    %s %s %s\n' "$(color_repo_cell 11 "$name")" "$(color_branch_cell 16 "$branch")" "$(color_branch_name "$current")"
    i=$((i + 1))
  done
  section "Tasks"
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
    section "$dir_name"
    printf '    %s %s\n' "$(table_header 11 repo)" "$(color_text "$WB_GRAY" branch)"
    i=0
    while [ $i -lt ${#REPO_NAMES[@]} ]; do
      name=$(repo_name_at "$i")
      current=$(branch_or_unknown "$path/$name")
      printf '    %s %s\n' "$(color_repo_cell 11 "$name")" "$(color_branch_name "$current")"
      i=$((i + 1))
    done
  done
  [ $found -eq 1 ] || info "  (none)"
}
