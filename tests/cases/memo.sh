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
  brief=$(cat "$project/login/TASK-WORKBRANCH.md")
  assert_contains "$brief" "# login"
  assert_contains "$brief" "status: todo"
  assert_contains "$brief" "- [ ] Major: Start work"
  guidance=$(cat "$project/login/AGENTS.md")
  assert_contains "$guidance" "TASK-WORKBRANCH.md"
  assert_contains "$guidance" "../TASK-WORKBRANCH.md"
  assert_contains "$guidance" 'Run AI agent sessions from the task root (`<task>`) by default.'
  assert_contains "$guidance" "The task root is not a Git repository; it is a workbranch metadata/agent workspace."
  assert_contains "$guidance" 'The actual Git repositories live under `<task>/<repo>`.'
  assert_contains "$guidance" 'Make code changes and run Git commands inside the repo folders; keep progress in `TASK-WORKBRANCH.md` at the task root.'
  assert_not_exists "$project/login/frontend/.gitignore"
  assert_not_exists "$project/login/backend/.gitignore"
  return 0
}


test_task_status_explicit_and_derived() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Login work

status: review

- [x] design
- [ ] verify
EOF_BRIEF
  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["status"] == "review", login
assert login["progressDone"] == 1, login
assert login["progressTotal"] == 2, login'

  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Login work

- [ ] design
- [ ] verify
EOF_BRIEF
  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["status"] == "todo", login'

  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Login work

- [x] design
- [ ] verify
EOF_BRIEF
  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["status"] == "in-progress", login'

  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Login work

- [x] design
- [x] verify
EOF_BRIEF
  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["status"] == "done", login'

  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Login work

status: todo

- [ ] design
EOF_BRIEF
  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["status"] == "todo", login'

  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Login work
EOF_BRIEF
  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["status"] == "todo", login'

  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Login work

status: strange

- [ ] design
EOF_BRIEF
  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["status"] == "", login'
}

test_task_checklist_counts() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Login work

- [x] done lower
- [X] done upper
- [ ] todo
```md
- [x] ignored code
```
- not checkbox
EOF_BRIEF

  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["progressDone"] == 2, login
assert login["progressTotal"] == 3, login'
}

test_task_current_item() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Login work

- [x] design
- [ ] implement API
- [ ] verify
EOF_BRIEF

  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["currentItem"] == "implement API", login'
}

test_add_agents_md_describes_status_update_protocol() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  guidance=$(cat "$project/login/AGENTS.md")
  assert_contains "$guidance" "Task progress update protocol"
  assert_contains "$guidance" "starting or resuming meaningful work"
  assert_contains "$guidance" "before running verification"
  assert_contains "$guidance" "before final response"
  assert_contains "$guidance" "todo | planning | in-progress | review | blocked | done"
  assert_contains "$guidance" "starting meaningful work, including planning, move status from todo to planning"
}


test_preferred_language_generates_korean_task_guidance() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  cat >> "$project/.workbranch.config" <<'CONFIG'
PREFERRED_LANGUAGE ko
CONFIG
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  brief=$(cat "$project/login/TASK-WORKBRANCH.md")
  assert_contains "$brief" "상태: todo"
  assert_contains "$brief" "status: todo"
  assert_contains "$brief" "- [ ] 주요: 작업 시작"
  guidance=$(cat "$project/login/AGENTS.md")
  assert_contains "$guidance" "Workbranch 작업 안내"
  assert_contains "$guidance" "작업 진행 업데이트 규칙"
  assert_contains "$guidance" '실제 Git repo는 `<task>/<repo>` 아래에 있습니다.'
  return 0
}
