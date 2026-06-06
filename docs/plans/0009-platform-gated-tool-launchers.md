# Platform-Gated Tool Launchers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` before every behavior change. Steps use checkbox (`- [ ]`) syntax for tracking. Make source changes under `src/workbranch/**`, rebuild with `scripts/build-workbranch.sh`, then verify syntax checks, targeted tests, `./tests/run.sh`, installed-binary smoke, and `git diff --check`. Do not edit `bin/workbranch` by hand.

**Goal:** Add a platform detection layer so core `workbranch` Git/worktree/config/path commands are explicitly supported on macOS, Linux, and WSL, while app-launcher tool surfaces are macOS-only.

**Architecture:** Introduce a small platform library with one source of truth for `macos`, `linux`, `wsl`, and `other`. Gate operational commands through core-platform support, gate tool app launch/config surfaces through macOS-only checks, and keep `help`/`version` available everywhere. Tests use a dedicated environment override so platform branches can be verified without relying on the host OS.

**Tech Stack:** Portable Bash, `uname`, WSL environment/proc detection, generated `bin/workbranch`, existing `tests/run.sh` integration suite, existing tool launcher/config modules from `docs/plans/0008-superset-open-in-app-launcher.md`.

---

## Repo Evidence

- Current source layout is modular and generated through `scripts/workbranch-sources.txt`; new source files must be added there before rebuilding `bin/workbranch`.
- Current tool app commands live in `src/workbranch/commands/tool-launcher.sh`:
  - `cmd_ide`
  - `cmd_terminal`
  - `cmd_finder`
- Current macOS app command presets live in `src/workbranch/lib/tool-launcher.sh` and use macOS `open` commands.
- Current `run_finder_command` still contains a Linux `xdg-open` branch. That conflicts with the new requirement and must be removed.
- Current `workbranch config` calls `configure_ide_prompt` and `configure_terminal_prompt` from `src/workbranch/commands/config.sh`; full project config must keep working on Linux/WSL without forcing macOS-only tool prompts.
- Current `workbranch init` calls `configure_ide_prompt` and `configure_terminal_prompt` from `src/workbranch/commands/init.sh`; init must keep working on Linux/WSL without forcing macOS-only tool prompts.

## Decision Gates

- [x] Core platform support scope
  - Impact: Public CLI contract and test matrix.
  - Current evidence: The user explicitly requested basic features usable on macOS/Linux/WSL.
  - Decision: Core operational commands support `macos`, `linux`, and `wsl`; unsupported platforms fail for operational commands with a clear platform error. `help` and `version` remain available everywhere.
  - Rationale: Git/worktree/path/config behavior is shell/Git based and can run on these three platform families. Keeping help/version available avoids making diagnosis harder on unsupported hosts.

- [x] Tool app platform support scope
  - Impact: User-visible launcher behavior and config prompts.
  - Current evidence: Current app presets use macOS `open`; the user stated tool app launch appears mac-only and should be restricted to macOS.
  - Decision: `workbranch finder`, `workbranch ide`, `workbranch terminal`, `workbranch config ide`, and `workbranch config terminal` are macOS-only. Full `workbranch config` and `workbranch init` skip IDE/Terminal tool prompts on Linux/WSL instead of failing the whole command.
  - Rationale: Direct tool app execution and app preset configuration are the macOS-only surface. Full project config/init are basic features, so they must remain usable on Linux/WSL.

- [x] Test platform override name
  - Impact: Test determinism and public environment surface.
  - Current evidence: Current tests fake `uname` in `tests/cases/tool-launcher.sh`, but a platform library will be easier to test through an explicit override.
  - Decision: Use `WORKBRANCH_TEST_PLATFORM` as a test-only override with accepted values `macos`, `linux`, `wsl`, and `other`.
  - Rationale: The name makes test-only intent explicit and avoids suggesting this is a user configuration knob.

## Target Behavior

### Core commands

These commands must run on `macos`, `linux`, and `wsl`:

```bash
workbranch init
workbranch config
workbranch list
workbranch add <task>
workbranch remove <task>
workbranch path <task>
workbranch status
workbranch pull
workbranch update
workbranch push
workbranch land <task>
```

