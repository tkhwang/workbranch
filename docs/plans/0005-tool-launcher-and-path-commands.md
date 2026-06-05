# Tool Launcher and Path Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Use `superpowers:test-driven-development` before behavior changes. Do not commit automatically; stop with a diff and verification summary unless the user explicitly asks for git history changes.

**Goal:** Add project-level editor/terminal launch commands and a scriptable path command so users do not have to manually locate task worktree repo paths.

**Architecture:** Store one common editor command and one common terminal command in `.workbranch.config`; most users choose from macOS app presets, while advanced users can enter a custom command. Add shared tool/path helpers that resolve `task` plus optional `--repo` to canonical paths, then wire `workbranch editor`, `workbranch terminal`, and `workbranch path` through the existing command dispatcher and generated single-file build.

**Tech Stack:** Portable Bash, Git worktree, line-oriented `.workbranch.config`, generated `bin/workbranch`, existing `tests/run.sh` integration suite, macOS `open -a` presets with custom command fallback.

---

## Decisions

## Decision Gates

- [x] New launcher/path module placement
  - Impact: generated source surface, command boundary, future maintenance
  - Current evidence: `scripts/workbranch-sources.txt` lists command files directly; `path` has stdout-only semantics distinct from editor/terminal launchers.
  - Status: resolved: use `src/workbranch/lib/tool-launcher.sh`, `src/workbranch/commands/tool-launcher.sh`, and `src/workbranch/commands/path.sh`.

- [x] Config directive names
  - Impact: public `.workbranch.config` format and manual-edit UX
  - Current evidence: existing config uses uppercase compact directives such as `PROJECT_NAME`, `BRANCH_PREFIX`, `TASK_SETUP`, and `REPO_SETUP`; config is not a shell script.
  - Status: resolved: use `EDITOR` and `TERMINAL`, not prefixed names such as `TOOL_EDITOR` or `WORKBRANCH_EDITOR`.

- [x] Command namespace
  - Impact: public CLI command surface and help/docs/tests
  - Current evidence: existing commands use direct verbs such as `add`, `resume`, `status`, and `path`; the user chose the shorter frequent-use form over `workbranch tool ...`.
  - Status: resolved: expose direct commands `workbranch editor <task>` and `workbranch terminal <task>`; do not add `workbranch tool editor|terminal` in this slice.

- [x] Interactive init tool prompt position
  - Impact: interactive input order, docs, and tests
  - Current evidence: `cmd_init_interactive` currently asks base/project settings first, then repositories, then task setup; user prefers editor/terminal after base settings.
  - Status: resolved: ask editor/terminal after `Branch prefix` and before `Repositories`, so base/project settings are settled before tool settings.

- [x] Multi-repo launcher fanout
  - Impact: public launcher semantics, test strategy, terminal/editor behavior
  - Current evidence: the requested UX says the command runs in every repo inside the task; `--repo` limits the same operation to one repo.
  - Status: resolved: run the configured command once per matching repo path (`task/repo`), not once with all repo paths as arguments.

- Use **project-wide common commands**, not per-repo tool settings.
- Keep config human-editable and compact:

```text
EDITOR open -a "Visual Studio Code"
TERMINAL open -a Warp
```

- Presets should prefer macOS app launches over editor CLIs because many VS Code/Cursor users have not installed `code` or `cursor` shell commands.
- Custom commands remain supported for users who prefer CLIs such as `code`, `cursor`, `cmux`, or full paths such as `/opt/homebrew/bin/code`.
- `workbranch path` prints only paths to stdout so it can be used in shell substitution.
- Tool commands append the resolved path as the final argument to the configured command.
- Tool launchers run serially across repos. Non-blocking macOS `open -a ...` commands work well for all repos; blocking terminal/TUI commands such as raw `cmux` should usually be used with `--repo` or wrapped in a non-blocking custom command. Document this rather than adding background execution in the first version, because backgrounding arbitrary custom commands can hide failures.

## Target UX

```bash
workbranch editor task1
workbranch editor task1 --repo frontend
workbranch terminal task1
workbranch terminal task1 --repo frontend
workbranch path task1
workbranch path task1 --repo frontend
workbranch config
workbranch config editor
workbranch config terminal
```

### Tool presets

Editor menu:

```text
Editor command:
  1) VS Code (open -a "Visual Studio Code")
  2) Cursor (open -a Cursor)
  3) Antigravity IDE (open -a "Antigravity IDE")
  4) Custom command
  5) Clear
Choose editor [current-or-keep]:
```

