# Split Integration Test Suite Into Per-Area Files Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This is a **mechanical move with zero behavior change** — no test logic is rewritten, no assertions change.

**Goal:** Mirror the modular `src/workbranch/**` layout in the test suite by splitting the single 2308-line `tests/run.sh` into a shared helper library plus per-area case files, while keeping `tests/run.sh` as the only entrypoint and preserving the exact current test ordering and 92-test pass count after the harness-output/stdin follow-ups.

**Architecture:** Keep `tests/run.sh` as the single runnable entrypoint. It defines the path globals, sources shared helpers from `tests/lib/helpers.sh`, sources every case file under `tests/cases/*.sh`, then runs `main()` which invokes each test in the current explicit order. Test functions move verbatim into `tests/cases/<area>.sh` files grouped by command/area. Case files are *sourced*, not executed (no shebang, `# shellcheck shell=bash` directive).

**Tech Stack:** Bash, existing `tests/run.sh` integration suite, `scripts/build-workbranch.sh` generated artifact, `git` fixtures via `mktemp`.

---

## Decision Summary

Five structural decisions were confirmed with the user:

1. **Grouping: by command/area** (not a strict 1:1 mirror of `src/`). Some `src` modules have no dedicated tests and several tests span multiple modules, so a pragmatic per-area grouping is cleaner than path mirroring.
2. **Runner: explicit list.** `run.sh` sources helpers, glob-sources all case files, and keeps the current hand-curated `run_test` ordering in `main()`. Deterministic and byte-for-byte equivalent to today's run order. Adding a test means editing both a case file and `main()`.
3. **Baseline test count: 89 for the split; 92 after output-prefix/stdin follow-ups.** The split started from 89 `test_*` functions and preserved that behavior. A follow-up harness-output test, `test_run_test_output_uses_status_prefixes`, plus two stdin regression tests now bring the current suite to 92 tests.
4. **New test structure: `tests/lib/helpers.sh` + `tests/cases/<area>.sh`.** Helper/driver code moves to `tests/lib/helpers.sh`; sourced-only test functions move under `tests/cases/` by command/area. Keep `tests/run.sh` as the only executable entrypoint.
5. **Lossless move proof: reconstruct by original `run_test` order.** Do not validate move-only behavior by simply concatenating case files. Rebuild the moved test region in the original `main()`/`run_test` order, then diff that reconstruction against the original test-function region.

```text
single entrypoint:        tests/run.sh           (path globals + sourcing + main())
shared helpers:           tests/lib/helpers.sh   (counters, asserts, fixtures, run_test)
per-area test functions:  tests/cases/*.sh       (sourced; ~12 files)
```

## Current State and Constraints

- `tests/run.sh` is a single 2308-line file containing:
  - **Header (lines 1–11):** shebang, `set -u`, `SCRIPT_DIR` / `REPO_ROOT` / `WORKBRANCH`, counters `PASS` / `FAIL` / `TMP_ROOT` / `FIXTURE_PROJECT`.
  - **Shared helpers (lines 13–151):** `log`, `fail`, `assert_*`, `manifest_version`, `run_expect_success`, `run_expect_fail`, `append_fake_tool_script`, `make_repo`, `commit_to_remote_master`, `commit_to_remote_branch`, `new_fixture`, `cleanup_fixture`, `run_test`.
  - **89 pre-split `test_*` functions (lines 152–2206), plus one follow-up meta test after the split.**
  - **`main()` (lines 2207–end):** prereq checks, then `run_test <name>` for every test in a fixed order, then pass/fail summary.
- Every test is self-contained: it calls `new_fixture` and is cleaned up by `cleanup_fixture` inside `run_test`. **There are no inter-test ordering dependencies**, so the explicit order is preserved purely for stable, readable output — not correctness.
- Some test bodies contain heredocs whose lines begin with `}` (106 column-0 `}` lines vs the 89 pre-split functions). **Slice test blocks by the next function's start line, never by brace matching.**
- `tests/run.sh` is invoked as `/bin/bash ./tests/run.sh` and referenced in `docs/plans/0002` and the release/verification matrix. The entrypoint path and invocation must not change.
- One test, `test_generated_workbranch_is_up_to_date`, calls `scripts/build-workbranch.sh` — unaffected by this refactor.
- No behavior, assertion, or fixture logic may change. This is a move-only refactor.

## Target File Structure

