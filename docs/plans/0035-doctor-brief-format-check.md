# 0035 Doctor Brief Format Check Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` before every behavior change. Make source changes under `apps/workbranch-cli/src/workbranch/**`, rebuild with `apps/workbranch-cli/scripts/build-workbranch.sh`, then verify syntax checks, targeted tests, `apps/workbranch-cli/tests/run.sh`, and `git diff --check`. Do not edit generated `apps/workbranch-cli/bin/workbranch` or root `bin/workbranch` by hand.

**Goal:** Extend `workbranch doctor` to detect task briefs (`TASK-WORKBRANCH.md`) that contain tracked content but parse to **zero plans** — i.e. they are invisible in the CLI HUD and the Companion app — and, with `--fix`, apply the one safe mechanical repair: prepend a `# <task>` H1 heading. This makes the brief parseable again and restores direct root-level checklist/progress visibility; if the lost checklist is nested under `## …` note sections, the H1 prepend restores only the plan title/status and reports the remaining section-promotion work as manual.

**Architecture:** Doctor stays read-only by default and exits non-zero when any issue is found. The new check reuses the existing brief parser (`task_load_plans` / `TASK_PLAN_COUNT` in `apps/workbranch-cli/src/workbranch/lib/task-state.sh`, sourced before `apps/workbranch-cli/src/workbranch/commands/doctor.sh`) as the single source of truth — it does **not** reimplement parsing and does **not** change the parser. `--fix` performs only the non-destructive, idempotent repair of inserting a leading H1 when the brief has tracked content but no `# ` heading. Multi-section restructuring (promoting `## …` sections to plans) is never auto-run; it is reported as manual.

**Tech Stack:** Portable Bash, line-oriented `TASK-WORKBRANCH.md`, generated single-file CLI via `apps/workbranch-cli/scripts/build-workbranch.sh`, integration tests in `apps/workbranch-cli/tests/run.sh`.

---

## Problem Statement

A `TASK-WORKBRANCH.md` that has real tracking content (a `status:` line and/or `- [ ]` checklist items) but **no `# <plan>` H1 heading** parses to zero plans. This is intentional, documented parser behavior (see Current Repo Evidence), so the CLI HUD and the Companion app correctly show the task as empty — no title, no progress, no checklist.

Observed in the wild: `monask-fullstack/feat-task1` has a rich, recently-updated brief (multiple `## Current …` sections, dozens of `[x]` steps) but starts with `status: done` and uses `##` headings throughout. It has no H1, so `workbranch list --json` returns `"plans": []`, `"status": "todo"`, `"progressDone": 0`, and the Companion shows nothing — while sibling tasks `feat-task2`/`feat-task3` (which start with `# feat-taskN`) display normally. For this multi-`##` shape, `--fix` can safely create the missing H1 so the task has a parseable plan again, but it must also tell the user that the `##` sections still need manual promotion to `# ` plans if those checklists should count as active plan progress.

Today `workbranch doctor` checks only git/worktree plumbing (base branch, worktree registration, prunable registrations). It reports this task as `healthy` and the project as `doctor found no issues`, so the failure mode is invisible to the one command meant to catch a broken environment.

## Current Repo Evidence