Terminal menu:

```text
Terminal command:
  1) Terminal.app (open -a Terminal)
  2) iTerm2 (open -a iTerm)
  3) Warp (open -a Warp)
  4) Ghostty (open -a Ghostty)
  5) cmux (cmux)
  6) Custom command
  7) Clear
Choose terminal [current-or-keep]:
```

For a new config with no current value, display `[keep]` and treat Enter as no configured command. For an existing config, display the current command in brackets and let Enter keep it.

## File Map

- Modify: `src/workbranch/globals.sh`
  - Add `EDITOR_COMMAND` and `TERMINAL_COMMAND` globals.
- Modify: `src/workbranch/lib/config.sh`
  - Parse, rewrite, validate, clear, and write `EDITOR` / `TERMINAL` directives.
- Modify: `src/workbranch/commands/config.sh`
  - Add tool preset prompts to full config flow.
  - Add targeted `workbranch config editor` and `workbranch config terminal` flows.
- Create: `src/workbranch/lib/tool-launcher.sh`
  - Hold preset menu helpers, path resolution helpers, and command execution helper.
- Create: `src/workbranch/commands/tool-launcher.sh`
  - Implement `cmd_editor` and `cmd_terminal`.
- Create: `src/workbranch/commands/path.sh`
  - Implement `cmd_path` and keep stdout path-only.
- Modify: `src/workbranch/main.sh`
  - Dispatch `editor`, `terminal`, and `path` commands.
- Modify: `src/workbranch/usage.sh`
  - Document new commands and config variants.
- Modify: `scripts/workbranch-sources.txt`
  - Include new source files before `main.sh`.
- Modify: `tests/run.sh`
  - Add integration tests for config parsing/writing, targeted config, path output, tool execution, missing config errors, and help text.
- Modify: `README.md`, `README.ko.md`, `docs/specs/0001-workbranch-mvp.md`, `docs/architecture.md`
  - Document the feature and config directives.
- Regenerate: `bin/workbranch`
  - Run `scripts/build-workbranch.sh`; never edit this file directly.

---

## Task 1: Add failing tests for path and tool launcher behavior

**Files:**
- Modify: `tests/run.sh`

- [x] **Step 1: Add test helpers for fake tool commands**

Add these helpers near the other helper functions in `tests/run.sh`:

```bash
append_fake_tool_script() {
  script=$1
  cat > "$script" <<'SCRIPT'
#!/usr/bin/env sh
set -eu
printf '%s\n' "$PWD|$1" >> "$WORKBRANCH_FAKE_TOOL_LOG"
SCRIPT
  chmod +x "$script"
}
```

- [x] **Step 2: Add a path command test**

Add this test near the existing workspace command tests:

```bash
test_path_prints_task_and_repo_paths() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  canonical_project=$(pwd -P)
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  out=$(run_expect_success "$WORKBRANCH" path login)
  [ "$out" = "$canonical_project/login" ] || fail "expected task path, got: $out"

  out=$(run_expect_success "$WORKBRANCH" path login --repo frontend)
  [ "$out" = "$canonical_project/login/frontend" ] || fail "expected frontend path, got: $out"

  out=$(run_expect_fail "$WORKBRANCH" path missing)
  assert_contains "$out" "task workspace not found: missing"

  out=$(run_expect_fail "$WORKBRANCH" path login --repo unknown)
  assert_contains "$out" "unknown repo: unknown"
}
```

- [x] **Step 3: Add a tool command execution test**

Add this test after the path command test:

```bash
test_editor_and_terminal_run_configured_command_for_task_repos() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  canonical_project=$(pwd -P)
  fake_tool="$TMP_ROOT/fake-tool.sh"
  append_fake_tool_script "$fake_tool"
  export WORKBRANCH_FAKE_TOOL_LOG="$TMP_ROOT/tool.log"

  cat >> "$project/.workbranch.config" <<CONFIG
EDITOR $fake_tool
TERMINAL $fake_tool
CONFIG

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  out=$(run_expect_success "$WORKBRANCH" editor login --repo frontend)
  assert_contains "$out" "[*] Opening editor: login/frontend"
  assert_contains "$(cat "$WORKBRANCH_FAKE_TOOL_LOG")" "$canonical_project/login/frontend|$canonical_project/login/frontend"

  : > "$WORKBRANCH_FAKE_TOOL_LOG"
  out=$(run_expect_success "$WORKBRANCH" terminal login)
  assert_contains "$out" "[*] Opening terminal: login/frontend"
  assert_contains "$out" "[*] Opening terminal: login/backend"
  assert_contains "$(cat "$WORKBRANCH_FAKE_TOOL_LOG")" "$canonical_project/login/frontend|$canonical_project/login/frontend"
  assert_contains "$(cat "$WORKBRANCH_FAKE_TOOL_LOG")" "$canonical_project/login/backend|$canonical_project/login/backend"
}
```

