# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.
test_interactive_init_writes_config_and_clones() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work"
  frontend_remote=$(make_repo frontend)
  backend_remote=$(make_repo backend)
  input=$(cat <<INPUT

.
fullstack
_base
frontend
$frontend_remote
master

Y
backend
$backend_remote


n
Y
n

2
2
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" init)
  assert_contains "$out" "[*] Create a new workbranch project"
  assert_not_contains "$out" "[*] Before workbranch"
  assert_not_contains "$out" "Problem: separate agents do not share context, session, or file search."
  assert_contains "$out" "[*] After workbranch"
  assert_contains "$out" "[*] Setup guide"
  case "$out" in
    *"[*] After workbranch"*"[*] Setup guide"*) ;;
    *) fail "expected after, then setup guide; got: $out" ;;
  esac
  assert_contains "$out" "Project name      directory name for this workbranch workspace"
  assert_contains "$out" "Main worktrees    directory for each repo main worktree"
  assert_not_contains "$out" "Branch prefix     task branch prefix"
  assert_not_contains "$out" "[*] Default task branch prefix [feature]:"
  assert_not_contains "$out" "Default base repo checkout branch"
  assert_not_contains "$out" "Base branch is checked out in _base/<repo>."
  assert_not_contains "$out" "Task branch examples: master + login -> feature/login, feature/cpq + task1 -> feature/cpq-task1"
  assert_contains "$out" "[*] Base repo branch [main]:"
  assert_contains "$out" "[*] Base repo branch [master]:"
  assert_contains "$out" "[*] Repo setup command for frontend []:"
  assert_contains "$out" "[*] Repo setup command for backend []:"
  assert_not_contains "$out" "[*] Task branch defaults:"
  assert_not_contains "$out" "[base repo] main        -> task1 -> [task repo] feature/task1"
  assert_not_contains "$out" "[base repo] feature/XXX -> task1 -> [task repo] feature/XXX-task1"
  assert_contains "$out" "[*] Task identity:"
  assert_contains "$out" "New tasks can be created with workbranch add."
  assert_contains "$out" "folder type-detail"
  assert_contains "$out" "Each repo suggests a task branch from its base branch"
  assert_not_contains "$out" "frontend: base=master task=feature/<task>"
  assert_not_contains "$out" "backend: base=master task=feature/<task>"
  assert_contains "$out" "[*] Main worktrees directory [_base]:"
  assert_contains "$out" "fullstack                     // workbranch project"
  assert_contains "$out" "├── .workbranch.config        // config"
  assert_contains "$out" "├── _base                     // main worktrees: _base"
  assert_contains "$out" "│   ├── frontend              // - base frontend repo"
  assert_contains "$out" "│   └── backend               // - base backend repo"
  assert_contains "$out" "└── login                     // task workspace"
  assert_contains "$out" "├── frontend              // - task frontend repo"
  assert_contains "$out" "├── backend               // - task backend repo"
  assert_contains "$out" "└── <work here>           // use AI Agents in here"
  assert_contains "$out" "Result: branch operations stay grouped by feature workspace."
  assert_contains "$out" "Multi-repo bonus: use one directory for shared AI session context."
  assert_contains "$out" "Press Enter to continue"
  assert_contains "$out" "[*] Project"
  assert_contains "$out" "[*] Repo #1"
  assert_contains "$out" "[*] Repo #2"
  assert_contains "$out" "[*] Preferred language for generated task guidance [English]:"
  case "$out" in
    *"[*] Repo #1"*"[*] Preferred language for generated task guidance [English]:"*"[*] IDE command:"*) ;;
    *) fail "expected language prompt before IDE prompt after repo setup; got: $out" ;;
  esac
  case "$out" in
    *"[+] Initialized"*"[*] Add your first task now? [Y/n]:"*"[*] Preferred language for generated task guidance [English]:"*"[*] IDE command:"*"[*] Terminal command:"*) ;;
    *) fail "expected init order: base clone, add first task prompt, language preference, then tool config; got: $out" ;;
  esac
  assert_not_contains "$out" "[*] Task setup command"
  assert_not_contains "$out" "[*] Task setup:"
  assert_contains "$out" "[*] Summary"
  assert_contains "$out" "[*] Create project now? [Y/n]:"
  assert_contains "$out" "[+] Initialized"
  project="$TMP_ROOT/work/fullstack"
  assert_file "$project/.workbranch.config"
  assert_contains "$(cat "$project/.workbranch.config")" "BRANCH_PREFIX feature"
  assert_contains "$(cat "$project/.workbranch.config")" 'IDE open -na "Antigravity IDE" --args --new-window'
  assert_contains "$(cat "$project/.workbranch.config")" "TERMINAL open -a Warp"
  assert_contains "$(cat "$project/.workbranch.config")" "PREFERRED_LANGUAGE en"
  assert_contains "$(cat "$project/.workbranch.config")" "REPO frontend $frontend_remote master"
  assert_contains "$(cat "$project/.workbranch.config")" "REPO backend $backend_remote master"
  assert_dir "$project/_base/frontend/.git"
  assert_dir "$project/_base/backend/.git"
}

