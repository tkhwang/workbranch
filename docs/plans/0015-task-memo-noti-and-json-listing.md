# 0015 Task Memo, Notifications, and JSON Listing Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` before every behavior change. Make source changes under `src/workbranch/**`, rebuild with `scripts/build-workbranch.sh`, then verify syntax checks, targeted tests, `./tests/run.sh`, and `git diff --check`. Do not edit `bin/workbranch` by hand.

> **Series:** Part 1 of 4 of the menu bar companion initiative. Execution order: **0015 (this)** → 0016 focus command → 0017 monorepo release plumbing → 0018 companion SwiftBar plugin. This plan has no dependency on the others and ships through the existing single-package `v*` release flow.

**Goal:** Add human-authored per-task state to workbranch — a memo (`workbranch memo`) and a notification inbox (`workbranch noti`) stored at the task workspace root — plus a stable machine-readable `workbranch list --json` that downstream frontends (menu bar app, Raycast, scripts) consume.

**Architecture:** State lives at the task root, outside both repo worktrees: `<task>/MEMO.md` (human-editable; first line is the title) and `<task>/.workbranch/notifications.jsonl`. `workbranch add` owns the task dir, and `workbranch remove` must treat these two paths as workbranch-owned task state while preserving unrelated user files. New shared helpers live in `src/workbranch/lib/task-state.sh`; commands stay thin. `list --json` is an early branch in `cmd_list` that never touches the human-output printers.

**Tech Stack:** Portable Bash, line-oriented `.workbranch.config`, generated single-file CLI via `scripts/build-workbranch.sh`, integration tests in `tests/run.sh` / `tests/cases/*.sh`, `python3` for JSON assertions in tests.

**Product fit:** This plan gives the companion one reliable CLI surface for "what task workspaces exist, what was I doing there, and which ones need attention." Git branch names remain implementation detail; memo/noti state explains human intent.

---

## Problem Statement

When running 3–5 task workspaces in parallel, git state cannot distinguish what each workspace is *for*: task branches carry near-identical commit subjects across tasks. "What am I doing here" must be a human-authored memo, and agent/build events ("tests done", "needs input") need a per-task inbox. Both must be queryable by other programs, which today is impossible because `workbranch list` renders colored human output only.

## Current Repo Evidence

- `src/workbranch/commands/list.sh` (`cmd_list`) prints via `info`/`section`/`table_header` with color codes; no machine-readable output exists anywhere in the CLI.
- `src/workbranch/lib/task-metadata.sh` already manages task-scoped metadata, establishing precedent for task-scoped state and for a `lib/` helper file per concern.
- `src/workbranch/lib/task-identity.sh` resolves and validates task names; reuse it for "unknown task" preflights.
- Tests are bash integration tests registered in `tests/run.sh` using `new_fixture`, `run_expect_success`, `run_expect_fail`, `assert_contains`.
- `src/workbranch/commands/remove.sh` removes repo worktrees and `.workbranch.task`, then runs `rmdir` on the task dir. Any extra file keeps the task directory, so this plan must explicitly clean only workbranch-owned state files during successful removal.

## Decision Gates

- [x] Memo lives at `<task>/MEMO.md`, notifications at `<task>/.workbranch/notifications.jsonl`.
  - Reason: the task root sits outside both repo worktrees (no gitignore churn), is owned by `workbranch add`/`remove`, and `MEMO.md` stays editable in any editor. Notifications are append-only machine data, so they hide under `.workbranch/`.

- [x] `--json` is the public contract for frontends.
  - Reason: keeps all logic in the CLI; frontends (0018 companion and beyond) shell out instead of re-implementing config parsing. Changing the JSON shape is a breaking change and must be called out in release notes.

- [x] No `git fetch`/network in the JSON path.
  - Reason: frontends poll on an interval (~5s). `dirty` uses `git status --porcelain` only.

