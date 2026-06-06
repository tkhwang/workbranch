# 0008 Superset-Style Open-In-App Launcher Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` before every behavior change. Make source changes under `src/workbranch/**`, rebuild with `scripts/build-workbranch.sh`, then verify with syntax checks, targeted tests, `./tests/run.sh`, and manual installed-binary smoke checks. Do not edit `bin/workbranch` by hand.

**Goal:** Evolve `workbranch` tool launching from raw configured commands into a Superset-inspired app launcher model with three app kinds: Finder, IDE, and Terminal.

**Architecture:** Use `IDE` consistently across the command, config prompt, config directive, status output, help text, and docs. The config directive becomes `IDE`, not `EDITOR`; this branch intentionally does not preserve `.workbranch.config` format compatibility for old `EDITOR` directives. Finder is not configured; it opens resolved task/repo paths directly.

**Tech Stack:** Portable Bash, macOS `open`, optional Linux CLI fallbacks for future work, line-oriented `.workbranch.config`, generated `bin/workbranch`, existing `tests/run.sh` integration suite, Superset benchmark at `superset-sh/superset` commit `e259b59`.

---

## Benchmark Evidence

Superset's launcher is split into three responsibilities:

1. **App option taxonomy in UI**
   - Finder, IDE, Terminal, VS Code submenu, JetBrains submenu, and Copy path are rendered from app option arrays.
   - Relevant files:
     - `apps/desktop/src/renderer/components/OpenInExternalDropdown/constants.ts`
     - `apps/desktop/src/renderer/components/OpenInExternalDropdown/OpenInExternalDropdownItems.tsx`

2. **App id -> OS command resolver**
   - `getAppCommand(app, targetPath, platform)` maps an app id to commands.
   - macOS uses `open -a <AppName> <path>` or `open -b <bundleId> <path>` for multi-edition JetBrains apps.
   - Linux uses direct CLI commands such as `cursor`, `code`, `zed`, `subl`, and JetBrains candidate fallbacks.
   - Relevant file: `apps/desktop/src/lib/trpc/routers/external/helpers.ts`.

3. **Open router with fallback/default persistence**
   - `openPathInApp` handles Finder specially, tries candidate commands, and falls back to Electron `shell.openPath` if no command is available.
   - `openInApp` persists project/global defaults after successful launch.
   - Relevant file: `apps/desktop/src/lib/trpc/routers/external/index.ts`.

Superset's approach is stronger than the current `workbranch` implementation in taxonomy, app coverage, and platform-aware command resolution. `workbranch`'s current approach is stronger for the specific multi-repo requirement because it already fans out one command per repo path and, for VS Code-like IDEs, uses `open -na ... --args --new-window <repo-path>` so each repo opens in a separate window.

Source links used for this benchmark:

- `constants.ts`: https://github.com/superset-sh/superset/blob/e259b59/apps/desktop/src/renderer/components/OpenInExternalDropdown/constants.ts
- `OpenInExternalDropdownItems.tsx`: https://github.com/superset-sh/superset/blob/e259b59/apps/desktop/src/renderer/components/OpenInExternalDropdown/OpenInExternalDropdownItems.tsx
- `helpers.ts`: https://github.com/superset-sh/superset/blob/e259b59/apps/desktop/src/lib/trpc/routers/external/helpers.ts
- `index.ts`: https://github.com/superset-sh/superset/blob/e259b59/apps/desktop/src/lib/trpc/routers/external/index.ts

## Naming Decision: IDE Everywhere

Use `IDE` consistently at every user-facing and config layer:

- **Display/group name:** `IDE`
  - Better matches the Superset taxonomy and the actual app list.
  - Avoids implying this is only `$EDITOR`-style text editing.
  - Menus and status lines should say `IDE command:` and `Opening IDE:`.

- **Primary CLI/config term:** `ide`
  - Use `workbranch ide <task>` and `workbranch config ide` as the user-facing commands.
  - Do not document or add new `editor` aliases in this slice.
  - Change the config directive from `EDITOR` to `IDE` because format compatibility is not required for this branch.

This makes the app taxonomy and command surface consistently Finder / IDE / Terminal.

## Decision Gates

- [x] IDE naming across command/config/directive
  - Impact: User-visible CLI output, `.workbranch.config` directive names, help text, and regression tests.
  - Current evidence: current source uses `EDITOR_COMMAND`, `EDITOR` directives, and `workbranch editor`; current tests assert `Opening editor:`. The user explicitly said config format compatibility is not required and approved using `IDE` everywhere if it is cleaner.
  - Recommended default: use `workbranch ide`, `workbranch config ide`, `IDE <command>` in `.workbranch.config`, and `Opening IDE:` in status output.
  - Recommended rationale: A single term eliminates translation between app taxonomy and config internals. It is a cleaner breaking change than carrying `editor`/`EDITOR` indefinitely while the product vocabulary is Finder / IDE / Terminal.
  - Status: resolved: use IDE everywhere; do not preserve the old `EDITOR` config directive in this plan.

## Target App Kinds

### Finder

