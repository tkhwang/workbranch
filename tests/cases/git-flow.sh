# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.
test_full_git_flow() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  out=$(run_expect_success "$WORKBRANCH" add login)
  assert_contains "$out" "[+] Created: login/frontend"
  assert_contains "$out" "[+]   [base repo] master -> [task repo] feature/login"
  assert_contains "$out" "[+] Created: login/backend"
  assert_contains "$out" "[+]   [base repo] master -> [task repo] feature/login"
  assert_file "$project/login/frontend/.git"
  assert_file "$project/login/backend/.git"
  assert_branch "$project/login/frontend" "feature/login"
  assert_branch "$project/login/backend" "feature/login"

  out=$(run_expect_fail "$WORKBRANCH" add login)
  assert_contains "$out" "already exists"

  out=$(run_expect_success "$WORKBRANCH" list)
  assert_contains "$out" "Base: _base"
  assert_contains "$out" "    repo        base             current"
  assert_contains "$out" "$(printf '    %-11s %-16s %s' frontend master master)"
  assert_contains "$out" "$(printf '    %-11s %-16s %s' backend master master)"
  assert_contains "$out" "[*] login"
  assert_not_contains "$out" "Task: login"
  assert_contains "$out" "    repo        branch"
  assert_contains "$out" "$(printf '    %-11s %s' frontend feature/login)"
  assert_contains "$out" "$(printf '    %-11s %s' backend feature/login)"

  commit_to_remote_master frontend upstream-change
  run_expect_success "$WORKBRANCH" pull >/dev/null
  assert_file "$project/_base/frontend/upstream-change.txt"
  assert_not_exists "$project/login/frontend/upstream-change.txt"

  run_expect_success "$WORKBRANCH" update login >/dev/null
  assert_file "$project/login/frontend/upstream-change.txt"

  git -C "$project/login/frontend" config user.name "Workbranch Test"
  git -C "$project/login/frontend" config user.email "workbranch-test@example.com"
  git -C "$project/login/backend" config user.name "Workbranch Test"
  git -C "$project/login/backend" config user.email "workbranch-test@example.com"

  printf '%s\n' "task frontend" > "$project/login/frontend/task.txt"
  git -C "$project/login/frontend" add task.txt
  git -C "$project/login/frontend" commit -m "task frontend" >/dev/null
  printf '%s\n' "task backend" > "$project/login/backend/task.txt"
  git -C "$project/login/backend" add task.txt
  git -C "$project/login/backend" commit -m "task backend" >/dev/null
  run_expect_success "$WORKBRANCH" push login >/dev/null
  git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse --verify refs/heads/feature/login >/dev/null
  git --git-dir="$TMP_ROOT/remotes/backend.git" rev-parse --verify refs/heads/feature/login >/dev/null

  run_expect_success "$WORKBRANCH" remove login >/dev/null
  assert_not_exists "$project/login"
  if git -C "$project/_base/frontend" show-ref --verify --quiet refs/heads/feature/login; then
    fail "expected remove to delete local frontend feature/login branch"
  fi
  if git -C "$project/_base/backend" show-ref --verify --quiet refs/heads/feature/login; then
    fail "expected remove to delete local backend feature/login branch"
  fi
  git --git-dir="$TMP_ROOT/remotes/frontend.git" rev-parse --verify refs/heads/feature/login >/dev/null
  git --git-dir="$TMP_ROOT/remotes/backend.git" rev-parse --verify refs/heads/feature/login >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" add login)
  assert_contains "$out" "task branch already exists for repo 'frontend': feature/login"
  assert_contains "$out" "Remote origin/feature/login exists; delete it outside workbranch before adding again."
  assert_not_contains "$out" "workbranch resume"
  assert_not_exists "$project/login"
}