test_interactive_init_can_add_first_task_after_cloning() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work"
  frontend_remote=$(make_repo frontend)
  backend_remote=$(make_repo backend)
  input=$(cat <<INPUT

.
fullstack
_base
frontend
$frontend_remote
master

Y
backend
$backend_remote


n
Y

feat
login



2
2
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" init)
  project="$TMP_ROOT/work/fullstack"

  assert_contains "$out" "[+] Initialized"
  assert_contains "$out" "[*] Add your first task now? [Y/n]:"
  assert_contains "$out" "Task folder: feat-login"
  assert_contains "$out" "Created: feat-login/frontend"
  assert_contains "$out" "Created: feat-login/backend"
  case "$out" in
    *"Created: feat-login/backend"*"[*] IDE command:"*"[*] Terminal command:"*) ;;
    *) fail "expected tool config after first task creation; got: $out" ;;
  esac
  assert_file "$project/.workbranch.config"
  assert_contains "$(cat "$project/.workbranch.config")" 'IDE open -na "Antigravity IDE" --args --new-window'
  assert_contains "$(cat "$project/.workbranch.config")" "TERMINAL open -a Warp"
  assert_dir "$project/_base/frontend/.git"
  assert_dir "$project/_base/backend/.git"
  assert_branch "$project/feat-login/frontend" "feat/login"
  assert_branch "$project/feat-login/backend" "feat/login"
}

test_interactive_init_persists_ide_when_terminal_prompt_eofs() {
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
n

2
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" init)
  project="$TMP_ROOT/work/fullstack"

  assert_contains "$out" "[*] IDE command:"
  assert_contains "$out" "[*] Terminal command:"
  assert_file "$project/.workbranch.config"
  config=$(cat "$project/.workbranch.config")
  assert_contains "$config" 'IDE open -na "Antigravity IDE" --args --new-window'
  assert_not_contains "$config" "TERMINAL "
}

test_interactive_init_does_not_prompt_for_task_branch_prefix() {
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
n


INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" init)
  assert_not_contains "$out" "Default task branch prefix"
  assert_contains "$out" "[*] Task identity:"
  assert_contains "$out" "folder type-detail"
  assert_contains "$out" "Each repo suggests a task branch from its base branch"
  assert_contains "$(cat "$TMP_ROOT/work/fullstack/.workbranch.config")" "BRANCH_PREFIX feature"
}

test_interactive_init_can_cancel_before_creating_project() {
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
n
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" init)
  assert_contains "$out" "[*] Summary"
  assert_contains "$out" "[*] Create project now? [Y/n]:"
  assert_contains "$out" "[*] Cancelled."
  assert_not_contains "$out" "[*] Creating project..."
  assert_not_contains "$out" "[+] Cloned:"
  assert_not_exists "$TMP_ROOT/work/fullstack"
}

