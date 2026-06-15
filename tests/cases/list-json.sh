# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

json_assert() {
  python3 - "$@"
}

test_list_json_shape() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  run_expect_success "$WORKBRANCH" memo login "견적 \"API\" \\ 경로" >/dev/null
  run_expect_success "$WORKBRANCH" noti add login "tests passed" >/dev/null
  run_expect_success "$WORKBRANCH" noti add login "needs input" >/dev/null

  project_real=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$project")
  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json, sys
expected_root = sys.argv[1]
d = json.load(sys.stdin)
assert d["schemaVersion"] == 1, d
assert d["project"] == "fullstack", d
assert d["root"] == expected_root, d
assert [t["name"] for t in d["tasks"]] == ["login"], d
login = d["tasks"][0]
assert login["path"] == f"{expected_root}/login", login
assert login["memoTitle"] == "견적 \"API\" \\ 경로", login
assert login["notiCount"] == 2, login
assert [r["name"] for r in login["repos"]] == ["frontend", "backend"], login
for repo in login["repos"]:
    assert set(repo) == {"name", "branch", "dirty"}, repo
    assert repo["branch"] == "feature/login", repo
    assert repo["dirty"] is False, repo' "$project_real"
}

test_list_json_no_color_no_log_noise() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  out=$(run_expect_success env -u NO_COLOR WORKBRANCH_COLOR=always "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)'
  assert_not_contains "$out" $'\033['
  assert_not_contains "$out" "[*]"
}

test_list_json_escapes_control_characters() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  run_expect_success "$WORKBRANCH" memo login $'needs\aattention' >/dev/null

  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json, sys
d = json.load(sys.stdin)
assert d["tasks"][0]["memoTitle"] == "needs\x07attention", d'
  assert_contains "$out" "\\u0007"
}

test_list_json_dirty_flag() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  printf '%s\n' dirty > "$project/login/frontend/dirty.txt"

  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json, sys
d = json.load(sys.stdin)
repos = {r["name"]: r for r in d["tasks"][0]["repos"]}
assert repos["frontend"]["dirty"] is True, repos
assert repos["backend"]["dirty"] is False, repos'
}

test_list_json_skips_stale_and_partial_task_dirs() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  mkdir -p "$project/partial/frontend"
  mkdir -p "$project/stale/frontend" "$project/stale/backend"
  rm -f "$project/stale/frontend/.git" "$project/stale/backend/.git"

  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json, sys
d = json.load(sys.stdin)
names = [t["name"] for t in d["tasks"]]
assert names == ["login"], names'
}


test_list_json_schema_v1_progress_shape() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d["schemaVersion"] == 1, d
login=d["tasks"][0]
for key in ["status", "progressDone", "progressTotal", "currentItem", "updatedAt"]:
    assert key in login, login
assert login["status"] == "todo", login
assert login["progressDone"] == 0, login
assert login["progressTotal"] >= 1, login
assert isinstance(login["currentItem"], str), login
assert isinstance(login["updatedAt"], int), login
assert login["updatedAt"] > 0, login'
}

test_list_json_progress_and_status() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Login work

status: blocked

- [x] design
- [ ] waiting for credentials
EOF_BRIEF

  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["memoTitle"] == "Login work", login
assert login["status"] == "blocked", login
assert login["progressDone"] == 1, login
assert login["progressTotal"] == 2, login
assert login["currentItem"] == "waiting for credentials", login'
}

test_list_json_plan_title() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Login work

plan: Authentication hardening slice
status: in-progress

- [x] inspect current auth flow
- [ ] implement session expiry guard
EOF_BRIEF

  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["planTitle"] == "Authentication hardening slice", login
assert login["memoTitle"] == "Login work", login
assert login["currentItem"] == "implement session expiry guard", login'
}

test_list_json_currentItem_escaped() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  printf '# Login\n\n- [ ] quote " slash \\ bell \a\n' > "$project/login/TASK-WORKBRANCH.md"

  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
expected = "quote \" slash \\ bell " + chr(7)
assert login["currentItem"] == expected, login' || return 1
  assert_contains "$out" "\\u0007"
}
test_list_json_legacy_memo_no_checkboxes() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Legacy memo

## Current work
- plain bullet only
EOF_BRIEF

  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["status"] == "todo", login
assert login["progressDone"] == 0, login
assert login["progressTotal"] == 0, login
assert login["currentItem"] == "", login'
}


test_list_json_includes_checklist_items_depth() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Login work

status: in-progress

- [x] Major: design
  - [ ] API
    - [ ] edge case
EOF_BRIEF

  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d["schemaVersion"] == 1, d
login=d["tasks"][0]
assert login["items"] == [
  {"text":"Major: design","checked":True,"depth":0},
  {"text":"API","checked":False,"depth":1},
  {"text":"edge case","checked":False,"depth":2},
], login'
}

test_list_json_plan_sections_shape_and_aggregate() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Login work

status: in-progress
plan: Legacy label

- [x] preface done

## Plan: Backend
- [x] API contract
- [x] Mapper

