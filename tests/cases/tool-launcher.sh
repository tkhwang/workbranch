# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.
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
  printf '

' | run_expect_success "$WORKBRANCH" add login >/dev/null

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


test_editor_legacy_macos_app_preset_opens_new_instance_per_repo() {
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
  export WORKBRANCH_FAKE_TOOL_LOG="$TMP_ROOT/open.log"

  cat >> "$project/.workbranch.config" <<'CONFIG'
EDITOR open -a "Visual Studio Code"
CONFIG

  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '\n\n' | run_expect_success "$WORKBRANCH" add login >/dev/null

  PATH="$fake_bin:$PATH" run_expect_success "$WORKBRANCH" editor login >/dev/null
  log=$(cat "$WORKBRANCH_FAKE_TOOL_LOG")
  assert_contains "$log" "$canonical_project/login/frontend|-na Visual Studio Code --args --new-window $canonical_project/login/frontend"
  assert_contains "$log" "$canonical_project/login/backend|-na Visual Studio Code --args --new-window $canonical_project/login/backend"
  assert_not_contains "$log" "|-a Visual Studio Code"
  assert_not_contains "$log" "|-na Visual Studio Code $canonical_project"
}

test_tool_launcher_forced_color_highlights_tool_and_target_path() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  fake_tool="$TMP_ROOT/fake-tool.sh"
  append_fake_tool_script "$fake_tool"
  export WORKBRANCH_FAKE_TOOL_LOG="$TMP_ROOT/tool.log"

  cat >> "$project/.workbranch.config" <<CONFIG
EDITOR $fake_tool
TERMINAL $fake_tool
CONFIG

  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '\n\n' | run_expect_success "$WORKBRANCH" add login >/dev/null

  out=$(env -u NO_COLOR WORKBRANCH_COLOR=always "$WORKBRANCH" editor login --repo frontend 2>&1)
  assert_contains "$out" $'\033[0;35meditor\033[0m'
  assert_contains "$out" $'\033[0;36mlogin/frontend\033[0m'

  out=$(env -u NO_COLOR WORKBRANCH_COLOR=always "$WORKBRANCH" terminal login --repo backend 2>&1)
  assert_contains "$out" $'\033[0;35mterminal\033[0m'
  assert_contains "$out" $'\033[0;36mlogin/backend\033[0m'
}

test_tool_commands_require_configured_command() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '

' | run_expect_success "$WORKBRANCH" add login >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" editor login)
  assert_contains "$out" "editor command is not configured; run workbranch config editor"

  out=$(run_expect_fail "$WORKBRANCH" terminal login --repo frontend)
  assert_contains "$out" "terminal command is not configured; run workbranch config terminal"
}

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
  printf '

' | run_expect_success "$WORKBRANCH" add login >/dev/null
  rm -rf "$project/login/frontend"

  out=$(run_expect_fail "$WORKBRANCH" editor login --repo frontend)
  assert_contains "$out" "task repo not found: login/frontend"
  assert_not_exists "$WORKBRANCH_FAKE_TOOL_LOG"
}