No config preset is needed.

Commands:

```bash
workbranch finder <task>
workbranch finder <task> --repo <repo>
```

Behavior:

- With `--repo`, open that repo worktree path.
- Without `--repo`, open the task root folder, not each repo. Finder is a folder browser, so task-root is the useful default.
- macOS command: `open "$resolved_path"`.
- Linux future fallback: `xdg-open "$resolved_path"` when available.

### IDE

Use Superset's level-1 IDE list from the screenshot, excluding JetBrains submenu apps:

1. Cursor
2. Antigravity
3. Windsurf
4. Zed
5. Sublime Text
6. Xcode
7. VS Code
8. Custom command
9. Clear

Notes:

- Do not include JetBrains in this slice.
- Do not create VS Code or JetBrains submenus in this Bash CLI.
- Use `workbranch ide` as the command. Do not add or document `workbranch editor` in this slice.
- VS Code-like apps should keep the currently-fixed multi-window command shape:

```bash
open -na Cursor --args --new-window <repo-path>
open -na "Antigravity IDE" --args --new-window <repo-path>
open -na Windsurf --args --new-window <repo-path>
open -na "Visual Studio Code" --args --new-window <repo-path>
```

- Apps that do not share VS Code's `--new-window` CLI contract should use plain app opening until verified:

```bash
open -na Zed <repo-path>
open -na "Sublime Text" <repo-path>
open -na Xcode <repo-path>
```

IDE command normalization should cover old app command shapes such as `open -a Cursor` when they are stored under the new `IDE` directive.

### Terminal

Align the preset list with Superset terminal apps:

1. iTerm
2. Warp
3. Terminal.app
4. Ghostty
5. Custom command
6. Clear

Notes:

- Remove `cmux` from the preset menu because it is not an external terminal app in Superset's taxonomy.
- Existing configs containing `TERMINAL cmux` must keep working because raw configured commands remain supported.
- Terminal commands should continue to append the repo path as the final argument. Any terminal-specific resolver exception belongs in a separate follow-up plan because it changes app-specific launch semantics.

## Target Command Surface

User-facing commands:

```bash
workbranch finder <task> [--repo <repo>]     # new Finder/file-manager launcher
workbranch ide <task> [--repo <repo>]        # IDE launcher
workbranch terminal <task> [--repo <repo>]
workbranch path <task> [--repo <repo>]
workbranch config ide                        # IDE config command
workbranch config terminal
```

Help should show:

```text
Tool:
  path <task>       Print a task workspace path
  finder <task>     Open a task workspace in Finder
  ide <task>        Open task repo worktrees in the configured IDE
  terminal <task>   Open task repo worktrees in the configured terminal
```

Config help should show:

```text
Config:
  config            Create or update .workbranch.config without cloning repos
  config ide        Update only the configured IDE command
  config terminal   Update only the configured terminal command
  config --rewrite  Rewrite config to current format without prompts
```

## Files and Responsibilities

- Modify `src/workbranch/lib/tool-launcher.sh`
  - Add app-kind helpers and preset catalogs.
  - Render colored app names for IDE and Terminal presets.
  - Add Finder launcher helper.
  - Normalize legacy IDE app command shapes for the `ide` tool label.
  - Do not normalize the new Zed preset to `--new-window`; Zed remains `open -na Zed` until its CLI contract is verified.

- Modify `src/workbranch/globals.sh`
  - Rename `EDITOR_COMMAND` to `IDE_COMMAND`.

- Modify `src/workbranch/lib/config.sh`
  - Parse/write `IDE <command>` instead of `EDITOR <command>`.
  - Rename setter/clearer helpers from editor to ide.
  - Treat old `EDITOR` directives as invalid under this breaking plan.

- Modify `src/workbranch/commands/tool-launcher.sh`
  - Add `cmd_ide`.
  - Add `cmd_finder`.
  - Make Finder no-`--repo` open the task root path; IDE/Terminal no-`--repo` continue faning out per repo.

- Modify `src/workbranch/commands/config.sh`
  - Accept `config ide`.
  - Change prompt label from `Editor command:` to `IDE command:`.
  - Update IDE choice numbers to the target list.

- Modify `src/workbranch/commands/init.sh` and `src/workbranch/commands/list.sh`
  - Read/display `IDE_COMMAND` instead of `EDITOR_COMMAND`.

- Modify `src/workbranch/main.sh`
  - Dispatch `ide` and `finder`.

- Modify `src/workbranch/usage.sh`
  - Update Tool and Config help rows.

- Modify docs:
  - `README.md`
  - `README.ko.md`
  - `docs/specs/0001-workbranch-mvp.md`
  - This plan supersedes the stale tool-launcher preset examples in `docs/plans/0005-tool-launcher-and-path-commands.md`; do not edit old historical plan text unless explicitly requested.

- Modify tests:
  - `tests/cases/config.sh`
  - `tests/cases/tool-launcher.sh`
  - `tests/cases/meta.sh`
  - `tests/run.sh`

- Regenerate:
  - `bin/workbranch`

---

## Implementation Tasks

