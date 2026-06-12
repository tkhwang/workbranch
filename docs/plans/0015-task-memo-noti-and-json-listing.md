# 0015 Task Memo, Notifications, and JSON Listing Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` before every behavior change. Make source changes under `src/workbranch/**`, rebuild with `scripts/build-workbranch.sh`, then verify syntax checks, targeted tests, `./tests/run.sh`, and `git diff --check`. Do not edit `bin/workbranch` by hand.
>
> **Series:** Part 1 of 4 of the menu bar companion initiative. Execution order: **0015 (this)** → 0016 focus command → 0017 monorepo release plumbing → 0018 companion SwiftBar plugin. This plan has no dependency on the others and ships through the existing single-package `v*` release flow.

**Goal:** Add human-authored per-task state to workbranch — a task brief (`workbranch memo`, stored as `TASK-WORKBRANCH.md`) and a notification inbox (`workbranch noti`) stored at the task workspace root — plus a stable machine-readable `workbranch list --json` that downstream frontends (menu bar app, Raycast, scripts) consume.

**Architecture:** State lives at the task root, outside repo worktrees: `<task>/TASK-WORKBRANCH.md` (human/agent-editable task brief; first non-empty line is the title), `<task>/AGENTS.md` (generated AI-agent guidance), and `<task>/.workbranch/notifications.jsonl`. `workbranch add` owns the task dir, and `workbranch remove` must treat these paths as workbranch-owned task state while preserving unrelated user files. Generated guidance tells agents running from either `<task>` or `<task>/<repo>` how to update the same task brief. New shared helpers live in `src/workbranch/lib/task-state.sh`; commands stay thin. `list --json` is an early branch in `cmd_list` that never touches the human-output printers.

**Tech Stack:** Portable Bash, line-oriented `.workbranch.config`, generated single-file CLI via `scripts/build-workbranch.sh`, integration tests in `tests/run.sh` / `tests/cases/*.sh`, `python3` for JSON assertions in tests.

**Product fit:** This plan gives the companion one reliable CLI surface for "what task workspaces exist, what was I doing there, and which ones need attention." Git branch names remain implementation detail; task brief/noti state explains human intent and agent progress.

---

## Problem Statement

When running 3–5 task workspaces in parallel, git state cannot distinguish what each workspace is *for*: task branches carry near-identical commit subjects across tasks. "What am I doing here" must be a human/agent-maintained task brief, and agent/build events ("tests done", "needs input") need a per-task inbox. Both must be queryable by other programs, which today is impossible because `workbranch list` renders colored human output only.

## Current Repo Evidence

- `src/workbranch/commands/list.sh` (`cmd_list`) prints via `info`/`section`/`table_header` with color codes; no machine-readable output exists anywhere in the CLI.
- `src/workbranch/lib/task-metadata.sh` already manages task-scoped metadata, establishing precedent for task-scoped state and for a `lib/` helper file per concern.
- `src/workbranch/lib/task-identity.sh` resolves and validates task names; reuse it for "unknown task" preflights.
- Tests are bash integration tests registered in `tests/run.sh` using `new_fixture`, `run_expect_success`, `run_expect_fail`, `assert_contains`.
- `src/workbranch/commands/remove.sh` removes repo worktrees and `.workbranch.task`, then runs `rmdir` on the task dir. Any extra file keeps the task directory, so this plan must explicitly clean only workbranch-owned state files during successful removal.

## Decision Gates

- [x] Task brief lives at `<task>/TASK-WORKBRANCH.md`, agent guidance at `<task>/AGENTS.md`, notifications at `<task>/.workbranch/notifications.jsonl`.
  - Reason: the task root sits outside repo worktrees (no repo `.gitignore` churn), is owned by `workbranch add`/`remove`, and `TASK-WORKBRANCH.md` stays visible/editable in any editor. `AGENTS.md` injects the update rule for AI agents without writing repo-local files. Notifications are append-only machine data, so they hide under `.workbranch/`.

- [x] `--json` is the public contract for frontends.
  - Reason: keeps all logic in the CLI; frontends (0018 companion and beyond) shell out instead of re-implementing config parsing. Changing the JSON shape is a breaking change and must be called out in release notes.

