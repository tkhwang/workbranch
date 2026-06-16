# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

archive_done_file_for() {
  find "$1/.workbranch/plans/done" -type f -name '*.md' | sort | tail -1
}

archive_done_file_count_for() {
  find "$1/.workbranch/plans/done" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' '
}

test_plan_archive_done_command_archives_active_plan_without_activity_write() {
  new_fixture
  project="$FIXTURE_PROJECT"
  home="$TMP_ROOT/home"
  mkdir -p "$home"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Completed Plan
status: done
- [x] old work

# Active Plan

status: review
- [x] inspect
- [ ] verify
## Notes
- keep this note

# Future Plan
- [ ] later
EOF_BRIEF

  out=$(run_expect_success env HOME="$home" "$WORKBRANCH" done login)
  assert_contains "$out" "Archived plan:"
  archive_file=$(archive_done_file_for "$project/login")
  assert_file "$archive_file"
  archive=$(cat "$archive_file")
  assert_contains "$archive" "archived_at:"
  assert_contains "$archive" "task: login"
  assert_contains "$archive" "branch: feature/login"
  assert_contains "$archive" "completed_via: done"
  assert_contains "$archive" "# Active Plan"
  assert_contains "$archive" "status: done"
  assert_not_contains "$archive" "status: review"
  status_count=$(printf '%s' "$archive" | grep -c '^status: ')
  [ "$status_count" = "1" ] || fail "expected one archived status line, got $status_count: $archive"
  assert_contains "$archive" "- [x] inspect"
  assert_contains "$archive" "- [ ] verify"
  assert_contains "$archive" "## Notes"
  assert_contains "$archive" "- keep this note"

  brief=$(cat "$project/login/TASK-WORKBRANCH.md")
  assert_contains "$brief" "# Completed Plan"
  assert_not_contains "$brief" "# Active Plan"
  assert_contains "$brief" "# Future Plan"
  assert_not_exists "$home/.local/state/workbranch/activity.jsonl"
}

test_plan_archive_slug_collision_suffix_and_no_plan_error() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_ONE'
# Repeat Plan
- [ ] first
EOF_ONE
  WORKBRANCH_TEST_ARCHIVE_TIMESTAMP=20260616-120000 run_expect_success "$WORKBRANCH" done login >/dev/null

  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_TWO'
# Repeat Plan
- [ ] second
EOF_TWO
  WORKBRANCH_TEST_ARCHIVE_TIMESTAMP=20260616-120000 run_expect_success "$WORKBRANCH" done login >/dev/null

  count=$(archive_done_file_count_for "$project/login")
  [ "$count" = "2" ] || fail "expected two archive files, got $count"
  files=$(find "$project/login/.workbranch/plans/done" -type f -name '*.md' | sort)
  assert_contains "$files" "repeat-plan.md"
  assert_contains "$files" "repeat-plan-2.md"

  : > "$project/login/TASK-WORKBRANCH.md"
  out=$(run_expect_fail "$WORKBRANCH" done login)
  assert_contains "$out" "no current plan to archive: login"
}

test_remove_deletes_workbranch_state_with_archives_before_leftover_prompt() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Done Soon
- [ ] archive me
EOF_BRIEF
  run_expect_success "$WORKBRANCH" done login >/dev/null
  assert_dir "$project/login/.workbranch/plans/done"
  printf '%s\n' leftover > "$project/login/leftover.txt"

  out=$(run_expect_success "$WORKBRANCH" remove login)
  assert_contains "$out" "Task directory kept because it is not empty: login"
  assert_file "$project/login/leftover.txt"
  assert_not_exists "$project/login/.workbranch"
  assert_not_exists "$project/login/TASK-WORKBRANCH.md"
  assert_not_exists "$project/login/AGENTS.md"
}