### Task 1: Lock the new IDE/Terminal preset menus with failing tests

**Files:**
- Modify: `tests/cases/config.sh`
- Modify: `tests/run.sh`

- [x] **Step 1: Add a failing test for the IDE preset order and prompt label**

Add this test to `tests/cases/config.sh`:

```bash
test_config_ide_preset_menu_uses_superset_level1_order() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  out=$(printf '\n' | run_expect_success "$WORKBRANCH" config ide)
  assert_contains "$out" "[*] IDE command:"
  assert_contains "$out" "1) Cursor (open -na Cursor --args --new-window)"
  assert_contains "$out" '2) Antigravity (open -na "Antigravity IDE" --args --new-window)'
  assert_contains "$out" "3) Windsurf (open -na Windsurf --args --new-window)"
  assert_contains "$out" "4) Zed (open -na Zed)"
  assert_contains "$out" '5) Sublime Text (open -na "Sublime Text")'
  assert_contains "$out" "6) Xcode (open -na Xcode)"
  assert_contains "$out" '7) VS Code (open -na "Visual Studio Code" --args --new-window)'
  assert_contains "$out" "8) Custom command"
  assert_contains "$out" "9) Clear"
  assert_contains "$out" "[*] Choose IDE [keep]:"
}
```

- [x] **Step 2: Add a failing test for colored IDE/Terminal names**

Add this test to `tests/cases/config.sh`:

```bash
test_config_app_preset_names_are_colored() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  out=$(printf '\n' | env -u NO_COLOR WORKBRANCH_COLOR=always "$WORKBRANCH" config ide 2>&1)
  assert_contains "$out" $'1) \033[0;36mCursor\033[0m (open -na Cursor --args --new-window)'
  assert_contains "$out" $'2) \033[0;36mAntigravity\033[0m (open -na "Antigravity IDE" --args --new-window)'
  assert_contains "$out" $'3) \033[0;36mWindsurf\033[0m (open -na Windsurf --args --new-window)'
  assert_contains "$out" $'4) \033[0;36mZed\033[0m (open -na Zed)'
  assert_contains "$out" $'5) \033[0;36mSublime Text\033[0m (open -na "Sublime Text")'
  assert_contains "$out" $'6) \033[0;36mXcode\033[0m (open -na Xcode)'
  assert_contains "$out" $'7) \033[0;36mVS Code\033[0m (open -na "Visual Studio Code" --args --new-window)'

  out=$(printf '\n' | env -u NO_COLOR WORKBRANCH_COLOR=always "$WORKBRANCH" config terminal 2>&1)
  assert_contains "$out" $'1) \033[0;36miTerm\033[0m (open -a iTerm)'
  assert_contains "$out" $'2) \033[0;36mWarp\033[0m (open -a Warp)'
  assert_contains "$out" $'3) \033[0;36mTerminal.app\033[0m (open -a Terminal)'
  assert_contains "$out" $'4) \033[0;36mGhostty\033[0m (open -a Ghostty)'
}
```

- [x] **Step 3: Add both tests to `tests/run.sh`**

Insert after the existing config editor preset tests:

```bash
  run_test test_config_ide_preset_menu_uses_superset_level1_order
  run_test test_config_app_preset_names_are_colored
```

- [x] **Step 4: Run tests to verify they fail**

Run:

```bash
REPO_ROOT="$PWD" WORKBRANCH="$PWD/bin/workbranch" /bin/bash <<'SCRIPT'
set -u
. "$REPO_ROOT/tests/lib/helpers.sh"
. "$REPO_ROOT/tests/cases/config.sh"
run_test test_config_ide_preset_menu_uses_superset_level1_order
run_test test_config_app_preset_names_are_colored
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -gt 0 ]
SCRIPT
```

Expected:

```text
PASS=0 FAIL=2
```

### Task 2: Implement IDE naming and Superset level-1 app presets

**Files:**
- Modify: `src/workbranch/lib/tool-launcher.sh`
- Modify: `src/workbranch/commands/config.sh`

- [x] **Step 1: Replace editor preset rendering with IDE preset rendering**

In `src/workbranch/lib/tool-launcher.sh`, keep `print_tool_preset`, then add/replace IDE preset rendering with:

```bash
print_ide_presets() {
  info "IDE command:"
  print_tool_preset 1 "Cursor" 'open -na Cursor --args --new-window'
  print_tool_preset 2 "Antigravity" 'open -na "Antigravity IDE" --args --new-window'
  print_tool_preset 3 "Windsurf" 'open -na Windsurf --args --new-window'
  print_tool_preset 4 "Zed" 'open -na Zed'
  print_tool_preset 5 "Sublime Text" 'open -na "Sublime Text"'
  print_tool_preset 6 "Xcode" 'open -na Xcode'
  print_tool_preset 7 "VS Code" 'open -na "Visual Studio Code" --args --new-window'
  printf '    8) Custom command\n' >&2
  printf '    9) Clear\n' >&2
}

```

- [x] **Step 2: Replace IDE preset command mapping**

