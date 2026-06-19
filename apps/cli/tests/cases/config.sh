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

test_config_reads_and_writes_ide_terminal_commands() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  cat >> "$project/.workbranch.config" <<'CONFIG'
IDE open -a "Visual Studio Code"
TERMINAL open -a Warp
CONFIG

  out=$(run_expect_success "$WORKBRANCH" config --rewrite)
  assert_contains "$out" "[+] Config rewritten:"
  config=$(cat "$project/.workbranch.config")
  assert_contains "$config" 'IDE open -a "Visual Studio Code"'
  assert_contains "$config" "TERMINAL open -a Warp"
}

test_config_ide_can_set_custom_command_without_prompting_repos() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  input=$(printf '%s
%s
' "8" "code --reuse-window")
  out=$(printf '%s' "$input" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" config ide)
  assert_contains "$out" "[*] IDE command:"
  assert_not_contains "$out" "Base repo branch for frontend"
  assert_contains "$out" "[+] Config updated:"
  assert_contains "$(cat "$project/.workbranch.config")" "IDE code --reuse-window"
}


test_config_ide_preset_uses_superset_level1_order() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  out=$(printf '%s
' "1" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" config ide)
  assert_contains "$out" "[*] IDE command:"
  assert_contains "$out" "1) Cursor (open -na Cursor --args --new-window)"
  assert_contains "$out" '2) Antigravity (open -na "Antigravity IDE" --args --new-window)'
  assert_contains "$out" "3) Windsurf (open -na Windsurf --args --new-window)"
  assert_contains "$out" "4) Zed (open -na Zed)"
  assert_contains "$out" '5) Sublime Text (open -na "Sublime Text")'
  assert_contains "$out" "6) Xcode (open -na Xcode)"
  assert_contains "$out" '7) VS Code (open -na "Visual Studio Code" --args --new-window'
  assert_contains "$out" "8) Custom command"
  assert_contains "$out" "9) Clear"
  assert_contains "$out" "[+] Config updated:"
  assert_contains "$(cat "$project/.workbranch.config")" "IDE open -na Cursor --args --new-window"
}

test_config_tool_preset_names_are_colored() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  out=$(printf '\n' | env -u NO_COLOR WORKBRANCH_COLOR=always WORKBRANCH_TEST_PLATFORM=macos "$WORKBRANCH" config ide 2>&1)
  assert_contains "$out" $'1) \033[0;36mCursor\033[0m (open -na Cursor --args --new-window)'
  assert_contains "$out" $'2) \033[0;36mAntigravity\033[0m (open -na "Antigravity IDE" --args --new-window)'
  assert_contains "$out" $'3) \033[0;36mWindsurf\033[0m (open -na Windsurf --args --new-window)'
  assert_contains "$out" $'4) \033[0;36mZed\033[0m (open -na Zed)'
  assert_contains "$out" $'5) \033[0;36mSublime Text\033[0m (open -na "Sublime Text")'
  assert_contains "$out" $'6) \033[0;36mXcode\033[0m (open -na Xcode)'
  assert_contains "$out" $'7) \033[0;36mVS Code\033[0m (open -na "Visual Studio Code" --args --new-window)'

  out=$(printf '\n' | env -u NO_COLOR WORKBRANCH_COLOR=always WORKBRANCH_TEST_PLATFORM=macos "$WORKBRANCH" config terminal 2>&1)
  assert_contains "$out" $'1) \033[0;36miTerm\033[0m (open -a iTerm)'
  assert_contains "$out" $'2) \033[0;36mWarp\033[0m (open -a Warp)'
  assert_contains "$out" $'3) \033[0;36mTerminal.app\033[0m (open -a Terminal)'
  assert_contains "$out" $'4) \033[0;36mGhostty\033[0m (open -a Ghostty)'
  }

test_config_terminal_can_clear_without_removing_ide() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  cat >> "$project/.workbranch.config" <<'CONFIG'
IDE open -a Cursor
TERMINAL open -a Warp
CONFIG

  out=$(printf '%s
' "6" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" config terminal)
  assert_contains "$out" "[*] Terminal command:"
  assert_contains "$out" "[+] Config updated:"
  config=$(cat "$project/.workbranch.config")
  assert_contains "$config" "IDE open -a Cursor"
  assert_not_contains "$config" "TERMINAL open -a Warp"
}

