# 0016 Focus Command with Warp Adapter Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` before every behavior change. Make source changes under `src/workbranch/**`, rebuild with `scripts/build-workbranch.sh`, then verify syntax checks, targeted tests, `./tests/run.sh`, and `git diff --check`. Do not edit `bin/workbranch` by hand. The live AppleScript path cannot run in CI — it is covered by an explicit manual verification checklist at the end.
> **Series:** Part 2 of 4 of the menu bar companion initiative. Execution order: 0015 memo/noti/json → **0016 (this)** → 0017 monorepo release plumbing → 0018 companion SwiftBar plugin. Depends on 0015 only for shared README sectioning; code-wise it is independent. Ships through the existing single-package `v*` release flow. After this plan, `workbranch focus <task>` delivers the core jump value with no menu bar required.

**Goal:** Add `workbranch focus <task>`: focus the existing Warp tab/pane belonging to a task workspace, from any shell. Validate the task before touching UI automation, and isolate Warp specifics behind a terminal-focus adapter seam so iTerm2/cmux adapters can be added later.

**Architecture:** `cmd_focus` preflights task existence (reusing task-identity validation), resolves an adapter from the existing `TERMINAL` config value (`*Warp*` → `warp`), and dispatches. The warp adapter drives Warp's `View > Navigation Palette` via `osascript` (menu click → paste task name → Enter). The osascript executor is injectable via an env override so dispatch logic is testable in CI without UI.

**Tech Stack:** Portable Bash, `osascript` (AppleScript + System Events), macOS Accessibility permission, generated single-file CLI, bash integration tests.

**Product fit:** This plan gives the companion the missing "jump back to the right task workspace" action. `workbranch terminal <task>` opens more windows; `workbranch focus <task>` must find the already-open task tab/pane or fail before it can jump to the wrong place.

---

## Problem Statement

`workbranch terminal <task>` launches a new terminal at a path; it cannot bring an *existing* workspace tab to the front. With ~20 tabs across 4–5 tasks in one Warp window, switching workspaces means scanning the tab sidebar manually. The menu bar companion (0018) needs a single command that deterministically lands on a task's workspace; that command is also useful standalone from any shell or launcher.

## Current Repo Evidence

- `src/workbranch/commands/tool-launcher.sh` + `lib/tool-launcher.sh`: `terminal|ide|finder` launchers resolve a configured command and `open` at the task path. Launcher tests stub the executor via env/PATH, establishing the stubbing pattern to reuse.
- `src/workbranch/lib/platform.sh`: platform gating helpers (this command is macOS-only; gate like existing launchers).
- `src/workbranch/lib/task-identity.sh`: task name validation for the preflight.

### Spike evidence: Warp tab focus (verified 2026-06-12, macOS Darwin 25.6)

Validated end-to-end on a real 4-task project (`monask-fullstack`, ~20 tabs/panes, single Warp window, vertical tabs):

```applescript
tell application "Warp" to activate
delay 0.3
tell application "System Events" to tell process "Warp"
  click menu item "Navigation Palette" of menu "View" of menu bar 1
end tell
delay 0.6
set the clipboard to taskName  -- e.g. "task3"
tell application "System Events" to keystroke "v" using command down
delay 0.8
tell application "System Events" to key code 36 -- Enter
```