In `src/workbranch/lib/tool-launcher.sh`, replace the old editor preset command helper with:

```bash
ide_preset_command() {
  case "$1" in
    1) printf '%s' 'open -na Cursor --args --new-window' ;;
    2) printf '%s' 'open -na "Antigravity IDE" --args --new-window' ;;
    3) printf '%s' 'open -na Windsurf --args --new-window' ;;
    4) printf '%s' 'open -na Zed' ;;
    5) printf '%s' 'open -na "Sublime Text"' ;;
    6) printf '%s' 'open -na Xcode' ;;
    7) printf '%s' 'open -na "Visual Studio Code" --args --new-window' ;;
    *) return 1 ;;
  esac
}
```

- [x] **Step 3: Update IDE legacy command normalization**

In `src/workbranch/lib/tool-launcher.sh`, update `run_tool_command` so the `ide` tool label normalizes legacy app command shapes, and remove the Zed normalization that would re-add `--new-window` to the new Zed preset:

```bash
run_tool_command() {
  tool_label=$1
  command=$2
  path=$3
  [ -n "$command" ] || die "$tool_label command is not configured; run workbranch config $tool_label"
  case "$tool_label" in
    ide)
      case "$command" in
        'open -a "Visual Studio Code"'|'open -na "Visual Studio Code"') command='open -na "Visual Studio Code" --args --new-window' ;;
        'open -a Cursor'|'open -na Cursor'|'open -a "Cursor"'|'open -na "Cursor"') command='open -na Cursor --args --new-window' ;;
        'open -a "Antigravity IDE"'|'open -na "Antigravity IDE"') command='open -na "Antigravity IDE" --args --new-window' ;;
        'open -a Windsurf'|'open -na Windsurf'|'open -a "Windsurf"'|'open -na "Windsurf"') command='open -na Windsurf --args --new-window' ;;
      esac
      ;;
  esac
  (
    cd "$path" || exit 1
    WORKBRANCH_TOOL_PATH=$path
    export WORKBRANCH_TOOL_PATH
    sh -c "$command \"\$WORKBRANCH_TOOL_PATH\""
  )
}
```

This is required for two behavior edges:

- `IDE open -a Cursor`-style configs should still launch a new IDE instance/window per repo.
- The new `Zed` preset must stay `open -na Zed <repo-path>` and must not be upgraded to `--args --new-window` at execution time.

- [x] **Step 4: Update terminal preset order**

In `src/workbranch/lib/tool-launcher.sh`, replace `print_terminal_presets` and `terminal_preset_command` with:

```bash
print_terminal_presets() {
  info "Terminal command:"
  print_tool_preset 1 "iTerm" 'open -a iTerm'
  print_tool_preset 2 "Warp" 'open -a Warp'
  print_tool_preset 3 "Terminal.app" 'open -a Terminal'
  print_tool_preset 4 "Ghostty" 'open -a Ghostty'
  printf '    5) Custom command\n' >&2
  printf '    6) Clear\n' >&2
}

terminal_preset_command() {
  case "$1" in
    1) printf '%s' 'open -a iTerm' ;;
    2) printf '%s' 'open -a Warp' ;;
    3) printf '%s' 'open -a Terminal' ;;
    4) printf '%s' 'open -a Ghostty' ;;
    *) return 1 ;;
  esac
}
```

- [x] **Step 5: Update config prompt dispatch**

In `src/workbranch/commands/config.sh`, replace `configure_editor_prompt` with `configure_ide_prompt`:

```bash
configure_ide_prompt() {
  print_ide_presets
  current=${IDE_COMMAND:-keep}
  value=$(prompt_read "[*] Choose IDE [$current]: ") || die "input aborted"
  case "$value" in
    "") ;;
    1|2|3|4|5|6|7) set_ide_command "$(ide_preset_command "$value")" ;;
    8)
      custom=$(prompt_required "Custom IDE command")
      set_ide_command "$custom"
      ;;
    9|--clear) clear_ide_command ;;
    *) die "invalid IDE choice: $value" ;;
  esac
}
```

Update `configure_terminal_prompt` numbering:

```bash
configure_terminal_prompt() {
  print_terminal_presets
  current=${TERMINAL_COMMAND:-keep}
  value=$(prompt_read "[*] Choose terminal [$current]: ") || die "input aborted"
  case "$value" in
    "") ;;
    1|2|3|4) set_terminal_command "$(terminal_preset_command "$value")" ;;
    5)
      custom=$(prompt_required "Custom terminal command")
      set_terminal_command "$custom"
      ;;
    6|--clear) clear_terminal_command ;;
    *) die "invalid terminal choice: $value" ;;
  esac
}
```

- [x] **Step 6: Rebuild and verify targeted tests pass**

Run:

```bash
scripts/build-workbranch.sh
REPO_ROOT="$PWD" WORKBRANCH="$PWD/bin/workbranch" /bin/bash <<'SCRIPT'
set -u
. "$REPO_ROOT/tests/lib/helpers.sh"
. "$REPO_ROOT/tests/cases/config.sh"
run_test test_config_ide_preset_menu_uses_superset_level1_order
run_test test_config_app_preset_names_are_colored
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
exit "$FAIL"
SCRIPT
```

