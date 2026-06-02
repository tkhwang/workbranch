repo_names_joined() {
  _repo_names_out=""
  _repo_names_i=0
  while [ $_repo_names_i -lt ${#REPO_NAMES[@]} ]; do
    _repo_names_name=$(repo_name_at "$_repo_names_i")
    if [ -z "$_repo_names_out" ]; then
      _repo_names_out=$_repo_names_name
    else
      _repo_names_out="$_repo_names_out $_repo_names_name"
    fi
    _repo_names_i=$((_repo_names_i + 1))
  done
  printf '%s' "$_repo_names_out"
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
    setup_status=$?
    if [ $setup_status -ne 0 ]; then
      printf '[-] Error: task setup failed: %s\n' "$task" >&2
      printf '[*] Setup directory: %s\n' "$PROJECT_ROOT" >&2
      printf '[*] Setup command: %s\n' "$TASK_SETUP" >&2
      exit "$setup_status"
    fi
  )
}

run_repo_task_setup() {
  task=$1
  repo=$2
  command=$3
  [ -n "$command" ] || die "repo setup command is not configured: $repo"
  task_dir="$PROJECT_ROOT/$task"
  repo_dir=$(task_repo_path "$task" "$repo")
  base_repo_dir=$(base_repo_path "$repo")
  is_task_workspace_path "$task_dir" || die "task workspace not found: $task"
  [ -d "$repo_dir" ] || die "task repo not found: $task/$repo"
  (
    cd "$repo_dir" || exit 1
    WORKBRANCH_PROJECT_ROOT=$PROJECT_ROOT
    WORKBRANCH_TASK=$task
    WORKBRANCH_TASK_DIR=$task_dir
    WORKBRANCH_BASE_DIR="$PROJECT_ROOT/$BASE_DIR"
    WORKBRANCH_REPOS=$(repo_names_joined)
    WORKBRANCH_REPO=$repo
    WORKBRANCH_REPO_DIR=$repo_dir
    WORKBRANCH_BASE_REPO_DIR=$base_repo_dir
    export WORKBRANCH_PROJECT_ROOT WORKBRANCH_TASK WORKBRANCH_TASK_DIR WORKBRANCH_BASE_DIR WORKBRANCH_REPOS
    export WORKBRANCH_REPO WORKBRANCH_REPO_DIR WORKBRANCH_BASE_REPO_DIR
    sh -c "$command"
    setup_status=$?
    if [ $setup_status -ne 0 ]; then
      printf '[-] Error: repo setup failed: %s/%s\n' "$task" "$repo" >&2
      printf '[*] Setup directory: %s\n' "$repo_dir" >&2
      printf '[*] Setup command: %s\n' "$command" >&2
      exit "$setup_status"
    fi
  )
}

run_task_setups() {
  task=$1
  ran_setup=0

  _setup_i=0
  while [ $_setup_i -lt ${#REPO_NAMES[@]} ]; do
    _setup_name=$(repo_name_at "$_setup_i")
    _setup_command=$(repo_setup_at "$_setup_i")
    if [ -n "$_setup_command" ] && repo_matches_filter "$_setup_name"; then
      info "Running repo setup: $task/$_setup_name"
      run_repo_task_setup "$task" "$_setup_name" "$_setup_command" || return 1
      success "Repo setup completed: $task/$_setup_name"
      ran_setup=1
    fi
    _setup_i=$((_setup_i + 1))
  done

  if [ "$ran_setup" -eq 0 ] && [ -z "$FILTER_REPO" ] && [ -n "$TASK_SETUP" ]; then
    info "Running task setup: $TASK_SETUP"
    run_task_setup "$task" || return 1
    success "Task setup completed: $task"
    ran_setup=1
  fi

  if [ "$ran_setup" -ne 1 ] && [ -z "$FILTER_REPO" ]; then
    die "task setup command is not configured"
  fi
}