test_repo_scope_limits_git_commands_to_one_repo() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  commit_to_remote_master frontend frontend-upstream
  commit_to_remote_master backend backend-upstream
  run_expect_success "$WORKBRANCH" pull --repo frontend >/dev/null
  assert_file "$project/_base/frontend/frontend-upstream.txt"
  assert_not_exists "$project/_base/backend/backend-upstream.txt"

  run_expect_success "$WORKBRANCH" update login --repo frontend >/dev/null
  assert_file "$project/login/frontend/frontend-upstream.txt"
  assert_not_exists "$project/login/backend/backend-upstream.txt"

  git -C "$project/login/frontend" config user.name "Workbranch Test"
  git -C "$project/login/frontend" config user.email "workbranch-test@example.com"
  git -C "$project/login/backend" config user.name "Workbranch Test"
  git -C "$project/login/backend" config user.email "workbranch-test@example.com"
  printf '%s\n' "frontend scoped" > "$project/login/frontend/scoped.txt"
  git -C "$project/login/frontend" add scoped.txt
  git -C "$project/login/frontend" commit -m "frontend scoped" >/dev/null
  printf '%s\n' "backend scoped" > "$project/login/backend/scoped.txt"
  git -C "$project/login/backend" add scoped.txt
  git -C "$project/login/backend" commit -m "backend scoped" >/dev/null

  run_expect_success "$WORKBRANCH" push login --repo frontend >/dev/null
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" feature/login scoped.txt "frontend scoped"
  assert_remote_missing_file "$TMP_ROOT/remotes/backend.git" feature/login scoped.txt

  run_expect_success "$WORKBRANCH" land login --repo frontend >/dev/null
  run_expect_success "$WORKBRANCH" push --repo frontend >/dev/null
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" master scoped.txt "frontend scoped"
  assert_remote_missing_file "$TMP_ROOT/remotes/backend.git" master scoped.txt
}

test_land_preflight_blocks_all_repos_before_partial_land() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add login >/dev/null

  git -C "$project/login/frontend" config user.name "Workbranch Test"
  git -C "$project/login/frontend" config user.email "workbranch-test@example.com"
  git -C "$project/login/backend" config user.name "Workbranch Test"
  git -C "$project/login/backend" config user.email "workbranch-test@example.com"
  git -C "$project/_base/backend" config user.name "Workbranch Test"
  git -C "$project/_base/backend" config user.email "workbranch-test@example.com"

  printf '%s\n' "frontend task" > "$project/login/frontend/frontend-task.txt"
  git -C "$project/login/frontend" add frontend-task.txt
  git -C "$project/login/frontend" commit -m "frontend task" >/dev/null

  printf '%s\n' "backend task" > "$project/login/backend/backend-task.txt"
  git -C "$project/login/backend" add backend-task.txt
  git -C "$project/login/backend" commit -m "backend task" >/dev/null

  printf '%s\n' "backend base" > "$project/_base/backend/backend-base.txt"
  git -C "$project/_base/backend" add backend-base.txt
  git -C "$project/_base/backend" commit -m "backend base" >/dev/null

  out=$(run_expect_fail "$WORKBRANCH" land login)
  assert_contains "$out" "Cannot land: preflight failed"
  assert_contains "$out" "login/backend cannot fast-forward land"
  assert_contains "$out" "workbranch update login --repo backend"
  assert_contains "$out" "If update reports a rebase conflict, resolve it manually with the shown rebase guidance, then retry land."
  assert_not_exists "$project/_base/frontend/frontend-task.txt"
  assert_not_exists "$project/_base/backend/backend-task.txt"
}

