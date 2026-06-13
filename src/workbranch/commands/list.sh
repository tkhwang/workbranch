cmd_list_json() {
  local first_task first_repo path task name repo_path branch title dirty status counts progress_done progress_total current_item
  printf '{'
  printf '"schemaVersion":1,'
  printf '"project":'
  json_string "$PROJECT_NAME"
  printf ',"root":'
  json_string "$PROJECT_ROOT"
  printf ',"tasks":['
  first_task=1
  for path in "$PROJECT_ROOT"/*; do
    is_task_workspace_path "$path" || continue
    task=${path##*/}
    if [ $first_task -eq 1 ]; then
      first_task=0
    else
      printf ','
    fi
    title=$(task_brief_title "$task")
    printf '{"name":'
    json_string "$task"
    printf ',"path":'
    json_string "$path"
    printf ',"memoTitle":'
    json_string "$title"
    status=$(task_status "$task")
    counts=$(task_checklist_counts "$task")
    progress_done=${counts%% *}
    progress_total=${counts##* }
    current_item=$(task_current_item "$task")
    printf ',"status":'
    json_string "$status"
    printf ',"progressDone":%s' "$progress_done"
    printf ',"progressTotal":%s' "$progress_total"
    printf ',"currentItem":'
    json_string "$current_item"
    printf ',"items":'
    task_checklist_items_json "$task"
    printf ',"notiCount":%s' "$(noti_count "$task")"
    printf ',"repos":['
    first_repo=1
    i=0
    while [ $i -lt ${#REPO_NAMES[@]} ]; do
      name=$(repo_name_at "$i")
      repo_path="$path/$name"
      branch=$(branch_or_unknown "$repo_path")
      if is_git_dirty "$repo_path"; then
        dirty=true
      else
        dirty=false
      fi
      if [ $first_repo -eq 1 ]; then
        first_repo=0
      else
        printf ','
      fi
      printf '{"name":'
      json_string "$name"
      printf ',"branch":'
      json_string "$branch"
      printf ',"dirty":%s}' "$dirty"
      i=$((i + 1))
    done
    printf ']}'
  done
  printf ']}'
  printf '\n'
}

cmd_list_local() {
  require_project
  if [ $# -eq 1 ] && [ "$1" = "--json" ]; then
    cmd_list_json
    return 0
  fi
  [ $# -eq 0 ] || die "usage: workbranch list [--json]"
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


cmd_list_global_json() {
  local root first_project first_error successes errors out status message
  printf '{"schemaVersion":1,"projects":['
  first_project=1
  first_error=1
  successes=0
  errors=0
  error_items=""
  while IFS= read -r root || [ -n "$root" ]; do
    [ -n "$root" ] || continue
    out=$(cd "$root" 2>/dev/null && "$0" list --json 2>&1)
    status=$?
    if [ $status -eq 0 ]; then
      if [ $first_project -eq 1 ]; then first_project=0; else printf ','; fi
      printf '%s' "$out"
      successes=$((successes + 1))
    else
      message=$out
      if [ $first_error -eq 1 ]; then first_error=0; else error_items="$error_items,"; fi
      error_items="$error_items{\"root\":"
      error_items="$error_items$(json_string_value "$root")"
      error_items="$error_items,\"message\":"
      error_items="$error_items$(json_string_value "$message")"
      error_items="$error_items}"
      errors=$((errors + 1))
    fi
  done <<EOF_REGISTRY_ROOTS
$(registry_list_roots)
EOF_REGISTRY_ROOTS
  printf '],"errors":['
  printf '%s' "$error_items"
  printf ']}\n'
  if [ $successes -eq 0 ] && [ $errors -gt 0 ]; then
    return 1
  fi
  return 0
}

json_string_value() {
  printf '"'
  printf '%s' "$1" | json_escape
  printf '"'
}

cmd_list_global_human() {
  local root out status successes errors
  successes=0
  errors=0
  while IFS= read -r root || [ -n "$root" ]; do
    [ -n "$root" ] || continue
    out=$(cd "$root" 2>/dev/null && "$0" list 2>&1)
    status=$?
    if [ $status -eq 0 ]; then
      [ $successes -eq 0 ] || printf '\n'
      printf '%s\n' "$out"
      successes=$((successes + 1))
    else
      printf '[-] Error: %s: %s\n' "$root" "$out" >&2
      errors=$((errors + 1))
    fi
  done <<EOF_REGISTRY_ROOTS
$(registry_list_roots)
EOF_REGISTRY_ROOTS
  if [ $successes -eq 0 ] && [ $errors -gt 0 ]; then
    return 1
  fi
}

cmd_list() {
  global=0
  json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --global) global=1; shift ;;
      --json) json=1; shift ;;
      *) die "usage: workbranch list [--global] [--json]" ;;
    esac
  done
  if [ $global -eq 1 ]; then
    if [ $json -eq 1 ]; then
      cmd_list_global_json
    else
      cmd_list_global_human
    fi
    return $?
  fi
  if [ $json -eq 1 ]; then
    require_project
    cmd_list_json
    return 0
  fi
  cmd_list_local
}