test_interactive_init_can_create_project_in_custom_target_directory() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work" "$TMP_ROOT/target"
  frontend_remote=$(make_repo frontend)
  input=$(cat <<INPUT

$TMP_ROOT/target
fullstack
_base
frontend
$frontend_remote
master

n
Y
n


INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" init)
  assert_contains "$out" "[+] Initialized"
  assert_file "$TMP_ROOT/target/fullstack/.workbranch.config"
  assert_dir "$TMP_ROOT/target/fullstack/_base/frontend/.git"
  assert_not_exists "$TMP_ROOT/work/fullstack"
}

test_interactive_init_accepts_slash_repo_base_branch() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/remotes" "$TMP_ROOT/seeds" "$TMP_ROOT/work"
  frontend_remote=$(make_repo frontend)
  git --git-dir="$frontend_remote" branch feature/cpq master
  input=$(cat <<INPUT

.
fullstack
_base
frontend
$frontend_remote
feature/cpq

n
Y
n


INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" init)
  assert_contains "$out" "[+] Initialized"
  assert_contains "$(cat "$TMP_ROOT/work/fullstack/.workbranch.config")" "REPO frontend $frontend_remote feature/cpq"
  assert_branch "$TMP_ROOT/work/fullstack/_base/frontend" "feature/cpq"
}

test_interactive_init_rejects_slash_in_main_worktrees_directory() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/work"
  input=$(cat <<INPUT

.
fullstack
feature/cpq
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | WORKBRANCH_TEST_PLATFORM=macos run_expect_fail "$WORKBRANCH" init)
  assert_contains "$out" "invalid MAIN_WORKTREES_DIR 'feature/cpq'"
}

test_interactive_init_eof_aborts_required_prompt() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/work"
  out_file="$TMP_ROOT/eof.out"
  status_file="$TMP_ROOT/eof.status"
  input=$(cat <<INPUT

.
fullstack
_base
INPUT
)

  (
    cd "$TMP_ROOT/work" || exit 1
    printf '%s' "$input" | "$WORKBRANCH" init >"$out_file" 2>&1
    printf '%s' "$?" >"$status_file"
  ) &
  pid=$!
  waited=0
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 30 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    fail "expected init to abort on EOF instead of hanging"
  fi
  wait "$pid" 2>/dev/null || true

  status=$(cat "$status_file")
  [ "$status" -ne 0 ] || fail "expected EOF during required prompt to exit non-zero"
  out=$(cat "$out_file")
  assert_contains "$out" "input aborted"
}


test_interactive_init_skips_tool_prompts_on_wsl() {
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
n
INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | WORKBRANCH_TEST_PLATFORM=wsl run_expect_success "$WORKBRANCH" init)
  assert_contains "$out" "[*] Tool app launchers are macOS-only; skipping IDE/Terminal prompts."
  assert_not_contains "$out" "[*] IDE command:"
  assert_not_contains "$out" "[*] Terminal command:"
  config=$(cat "$TMP_ROOT/work/fullstack/.workbranch.config")
  assert_not_contains "$config" "IDE "
  assert_not_contains "$config" "TERMINAL "
}


test_interactive_init_can_choose_korean_preferred_language_before_tool_config() {
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
n
ko


INPUT
)
  out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" init)
  project="$TMP_ROOT/work/fullstack"
  assert_contains "$out" "[*] Preferred language for generated task guidance [English]:"
  case "$out" in
    *"[*] Preferred language for generated task guidance [English]:"*"[*] IDE command:"*) ;;
    *) fail "expected language prompt before tool config; got: $out" ;;
  esac
  assert_contains "$(cat "$project/.workbranch.config")" "PREFERRED_LANGUAGE ko"
}