`help`, `-h`, `--help`, `version`, `-v`, and `--version` remain available on every platform, including unsupported `other`.

On unsupported `other`, operational commands fail before project parsing with:

```text
[-] Error: unsupported platform: other; workbranch supports macOS, Linux, and WSL
```

### Tool app commands

These commands must run only on `macos`:

```bash
workbranch finder <task> [--repo <repo>]
workbranch ide <task> [--repo <repo>]
workbranch terminal <task> [--repo <repo>]
```

On `linux`, `wsl`, or `other`, they fail before project parsing with:

```text
[-] Error: workbranch <command> is only supported on macOS; core workbranch commands support macOS, Linux, and WSL
```

where `<command>` is `finder`, `ide`, or `terminal`.

### Tool config commands

These commands must run only on `macos`:

```bash
workbranch config ide
workbranch config terminal
```

On `linux`, `wsl`, or `other`, they fail before project parsing with:

```text
[-] Error: workbranch config <target> is only supported on macOS; core workbranch commands support macOS, Linux, and WSL
```

where `<target>` is `ide` or `terminal`.

### Full config/init prompts on Linux/WSL

On `linux` and `wsl`, full interactive config flows remain basic features:

```bash
workbranch config
workbranch init
```

They skip IDE/Terminal prompts and print one status line:

```text
[*] Tool app launchers are macOS-only; skipping IDE/Terminal prompts.
```

No `IDE` or `TERMINAL` directive is written unless the command was already present in a parsed config and the command is rewriting that existing value. The implementation should preserve existing parsed directives during rewrite, but should not prompt for new tool command values on Linux/WSL.

---

## Files and Responsibilities

- Create `src/workbranch/lib/platform.sh`
  - Detect `macos`, `linux`, `wsl`, or `other`.
  - Provide core-platform and tool-platform guard helpers.
  - Provide a test-only override through `WORKBRANCH_TEST_PLATFORM`.

- Modify `scripts/workbranch-sources.txt`
  - Include `src/workbranch/lib/platform.sh` before modules that call platform helpers.

- Modify `src/workbranch/main.sh`
  - Call the core platform guard for operational commands.
  - Exempt `help` and `version` commands from the core platform guard.

- Modify `src/workbranch/commands/tool-launcher.sh`
  - Gate `cmd_finder`, `cmd_ide`, and `cmd_terminal` with macOS-only checks before project parsing.

- Modify `src/workbranch/lib/tool-launcher.sh`
  - Remove Linux `xdg-open` support from `run_finder_command`.
  - Keep Finder implementation macOS `open` only.

- Modify `src/workbranch/commands/config.sh`
  - Gate `config ide` and `config terminal` as macOS-only.
  - Keep full `workbranch config` available on Linux/WSL by skipping IDE/Terminal prompts.

- Modify `src/workbranch/commands/init.sh`
  - Keep `workbranch init` available on Linux/WSL by skipping IDE/Terminal prompts.

- Modify tests:
  - `tests/cases/platform.sh`
  - `tests/cases/tool-launcher.sh`
  - `tests/cases/config.sh`
  - `tests/cases/interactive-init.sh`
  - `tests/run.sh`

- Modify docs:
  - `README.md`
  - `README.ko.md`
  - `docs/specs/0001-workbranch-mvp.md`

- Regenerate:
  - `bin/workbranch`

---

## Implementation Tasks

### Task 1: Add platform detection and core command tests

**Files:**
- Create: `tests/cases/platform.sh`
- Modify: `tests/run.sh`

- [ ] **Step 1: Write failing platform helper/guard tests**

Create `tests/cases/platform.sh`:

```bash
# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

test_help_and_version_work_on_unsupported_platform() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  out=$(WORKBRANCH_TEST_PLATFORM=other run_expect_success "$WORKBRANCH" help)
  assert_contains "$out" "Usage:"

  out=$(WORKBRANCH_TEST_PLATFORM=other run_expect_success "$WORKBRANCH" version)
  assert_contains "$out" "workbranch "
}

test_core_commands_reject_unsupported_platform() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  out=$(WORKBRANCH_TEST_PLATFORM=other run_expect_fail "$WORKBRANCH" list)
  assert_contains "$out" "unsupported platform: other; workbranch supports macOS, Linux, and WSL"
}

test_core_commands_allow_linux_and_wsl() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  out=$(WORKBRANCH_TEST_PLATFORM=linux run_expect_success "$WORKBRANCH" list)
  assert_contains "$out" "[*] Project: fullstack"

  out=$(WORKBRANCH_TEST_PLATFORM=wsl run_expect_success "$WORKBRANCH" list)
  assert_contains "$out" "[*] Project: fullstack"
}
```

- [ ] **Step 2: Register the tests**

In `tests/run.sh`, add these near other meta/platform-level tests:

```bash
  run_test test_help_and_version_work_on_unsupported_platform
  run_test test_core_commands_reject_unsupported_platform
  run_test test_core_commands_allow_linux_and_wsl
```

- [ ] **Step 3: Run the platform tests and verify RED**

Run:

```bash
REPO_ROOT="$PWD" WORKBRANCH="$PWD/bin/workbranch" /bin/bash <<'SCRIPT'
set -u
. "$REPO_ROOT/tests/lib/helpers.sh"
. "$REPO_ROOT/tests/cases/platform.sh"
run_test test_help_and_version_work_on_unsupported_platform
run_test test_core_commands_reject_unsupported_platform
run_test test_core_commands_allow_linux_and_wsl
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -gt 0 ]
SCRIPT
```

Expected:

```text
PASS=1 FAIL=2
```

`help` and `version` should already pass because no platform guard exists. The two guard tests should fail because `WORKBRANCH_TEST_PLATFORM` is not implemented yet.

### Task 2: Implement platform library and core command guard

**Files:**
- Create: `src/workbranch/lib/platform.sh`
- Modify: `scripts/workbranch-sources.txt`
- Modify: `src/workbranch/main.sh`
- Regenerate: `bin/workbranch`

- [ ] **Step 1: Add the platform library**

Create `src/workbranch/lib/platform.sh`:

```bash
detect_platform() {
  if [ -n "${WORKBRANCH_TEST_PLATFORM:-}" ]; then
    case "$WORKBRANCH_TEST_PLATFORM" in
      macos|linux|wsl|other) printf '%s' "$WORKBRANCH_TEST_PLATFORM" ;;
      *) die "invalid WORKBRANCH_TEST_PLATFORM: $WORKBRANCH_TEST_PLATFORM" ;;
    esac
    return 0
  fi

  case "$(uname -s 2>/dev/null || printf unknown)" in
    Darwin) printf '%s' macos ;;
    Linux)
      if [ -n "${WSL_INTEROP:-}" ] || grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
        printf '%s' wsl
      else
        printf '%s' linux
      fi
      ;;
    *) printf '%s' other ;;
  esac
}

is_core_supported_platform() {
  case "$(detect_platform)" in
    macos|linux|wsl) return 0 ;;
    *) return 1 ;;
  esac
}

is_macos_platform() {
  [ "$(detect_platform)" = "macos" ]
}

require_core_supported_platform() {
  platform=$(detect_platform)
  case "$platform" in
    macos|linux|wsl) return 0 ;;
    *) die "unsupported platform: $platform; workbranch supports macOS, Linux, and WSL" ;;
  esac
}

require_macos_tool_platform() {
  label=$1
  is_macos_platform || die "workbranch $label is only supported on macOS; core workbranch commands support macOS, Linux, and WSL"
}

info_skip_tool_prompts_for_platform() {
  info "Tool app launchers are macOS-only; skipping IDE/Terminal prompts."
}
```

- [ ] **Step 2: Add the source to the build order**

In `scripts/workbranch-sources.txt`, insert `src/workbranch/lib/platform.sh` after `src/workbranch/lib/output.sh` and before command modules:

```text
src/workbranch/lib/output.sh
src/workbranch/lib/platform.sh
src/workbranch/usage.sh
```

