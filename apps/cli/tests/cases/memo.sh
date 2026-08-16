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
  [ "$brief" = "# login
status: todo" ] || fail "expected status-only default brief, got: $brief"
  guidance=$(cat "$project/login/AGENTS.md")
  assert_contains "$guidance" "TASK-WORKBRANCH.md"
  assert_contains "$guidance" "../TASK-WORKBRANCH.md"
  assert_contains "$guidance" 'Run AI agent sessions from the task root (`<task>`) by default.'
  assert_contains "$guidance" "The task root is not a Git repository; it is a workbranch metadata/agent workspace."
  assert_contains "$guidance" 'The actual Git repositories live under `<task>/<repo>`.'
  assert_contains "$guidance" 'Make code changes and run Git commands inside the repo folders; keep progress in `TASK-WORKBRANCH.md` at the task root.'
  assert_contains "$guidance" 'Before editing a repo, read and follow repo-local agent instructions such as `<task>/<repo>/AGENTS.md`, `<task>/<repo>/CLAUDE.md`, or `<task>/<repo>/.claude/` when present.'
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
assert login["status"] == "todo", login'
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
	assert_contains "$guidance" 'Update only the `status:` line when the task stage changes.'
	assert_contains "$guidance" "todo → planning → in-progress → review → done"
	assert_contains "$guidance" 'When meaningful work starts, including planning, move `status:` from `todo` to `planning` immediately.'
	assert_contains "$guidance" 'Use `blocked` only from `in-progress`; when unblocked, restore `in-progress`.'
	assert_contains "$guidance" "Add checklists or notes only when the user explicitly requests them."
	assert_contains "$guidance" "workbranch done <task>"
	assert_not_contains "$guidance" "before running verification"
  assert_not_contains "$guidance" "before final response"
  assert_not_contains "$guidance" "mark completed Steps"
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
  [ "$brief" = "# login
status: todo" ] || fail "status-only 기본 brief를 기대했지만 다음을 받음: $brief"
  guidance=$(cat "$project/login/AGENTS.md")
  assert_contains "$guidance" "Workbranch 작업 안내"
	assert_contains "$guidance" '작업 단계가 바뀔 때만 `status:` 한 줄을 갱신합니다.'
	assert_contains "$guidance" "todo → planning → in-progress → review → done"
	assert_contains "$guidance" '계획을 포함한 의미 있는 작업을 시작하면 `status:`를 `todo`에서 `planning`으로 즉시 변경합니다.'
	assert_contains "$guidance" '`blocked`는 `in-progress`에서만 사용하고, blocker가 해소되면 `in-progress`로 복원합니다.'
	assert_contains "$guidance" "사용자가 명시적으로 요청한 경우에만 checklist나 note를 추가합니다."
  assert_contains "$guidance" '실제 Git repo는 `<task>/<repo>` 아래에 있습니다.'
  assert_not_contains "$guidance" "검증을 실행하기 전"
  assert_not_contains "$guidance" "final response 직전"
  return 0
}