## Plan: Frontend
- [x] Package sync
  - [x] Generated types
- [ ] Smoke test

## Notes
- [ ] this checkbox is a note, not a step
EOF_BRIEF

  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["planTitle"] == "Frontend", login
assert login["status"] == "in-progress", login
assert login["progressDone"] == 5, login
assert login["progressTotal"] == 6, login
assert login["currentItem"] == "Smoke test", login
assert [item["text"] for item in login["items"]] == ["preface done", "API contract", "Mapper", "Package sync", "Generated types", "Smoke test"], login
assert len(login["plans"]) == 3, login
assert [(p["title"], p["index"], p["status"], p["progressDone"], p["progressTotal"], p["currentItem"]) for p in login["plans"]] == [
    ("Legacy label", 0, "done", 1, 1, ""),
    ("Backend", 1, "done", 2, 2, ""),
    ("Frontend", 2, "in-progress", 2, 3, "Smoke test"),
], login
assert [item["text"] for item in login["plans"][2]["items"]] == ["Package sync", "Generated types", "Smoke test"], login'
}

test_list_json_implicit_and_empty_plans() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Login work

plan: Auth hardening

- [x] inspect
- [ ] implement
EOF_BRIEF

  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["planTitle"] == "Auth hardening", login
assert len(login["plans"]) == 1, login
plan=login["plans"][0]
assert (plan["title"], plan["index"], plan["status"], plan["progressDone"], plan["progressTotal"], plan["currentItem"]) == ("Auth hardening", 0, "in-progress", 1, 2, "implement"), login'

  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_EMPTY'
# Empty work

plan: Empty plan

## Notes
-
EOF_EMPTY
  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["plans"] == [], login
assert login["progressDone"] == 0 and login["progressTotal"] == 0, login
assert login["currentItem"] == "", login'
}

test_list_json_duplicate_plan_titles_keep_distinct_indexes() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
# Login work

## Plan: Review
- [x] first review

## Plan: Review
- [ ] second review
EOF_BRIEF

  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["planTitle"] == "Review", login
assert [(p["title"], p["index"], p["status"], p["currentItem"]) for p in login["plans"]] == [("Review", 0, "done", ""), ("Review", 1, "todo", "second review")], login'
}


test_list_global_json_projects_and_errors() {
  new_fixture
  project="$FIXTURE_PROJECT"
  xdg="$TMP_ROOT/xdg"
  mkdir -p "$xdg/workbranch-companion"
  cd "$project" || return 1
  run_expect_success env XDG_CONFIG_HOME="$xdg" "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  printf '\n# manual note\n- /tmp/workbranch-missing-root\n' >> "$xdg/workbranch-companion/projects.md"

  out=$(cd "$TMP_ROOT" && run_expect_success env XDG_CONFIG_HOME="$xdg" "$WORKBRANCH" list --global --json)
  printf '%s' "$out" | python3 -c 'import json,sys,os
expected=os.path.realpath(sys.argv[1])
d=json.load(sys.stdin)
assert d["schemaVersion"] == 1, d
assert [p["root"] for p in d["projects"]] == [expected], d
assert d["projects"][0]["tasks"][0]["name"] == "login", d
assert d["errors"] and d["errors"][0]["root"] == "/tmp/workbranch-missing-root", d
assert "message" in d["errors"][0], d' "$project"
}


test_list_global_uses_stable_launcher_after_changing_directory() {
  new_fixture
  project="$FIXTURE_PROJECT"
  xdg="$TMP_ROOT/xdg"
  cd "$project" || return 1
  run_expect_success env XDG_CONFIG_HOME="$xdg" "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  out=$(cd "$REPO_ROOT" && run_expect_success env XDG_CONFIG_HOME="$xdg" bin/workbranch list --global --json)
  printf '%s' "$out" | python3 -c 'import json,sys,os
expected=os.path.realpath(sys.argv[1])
d=json.load(sys.stdin)
assert [p["root"] for p in d["projects"]] == [expected], d
assert d["projects"][0]["tasks"][0]["name"] == "login", d
assert d["errors"] == [], d' "$project"

  human=$(cd "$REPO_ROOT" && run_expect_success env XDG_CONFIG_HOME="$xdg" bin/workbranch list --global)
  assert_contains "$human" "Project: fullstack"
  assert_contains "$human" "login"
}


test_list_global_json_all_roots_failure_is_nonzero() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  xdg="$TMP_ROOT/xdg"
  mkdir -p "$xdg/workbranch-companion"
  cat > "$xdg/workbranch-companion/projects.md" <<'EOF_REGISTRY'
# workbranch companion projects

## projects
- /tmp/workbranch-missing-a
- /tmp/workbranch-missing-b
EOF_REGISTRY

  out=$(cd "$TMP_ROOT" && run_expect_fail env XDG_CONFIG_HOME="$xdg" "$WORKBRANCH" list --global --json)
  printf '%s' "$out" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d["schemaVersion"] == 1, d
assert d["projects"] == [], d
assert len(d["errors"]) == 2, d'
}