test_config_tool_targets_are_macos_only() {
  out=$(WORKBRANCH_TEST_FORCE_TTY_STDIN=1 WORKBRANCH_TEST_PLATFORM=linux run_expect_fail "$WORKBRANCH" config ide)
  assert_contains "$out" "workbranch config ide is only supported on macOS; core workbranch commands support macOS, Linux, and WSL"
  assert_not_contains "$out" "no enclosing workbranch project found"

  out=$(WORKBRANCH_TEST_FORCE_TTY_STDIN=1 WORKBRANCH_TEST_PLATFORM=other run_expect_fail "$WORKBRANCH" config ide)
  assert_contains "$out" "workbranch config ide is only supported on macOS; core workbranch commands support macOS, Linux, and WSL"
  assert_not_contains "$out" "unsupported platform: other"

  out=$(WORKBRANCH_TEST_FORCE_TTY_STDIN=1 WORKBRANCH_TEST_PLATFORM=wsl run_expect_fail "$WORKBRANCH" config terminal)
  assert_contains "$out" "workbranch config terminal is only supported on macOS; core workbranch commands support macOS, Linux, and WSL"
  assert_not_contains "$out" "no enclosing workbranch project found"
}



test_config_language_updates_preferred_language_only() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  cat >> "$project/.workbranch.config" <<'CONFIG'
IDE open -a Cursor
TERMINAL open -a Warp
PREFERRED_LANGUAGE en
CONFIG

  out=$(printf '%s\n' "2" | run_expect_success "$WORKBRANCH" config language)
  assert_contains "$out" "[*] Preferred language"
  assert_contains "$out" "1) English"
  assert_contains "$out" "2) 한글"
  assert_contains "$out" "[+] Config updated:"
  config=$(cat "$project/.workbranch.config")
  assert_contains "$config" "PREFERRED_LANGUAGE ko"
  assert_contains "$config" "IDE open -a Cursor"
  assert_contains "$config" "TERMINAL open -a Warp"
}

test_config_rejects_invalid_preferred_language() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  cat >> "$project/.workbranch.config" <<'CONFIG'
PREFERRED_LANGUAGE jp
CONFIG

  out=$(run_expect_fail "$WORKBRANCH" list)
  assert_contains "$out" "invalid PREFERRED_LANGUAGE 'jp'"
}

test_config_base_checks_out_changed_base_branches_before_add() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feature/cpq parent-frontend
  commit_to_remote_branch backend feature/cpq parent-backend

  out=$(printf '%s\n%s\n' "feature/cpq" "feature/cpq" | run_expect_success "$WORKBRANCH" config base)
  assert_contains "$out" "[*] Base branches"
  assert_contains "$out" "[*] _base/frontend current branch: master"
  assert_contains "$out" "[+] Base branch ready: _base/frontend -> feature/cpq"
  assert_contains "$out" "[+] Config updated:"
  assert_not_contains "$out" "Existing cloned base worktrees are not checked out automatically."
  assert_contains "$(cat "$project/.workbranch.config")" "REPO frontend $TMP_ROOT/remotes/frontend.git feature/cpq"
  assert_contains "$(cat "$project/.workbranch.config")" "REPO backend $TMP_ROOT/remotes/backend.git feature/cpq"
  assert_branch "$project/_base/frontend" "feature/cpq"
  assert_branch "$project/_base/backend" "feature/cpq"

  out=$(printf '\n\n' | "$WORKBRANCH" add feat-task1 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "add after config base failed: $out"
  assert_contains "$out" "  base branch: feature/cpq"
  assert_contains "$out" "  task repo branch [feature/cpq-task1]"
  assert_branch "$project/feat-task1/frontend" "feature/cpq-task1"
  assert_branch "$project/feat-task1/backend" "feature/cpq-task1"
}