- [x] No `git fetch`/network in the JSON path.
  - Reason: frontends poll on an interval (~5s). `dirty` uses `git status --porcelain` only.

- [x] AI agent cwd and task brief update contract.
  - Impact: agent usability, companion display consistency, and repo dirty-state behavior.
  - Decision: users/agents may run from either `<task>` or `<task>/<repo>`; the canonical task brief remains `<task>/TASK-WORKBRANCH.md`. Generated `<task>/AGENTS.md` instructs agents to update `TASK-WORKBRANCH.md` when running at the task root and `../TASK-WORKBRANCH.md` when running inside a repo folder.
  - Reason: repo-root execution is common for single-repo work, while task-root state keeps companion/app integration one-per-task and avoids repo-local files.
  - Status: resolved.

- [x] No repo `.gitignore` mutation.
  - Impact: repo cleanliness and user-owned source files.
  - Decision: `workbranch add` does not write `TASK-WORKBRANCH.md`, `AGENTS.md`, or notification files inside repo worktrees and does not edit repo `.gitignore`.
  - Reason: all workbranch-managed task state lives directly under `<task>` or `<task>/.workbranch/`, outside Git-managed repo folders.
  - Status: resolved.

- [x] Task-state removal policy.
  - Impact: user data lifecycle and `workbranch remove` behavior.
  - Current evidence: current `remove` keeps a task root when any extra file remains; `TASK-WORKBRANCH.md`, generated `AGENTS.md`, and `.workbranch/notifications.jsonl` would otherwise prevent cleanup.
  - Decision: `remove` deletes app-managed/workbranch-owned task state paths (`TASK-WORKBRANCH.md`, generated `AGENTS.md`, `.workbranch/notifications.jsonl`, and an empty `.workbranch/` dir) after repo worktrees and task branches are removed successfully, while preserving unrelated files such as `notes.txt`.
  - Reason: task brief/noti/agent-guidance state is managed by workbranch/app integration at fixed task-root locations and belongs to the task workspace lifecycle; unrelated user files remain outside this owned-state cleanup.
  - Status: resolved.

- [x] `memo` cwd-inference grammar.
  - Impact: command UX and accidental overwrites.
  - Current evidence: task work may happen from either `<task>` or `<task>/<repo>`, while the canonical brief is always `<task>/TASK-WORKBRANCH.md`.
  - Decision: keep cwd inference only for zero-argument reads from inside a registered task workspace. `workbranch memo` shows the current task brief. Any provided argument is treated as an explicit task: `workbranch memo <task>` reads, `workbranch memo <task> "text"` overwrites, and `workbranch memo <task> --clear` removes it. Outside a task workspace, `workbranch memo` fails with usage.
  - Reason: this keeps the fast agent/user workflow for repo-local execution while preventing accidental writes from the project root or unrelated directories.
  - Status: resolved.

- [x] JSON contract shape and versioning.
  - Impact: public wire format consumed by SwiftBar, Raycast, and scripts.
  - Current evidence: the JSON sample already uses a top-level `"schemaVersion": 1`; downstream companion work can also gate on CLI semver, but ad-hoc consumers need a direct schema signal.
  - Decision: include top-level `"schemaVersion": 1`, keep `project`, `root`, and `tasks` stable, sort tasks lexicographically by task dir, keep repos in config order, and document that consumers should ignore unknown fields.
  - Reason: schema versioning makes the machine contract explicit without forcing every consumer to parse CLI semver.
  - Status: resolved by repo-evidence/default recommendation.

- [x] Task eligibility for `list --json`.
  - Impact: companion must not show stale or partial task directories as active workspaces.
  - Current evidence: human `list` uses a loose repo-directory scan; registered-workspace helpers already exist in `src/workbranch/lib/status-format.sh`.
  - Decision: `list --json` includes only registered task workspaces (`is_task_workspace_path` semantics), not stale or partial task-shaped directories. Human `list` output remains untouched in this slice.
  - Reason: companion/app/script consumers need active, usable tasks; stale/partial diagnostics belong to `doctor`/status-style flows, not the primary JSON listing.
  - Status: resolved.

