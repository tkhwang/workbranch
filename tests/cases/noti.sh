# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

test_noti_add_list_clear() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  out=$(run_expect_success "$WORKBRANCH" noti list login)
  [ -z "$out" ] || fail "expected fresh noti list to be empty, got: $out"

  run_expect_success "$WORKBRANCH" noti add login "tests passed" >/dev/null
  run_expect_success "$WORKBRANCH" noti add login "needs input" >/dev/null
  assert_file "$project/login/.workbranch/notifications.jsonl"

  out=$(run_expect_success "$WORKBRANCH" noti list login)
  case "$out" in
    *"tests passed"*"needs input"*) : ;;
    *) fail "expected notifications oldest-first, got: $out" ;;
  esac

  run_expect_success "$WORKBRANCH" noti clear login >/dev/null
  out=$(run_expect_success "$WORKBRANCH" noti list login)
  [ -z "$out" ] || fail "expected cleared noti list to be empty, got: $out"
}

test_noti_escapes_control_characters() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  run_expect_success "$WORKBRANCH" noti add login $'needs\aattention' >/dev/null

  python3 -c 'import json, sys
path = sys.argv[1]
line = open(path, "rb").read()
assert b"\x07" not in line, line
d = json.loads(line)
assert d["text"] == "needs\x07attention", d' "$project/login/.workbranch/notifications.jsonl" || return 1
  out=$(run_expect_success "$WORKBRANCH" noti list login)
  [ "$out" = $'needs\aattention' ] || fail "expected notification control char round-trip"
}

test_noti_rejects_unknown_task() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" noti add task9 "nope")
  assert_contains "$out" "Cannot noti: unknown task 'task9'"
  assert_not_exists "$project/task9/.workbranch/notifications.jsonl"
}

test_noti_state_removed_with_workspace() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  run_expect_success "$WORKBRANCH" noti add login "tests passed" >/dev/null

  run_expect_success "$WORKBRANCH" remove login >/dev/null
  assert_not_exists "$project/login"

  run_expect_success "$WORKBRANCH" add keep >/dev/null
  run_expect_success "$WORKBRANCH" noti add keep "needs input" >/dev/null
  printf '%s\n' "user note" > "$project/keep/notes.txt"

  out=$(run_expect_success "$WORKBRANCH" remove keep)
  assert_file "$project/keep/notes.txt"
  assert_not_exists "$project/keep/TASK-WORKBRANCH.md"
  assert_not_exists "$project/keep/AGENTS.md"
  assert_not_exists "$project/keep/.workbranch/notifications.jsonl"
  assert_contains "$out" "Task directory kept because it is not empty: keep"
}