- [ ] **Step 3: Gate operational commands in `main`**

In `src/workbranch/main.sh`, update `main` so `help` and `version` bypass the core guard while operational commands require macOS/Linux/WSL:

```bash
main() {
  cmd=${1:-help}
  if [ $# -gt 0 ]; then shift; fi
  case "$cmd" in
    help|-h|--help|version|-v|--version) ;;
    *) require_core_supported_platform ;;
  esac
  case "$cmd" in
    config) cmd_config "$@" ;;
    init) cmd_init "$@" ;;
    add) cmd_add "$@" ;;
    list) cmd_list "$@" ;;
    path) cmd_path "$@" ;;
    ide) cmd_ide "$@" ;;
    finder) cmd_finder "$@" ;;
    terminal) cmd_terminal "$@" ;;
    status) cmd_status "$@" ;;
    pull) cmd_pull "$@" ;;
    update) cmd_update "$@" ;;
    push) cmd_push "$@" ;;
    land) cmd_land "$@" ;;
    remove) cmd_remove "$@" ;;
    version|-v|--version) cmd_version "$@" ;;
    help|-h|--help) usage ;;
    *) usage_plain >&2; die "unknown command: $cmd" ;;
  esac
}
```

- [ ] **Step 4: Rebuild and verify Task 1 tests pass**

Run:

```bash
scripts/build-workbranch.sh
REPO_ROOT="$PWD" WORKBRANCH="$PWD/bin/workbranch" /bin/bash <<'SCRIPT'
set -u
. "$REPO_ROOT/tests/lib/helpers.sh"
. "$REPO_ROOT/tests/cases/platform.sh"
run_test test_help_and_version_work_on_unsupported_platform
run_test test_core_commands_reject_unsupported_platform
run_test test_core_commands_allow_linux_and_wsl
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
exit "$FAIL"
SCRIPT
```

Expected:

```text
PASS=3 FAIL=0
```

### Task 3: Gate tool app execution to macOS only

**Files:**
- Modify: `tests/cases/tool-launcher.sh`
- Modify: `tests/run.sh`
- Modify: `src/workbranch/commands/tool-launcher.sh`
- Modify: `src/workbranch/lib/tool-launcher.sh`
- Regenerate: `bin/workbranch`

- [ ] **Step 1: Replace the Linux Finder success test with macOS-only failure tests**

In `tests/cases/tool-launcher.sh`, remove `test_finder_linux_branch_uses_xdg_open` and add:

```bash
test_tool_app_commands_are_macos_only() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  out=$(WORKBRANCH_TEST_PLATFORM=linux run_expect_fail "$WORKBRANCH" finder login)
  assert_contains "$out" "workbranch finder is only supported on macOS; core workbranch commands support macOS, Linux, and WSL"

  out=$(WORKBRANCH_TEST_PLATFORM=wsl run_expect_fail "$WORKBRANCH" ide login)
  assert_contains "$out" "workbranch ide is only supported on macOS; core workbranch commands support macOS, Linux, and WSL"

  out=$(WORKBRANCH_TEST_PLATFORM=linux run_expect_fail "$WORKBRANCH" terminal login)
  assert_contains "$out" "workbranch terminal is only supported on macOS; core workbranch commands support macOS, Linux, and WSL"
}
```

- [ ] **Step 2: Update test registration**

In `tests/run.sh`, remove:

```bash
  run_test test_finder_linux_branch_uses_xdg_open
```

Add:

```bash
  run_test test_tool_app_commands_are_macos_only
```

- [ ] **Step 3: Run the tool app platform test and verify RED**

Run:

```bash
REPO_ROOT="$PWD" WORKBRANCH="$PWD/bin/workbranch" /bin/bash <<'SCRIPT'
set -u
. "$REPO_ROOT/tests/lib/helpers.sh"
. "$REPO_ROOT/tests/cases/tool-launcher.sh"
run_test test_tool_app_commands_are_macos_only
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -gt 0 ]
SCRIPT
```

Expected:

```text
PASS=0 FAIL=1
```

- [ ] **Step 4: Add macOS-only checks to tool commands**

