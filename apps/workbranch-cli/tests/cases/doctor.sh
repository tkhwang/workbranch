# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

doctor_with_status() {
  "$WORKBRANCH" doctor "$@" 2>&1
  printf 'status=%s' "$?"
}

test_doctor_healthy_project_exits_zero() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null

  out=$(doctor_with_status)
  assert_contains "$out" "Base repos"
  assert_contains "$out" "Task workspaces"
  assert_contains "$out" "feat-login"
  assert_contains "$out" "healthy"
  assert_contains "$out" "doctor found no issues"
  assert_contains "$out" "status=0"
}

test_doctor_detects_partial_workspace() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  git -C "$project/_base/backend" worktree remove --force "$project/feat-login/backend" >/dev/null 2>&1

  out=$(doctor_with_status)
  assert_contains "$out" "feat-login"
  assert_contains "$out" "partial"
  assert_contains "$out" "backend worktree missing"
  assert_contains "$out" "status=1"
}

test_doctor_repo_scope_ignores_filtered_out_task_damage() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  git -C "$project/_base/frontend" worktree remove --force "$project/feat-login/frontend" >/dev/null 2>&1

  out=$(doctor_with_status --repo backend)
  assert_contains "$out" "feat-login"
  assert_contains "$out" "healthy"
  assert_not_contains "$out" "frontend worktree missing"
  assert_contains "$out" "status=0"

  git -C "$project/_base/backend" worktree remove --force "$project/feat-login/backend" >/dev/null 2>&1
  out=$(doctor_with_status --repo backend)
  assert_contains "$out" "feat-login"
  assert_contains "$out" "backend"
  assert_contains "$out" "status=1"
}

test_doctor_repo_scope_ignores_stale_dir_with_only_filtered_out_repo() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  mkdir -p "$project/old-task/frontend"

  out=$(doctor_with_status --repo backend)
  assert_not_contains "$out" "old-task"
  assert_not_contains "$out" "stale"
  assert_contains "$out" "doctor found no issues"
  assert_contains "$out" "status=0"
}

test_doctor_reports_registered_task_worktree_on_wrong_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  git -C "$project/feat-login/backend" checkout -b wrong-doctor-branch >/dev/null 2>&1

  out=$(doctor_with_status)
  assert_contains "$out" "feat-login"
  assert_contains "$out" "partial"
  assert_contains "$out" "backend expected branch feat/login, got wrong-doctor-branch"
  assert_contains "$out" "status=1"
}

test_doctor_reports_base_branch_drift() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  git -C "$project/_base/backend" checkout -b hotfix >/dev/null 2>&1

  out=$(doctor_with_status)
  assert_contains "$out" "backend"
  assert_contains "$out" "expected master, got hotfix"
  assert_contains "$out" "status=1"
}

test_doctor_reports_stale_directory_with_remove_hint() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  mkdir -p "$project/old-task/frontend" "$project/old-task/backend"

  out=$(doctor_with_status)
  assert_contains "$out" "old-task"
  assert_contains "$out" "stale"
  assert_contains "$out" "workbranch remove old-task"
  assert_contains "$out" "status=1"
}

test_doctor_flags_unparseable_brief() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  cat > "$project/feat-login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
status: done
- [x] did the work
- [ ] verify
EOF_BRIEF

  out=$(doctor_with_status)
  assert_contains "$out" "Task briefs"
  assert_contains "$out" "feat-login brief not parseable"
  assert_contains "$out" "fix: workbranch doctor --fix"
  assert_contains "$out" "status=1"
}

test_doctor_brief_false_positive_guards() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  run_expect_success "$WORKBRANCH" add feat-notes >/dev/null
  cat > "$project/feat-login/TASK-WORKBRANCH.md" <<'EOF_HEALTHY'
# Login work
status: review
- [x] implemented
EOF_HEALTHY
  cat > "$project/feat-notes/TASK-WORKBRANCH.md" <<'EOF_NOTES'
