doctor_usage() {
  die "usage: workbranch doctor [--fix] [--repo <repo>]"
}

doctor_issue() {
  doctor_issue_count=$((doctor_issue_count + 1))
  printf '[-] %s\n' "$*"
  doctor_manual_lines+=("$*")
}

doctor_task_state() {
  local path task selected_count registered_count present_count selected_present_count missing_details unregistered_details branch_details i name repo_path base_path detail expected_branch actual_branch
  path=$1
  task=${path##*/}
  selected_count=0
  registered_count=0
  present_count=0
  selected_present_count=0
  missing_details=""
  unregistered_details=""
  branch_details=""
  load_task_metadata "$task"

  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    selected_count=$((selected_count + 1))
    repo_path="$path/$name"
    base_path=$(base_repo_path "$name")
    if [ -d "$repo_path" ] || metadata_task_branch_for_repo "$name" >/dev/null; then
      selected_present_count=$((selected_present_count + 1))
    fi
    if is_registered_worktree_path "$repo_path" "$base_path"; then
      present_count=$((present_count + 1))
      expected_branch=$(repo_task_branch_at "$i" "$task")
      actual_branch=$(branch_or_unknown "$repo_path")
      if [ "$actual_branch" = "$expected_branch" ]; then
        registered_count=$((registered_count + 1))
      elif [ -z "$branch_details" ]; then
        branch_details="$name expected branch $expected_branch, got $actual_branch"
      else
        branch_details="$branch_details, $name expected branch $expected_branch, got $actual_branch"
      fi
    elif [ -d "$repo_path" ]; then
      present_count=$((present_count + 1))
      if [ -z "$unregistered_details" ]; then
        unregistered_details="$name worktree not registered"
      else
        unregistered_details="$unregistered_details, $name worktree not registered"
      fi
    else
      if [ -z "$missing_details" ]; then
        missing_details="$name worktree missing"
      else
        missing_details="$missing_details, $name worktree missing"
      fi
    fi
    i=$((i + 1))
  done

  if [ "$selected_count" -eq 0 ]; then
    printf 'ignore|no selected repos'
  elif [ "$selected_present_count" -eq 0 ]; then
    printf 'ignore|no selected repo state'
  elif [ "$registered_count" -eq "$selected_count" ]; then
    printf 'healthy|healthy'
  elif [ "$registered_count" -eq 0 ] && [ -z "$branch_details" ]; then
    printf 'stale|no registered worktrees'
  else
    detail=$missing_details
    if [ -n "$unregistered_details" ]; then
      [ -n "$detail" ] && detail="$detail, "
      detail="$detail$unregistered_details"
    fi
    if [ -n "$branch_details" ]; then
      [ -n "$detail" ] && detail="$detail, "
      detail="$detail$branch_details"
    fi
    printf 'partial|%s' "$detail"
  fi
}

doctor_report() {
  local i name base expected actual state task_path task state_result task_state task_detail prunable_count healthy_found stale_found prunable_found
  doctor_issue_count=0
  doctor_manual_lines=()

  section "Base repos"
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    base=$(base_repo_path "$name")
    expected=$(repo_base_branch_at "$i")
    if [ ! -d "$base/.git" ] && [ ! -f "$base/.git" ]; then
      doctor_issue "$name missing git repo: $base"
      i=$((i + 1))
      continue
    fi
    actual=$(branch_or_unknown "$base")
    if [ "$actual" != "$expected" ]; then
      doctor_issue "$name expected $expected, got $actual"
    elif is_rebase_in_progress "$base"; then
      doctor_issue "$name rebase in progress"
    elif is_git_dirty "$base"; then
      doctor_issue "$name dirty worktree"
    else
      success "$name on $expected, clean"
    fi
    i=$((i + 1))
  done

  printf '\n'
  section "Task workspaces"
  healthy_found=0
  stale_found=0
  for task_path in "$PROJECT_ROOT"/*; do
    doctor_task_candidate_path "$task_path" || continue
    task=${task_path##*/}
    state_result=$(doctor_task_state "$task_path")
    task_state=${state_result%%|*}
    task_detail=${state_result#*|}
    case "$task_state" in
      healthy)
        success "$task healthy"
        healthy_found=1
        ;;
      partial)
        doctor_issue "$task partial: $task_detail"
        healthy_found=1
        ;;
      stale)
        stale_found=1
        ;;
    esac
  done
  [ "$healthy_found" -eq 1 ] || info "(none)"

  if [ "$stale_found" -eq 1 ]; then
    printf '\n'
    section "Stale directories"
    for task_path in "$PROJECT_ROOT"/*; do
      doctor_task_candidate_path "$task_path" || continue
      task=${task_path##*/}
      state_result=$(doctor_task_state "$task_path")
      task_state=${state_result%%|*}
      [ "$task_state" = "stale" ] || continue
      doctor_issue "$task stale: task-shaped directory but no registered worktrees"
      info "fix: workbranch remove $task"
    done
  fi

  printf '\n'
  section "Prunable worktrees"
  prunable_found=0
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    base=$(base_repo_path "$name")
    prunable_count=$(doctor_prunable_worktree_count "$base")
    if [ "$prunable_count" -gt 0 ]; then
      doctor_issue "$name $prunable_count stale worktree registration(s)"
      info "fix: workbranch doctor --fix"
      prunable_found=1
    fi
    i=$((i + 1))
  done
  [ "$prunable_found" -eq 1 ] || info "(none)"

  if [ "$doctor_issue_count" -eq 0 ]; then
    success "doctor found no issues"
  else
    printf '[-] doctor found %s issue(s)\n' "$doctor_issue_count"
  fi
}

doctor_apply_fix() {
  local i name base prunable_count pruned_names
  doctor_fixed_count=0
  pruned_names=""
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    repo_matches_filter "$name" || { i=$((i + 1)); continue; }
    base=$(base_repo_path "$name")
    prunable_count=$(doctor_prunable_worktree_count "$base")
    if [ "$prunable_count" -gt 0 ]; then
      workbranch_git_prune_stale_worktrees "$base" || die "failed to prune stale worktrees for repo '$name'"
      doctor_fixed_count=$((doctor_fixed_count + prunable_count))
      if [ -z "$pruned_names" ]; then
        pruned_names="$name"
      else
        pruned_names="$pruned_names, $name"
      fi
    fi
    i=$((i + 1))
  done
  if [ "$doctor_fixed_count" -gt 0 ]; then
    success "Pruned stale worktree registrations: $pruned_names"
    printf '\n'
  fi
}

cmd_doctor() {
  local fix doctor_args
  fix=0
  doctor_args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --fix) fix=1 ;;
      --fix=*) doctor_usage ;;
      *) doctor_args[${#doctor_args[@]}]="$1" ;;
    esac
    shift
  done

  require_project
  if [ ${#doctor_args[@]} -eq 0 ]; then
    parse_repo_option
  else
    parse_repo_option "${doctor_args[@]}"
  fi
  [ ${#ARGS[@]} -eq 0 ] || doctor_usage

  doctor_fixed_count=0
  if [ "$fix" -eq 1 ]; then
    doctor_apply_fix
  fi
  doctor_report
  if [ "$fix" -eq 1 ] && [ "$doctor_fixed_count" -gt 0 ]; then
    if [ "$doctor_issue_count" -eq 0 ]; then
      success "doctor fixed $doctor_fixed_count issue(s); 0 require manual action"
    else
      printf '[-] doctor fixed %s issue(s); %s require manual action\n' "$doctor_fixed_count" "$doctor_issue_count"
    fi
  fi
  [ "$doctor_issue_count" -eq 0 ] || exit 1
}
