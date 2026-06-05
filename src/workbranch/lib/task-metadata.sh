task_metadata_file() { printf '%s/%s/.workbranch.task' "$PROJECT_ROOT" "$1"; }

reset_task_metadata_cache() {
  TASK_BRANCH_REPOS=()
  TASK_BRANCH_NAMES=()
}

task_metadata_branch_index() {
  local name
  name=$1
  TASK_METADATA_INDEX=0
  while [ $TASK_METADATA_INDEX -lt ${#TASK_BRANCH_REPOS[@]} ]; do
    [ "${TASK_BRANCH_REPOS[$TASK_METADATA_INDEX]}" = "$name" ] && return 0
    TASK_METADATA_INDEX=$((TASK_METADATA_INDEX + 1))
  done
  return 1
}

set_task_metadata_branch() {
  local name branch
  name=$1
  branch=$2
  validate_branch_name "task branch" "$branch"
  if task_metadata_branch_index "$name"; then
    TASK_BRANCH_NAMES[$TASK_METADATA_INDEX]=$branch
  else
    TASK_BRANCH_REPOS[${#TASK_BRANCH_REPOS[@]}]=$name
    TASK_BRANCH_NAMES[${#TASK_BRANCH_NAMES[@]}]=$branch
  fi
}

load_task_metadata() {
  local task file line_no raw_line line
  task=$1
  file=$(task_metadata_file "$task")
  reset_task_metadata_cache
  [ -f "$file" ] || return 0
  line_no=0
  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    line_no=$((line_no + 1))
    line=$(printf '%s' "$raw_line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    config_line_split_tokens "$line"
    set -- "${CONFIG_FIELDS[@]}"
    case "$1" in
      REPO_BRANCH)
        [ $# -eq 3 ] || die "invalid task metadata line $line_no: REPO_BRANCH expects 2 values"
        repo_index_by_name "$2" >/dev/null || die "task metadata references unknown repo '$2'"
        set_task_metadata_branch "$2" "$3"
        ;;
      *) die "unknown directive '$1' in task metadata line $line_no" ;;
    esac
  done < "$file"
}

metadata_task_branch_for_repo() {
  local name
  name=$1
  if task_metadata_branch_index "$name"; then
    printf '%s' "${TASK_BRANCH_NAMES[$TASK_METADATA_INDEX]}"
    return 0
  fi
  return 1
}

write_task_metadata() {
  local task file name branch
  task=$1
  file=$(task_metadata_file "$task")
  mkdir -p "$(dirname "$file")" || die "failed to create task metadata directory: $task"
  {
    printf '# Workbranch task metadata\n'
    printf '# This file stores branch names chosen when the task workspace was created.\n'
    _task_metadata_i=0
    while [ $_task_metadata_i -lt ${#REPO_NAMES[@]} ]; do
      name=$(repo_name_at "$_task_metadata_i")
      branch=$(metadata_task_branch_for_repo "$name") || branch=$(default_repo_task_branch_at "$_task_metadata_i" "$task")
      printf 'REPO_BRANCH %s %s\n' "$name" "$branch"
      _task_metadata_i=$((_task_metadata_i + 1))
    done
  } > "$file" || die "failed to write task metadata: $file"
}