- `apps/workbranch-cli/src/workbranch/lib/task-state.sh` `task_load_plans`: a plan is registered **only** on an H1 `# <title>` line (`task_plan_add`). With `current_plan = -1` (no H1 seen), `status:` lines are skipped (`current_plan >= 0` guard) and checklist items are skipped (`[ "$current_plan" -ge 0 ] || continue`). `H2+` (`^#{2,}`) headings reset `current_plan = -1`, so their checkboxes are treated as notes. Result: a no-H1 brief yields `TASK_PLAN_COUNT = 0`; a repaired brief with checklists only under `##` sections yields one plan but still `progressTotal = 0`.
- The "no H1 ⇒ zero plans" contract is **locked by existing tests** in `apps/workbranch-cli/tests/cases/list-json.sh`: `test_list_json_implicit_and_empty_plans` (a `plan:` line + checkboxes but no H1 asserts `plans == []`, progress `0/0`) and `test_list_json_legacy_memo_no_checkboxes`. Therefore the parser must not change; the fix belongs in doctor.
- `apps/workbranch-cli/src/workbranch/lib/task-state.sh` `write_default_task_brief` writes the canonical shape `# $task` / `status: todo` / checklist, so prepending `# <task>` for repair matches the existing convention. Generated `AGENTS.md` guidance (in `write_task_agent_guidance`) states plans start with a `# <name>` H1 and that `## Notes`/H2+ are notes, not steps.
- `apps/workbranch-cli/src/workbranch/commands/doctor.sh`: `doctor_report` prints grouped sections via `section`/`success`/`info` and accumulates issues via `doctor_issue` (`doctor_issue_count`); `doctor_apply_fix` runs safe repairs **before** `doctor_report`; `cmd_doctor` orchestrates `--fix`, the fixed/manual summary, and `exit 1` when `doctor_issue_count > 0`.
- `apps/workbranch-cli/src/workbranch/lib/status-format.sh` `doctor_task_candidate_path` already enumerates task-shaped directories under `"$PROJECT_ROOT"/*`; reuse it to iterate tasks for the brief check.
- Build: `apps/workbranch-cli/src/workbranch/**` is amalgamated by `apps/workbranch-cli/scripts/build-workbranch.sh` (manifest `apps/workbranch-cli/scripts/workbranch-sources.txt`) into `apps/workbranch-cli/bin/workbranch`, and the build script copies that generated file to root `bin/workbranch`. `task-state.sh` is emitted before `commands/doctor.sh`, so `task_load_plans`/`TASK_PLAN_*` are in scope. No new module file is added (changes are inside the existing `doctor.sh`), so the manifest does not change.

## Decision Gates

- [x] Detection precision (avoid false positives)
  - Impact: which briefs doctor flags; risk of nagging on legitimate note-only briefs.
  - Resolved: flag a brief **only** when `TASK_PLAN_COUNT == 0` **and** the file contains tracked content — a `- [ ]`/`- [x]` checklist item **or** a `status:` line. A brief with prose/notes only (no checkbox, no `status:`) is **not** flagged, because no tracked steps are being lost.

- [x] Auto-fix aggressiveness
  - Impact: how invasive `--fix` is on user content.
  - Resolved: `--fix` only **prepends a single `# <task>` H1** and only when the file has zero `^# ` headings. It never rewrites, reorders, or promotes `## …` sections. If `## …` sections remain that the user may want as separate plans, that is reported as a manual follow-up, not auto-applied.

- [x] Backup on auto-fix
  - Impact: consistency with existing doctor repairs.
  - Resolved: **no `.bak`**. `TASK-WORKBRANCH.md` lives in the task root outside the repo worktree, so Git does not protect it; however, this repair is a single reversible prepend. `--fix` should print enough context for manual undo (`remove the first '# <task>' line`) instead of leaving persistent backup files in task-root state.

- [x] Exit status when `--fix` leaves manual brief follow-up
  - Impact: automation/CI contract for whether a partially repaired brief is healthy.
  - Resolved: keep **exit 1** when `doctor --fix` prepends the missing H1 but still reports manual `##` checklist promotion. This follows the existing doctor pattern: `--fix` exits 0 only when no issues/manual actions remain.

## Product Decisions

1. **Reuse the parser, never fork it.** Detection calls `task_load_plans` and reads `TASK_PLAN_COUNT`; the "tracked content" probe is a simple `grep`-style scan of the brief. No parsing logic is duplicated in doctor, and `task_load_plans` is unchanged.

2. **Read-only by default; issue affects exit code.** An unparseable brief is a `doctor_issue`, so plain `workbranch doctor` reports it and exits non-zero, consistent with every other doctor finding.