Expected:

```text
PASS=2 FAIL=0
```

### Task 3: Replace editor command/config internals with IDE

**Files:**
- Modify: `src/workbranch/globals.sh`
- Modify: `src/workbranch/lib/config.sh`
- Modify: `src/workbranch/main.sh`
- Modify: `src/workbranch/commands/config.sh`
- Modify: `src/workbranch/commands/init.sh`
- Modify: `src/workbranch/commands/list.sh`
- Modify: `src/workbranch/commands/tool-launcher.sh`
- Modify: `tests/cases/tool-launcher.sh`
- Modify: `tests/cases/config.sh`

- [x] **Step 1: Update existing launcher tests from editor to ide**

In `tests/cases/tool-launcher.sh`, rename editor-focused tests to IDE-focused names and update commands/config directives:

```bash
# Example replacements in existing tests:
# EDITOR <command> -> IDE <command>
# "$WORKBRANCH" editor login -> "$WORKBRANCH" ide login
# "[*] Opening editor:" -> "[*] Opening IDE:"
```

Add this targeted test for the canonical `IDE` directive:

```bash
test_ide_launcher_uses_ide_directive() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  canonical_project=$(pwd -P)
  fake_tool="$TMP_ROOT/fake-tool.sh"
  append_fake_tool_script "$fake_tool"
  export WORKBRANCH_FAKE_TOOL_LOG="$TMP_ROOT/tool.log"

  cat >> "$project/.workbranch.config" <<CONFIG
IDE $fake_tool
CONFIG

  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '

' | run_expect_success "$WORKBRANCH" add login >/dev/null

  out=$(run_expect_success "$WORKBRANCH" ide login --repo frontend)
  assert_contains "$out" "[*] Opening IDE: login/frontend"
  assert_contains "$(cat "$WORKBRANCH_FAKE_TOOL_LOG")" "$canonical_project/login/frontend|$canonical_project/login/frontend"
}
```

- [x] **Step 2: Update config tests for `IDE` directive**

In `tests/cases/config.sh`, update editor/config tests to use `config ide` and assert the written directive is `IDE`, not `EDITOR`:

```bash
test_config_ide_writes_ide_directive() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  out=$(printf '%s
' "1" | run_expect_success "$WORKBRANCH" config ide)
  assert_contains "$out" "[*] IDE command:"
  assert_contains "$out" "[+] Config updated:"
  assert_contains "$(cat "$project/.workbranch.config")" "IDE open -na Cursor --args --new-window"
  assert_not_contains "$(cat "$project/.workbranch.config")" "EDITOR "
}
```

- [x] **Step 3: Rename config state from editor to ide**

In `src/workbranch/globals.sh`, replace:

```bash
EDITOR_COMMAND=""
```

with:

```bash
IDE_COMMAND=""
```

In `src/workbranch/lib/config.sh`, rename helpers and directive parsing/writing:

```bash
set_ide_command() {
  command=$1
  IDE_COMMAND=$command
}

clear_ide_command() {
  IDE_COMMAND=""
}
```

In `parse_config` and `parse_config_for_rewrite`, replace the `EDITOR)` case with:

```bash
IDE)
  [ -z "$IDE_COMMAND" ] || die "duplicate IDE directive in config"
  set_ide_command "$(task_setup_from_line "$line")"
  ;;
```

In `write_config`, replace `EDITOR` output with:

```bash
if [ -n "$IDE_COMMAND" ]; then
  printf 'IDE %s
' "$IDE_COMMAND"
fi
```

- [x] **Step 4: Implement `cmd_ide` as the only IDE launcher command**

In `src/workbranch/commands/tool-launcher.sh`, select `IDE_COMMAND` for the `ide` label:

```bash
case "$tool_label" in
  ide) command=$IDE_COMMAND ;;
  terminal) command=$TERMINAL_COMMAND ;;
  *) die "unknown tool launcher: $tool_label" ;;
esac
```

Use `IDE` for display in both `info_tool_opening` calls:

```bash
display_label=$tool_label
case "$tool_label" in
  ide) display_label="IDE" ;;
esac
```

and:

```bash
info_tool_opening "$display_label" "$task/$FILTER_REPO"
info_tool_opening "$display_label" "$task/$name"
```

Add:

```bash
cmd_ide() {
  cmd_tool_launcher ide "$@"
}
```

- [x] **Step 5: Dispatch `ide` and remove public `editor` dispatch**

In `src/workbranch/main.sh`, dispatch `ide`:

```bash
ide) cmd_ide "$@" ;;
```

Do not add `editor)` dispatch in this plan.

- [x] **Step 6: Update config/init/list call sites**

In `src/workbranch/commands/config.sh`, accept only `ide` for the IDE config target:

```bash
ide) config_target="ide" ;;
*) die "usage: workbranch config [ide|terminal|--rewrite]" ;;
```

Dispatch:

```bash
ide) configure_ide_prompt ;;
```