```text
tests/
  run.sh                       # entrypoint: globals + source helpers + source cases + main()
  lib/
    helpers.sh                 # counters, asserts, run/​fixture helpers, run_test driver
  cases/
    meta.sh                    # build freshness, help, version, removed commands
    init.sh                    # init / failed-init / legacy-config accepted on init
    add.sh                     # add (incl. safe-name validation, preflight, rollback)
    remove.sh                  # remove (incl. dirty-worktree safety, stale dirs)
    update.sh                  # update (batch + preflight)
    status.sh                  # status and list display
    config.sh                  # config / task-setup / repo-setup / legacy rewrites
    path.sh                    # path and scoped tool paths
    tool-launcher.sh           # tool launcher (editor/terminal)
    git-flow.sh                # full git flow: push / land / pull / repo-scope
    interactive-init.sh        # interactive init prompts
    installer.sh               # install.sh installer
```

## Test-to-File Routing

All current tests route by name prefix. Order matters for ambiguous prefixes (`test_interactive_init_*` before `test_init_*`; `test_repo_setup_*` → config, but `test_repo_scope_*` → git-flow).

| File | Tests (by name prefix / explicit name) |
|------|----------------------------------------|
| `meta.sh` | `test_generated_*`, `test_help_*`, `test_version_*`, `test_setup_command_is_removed`, `test_resume_command_is_removed` |
| `init.sh` | `test_init_*`, `test_failed_init_*` |
| `add.sh` | `test_add_*`, `test_safe_names_*` |
| `remove.sh` | `test_remove_*`, `test_dirty_worktree_safety` |
| `update.sh` | `test_update_*` |
| `status.sh` | `test_status_*`, `test_list_*` |
| `config.sh` | `test_config_*`, `test_task_setup_*`, `test_repo_setup_*`, `test_legacy_config_*`, `test_invalid_config_*` |
| `path.sh` | `test_path_*`, `test_scoped_tool_paths_*` |
| `tool-launcher.sh` | `test_editor_*`, `test_tool_*` |
| `git-flow.sh` | `test_full_git_flow`, `test_repo_scope_*`, `test_land_*`, `test_push_*`, `test_pull_*` |
| `interactive-init.sh` | `test_interactive_init_*` |
| `installer.sh` | `test_installer_*` |

Routing distribution after the harness-output/stdin follow-ups (must sum to 92): meta 8, init 9, add 10, remove 11, update 5, status 6, config 19, path 2, tool-launcher 3, git-flow 5, interactive-init 7, installer 7.

## Layering Rules

1. `tests/run.sh` owns path globals (`SCRIPT_DIR` / `REPO_ROOT` / `WORKBRANCH`), sources helpers + cases, and owns `main()` with the explicit `run_test` order.
2. `tests/lib/helpers.sh` owns all shared state (`PASS` / `FAIL` / `TMP_ROOT` / `FIXTURE_PROJECT`) and every shared function. It is sourced *after* the path globals are set (it reads `REPO_ROOT`).
3. `tests/cases/*.sh` contain only `test_*` function definitions — no top-level execution, no `main`, no `run_test` calls. They are sourced, so they carry `# shellcheck shell=bash` and no shebang.
4. A test function must appear in exactly one case file. No function is duplicated or redefined.
5. The set and order of `run_test` calls in `main()` must be byte-for-byte identical to the current file.

## Acceptance Criteria

- `tests/run.sh` remains the single entrypoint; `/bin/bash ./tests/run.sh` runs the full suite unchanged.
- All 92 tests still run, in the same order, and report `Tests passed: 92` with no failures.
- The number of `run_test` invocations in `main()` equals 92 and matches the original order exactly.
- Every `test_*` function is defined exactly once across `tests/cases/*.sh`; none remain in `tests/run.sh`.
- `tests/lib/helpers.sh` defines every shared helper exactly once; none remain in `tests/run.sh`.
- `/bin/bash -n` passes on `tests/run.sh`, `tests/lib/helpers.sh`, and every `tests/cases/*.sh`.
- No assertion, fixture, or test logic is changed (move-only). Reconstruct the moved test-function region by reading the new `tests/run.sh` `run_test` order and extracting each function block from `tests/cases/*.sh`, then diff that reconstruction against the original `tests/run.sh.orig` test-function region. Do not use a simple `cat tests/cases/*.sh` diff, because per-area grouping intentionally changes physical file order.
- `docs/plans/0002` verification/release matrices still work (`tests/run.sh` path and invocation unchanged).

## Implementation Tasks

### Task 1: Scaffold helpers and runner shell without removing anything

**Files:**

- Create: `tests/lib/helpers.sh`
- Create: `tests/cases/` (directory)
- Keep (temporary): `tests/run.sh` original as `tests/run.sh.orig` backup