3. **`--fix` is safe and idempotent.** Prepending `# <task>` to a no-H1 brief is non-destructive and a second run is a no-op (the brief now has an H1, so it is no longer flagged). Done via temp file + atomic `mv`. No backup file is created; the repair output explains that undo is deleting the inserted first line.

4. **Respect existing flags/scope.** No new flag. `--repo` is irrelevant to brief format (briefs are per-task, not per-repo), so the brief check is not gated by `repo_matches_filter`; it runs for all task workspaces regardless of `--repo`.

5. **Manual follow-up for multi-section briefs.** When a flagged brief also has `## …` sections with checklist content (likely intended as separate plans), the report notes that promoting them to `# ` plans is a manual edit, with no auto-change. `--fix` may still prepend the missing task H1, but it must not claim that nested `##` checklist progress is restored.

6. **Manual follow-up remains non-zero.** If `--fix` repairs the missing H1 but leaves manual `##` promotion work, the command reports the repair and exits non-zero because the task brief is still not fully healthy for progress/HUD purposes.

## Target UX

```bash
$ workbranch doctor
[*] Base repos
[+] frontend on feature/cpq, clean
[+] backend on feature/cpq, clean

[*] Task workspaces
[+] feat-task1 healthy
[+] feat-task2 healthy
[+] feat-task3 healthy

[*] Task briefs
[-] feat-task1 brief not parseable: no '# <plan>' heading (HUD/Companion shows nothing)
    fix: workbranch doctor --fix

[*] Prunable worktrees
[*] (none)
[-] doctor found 1 issue(s)

$ workbranch doctor --fix
[+] Repaired task briefs (added '# <task>' heading): feat-task1
[*] Manual task brief follow-up: feat-task1 has checklist items under '##' sections; promote intended plans to '# ' headings
...
[-] doctor fixed 1 issue(s); 1 require manual action
```

## Target File Structure

```text
apps/workbranch-cli/src/workbranch/commands/doctor.sh   # add brief-format detection, report section, and --fix repair
apps/workbranch-cli/tests/cases/doctor.sh               # new integration tests
apps/workbranch-cli/tests/run.sh                        # register new doctor tests
apps/workbranch-cli/bin/workbranch                      # regenerated by apps/workbranch-cli/scripts/build-workbranch.sh
bin/workbranch                                          # copied by the build script for root/package consumers
```

(No manifest change: edits live inside existing `doctor.sh`. `apps/workbranch-cli/src/workbranch/usage.sh` line already reads "Diagnose project health; --fix applies safe repairs" and stays as-is. No new completion entries.)

## Implementation Tasks

### Task 1: Detection + report section (read-only) with failing tests

**Files:**
- Modify: `apps/workbranch-cli/src/workbranch/commands/doctor.sh`, `apps/workbranch-cli/tests/cases/doctor.sh`, `apps/workbranch-cli/tests/run.sh`

- [x] Add a failing test: a task whose brief has `status:` + checkboxes but no H1 is reported and `doctor` exits non-zero.

  ```bash
  test_doctor_flags_unparseable_brief() {
    new_fixture
    cd "$FIXTURE_PROJECT" || fail "cd project failed"
    run_expect_success "$WORKBRANCH" init >/dev/null
    printf '\n\n' | "$WORKBRANCH" add feat-login >/dev/null 2>&1 || fail "add failed"
    cat > "$FIXTURE_PROJECT/feat-login/TASK-WORKBRANCH.md" <<'EOF_BRIEF'
status: done
- [x] did the work
- [ ] verify
EOF_BRIEF
    out=$("$WORKBRANCH" doctor 2>&1; echo "status=$?")
    assert_contains "$out" "feat-login"
    assert_contains "$out" "brief not parseable"
    assert_contains "$out" "status=1"
  }
  ```

- [x] Add a false-positive guard test: a healthy `# Title` brief and a note-only brief (no checkbox, no `status:`) are **not** flagged, and a healthy-only project still exits 0.