This expected log assumes the implementation runs the command from the repo directory and passes the same repo path as argument.

- [x] **Step 4: Add missing tool config errors**

Add this test near the tool command execution test:

```bash
test_tool_commands_require_configured_command() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" editor login)
  assert_contains "$out" "editor command is not configured; run workbranch config editor"

  out=$(run_expect_fail "$WORKBRANCH" terminal login --repo frontend)
  assert_contains "$out" "terminal command is not configured; run workbranch config terminal"
}
```

- [x] **Step 5: Add missing task repo launcher error coverage**

Add this test near the missing tool config test. It prevents helper errors from being swallowed by command substitution and misreported as `failed to open`:

```bash
test_tool_launcher_reports_missing_task_repo_before_running_command() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  fake_tool="$TMP_ROOT/fake-tool.sh"
  append_fake_tool_script "$fake_tool"
  export WORKBRANCH_FAKE_TOOL_LOG="$TMP_ROOT/tool.log"

  cat >> "$project/.workbranch.config" <<CONFIG
EDITOR $fake_tool
CONFIG

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  rm -rf "$project/login/frontend"

  out=$(run_expect_fail "$WORKBRANCH" editor login --repo frontend)
  assert_contains "$out" "task repo not found: login/frontend"
  assert_not_exists "$WORKBRANCH_FAKE_TOOL_LOG"
}
```

- [x] **Step 6: Add config persistence tests**

Add this test near the existing config tests:

```bash
test_config_reads_and_writes_editor_terminal_commands() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  cat >> "$project/.workbranch.config" <<'CONFIG'
EDITOR open -a "Visual Studio Code"
TERMINAL open -a Warp
CONFIG

  out=$(run_expect_success "$WORKBRANCH" config --rewrite)
  assert_contains "$out" "[+] Config rewritten:"
  config=$(cat "$project/.workbranch.config")
  assert_contains "$config" "EDITOR open -a \"Visual Studio Code\""
  assert_contains "$config" "TERMINAL open -a Warp"
}
```

- [x] **Step 7: Add targeted config tests**

Add these tests near the existing config prompt tests:

```bash
test_config_editor_can_set_custom_command_without_prompting_repos() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  input=$(printf '%s\n%s\n' "4" "code --reuse-window")
  out=$(printf '%s' "$input" | run_expect_success "$WORKBRANCH" config editor)
  assert_contains "$out" "[*] Editor command:"
  assert_not_contains "$out" "Base repo branch for frontend"
  assert_contains "$out" "[+] Config updated:"
  assert_contains "$(cat "$project/.workbranch.config")" "EDITOR code --reuse-window"
}

test_config_terminal_can_clear_without_removing_editor() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  cat >> "$project/.workbranch.config" <<'CONFIG'
EDITOR open -a Cursor
TERMINAL open -a Warp
CONFIG

  out=$(printf '%s\n' "7" | run_expect_success "$WORKBRANCH" config terminal)
  assert_contains "$out" "[*] Terminal command:"
  assert_contains "$out" "[+] Config updated:"
  config=$(cat "$project/.workbranch.config")
  assert_contains "$config" "EDITOR open -a Cursor"
  assert_not_contains "$config" "TERMINAL open -a Warp"
}
```

- [x] **Step 8: Update every interactive config/init input vector for the two new prompts**

The existing `workbranch config` and `workbranch init` tests provide newline-delimited input. Any test that reaches beyond `Branch prefix` must insert two blank answers immediately after the `Branch prefix` answer, so Enter means no editor and no terminal command. Do this in the same test patch that adds the new tests; otherwise existing tests will fail by shifting later answers into the wrong prompts.

Affected full `workbranch config` tests that must insert two blank answers after the branch prefix input:

- `test_config_writes_config_without_cloning`
- `test_config_preserves_task_setup_while_prompting_repo_setup`
- `test_config_can_change_branch_prefix_without_cloning`
- `test_config_guides_base_branch_change_for_cloned_repo`
- `test_repo_setup_can_be_configured_and_run_per_repo`
- `test_repo_setup_can_be_cleared_without_removing_other_repo_setup`

Affected interactive `workbranch init` tests that must insert two blank answers after the branch prefix input:

- `test_interactive_init_writes_config_and_clones`
- `test_interactive_init_can_cancel_before_creating_project`
- `test_interactive_init_can_create_project_in_custom_target_directory`
- `test_interactive_init_accepts_slash_repo_base_branch`

Do not change these early-failure tests for the new prompts because they die before the editor/terminal prompts are reached:

- `test_config_rejects_branch_prefix_change_when_task_workspaces_exist`
- `test_config_rejects_branch_prefix_change_when_stale_task_directory_exists`
- `test_config_rejects_main_worktrees_dir_change_when_base_worktrees_exist`
- `test_interactive_init_rejects_slash_in_main_worktrees_directory`

Check `test_interactive_init_eof_aborts_required_prompt` after implementation. With editor/terminal prompts after `Branch prefix`, EOF will occur at `Choose editor`, not `Repository name`; the current assertion only checks `input aborted`, so it should still be valid.

For init/config flows that create a new project, preserve the initial `Press Enter to continue` and `Target directory` answers. Example:

```bash
# Before: press enter, target dir, project, base dir, branch prefix, first repo name

.
fullstack
_base
feature
frontend

# After: press enter, target dir, project, base dir, branch prefix, editor, terminal, first repo name

.
fullstack
_base
feature


frontend
```

For existing-project `workbranch config`, update assertions in `test_config_preserves_task_setup_while_prompting_repo_setup` to expect the editor and terminal prompts between `Branch prefix` and `Repositories`.

- [x] **Step 9: Run tests to confirm failure before implementation**

Run:

```bash
./tests/run.sh
```

Expected: the new tests fail with unknown commands, unknown config directives, missing prompts, or stale generated output. Existing unrelated tests may also fail until interactive input expectations are updated in the same test patch.

---

## Task 2: Extend config state for editor and terminal commands

**Files:**
- Modify: `src/workbranch/globals.sh`
- Modify: `src/workbranch/lib/config.sh`

- [x] **Step 1: Add globals**

In `src/workbranch/globals.sh`, add these after `TASK_SETUP`:

```bash
EDITOR_COMMAND=""
TERMINAL_COMMAND=""
```

- [x] **Step 2: Add accessors and mutators**

In `src/workbranch/lib/config.sh`, reuse the existing one-directive-tail parser for `EDITOR` and `TERMINAL`; do not duplicate the same `sed` body under another name. Add these near the setup command helpers:

```bash
set_editor_command() {
  command=$1
  [ -n "$command" ] || die "editor command is empty"
  EDITOR_COMMAND=$command
}

clear_editor_command() {
  EDITOR_COMMAND=""
}

set_terminal_command() {
  command=$1
  [ -n "$command" ] || die "terminal command is empty"
  TERMINAL_COMMAND=$command
}

clear_terminal_command() {
  TERMINAL_COMMAND=""
}
```

- [x] **Step 3: Reset command globals**

Update `reset_config()`:

```bash
reset_config() {
  PROJECT_NAME=""
  BASE_DIR=""
  BRANCH_PREFIX=""
  TASK_SETUP=""
  EDITOR_COMMAND=""
  TERMINAL_COMMAND=""
  REPO_NAMES=()
  REPO_URLS=()
  REPO_BASE_BRANCHES=()
  REPO_SETUP_COMMANDS=()
}
```

- [x] **Step 4: Parse strict config directives**

In `parse_config()`, add cases before `TASK_SETUP`:

```bash
      EDITOR)
        [ -z "$EDITOR_COMMAND" ] || die "duplicate EDITOR directive in config"
        set_editor_command "$(task_setup_from_line "$line")"
        ;;
      TERMINAL)
        [ -z "$TERMINAL_COMMAND" ] || die "duplicate TERMINAL directive in config"
        set_terminal_command "$(task_setup_from_line "$line")"
        ;;
```

- [x] **Step 5: Parse rewrite-compatible directives**

In `parse_config_for_rewrite()`, add cases before `TASK_SETUP|task_setup`:

```bash
      EDITOR|editor)
        [ -z "$EDITOR_COMMAND" ] || die "duplicate EDITOR directive in config"
        set_editor_command "$(task_setup_from_line "$line")"
        ;;
      TERMINAL|terminal)
        [ -z "$TERMINAL_COMMAND" ] || die "duplicate TERMINAL directive in config"
        set_terminal_command "$(task_setup_from_line "$line")"
        ;;
```

- [x] **Step 6: Write directives in stable order**

In `write_config()`, print configured tool commands after `BRANCH_PREFIX` and before `TASK_SETUP`:

```bash
    printf 'BRANCH_PREFIX %s\n' "$BRANCH_PREFIX"
    if [ -n "$EDITOR_COMMAND" ]; then
      printf 'EDITOR %s\n' "$EDITOR_COMMAND"
    fi
    if [ -n "$TERMINAL_COMMAND" ]; then
      printf 'TERMINAL %s\n' "$TERMINAL_COMMAND"
    fi
    if [ -n "$TASK_SETUP" ]; then
      printf 'TASK_SETUP %s\n' "$TASK_SETUP"
    fi
```

- [x] **Step 7: Run targeted syntax and tests**

Run:

```bash
/bin/bash -n src/workbranch/globals.sh src/workbranch/lib/config.sh tests/run.sh
./scripts/build-workbranch.sh
./tests/run.sh
```

Expected at this point: config persistence tests pass; command tests still fail until commands are implemented.

---

## Task 3: Add preset prompts and targeted config flows

**Files:**
- Create: `src/workbranch/lib/tool-launcher.sh`
- Modify: `src/workbranch/commands/config.sh`
- Modify: `scripts/workbranch-sources.txt`

- [x] **Step 1: Add tool prompt helpers**

Create `src/workbranch/lib/tool-launcher.sh`:

```bash
print_editor_presets() {
  info "Editor command:"
  printf '    1) VS Code (open -a "Visual Studio Code")\n' >&2
  printf '    2) Cursor (open -a Cursor)\n' >&2
  printf '    3) Antigravity IDE (open -a "Antigravity IDE")\n' >&2
  printf '    4) Custom command\n' >&2
  printf '    5) Clear\n' >&2
}

editor_preset_command() {
  case "$1" in
    1) printf '%s' 'open -a "Visual Studio Code"' ;;
    2) printf '%s' 'open -a Cursor' ;;
    3) printf '%s' 'open -a "Antigravity IDE"' ;;
    *) return 1 ;;
  esac
}

print_terminal_presets() {
  info "Terminal command:"
  printf '    1) Terminal.app (open -a Terminal)\n' >&2
  printf '    2) iTerm2 (open -a iTerm)\n' >&2
  printf '    3) Warp (open -a Warp)\n' >&2
  printf '    4) Ghostty (open -a Ghostty)\n' >&2
  printf '    5) cmux (cmux)\n' >&2
  printf '    6) Custom command\n' >&2
  printf '    7) Clear\n' >&2
}

terminal_preset_command() {
  case "$1" in
    1) printf '%s' 'open -a Terminal' ;;
    2) printf '%s' 'open -a iTerm' ;;
    3) printf '%s' 'open -a Warp' ;;
    4) printf '%s' 'open -a Ghostty' ;;
    5) printf '%s' 'cmux' ;;
    *) return 1 ;;
  esac
}
```

- [x] **Step 2: Add prompt functions in config command file**

Add to `src/workbranch/commands/config.sh` near the setup prompt functions:

```bash
configure_editor_prompt() {
  print_editor_presets
  current=${EDITOR_COMMAND:-keep}
  value=$(prompt_read "[*] Choose editor [$current]: ") || die "input aborted"
  case "$value" in
    "") ;;
    1|2|3) set_editor_command "$(editor_preset_command "$value")" ;;
    4)
      custom=$(prompt_required "Custom editor command")
      set_editor_command "$custom"
      ;;
    5|--clear) clear_editor_command ;;
    *) die "invalid editor choice: $value" ;;
  esac
}

configure_terminal_prompt() {
  print_terminal_presets
  current=${TERMINAL_COMMAND:-keep}
  value=$(prompt_read "[*] Choose terminal [$current]: ") || die "input aborted"
  case "$value" in
    "") ;;
    1|2|3|4|5) set_terminal_command "$(terminal_preset_command "$value")" ;;
    6)
      custom=$(prompt_required "Custom terminal command")
      set_terminal_command "$custom"
      ;;
    7|--clear) clear_terminal_command ;;
    *) die "invalid terminal choice: $value" ;;
  esac
}
```

