# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.
test_invalid_config_rejected_without_execution() {
  new_fixture
  project="$FIXTURE_PROJECT"
  rm -rf "$project/_base"
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature
REPO frontend $TMP_ROOT/remotes/frontend.git master
CONFIG
  printf 'unknown $(touch %s)\n' "$TMP_ROOT/pwned" >> "$project/.workbranch.config"
  out=$(cd "$project" && run_expect_fail "$WORKBRANCH" list)
  assert_contains "$out" "unknown directive"
  assert_not_exists "$TMP_ROOT/pwned"
}

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
  assert_contains "$config" 'EDITOR open -a "Visual Studio Code"'
  assert_contains "$config" "TERMINAL open -a Warp"
}

test_config_editor_can_set_custom_command_without_prompting_repos() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  input=$(printf '%s
%s
' "4" "code --reuse-window")
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

  out=$(printf '%s
' "7" | run_expect_success "$WORKBRANCH" config terminal)
  assert_contains "$out" "[*] Terminal command:"
  assert_contains "$out" "[+] Config updated:"
  config=$(cat "$project/.workbranch.config")
  assert_contains "$config" "EDITOR open -a Cursor"
  assert_not_contains "$config" "TERMINAL open -a Warp"
}

test_config_writes_config_without_cloning() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work"
  frontend_remote=$(make_repo frontend)
  input=$(cat <<INPUT

.
fullstack
_base



frontend
$frontend_remote
master

n
Y
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "Config written"
  project="$TMP_ROOT/work/fullstack"
  assert_file "$project/.workbranch.config"
  assert_contains "$(cat "$project/.workbranch.config")" "BRANCH_PREFIX feature"
  assert_contains "$(cat "$project/.workbranch.config")" "REPO frontend $frontend_remote master"
  assert_not_exists "$project/_base"
}

test_config_rewrites_legacy_config_without_cloning() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  rm "$project/.workbranch.config"
  cat > "$project/.monotree.config" <<CONFIG
project fullstack
base_dir _base
branch_prefix feature

repo frontend $TMP_ROOT/remotes/frontend.git
base_branch frontend master
repo backend $TMP_ROOT/remotes/backend.git master
CONFIG

  out=$(run_expect_success "$WORKBRANCH" status)
  assert_contains "$out" "[*] Base worktrees"
  assert_contains "$out" "frontend    missing"

  out=$(run_expect_success "$WORKBRANCH" config --rewrite)
  assert_contains "$out" "[+] Config rewritten:"
  assert_file "$project/.workbranch.config"
  config=$(cat "$project/.workbranch.config")
  assert_contains "$config" "PROJECT_NAME fullstack"
  assert_contains "$config" "MAIN_WORKTREES_DIR _base"
  assert_contains "$config" "BRANCH_PREFIX feature"
  assert_contains "$config" "REPO frontend $TMP_ROOT/remotes/frontend.git master"
  assert_contains "$config" "REPO backend $TMP_ROOT/remotes/backend.git master"
  assert_not_exists "$project/_base"

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_success "$WORKBRANCH" status)
  assert_contains "$out" "[*] Base worktrees"
}

test_config_keeps_glob_characters_literal() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  : > "$project/maZZster"
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git ma*ster
REPO backend $TMP_ROOT/remotes/backend.git master
CONFIG

  out=$(run_expect_success "$WORKBRANCH" list)
  assert_contains "$out" "ma*ster"
  assert_not_contains "$out" "maZZster"
}

test_legacy_config_supports_project_commands_without_rewrite() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  rm "$project/.workbranch.config"
  cat > "$project/.monotree.config" <<CONFIG
project fullstack
base_dir _base
branch_prefix feature

repo frontend $TMP_ROOT/remotes/frontend.git
base_branch frontend master
repo backend $TMP_ROOT/remotes/backend.git master
CONFIG

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_success "$WORKBRANCH" list)
  assert_contains "$out" "Project: fullstack"
  assert_contains "$out" "frontend    master"
  assert_contains "$out" "backend     master"
  assert_not_exists "$project/.workbranch.config"
}

test_config_rewrites_legacy_tasktree_config_without_cloning() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  mv "$project/.workbranch.config" "$project/.tasktree.config"

  out=$(run_expect_success "$WORKBRANCH" config --rewrite)
  assert_contains "$out" "[+] Config rewritten:"
  assert_file "$project/.workbranch.config"
  assert_contains "$(cat "$project/.workbranch.config")" "PROJECT_NAME fullstack"
  assert_contains "$(cat "$project/.workbranch.config")" "REPO frontend $TMP_ROOT/remotes/frontend.git master"
  assert_not_exists "$project/_base"
}