- [x] Notification producers and consumers.
  - Impact: ownership of `.workbranch/notifications.jsonl` and companion app behavior.
  - Decision: `workbranch noti add` and AI-agent/hooks are producers; the companion app is a consumer that reads `notiCount`, may show `noti list`, and may clear with `noti clear`. This slice ships storage + CLI; automatic hook wiring is a follow-up after the command surface is stable.
  - Reason: the CLI owns the file format and append/clear behavior, agents produce event notifications, and the companion app displays/manages the inbox instead of being the primary writer.
  - Status: resolved.

## Product Decisions

1. **`workbranch memo <task> [text]`** — with text: write (overwrite) `<task>/TASK-WORKBRANCH.md`; without: print it. `--clear` removes the file. From inside a task workspace, `<task>` may be omitted only for zero-argument reads: resolve by walking up from `$PWD` to a directory directly under `$PROJECT_ROOT` that is a configured task. Multi-line task briefs allowed; only the first non-empty line is the `memoTitle` / display title.
2. **`workbranch add <task>` task-state bootstrap** — create `<task>/TASK-WORKBRANCH.md` from a short template and generated `<task>/AGENTS.md` with instructions for agents to keep that task brief current whether they run from `<task>` or `<task>/<repo>`. Do not edit repo `.gitignore` or create repo-local task-state files.
3. **`workbranch noti add <task> <text>`** appends `{"ts":"<ISO8601>","text":"..."}` JSONL; **`noti list <task>`** prints text lines (oldest first); **`noti clear <task>`** truncates. Missing file ⇒ empty list, count 0.
4. **`workbranch list --json`** — single JSON document on stdout, zero log noise, color-proof:

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

5. **Unknown task fails preflight-style:** `Cannot memo: unknown task 'task9'` / `Cannot noti: unknown task 'task9'`.
6. **`list --json` eligibility:** include only registered task workspaces using `is_task_workspace_path`; do not show stale or partial task-shaped directories in companion-facing JSON.
7. **No behavior change to human `list` output.** The only existing command behavior change is the explicit task-state cleanup in `remove`, limited to workbranch-owned task brief/agent-guidance/noti paths after successful workspace removal.

## Target File Structure

```text
src/workbranch/lib/task-state.sh        # task_brief_path, task_brief_title, task_agents_path, task_noti_path, noti_count, json_escape
src/workbranch/commands/memo.sh         # cmd_memo
src/workbranch/commands/noti.sh         # cmd_noti
src/workbranch/commands/list.sh         # add --json early branch
<task>/TASK-WORKBRANCH.md               # generated task brief, managed by add/memo/remove
<task>/AGENTS.md                        # generated agent guidance, managed by add/remove
src/workbranch/main.sh                  # route memo/noti subcommands
src/workbranch/usage.sh                 # document memo, noti, list --json
scripts/workbranch-sources.txt          # include new source files in bundle order
bin/workbranch                          # regenerated only by scripts/build-workbranch.sh
tests/cases/memo.sh                     # new
tests/cases/noti.sh                     # new
tests/cases/list.sh                     # add --json shape tests
tests/run.sh                            # register new tests
README.md / README.ko.md                # command table rows for memo / noti / list --json plus task brief/agent-guidance notes
```

## Implementation Tasks

### Task 1: `task-state.sh` helpers + `memo` command (TDD)

- [x] RED: `test_memo_set_show_clear` — `workbranch memo login "publish API 구현"` writes `login/TASK-WORKBRANCH.md`; `workbranch memo login` prints it; `workbranch memo login --clear` removes the file; second `--clear` is a no-op success.
- [x] RED: `test_memo_rejects_unknown_task` — `Cannot memo: unknown task 'task9'`, exit nonzero, no task brief file created.
- [x] RED: `test_memo_resolves_task_from_cwd` — from `login/backend`, `workbranch memo` reads `login/TASK-WORKBRANCH.md`; from `$PROJECT_ROOT` without a task argument it fails with usage guidance.
- [x] RED: `test_add_creates_task_brief_and_agent_guidance` — `workbranch add login` creates `login/TASK-WORKBRANCH.md` and `login/AGENTS.md`; generated guidance tells agents running from task root to update `TASK-WORKBRANCH.md` and agents running from repo folders to update `../TASK-WORKBRANCH.md`; no repo `.gitignore` changes are made.
- [x] GREEN: implement `task_brief_path`/`task_brief_title`/`task_agents_path` in `lib/task-state.sh`; `cmd_memo` stays thin; cwd-resolution helper reuses `task-identity.sh` validation; `cmd_add` writes the task brief and guidance before repo setup commands run.
- [x] Rebuild (`scripts/build-workbranch.sh`) + full `./tests/run.sh`.
  - Task 1 verification: `scripts/build-workbranch.sh`; targeted memo/add tests via sourced `tests/cases/memo.sh`.