Loose notes only

Some scratch text without tracked status or checklist.
EOF_NOTES

  out=$(doctor_with_status)
  assert_contains "$out" "doctor found no issues"
  assert_not_contains "$out" "brief not parseable"
  assert_contains "$out" "status=0"
}

test_doctor_ignores_fenced_brief_examples() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  cat > "$project/feat-login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
Example only:

```markdown
status: done
- [x] did the work
- [ ] verify
```
EOF_BRIEF

  out=$(doctor_with_status)
  assert_contains "$out" "doctor found no issues"
  assert_not_contains "$out" "brief not parseable"
  assert_contains "$out" "status=0"

  fix_out=$(doctor_with_status --fix)
  assert_contains "$fix_out" "doctor found no issues"
  assert_contains "$fix_out" "status=0"
  if grep -q '^# feat-login$' "$project/feat-login/TASK-WORKBRANCH.md"; then
    fail "fenced-only example was incorrectly repaired"
  fi
}

test_doctor_flags_multi_h2_unparseable_brief() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  cat > "$project/feat-login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
status: done

## Current work
- [x] did the work
- [ ] verify
EOF_BRIEF

  out=$(doctor_with_status)
  assert_contains "$out" "feat-login brief not parseable"
  assert_contains "$out" "status=1"
}

test_doctor_rejects_unexpected_args_and_flags() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_fail "$WORKBRANCH" doctor feat-login)
  assert_contains "$out" "usage: workbranch doctor [--fix] [--repo <repo>]"

  out=$(run_expect_fail "$WORKBRANCH" doctor --bad)
  assert_contains "$out" "usage: workbranch doctor [--fix] [--repo <repo>]"
}

test_doctor_fix_prunes_stale_worktree_registration() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  git -C "$project/_base/frontend" worktree add "$TMP_ROOT/ghost-frontend" -b ghost-doctor HEAD >/dev/null 2>&1
  rm -rf "$TMP_ROOT/ghost-frontend"

  out=$(doctor_with_status)
  assert_contains "$out" "Prunable worktrees"
  assert_contains "$out" "frontend"
  assert_contains "$out" "workbranch doctor --fix"
  assert_contains "$out" "status=1"

  fix_out=$(doctor_with_status --fix --repo frontend)
  assert_contains "$fix_out" "Pruned stale worktree registrations: frontend"
  assert_contains "$fix_out" "status=0"
  worktrees=$(git -C "$project/_base/frontend" worktree list --porcelain)
  assert_not_contains "$worktrees" "prunable"
}

test_doctor_fix_prepends_h1_heading() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  cat > "$project/feat-login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
status: done
- [x] did the work
- [ ] verify
EOF_BRIEF

  fix_out=$(doctor_with_status --fix)
  assert_contains "$fix_out" "Repaired task briefs"
  assert_contains "$fix_out" "status=0"
  head -n 1 "$project/feat-login/TASK-WORKBRANCH.md" | grep -q '^# feat-login$' || fail "no H1 prepended"
  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
t=json.load(sys.stdin)["tasks"][0]
assert len(t["plans"]) == 1, t
assert t["progressTotal"] == 2 and t["progressDone"] == 1, t'
  clean_out=$(doctor_with_status)
  assert_contains "$clean_out" "doctor found no issues"
  assert_contains "$clean_out" "status=0"
}

test_doctor_fix_ignores_fenced_h1_before_repair() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  cat > "$project/feat-login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
```markdown
# example
```

status: done
- [x] did the work
- [ ] verify
EOF_BRIEF

  fix_out=$(doctor_with_status --fix)
  assert_contains "$fix_out" "Repaired task briefs"
  assert_contains "$fix_out" "status=0"
  head -n 1 "$project/feat-login/TASK-WORKBRANCH.md" | grep -q '^# feat-login$' || fail "no H1 prepended"
  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