- [x] Add a multi-H2 guard test: a brief with `status:` and checkboxes only under `## …` sections is reported as unparseable; this locks that the parser behavior is not silently changed and prepares Task 2's manual-follow-up behavior.

- [x] Implement detection in `doctor.sh`:
  - `doctor_brief_unparseable(task)` → returns success when: brief file exists and is non-empty, `task_load_plans "$task"` yields `TASK_PLAN_COUNT == 0`, **and** the file contains a `- [ ]`/`- [x]` item or a `status:` line. Otherwise non-success.
  - Add a `section "Task briefs"` block to `doctor_report` iterating `doctor_task_candidate_path` task dirs; for each unparseable brief call `doctor_issue "<task> brief not parseable: no '# <plan>' heading (HUD/Companion shows nothing)"` and `info "fix: workbranch doctor --fix"`. Print `(none)` when clean, matching other sections.

- [x] Register the test in `apps/workbranch-cli/tests/run.sh`. Rebuild (`apps/workbranch-cli/scripts/build-workbranch.sh`) and run.

### Task 2: `--fix` safe repair (prepend H1)

**Files:**
- Modify: `apps/workbranch-cli/src/workbranch/commands/doctor.sh`, `apps/workbranch-cli/tests/cases/doctor.sh`, `apps/workbranch-cli/tests/run.sh`

- [x] Add a failing test: `doctor --fix` on the unparseable brief inserts `# feat-login` as the first line, after which `list --json` shows one plan with the original checklist/progress, and a re-run of `doctor` is clean (exit 0).

  ```bash
  test_doctor_fix_prepends_h1_heading() {
    # ... build unparseable brief as above ...
    "$WORKBRANCH" doctor --fix >/dev/null 2>&1
    head -n 1 "$FIXTURE_PROJECT/feat-login/TASK-WORKBRANCH.md" | grep -q '^# feat-login$' || fail "no H1 prepended"
    out=$("$WORKBRANCH" list --json)
    printf '%s' "$out" | python3 -c 'import json,sys
t=json.load(sys.stdin)["tasks"][0]
assert len(t["plans"]) == 1, t
assert t["progressTotal"] == 2 and t["progressDone"] == 1, t'
    "$WORKBRANCH" doctor >/dev/null 2>&1 || fail "doctor still reports issue after fix"
  }
  ```

- [x] Implement `doctor_apply_brief_fix`:
  - For each unparseable brief with **zero** `^# ` headings, prepend `# <task>` + newline via temp file and atomic `mv`; increment a `doctor_brief_fixed_count`; collect repaired task names.
  - Print a success line listing repaired tasks, mirroring `doctor_apply_fix` output style, plus a concise undo hint: remove the inserted first line if the repair was not wanted.
  - If the original brief had checklist items under `## …` headings, collect a manual follow-up line and count it in the final `require manual action` summary because the safe H1 prepend does not restore those nested checklist items as plan progress.
  - If a flagged brief already has an H1 (so prepend is not the right repair) leave it for the manual path — do not modify.

- [x] Wire into `cmd_doctor`: call `doctor_apply_brief_fix` in the `--fix` branch alongside `doctor_apply_fix` (before `doctor_report`); include brief repairs and brief manual follow-ups in the final `doctor fixed N issue(s); M require manual action` accounting.

- [x] Confirm idempotency in a test: running `doctor --fix` twice leaves a single H1 and exits 0 both times.

- [x] Add a multi-H2 `--fix` test: running `doctor --fix` prepends exactly one H1, `list --json` shows one parseable plan with `progressTotal == 0`, the output reports that `##` checklist promotion is still manual, and the command exits `1` because manual action remains.

- [x] Rebuild and run targeted doctor tests.

### Task 3: Docs + full verification