test_finalize_pulls_updates_and_lands_without_push_or_remove() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null

  commit_to_remote_master frontend finalize-upstream

  git -C "$project/feat-login/frontend" config user.name "Workbranch Test"
  git -C "$project/feat-login/frontend" config user.email "workbranch-test@example.com"
  git -C "$project/feat-login/backend" config user.name "Workbranch Test"
  git -C "$project/feat-login/backend" config user.email "workbranch-test@example.com"
  printf '%s\n' "finalize frontend" > "$project/feat-login/frontend/finalize-task.txt"
  git -C "$project/feat-login/frontend" add finalize-task.txt
  git -C "$project/feat-login/frontend" commit -m "finalize frontend" >/dev/null
  printf '%s\n' "finalize backend" > "$project/feat-login/backend/finalize-task.txt"
  git -C "$project/feat-login/backend" add finalize-task.txt
  git -C "$project/feat-login/backend" commit -m "finalize backend" >/dev/null

  out=$(run_expect_success "$WORKBRANCH" finalize feat-login)
  assert_contains "$out" "Pulling base branches"
  assert_contains "$out" "Updating task workspace"
  assert_contains "$out" "Landing task"
  assert_file "$project/_base/frontend/finalize-upstream.txt"
  assert_file "$project/_base/frontend/finalize-task.txt"
  assert_file "$project/_base/backend/finalize-task.txt"
  assert_file "$project/feat-login/frontend/finalize-task.txt"
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" master finalize-task.txt
  assert_remote_missing_file "$TMP_ROOT/remotes/backend.git" master finalize-task.txt
}

test_finalize_preflight_blocks_pull_before_dirty_task_update() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-login >/dev/null
  before_head=$(git -C "$project/_base/frontend" rev-parse HEAD)
  commit_to_remote_master frontend finalize-should-not-pull
  printf '%s\n' "dirty task" > "$project/feat-login/backend/dirty.txt"

  out=$(run_expect_fail "$WORKBRANCH" finalize feat-login)
  assert_contains "$out" "Cannot finalize: preflight failed"
  assert_contains "$out" "feat-login/backend dirty worktree"
  [ "$(git -C "$project/_base/frontend" rev-parse HEAD)" = "$before_head" ] || fail "base advanced before finalize preflight failure"
  assert_not_exists "$project/_base/frontend/finalize-should-not-pull.txt"
}

test_push_supports_task_and_base_branches_after_fast_forward_merge() {
  new_fixture
  project="$FIXTURE_PROJECT"
  commit_to_remote_branch frontend feature/cpq parent-frontend
  cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature

REPO frontend $TMP_ROOT/remotes/frontend.git feature/cpq
REPO backend $TMP_ROOT/remotes/backend.git master
CONFIG
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add ui >/dev/null
  assert_branch "$project/ui/frontend" "feature/cpq-ui"
  assert_branch "$project/ui/backend" "feature/ui"
  assert_file "$project/ui/frontend/parent-frontend.txt"

  git -C "$project/ui/frontend" config user.name "Workbranch Test"
  git -C "$project/ui/frontend" config user.email "workbranch-test@example.com"
  git -C "$project/ui/backend" config user.name "Workbranch Test"
  git -C "$project/ui/backend" config user.email "workbranch-test@example.com"
  printf '%s\n' "landed frontend" > "$project/ui/frontend/landed.txt"
  git -C "$project/ui/frontend" add landed.txt
  git -C "$project/ui/frontend" commit -m "landed frontend" >/dev/null
  printf '%s\n' "feature backend" > "$project/ui/backend/normal.txt"
  git -C "$project/ui/backend" add normal.txt
  git -C "$project/ui/backend" commit -m "feature backend" >/dev/null

  out=$(run_expect_success "$WORKBRANCH" push ui)
  assert_contains "$out" "[*] Pushing ui/frontend: feature/cpq-ui"
  assert_contains "$out" "[*] Pushing ui/backend: feature/ui"
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" feature/cpq-ui landed.txt "landed frontend"
  assert_remote_file "$TMP_ROOT/remotes/backend.git" feature/ui normal.txt "feature backend"
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" feature/cpq landed.txt
  run_expect_success "$WORKBRANCH" land ui >/dev/null
  assert_branch "$project/_base/frontend" "feature/cpq"
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" feature/cpq landed.txt
  assert_remote_missing_file "$TMP_ROOT/remotes/backend.git" master normal.txt

  out=$(run_expect_success "$WORKBRANCH" push)
  assert_contains "$out" "[*] Pushing frontend: feature/cpq"
  assert_contains "$out" "[*] Pushing backend: master"
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" feature/cpq landed.txt "landed frontend"
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" master landed.txt
  assert_remote_file "$TMP_ROOT/remotes/backend.git" master normal.txt "feature backend"
}