- [x] **Step 1: Back up the original**

```bash
cp tests/run.sh tests/run.sh.orig
```

Evidence: `tests/run.sh.orig` created from the original runner.

- [x] **Step 2: Capture authoritative boundaries**

Record the function start lines for the move. Verify the counts before slicing:

```bash
grep -cE '^test_[a-zA-Z0-9_]*\(\) \{' tests/run.sh   # expect 89
grep -nE '^main\(\) \{' tests/run.sh                  # note main() start line
```

Expected: 89 test functions; first test starts at line 152; `main()` at line 2207. If these differ, re-derive ranges from live `grep` output rather than trusting the numbers here.

Evidence: `grep -cE` returned 89; `grep -nE '^main\(\) \{' tests/run.sh.orig` returned `2207:main() {`.

- [x] **Step 3: Extract shared helpers into `tests/lib/helpers.sh`**

Move lines 8–151 (counters through the end of `run_test`) verbatim. Prepend a sourced-file header. The helpers reference `REPO_ROOT`, which `run.sh` sets before sourcing.

```text
# shellcheck shell=bash
# Shared test helpers: counters, assertions, fixtures, and the run_test driver.
# Sourced by tests/run.sh (which defines SCRIPT_DIR / REPO_ROOT / WORKBRANCH first).
<lines 8-151 of original tests/run.sh, verbatim>
```

Expected: `tests/lib/helpers.sh` contains `PASS` / `FAIL` / `TMP_ROOT` / `FIXTURE_PROJECT` and all helper functions, and **no** `test_*` functions, no `main`, no shebang.

Evidence: helper extraction completed; `grep -cE` found 0 `test_*` functions and 0 `main()` definitions in `tests/lib/helpers.sh`.

### Task 2: Move test functions into per-area case files

**Files:**

- Create: `tests/cases/meta.sh`, `init.sh`, `add.sh`, `remove.sh`, `update.sh`, `status.sh`, `config.sh`, `path.sh`, `tool-launcher.sh`, `git-flow.sh`, `interactive-init.sh`, `installer.sh`

- [x] **Step 1: Slice each test block by next-function start**

For each `test_*` function, copy lines from its start through the line **before** the next function's start (the last test ends at `main()` start − 1). **Do not** end blocks on `}` — heredocs contain column-0 `}` lines. Route each function to its file per the Test-to-File Routing table. Preserve original line order within each file.

A mechanical extractor (run once, then delete) is the safe way to do this:

```bash
#!/usr/bin/env bash
set -euo pipefail
SRC=tests/run.sh
mkdir -p tests/cases tests/lib
mapfile -t starts < <(grep -nE '^test_[a-zA-Z0-9_]*\(\) \{' "$SRC" | sed 's/:.*//')
mapfile -t names  < <(grep -nE '^test_[a-zA-Z0-9_]*\(\) \{' "$SRC" | sed -E 's/^[0-9]+:([a-zA-Z0-9_]+)\(\).*/\1/')
main_start=$(grep -nE '^main\(\) \{' "$SRC" | head -n1 | sed 's/:.*//')
route() { case "$1" in
  test_installer_*) echo installer ;;
  test_interactive_init_*) echo interactive-init ;;
  test_init_*|test_failed_init_*) echo init ;;
  test_add_*|test_safe_names_*) echo add ;;
  test_remove_*|test_dirty_worktree_safety) echo remove ;;
  test_update_*) echo update ;;
  test_status_*|test_list_*) echo status ;;
  test_path_*|test_scoped_tool_paths_*) echo path ;;
  test_editor_*|test_tool_*) echo tool-launcher ;;
  test_config_*|test_task_setup_*|test_repo_setup_*|test_legacy_config_*|test_invalid_config_*) echo config ;;
  test_full_git_flow|test_repo_scope_*|test_land_*|test_push_*|test_pull_*) echo git-flow ;;
  test_generated_*|test_help_*|test_version_*|test_setup_command_is_removed|test_resume_command_is_removed) echo meta ;;
  *) echo "UNROUTED:$1" >&2; exit 1 ;;
esac }
n=${#names[@]}
for ((i=0;i<n;i++)); do
  s=${starts[i]}
  if ((i+1<n)); then e=$(( starts[i+1]-1 )); else e=$(( main_start-1 )); fi
  f="tests/cases/$(route "${names[i]}").sh"
  [ -f "$f" ] || printf '# shellcheck shell=bash\n# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.\n' > "$f"
  awk -v s="$s" -v e="$e" 'NR>=s && NR<=e' "$SRC" >> "$f"
done
```