- [x] **Step 3: Call full-flow prompts**

In `configure_existing_project()`, after `configure_project_settings` and before `Repositories`, call:

```bash
  printf '\n'
  configure_editor_prompt
  configure_terminal_prompt
```

In the interactive init/config setup path in `src/workbranch/commands/init.sh`, add the same two prompts after `Branch prefix` is collected and before repo prompts begin. This matches the resolved UX: base/project settings first, then tool settings, then repositories.

- [x] **Step 4: Support targeted config subcommands**

Replace the `cmd_config()` argument parsing with support for `editor` and `terminal`:

```bash
cmd_config() {
  rewrite_only=0
  config_target="all"
  case $# in
    0) ;;
    1)
      case "$1" in
        --rewrite) rewrite_only=1 ;;
        editor) config_target="editor" ;;
        terminal) config_target="terminal" ;;
        *) die "usage: workbranch config [editor|terminal|--rewrite]" ;;
      esac
      ;;
    *) die "usage: workbranch config [editor|terminal|--rewrite]" ;;
  esac
  ...
}
```

Inside the existing-project branch, call the targeted prompt instead of `configure_existing_project`:

```bash
    if [ "$rewrite_only" -eq 0 ]; then
      case "$config_target" in
        all) configure_existing_project ;;
        editor) configure_editor_prompt ;;
        terminal) configure_terminal_prompt ;;
      esac
    fi
```

When no project exists, allow only full `workbranch config`; reject targeted config with:

```bash
    [ "$config_target" = "all" ] || die "no enclosing workbranch project found"
```

- [x] **Step 5: Update source manifest**

Add `src/workbranch/lib/tool-launcher.sh` to `scripts/workbranch-sources.txt` after `src/workbranch/lib/prompts.sh`, before command files.

- [x] **Step 6: Run syntax and tests**

Run:

```bash
/bin/bash -n src/workbranch/lib/tool-launcher.sh src/workbranch/commands/config.sh src/workbranch/commands/init.sh tests/run.sh
./scripts/build-workbranch.sh
./tests/run.sh
```

Expected: targeted config tests pass after input expectations are updated; command tests still fail until `editor`, `terminal`, and `path` dispatch exists.

---

## Task 4: Implement path resolution and tool commands

**Files:**
- Modify: `src/workbranch/lib/tool-launcher.sh`
- Create: `src/workbranch/commands/tool-launcher.sh`
- Create: `src/workbranch/commands/path.sh`
- Modify: `src/workbranch/main.sh`
- Modify: `scripts/workbranch-sources.txt`

- [x] **Step 1: Add canonical path and task repo helpers**

Append to `src/workbranch/lib/tool-launcher.sh`:

```bash
canonical_path() {
  path=$1
  (cd "$path" 2>/dev/null && pwd -P) || return 1
}

resolve_task_path() {
  task=$1
  task_dir="$PROJECT_ROOT/$task"
  is_task_workspace_path "$task_dir" || die "task workspace not found: $task"
  RESOLVED_PATH=$(canonical_path "$task_dir") || die "task workspace not found: $task"
}

resolve_task_repo_path() {
  task=$1
  repo=$2
  repo_path=$(task_repo_path "$task" "$repo")
  [ -d "$repo_path" ] || die "task repo not found: $task/$repo"
  RESOLVED_PATH=$(canonical_path "$repo_path") || die "task repo not found: $task/$repo"
}

run_tool_command() {
  tool_label=$1
  command=$2
  path=$3
  [ -n "$command" ] || die "$tool_label command is not configured; run workbranch config $tool_label"
  (
    cd "$path" || exit 1
    WORKBRANCH_TOOL_PATH=$path
    export WORKBRANCH_TOOL_PATH
    sh -c "$command \"\$WORKBRANCH_TOOL_PATH\""
  )
}
```

- [x] **Step 2: Add path command implementation**

Create `src/workbranch/commands/path.sh`:

```bash
cmd_path() {
  require_project
  parse_repo_option "$@"
  [ ${#ARGS[@]} -eq 1 ] || die "usage: workbranch path <task> [--repo <repo>]"
  task=${ARGS[0]}
  validate_safe_name "task" "$task"

  # Keep stdout path-only: do not call info/success in this command.
  if [ -n "$FILTER_REPO" ]; then
    resolve_task_repo_path "$task" "$FILTER_REPO"
  else
    resolve_task_path "$task"
  fi
  printf '%s\n' "$RESOLVED_PATH"
}
```

- [x] **Step 3: Add editor/terminal launcher command implementation**

Create `src/workbranch/commands/tool-launcher.sh`:

```bash
cmd_tool_launcher() {
  tool_label=$1
  shift
  require_project
  case "$tool_label" in
    editor) command=$EDITOR_COMMAND ;;
    terminal) command=$TERMINAL_COMMAND ;;
    *) die "unknown tool launcher: $tool_label" ;;
  esac
  parse_repo_option "$@"
  [ ${#ARGS[@]} -eq 1 ] || die "usage: workbranch $tool_label <task> [--repo <repo>]"
  task=${ARGS[0]}
  validate_safe_name "task" "$task"

  if [ -n "$FILTER_REPO" ]; then
    resolve_task_repo_path "$task" "$FILTER_REPO"
    path=$RESOLVED_PATH
    info "Opening $tool_label: $task/$FILTER_REPO"
    run_tool_command "$tool_label" "$command" "$path" || die "failed to open $tool_label: $task/$FILTER_REPO"
    return 0
  fi

  resolve_task_path "$task"
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    resolve_task_repo_path "$task" "$name"
    path=$RESOLVED_PATH
    info "Opening $tool_label: $task/$name"
    run_tool_command "$tool_label" "$command" "$path" || die "failed to open $tool_label: $task/$name"
    i=$((i + 1))
  done
}

cmd_editor() {
  cmd_tool_launcher editor "$@"
}

cmd_terminal() {
  cmd_tool_launcher terminal "$@"
}
```

- [x] **Step 4: Wire command dispatch**

Add to `src/workbranch/main.sh`:

```bash
    editor) cmd_editor "$@" ;;
    terminal) cmd_terminal "$@" ;;
    path) cmd_path "$@" ;;
```

Place these near other workspace commands, after `list` or before `status`.

- [x] **Step 5: Update source manifest**

Add `src/workbranch/commands/path.sh` and `src/workbranch/commands/tool-launcher.sh` to `scripts/workbranch-sources.txt` after `src/workbranch/commands/list.sh` and before `src/workbranch/commands/status.sh`, with `path.sh` first so the path-only command is visibly separate from launchers.

- [x] **Step 6: Build and run tests**

Run:

```bash
./scripts/build-workbranch.sh
./tests/run.sh
```

Expected: path and tool command tests pass; docs/help tests may still fail until usage/docs are updated.

---

## Task 5: Update help, README, specs, and architecture docs

**Files:**
- Modify: `src/workbranch/usage.sh`
- Modify: `README.md`
- Modify: `README.ko.md`
- Modify: `docs/specs/0001-workbranch-mvp.md`
- Modify: `docs/architecture.md`

- [x] **Step 1: Update CLI help**

In `src/workbranch/usage.sh`, update the Workspace group:

```text
  list              List configured repos and task workspaces
  path <task>       Print a task workspace path
  editor <task>     Open task repo worktrees in the configured editor
  terminal <task>   Open task repo worktrees in the configured terminal
  config            Create or update .workbranch.config without cloning repos
  config editor     Update only the configured editor command
  config terminal   Update only the configured terminal command
  config --rewrite  Rewrite config to current format without prompts
```

Keep the Common option text:

```text
  --repo <repo>     Limit operation to one repo; otherwise all repos
```

- [x] **Step 2: Update help tests**

In `test_help_groups_commands`, add assertions for:

```bash
assert_contains "$out" "path <task>"
assert_contains "$out" "editor <task>"
assert_contains "$out" "terminal <task>"
assert_contains "$out" "config editor"
assert_contains "$out" "config terminal"
```

- [x] **Step 3: Update README command docs**

Add a short section under workspace lifecycle commands in `README.md`:

```markdown
### Opening task workspaces

Configure one editor and one terminal command for the project:

```bash
workbranch config editor
workbranch config terminal
```

Then open every repo in a task workspace:

```bash
workbranch editor login
workbranch terminal login
```

Limit to one repo when needed:

```bash
workbranch editor login --repo frontend
workbranch terminal login --repo backend
```

Launcher commands run repo-by-repo. Commands that keep running in the foreground, such as a raw TUI terminal command, should use `--repo` or a custom non-blocking wrapper.

Print full paths for scripting:

```bash
workbranch path login
workbranch path login --repo frontend
```
```