**Files:**
- Modify: `README.md`, `README.ko.md`, `docs/git-operations.md` (doctor maintenance behavior), `apps/workbranch-cli/src/workbranch/usage.sh` (only if wording needs the brief case)
- Generated: `apps/workbranch-cli/bin/workbranch`, `bin/workbranch`

- [x] Document the brief-format check and `--fix` repair under doctor in `README.md` and mirror in `README.ko.md`.
- [x] Note in `docs/git-operations.md` that `--fix` may prepend a `# <task>` H1 to a content-bearing brief that has no heading, never rewrites or reorders brief content, creates no backup, and can be undone by removing the inserted first line.
- [x] Rebuild: `apps/workbranch-cli/scripts/build-workbranch.sh`.
- [x] Syntax: `/bin/bash -n apps/workbranch-cli/bin/workbranch apps/workbranch-cli/install.sh apps/workbranch-cli/tests/run.sh`.
- [x] Full suite: `apps/workbranch-cli/tests/run.sh` (report final `Tests passed: N`).
- [x] Whitespace: `git diff --check`.
- [x] Manual smoke against `monask-fullstack`: run the freshly built `bin/workbranch doctor` from the project root and confirm `feat-task1` is reported under "Task briefs". `doctor --fix` real-file mutation was not run because this plan requires confirmation before editing user files outside the workbranch task workspace.

## Verification Evidence

_(to be filled during implementation)_

- RED observed: new doctor tests failed against the pre-change generated CLI because doctor reported the project healthy and did not show "Task briefs" / "Repaired task briefs".
- Targeted doctor tests pass: detection, false-positive guard, multi-H2 detection, `--fix` prepend, idempotency.
- Targeted doctor tests pass for the multi-H2 shape: `--fix` prepends H1 but still reports manual `##` promotion instead of claiming progress restoration (`Tests passed: 6`, `Tests failed: 0` in the targeted runner).
- Regression: `apps/workbranch-cli/tests/cases/list-json.sh` (parser contract) unchanged and passing.
- Syntax passed: `/bin/bash -n apps/workbranch-cli/bin/workbranch apps/workbranch-cli/install.sh apps/workbranch-cli/tests/run.sh`.
- Full suite passed: `apps/workbranch-cli/tests/run.sh` → `Tests passed: 265`.
- Whitespace passed: `git diff --check`.
- Manual smoke passed read-only: running freshly built `bin/workbranch doctor` in `/Users/tommyhwang/Documents/git/monask-fullstack` reports `feat-task1 brief not parseable`, the `workbranch doctor --fix` hint, and the `##` promotion manual note with `status=1`. The real `doctor --fix` mutation was not run because the plan says real user-file edits require confirmation.

## Acceptance Criteria

- `workbranch doctor` reports a "Task briefs" finding for any brief that has tracked content (`status:` or a checklist) but parses to zero plans, with a `workbranch doctor --fix` hint, and exits non-zero.
- Note-only briefs and healthy `# Title` briefs are not flagged (no false positives).
- `workbranch doctor --fix` prepends a single `# <task>` H1 only to content-bearing, heading-less briefs; it is idempotent, creates no backup, prints an undo hint, and never rewrites/reorders/promotes existing content.
- For multi-`##` briefs, `--fix` does not claim that `##` checklist progress is restored; it reports manual promotion to `# ` headings when needed and exits non-zero until that manual action is resolved.
- The brief parser (`task_load_plans`) and `apps/workbranch-cli/tests/cases/list-json.sh` are unchanged.
- `apps/workbranch-cli/bin/workbranch` and root `bin/workbranch` are regenerated from source; syntax checks, full `apps/workbranch-cli/tests/run.sh`, and `git diff --check` pass.

## Non-Goals

- Do not change `task_load_plans` or the "no H1 ⇒ zero plans" parser contract.
- Do not auto-promote `## …` sections to `# ` plans, or otherwise rewrite/reformat brief body content.
- Do not gate the brief check on `--repo` (briefs are per-task, not per-repo).
- Do not add a new flag, command, or persistent state.