In `src/workbranch/commands/init.sh`, call `configure_ide_prompt` and display `IDE_COMMAND`.

In `src/workbranch/commands/list.sh`, display `IDE_COMMAND` wherever the configured IDE command is shown.

- [x] **Step 7: Rebuild and verify IDE directive tests**

Run:

```bash
scripts/build-workbranch.sh
REPO_ROOT="$PWD" WORKBRANCH="$PWD/bin/workbranch" /bin/bash <<'SCRIPT'
set -u
. "$REPO_ROOT/tests/lib/helpers.sh"
. "$REPO_ROOT/tests/cases/tool-launcher.sh"
. "$REPO_ROOT/tests/cases/config.sh"
run_test test_ide_launcher_uses_ide_directive
run_test test_config_ide_writes_ide_directive
printf 'PASS=%s FAIL=%s
' "$PASS" "$FAIL"
exit "$FAIL"
SCRIPT
```

Expected:

```text
PASS=2 FAIL=0
```

### Task 4: Add Finder launcher

**Files:**
- Modify: `src/workbranch/lib/tool-launcher.sh`
- Modify: `src/workbranch/commands/tool-launcher.sh`
- Modify: `src/workbranch/main.sh`
- Modify: `tests/cases/tool-launcher.sh`
- Modify: `tests/run.sh`

- [x] **Step 1: Add failing Finder tests**

Add to `tests/cases/tool-launcher.sh`:

```bash
test_finder_opens_task_root_without_repo_filter() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  canonical_project=$(pwd -P)
  fake_bin="$TMP_ROOT/bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/open" <<'SCRIPT'
#!/usr/bin/env sh
set -eu
printf '%s|%s\n' "$PWD" "$*" >> "$WORKBRANCH_FAKE_TOOL_LOG"
SCRIPT
  chmod +x "$fake_bin/open"
  export WORKBRANCH_FAKE_TOOL_LOG="$TMP_ROOT/finder.log"

  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '\n\n' | run_expect_success "$WORKBRANCH" add login >/dev/null

  out=$(PATH="$fake_bin:$PATH" run_expect_success "$WORKBRANCH" finder login)
  assert_contains "$out" "[*] Opening Finder: login"
  assert_contains "$(cat "$WORKBRANCH_FAKE_TOOL_LOG")" "$canonical_project/login|$canonical_project/login"
  assert_not_contains "$(cat "$WORKBRANCH_FAKE_TOOL_LOG")" "$canonical_project/login/frontend"
  assert_not_contains "$(cat "$WORKBRANCH_FAKE_TOOL_LOG")" "$canonical_project/login/backend"
}

test_finder_repo_filter_opens_one_repo_path() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  canonical_project=$(pwd -P)
  fake_bin="$TMP_ROOT/bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/open" <<'SCRIPT'
#!/usr/bin/env sh
set -eu
printf '%s|%s\n' "$PWD" "$*" >> "$WORKBRANCH_FAKE_TOOL_LOG"
SCRIPT
  chmod +x "$fake_bin/open"
  export WORKBRANCH_FAKE_TOOL_LOG="$TMP_ROOT/finder.log"

  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '\n\n' | run_expect_success "$WORKBRANCH" add login >/dev/null

  out=$(PATH="$fake_bin:$PATH" run_expect_success "$WORKBRANCH" finder login --repo frontend)
  assert_contains "$out" "[*] Opening Finder: login/frontend"
  assert_contains "$(cat "$WORKBRANCH_FAKE_TOOL_LOG")" "$canonical_project/login/frontend|$canonical_project/login/frontend"
  assert_not_contains "$(cat "$WORKBRANCH_FAKE_TOOL_LOG")" "$canonical_project/login/backend"
}
```

Register both in `tests/run.sh`.

- [x] **Step 2: Implement Finder launch helper**

In `src/workbranch/lib/tool-launcher.sh`, add:

```bash
run_finder_command() {
  path=$1
  (
    # The cwd is observable in tests via the fake `open` command; real
    # `open`/`xdg-open` receive the absolute path and do not depend on cwd.
    cd "$path" || exit 1
    case "$(uname -s)" in
      Darwin) open "$path" ;;
      Linux)
        if command -v xdg-open >/dev/null 2>&1; then
          xdg-open "$path"
        else
          die "finder command is not available on this platform"
        fi
        ;;
      *) die "finder command is not available on this platform" ;;
    esac
  )
}
```

Because `die` exits from a subshell in this helper, the caller still needs to wrap failure:

```bash
run_finder_command "$path" || die "failed to open Finder: $target_label"
```

- [x] **Step 3: Implement `cmd_finder`**

In `src/workbranch/commands/tool-launcher.sh`, add:

```bash
cmd_finder() {
  require_project
  parse_repo_option "$@"
  [ ${#ARGS[@]} -eq 1 ] || die "usage: workbranch finder <task> [--repo <repo>]"
  task=${ARGS[0]}
  validate_safe_name "task" "$task"

  if [ -n "$FILTER_REPO" ]; then
    resolve_task_repo_path "$task" "$FILTER_REPO"
    path=$RESOLVED_PATH
    info_tool_opening "Finder" "$task/$FILTER_REPO"
    run_finder_command "$path" || die "failed to open Finder: $task/$FILTER_REPO"
    return 0
  fi

  resolve_task_path "$task"
  path=$RESOLVED_PATH
  info_tool_opening "Finder" "$task"
  run_finder_command "$path" || die "failed to open Finder: $task"
}
```

- [x] **Step 4: Dispatch `finder` in main**

In `src/workbranch/main.sh`, add:

```bash
finder) cmd_finder "$@" ;;
```

- [x] **Step 5: Rebuild and verify Finder tests**

Run:

```bash
scripts/build-workbranch.sh
REPO_ROOT="$PWD" WORKBRANCH="$PWD/bin/workbranch" /bin/bash <<'SCRIPT'
set -u
. "$REPO_ROOT/tests/lib/helpers.sh"
. "$REPO_ROOT/tests/cases/tool-launcher.sh"
run_test test_finder_opens_task_root_without_repo_filter
run_test test_finder_repo_filter_opens_one_repo_path
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
exit "$FAIL"
SCRIPT
```

Expected:

```text
PASS=2 FAIL=0
```

### Task 5: Update help/docs/specs

**Files:**
- Modify: `src/workbranch/usage.sh`
- Modify: `tests/cases/meta.sh`
- Modify: `README.md`
- Modify: `README.ko.md`
- Modify: `docs/specs/0001-workbranch-mvp.md`

- [x] **Step 1: Add failing help tests**

Update `tests/cases/meta.sh:test_help_groups_commands` to assert:

```bash
assert_contains "$out" "finder <task>     Open a task workspace in Finder"
assert_contains "$out" "ide <task>        Open task repo worktrees in the configured IDE"
assert_contains "$out" "config ide        Update only the configured IDE command"
```

Also update the ordering glob in the same test. The test has a large `case`
pattern that enforces group order; update the Tool and Config fragments there
at the same time, otherwise the individual assertions can pass while the order
check still fails:

```bash
case "$out" in
  *"Workspace:"*"init              Initialize a workbranch project"*"list              List configured repos and task workspaces"*"add <task>        Create a task workspace"*"remove <task>     Remove task worktrees and local task branches"*"Git:"*"status            Show commits, diff, and dirty state"*"  vertical"*"Tool:"*"path <task>       Print a task workspace path"*"finder <task>     Open a task workspace in Finder"*"ide <task>        Open task repo worktrees in the configured IDE"*"terminal <task>   Open task repo worktrees in the configured terminal"*"Config:"*"config            Create or update .workbranch.config without cloning repos"*"config ide        Update only the configured IDE command"*"config terminal   Update only the configured terminal command"*"config --rewrite  Rewrite config to current format without prompts"*"Other:"*) ;;
  *) fail "expected workspace, git, tool, config, and other group ordering; got: $out" ;;
esac
```

- [x] **Step 2: Update usage help**

In `src/workbranch/usage.sh`, update plain and enhanced Tool rows:

```bash
  path <task>       Print a task workspace path
  finder <task>     Open a task workspace in Finder
  ide <task>        Open task repo worktrees in the configured IDE
  terminal <task>   Open task repo worktrees in the configured terminal
```

Update Config rows:

```bash
  config ide        Update only the configured IDE command
```

- [x] **Step 3: Update README and spec**

In `README.md`, add examples:

```bash
workbranch finder login
workbranch finder login --repo frontend
workbranch ide login
workbranch terminal login
```

Mention in the launcher/config docs that the IDE config directive is now `IDE`, not `EDITOR`, and that the interactive IDE preset numbers changed to match the Superset-inspired order.

In `docs/specs/0001-workbranch-mvp.md`, update the tool launcher section:

```markdown
### `workbranch finder <task>` / `workbranch ide <task>` / `workbranch terminal <task>`

`finder` opens the task root folder by default and one repo folder with `--repo <repo>`.
`ide` and `terminal` run the configured command once per matching task repo worktree.
The IDE config directive is `IDE <command>`.
Tool launchers do not modify repositories.
```

- [x] **Step 4: Rebuild and verify help tests**

Run:

```bash
scripts/build-workbranch.sh
REPO_ROOT="$PWD" WORKBRANCH="$PWD/bin/workbranch" /bin/bash <<'SCRIPT'
set -u
. "$REPO_ROOT/tests/lib/helpers.sh"
. "$REPO_ROOT/tests/cases/meta.sh"
run_test test_help_groups_commands
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
exit "$FAIL"
SCRIPT
```

Expected:

```text
PASS=1 FAIL=0
```

### Task 6: Full verification and installed-binary smoke

**Files:**
- Regenerate: `bin/workbranch`

- [x] **Step 1: Run syntax checks**

Run:

```bash
/bin/bash -n bin/workbranch install.sh tests/run.sh src/workbranch/lib/tool-launcher.sh src/workbranch/commands/tool-launcher.sh src/workbranch/commands/config.sh src/workbranch/usage.sh
```

