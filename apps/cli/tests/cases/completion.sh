# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.

test_complete_helpers_list_tasks_repos_and_commands() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '\n\n' | "$WORKBRANCH" add feat-login >/dev/null 2>&1 || fail "add failed"

  tasks=$("$WORKBRANCH" __complete-tasks)
  repos=$("$WORKBRANCH" __complete-repos)
  commands=$("$WORKBRANCH" __complete-commands)

  assert_contains "$tasks" "feat-login"
  assert_contains "$repos" "frontend"
  assert_contains "$repos" "backend"
  assert_contains "$commands" "completion"
  assert_contains "$commands" "update"
  assert_contains "$commands" "refresh"
  assert_not_contains "$commands" "sync"
  assert_contains "$commands" "doctor"
  assert_contains "$commands" "prune"
  assert_contains "$commands" "memo"
  assert_contains "$commands" "noti"
  assert_contains "$commands" "destroy"
  assert_not_contains "$commands" "forget"
}

test_complete_helpers_are_silent_outside_project() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)

  out=$(cd "$TMP_ROOT" && "$WORKBRANCH" __complete-tasks; echo "status=$?")
  assert_contains "$out" "status=0"
  assert_not_contains "$out" "Error:"

  out=$(cd "$TMP_ROOT" && "$WORKBRANCH" __complete-repos; echo "status=$?")
  assert_contains "$out" "status=0"
  assert_not_contains "$out" "Error:"
}

test_completion_bash_emits_complete_directive() {
  out=$("$WORKBRANCH" completion bash)
  assert_contains "$out" "complete -F _workbranch workbranch"
  assert_contains "$out" "__complete-tasks"
}

test_completion_zsh_emits_compdef() {
  out=$("$WORKBRANCH" completion zsh)
  assert_contains "$out" "#compdef workbranch"
  assert_contains "$out" "__complete-tasks"
}

test_completion_requires_known_shell() {
  out=$("$WORKBRANCH" completion 2>&1; echo "status=$?")
  assert_contains "$out" "usage: workbranch completion"
  assert_contains "$out" "status=1"
}

test_completion_bash_completes_tasks_and_repos() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '\n\n' | "$WORKBRANCH" add feat-login >/dev/null 2>&1 || fail "add failed"

  completion_file="$TMP_ROOT/workbranch-completion.bash"
  "$WORKBRANCH" completion bash > "$completion_file"
  # shellcheck disable=SC1090
  . "$completion_file"

  COMP_WORDS=(workbranch update "")
  COMP_CWORD=2
  _workbranch
  assert_contains "${COMPREPLY[*]}" "feat-login"

  COMP_WORDS=(workbranch refresh "")
  COMP_CWORD=2
  _workbranch
  assert_contains "${COMPREPLY[*]}" "feat-login"

  COMP_WORDS=(workbranch refresh --repo "")
  COMP_CWORD=3
  _workbranch
  assert_contains "${COMPREPLY[*]}" "frontend"
  assert_contains "${COMPREPLY[*]}" "backend"

  COMP_WORDS=(workbranch status --repo "")
  COMP_CWORD=3
  _workbranch
  assert_contains "${COMPREPLY[*]}" "frontend"
  assert_contains "${COMPREPLY[*]}" "backend"

  COMP_WORDS=(workbranch memo "")
  COMP_CWORD=2
  _workbranch
  assert_contains "${COMPREPLY[*]}" "feat-login"

  COMP_WORDS=(workbranch noti "")
  COMP_CWORD=2
  _workbranch
  assert_contains "${COMPREPLY[*]}" "add"
  assert_contains "${COMPREPLY[*]}" "list"
  assert_contains "${COMPREPLY[*]}" "clear"

  COMP_WORDS=(workbranch noti add "")
  COMP_CWORD=3
  _workbranch
  assert_contains "${COMPREPLY[*]}" "feat-login"
}

test_completion_bash_uses_command_specific_flags() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  completion_file="$TMP_ROOT/workbranch-completion.bash"
  "$WORKBRANCH" completion bash > "$completion_file"
  # shellcheck disable=SC1090
  . "$completion_file"

  COMP_WORDS=(workbranch update --)
  COMP_CWORD=2
  _workbranch
  assert_contains "${COMPREPLY[*]}" "--all"
  assert_contains "${COMPREPLY[*]}" "--repo"
  assert_not_contains "${COMPREPLY[*]}" "--from"

  COMP_WORDS=(workbranch doctor --)
  COMP_CWORD=2
  _workbranch
  assert_contains "${COMPREPLY[*]}" "--repo"
  assert_contains "${COMPREPLY[*]}" "--fix"
  assert_not_contains "${COMPREPLY[*]}" "--all"

  COMP_WORDS=(workbranch doctor "")
  COMP_CWORD=2
  _workbranch
  assert_not_contains "${COMPREPLY[*]-}" "feat-login"

  COMP_WORDS=(workbranch refresh --)
  COMP_CWORD=2
  _workbranch
  assert_contains "${COMPREPLY[*]}" "--repo"
  assert_not_contains "${COMPREPLY[*]}" "--all"

  COMP_WORDS=(workbranch add --)
  COMP_CWORD=2
  _workbranch
  assert_contains "${COMPREPLY[*]}" "--from"
  assert_not_contains "${COMPREPLY[*]}" "--force"

  COMP_WORDS=(workbranch list --)
  COMP_CWORD=2
  _workbranch
  assert_contains "${COMPREPLY[*]}" "--json"
  assert_contains "${COMPREPLY[*]}" "--global"

  COMP_WORDS=(workbranch memo --)
  COMP_CWORD=2
  _workbranch
  assert_contains "${COMPREPLY[*]}" "--clear"
}

test_completion_fish_emits_complete_command() {
  out=$("$WORKBRANCH" completion fish)
  assert_contains "$out" "complete -c workbranch"
  assert_contains "$out" "__complete-tasks"
  assert_contains "$out" "__workbranch_seen_command refresh' -l repo"
  assert_not_contains "$out" "__workbranch_seen_command sync' -l repo"
  assert_contains "$out" "__workbranch_seen_command doctor' -l repo"
  assert_contains "$out" "__workbranch_seen_command doctor' -l fix"
  assert_contains "$out" "__workbranch_seen_command list' -l json"
  assert_contains "$out" "__workbranch_seen_command list' -l global"
  assert_contains "$out" "__workbranch_seen_command destroy' -l force"
  assert_contains "$out" "__workbranch_seen_command memo' -l clear"
  assert_contains "$out" "__workbranch_completing_noti_subcommand' -a 'add list clear"
  assert_contains "$out" "__workbranch_completing_noti_task' -a '(__workbranch_complete_tasks)"
}

test_completion_fish_completes_partial_subcommands() {
  out=$("$WORKBRANCH" completion fish)
  assert_contains "$out" "__workbranch_completing_command"
  assert_contains "$out" 'test (count $tokens) -eq 2; and test -n "$current"'
  assert_not_contains "$out" "test (count (commandline -opc)) -le 1"
}

test_completion_fish_uses_long_option_condition_for_repo_values() {
  out=$("$WORKBRANCH" completion fish)
  assert_contains "$out" "__fish_seen_argument -l repo"
  assert_not_contains "$out" "__fish_seen_argument --repo"
  assert_contains "$out" "-a '(__workbranch_complete_repos)'"
}