test_task_setup_can_be_configured_and_run() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  mkdir -p "$project/scripts"
  cat > "$project/scripts/workbranch-setup.sh" <<'SCRIPT'
#!/usr/bin/env sh
set -eu
printf '%s\n' "$WORKBRANCH_PROJECT_ROOT" > "$WORKBRANCH_TASK_DIR/setup-project-root.txt"
printf '%s\n' "$WORKBRANCH_TASK" > "$WORKBRANCH_TASK_DIR/setup-task.txt"
printf '%s\n' "$WORKBRANCH_REPOS" > "$WORKBRANCH_TASK_DIR/setup-repos.txt"
SCRIPT

  printf '\nTASK_SETUP sh scripts/workbranch-setup.sh\n' >> "$project/.workbranch.config"
  assert_contains "$(cat "$project/.workbranch.config")" "TASK_SETUP sh scripts/workbranch-setup.sh"
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(run_expect_success "$WORKBRANCH" list)
  assert_not_contains "$out" "[*] Task setup:"
  assert_not_contains "$out" "sh scripts/workbranch-setup.sh"

  out=$(run_expect_success "$WORKBRANCH" add login)
  assert_contains "$out" "[*] Running task setup: sh scripts/workbranch-setup.sh"
  assert_contains "$out" "[+] Task setup completed: login"
  assert_contains "$(cat "$project/login/setup-task.txt")" "login"
  assert_contains "$(cat "$project/login/setup-repos.txt")" "frontend backend"
}

test_config_preserves_task_setup_while_prompting_repo_setup() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  printf '\nTASK_SETUP pnpm install\n' >> "$project/.workbranch.config"

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "" "" "" 'printf frontend > repo.txt' "" "" | run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[*] Project name [fullstack]:"
  assert_contains "$out" "[*] Main worktrees dir [_base]:"
  assert_not_contains "$out" "[*] Branch prefix [feature]:"
  assert_contains "$out" "[*] Editor command:"
  assert_contains "$out" "[*] Choose editor [keep]:"
  assert_contains "$out" "[*] Terminal command:"
  assert_contains "$out" "[*] Choose terminal [keep]:"
  assert_contains "$out" "[*] Base repo branch for frontend [master]:"
  assert_contains "$out" "[*] Repo setup command for frontend []:"
  assert_contains "$out" "[*] Base repo branch for backend [master]:"
  assert_contains "$out" "[*] Repo setup command for backend []:"
  assert_not_contains "$out" "Task setup command"
  assert_contains "$out" "$(printf '%s \n\n%s' "[*] Repo setup command for frontend []:" "[*] Base repo branch for backend [master]:")"
  assert_contains "$out" "$(printf '%s \n\n%s' "[*] Repo setup command for backend []:" "[+] Config updated:")"
  case "$out" in
    *"Base repo branch for frontend"*"Repo setup command for frontend"*"Base repo branch for backend"*"Repo setup command for backend"*) ;;
    *) fail "expected config to ask branch and setup per repo only; got: $out" ;;
  esac
  assert_contains "$out" "[+] Config updated:"
  config=$(cat "$project/.workbranch.config")
  assert_contains "$config" "REPO_SETUP frontend printf frontend > repo.txt"
  assert_contains "$config" "TASK_SETUP pnpm install"
}

test_config_preserves_existing_branch_prefix_without_prompting() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  sed -i.bak 's/BRANCH_PREFIX feature/BRANCH_PREFIX ticket/' "$project/.workbranch.config"
  rm -f "$project/.workbranch.config.bak"

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "" "" "" "" "" "" | run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[+] Config updated:"
  assert_contains "$(cat "$project/.workbranch.config")" "BRANCH_PREFIX ticket"
  assert_not_contains "$out" "Branch prefix [ticket]"
}

test_config_rejects_main_worktrees_dir_change_when_base_worktrees_exist() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf '%s\n%s\n' "" "_main" | run_expect_fail "$WORKBRANCH" config)
  assert_contains "$out" "cannot change MAIN_WORKTREES_DIR while base worktrees exist: _base"
  assert_contains "$out" "remove or move existing base worktrees before changing it"
  assert_contains "$(cat "$project/.workbranch.config")" "MAIN_WORKTREES_DIR _base"
  assert_not_contains "$(cat "$project/.workbranch.config")" "MAIN_WORKTREES_DIR _main"

  out=$(run_expect_success "$WORKBRANCH" status)
  assert_contains "$out" "[*] Task workspaces"
  assert_contains "$out" "[*] (none)"
  assert_not_contains "$out" "[*] _base"
}