t=json.load(sys.stdin)["tasks"][0]
assert len(t["plans"]) == 1, t
assert t["progressTotal"] == 2 and t["progressDone"] == 1, t'
  clean_out=$(doctor_with_status)
  assert_contains "$clean_out" "doctor found no issues"
  assert_contains "$clean_out" "status=0"
}

test_doctor_fix_is_idempotent() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  cat > "$project/feat-login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
status: done
- [x] did the work
EOF_BRIEF

  first_out=$(doctor_with_status --fix)
  assert_contains "$first_out" "status=0"
  second_out=$(doctor_with_status --fix)
  assert_contains "$second_out" "doctor found no issues"
  assert_contains "$second_out" "status=0"
  h1_count=$(grep -c '^# feat-login$' "$project/feat-login/TASK-WORKBRANCH.md")
  [ "$h1_count" -eq 1 ] || fail "expected one H1, got $h1_count"
}

test_doctor_fix_multi_h2_keeps_manual_follow_up_nonzero() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  cat > "$project/feat-login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
status: done

## Current work
- [x] did the work
- [ ] verify
EOF_BRIEF

  fix_out=$(doctor_with_status --fix)
  assert_contains "$fix_out" "Repaired task briefs"
  assert_contains "$fix_out" "Manual task brief follow-up"
  assert_contains "$fix_out" "doctor fixed 1 issue(s); 1 require manual action"
  assert_contains "$fix_out" "status=1"
  head -n 1 "$project/feat-login/TASK-WORKBRANCH.md" | grep -q '^# feat-login$' || fail "no H1 prepended"
  h1_count=$(grep -c '^# feat-login$' "$project/feat-login/TASK-WORKBRANCH.md")
  [ "$h1_count" -eq 1 ] || fail "expected one H1, got $h1_count"
  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
t=json.load(sys.stdin)["tasks"][0]
assert len(t["plans"]) == 1, t
assert t["progressTotal"] == 0 and t["progressDone"] == 0, t'

  follow_up_out=$(doctor_with_status)
  assert_contains "$follow_up_out" "Manual task brief follow-up"
  assert_contains "$follow_up_out" "feat-login"
  assert_contains "$follow_up_out" "status=1"
}


test_doctor_fix_h2_status_keeps_manual_follow_up_nonzero() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  cat > "$project/feat-login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
## Current status
status: blocked
EOF_BRIEF

  fix_out=$(doctor_with_status --fix)
  assert_contains "$fix_out" "Repaired task briefs"
  assert_contains "$fix_out" "Manual task brief follow-up"
  assert_contains "$fix_out" "doctor fixed 1 issue(s); 1 require manual action"
  assert_contains "$fix_out" "status=1"
  head -n 1 "$project/feat-login/TASK-WORKBRANCH.md" | grep -q '^# feat-login$' || fail "no H1 prepended"
  h1_count=$(grep -c '^# feat-login$' "$project/feat-login/TASK-WORKBRANCH.md")
  [ "$h1_count" -eq 1 ] || fail "expected one H1, got $h1_count"
  out=$(run_expect_success "$WORKBRANCH" list --json)
  printf '%s' "$out" | python3 -c 'import json,sys
t=json.load(sys.stdin)["tasks"][0]
assert len(t["plans"]) == 1, t
assert t["status"] == "todo", t
assert t["progressTotal"] == 0 and t["progressDone"] == 0, t'

  follow_up_out=$(doctor_with_status)
  assert_contains "$follow_up_out" "Manual task brief follow-up"
  assert_contains "$follow_up_out" "feat-login"
  assert_contains "$follow_up_out" "status=1"
}

test_doctor_fix_does_not_delete_stale_task_directory() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  mkdir -p "$project/old-task/frontend" "$project/old-task/backend"

  out=$(doctor_with_status --fix)
  assert_contains "$out" "old-task"
  assert_contains "$out" "workbranch remove old-task"
  assert_contains "$out" "status=1"
  assert_dir "$project/old-task"
}
