# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

test_memo_set_show_clear() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  run_expect_success "$WORKBRANCH" memo login "publish API 구현" >/dev/null
  assert_file "$project/login/TASK-WORKBRANCH.md"
  assert_contains "$(cat "$project/login/TASK-WORKBRANCH.md")" "publish API 구현"

  out=$(run_expect_success "$WORKBRANCH" memo login)
  assert_contains "$out" "publish API 구현"

  run_expect_success "$WORKBRANCH" memo login --clear >/dev/null
  assert_not_exists "$project/login/TASK-WORKBRANCH.md"
  run_expect_success "$WORKBRANCH" memo login --clear >/dev/null
}

test_memo_rejects_unknown_task() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" memo task9 "nope")
  assert_contains "$out" "Cannot memo: unknown task 'task9'"
  assert_not_exists "$project/task9/TASK-WORKBRANCH.md"
}

test_memo_resolves_task_from_cwd() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  run_expect_success "$WORKBRANCH" memo login "backend 작업 중" >/dev/null
  assert_file "$project/login/TASK-WORKBRANCH.md"
  assert_contains "$(cat "$project/login/TASK-WORKBRANCH.md")" "backend 작업 중"

  out=$(cd "$project/login/backend" && run_expect_success "$WORKBRANCH" memo)
  assert_contains "$out" "backend 작업 중"

  out=$(cd "$project" && run_expect_fail "$WORKBRANCH" memo)
  assert_contains "$out" "usage: workbranch memo"
}

test_memo_treats_task_argument_as_explicit_inside_task_workspace() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  run_expect_success "$WORKBRANCH" add checkout >/dev/null
  run_expect_success "$WORKBRANCH" memo login "login brief" >/dev/null
  run_expect_success "$WORKBRANCH" memo checkout "checkout brief" >/dev/null

  out=$(cd "$project/checkout/backend" && run_expect_success "$WORKBRANCH" memo login)
  assert_contains "$out" "login brief"
  assert_not_contains "$(cat "$project/checkout/TASK-WORKBRANCH.md")" "login"
}

test_add_creates_task_brief_and_agent_guidance() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  assert_file "$project/login/TASK-WORKBRANCH.md"
  assert_file "$project/login/AGENTS.md"
  assert_file "$project/login/.workbranch/notifications.jsonl"
  [ ! -s "$project/login/.workbranch/notifications.jsonl" ] || fail "expected empty notification inbox"
  assert_contains "$(cat "$project/login/TASK-WORKBRANCH.md")" "# login"
  guidance=$(cat "$project/login/AGENTS.md")
  assert_contains "$guidance" "TASK-WORKBRANCH.md"
  assert_contains "$guidance" "../TASK-WORKBRANCH.md"
  assert_not_exists "$project/login/frontend/.gitignore"
  assert_not_exists "$project/login/backend/.gitignore"
}
