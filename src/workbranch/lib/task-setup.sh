repo_names_joined() {
  out=""
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    if [ -z "$out" ]; then
      out=$name
    else
      out="$out $name"
    fi
    i=$((i + 1))
  done
  printf '%s' "$out"
}

run_task_setup() {
  task=$1
  [ -n "$TASK_SETUP" ] || die "task setup command is not configured"
  task_dir="$PROJECT_ROOT/$task"
  is_task_workspace_path "$task_dir" || die "task workspace not found: $task"
  (
    cd "$PROJECT_ROOT" || exit 1
    WORKBRANCH_PROJECT_ROOT=$PROJECT_ROOT
    WORKBRANCH_TASK=$task
    WORKBRANCH_TASK_DIR=$task_dir
    WORKBRANCH_BASE_DIR="$PROJECT_ROOT/$BASE_DIR"
    WORKBRANCH_REPOS=$(repo_names_joined)
    export WORKBRANCH_PROJECT_ROOT WORKBRANCH_TASK WORKBRANCH_TASK_DIR WORKBRANCH_BASE_DIR WORKBRANCH_REPOS
    sh -c "$TASK_SETUP"
  )
}