In `src/workbranch/commands/tool-launcher.sh`, add macOS checks before `require_project` in `cmd_tool_launcher` and `cmd_finder`:

```bash
cmd_tool_launcher() {
  tool_label=$1
  shift
  require_macos_tool_platform "$tool_label"
  require_project
  ...
}
```

and:

```bash
cmd_finder() {
  require_macos_tool_platform finder
  require_project
  ...
}
```

- [ ] **Step 5: Remove Linux `xdg-open` from Finder implementation**

In `src/workbranch/lib/tool-launcher.sh`, replace `run_finder_command` with macOS-only `open`:

```bash
run_finder_command() {
  path=$1
  (
    # Keep cwd aligned with the opened absolute path so tests can observe it via fake open.
    cd "$path" || exit 1
    open "$path"
  )
}
```

- [ ] **Step 6: Rebuild and verify tool app platform tests pass**

Run:

```bash
scripts/build-workbranch.sh
REPO_ROOT="$PWD" WORKBRANCH="$PWD/bin/workbranch" /bin/bash <<'SCRIPT'
set -u
. "$REPO_ROOT/tests/lib/helpers.sh"
. "$REPO_ROOT/tests/cases/tool-launcher.sh"
run_test test_tool_app_commands_are_macos_only
run_test test_finder_opens_task_root_without_repo_filter
run_test test_finder_repo_filter_opens_one_repo_path
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
exit "$FAIL"
SCRIPT
```

Expected:

```text
PASS=3 FAIL=0
```

### Task 4: Keep full config/init usable on Linux/WSL while gating tool-specific config

**Files:**
- Modify: `tests/cases/config.sh`
- Modify: `tests/cases/interactive-init.sh`
- Modify: `tests/run.sh`
- Modify: `src/workbranch/commands/config.sh`
- Modify: `src/workbranch/commands/init.sh`
- Regenerate: `bin/workbranch`

- [ ] **Step 1: Add failing config platform tests**

Add to `tests/cases/config.sh`:

```bash
test_config_tool_targets_are_macos_only() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  out=$(WORKBRANCH_TEST_PLATFORM=linux run_expect_fail "$WORKBRANCH" config ide)
  assert_contains "$out" "workbranch config ide is only supported on macOS; core workbranch commands support macOS, Linux, and WSL"

  out=$(WORKBRANCH_TEST_PLATFORM=wsl run_expect_fail "$WORKBRANCH" config terminal)
  assert_contains "$out" "workbranch config terminal is only supported on macOS; core workbranch commands support macOS, Linux, and WSL"
}

test_full_config_skips_tool_prompts_on_linux() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "" "" "" "" | WORKBRANCH_TEST_PLATFORM=linux run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[*] Tool app launchers are macOS-only; skipping IDE/Terminal prompts."
  assert_not_contains "$out" "[*] IDE command:"
  assert_not_contains "$out" "[*] Terminal command:"
}
```

Add to `tests/cases/interactive-init.sh`:

```bash
test_interactive_init_skips_tool_prompts_on_wsl() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work"
  frontend_remote=$(make_repo frontend)
  input=$(cat <<INPUT

.
fullstack
_base
feature
frontend
$frontend_remote
master

n
Y
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | WORKBRANCH_TEST_PLATFORM=wsl run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[*] Tool app launchers are macOS-only; skipping IDE/Terminal prompts."
  assert_not_contains "$out" "[*] IDE command:"
  assert_not_contains "$out" "[*] Terminal command:"
  config=$(cat "$TMP_ROOT/work/fullstack/.workbranch.config")
  assert_not_contains "$config" "IDE "
  assert_not_contains "$config" "TERMINAL "
}
```

- [ ] **Step 2: Register the config/init platform tests**

In `tests/run.sh`, add:

```bash
  run_test test_config_tool_targets_are_macos_only
  run_test test_full_config_skips_tool_prompts_on_linux
  run_test test_interactive_init_skips_tool_prompts_on_wsl
```

- [ ] **Step 3: Run the config/init platform tests and verify RED**

Run:

```bash
REPO_ROOT="$PWD" WORKBRANCH="$PWD/bin/workbranch" /bin/bash <<'SCRIPT'
set -u
. "$REPO_ROOT/tests/lib/helpers.sh"
. "$REPO_ROOT/tests/cases/config.sh"
. "$REPO_ROOT/tests/cases/interactive-init.sh"
run_test test_config_tool_targets_are_macos_only
run_test test_full_config_skips_tool_prompts_on_linux
run_test test_interactive_init_skips_tool_prompts_on_wsl
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -gt 0 ]
SCRIPT
```

Expected:

```text
PASS=0 FAIL=3
```

- [ ] **Step 4: Add a helper for optional tool prompts**

In `src/workbranch/commands/config.sh`, add:

```bash
configure_tool_prompts_if_macos() {
  if is_macos_platform; then
    configure_ide_prompt
    configure_terminal_prompt
  else
    info_skip_tool_prompts_for_platform
  fi
}
```

- [ ] **Step 5: Gate targeted config commands**

In `src/workbranch/commands/config.sh`, after argument parsing and before `find_project_root`, add:

```bash
case "$config_target" in
  ide|terminal) require_macos_tool_platform "config $config_target" ;;
esac
```

- [ ] **Step 6: Use the optional prompt helper in full config/init**

In `src/workbranch/commands/config.sh`, replace full config calls to separate IDE/Terminal prompts with:

```bash
configure_tool_prompts_if_macos
```

In `src/workbranch/commands/init.sh`, replace:

```bash
configure_ide_prompt
configure_terminal_prompt
```

with:

```bash
configure_tool_prompts_if_macos
```

- [ ] **Step 7: Rebuild and verify config/init platform tests pass**

Run:

```bash
scripts/build-workbranch.sh
REPO_ROOT="$PWD" WORKBRANCH="$PWD/bin/workbranch" /bin/bash <<'SCRIPT'
set -u
. "$REPO_ROOT/tests/lib/helpers.sh"
. "$REPO_ROOT/tests/cases/config.sh"
. "$REPO_ROOT/tests/cases/interactive-init.sh"
run_test test_config_tool_targets_are_macos_only
run_test test_full_config_skips_tool_prompts_on_linux
run_test test_interactive_init_skips_tool_prompts_on_wsl
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
exit "$FAIL"
SCRIPT
```

Expected:

```text
PASS=3 FAIL=0
```

### Task 5: Update docs/specs for platform support

**Files:**
- Modify: `README.md`
- Modify: `README.ko.md`
- Modify: `docs/specs/0001-workbranch-mvp.md`

- [ ] **Step 1: Add platform support text to README**

In `README.md`, add a platform note near the command table:

```markdown
## Platform support

Core workbranch commands are supported on macOS, Linux, and WSL. Tool app launchers are macOS-only because the built-in app presets use macOS `open` and macOS app names.

Supported everywhere: Git/worktree commands, `path`, `list`, `status`, `config`, `init`, and generated CLI distribution checks.

macOS-only: `finder`, `ide`, `terminal`, `config ide`, and `config terminal`. On Linux/WSL, full `workbranch config` and `workbranch init` skip IDE/Terminal tool prompts.
```

- [ ] **Step 2: Add Korean platform support text**

In `README.ko.md`, add:

```markdown
## Platform 지원

기본 workbranch 명령은 macOS, Linux, WSL에서 지원합니다. Tool app launcher는 macOS 전용입니다. 내장 app preset이 macOS `open`과 macOS app 이름을 사용하기 때문입니다.

공통 지원: Git/worktree 명령, `path`, `list`, `status`, `config`, `init`, generated CLI 검증.

macOS 전용: `finder`, `ide`, `terminal`, `config ide`, `config terminal`. Linux/WSL에서 전체 `workbranch config`와 `workbranch init`은 IDE/Terminal tool prompt를 건너뜁니다.
```

- [ ] **Step 3: Update the MVP spec**

In `docs/specs/0001-workbranch-mvp.md`, add this section before the tool launcher section:

```markdown
### Platform support

Core commands support macOS, Linux, and WSL. Operational commands fail on unsupported platforms before project parsing with `unsupported platform: <platform>; workbranch supports macOS, Linux, and WSL`. `help` and `version` remain available on unsupported platforms.

Tool app launcher commands are macOS-only: `finder`, `ide`, and `terminal`. Tool-specific config commands are also macOS-only: `config ide` and `config terminal`. Full `config` and `init` remain available on Linux/WSL and skip IDE/Terminal tool prompts.
```

- [ ] **Step 4: Verify docs do not advertise Linux tool launchers**

Run:

```bash
rg -n "xdg-open|Linux.*finder|Linux.*IDE|Linux.*terminal" README.md README.ko.md docs/specs/0001-workbranch-mvp.md
```

Expected: no output.

### Task 6: Full verification and installed smoke

**Files:**
- Regenerate: `bin/workbranch`
- Update: `docs/plans/0009-platform-gated-tool-launchers.md`

- [ ] **Step 1: Run syntax checks**

Run:

```bash
/bin/bash -n bin/workbranch install.sh tests/run.sh tests/cases/*.sh src/workbranch/*.sh src/workbranch/lib/*.sh src/workbranch/commands/*.sh
```

Expected: exit 0.

- [ ] **Step 2: Run full integration suite**

Run:

```bash
./tests/run.sh
```

Expected final line:

```text
Tests passed: <current count>
```

No failures are acceptable.

- [ ] **Step 3: Run diff hygiene**

Run:

```bash
git diff --check
```

Expected: exit 0.

- [ ] **Step 4: Install and smoke-test the live binary**

Run:

```bash
install -m 0755 bin/workbranch "$HOME/.local/bin/workbranch"
~/.local/bin/workbranch version
```

Expected:

```text
workbranch <current version>
```

Run targeted platform smoke checks:

```bash
WORKBRANCH_TEST_PLATFORM=linux ~/.local/bin/workbranch help >/dev/null
WORKBRANCH_TEST_PLATFORM=linux ~/.local/bin/workbranch version >/dev/null
WORKBRANCH_TEST_PLATFORM=other ~/.local/bin/workbranch list 2>&1 | grep 'unsupported platform: other'
WORKBRANCH_TEST_PLATFORM=linux ~/.local/bin/workbranch finder task1 2>&1 | grep 'workbranch finder is only supported on macOS'
```

Expected: each command exits with the expected status for its pipeline and prints the expected grep match where grep is used.

- [ ] **Step 5: Record execution evidence in this plan**

Append an `## Execution Evidence` section to `docs/plans/0009-platform-gated-tool-launchers.md` with exact command output summaries from syntax, targeted tests, full suite, installed smoke, and `git diff --check`.

---

## Deferred / Explicitly Out of Scope

- Linux desktop app launchers such as `xdg-open`, `gio open`, direct `code`, `cursor`, or terminal emulator commands.
- WSL bridge launchers such as `wslview`, `explorer.exe`, Windows Terminal, or Windows-side IDE path translation.
- Structured app-id config replacing raw command strings.
- Platform-specific Homebrew/Linux package manager formulas.
- Runtime migration from `IDE`/`TERMINAL` directives to app ids.

## Acceptance Criteria

- A new platform library detects `macos`, `linux`, `wsl`, and `other`, with deterministic tests through `WORKBRANCH_TEST_PLATFORM`.
- Core operational commands are allowed on `macos`, `linux`, and `wsl`.
- Operational commands on `other` fail with a clear unsupported-platform error, while `help` and `version` still run.
- `finder`, `ide`, and `terminal` fail on `linux`, `wsl`, and `other` before project parsing.
- `run_finder_command` no longer supports Linux `xdg-open`.
- `config ide` and `config terminal` are macOS-only.
- Full `workbranch config` and `workbranch init` run on Linux/WSL and skip IDE/Terminal prompts with a clear info line.
- README, Korean README, and MVP spec state that basic features support macOS/Linux/WSL and app launchers are macOS-only.
- `bin/workbranch` is regenerated from source.
- Syntax checks, targeted platform tests, full integration suite, installed smoke, and `git diff --check` pass.