test_pull_preflight_requires_base_worktree_on_configured_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  git -C "$project/_base/frontend" checkout -b unrelated >/dev/null 2>&1
  commit_to_remote_master frontend pull-should-not-touch-unrelated

  out=$(run_expect_fail "$WORKBRANCH" pull --repo frontend)
  assert_contains "$out" "Cannot pull: preflight failed"
  assert_contains "$out" "_base/frontend expected branch master, got unrelated"
  assert_not_exists "$project/_base/frontend/pull-should-not-touch-unrelated.txt"
}

test_pull_preflight_guides_diverged_base_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null

  git -C "$project/_base/frontend" config user.name "Workbranch Test"
  git -C "$project/_base/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "local frontend divergence" > "$project/_base/frontend/local-divergence.txt"
  git -C "$project/_base/frontend" add local-divergence.txt
  git -C "$project/_base/frontend" commit -m "local frontend divergence" >/dev/null
  commit_to_remote_master frontend remote-frontend-divergence

  out=$(run_expect_fail "$WORKBRANCH" pull --repo frontend)
  assert_contains "$out" "Cannot pull: preflight failed"
  assert_contains "$out" "_base/frontend cannot fast-forward pull: HEAD and origin/master diverged"
  assert_contains "$out" "Inspect manually:"
  assert_contains "$out" "git -C _base/frontend fetch origin"
  assert_contains "$out" "git -C _base/frontend log --oneline --left-right HEAD...origin/master"
}

test_finalize_preflight_blocks_rebase_conflict_after_pull_without_touching_task() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add feat-conflict >/dev/null

  git -C "$project/feat-conflict/frontend" config user.name "Workbranch Test"
  git -C "$project/feat-conflict/frontend" config user.email "workbranch-test@example.com"
  printf '%s\n' "task change" > "$project/feat-conflict/frontend/README.md"
  git -C "$project/feat-conflict/frontend" add README.md
  git -C "$project/feat-conflict/frontend" commit -m "task edits readme" >/dev/null
  task_head_before=$(git -C "$project/feat-conflict/frontend" rev-parse HEAD)

  clone="$TMP_ROOT/upstream-conflict"
  git clone "$TMP_ROOT/remotes/frontend.git" "$clone" >/dev/null 2>&1
  git -C "$clone" config user.name "Workbranch Test"
  git -C "$clone" config user.email "workbranch-test@example.com"
  printf '%s\n' "base change" > "$clone/README.md"
  git -C "$clone" add README.md
  git -C "$clone" commit -m "base edits readme" >/dev/null
  git -C "$clone" push origin master >/dev/null 2>&1

  out=$(run_expect_fail "$WORKBRANCH" finalize feat-conflict --repo frontend)
  assert_contains "$out" "Pulling base branches"
  assert_contains "$out" "Cannot finalize: preflight failed"
  assert_contains "$out" "feat-conflict/frontend cannot rebase onto _base/frontend"
  assert_contains "$out" "Resolve manually:"
  assert_contains "$out" 'git -C feat-conflict/frontend rebase "$(git -C _base/frontend rev-parse HEAD)"'
  assert_contains "$out" "workbranch update feat-conflict --repo frontend"
  assert_not_contains "$out" "Updating task workspace"
  [ "$(git -C "$project/feat-conflict/frontend" rev-parse HEAD)" = "$task_head_before" ] || fail "task HEAD changed after conflict preflight"
  assert_clean "$project/feat-conflict/frontend"
  if git -C "$project/feat-conflict/frontend" status --porcelain=v1 -uno | grep -q '^UU '; then
    fail "task worktree was left with conflicts"
  fi
}