- [ ] Task-state removal policy.
  - Impact: user data lifecycle and `workbranch remove` behavior.
  - Current evidence: current `remove` keeps a task root when any extra file remains; `MEMO.md` and `.workbranch/notifications.jsonl` would otherwise prevent cleanup.
  - Recommended default: `remove` deletes only workbranch-owned state paths (`MEMO.md`, `.workbranch/notifications.jsonl`, and an empty `.workbranch/` dir) after repo worktrees are removed, while preserving unrelated files such as `notes.txt`.
  - Alternative: leave memo/noti files in place and document that `remove` may keep task directories. Reject unless the user wants memo state to survive task deletion.
  - Status: unresolved.

- [ ] `memo` cwd-inference grammar.
  - Impact: command UX and accidental overwrites.
  - Current evidence: the plan allows omitting `<task>` from inside a task workspace, which creates a one-argument ambiguity between `workbranch memo <task>` and `workbranch memo "text"`.
  - Recommended default: keep cwd inference for `workbranch memo` (show current task memo) and `workbranch memo "text"` (write current task memo) only when `$PWD` is inside a registered task workspace; outside a task workspace require explicit `<task>` and fail with usage. Pin this behavior in tests and README.
  - Alternative: require `--current` or explicit task everywhere. Safer but slower for the intended terminal workflow.
  - Status: unresolved.

- [ ] JSON contract shape and versioning.
  - Impact: public wire format consumed by SwiftBar, Raycast, and scripts.
  - Current evidence: the sample omits a schema field; 0018 plans to gate on CLI version.
  - Recommended default: add top-level `"schemaVersion": 1` now, keep `project`, `root`, and `tasks` stable, sort tasks lexicographically by task dir, and keep repos in config order. Consumers should ignore unknown fields.
  - Alternative: use CLI semver only. Works for the companion but makes ad-hoc scripts harder to reason about.
  - Status: unresolved.

- [ ] Task eligibility for `list --json`.
  - Impact: companion must not show stale or partial task directories as active workspaces.
  - Current evidence: existing human `list` uses a loose repo-directory scan; `status` has stricter helpers for registered task workspaces.
  - Recommended default: `list --json` includes only registered task workspaces (`is_task_workspace_path` semantics), not stale or partial task-shaped directories. Human `list` output remains untouched in this slice.
  - Alternative: mirror the current human list scan exactly. This risks showing broken task folders in the menu bar.
  - Status: unresolved.

- [ ] Notification producers (who calls `workbranch noti add`).
  - Candidate: Claude Code / Codex `Notification`/`Stop` hooks invoking `workbranch noti add <task> "<msg>"` keyed off `$PWD`. This plan ships storage + CLI only; hook wiring is a follow-up slice once the command surface is stable.

## Product Decisions

1. **`workbranch memo <task> [text]`** — with text: write (overwrite); without: print. `--clear` removes the file. From inside a task workspace, `<task>` may be omitted: resolve by walking up from `$PWD` to a directory directly under `$PROJECT_ROOT` that is a configured task. Multi-line memos allowed; only the first non-empty line is the "title".
2. **`workbranch noti add <task> <text>`** appends `{"ts":"<ISO8601>","text":"..."}` JSONL; **`noti list <task>`** prints text lines (oldest first); **`noti clear <task>`** truncates. Missing file ⇒ empty list, count 0.
3. **`workbranch list --json`** — single JSON document on stdout, zero log noise, color-proof:

```json
{
  "schemaVersion": 1,
  "project": "monask-fullstack",
  "root": "/abs/path",
  "tasks": [
    {
      "name": "task3",
      "path": "/abs/path/task3",
      "memoTitle": "draft-tree 가이드 작성",
      "notiCount": 2,
      "repos": [{"name": "backend", "branch": "feature/cpq-task3", "dirty": true}]
    }
  ]
}
```

4. **Unknown task fails preflight-style:** `Cannot memo: unknown task 'task9'` / `Cannot noti: unknown task 'task9'`.
5. **No behavior change to human `list` output.** The only existing command behavior change is the explicit task-state cleanup in `remove`, limited to workbranch-owned memo/noti paths after successful workspace removal.

## Target File Structure