Evidence: 89 test blocks were routed into 12 `tests/cases/*.sh` files using next-function boundaries from `tests/run.sh.orig`.

- [x] **Step 2: Verify the move was lossless**

```bash
# Every routed test still exists exactly once across case files
grep -hcE '^test_[a-zA-Z0-9_]*\(\) \{' tests/cases/*.sh | paste -sd+ - | bc   # expect 92
grep -hoE '^test_[a-zA-Z0-9_]*\(\) \{' tests/cases/*.sh | sort | uniq -d      # expect empty (no dupes)
# No stray top-level execution leaked into case files
grep -nE '^(main|run_test|\. )' tests/cases/*.sh                              # expect empty
```

Expected: 92 current total, no duplicates, no top-level execution in case files.

Evidence: initial split case-file scan found 89 tests; after adding `test_run_test_output_uses_status_prefixes`, current case-file scan finds 92 tests, no duplicate function names, and no top-level `main`, `run_test`, or source execution lines.

- [x] **Step 3: Verify function bodies are unchanged**

Reconstruct moved tests in the original explicit run order before diffing. This avoids false failures from the new per-area physical file layout.

```bash
python3 - <<'PY'
from pathlib import Path
import re

orig = Path('tests/run.sh.orig').read_text()
new_run = Path('tests/run.sh').read_text()

def names_from_main(text):
    return re.findall(r'^\s*run_test\s+(test_[A-Za-z0-9_]+)\s*$', text, re.M)

def blocks_by_name(text):
    matches = list(re.finditer(r'^(test_[A-Za-z0-9_]+)\(\) \{', text, re.M))
    main = re.search(r'^main\(\) \{', text, re.M)
    end = main.start() if main else len(text)
    blocks = {}
    for i, m in enumerate(matches):
        block_end = matches[i + 1].start() if i + 1 < len(matches) else end
        blocks[m.group(1)] = text[m.start():block_end].rstrip() + '\n'
    return blocks

orig_order = names_from_main(orig)
new_order = names_from_main(new_run)
if orig_order != new_order:
    raise SystemExit('run_test order changed')
orig_blocks = blocks_by_name(orig)
new_blocks = {}
for path in sorted(Path('tests/cases').glob('*.sh')):
    for name, block in blocks_by_name(path.read_text()).items():
        if name in new_blocks:
            raise SystemExit(f'duplicate moved test: {name}')
        new_blocks[name] = block
missing = [name for name in orig_order if name not in new_blocks]
extra = sorted(set(new_blocks) - set(orig_order))
if missing or extra:
    raise SystemExit(f'missing={missing} extra={extra}')
Path('/tmp/workbranch-tests-orig-region').write_text('\n'.join(orig_blocks[name].rstrip() for name in orig_order) + '\n')
Path('/tmp/workbranch-tests-new-region').write_text('\n'.join(new_blocks[name].rstrip() for name in new_order) + '\n')
PY
diff -u /tmp/workbranch-tests-orig-region /tmp/workbranch-tests-new-region
```

Expected: empty diff.

Evidence: original-order reconstruction diff was empty after extracting function blocks per case file, excluding sourced-file headers.

### Task 3: Rewrite `tests/run.sh` as the thin entrypoint

**Files:**

- Modify: `tests/run.sh`

- [x] **Step 1: Replace `run.sh` with globals + sourcing + `main()`**

```bash
#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)
WORKBRANCH="$REPO_ROOT/bin/workbranch"

. "$SCRIPT_DIR/lib/helpers.sh"
for case_file in "$SCRIPT_DIR"/cases/*.sh; do
  . "$case_file"
done

main() {
  [ -x "$WORKBRANCH" ] || fail "missing executable: $WORKBRANCH"
  git --version >/dev/null || fail "git is required"

  <the exact run_test ... lines from the original main(), in the original order>

  log "Tests passed: $PASS"
  if [ "$FAIL" -ne 0 ]; then
    log "Tests failed: $FAIL"
    exit 1
  fi
}

main "$@"
```

The `run_test` block must be copied verbatim from the original `main()` — same names, same order. Do not regenerate or reorder it.

Evidence: `tests/run.sh` now contains 0 `test_*` functions and 0 helper definitions; it sources `tests/lib/helpers.sh` and `tests/cases/*.sh` before `main()`.

- [x] **Step 2: Confirm ordering parity**

```bash
# Original order (from backup) vs new run.sh order must be identical
grep -E '^\s*run_test ' tests/run.sh.orig | awk '{print $2}' > /tmp/order_orig
grep -E '^\s*run_test ' tests/run.sh      | awk '{print $2}' > /tmp/order_new
diff /tmp/order_orig /tmp/order_new        # expect empty
wc -l < /tmp/order_new                      # expect 92 after output-prefix/stdin follow-ups
```

