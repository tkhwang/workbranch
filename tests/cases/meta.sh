# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.
test_generated_workbranch_is_up_to_date() {
  tmp_root=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  generated="$tmp_root/workbranch.generated"
  if ! build_output=$("$REPO_ROOT/scripts/build-workbranch.sh" "$generated" 2>&1); then
    rm -rf "$tmp_root"
    fail "failed to build generated workbranch: $build_output"
  fi
  if ! cmp "$generated" "$WORKBRANCH" >/dev/null; then
    rm -rf "$tmp_root"
    fail "bin/workbranch is stale; run scripts/build-workbranch.sh"
  fi
  rm -rf "$tmp_root"
}

test_run_test_output_uses_status_prefixes() {
  out=$(
    REPO_ROOT="$REPO_ROOT" /bin/bash <<'SCRIPT'
set -u
. "$REPO_ROOT/tests/lib/helpers.sh"
cleanup_fixture() { :; }
harness_pass() { return 0; }
harness_fail() { return 1; }
run_test harness_pass
run_test harness_fail
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
SCRIPT
  )
  assert_contains "$out" "[*] harness_pass"
  case "$out" in
    *"[+] ("*"s)"*) ;;
    *) fail "expected pass output to include elapsed seconds; got: $out" ;;
  esac
  assert_not_contains "$out" "[+] harness_pass"
  assert_contains "$out" "[*] harness_fail"
  case "$out" in
    *"[-] ("*"s)"*) ;;
    *) fail "expected fail output to include elapsed seconds; got: $out" ;;
  esac
  assert_not_contains "$out" "[-] harness_fail"
  assert_contains "$out" "PASS=1 FAIL=1"
}

test_run_expect_helpers_do_not_leak_tty_stdin() {
  out=$(printf 'unexpected-tty-input\n' | WORKBRANCH_TEST_FORCE_TTY_STDIN=1 run_expect_success /bin/bash -c 'if IFS= read -r line; then printf "read:%s" "$line"; else printf "no-input"; fi')
  [ "$out" = "no-input" ] || fail "expected forced TTY stdin to be closed, got: $out"
}

test_run_expect_helpers_preserve_piped_stdin() {
  out=$(printf 'expected-pipe-input\n' | run_expect_success /bin/bash -c 'IFS= read -r line && printf "%s" "$line"')
  [ "$out" = "expected-pipe-input" ] || fail "expected piped stdin to be preserved, got: $out"
}

test_fail_helper_uses_error_prefix() {
  out=$(
    REPO_ROOT="$REPO_ROOT" /bin/bash <<'SCRIPT'
set -u
. "$REPO_ROOT/tests/lib/helpers.sh"
fail "sample failure"
SCRIPT
  )
  assert_contains "$out" "[-] Error: sample failure"
  assert_not_contains "$out" "FAIL: sample failure"
}

test_run_test_continues_after_fail_helper() {
  out=$(
    REPO_ROOT="$REPO_ROOT" /bin/bash <<'SCRIPT' || true
set -u
. "$REPO_ROOT/tests/lib/helpers.sh"
cleanup_fixture() { :; }
nested_fail() { fail "nested failure"; }
nested_pass() { return 0; }
run_test nested_fail
run_test nested_pass
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
SCRIPT
  )
  assert_contains "$out" "[*] nested_fail"
  assert_contains "$out" "[-] Error: nested failure"
  assert_contains "$out" "[-] ("
  assert_contains "$out" "[*] nested_pass"
  assert_contains "$out" "[+] ("
  assert_contains "$out" "PASS=1 FAIL=1"
}

test_runner_fails_fast_when_no_case_files() {
  tmp_root=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$tmp_root/tests/lib" "$tmp_root/bin"
  cp "$REPO_ROOT/tests/run.sh" "$tmp_root/tests/run.sh"
  cp "$REPO_ROOT/tests/lib/helpers.sh" "$tmp_root/tests/lib/helpers.sh"
  : > "$tmp_root/bin/workbranch"
  chmod +x "$tmp_root/bin/workbranch"

  out=$(/bin/bash "$tmp_root/tests/run.sh" 2>&1)
  status=$?
  rm -rf "$tmp_root"

  [ "$status" -ne 0 ] || fail "expected runner to fail without case files"
  assert_contains "$out" "[-] Error: no test case files found:"
  assert_not_contains "$out" "[*] test_generated_workbranch_is_up_to_date"
}

test_runner_rejects_non_regular_case_file() {
  tmp_root=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$tmp_root/tests/lib" "$tmp_root/tests/cases/not-regular.sh" "$tmp_root/bin"
  cp "$REPO_ROOT/tests/run.sh" "$tmp_root/tests/run.sh"
  cp "$REPO_ROOT/tests/lib/helpers.sh" "$tmp_root/tests/lib/helpers.sh"
  : > "$tmp_root/bin/workbranch"
  chmod +x "$tmp_root/bin/workbranch"

  out=$(/bin/bash "$tmp_root/tests/run.sh" 2>&1)
  status=$?
  rm -rf "$tmp_root"

  [ "$status" -ne 0 ] || fail "expected runner to fail on non-regular case file"
  assert_contains "$out" "[-] Error: invalid test case file:"
  assert_not_contains "$out" "[*] test_generated_workbranch_is_up_to_date"
}