- [x] **Step 4: Update Korean README command docs**

Add the equivalent section to `README.ko.md`:

```markdown
### 작업 workspace 열기

프로젝트에서 공통으로 사용할 editor와 terminal 명령을 설정합니다.

```bash
workbranch config editor
workbranch config terminal
```

작업 workspace 안의 모든 repo를 엽니다.

```bash
workbranch editor login
workbranch terminal login
```

필요하면 repo 하나로 제한합니다.

```bash
workbranch editor login --repo frontend
workbranch terminal login --repo backend
```

Launcher 명령은 repo별로 순서대로 실행됩니다. foreground에 계속 머무는 TUI terminal 명령은 `--repo`를 쓰거나 non-blocking custom wrapper로 설정하세요.

스크립트에서 사용할 전체 경로를 출력합니다.

```bash
workbranch path login
workbranch path login --repo frontend
```
```

- [x] **Step 5: Update spec config contract**

In `docs/specs/0001-workbranch-mvp.md`, add optional directives to the config example and parser contract:

```text
EDITOR open -a "Visual Studio Code"
TERMINAL open -a Warp
```

Document that `EDITOR` and `TERMINAL` preserve command tails with whitespace the same way `TASK_SETUP` and `REPO_SETUP` do.

- [x] **Step 6: Update architecture notes**

In `docs/architecture.md`, add `src/workbranch/lib/tool-launcher.sh`, `src/workbranch/commands/tool-launcher.sh`, and `src/workbranch/commands/path.sh` to the module responsibility list. State that launcher/path commands are intentionally not Git operations and do not modify repositories.

- [x] **Step 7: Build and run docs-related tests**

Run:

```bash
./scripts/build-workbranch.sh
./tests/run.sh
```

Expected: help tests and generated-file freshness pass.

---

## Task 6: Final verification and review handoff

**Files:**
- Regenerate: `bin/workbranch`
- Verify: full repository state

- [x] **Step 1: Run syntax checks**

Run:

```bash
/bin/bash -n bin/workbranch install.sh tests/run.sh
```

Expected: no output and exit 0.

- [x] **Step 2: Run full integration suite**

Run:

```bash
./tests/run.sh
```

Expected: all tests pass. Record the final `Tests passed: N` line.

- [x] **Step 3: Check generated artifact freshness**

Run:

```bash
scripts/build-workbranch.sh
./tests/run.sh
```

Expected: `test_generated_workbranch_is_up_to_date` passes and `git diff -- bin/workbranch` contains only generated changes from source edits.

- [x] **Step 4: Check whitespace**

Run:

```bash
git diff --check
```

Expected: no output and exit 0.

- [x] **Step 5: Summarize without committing**

Prepare a handoff summary with:

```text
Implemented:
- EDITOR / TERMINAL config directives with presets and custom commands
- workbranch editor / terminal launchers
- workbranch path output
- docs and generated bin/workbranch updates

Verification:
- /bin/bash -n bin/workbranch install.sh tests/run.sh
- ./tests/run.sh
- git diff --check
```

Do not run `git commit` unless the user explicitly asks.

---

## Self-Review

- Spec coverage: The plan covers common editor/terminal config, preset/custom selection, targeted `workbranch config editor`, targeted `workbranch config terminal`, task/repo launcher commands, scriptable path output, docs, tests, and generated artifact refresh.
- Placeholder scan: No implementation step relies on unspecified behavior; each code-changing step names exact files and concrete snippets.
- Consistency check: Config directives are `EDITOR` and `TERMINAL`; Bash globals are `EDITOR_COMMAND` and `TERMINAL_COMMAND`; command names are `editor`, `terminal`, and `path`; all command forms accept the existing `--repo <repo>` parser. The launcher reads config after `require_project`, resolves paths without command-substitution-swallowed `die`, and keeps `workbranch path` stdout path-only.

## Execution Notes

- Implemented in auto mode.
- Verification passed:
  - `/bin/bash -n bin/workbranch install.sh tests/run.sh`
  - `./scripts/build-workbranch.sh`
  - `./tests/run.sh` (`Tests passed: 87`)
  - `git diff --check`
- No git commit or push was run.