test_config_guides_base_branch_change_for_cloned_repo() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "" "" "develop" "" "" "" | run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[*] _base/frontend current branch: master"
  assert_contains "$out" "[+] Config updated:"
  assert_contains "$out" "[*] Base branch changes were saved in config only."
  assert_contains "$out" "_base/frontend"
  assert_contains "$out" "git checkout develop"
  assert_contains "$(cat "$project/.workbranch.config")" "REPO frontend $TMP_ROOT/remotes/frontend.git develop"
}

test_repo_setup_can_be_configured_and_run_per_repo() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  frontend_cmd='printf "%s:%s:%s\n" "$WORKBRANCH_REPO" "$WORKBRANCH_TASK" "$(basename "$PWD")" >> "$WORKBRANCH_TASK_DIR/setup.log"; printf "%s\n" "$WORKBRANCH_REPO_DIR" > repo-setup-dir.txt'
  backend_cmd='printf "%s:%s:%s\n" "$WORKBRANCH_REPO" "$WORKBRANCH_TASK" "$(basename "$PWD")" >> "$WORKBRANCH_TASK_DIR/setup.log"; printf "%s\n" "$WORKBRANCH_BASE_REPO_DIR" > repo-base-dir.txt'

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "" "" "" "$frontend_cmd" "" "$backend_cmd" | run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[+] Config updated:"
  config=$(cat "$project/.workbranch.config")
  assert_contains "$config" "REPO_SETUP frontend $frontend_cmd"
  assert_contains "$config" "REPO_SETUP backend $backend_cmd"

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_success "$WORKBRANCH" add login)
  assert_contains "$out" "[*] Running repo setup: login/frontend"
  assert_contains "$out" "[*] Running repo setup: login/backend"
  assert_contains "$out" "[+] Repo setup completed: login/frontend"
  assert_contains "$out" "[+] Repo setup completed: login/backend"
  assert_contains "$(cat "$project/login/setup.log")" "frontend:login:frontend"
  assert_contains "$(cat "$project/login/setup.log")" "backend:login:backend"
  assert_contains "$(cat "$project/login/frontend/repo-setup-dir.txt")" "$project/login/frontend"
  assert_contains "$(cat "$project/login/backend/repo-base-dir.txt")" "$project/_base/backend"

}

test_repo_setup_suppresses_legacy_task_setup_fallback() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  cat >> "$project/.workbranch.config" <<'CONFIG'
TASK_SETUP printf project >> "$WORKBRANCH_TASK_DIR/setup.log"
REPO_SETUP frontend printf frontend >> "$WORKBRANCH_TASK_DIR/setup.log"
REPO_SETUP backend printf backend >> "$WORKBRANCH_TASK_DIR/setup.log"
CONFIG

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_success "$WORKBRANCH" add login)
  assert_contains "$out" "[*] Running repo setup: login/frontend"
  assert_contains "$out" "[*] Running repo setup: login/backend"
  assert_not_contains "$out" "[*] Running task setup:"
  assert_contains "$(cat "$project/login/setup.log")" "frontend"
  assert_contains "$(cat "$project/login/setup.log")" "backend"
  assert_not_contains "$(cat "$project/login/setup.log")" "project"
}

test_task_setup_failure_reports_directory_and_command() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  canonical_project=$(pwd -P)
  printf '\nTASK_SETUP false\n' >> "$project/.workbranch.config"

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_fail "$WORKBRANCH" add login)
  assert_contains "$out" "task setup failed: login"
  assert_contains "$out" "Setup directory: $canonical_project"
  assert_contains "$out" "Setup command: false"
  assert_not_contains "$out" "in the task workspace"
}

test_repo_setup_failure_reports_directory_and_command() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  canonical_project=$(pwd -P)
  printf '\nREPO_SETUP frontend false\n' >> "$project/.workbranch.config"

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_fail "$WORKBRANCH" add login)
  assert_contains "$out" "repo setup failed: login/frontend"
  assert_contains "$out" "Setup directory: $canonical_project/login/frontend"
  assert_contains "$out" "Setup command: false"
  assert_not_contains "$out" "in the task workspace"
}

test_repo_setup_can_be_cleared_without_removing_other_repo_setup() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  cat >> "$project/.workbranch.config" <<'CONFIG'
REPO_SETUP frontend printf frontend > repo.txt
REPO_SETUP backend printf backend > repo.txt
CONFIG

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "" "" "" "--clear" "" "" | run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[+] Config updated:"
  config=$(cat "$project/.workbranch.config")
  assert_not_contains "$config" "REPO_SETUP frontend"
  assert_contains "$config" "REPO_SETUP backend printf backend > repo.txt"
}

