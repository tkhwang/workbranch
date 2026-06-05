# 0007 Colorful CLI Display and Banner Refactor Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` before behavior changes. Make source changes under `src/workbranch/**`, then run `scripts/build-workbranch.sh`, then verification. Never edit `bin/workbranch` by hand.

**Goal:** Make `workbranch` command-line output feel closer to Mole: colorful, scannable, and pleasant in an interactive terminal, with a banner and clearer title/section/item display.

**Architecture:** Add a small dependency-free ANSI presentation layer in the existing Bash source tree. Keep Git behavior, command semantics, and machine-readable path output unchanged. Use color only as presentation, with `NO_COLOR` and non-TTY safeguards so tests, pipes, and scripts stay stable.

**Tech Stack:** Portable Bash, ANSI escape sequences, existing generated single-file distribution (`scripts/build-workbranch.sh` -> `bin/workbranch`), integration tests in `tests/run.sh`.

---

## Inspiration and Current Evidence

### Mole reference surface

Mole's CLI display is built around a small set of color and icon constants:

- `GREEN`, `BLUE`, `CYAN`, `YELLOW`, `PURPLE_BOLD`, `RED`, `GRAY`, `NC`
- `ICON_CONFIRM=◎`, `ICON_ADMIN=⚙`, `ICON_SUCCESS=✓`, `ICON_LIST=•`, `ICON_SUBLIST=↳`, `ICON_ARROW=➤`, `ICON_REVIEW=☞`

The shell-side Mole display does not need a color library. It defines ANSI constants directly and clears them when `NO_COLOR` is set. Its section display is similarly simple: `➤ <section title>` in purple/bold, indented result lines, and gray review/sub-detail lines.

Relevant Mole files checked at `tw93/Mole` commit `b62eb8706277`:

- `lib/core/base.sh` — color and icon constants; `NO_COLOR` support; generic `start_section`/`end_section` helpers.
- `bin/clean.sh` — clean-command section header override using `➤` and `Nothing to clean` fallback.
- `lib/clean/hints.sh` — Mole-like list/sublist/review output for the exact sample style.
- `cmd/analyze/constants.go` — Go TUI color constants; useful reference, but not the right implementation model for this Bash CLI.

### workbranch current surface

Current `workbranch` output is intentionally simple and centralized only at the top level:

- `src/workbranch/lib/output.sh`
  - `info()` prints `[*] ...`
  - `success()` prints `[+] ...`
  - `die()` prints `[-] Error: ...`
- `src/workbranch/usage.sh` prints plain help text.
- `src/workbranch/commands/list.sh` and `src/workbranch/lib/status-format.sh` print aligned tables directly with `printf`.
- `src/workbranch/commands/init.sh` already has an onboarding-style intro and is the best place to introduce a banner for first-run interactive UX.
- `scripts/workbranch-sources.txt` includes `src/workbranch/lib/output.sh` before command modules, so color/icon helpers placed there are available everywhere after generation.

Current tests assert literal `[*]`, `[+]`, and `[-] Error:` prefixes in several places. Therefore, this refactor must avoid breaking the text contract unless tests and docs are intentionally updated in the same phase.

---

## Decisions

1. **Use direct ANSI constants, not a library.**
   - `workbranch` is a dependency-free Bash CLI with a generated single-file install artifact.
   - Adding a library would complicate curl/Homebrew distribution for little gain.

2. **Color defaults to interactive-only, and `NO_COLOR` always wins.**
   - Default mode: color when stdout is a TTY and `TERM` is not `dumb`.
   - `NO_COLOR` non-empty disables all ANSI/color/banner enhancement even if `WORKBRANCH_COLOR=always` is set.
   - Add `WORKBRANCH_COLOR=auto|always|never` for explicit override, with `NO_COLOR` as the stronger opt-out.

3. **Keep existing semantic prefixes in phase 1.**
   - Preserve `[*]`, `[+]`, and `[-] Error:` text for compatibility.
   - Color the prefix/title/label, not the full line by default.
   - Introduce Mole-style icons as helper functions first, then selectively use them where the output is not part of existing strict tests or where tests are updated deliberately.