test_config_base_preflights_fast_forward_before_checkout() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feature/cpq parent-frontend
  commit_to_remote_branch backend feature/cpq parent-backend

  git -C "$project/_base/backend" fetch origin >/dev/null 2>&1
  git -C "$project/_base/backend" checkout -b feature/cpq origin/feature/cpq >/dev/null 2>&1
  git -C "$project/_base/backend" config user.name "Workbranch Test"
  git -C "$project/_base/backend" config user.email "workbranch-test@example.com"
  printf '%s\n' "local backend divergence" > "$project/_base/backend/local-divergence.txt"
  git -C "$project/_base/backend" add local-divergence.txt
  git -C "$project/_base/backend" commit -m "local backend divergence" >/dev/null
  git -C "$project/_base/backend" checkout master >/dev/null 2>&1
  commit_to_remote_branch backend feature/cpq remote-backend-divergence

  out=$(printf '%s\n%s\n' "feature/cpq" "feature/cpq" | run_expect_fail "$WORKBRANCH" config base)
  assert_contains "$out" "Cannot config base: preflight failed"
  assert_contains "$out" "_base/backend cannot fast-forward pull: feature/cpq and origin/feature/cpq diverged"
  assert_branch "$project/_base/frontend" "master"
  assert_branch "$project/_base/backend" "master"
  assert_not_exists "$project/_base/frontend/parent-frontend.txt"
  assert_contains "$(cat "$project/.workbranch.config")" "REPO frontend $TMP_ROOT/remotes/frontend.git master"
  assert_contains "$(cat "$project/.workbranch.config")" "REPO backend $TMP_ROOT/remotes/backend.git master"
}

test_config_base_pulls_when_branch_already_checked_out() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  commit_to_remote_master frontend config-base-rerun-frontend
  commit_to_remote_master backend config-base-rerun-backend
  remote_frontend_head=$(git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse master)
  remote_backend_head=$(git --git-dir="$TMP_ROOT/remotes/backend.git" rev-parse master)

  out=$(printf '\n\n' | run_expect_success "$WORKBRANCH" config base)
  assert_contains "$out" "[*] Base branches"
  assert_contains "$out" "[+] Base branch ready: _base/frontend -> master"
  assert_contains "$out" "[+] Base branch ready: _base/backend -> master"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$remote_frontend_head" ] || fail "frontend base did not pull while already on master"
  [ "$(git -C "$project/_base/backend" rev-parse HEAD)" = "$remote_backend_head" ] || fail "backend base did not pull while already on master"
  assert_file "$project/_base/frontend/config-base-rerun-frontend.txt"
  assert_file "$project/_base/backend/config-base-rerun-backend.txt"
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

test_full_config_repo_setup_change_does_not_touch_unchanged_dirty_base() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  printf '%s\n' "local dirty base edit" > "$project/_base/frontend/dirty.txt"

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "" "pnpm install --frozen-lockfile" "" "" | WORKBRANCH_TEST_PLATFORM=linux run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[*] Repositories"
  assert_not_contains "$out" "Cannot config base: preflight failed"
  assert_not_contains "$out" "Base branch ready:"
  assert_contains "$out" "[+] Config updated:"
  assert_contains "$(cat "$project/.workbranch.config")" "REPO_SETUP frontend pnpm install --frozen-lockfile"
  assert_file "$project/_base/frontend/dirty.txt"
}

test_full_config_base_branch_change_auto_applies_without_stale_manual_guidance() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feature/cpq parent-frontend
  commit_to_remote_branch backend feature/cpq parent-backend

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "feature/cpq" "" "feature/cpq" "" | WORKBRANCH_TEST_PLATFORM=linux run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[+] Base branch ready: _base/frontend -> feature/cpq"
  assert_contains "$out" "[+] Base branch ready: _base/backend -> feature/cpq"
  assert_not_contains "$out" "Base branch changes were saved in config only."
  assert_not_contains "$out" "Existing cloned base worktrees are not checked out automatically."
  assert_not_contains "$out" "Update each changed base worktree before running git operations:"
  assert_branch "$project/_base/frontend" "feature/cpq"
  assert_branch "$project/_base/backend" "feature/cpq"
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
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" config)
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

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "" "" "" 'printf frontend > repo.txt' "" "" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[*] Project name [fullstack]:"
  assert_contains "$out" "[*] Main worktrees dir [_base]:"
  assert_not_contains "$out" "[*] Branch prefix [feature]:"
  assert_contains "$out" "[*] IDE command:"
  assert_contains "$out" "[*] Choose IDE [keep]:"
  assert_contains "$out" "[*] Terminal command:"
  assert_contains "$out" "[*] Choose terminal [keep]:"
  assert_contains "$out" "[*] Base repo branch for frontend [master]:"
  assert_contains "$out" "[*] Repo setup command for frontend [pnpm install] (example, Enter to skip):"
  assert_contains "$out" "[*] Base repo branch for backend [master]:"
  assert_contains "$out" "[*] Repo setup command for backend [pnpm install] (example, Enter to skip):"
  assert_not_contains "$out" "Task setup command"
  assert_contains "$out" "$(printf '%s \n\n%s' "[*] Repo setup command for frontend [pnpm install] (example, Enter to skip):" "[*] Base repo branch for backend [master]:")"
  assert_contains "$out" "$(printf '%s \n\n%s' "[*] Repo setup command for backend [pnpm install] (example, Enter to skip):" "[+] Config updated:")"
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

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "" "" "" "" "" "" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[+] Config updated:"
  assert_contains "$(cat "$project/.workbranch.config")" "BRANCH_PREFIX ticket"
  assert_not_contains "$out" "Branch prefix [ticket]"
  assert_contains "$out" "Legacy branch prefix: ticket (kept for existing shorthand defaults)"
}