Evidence: original/new `run_test` order diff was empty for the split baseline; current `run_test` order contains 92 entries after the output-prefix/stdin follow-ups.

Additional evidence: post-runner original-order reconstruction diff was empty.

### Task 4: Verify and clean up

**Files:**

- Delete: `tests/run.sh.orig`
- Delete: any temporary extractor script

- [x] **Step 1: Syntax-check all test files**

```bash
/bin/bash -n tests/run.sh tests/lib/helpers.sh tests/cases/*.sh
```

Expected: no syntax errors.

Evidence: `/bin/bash -n tests/run.sh tests/lib/helpers.sh tests/cases/*.sh` passed before and after scaffolding cleanup.

- [x] **Step 2: Run the full suite**

```bash
./scripts/build-workbranch.sh
/bin/bash ./tests/run.sh
```

Expected: `Tests passed: 92`, no `Tests failed:` line, exit 0.

Evidence: `/bin/bash -n tests/run.sh tests/lib/helpers.sh tests/cases/*.sh && /bin/bash ./tests/run.sh` passed with `Tests passed: 92` after adding the output-prefix/stdin meta tests.

- [x] **Step 3: Optional ShellCheck (when available)**

```bash
shellcheck -x tests/run.sh tests/lib/helpers.sh tests/cases/*.sh
```

`-x` lets ShellCheck follow the sourced helpers. Treat findings as informational; this refactor introduces no new logic.

Evidence: ShellCheck was available and ran. It reported non-blocking informational/warning findings around dynamic sources (`SC1090`/`SC1091`), cross-file fixture state (`SC2034`), and pre-existing intentional test snippets (`SC2155`/`SC2016`); no logic was changed to silence optional lint output.

- [x] **Step 4: Remove scaffolding**

```bash
rm -f tests/run.sh.orig /tmp/order_orig /tmp/order_new /tmp/workbranch-tests-orig-region /tmp/workbranch-tests-new-region
```

Evidence: `tests/run.sh.orig` and temporary `/tmp` comparison files were removed; post-cleanup syntax and `git diff --check` passed.

- [x] **Step 5: Commit checkpoint (not committed; explicit request required)**

Use a Lore-style commit message if committing:

```text
Split the integration suite into per-area test files

Constraint: tests/run.sh stays the single entrypoint; run order and pass count unchanged.
Rejected: auto-discovery of tests | would drop the hand-curated, stable run order.
Rejected: strict 1:1 mirror of src/ | several tests span modules; awkward fit.
Confidence: high
Scope-risk: narrow (move-only; no assertion or fixture logic changed)
Directive: add new tests to the matching tests/cases/<area>.sh AND register them in main().
Tested: run-order reconstruction diff; /bin/bash -n tests/run.sh tests/lib/helpers.sh tests/cases/*.sh; /bin/bash ./tests/run.sh
```

Evidence: Commit was not created because `plan-execute auto` stops before git commit/push unless explicitly requested.

## Verification Matrix

Run before claiming completion:

```bash
./scripts/build-workbranch.sh
/bin/bash -n tests/run.sh tests/lib/helpers.sh tests/cases/*.sh
/bin/bash ./tests/run.sh        # expect: Tests passed: 92
grep -hcE '^test_[a-zA-Z0-9_]*\(\) \{' tests/cases/*.sh | paste -sd+ - | bc   # expect 92
grep -E '^\s*run_test ' tests/run.sh | wc -l                                  # expect 92
# Also run Task 2 Step 3's reconstruction diff before deleting tests/run.sh.orig.
```

## Explicitly Deferred

- Auto-discovery of test files or self-registering tests (chose explicit ordering).
- Strict 1:1 mirroring of every `src/workbranch/**` module path.
- Parallel test execution or a faster runner.
- Any change to assertions, fixtures, or test coverage.
- Splitting `tests/lib/helpers.sh` further (asserts vs fixtures vs driver) — keep one helper file until it earns a split.

## Self-Review

- Spec coverage: covers helper extraction, per-area grouping, explicit-order runner, and a verification path proving lossless move and unchanged run order.
- Risk scan: the only real hazard is slicing on `}` inside heredocs; the plan mandates next-function-start slicing and includes count/dup/order checks to catch a bad move.
- Scope check: move-only refactor; no test logic changes; entrypoint and invocation preserved so downstream docs and release steps keep working.