### Task 2: `noti` command (TDD)

- [x] RED: `test_noti_add_list_clear` — add twice, list prints both texts oldest-first, clear empties; list on a fresh task prints nothing and exits 0.
- [x] RED: `test_noti_rejects_unknown_task`.
- [x] RED: `test_noti_state_removed_with_workspace` — `workbranch remove login` deletes workbranch-owned task brief/agent-guidance/noti state and removes the task dir when no unrelated files remain; add a companion assertion that unrelated files still keep the task dir.
- [x] GREEN: `task_noti_path`, `noti_count`; ISO-8601 timestamps via `date -u +%Y-%m-%dT%H:%M:%SZ`; JSON string escaping shared with Task 3's `json_escape`.
- [x] Rebuild + full `./tests/run.sh`.
  - Task 2 verification: `scripts/build-workbranch.sh`; targeted noti/remove tests via sourced `tests/cases/noti.sh`.

### Task 3: `list --json` (TDD)

- [x] RED: `test_list_json_shape` — parse with `python3 -c 'import json,sys; d=json.load(sys.stdin); ...'`; assert keys `schemaVersion`, `project`, `root`, `tasks[].name/path/memoTitle/notiCount/repos[].name/branch/dirty`. Include a task brief title containing double quotes, backslash, and Hangul to prove escaping round-trips.
- [x] RED: `test_list_json_no_color_no_log_noise` — with `WORKBRANCH_COLOR=always`, stdout still parses as JSON.
- [x] RED: `test_list_json_dirty_flag` — touch an untracked file in one task repo, assert `dirty: true` there and `false` elsewhere.
- [x] RED: `test_list_json_skips_stale_and_partial_task_dirs` — create task-shaped directories that are missing registered worktree state or one configured repo; assert they do not appear in JSON while a valid task does.
- [x] GREEN: early `--json` branch in `cmd_list`; emit via a small writer using `json_escape` (no inline printf escaping); `memoTitle` empty string when no task brief; collect tasks with `is_task_workspace_path` and keep human `list` unchanged.
- [x] Rebuild + full `./tests/run.sh`.
  - Task 3 verification: `scripts/build-workbranch.sh`; targeted list JSON tests via sourced `tests/cases/list-json.sh`.

### Task 4: Docs and public CLI surface

- [x] `src/workbranch/commands/completion.sh`: expose `memo`/`noti`, `list --json`, `memo --clear`, and task/subcommand completion.
- [x] `docs/specs/0001-workbranch-mvp.md` / `docs/usage.md` / `docs/usage.ko.md`: document task brief, notifications, and JSON listing contracts.
- [x] `usage.sh`: add `memo`, `noti`, and `list --json` lines under fitting sections.
- [x] `README.md` / `README.ko.md`: command table rows + a short "Task brief & notifications" subsection noting the storage locations and that `--json` is a stable contract.
  - Task 4 verification: `scripts/build-workbranch.sh`; `/bin/bash -n bin/workbranch src/workbranch/usage.sh tests/run.sh`; targeted memo/noti/list-json/completion/remove tests.

## Risks

- **JSON emitted from bash is easy to get subtly wrong.** Mitigation: single `json_escape` helper, tests with quotes/Hangul/backslash, python3-based assertions instead of grep.
- **`list --json` latency with many repos.** `git status --porcelain` per repo only; if it ever exceeds ~100ms/repo in practice, add `--json --fast` (skip dirty) as a follow-up — do not pre-build it now.

## Final Verification

- `./tests/run.sh` — passed (`Tests passed: 205`).
- `scripts/build-workbranch.sh && /bin/bash -n bin/workbranch install.sh tests/run.sh scripts/build-workbranch.sh` — passed.
- `git diff --check` — passed.