Expected: exit 0.

- [x] **Step 2: Run full integration suite**

Run:

```bash
./tests/run.sh
```

Expected final line:

```text
Tests passed: <current count>
```

The count must increase by the new tests added in this plan. No failures are acceptable.

- [x] **Step 3: Run diff checks**

Run:

```bash
git diff --check
git diff --cached --check
```

Expected: exit 0.

- [x] **Step 4: Install local binary and smoke-test the actual user surface**

Run:

```bash
install -m 0755 bin/workbranch "$HOME/.local/bin/workbranch"
~/.local/bin/workbranch version
```

Then run a deterministic menu smoke in a fixture:

```bash
REPO_ROOT="$PWD" WORKBRANCH="$HOME/.local/bin/workbranch" /bin/bash <<'SCRIPT'
set -u
. "$REPO_ROOT/tests/lib/helpers.sh"
new_fixture
cd "$FIXTURE_PROJECT" || exit 1
printf '\n' | env -u NO_COLOR WORKBRANCH_COLOR=always "$WORKBRANCH" config ide 2>&1 | sed -n '1,12p' | cat -v
printf '\n' | env -u NO_COLOR WORKBRANCH_COLOR=always "$WORKBRANCH" config terminal 2>&1 | sed -n '1,10p' | cat -v
SCRIPT
```

Expected installed output includes colored app names and these rows:

```text
1) Cursor
2) Antigravity
3) Windsurf
4) Zed
5) Sublime Text
6) Xcode
7) VS Code
```

- [x] **Step 5: Smoke-test Finder with fake `open`**

Run:

```bash
tmp=$(mktemp -d)
cat > "$tmp/open" <<'SCRIPT'
#!/usr/bin/env sh
set -eu
printf '%s|%s\n' "$PWD" "$*" >> "$WORKBRANCH_FAKE_TOOL_LOG"
SCRIPT
chmod +x "$tmp/open"
REPO_ROOT="$PWD" WORKBRANCH="$HOME/.local/bin/workbranch" PATH="$tmp:$PATH" /bin/bash <<'SCRIPT'
set -u
. "$REPO_ROOT/tests/lib/helpers.sh"
. "$REPO_ROOT/tests/cases/tool-launcher.sh"
run_test test_finder_opens_task_root_without_repo_filter
run_test test_finder_repo_filter_opens_one_repo_path
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
exit "$FAIL"
SCRIPT
```

Expected:

```text
PASS=2 FAIL=0
```

---

## Deferred / Explicitly Out of Scope

- JetBrains presets and submenus.
- VS Code Insiders submenu.
- Persisting an app id separate from raw command text.
- Replacing `.workbranch.config` `IDE` / `TERMINAL` directives with structured app ids.
- Linux-specific IDE resolver in this slice. Track Superset's Linux mappings in a separate follow-up plan; the current user-reported issue is macOS launcher UX.
- Reintroducing `workbranch editor` as a compatibility alias.

## Acceptance Criteria

- `workbranch config ide` writes the `IDE` directive and does not write `EDITOR`.
- Config prompt displays `IDE command:` and colored preset app names when color is enabled.
- IDE presets use the target Superset-inspired level-1 order and exclude JetBrains.
- Terminal presets align to Superset terminal apps: iTerm, Warp, Terminal.app, Ghostty.
- `workbranch finder <task>` opens the task root; `workbranch finder <task> --repo <repo>` opens one repo path.
- `workbranch ide <task>` fans out across task repos; `--repo` narrows to one repo.
- `bin/workbranch` is regenerated from source, not hand-edited.
- Full suite passes and installed `~/.local/bin/workbranch` smoke confirms the user-facing menus.


## Execution Evidence

- Completed mode: `plan-execute auto`.
- Red check: targeted IDE/Finder/config tests failed against the pre-change `bin/workbranch` because `ide`, `finder`, and `IDE` directives were not implemented.
- Targeted green check: targeted IDE/Finder/config tests passed after source changes and `scripts/build-workbranch.sh`.
- Syntax/build: `/bin/bash -n bin/workbranch install.sh tests/run.sh tests/cases/*.sh src/workbranch/*.sh src/workbranch/lib/*.sh src/workbranch/commands/*.sh` passed; `scripts/build-workbranch.sh` passed.
- Full suite: `./tests/run.sh` passed with `Tests passed: 116`.
- Installed smoke: installed `bin/workbranch` to `$HOME/.local/bin/workbranch`; `~/.local/bin/workbranch version` reported `workbranch 1.0.0`.
- Installed menu smoke: `WORKBRANCH_COLOR=always ~/.local/bin/workbranch config ide` showed colored IDE preset names in Cursor, Antigravity, Windsurf, Zed, Sublime Text, Xcode, VS Code order.
- Installed Finder smoke: `test_finder_opens_task_root_without_repo_filter` and `test_finder_repo_filter_opens_one_repo_path` passed against `$HOME/.local/bin/workbranch` with fake `open`.
- Diff hygiene: `git diff --check` passed.
