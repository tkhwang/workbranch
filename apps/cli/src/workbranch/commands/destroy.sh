cmd_destroy_usage() { die "usage: workbranch destroy [--force]"; }

confirm_destroy_project() {
  local answer
  [ "$1" -eq 1 ] && return 0
  if [ -t 0 ] || [ "${WORKBRANCH_ALLOW_NON_TTY_PROMPT:-}" = "1" ]; then
    answer=$(prompt_read "[*] Destroy workbranch project and delete files? [y/N]: ") || answer=""
    case "$answer" in y|Y|yes|YES|Yes) return 0 ;; esac
  fi
  die "destroy cancelled"
}

preflight_require_no_unpushed_current_branch() {
  local label path branch upstream
  label=$1
  path=$2
  branch=$(branch_or_unknown "$path")
  case "$branch" in
    ""|"(unknown)"|"HEAD"|"(detached)"|"(detached HEAD)") return 0 ;;
  esac
  git -C "$path" check-ref-format --branch "$branch" >/dev/null 2>&1 || return 0
  upstream=$(git -C "$path" rev-parse --verify --quiet "$branch@{upstream}^{commit}" 2>/dev/null) || upstream=""
  [ -n "$upstream" ] || return 0
  if ! git_is_ancestor "$path" "$branch" "$upstream"; then
    preflight_error "$label has unpushed commits"
  fi
}

cmd_destroy() {
  local force i name base task task_dir path branch project_root
  force=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) force=1; shift ;;
      --keep-files) cmd_destroy_usage ;;
      *) cmd_destroy_usage ;;
    esac
  done
  require_project
  project_root=$PROJECT_ROOT
  reset_preflight

  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base=$(base_repo_path "$name")
    if [ ! -d "$base/.git" ] && [ ! -f "$base/.git" ]; then
      if [ "$force" -ne 1 ]; then
        preflight_error "$BASE_DIR/$name missing git repo"
        i=$((i + 1))
        continue
      fi
      printf '[-] Warning: %s missing git repo; continuing forced destroy\n' "$BASE_DIR/$name" >&2
    fi
    if [ "$force" -ne 1 ]; then
      preflight_require_clean "$BASE_DIR/$name" "$base"
      preflight_require_no_unpushed_current_branch "$BASE_DIR/$name" "$base"
    fi
    i=$((i + 1))
  done

  for task_dir in "$PROJECT_ROOT"/*; do
    doctor_task_candidate_path "$task_dir" || continue
    task=${task_dir##*/}
    i=0
    while [ $i -lt ${#REPO_NAMES[@]} ]; do
      name=$(repo_name_at "$i")
      path=$(task_repo_path "$task" "$name")
      base=$(base_repo_path "$name")
      branch=$(repo_task_branch_at "$i" "$task")
      if [ -d "$path/.git" ] || [ -f "$path/.git" ]; then
        if [ "$force" -ne 1 ]; then
          preflight_require_clean "$task/$name" "$path"
        fi
      fi
      if [ "$force" -ne 1 ] && { [ -d "$base/.git" ] || [ -f "$base/.git" ]; }; then
        preflight_require_task_branch_safe_to_delete "$task/$name" "$base" "$branch" "$task"
      fi
      i=$((i + 1))
    done
  done

  preflight_die_if_errors "destroy"
  confirm_destroy_project "$force"

  for task_dir in "$PROJECT_ROOT"/*; do
    is_task_workspace_path "$task_dir" || continue
    task=${task_dir##*/}
    i=0
    while [ $i -lt ${#REPO_NAMES[@]} ]; do
      name=$(repo_name_at "$i")
      path=$(task_repo_path "$task" "$name")
      base=$(base_repo_path "$name")
      branch=$(repo_task_branch_at "$i" "$task")
      if [ -d "$path" ] && { [ -d "$base/.git" ] || [ -f "$base/.git" ]; }; then
        if [ "$force" -eq 1 ]; then
          git -C "$base" worktree remove --force "$path" >/dev/null 2>&1 || rm -rf "$path"
        else
          git -C "$base" worktree remove "$path" >/dev/null 2>&1 || die "failed to remove worktree: $task/$name"
        fi
      fi
      if [ -d "$base/.git" ] || [ -f "$base/.git" ]; then
        workbranch_git_delete_task_branch "$base" "$branch" "$force" || die "failed to delete task branch: $task/$name $branch"
      fi
      i=$((i + 1))
    done
  done

  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    base=$(base_repo_path "$name")
    [ ! -e "$base" ] || rm -rf "$base" || die "failed to remove base repo: $BASE_DIR/$name"
    i=$((i + 1))
  done
  [ ! -e "$PROJECT_ROOT/$BASE_DIR" ] || rmdir "$PROJECT_ROOT/$BASE_DIR" 2>/dev/null || true
  [ ! -f "$CONFIG_FILE" ] || rm -f "$CONFIG_FILE" || die "failed to remove config: $CONFIG_FILE"
  registry_remove_root "$project_root"
  [ ! -e "$project_root" ] || rm -rf "$project_root" || die "failed to remove project: $project_root"
  success "Destroyed workbranch project: $project_root"
}