test_config_rejects_main_worktrees_dir_change_when_base_worktrees_exist() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  out=$(printf '%s\n%s\n' "" "_main" | WORKBRANCH_TEST_PLATFORM=macos run_expect_fail "$WORKBRANCH" config)
  assert_contains "$out" "cannot change MAIN_WORKTREES_DIR while base worktrees exist: _base"
  assert_contains "$out" "remove or move existing base worktrees before changing it"
  assert_contains "$(cat "$project/.workbranch.config")" "MAIN_WORKTREES_DIR _base"
  assert_not_contains "$(cat "$project/.workbranch.config")" "MAIN_WORKTREES_DIR _main"

  out=$(run_expect_success "$WORKBRANCH" status)
  assert_contains "$out" "[*] Task workspaces"
  assert_contains "$out" "[*] (none)"
  assert_not_contains "$out" "[*] _base"
}

test_config_base_checks_out_configured_base_branch_for_cloned_repo() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  commit_to_remote_branch frontend feature/cpq parent-frontend
  commit_to_remote_branch backend feature/cpq parent-backend
  sed -i.bak 's/ master$/ feature\/cpq/' "$project/.workbranch.config"
  rm -f "$project/.workbranch.config.bak"

  out=$(printf '%s\n%s\n' "" "" | run_expect_success "$WORKBRANCH" config base)
  assert_contains "$out" "[*] _base/frontend current branch: master"
  assert_contains "$out" "[+] Config updated:"
  assert_contains "$out" "[+] Base branch ready: _base/frontend -> feature/cpq"
  assert_contains "$out" "[+] Base branch ready: _base/backend -> feature/cpq"
  assert_not_contains "$out" "Existing cloned base worktrees are not checked out automatically."
  assert_contains "$(cat "$project/.workbranch.config")" "REPO frontend $TMP_ROOT/remotes/frontend.git feature/cpq"
  assert_branch "$project/_base/frontend" "feature/cpq"
  assert_branch "$project/_base/backend" "feature/cpq"
}

test_repo_setup_can_be_configured_and_run_per_repo() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  frontend_cmd='printf "%s:%s:%s\n" "$WORKBRANCH_REPO" "$WORKBRANCH_TASK" "$(basename "$PWD")" >> "$WORKBRANCH_TASK_DIR/setup.log"; printf "%s\n" "$WORKBRANCH_REPO_DIR" > repo-setup-dir.txt'
  backend_cmd='printf "%s:%s:%s\n" "$WORKBRANCH_REPO" "$WORKBRANCH_TASK" "$(basename "$PWD")" >> "$WORKBRANCH_TASK_DIR/setup.log"; printf "%s\n" "$WORKBRANCH_BASE_REPO_DIR" > repo-base-dir.txt'

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "" "" "" "$frontend_cmd" "" "$backend_cmd" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" config)
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

  out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "" "" "" "" "" "--clear" "" "" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" config)
  assert_contains "$out" "[+] Config updated:"
  config=$(cat "$project/.workbranch.config")
  assert_not_contains "$config" "REPO_SETUP frontend"
  assert_contains "$config" "REPO_SETUP backend printf backend > repo.txt"
}
