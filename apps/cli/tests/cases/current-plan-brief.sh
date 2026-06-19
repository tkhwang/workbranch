# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

test_current_plan_brief_h1_status_and_active_json_contract() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  cat > "$project/login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
status: blocked
plan: stale-label
- [x] orphan legacy step ignored

# Done Plan
status: done
- [x] archived work

# Active Plan
status: review
- [x] inspect
  - [x] map callers
- [ ] verify

## Notes
- [ ] this note is not a step

# Later Plan
- [ ] future work

```markdown
# Fenced Plan
status: done
- [x] ignored
```
EOF_BRIEF

  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
login=json.load(sys.stdin)["tasks"][0]
assert login["memoTitle"] == "Active Plan", login
assert login["planTitle"] == "Active Plan", login
assert login["status"] == "review", login
assert login["progressDone"] == 2, login
assert login["progressTotal"] == 3, login
assert login["currentItem"] == "verify", login
assert [item["text"] for item in login["items"]] == ["inspect", "map callers", "verify"], login
assert [(p["title"], p["index"], p["status"], p["progressDone"], p["progressTotal"], p["currentItem"]) for p in login["plans"]] == [
  ("Done Plan", 0, "done", 1, 1, ""),
  ("Active Plan", 1, "review", 2, 3, "verify"),
  ("Later Plan", 2, "todo", 0, 1, "future work"),
], login
assert [item["depth"] for item in login["plans"][1]["items"]] == [0,1,0], login'
}
