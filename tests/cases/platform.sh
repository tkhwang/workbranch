# shellcheck shell=bash

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
  out=$(WORKBRANCH_TEST_PLATFORM=other run_expect_fail "$WORKBRANCH" list)
  assert_contains "$out" "unsupported platform: other; workbranch supports macOS, Linux, and WSL"
  assert_not_contains "$out" "no enclosing workbranch project found"
}

test_core_commands_allow_linux_and_wsl() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  out=$(WORKBRANCH_TEST_PLATFORM=linux run_expect_success "$WORKBRANCH" list)
  assert_contains "$out" "Project: fullstack"

  out=$(WORKBRANCH_TEST_PLATFORM=wsl run_expect_success "$WORKBRANCH" list)
  assert_contains "$out" "Project: fullstack"
}