4. **Banner and Mole-style section markers are enhanced terminal display, not captured/script output.**
   - Show the banner and `➤` section markers only when the presentation layer is enabled (`color_enabled`, including `WORKBRANCH_COLOR=always`).
   - Keep non-TTY captured `workbranch help` compact and plain by default so existing tests and scripts do not receive banner lines, blank lines, or ANSI escapes.
   - Do not print a banner for scriptable commands like `workbranch path`, `version`, or successful Git operations unless explicitly requested later.

5. **No behavior changes in this slice.**
   - Git commands, config parsing, branch naming, task metadata, and setup command execution stay unchanged.
   - This plan is presentation-only.

---

## Decision Gates

- [x] Enhanced help display contract
  - Impact: user-visible help output, script/test compatibility, banner visibility.
  - Current evidence: `tests/cases/meta.sh:test_help_groups_commands` asserts compact help with no blank lines plus literal `Workspace:`, `Git:`, `Tool:`, `Config:`, `Other:`, and subgroup labels `vertical`, `horizontal`, `common`; `src/workbranch/usage.sh` currently emits that compact plain shape.
  - Resolved decision: gate Mole-style banner and `➤` section markers behind enhanced display (`color_enabled`, including `WORKBRANCH_COLOR=always`) and keep default non-TTY captured help compact/plain.
  - Rationale: this preserves scripts and existing tests by default while still giving interactive users the Mole-like surface. The rejected alternative, changing default help to always show the banner/`➤` shape, would require rewriting the compact-help test and could surprise users or scripts that inspect help output.
  - Status: resolved: gated enhanced display.

- [x] Display regression test file placement
  - Impact: new test file path, test runner ordering, future maintainability of user-visible display regressions.
  - Current evidence: `tests/run.sh` sources every `tests/cases/*.sh`, but each test still needs an explicit `run_test` entry; existing help/harness tests live in `tests/cases/meta.sh`, while command-area behavior lives in dedicated case files.
  - Resolved decision: add a focused `tests/cases/display.sh` for Mole-like title/banner/color regression tests, and add explicit `run_test` calls in `tests/run.sh`.
  - Rationale: banner/color/title display is a cross-command user-visible surface rather than only help metadata. A dedicated file keeps enhanced display tests from growing the already mixed-purpose `meta.sh`, while the explicit runner entries preserve deterministic test order.
  - Status: resolved: `tests/cases/display.sh`.

---

## Target UX Direction

### Banner

Use a compact ASCII banner inspired by Mole, but keep it narrow enough for default terminals. This banner is an enhanced terminal surface only: it must be gated by `color_enabled` / `WORKBRANCH_COLOR=always`, and it must not appear in default non-TTY captured help output.

