# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

test_display_default_error_output_has_no_ansi() {
  out=$(run_expect_fail "$WORKBRANCH" nope)
  assert_contains "$out" "[-] Error: unknown command: nope"
  assert_not_contains "$out" $'\033['
}

test_display_forced_color_colors_error_prefix() {
  out=$(env -u NO_COLOR WORKBRANCH_COLOR=always "$WORKBRANCH" nope 2>&1)
  rc=$?
  [ $rc -ne 0 ] || fail "expected failure for unknown command"
  assert_contains "$out" $'\033['
  assert_contains "$out" "unknown command: nope"
}

test_display_no_color_overrides_forced_color() {
  out=$(NO_COLOR=1 WORKBRANCH_COLOR=always "$WORKBRANCH" nope 2>&1)
  rc=$?
  [ $rc -ne 0 ] || fail "expected failure for unknown command"
  assert_contains "$out" "[-] Error: unknown command: nope"
  assert_not_contains "$out" $'\033['
}

test_display_auto_redirected_stderr_has_no_ansi() {
  command -v script >/dev/null 2>&1 || fail "script command is required for TTY display test"
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  err="$TMP_ROOT/err.log"

  script -q /dev/null sh -c 'err=$1; shift; TERM=xterm env -u NO_COLOR WORKBRANCH_COLOR=auto "$@" 2>"$err"' sh "$err" "$WORKBRANCH" nope >/dev/null 2>&1 || true
  out=$(cat "$err")
  assert_contains "$out" "unknown command: nope"
  assert_not_contains "$out" $'\033['
}

test_display_color_never_disables_color() {
  out=$(WORKBRANCH_COLOR=never "$WORKBRANCH" help 2>&1)
  assert_not_contains "$out" $'\033['
  assert_not_contains "$out" "Task-based Git worktrees, made easy."
  assert_contains "$out" "Workspace:"
}

test_display_forced_color_help_shows_banner_and_sections() {
  out=$(env -u NO_COLOR WORKBRANCH_COLOR=always "$WORKBRANCH" help 2>&1)
  assert_contains "$out" $'\033['
  assert_contains "$out" "__        __         _    _                         _"
  assert_contains "$out" '  \ V  V / (_) | |  |   <| |_) | | | (_| | | | | (__| | | |'
  assert_not_contains "$out" "Workbranch"
  assert_contains "$out" $'|_| |_|\n\033[0m\n\033[0;90m                       Task-based Git worktrees, made easy.'
  assert_contains "$out" "➤ Workspace"
  assert_contains "$out" "init              Initialize a workbranch project"
  assert_contains "$out" "➤ Git"
}

test_display_no_color_suppresses_enhanced_help() {
  out=$(NO_COLOR=1 WORKBRANCH_COLOR=always "$WORKBRANCH" help 2>&1)
  assert_not_contains "$out" $'\033['
  assert_not_contains "$out" "Task-based Git worktrees, made easy."
  assert_not_contains "$out" "➤ Workspace"
  assert_contains "$out" "Workspace:"
}

test_display_forced_color_status_uses_sections_and_colored_states() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '%s\n' scratch > "$project/_base/frontend/scratch.txt"

  out=$(env -u NO_COLOR WORKBRANCH_COLOR=always "$WORKBRANCH" status 2>&1)
  assert_contains "$out" $'\033['
  assert_contains "$out" "➤ Base worktrees"
  assert_contains "$out" "➤ Task workspaces"
  assert_contains "$out" $'\033[0;90mrepo'
  assert_contains "$out" $'\033[0;33muntracked\033[0m'
  assert_contains "$out" $'\033[0;32mclean\033[0m'
}

test_display_auto_tty_status_preserves_table_colors() {
  command -v script >/dev/null 2>&1 || fail "script command is required for TTY display test"
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '%s\n' scratch > "$project/_base/frontend/scratch.txt"

  out=$(script -q /dev/null sh -c 'cd "$1" && shift && exec "$@"' sh "$project" env -u NO_COLOR WORKBRANCH_COLOR=auto "$WORKBRANCH" status 2>&1)
  assert_contains "$out" "➤ Base worktrees"
  assert_contains "$out" $'\033[0;90mrepo'
  assert_contains "$out" $'\033[0;33muntracked\033[0m'
  assert_contains "$out" $'\033[0;32mclean\033[0m'
}

test_display_forced_color_init_shows_banner_and_sections() {
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
n
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | env -u NO_COLOR WORKBRANCH_COLOR=always "$WORKBRANCH" init 2>&1)
  rc=$?
  [ $rc -eq 0 ] || fail "expected init cancellation to succeed: $out"
  assert_contains "$out" $'\033['
  assert_contains "$out" "Task-based Git worktrees, made easy."
  assert_contains "$out" "➤ Project"
  assert_contains "$out" "➤ Repositories"
  assert_contains "$out" "➤ Summary"
  assert_contains "$out" $'\033[0;34m[*]\033[0m Target directory'
}

test_display_forced_color_preflight_guidance_is_colored() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null
  printf '%s\n' dirty > "$project/login/frontend/dirty.txt"

  out=$(env -u NO_COLOR WORKBRANCH_COLOR=always "$WORKBRANCH" remove login 2>&1)
  rc=$?
  [ $rc -ne 0 ] || fail "expected remove to fail on dirty task worktree"
  assert_contains "$out" $'\033['
  assert_contains "$out" "Cannot remove: preflight failed"
  assert_contains "$out" "Fix these worktrees, then retry"
}

test_display_forced_color_task_setup_failure_is_colored() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  printf '\nREPO_SETUP frontend false\n' >> "$project/.workbranch.config"

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(env -u NO_COLOR WORKBRANCH_COLOR=always "$WORKBRANCH" add login 2>&1)
  rc=$?
  [ $rc -ne 0 ] || fail "expected add to fail on repo setup"
  assert_contains "$out" $'\033['
  assert_contains "$out" $'\033[0;31m[-] Error:\033[0m repo setup failed'
  assert_contains "$out" "repo setup failed: login/frontend"
  assert_contains "$out" $'\033[0;34m[*]\033[0m Setup directory:'
  assert_contains "$out" $'\033[0;34m[*]\033[0m Setup command: false'
}
