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
