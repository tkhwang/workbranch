archive_slug() {
  local title slug
  title=$1
  slug=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/-\{1,\}/-/g; s/^-//; s/-$//; s/^\(.\{60\}\).*/\1/; s/-$//')
  [ -n "$slug" ] || slug=plan
  printf '%s' "$slug"
}

archive_timestamp() {
  if [ -n "${WORKBRANCH_TEST_ARCHIVE_TIMESTAMP:-}" ]; then
    printf '%s' "$WORKBRANCH_TEST_ARCHIVE_TIMESTAMP"
  else
    date +%Y%m%d-%H%M%S
  fi
}

archive_iso_timestamp() {
  if [ -n "${WORKBRANCH_TEST_ARCHIVED_AT:-}" ]; then
    printf '%s' "$WORKBRANCH_TEST_ARCHIVED_AT"
  else
    date +%Y-%m-%dT%H:%M:%S%z | sed 's/\(..\)$/:\1/'
  fi
}

archive_unique_path() {
  local dir timestamp slug candidate suffix base
  dir=$1
  timestamp=$2
  slug=$3
  base="$dir/$timestamp-$slug"
  candidate="$base.md"
  suffix=2
  while [ -e "$candidate" ]; do
    candidate="$base-$suffix.md"
    suffix=$((suffix + 1))
  done
  printf '%s' "$candidate"
}

archive_extract_plan_block() {
  local file plan_index
  file=$1
  plan_index=$2
  awk -v target="$plan_index" '
    BEGIN { plan_index = -1 }
    /^[[:space:]]*```/ { if (in_code) in_code = 0; else in_code = 1 }
    !in_code && /^#[[:space:]]+/ {
      plan_index += 1
      if (capture) exit
      if (plan_index == target) capture = 1
    }
    capture { print }
  ' "$file"
}

archive_remove_plan_block() {
  local file plan_index
  file=$1
  plan_index=$2
  awk -v target="$plan_index" '
    BEGIN { plan_index = -1 }
    /^[[:space:]]*```/ { if (in_code) in_code = 0; else in_code = 1 }
    !in_code && /^#[[:space:]]+/ {
      plan_index += 1
      if (skip && plan_index != target) skip = 0
      if (plan_index == target) skip = 1
    }
    !skip { print }
  ' "$file"
}

archive_plan_body_with_done_status() {
  awk '
    NR == 1 { print; print "status: done"; next }
    NR == 2 && /^[[:space:]]*status:[[:space:]]*/ { next }
    { print }
  '
}

archive_current_plan() {
  local task completed_via brief state_dir archive_dir plan_index title slug timestamp archive_path tmp_block tmp_body tmp_brief branch repo_name archived_at
  task=$1
  completed_via=$2
  brief=$(task_brief_path "$task")
  [ -f "$brief" ] || die "no task brief to archive: $task"
  task_load_plans "$task"
  plan_index=$(task_active_plan_index_loaded) || die "no current plan to archive: $task"
  title=${TASK_PLAN_TITLES[$plan_index]}
  state_dir=$(task_state_dir_path "$task")
  archive_dir="$state_dir/plans/done"
  mkdir -p "$archive_dir" || die "failed to create archive directory: $archive_dir"
  slug=$(archive_slug "$title")
  timestamp=$(archive_timestamp)
  archive_path=$(archive_unique_path "$archive_dir" "$timestamp" "$slug")
  tmp_block="$state_dir/archive-block.$$"
  tmp_body="$state_dir/archive-body.$$"
  tmp_brief="$state_dir/archive-brief.$$"
  archive_extract_plan_block "$brief" "$plan_index" > "$tmp_block" || die "failed to extract current plan: $task"
  [ -s "$tmp_block" ] || die "no current plan to archive: $task"
  archive_plan_body_with_done_status < "$tmp_block" > "$tmp_body" || die "failed to prepare archive body: $task"
  branch=""
  if [ ${#REPO_NAMES[@]} -gt 0 ]; then
    repo_name=$(repo_name_at 0)
    branch=$(repo_task_branch_at 0 "$task")
  fi
  archived_at=$(archive_iso_timestamp)
  {
    printf '%s\n' '---'
    printf 'archived_at: %s\n' "$archived_at"
    printf 'task: %s\n' "$task"
    printf 'branch: %s\n' "$branch"
    printf 'completed_via: %s\n' "$completed_via"
    printf '%s\n\n' '---'
    cat "$tmp_body"
  } > "$archive_path" || die "failed to write archive: $archive_path"
  archive_remove_plan_block "$brief" "$plan_index" > "$tmp_brief" || die "failed to rewrite task brief: $task"
  mv "$tmp_brief" "$brief" || die "failed to update task brief: $task"
  rm -f "$tmp_block" "$tmp_body" "$tmp_brief"
  success "Archived plan: $archive_path"
}

archive_prompt_current_plan() {
  local task completed_via plan_index title answer
  task=$1
  completed_via=$2
  task_load_plans "$task"
  plan_index=$(task_active_plan_index_loaded) || return 0
  title=${TASK_PLAN_TITLES[$plan_index]}
  if [ -t 0 ] || [ "${WORKBRANCH_ALLOW_NON_TTY_PROMPT:-}" = "1" ]; then
    answer=$(prompt_read "[*] Mark plan \"$title\" done and archive? [y/N]: ") || answer=""
    case "$answer" in
      y|Y|yes|YES|Yes)
        archive_current_plan "$task" "$completed_via"
        ;;
    esac
  fi
}