test_runner_reports_failed_case_source() {
  tmp_root=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$tmp_root/tests/lib" "$tmp_root/tests/cases" "$tmp_root/bin"
  cp "$REPO_ROOT/tests/run.sh" "$tmp_root/tests/run.sh"
  cp "$REPO_ROOT/tests/lib/helpers.sh" "$tmp_root/tests/lib/helpers.sh"
  printf '%s\n' 'return 1' > "$tmp_root/tests/cases/bad.sh"
  : > "$tmp_root/bin/workbranch"
  chmod +x "$tmp_root/bin/workbranch"

  out=$(/bin/bash "$tmp_root/tests/run.sh" 2>&1)
  status=$?
  rm -rf "$tmp_root"

  [ "$status" -ne 0 ] || fail "expected runner to fail when sourcing case file fails"
  assert_contains "$out" "[-] Error: failed to source test case file:"
  assert_not_contains "$out" "[*] test_generated_workbranch_is_up_to_date"
}

test_setup_command_is_removed() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  out=$(run_expect_fail "$WORKBRANCH" setup login)
  assert_contains "$out" "unknown command: setup"
}

test_resume_command_is_removed() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  out=$(run_expect_fail "$WORKBRANCH" resume login)
  assert_contains "$out" "unknown command: resume"
}

test_help_groups_commands() {
  out=$(run_expect_success "$WORKBRANCH" help)
  assert_contains "$out" "Workspace:"
  assert_contains "$out" "init              Initialize a workbranch project"
  assert_contains "$out" "list              List configured repos and task workspaces"
  assert_contains "$out" "add <task>        Create a task workspace"
  assert_contains "$out" "remove <task>     Remove task worktrees and local task branches"
  assert_not_contains "$out" "resume <task>"
  assert_contains "$out" "Git:"
  assert_contains "$out" "status            Show remote diff, task diff, and dirty state"
  assert_contains "$out" "  vertical"
  assert_contains "$out" "pull              Pull remote base branches into main worktrees"
  assert_contains "$out" "push              Push base branches to origin"
  assert_contains "$out" "push <task>       Push task branches to origin"
  assert_contains "$out" "  horizontal"
  assert_contains "$out" "update            Update every task workspace from local base worktrees"
  assert_contains "$out" "update --all      Update every task workspace from local base worktrees"
  assert_contains "$out" "update <task>     Update one task workspace from local base worktrees"
  assert_contains "$out" "land <task>       Land task branches into base branches"
  assert_contains "$out" "  common"
  assert_contains "$out" "--repo <repo>     Limit operation to one repo; otherwise all repos"
  assert_contains "$out" "Tool:"
  assert_contains "$out" "path <task>       Print a task workspace path"
  assert_contains "$out" "finder <task>     Open a task workspace in Finder"
  assert_contains "$out" "ide <task>        Open task repo worktrees in the configured IDE"
  assert_contains "$out" "terminal <task>   Open task repo worktrees in the configured terminal"
  assert_contains "$out" "Config:"
  assert_contains "$out" "config            Create or update .workbranch.config without cloning repos"
  assert_contains "$out" "config ide        Update only the configured IDE command"
  assert_contains "$out" "config terminal   Update only the configured terminal command"
  assert_contains "$out" "config --rewrite  Rewrite config to current format without prompts"
  assert_contains "$out" "Other:"
  assert_contains "$out" "help              Show this help"
  assert_contains "$out" "-v, --version     Show the installed workbranch version"
  assert_contains "$out" "version           Show the installed workbranch version"
  assert_not_contains "$out" "// vertical"
  assert_not_contains "$out" "// horizontal"
  assert_not_contains "$out" "// common"
  case "$out" in
    *$'

'*) fail "expected compact help without blank lines; got: $out" ;;
  esac
  case "$out" in
    *"Workspace:"*"init              Initialize a workbranch project"*"list              List configured repos and task workspaces"*"add <task>        Create a task workspace"*"remove <task>     Remove task worktrees and local task branches"*"Git:"*"status            Show remote diff, task diff, and dirty state"*"  vertical"*"Tool:"*"path <task>       Print a task workspace path"*"finder <task>     Open a task workspace in Finder"*"ide <task>        Open task repo worktrees in the configured IDE"*"terminal <task>   Open task repo worktrees in the configured terminal"*"Config:"*"config            Create or update .workbranch.config without cloning repos"*"config ide        Update only the configured IDE command"*"config terminal   Update only the configured terminal command"*"config --rewrite  Rewrite config to current format without prompts"*"Other:"*) ;;
    *) fail "expected workspace, git, tool, config, and other group ordering; got: $out" ;;
  esac
}

test_version_reports_release_manifest_version() {
  expected=$(manifest_version)
  [ -n "$expected" ] || fail "could not read release manifest version"

  out=$(run_expect_success "$WORKBRANCH" version)
  [ "$out" = "workbranch $expected" ] || fail "expected version output 'workbranch $expected', got: $out"

  out=$(run_expect_success "$WORKBRANCH" --version)
  [ "$out" = "workbranch $expected" ] || fail "expected --version output 'workbranch $expected', got: $out"

  out=$(run_expect_success "$WORKBRANCH" -v)
  [ "$out" = "workbranch $expected" ] || fail "expected -v output 'workbranch $expected', got: $out"
}