Results, auto-judged by reading `AXValue` of `AXFocusedUIElement` (the focused pane's visible text) after each jump: `task1`→`omc-feat-task1`, `task2`→`omc-feat-task2`, `task3`→`omc-feat-task3`, `task4`→`feat-task4` — **4/4 deterministic**. Matching keys off the workspace *directory path*, so no tab-naming convention is required.

Hard constraints discovered:

1. The palette query MUST be a single token without spaces — queries with spaces/colons break matching and Enter selects the first (wrong) tab. Workbranch task names already satisfy this.
2. A query with no real match (e.g. `task9`) lands on an arbitrary tab. **Task-existence preflight before any osascript is mandatory.**
3. Requires Accessibility permission for the invoking process; without it, osascript fails with `-1728 assistive access` — surface that error, never a silent no-op.
4. Dead ends, do not revisit: `warp://` URI actions don't exist; Warp's in-window AX tree exposes no elements; window titles mirror the focused *pane* title and are not unique across tasks (never use them for matching or verification); `Cmd+1..9` only reaches 9 tabs.

## Decision Gates

- [x] Navigation Palette automation, not window-per-task `AXRaise`.
  - Reason: verified deterministic on the real single-window layout with zero workflow changes. Window-per-task + `AXRaise` (System Events can enumerate windows) is the documented fallback if a Warp update breaks the palette.

- [x] Adapter resolved from the existing `TERMINAL` config value; no new config directive.
  - Reason: `TERMINAL open -a Warp` already names the terminal. A dedicated directive can be added later if a user's `TERMINAL` doesn't identify the app.

- [x] Unsupported terminal fails with guidance, not best-effort.
  - Reason: a wrong-tab jump is worse than an error. Message suggests `workbranch terminal <task>` (launch) as the available alternative.

- [ ] Warp palette query value.
  - Impact: wrong-tab risk when several projects reuse task names such as `task1` or `login`.
  - Current evidence: the spike verified task-name queries on one real project. The adapter contract receives both task name and task path, but the current plan says Warp uses the name.
  - Recommended default: use the shortest unambiguous query that works in the spike environment: start with task name for v1, require `cmd_focus` to run from the target project root when invoked by the companion, and document that duplicate task names across visible Warp workspaces may require distinct task names. Revisit path-based queries only if manual verification shows reliable matching with paths containing slashes and possible spaces.
  - Alternative: query the canonical task path. Better disambiguation, but spaces in parent paths could violate the spike's single-token constraint.
  - Status: unresolved.

- [ ] Accessibility failure message.
  - Impact: supportability; without a hint, `osascript` errors look like a broken command.
  - Current evidence: the spike saw `-1728 assistive access` when permission is missing.
  - Recommended default: propagate stderr and append a workbranch hint that names System Settings → Privacy & Security → Accessibility and the responsible app (Terminal/Warp when run manually, SwiftBar when run through the companion).
  - Alternative: surface raw `osascript` stderr only. Easier, but users will not know which app needs permission.
  - Status: unresolved.

- [ ] iTerm2 adapter (official AppleScript, no palette) and cmux adapter — separate follow-up plans.

## Product Decisions

1. **`workbranch focus <task>`** — exactly one argument; no cwd-inference (you are jumping *away*, the target must be explicit).
2. Preflight failures use the existing style: `Cannot focus: unknown task 'task9'`.
3. macOS-only; on other platforms fail like other gated launchers.
4. Adapter contract: a function receiving the task name (palette query) and task path; the warp adapter uses the name, future adapters may prefer the path.
5. Automation timing (`delay` values) are named constants at the top of the adapter with a comment pointing to this plan's spike evidence.
6. `WORKBRANCH_FOCUS_DRIVER` env override replaces the osascript executor for tests (mirrors launcher-test stubbing).

## Target File Structure

```text
src/workbranch/lib/terminal-focus.sh    # adapter seam: resolve_focus_adapter, focus_with_warp (osascript heredoc)
src/workbranch/commands/focus.sh        # cmd_focus: preflight + dispatch
src/workbranch/main.sh                  # route focus
src/workbranch/usage.sh                 # document focus
scripts/build-workbranch.sh             # bundle new files
bin/workbranch                          # regenerated
tests/cases/focus.sh                    # new
tests/run.sh                            # register tests
README.md / README.ko.md                # focus row + Accessibility permission note
```

## Implementation Tasks

### Task 1: Dispatch and preflight (TDD)

- [ ] RED: `test_focus_rejects_unknown_task` — `Cannot focus: unknown task 'task9'`, nonzero exit, and (with driver stub recording invocations) zero driver calls.
- [ ] RED: `test_focus_rejects_unsupported_terminal` — fixture config `TERMINAL open -a iTerm`; error names the missing adapter and suggests `workbranch terminal <task>`.
- [ ] RED: `test_focus_dispatches_warp_adapter` — fixture config `TERMINAL open -a Warp`; `WORKBRANCH_FOCUS_DRIVER` stub records args; assert the task name is passed as the palette query.
- [ ] RED: `test_focus_requires_macos` — platform-gated like existing launcher tests.
- [ ] GREEN: implement `cmd_focus` + `resolve_focus_adapter`; rebuild + full `./tests/run.sh`.

### Task 2: Warp adapter osascript

- [ ] Implement `focus_with_warp` embedding the spike AppleScript via heredoc; task name passed as an osascript argv (never interpolated into the script body); stderr from osascript propagates to the user.
- [ ] Driver indirection: real path runs `osascript`; `WORKBRANCH_FOCUS_DRIVER` replaces the binary for tests.
- [ ] Rebuild + full `./tests/run.sh` (CI-safe tests only).

### Task 3: Manual verification checklist (not CI)

- [ ] With Accessibility granted to the invoking terminal: `workbranch focus <task>` for every task in a real multi-task project lands on the correct workspace (verify by the focused pane's content, not the window title).
- [ ] `workbranch focus` from inside a *different* task's pane jumps correctly (palette opens regardless of current focus).
- [ ] Revoke Accessibility: command fails with the surfaced osascript error and a workbranch hint naming System Settings → Privacy & Security → Accessibility plus the responsible app.
- [ ] Record the tested Warp version in the PR description.

### Task 4: Docs

- [ ] `usage.sh` + README/README.ko: `focus <task>` row under Tool; subsection covering the Accessibility requirement, single-window-many-tabs support, Warp-only status, duplicate task-name caveat, and adapter roadmap.

## Risks

- **Warp UI changes break palette automation.** Failure degrades to "Warp activated, palette/no-op" — never data loss. The adapter isolates all Warp specifics; the window-per-task `AXRaise` fallback is sketched above. Pin the tested Warp version in docs.
- **Ambiguous task names across projects** (a task name that substring-matches another project's path could mis-rank). Docs recommend distinct task names; revisit only if real collisions are reported.
- **Focus stealing during automation**: keystrokes go to the palette only; the command takes ~2.5s during which the user should not type. Documented in README.
