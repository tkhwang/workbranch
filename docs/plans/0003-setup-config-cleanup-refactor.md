# Setup/Config Cleanup Refactor Plan

> **For agentic workers:** Use `superpowers:executing-plans` or `agent-skills:build` to implement task-by-task. Steps use checkbox (`- [ ]`) syntax. Make source changes under `src/workbranch/**`, then run `scripts/build-workbranch.sh`, then `./tests/run.sh`. Never edit `bin/workbranch` by hand.

**Goal:** Remove duplication and accidental complexity introduced by the per-repo setup (`REPO_SETUP`) + `config` / `config --rewrite` work (merged in PR #4), without changing any user-visible behavior.

**Scope:** Pure quality refactor of the setup/config code paths surfaced by a `/simplify` review. No new features, no behavior changes. Every task must keep the full `tests/run.sh` suite green.

**Tech Stack:** Portable Bash, generated single-file build (`scripts/build-workbranch.sh`), `tests/run.sh` integration suite.

---

## Background

A `/simplify` review (4 parallel agents: reuse, simplification, efficiency, altitude) examined the diff for the `REPO_SETUP` / `config` feature. The findings are consolidated below and triaged into **Apply**, **Evaluate**, and **Deferred (skip)** buckets. This plan only schedules the Apply and Evaluate items. The Deferred items are recorded with rationale so they are not re-litigated.

Affected files:

- `src/workbranch/commands/add.sh`
- `src/workbranch/commands/config.sh`
- `src/workbranch/lib/config.sh`
- `src/workbranch/lib/task-setup.sh`
- `docs/specs/0001-workbranch-mvp.md`
- `docs/git-operations.md`

## Guiding Constraints

- No user-visible behavior change. Status prefixes (`[*]`, `[+]`, `[-] Error:`), prompt text, error wording, and config file output must stay byte-for-byte identical. Documentation tasks may update stale contract text to match current behavior, but they must not introduce new behavior.
- `WORKBRANCH_*` environment variables exported to setup commands must keep the exact same scoping. In particular, `WORKBRANCH_REPO`, `WORKBRANCH_REPO_DIR`, and `WORKBRANCH_BASE_REPO_DIR` are currently set **inside the subshell** of `run_repo_task_setup` and must not leak into the parent `workbranch` process.
- Rebuild `bin/workbranch` and run `./tests/run.sh` after every task. Commit only when green.

## Acceptance Criteria

- All existing `tests/run.sh` tests still pass.
- `git diff bin/workbranch` reflects only the regenerated output of the source changes (no hand edits).
- No new directives, flags, prompts, or messages.
- Net line count of the setup/config paths goes down, or stays flat with improved clarity.

---

## Implementation Tasks

### Task 1: Collapse the inverted `task setup` branch in `cmd_add` (low risk)

**Why:** `cmd_add` guards the setup run with an `if/then`/empty-`:`/`else` block. The `then` branch is a no-op (`:`), which is inverted control flow.

**Files:** `src/workbranch/commands/add.sh`

- [x] **Step 1: Rewrite the block**

Current (`src/workbranch/commands/add.sh`):

```bash
  if has_task_setups; then
    if run_task_setups "$task"; then
      :
    else
      printf '[-] Error: task setup failed\n' >&2
      printf '[*] Worktrees were created. Fix setup with:\n' >&2
      printf '    workbranch config\n' >&2
      printf '[*] Then rerun the setup command shown above, or remove and add the task again.\n' >&2
      return 1
    fi
  fi
```

Replace with:

```bash
  if has_task_setups && ! run_task_setups "$task"; then
    printf '[-] Error: task setup failed\n' >&2
    printf '[*] Worktrees were created. Fix setup with:\n' >&2
    printf '    workbranch config\n' >&2
    printf '[*] Then rerun the setup command shown above, or remove and add the task again.\n' >&2
    return 1
  fi
```

`has_task_setups` short-circuits `run_task_setups`, preserving the current guard (which exists so `run_task_setups`' own "not configured" `die` is never reached from `add`).

- [x] **Step 2: Build and verify**

```bash
scripts/build-workbranch.sh
/bin/bash ./tests/run.sh
```

Expected: all tests pass. Pay attention to `test_repo_setup_failure_reports_directory_and_command`, `test_task_setup_failure_reports_directory_and_command`, and `test_repo_setup_can_be_configured_and_run_per_repo`.

### Task 2: Single-`sed` parse for `repo_setup_command_from_line` (low risk)

**Why:** `repo_setup_command_from_line` uses two `sed` subprocesses plus a parameter-expansion dance, while the sibling `task_setup_from_line` does the equivalent job with one `sed`. Repo names are validated safe (no whitespace), so dropping two leading whitespace-free tokens in one pass is equivalent.

**Files:** `src/workbranch/lib/config.sh`

- [x] **Step 1: Rewrite the helper**

Current:

```bash
repo_setup_command_from_line() {
  line=$1
  rest=$(printf '%s' "$line" | sed 's/^[^[:space:]]*[[:space:]]*//; s/[[:space:]]*$//')
  repo=${rest%%[[:space:]]*}
  command=${rest#"$repo"}
  command=$(printf '%s' "$command" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  printf '%s' "$command"
}
```

Replace with:

```bash
repo_setup_command_from_line() {
  # Strip the directive and repo-name tokens (both whitespace-free), leaving the
  # command tail. Mirrors task_setup_from_line, which drops a single directive.
  line=$1
  command=$(printf '%s' "$line" | sed 's/^[^[:space:]]*[[:space:]]*[^[:space:]]*[[:space:]]*//; s/[[:space:]]*$//')
  printf '%s' "$command"
}
```

- [x] **Step 2: Build and verify**

```bash
scripts/build-workbranch.sh
/bin/bash ./tests/run.sh
```

Expected: all tests pass. Watch `test_repo_setup_can_be_configured_and_run_per_repo` and `test_config_preserves_task_setup_while_prompting_repo_setup`, which assert the exact `REPO_SETUP <repo> <command>` round-trip (including commands containing `>` and spaces).

### Task 3: Extract a shared setup runner (medium risk — TDD-guard)

**Why:** `run_task_setup` and `run_repo_task_setup` in `src/workbranch/lib/task-setup.sh` are ~70% identical: `cd`, export the common `WORKBRANCH_*` vars, `sh -c`, capture `$?`, and on failure print a 3-line `directory`/`command` report and `exit`. They differ only in run directory, the extra repo vars, and the failure label.

**Critical constraint:** the repo-only vars (`WORKBRANCH_REPO`, `WORKBRANCH_REPO_DIR`, `WORKBRANCH_BASE_REPO_DIR`) must remain scoped to the subshell. Do **not** set them as parent-shell globals before calling a helper — that would leak them into the later `TASK_SETUP` fallback run and into any other subprocess. Pass them into the helper instead, or keep the export inside the subshell.

**Files:** `src/workbranch/lib/task-setup.sh`

- [x] **Step 1: Confirm coverage is RED-capable**

These tests already exercise both runners and their failure reporting:

- `test_repo_setup_can_be_configured_and_run_per_repo` (env vars: `WORKBRANCH_REPO`, `WORKBRANCH_REPO_DIR`, `WORKBRANCH_BASE_REPO_DIR`)
- `test_task_setup_failure_reports_directory_and_command`
- `test_repo_setup_failure_reports_directory_and_command`
- `test_repo_setup_suppresses_legacy_task_setup_fallback`

Run them first to confirm baseline green:

```bash
scripts/build-workbranch.sh
/bin/bash ./tests/run.sh
```

- [x] **Step 2: Introduce a private `_run_setup_command` helper**

Proposed shape (adjust names to match surrounding style). The helper takes the setup kind (`task` or `repo`), run dir, command, failure label, and optional repo vars. Pass the kind explicitly; do not derive it from the repo name because the failure message must stay exactly `task setup failed: <task>` or `repo setup failed: <task>/<repo>`.

```bash
# _run_setup_command <kind> <run_dir> <command> <fail_label> [repo] [repo_dir] [base_repo_dir]
_run_setup_command() {
  _rs_kind=$1
  _rs_dir=$2
  _rs_command=$3
  _rs_label=$4
  _rs_repo=${5:-}
  _rs_repo_dir=${6:-}
  _rs_base_repo_dir=${7:-}
  (
    cd "$_rs_dir" || exit 1
    WORKBRANCH_PROJECT_ROOT=$PROJECT_ROOT
    WORKBRANCH_TASK=$task
    WORKBRANCH_TASK_DIR=$task_dir
    WORKBRANCH_BASE_DIR="$PROJECT_ROOT/$BASE_DIR"
    WORKBRANCH_REPOS=$(repo_names_joined)
    export WORKBRANCH_PROJECT_ROOT WORKBRANCH_TASK WORKBRANCH_TASK_DIR WORKBRANCH_BASE_DIR WORKBRANCH_REPOS
    if [ -n "$_rs_repo" ]; then
      WORKBRANCH_REPO=$_rs_repo
      WORKBRANCH_REPO_DIR=$_rs_repo_dir
      WORKBRANCH_BASE_REPO_DIR=$_rs_base_repo_dir
      export WORKBRANCH_REPO WORKBRANCH_REPO_DIR WORKBRANCH_BASE_REPO_DIR
    fi
    sh -c "$_rs_command"
    setup_status=$?
    if [ $setup_status -ne 0 ]; then
      printf '[-] Error: %s setup failed: %s\n' "$_rs_kind" "$_rs_label" >&2
      printf '[*] Setup directory: %s\n' "$_rs_dir" >&2
      printf '[*] Setup command: %s\n' "$_rs_command" >&2
      exit "$setup_status"
    fi
  )
}
```

- [x] **Step 3: Reduce the two public runners to thin wrappers**

```bash
run_task_setup() {
  task=$1
  [ -n "$TASK_SETUP" ] || die "task setup command is not configured"
  task_dir="$PROJECT_ROOT/$task"
  is_task_workspace_path "$task_dir" || die "task workspace not found: $task"
  _run_setup_command task "$PROJECT_ROOT" "$TASK_SETUP" "$task"
}

run_repo_task_setup() {
  task=$1
  repo=$2
  command=$3
  [ -n "$command" ] || die "repo setup command is not configured: $repo"
  task_dir="$PROJECT_ROOT/$task"
  repo_dir=$(task_repo_path "$task" "$repo")
  base_repo_dir=$(base_repo_path "$repo")
  is_task_workspace_path "$task_dir" || die "task workspace not found: $task"
  [ -d "$repo_dir" ] || die "task repo not found: $task/$repo"
  _run_setup_command repo "$repo_dir" "$command" "$task/$repo" "$repo" "$repo_dir" "$base_repo_dir"
}
```

- [x] **Step 4: Build and verify, with extra attention to env scoping**

```bash
scripts/build-workbranch.sh
/bin/bash ./tests/run.sh
```

Expected: all tests pass, including the failure-report and per-repo env-var assertions. If any fail, prefer reverting to the two-function form over weakening the subshell scoping — the duplication is acceptable if a clean merge is not achievable.

- [x] **Step 5: Go/No-Go**

If the merged form is not clearly simpler than the original two functions (e.g. the parameter list or the label logic becomes more confusing than the duplication it removes), **abandon this task** and leave the two runners as-is. Record the decision in the commit message or a comment. This is an explicitly optional cleanup.

### Task 4: De-duplicate the `REPO_SETUP` directive handling (optional, low value)

**Why:** `parse_config` and `parse_config_for_rewrite` contain identical `REPO_SETUP` arms:

```bash
[ $# -ge 3 ] || die "invalid config line $line_no: REPO_SETUP expects <repo> <command>"
set_repo_setup "$2" "$(repo_setup_command_from_line "$line")"
```

**Files:** `src/workbranch/lib/config.sh`

- [x] **Step 1: Decide whether it earns a helper**

It is only two lines duplicated across two parsers that intentionally diverge elsewhere (the rewrite parser also accepts lowercase aliases and `BASE_BRANCH`). Extracting `handle_repo_setup_directive` is marginal. **Default: skip** unless Task 3 establishes a pattern that makes this trivially consistent. If implemented, the helper must preserve `$line_no` in the error message (pass it in).

- [x] **Step 2 (only if implemented): Build and verify** — skipped because Task 4 was not implemented

```bash
scripts/build-workbranch.sh
/bin/bash ./tests/run.sh
```

### Task 5: Sync stale setup/config contract docs (low risk)

**Why:** Current code preserves project-level `TASK_SETUP` during `workbranch config`, prompts only for repo-level setup in the existing-project config flow, suppresses `TASK_SETUP` after repo setup has run, and prints exact setup failure directory/command details. The spec and Git-operations docs still describe older behavior.

**Files:**

- `docs/specs/0001-workbranch-mvp.md`
- `docs/git-operations.md`

- [x] **Step 1: Update `workbranch config` contract text**

In `docs/specs/0001-workbranch-mvp.md`, change the existing-project config description so it says:

- `workbranch config` loads existing config.
- It prompts for each repo's base branch and repo-level setup command.
- It preserves existing project-level `TASK_SETUP` unless another explicit flow clears or migrates it.

Do not document a new prompt or flag.

- [x] **Step 2: Update `workbranch add` setup execution and failure text**

In `docs/specs/0001-workbranch-mvp.md`, describe the current add-time setup contract:

- Repo-level setup commands run first.
- Project-level `TASK_SETUP` is the fallback when no repo setup ran and the operation is not repo-filtered.
- Setup failure output includes the exact setup directory and command.

In `docs/git-operations.md`, replace the stale "run the setup command manually" wording with the current guidance: fix setup with `workbranch config`, then rerun the command shown in the failure output or remove and add the task again.

- [x] **Step 3: Verify docs and unchanged behavior**

```bash
git diff --check
/bin/bash -n bin/workbranch install.sh tests/run.sh
/bin/bash ./tests/run.sh
```

### Task 6: Final verification and commit

- [x] **Step 1: Full gate**

```bash
scripts/build-workbranch.sh
/bin/bash -n bin/workbranch install.sh tests/run.sh
git diff --check
/bin/bash ./tests/run.sh
```

- [x] **Step 2: Confirm generated artifact is current**

```bash
git diff --stat bin/workbranch src/workbranch
```

Expected: `bin/workbranch` changes are consistent with the source changes only.

- [x] **Step 3: Commit**

Use the Lore commit protocol from `AGENTS.md`. Example:

```text
Preserve setup/config behavior while reducing cleanup risk

Constraint: Generated CLI is built from src/workbranch sources.
Confidence: high
Scope-risk: narrow
Directive: Keep bin/workbranch generated by scripts/build-workbranch.sh; do not edit it by hand.
Tested: scripts/build-workbranch.sh; /bin/bash -n bin/workbranch install.sh tests/run.sh; git diff --check; /bin/bash ./tests/run.sh
```

Include `./tests/run.sh` output in the PR body per `AGENTS.md`.

---

## Deferred / Already Applied (reviewed and intentionally not scheduled)

These were raised by the review but are **not** scheduled as cleanup work. Recorded so they are not re-opened without new information.

| Finding | Decision | Rationale |
|---|---|---|
| Revert `_repo_names_*` prefixed locals in `repo_names_joined` back to `out`/`i`/`name` | **Skip** | The codebase uses no `local` scoping; prefixing is a deliberate collision-avoidance idiom consistent with `_setup_i` in `run_task_setups`. Reverting reduces safety and is pure churn. |
| Extract a generic `for_each_repo`/iterator abstraction over `REPO_*` arrays | **Defer** | Large cross-cutting refactor well outside this diff; touches `list.sh`, `config.sh`, `task-setup.sh`, `validate_config_complete`. Worth a separate dedicated plan if pursued. |
| Merge `set_repo_base_branch` (strict, dies on conflict) and `update_repo_base_branch` (overwrites) | **Skip** | Different, intentional error semantics. `set_*` guards the legacy-rewrite parse path; `update_*` serves interactive `config`. Merging behind a flag is behavior-sensitive and the distinct names document intent. |
| Remove the trailing explanatory comment in `configure_existing_project` (`commands/config.sh`) | **Keep** | It documents *why* `config` preserves project-level `TASK_SETUP` while only prompting for repo setup — useful "why" context, not noise. |
| Cache `has_repo_setups` results / avoid repeated O(n) scans | **Skip** | Negligible for a CLI with a handful of repos; I/O and user prompts dominate. Caching would add state with no measurable gain. |
| Restructure the `ran_setup` flag flow in `run_task_setups` | **Already applied** | Current code already gates the final `die` on `ran_setup` plus empty `FILTER_REPO`, preserving repo-filtered helper semantics. Do not refactor this again inside the cleanup plan unless a test fails. |
| Make setup failure guidance distinguish repo-level vs task-level failure | **Already applied** | Current `run_task_setup` and `run_repo_task_setup` already print the exact failed context, setup directory, and setup command. Task 5 only syncs stale docs to that behavior. |

## Self-Review

- Scope check: scheduled code tasks are behavior-preserving cleanups; Task 5 is docs-only contract sync to current behavior.
- Risk ordering: Tasks 1–2 are mechanical and safe; Task 3 is the only structural change and carries an explicit Go/No-Go and env-scoping guard; Task 4 is optional; Task 5 should not touch code.
- Verification: each code task rebuilds the generated artifact and runs the full suite. The named tests cover the setup paths, so add tests only if a task changes behavior or exposes an uncovered edge.