```text
src/workbranch/lib/task-state.sh        # task_memo_path, task_memo_title, task_noti_path, noti_count, json_escape
src/workbranch/commands/memo.sh         # cmd_memo
src/workbranch/commands/noti.sh         # cmd_noti
src/workbranch/commands/list.sh         # add --json early branch
src/workbranch/main.sh                  # route memo/noti subcommands
src/workbranch/usage.sh                 # document memo, noti, list --json
scripts/build-workbranch.sh             # include new source files in bundle order
bin/workbranch                          # regenerated only by scripts/build-workbranch.sh
tests/cases/memo.sh                     # new
tests/cases/noti.sh                     # new
tests/cases/list.sh                     # add --json shape tests
tests/run.sh                            # register new tests
README.md / README.ko.md                # command table rows for memo / noti / list --json
```

## Implementation Tasks

### Task 1: `task-state.sh` helpers + `memo` command (TDD)

- [ ] RED: `test_memo_set_show_clear` — `workbranch memo login "publish API 구현"` writes `login/MEMO.md`; `workbranch memo login` prints it; `workbranch memo login --clear` removes the file; second `--clear` is a no-op success.
- [ ] RED: `test_memo_rejects_unknown_task` — `Cannot memo: unknown task 'task9'`, exit nonzero, no file created.
- [ ] RED: `test_memo_resolves_task_from_cwd` — from `login/backend`, `workbranch memo "text"` writes `login/MEMO.md`; from `$PROJECT_ROOT` without a task argument it fails with usage guidance.
- [ ] GREEN: implement `task_memo_path`/`task_memo_title` in `lib/task-state.sh`; `cmd_memo` stays thin; cwd-resolution helper reuses `task-identity.sh` validation.
- [ ] Rebuild (`scripts/build-workbranch.sh`) + full `./tests/run.sh`.

### Task 2: `noti` command (TDD)

- [ ] RED: `test_noti_add_list_clear` — add twice, list prints both texts oldest-first, clear empties; list on a fresh task prints nothing and exits 0.
- [ ] RED: `test_noti_rejects_unknown_task`.
- [ ] RED: `test_noti_state_removed_with_workspace` — `workbranch remove login` deletes workbranch-owned memo/noti state and removes the task dir when no unrelated files remain; add a companion assertion that unrelated files still keep the task dir.
- [ ] GREEN: `task_noti_path`, `noti_count`; ISO-8601 timestamps via `date -u +%Y-%m-%dT%H:%M:%SZ`; JSON string escaping shared with Task 3's `json_escape`.
- [ ] Rebuild + full `./tests/run.sh`.

### Task 3: `list --json` (TDD)

- [ ] RED: `test_list_json_shape` — parse with `python3 -c 'import json,sys; d=json.load(sys.stdin); ...'`; assert keys `schemaVersion`, `project`, `root`, `tasks[].name/path/memoTitle/notiCount/repos[].name/branch/dirty`. Include a memo containing double quotes and Hangul to prove escaping round-trips.
- [ ] RED: `test_list_json_no_color_no_log_noise` — with `WORKBRANCH_COLOR=always`, stdout still parses as JSON.
- [ ] RED: `test_list_json_dirty_flag` — touch an untracked file in one task repo, assert `dirty: true` there and `false` elsewhere.
- [ ] GREEN: early `--json` branch in `cmd_list`; emit via a small writer using `json_escape` (no inline printf escaping); `memoTitle` empty string when no memo.
- [ ] Rebuild + full `./tests/run.sh`.

### Task 4: Docs

- [ ] `usage.sh`: add `memo`, `noti`, and `list --json` lines under fitting sections.
- [ ] `README.md` / `README.ko.md`: command table rows + a short "Task memo & notifications" subsection noting the storage locations and that `--json` is a stable contract.

## Risks

- **JSON emitted from bash is easy to get subtly wrong.** Mitigation: single `json_escape` helper, tests with quotes/Hangul/backslash, python3-based assertions instead of grep.
- **`list --json` latency with many repos.** `git status --porcelain` per repo only; if it ever exceeds ~100ms/repo in practice, add `--json --fast` (skip dirty) as a follow-up — do not pre-build it now.