```text
__        __         _    _                         _
\ \      / /__  _ __| | _| |__  _ __ __ _ _ __   ___| |__
 \ \ /\ / / _ \| '__| |/ / '_ \| '__/ _` | '_ \ / __| '_ \
  \ V  V / (_) | |  |   <| |_) | | | (_| | | | | (__| | | |
   \_/\_/ \___/|_|  |_|\_\_.__/|_|  \__,_|_| |_|\___|_| |_|

                       Task-based Git worktrees, made easy.
```

If this is too wide or visually noisy during implementation, use a shorter banner:

```text
              _    _                         _
__      _____| | _| |__  _ __ __ _ _ __   ___| |__
\ \ /\ / / _ \ |/ / '_ \| '__/ _` | '_ \ / __| '_ \
 \ V  V /  __/   <| |_) | | | (_| | | | | (__| | | |
  \_/\_/ \___|_|\_\_.__/|_|  \__,_|_| |_|\___|_| |_|
                       Task-based Git worktrees, made easy.
```

### Colored help/menu titles

When enhanced terminal display is enabled, `workbranch help` should remain readable but get title grouping:

```text
__        __         _    _                         _
\ \      / /__  _ __| | _| |__  _ __ __ _ _ __   ___| |__
 \ \ /\ / / _ \| '__| |/ / '_ \| '__/ _` | '_ \ / __| '_ \
  \ V  V / (_) | |  |   <| |_) | | | (_| | | | | (__| | | |
   \_/\_/ \___/|_|  |_|\_\_.__/|_|  \__,_|_| |_|\___|_| |_|

                       Task-based Git worktrees, made easy.

➤ Workspace
  init              Initialize a workbranch project
  list              List configured repos and task workspaces
  add <task>        Create a task workspace
  remove <task>     Remove task worktrees and local task branches

➤ Git
  status            Show commits, diff, and dirty state
  vertical
  pull              Pull remote base branches into main worktrees
  ...
```

Implementation note: keep exact command descriptions unless the phase also updates tests/docs. Prefer adding colored section rendering helpers over rewriting the command list. Default non-TTY help should keep the current compact shape unless the implementation intentionally rewrites `tests/cases/meta.sh:test_help_groups_commands` in the same patch.

### Section and item helpers

Add helpers that mirror Mole's display vocabulary but stay `workbranch`-specific:

```bash
section()      # purple/bold: ➤ Title
item_ok()      # green: ✓ message
item_warn()    # yellow: ◎ message
item_info()    # blue/gray: • message
item_detail()  # gray: ↳ detail
item_review()  # gray: ☞ next action / review note
```

Existing wrappers remain:

```bash
info()         # colored [*]
success()      # colored [+]
die()          # colored [-] Error:
```

### Status/list display improvements

Apply color to values, not just prefixes:

- `clean` -> green
- `modified`, `untracked`, `modified, untracked` -> yellow
- `missing`, `?` -> red or gray depending on context
- `+N` diff / `land` -> green or blue
- `-N`, `±A/B` / `update` -> yellow
- `check` -> yellow
- table headers -> gray or bold

Keep columns aligned by applying **pad-then-color** formatting. Do not pass pre-colored strings into `printf '%-Ns'`, because ANSI escape bytes count toward Bash/printf field width and will break alignment. Compute or print padded plain values first, then wrap only the visible cell text with color, or add an explicit helper that pads by visible width before adding ANSI escapes.

---

## Implementation Phases

### Phase 1: Color capability and compatibility tests

**Files:**

- Modify: `src/workbranch/lib/output.sh`
- Add: `tests/cases/display.sh`
- Modify: `tests/run.sh` to add explicit `run_test` entries for display regressions
- Regenerate: `bin/workbranch`

**Tasks:**

- [x] Add `color_enabled()` with this exact priority order:
  - `NO_COLOR` non-empty -> disabled and wins over every `WORKBRANCH_COLOR` value
  - `WORKBRANCH_COLOR=never` -> disabled
  - `WORKBRANCH_COLOR=always` -> enabled only when `NO_COLOR` is empty
  - default `auto` -> enabled only when stdout is TTY, `TERM != dumb`, and `NO_COLOR` is empty
- [x] Add color constants with empty fallback:
  - `WB_GREEN`, `WB_BLUE`, `WB_CYAN`, `WB_YELLOW`, `WB_PURPLE`, `WB_PURPLE_BOLD`, `WB_RED`, `WB_GRAY`, `WB_BOLD`, `WB_RESET`
- [x] Add icon constants:
  - `WB_ICON_CONFIRM=◎`, `WB_ICON_SUCCESS=✓`, `WB_ICON_WARNING=◎`, `WB_ICON_LIST=•`, `WB_ICON_SUBLIST=↳`, `WB_ICON_ARROW=➤`, `WB_ICON_REVIEW=☞`
- [x] Update `info`, `success`, and `die` to color only their prefix/error label.
- [x] Add tests in `tests/cases/display.sh` proving captured output remains uncolored by default, because test helpers capture pipes/non-TTY output.
- [x] Add focused tests in `tests/cases/display.sh` for explicit overrides:
  - `WORKBRANCH_COLOR=always workbranch help` contains ANSI escapes.
  - `NO_COLOR=1 WORKBRANCH_COLOR=always workbranch help` contains no ANSI escapes because `NO_COLOR` is always the stronger override.
  - `WORKBRANCH_COLOR=never workbranch help` contains no ANSI escapes.

**Acceptance Criteria:**

- Existing prefix assertions still pass.
- No command output has raw ANSI escapes under non-TTY capture unless `WORKBRANCH_COLOR=always` is set.
- `NO_COLOR` behavior is documented by tests.

### Phase 2: Banner and help title rendering

**Files:**

- Modify: `src/workbranch/usage.sh`
- Modify: `src/workbranch/main.sh` only if no-arg behavior needs a separate banner path
- Add/modify: `tests/cases/display.sh` for enhanced banner/title assertions
- Modify: `tests/cases/meta.sh` only if the default compact help contract intentionally changes
- Modify: `tests/run.sh` to add explicit display test ordering
- Regenerate: `bin/workbranch`

**Tasks:**

- [x] Add `print_banner()` in `src/workbranch/usage.sh` or `src/workbranch/lib/output.sh`.
- [x] Render the banner for `workbranch help`, `workbranch -h`, `workbranch --help`, and no-arg usage only when enhanced terminal display is enabled.
- [x] Keep default non-TTY captured help output compact, plain, and compatible with `tests/cases/meta.sh:test_help_groups_commands` unless that test is intentionally rewritten in the same patch.
- [x] Keep `workbranch version` and `workbranch path` banner-free.
- [x] Convert help section labels from plain text to a helper such as `section "Workspace"`, `section "Git"`, `section "Tool"`, `section "Config"`, `section "Other"` only for enhanced display; default plain help should continue to expose `Workspace:`, `Git:`, `Tool:`, `Config:`, and `Other:` unless tests are updated.
- [x] Preserve the `vertical`, `horizontal`, and `common` help subgroup labels, because `tests/cases/meta.sh:test_help_groups_commands` asserts those exact indented words.
- [x] If implementation changes the default captured help shape, update the compact-help no-blank-line assertion and the five literal section-header assertions (`Workspace:`, `Git:`, `Tool:`, `Config:`, `Other:`) in `tests/cases/meta.sh` in the same patch. Preferred implementation: do not change default captured help shape; add separate `WORKBRANCH_COLOR=always` assertions for banner and `➤` section markers.
- [x] Add snapshot-style assertions in `tests/cases/display.sh` for key banner text and section markers under `WORKBRANCH_COLOR=always`, and no-banner/no-blank-line assertions for default captured help.

**Acceptance Criteria:**

- `WORKBRANCH_COLOR=always workbranch help` includes the banner and tagline when `NO_COLOR` is unset.
- Default captured `workbranch help` stays compact: no banner, no ANSI escapes, and no blank lines unless `tests/cases/meta.sh:test_help_groups_commands` is intentionally updated in the same patch.
- Existing help command descriptions and subgroup labels (`vertical`, `horizontal`, `common`) are still present.
- Colored/enhanced help is visible with `WORKBRANCH_COLOR=always`.

### Phase 3: Shared section/item vocabulary

**Files:**

- Modify: `src/workbranch/lib/output.sh`
- Modify selected call sites after helper introduction:
  - `src/workbranch/commands/init.sh`
  - `src/workbranch/commands/list.sh`
  - `src/workbranch/commands/status.sh`
  - `src/workbranch/lib/status-format.sh`
  - `src/workbranch/lib/preflight.sh`
  - `src/workbranch/lib/task-setup.sh`
- Regenerate: `bin/workbranch`

**Tasks:**

- [x] Add helper functions:
  - `section`, `item_ok`, `item_warn`, `item_info`, `item_detail`, `item_review`, `table_header`, `color_status`, `color_diff`, `color_next_action`.
- [x] Replace direct title prints in `list` and `status` with `section` where it improves scanning.
- [x] Keep existing `info` where output wording is already part of tests, or update tests in the same patch if switching to `section` is intentional.
- [x] Color status/diff/action values in `status-format.sh` only with pad-then-color helpers at the final print boundary; never pass ANSI-colored strings directly into the existing `printf '%-11s ...'` field-width calls.
- [x] Use detail/review helpers for preflight guidance lines where Mole-like display improves readability.

**Acceptance Criteria:**

- Status/list output is visually grouped like Mole:
  - colored section titles
  - gray table headers
  - colored status labels
  - gray detail/review lines
- No machine-sensitive output changes for `workbranch path <task> [--repo <repo>]`.
- Column alignment remains acceptable in color and no-color modes, with explicit proof that ANSI escapes do not affect the visible table widths.

### Phase 4: Interactive init onboarding polish

**Files:**

- Modify: `src/workbranch/commands/init.sh`
- Modify: `src/workbranch/lib/prompts.sh` if prompt prefix coloring should be centralized
- Modify: `tests/cases/interactive-init.sh`
- Regenerate: `bin/workbranch`

**Tasks:**

- [x] Show the banner at the start of first-run interactive init.
- [x] Use `section` for `Project`, `Repositories`, `Summary`.
- [x] Use `item_detail` for the directory tree explanation and setup guide detail lines where possible.
- [x] Color prompt prefixes but preserve prompt text and default values.
- [x] Keep prompts on stderr, as current transcript tests rely on stdout/stderr capture behavior.

**Acceptance Criteria:**

- Interactive init feels like a guided CLI screen rather than raw logs.
- Existing blank-line and prompt-order tests are updated intentionally, not accidentally broken.
- Non-TTY behavior remains deterministic.

### Phase 5: Docs and release notes

**Files:**

- Modify: `README.md`
- Modify: `README.ko.md` if matching Korean docs are maintained for CLI output examples
- Modify: `docs/specs/0001-workbranch-mvp.md` if it includes output examples affected by banner/help/status formatting
- Regenerate: `bin/workbranch`

**Tasks:**

- [x] Document color behavior:
  - default auto-color only on TTY
  - `NO_COLOR=1`
  - `WORKBRANCH_COLOR=auto|always|never`
- [x] Update help/status examples to show the new text display without embedding raw ANSI escapes.
- [x] Mention that scriptable `path` output remains plain.

**Acceptance Criteria:**

- Docs match the new user-facing output.
- No docs imply color appears in pipes by default.

---

## Testing and Verification

Run these after each implementation phase that edits source:

```bash
./scripts/build-workbranch.sh
/bin/bash -n bin/workbranch install.sh tests/run.sh scripts/build-workbranch.sh
./tests/run.sh
git diff --check
```

Additional focused checks for this plan:

```bash
# No color in captured output by default
./bin/workbranch help | LC_ALL=C grep -q $'\033' && echo "unexpected color" && exit 1 || true

# Forced color works
WORKBRANCH_COLOR=always ./bin/workbranch help | LC_ALL=C grep -q $'\033'

# NO_COLOR wins
NO_COLOR=1 WORKBRANCH_COLOR=always ./bin/workbranch help | LC_ALL=C grep -q $'\033' && echo "unexpected color" && exit 1 || true

# Scriptable path output remains plain once a fixture/project exists
# Use the integration test fixture path command rather than ad hoc local state.
```

Manual QA gate:

- Run `WORKBRANCH_COLOR=always ./bin/workbranch help` in a terminal and confirm:
  - banner appears
  - title/section colors are visible
  - command descriptions remain readable
- Run `WORKBRANCH_COLOR=always ./bin/workbranch status` inside a test project and confirm:
  - section titles scan like Mole
  - status labels are readable
  - table alignment is still acceptable
- Run `NO_COLOR=1 ./bin/workbranch help` and confirm plain output.

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| ANSI escapes break tests or scripts | High | Default to no color under non-TTY capture; add explicit override tests. |
| Existing prefix contract changes accidentally | Medium | Keep `[*]`, `[+]`, `[-] Error:` in phase 1; update tests only when deliberately changing a call site. |
| Unicode icons render poorly in some terminals | Medium | Keep text prefixes for core wrappers; isolate Mole-like icons behind helper functions; allow no-color/plain mode to remain readable. |
| Colored table values break alignment | Medium | Use pad-then-color helpers; never pass ANSI-colored values into `printf '%-Ns'` padding. |
| Banner or section-marker output breaks compact help tests | High | Gate banner/`➤` section markers behind `color_enabled`; keep default non-TTY help plain, or update `test_help_groups_commands` in the same patch if changing default help. |
| Banner becomes noisy for automation | Medium | Show banner only for enhanced terminal help/no-arg/interactive init, never on scriptable outputs like `path` or `version`. |
| Generated `bin/workbranch` drifts | High | Always edit `src/workbranch/**`, run `scripts/build-workbranch.sh`, and rely on `test_generated_workbranch_is_up_to_date`. |

---

## Out of Scope

- Full-screen TUI navigation like Mole's menu.
- Spinners/progress bars.
- External color/TUI libraries.
- Changing Git command behavior, config semantics, branch naming, or workspace layout.
- Making `workbranch path` colorful by default.

---

## Done Definition

- Banner exists for help/no-arg/interactive init.
- Title and section display is colorful in interactive terminals.
- Status/list text display is more scannable using section/item/detail/review helpers.
- `NO_COLOR` and `WORKBRANCH_COLOR=auto|always|never` are tested and documented.
- `bin/workbranch` is regenerated from source.
- Syntax checks, integration tests, and `git diff --check` pass.

---

## Execution Evidence

Updated during `$plan-execute auto` implementation.

- Phase 1 complete: added dependency-free ANSI/color helpers, icons, override behavior, and display regression tests. RED evidence: forced-color error-prefix test failed before `output.sh` implementation; GREEN evidence: targeted display tests passed after rebuild.
- Phase 2 complete: added enhanced gated banner/help rendering. Default non-TTY help remains compact/plain; `WORKBRANCH_COLOR=always` shows banner and `➤` sections; `NO_COLOR` suppresses enhancements.
- Phase 3 complete: added shared section/item/value helpers, applied section/status/list/preflight/task-setup display polish, and kept table coloring pad-then-color via `color_cell`. RED evidence: forced-color status/preflight/task-setup tests failed before implementation; GREEN evidence: targeted tests passed after rebuild.
- Phase 4 complete: interactive init now shows the banner and sectioned onboarding under enhanced display; prompt prefixes are colored when color is enabled and plain otherwise. RED evidence: forced-color init prompt-prefix assertion failed before `prompts.sh` update; GREEN evidence: targeted init display test passed after rebuild.
- Phase 5 complete: README, README.ko, and MVP spec document auto-color, `NO_COLOR`, `WORKBRANCH_COLOR`, enhanced display, and plain scriptable `path` output without raw ANSI examples.

Verification recorded so far:

- `./scripts/build-workbranch.sh` — pass after source changes.
- Targeted TDD checks:
  - `test_display_forced_color_init_shows_banner_and_sections` — RED before prompt coloring, pass after implementation.
  - `test_display_forced_color_task_setup_failure_is_colored` — RED before task-setup coloring, pass after implementation.
- Full suite and final static checks were run after the plan update; final command output is recorded below and reported in the handoff summary.

Final verification:

- `./scripts/build-workbranch.sh` — pass.
- `/bin/bash -n bin/workbranch install.sh tests/run.sh scripts/build-workbranch.sh src/workbranch/lib/output.sh src/workbranch/lib/prompts.sh src/workbranch/lib/status-format.sh src/workbranch/lib/preflight.sh src/workbranch/lib/task-setup.sh src/workbranch/commands/add.sh src/workbranch/commands/init.sh src/workbranch/usage.sh tests/cases/display.sh` — pass.
- `./tests/run.sh` — pass, `Tests passed: 107`.
- `git diff --check` — pass.
- Manual smoke — pass:
  - `env -u NO_COLOR WORKBRANCH_COLOR=always ./bin/workbranch help` contains ANSI, banner tagline, and `➤ Workspace`.
  - `NO_COLOR=1 WORKBRANCH_COLOR=always ./bin/workbranch help` contains no ANSI/banner and keeps `Workspace:`.
  - `WORKBRANCH_COLOR=never ./bin/workbranch help` contains no ANSI.
  - `env -u NO_COLOR WORKBRANCH_COLOR=always ./bin/workbranch version` remains banner-free.
  - `env -u NO_COLOR WORKBRANCH_COLOR=always ./bin/workbranch path login --repo frontend` returns only the plain path in a fixture.
