# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

archive_trigger_file_for() {
  find "$1/.workbranch/plans/done" -type f -name '*.md' 2>/dev/null | sort | tail -1
}

write_trigger_brief() {
  task_dir=$1
  title=$2
  cat > "$task_dir/TASK-WORKBRANCH.md" <<EOF_BRIEF
# $title
status: review
- [x] implement
- [ ] verify
## Notes
- trigger note
EOF_BRIEF
}

commit_task_repo_file() {
  repo_path=$1
  file_name=$2
  contents=$3
  git -C "$repo_path" config user.name "Workbranch Test"
  git -C "$repo_path" config user.email "workbranch-test@example.com"
  printf '%s\n' "$contents" > "$repo_path/$file_name"
  git -C "$repo_path" add "$file_name"
  git -C "$repo_path" commit -m "$contents" >/dev/null
}

test_land_archive_prompt_yes_archives_and_no_keeps_brief() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  write_trigger_brief "$project/login" "Land Plan"
  commit_task_repo_file "$project/login/frontend" land.txt "land frontend"
  commit_task_repo_file "$project/login/backend" land.txt "land backend"

  out=$(printf '\n' | WORKBRANCH_TEST_ARCHIVE_TIMESTAMP=20260616-130000 run_expect_success env WORKBRANCH_ALLOW_NON_TTY_PROMPT=1 "$WORKBRANCH" land login)
  assert_contains "$out" "$(printf '\n[*] Mark plan \"Land Plan\" done and archive? [Y/n]')"
  assert_contains "$out" "Archived plan:"
  archive_file=$(archive_trigger_file_for "$project/login")
  assert_file "$archive_file"
  archive=$(cat "$archive_file")
  assert_contains "$archive" "completed_via: land"
  assert_contains "$archive" "# Land Plan"
  assert_contains "$archive" "status: done"
  assert_not_contains "$(cat "$project/login/TASK-WORKBRANCH.md")" "# Land Plan"

  run_expect_success "$WORKBRANCH" add keep >/dev/null
  write_trigger_brief "$project/keep" "Keep Land Plan"
  commit_task_repo_file "$project/keep/frontend" keep-land.txt "keep land frontend"
  commit_task_repo_file "$project/keep/backend" keep-land.txt "keep land backend"
  out=$(printf 'n\n' | run_expect_success env WORKBRANCH_ALLOW_NON_TTY_PROMPT=1 "$WORKBRANCH" land keep)
  assert_contains "$out" "$(printf '\n[*] Mark plan \"Keep Land Plan\" done and archive? [Y/n]')"
  assert_contains "$(cat "$project/keep/TASK-WORKBRANCH.md")" "# Keep Land Plan"
  assert_not_exists "$project/keep/.workbranch/plans/done"
}

test_land_archive_prompt_eof_keeps_brief() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add eof >/dev/null
  write_trigger_brief "$project/eof" "EOF Land Plan"
  commit_task_repo_file "$project/eof/frontend" eof-land.txt "eof land frontend"
  commit_task_repo_file "$project/eof/backend" eof-land.txt "eof land backend"

  out=$(WORKBRANCH_TEST_ARCHIVE_TIMESTAMP=20260616-130500 run_expect_success env WORKBRANCH_ALLOW_NON_TTY_PROMPT=1 "$WORKBRANCH" land eof </dev/null)
  assert_contains "$out" "$(printf '\n[*] Mark plan \"EOF Land Plan\" done and archive? [Y/n]')"
  assert_not_contains "$out" "Archived plan:"
  assert_contains "$(cat "$project/eof/TASK-WORKBRANCH.md")" "# EOF Land Plan"
  assert_not_exists "$project/eof/.workbranch/plans/done"
}

test_finalize_archive_prompt_records_finalize() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  write_trigger_brief "$project/feat-login" "Finalize Plan"
  commit_task_repo_file "$project/feat-login/frontend" finalize.txt "finalize frontend"
  commit_task_repo_file "$project/feat-login/backend" finalize.txt "finalize backend"

  out=$(printf 'y\n' | WORKBRANCH_TEST_ARCHIVE_TIMESTAMP=20260616-131000 run_expect_success env WORKBRANCH_ALLOW_NON_TTY_PROMPT=1 "$WORKBRANCH" finalize feat-login)
  assert_contains "$out" "Landing task"
  assert_contains "$out" "$(printf '\n[*] Mark plan \"Finalize Plan\" done and archive? [Y/n]')"
  archive_file=$(archive_trigger_file_for "$project/feat-login")
  assert_file "$archive_file"
  assert_contains "$(cat "$archive_file")" "completed_via: finalize"
}

test_pull_archive_prompt_requires_all_filtered_repos_merged() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  write_trigger_brief "$project/login" "Pull Filter Plan"
  commit_task_repo_file "$project/login/frontend" pull-frontend.txt "pull frontend"
  commit_task_repo_file "$project/login/backend" pull-backend.txt "pull backend"
  git -C "$project/login/frontend" push origin feature/login:master >/dev/null 2>&1

  out=$(printf 'y\n' | WORKBRANCH_TEST_ARCHIVE_TIMESTAMP=20260616-132000 run_expect_success env WORKBRANCH_ALLOW_NON_TTY_PROMPT=1 "$WORKBRANCH" pull)
  assert_not_contains "$out" "Mark plan \"Pull Filter Plan\" done and archive?"
  assert_contains "$(cat "$project/login/TASK-WORKBRANCH.md")" "# Pull Filter Plan"
  assert_not_exists "$project/login/.workbranch/plans/done"

  run_expect_success "$WORKBRANCH" add filtered >/dev/null
  write_trigger_brief "$project/filtered" "Pull Filtered Repo Plan"
  commit_task_repo_file "$project/filtered/frontend" filtered-frontend.txt "filtered frontend"
  commit_task_repo_file "$project/filtered/backend" filtered-backend.txt "filtered backend"
  git -C "$project/filtered/frontend" push origin feature/filtered:master >/dev/null 2>&1

  out=$(printf 'y\n' | WORKBRANCH_TEST_ARCHIVE_TIMESTAMP=20260616-132000 run_expect_success env WORKBRANCH_ALLOW_NON_TTY_PROMPT=1 "$WORKBRANCH" pull --repo frontend)
  assert_contains "$out" "$(printf '\n[*] Mark plan \"Pull Filtered Repo Plan\" done and archive? [Y/n]')"
  archive_file=$(archive_trigger_file_for "$project/filtered")
  assert_file "$archive_file"
  assert_contains "$(cat "$archive_file")" "completed_via: pull"
  assert_contains "$(cat "$project/login/TASK-WORKBRANCH.md")" "# Pull Filter Plan"
}

test_pull_archive_prompt_skips_trivial_ancestor_without_task_commits() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add empty >/dev/null
  write_trigger_brief "$project/empty" "Empty Branch Plan"
  commit_to_remote_master frontend upstream-only

  out=$(printf 'y\n' | run_expect_success env WORKBRANCH_ALLOW_NON_TTY_PROMPT=1 "$WORKBRANCH" pull --repo frontend)
  assert_not_contains "$out" "Mark plan \"Empty Branch Plan\" done and archive?"
  assert_contains "$(cat "$project/empty/TASK-WORKBRANCH.md")" "# Empty Branch Plan"
  assert_not_exists "$project/empty/.workbranch/plans/done"
}
