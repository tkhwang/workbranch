# Explicit Task Branch Names Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make task branch names explicit at `workbranch add`/`resume` time while keeping the current inferred branch naming as the default.

**Architecture:** Keep the task name as the workspace folder name, but separate it from the Git branch name. Compute a default branch per repo, prompt the user with that default, validate the chosen Git ref, and persist the chosen branch names in a task-local metadata file so later commands (`status`, `push`, `update`, `land`, `remove`) use the real branch instead of re-inferencing from the folder name.

**Tech Stack:** Portable Bash, Git worktrees, generated single-file CLI via `scripts/build-workbranch.sh`, integration tests in `tests/run.sh`.

---

## Decisions

- New task folder name remains `workbranch add <task>` and must keep using `validate_safe_name`.
- Task branch name becomes an explicit per-repo value shown at add/resume time:
  - default for base `main`, `master`, `develop`, or other non-feature branches: `feature/<task>`
  - default for base `feature/<parent>`: `feature/<parent>-<task>`
  - default for base `feat/<parent>`: `feat/<parent>-<task>`
  - compatibility default for existing custom configs: if `BRANCH_PREFIX=ticket` and base is `ticket/<parent>`, default `ticket/<parent>-<task>`; otherwise `ticket/<task>`
- `feature` remains the default prefix for new projects because it is clearer for branch names than `feat`, which is more strongly associated with Conventional Commits.
- `workbranch init` and interactive `workbranch config` no longer ask the user for branch prefix.
- Existing `.workbranch.config` files with `BRANCH_PREFIX` remain readable. New configs still write `BRANCH_PREFIX feature` for compatibility, but treat it as an advanced/manual default rather than a prompted setup question.
- Chosen task branches are stored in `<task>/.workbranch.task` using repo-specific lines, for example:

```text
# Workbranch task metadata
# This file stores branch names chosen when the task workspace was created.
REPO_BRANCH frontend feature/login
REPO_BRANCH backend tkhwang/login-api
```

- Commands must resolve task branch in this order:
  1. `<task>/.workbranch.task` `REPO_BRANCH <repo> <branch>` entry
  2. existing task repo current branch, when `<task>/<repo>` already exists
  3. default branch rule above
- `workbranch resume <task>` should prompt for branch names only when it must create or restore missing task worktrees. If a metadata file already exists, use it as the prompt default. If no metadata exists, use the default branch rule.
- Existing task workspaces without metadata keep working through fallback to current branch or default inference.
- Do not commit the implementation unless the user explicitly asks.

## Files and Responsibilities

- Modify `src/workbranch/lib/validation.sh`
  - Add Git branch-name validation with `git check-ref-format --branch`.
- Create `src/workbranch/lib/task-metadata.sh`
  - Read/write `<task>/.workbranch.task`.
  - Resolve task branch names for existing and new task workspaces.
- Modify `scripts/workbranch-sources.txt`
  - Include the new metadata module before command modules.
- Modify `src/workbranch/lib/project.sh`
  - Replace hidden branch inference helpers with explicit default-branch helpers and metadata-aware resolution wrappers.
- Modify `src/workbranch/commands/add.sh`
  - Prompt branch name per repo, check branch collisions against chosen values, write metadata, then create worktrees.
- Modify `src/workbranch/commands/resume.sh`
  - Resolve/prompt branch names before preflight checks and persist metadata after creating or restoring the task directory.
- Modify `src/workbranch/commands/config.sh`
  - Stop prompting for branch prefix, remove branch-prefix change next-step output, and preserve existing `BRANCH_PREFIX` silently.
- Modify `src/workbranch/commands/init.sh`
  - Stop prompting for branch prefix, set `BRANCH_PREFIX=feature`, and update setup/summary text.
- Modify command modules that currently call `repo_task_branch_at` directly:
  - `src/workbranch/commands/push.sh`
  - `src/workbranch/commands/land.sh`
  - `src/workbranch/commands/update.sh`
  - `src/workbranch/commands/remove.sh`
  - `src/workbranch/lib/status-format.sh`
- Modify docs:
  - `README.md`
  - `docs/specs/0001-workbranch-mvp.md`
  - `docs/git-operations.md`
- Modify tests:
  - `tests/run.sh`
- Regenerate:
  - `bin/workbranch`

---

## Task 1: Add branch-name validation

**Files:**
- Modify: `src/workbranch/lib/validation.sh`
- Test: `tests/run.sh`

- [x] **Step 1: Add a failing integration test for invalid override branch names**

Add a test near existing `add` validation tests in `tests/run.sh`:

```bash
test_add_rejects_invalid_task_branch_override() {
  setup_project_fixture
  out=$(cd "$TMP_ROOT/work/fullstack" && printf 'bad branch\n' | "$WB" add login 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "expected invalid task branch override to fail"
  assert_contains "$out" "invalid task branch 'bad branch'"
  [ ! -d "$TMP_ROOT/work/fullstack/login" ] || fail "expected failed branch prompt validation not to create task dir"
}
```

Register it in the `run_test` list after the existing add validation tests.

- [x] **Step 2: Run the integration suite and verify the new test fails**

Run:

```bash
./tests/run.sh
```

Expected: FAIL at `test_add_rejects_invalid_task_branch_override` before implementation. The current harness does not support single-test filtering, so use the full suite for red/green checks unless you temporarily edit the local `run_test` list during development and revert that edit before final verification.

- [x] **Step 3: Implement branch-name validation**

Append this function to `src/workbranch/lib/validation.sh`:

```bash
validate_branch_name() {
  label=$1
  value=$2
  [ -n "$value" ] || die "invalid $label: empty value"
  if has_whitespace "$value"; then
    die "invalid $label '$value': whitespace is not supported"
  fi
  git check-ref-format --branch "$value" >/dev/null 2>&1 || die "invalid $label '$value'"
}
```

- [x] **Step 4: Rebuild and run syntax check**

Run:

```bash
scripts/build-workbranch.sh
/bin/bash -n bin/workbranch install.sh tests/run.sh
```

Expected: both commands exit 0.

Verification evidence:
- `./tests/run.sh` failed as expected at `test_add_rejects_invalid_task_branch_override` with `expected invalid task branch override to fail` before implementation.
- `scripts/build-workbranch.sh && /bin/bash -n bin/workbranch install.sh tests/run.sh` exited 0 after adding `validate_branch_name`.

---

## Task 2: Add task metadata read/write helpers

**Files:**
- Create: `src/workbranch/lib/task-metadata.sh`
- Modify: `scripts/workbranch-sources.txt`
- Modify: `src/workbranch/lib/project.sh`
- Test: `tests/run.sh`

- [x] **Step 1: Add a failing test that an override branch survives later commands**

Add this integration test near the add/push tests:

```bash
test_add_task_branch_override_is_used_by_later_commands() {
  setup_project_fixture
  project="$TMP_ROOT/work/fullstack"

  out=$(cd "$project" && printf 'tk/login-frontend\ntk/login-backend\n' | "$WB" add login 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "add with branch overrides failed: $out"

  assert_branch "$project/login/frontend" "tk/login-frontend"
  assert_branch "$project/login/backend" "tk/login-backend"
  assert_contains "$(cat "$project/login/.workbranch.task")" "REPO_BRANCH frontend tk/login-frontend"
  assert_contains "$(cat "$project/login/.workbranch.task")" "REPO_BRANCH backend tk/login-backend"

  printf 'frontend scoped\n' > "$project/login/frontend/scoped.txt"
  git -C "$project/login/frontend" add scoped.txt
  git -C "$project/login/frontend" commit -m "frontend scoped" >/dev/null

  out=$(cd "$project" && "$WB" push login --repo frontend 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "push with branch override failed: $out"
  assert_remote_file "$TMP_ROOT/remotes/frontend.git" tk/login-frontend scoped.txt "frontend scoped"
  assert_remote_missing_file "$TMP_ROOT/remotes/frontend.git" feature/login scoped.txt
}
```

- [x] **Step 2: Add metadata module to source order**

Insert this line in `scripts/workbranch-sources.txt` after `src/workbranch/lib/project.sh` and before `src/workbranch/lib/preflight.sh`:

```text
src/workbranch/lib/task-metadata.sh
```

- [x] **Step 3: Create `src/workbranch/lib/task-metadata.sh`**

Create the file with these helpers:

```bash
task_metadata_file() { printf '%s/%s/.workbranch.task' "$PROJECT_ROOT" "$1"; }

reset_task_metadata_cache() {
  TASK_BRANCH_REPOS=()
  TASK_BRANCH_NAMES=()
}

task_metadata_branch_index() {
  name=$1
  TASK_METADATA_INDEX=0
  while [ $TASK_METADATA_INDEX -lt ${#TASK_BRANCH_REPOS[@]} ]; do
    [ "${TASK_BRANCH_REPOS[$TASK_METADATA_INDEX]}" = "$name" ] && return 0
    TASK_METADATA_INDEX=$((TASK_METADATA_INDEX + 1))
  done
  return 1
}

set_task_metadata_branch() {
  name=$1
  branch=$2
  validate_branch_name "task branch" "$branch"
  if task_metadata_branch_index "$name"; then
    TASK_BRANCH_NAMES[$TASK_METADATA_INDEX]=$branch
  else
    TASK_BRANCH_REPOS[${#TASK_BRANCH_REPOS[@]}]=$name
    TASK_BRANCH_NAMES[${#TASK_BRANCH_NAMES[@]}]=$branch
  fi
}

load_task_metadata() {
  task=$1
  file=$(task_metadata_file "$task")
  reset_task_metadata_cache
  [ -f "$file" ] || return 0
  line_no=0
  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    line_no=$((line_no + 1))
    line=$(printf '%s' "$raw_line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    config_line_split_tokens "$line"
    set -- "${CONFIG_FIELDS[@]}"
    case "$1" in
      REPO_BRANCH)
        [ $# -eq 3 ] || die "invalid task metadata line $line_no: REPO_BRANCH expects 2 values"
        repo_index_by_name "$2" >/dev/null || die "task metadata references unknown repo '$2'"
        set_task_metadata_branch "$2" "$3"
        ;;
      *) die "unknown directive '$1' in task metadata line $line_no" ;;
    esac
  done < "$file"
}

metadata_task_branch_for_repo() {
  name=$1
  if task_metadata_branch_index "$name"; then
    printf '%s' "${TASK_BRANCH_NAMES[$TASK_METADATA_INDEX]}"
    return 0
  fi
  return 1
}

write_task_metadata() {
  task=$1
  file=$(task_metadata_file "$task")
  mkdir -p "$(dirname "$file")" || die "failed to create task metadata directory: $task"
  {
    printf '# Workbranch task metadata\n'
    printf '# This file stores branch names chosen when the task workspace was created.\n'
    _task_metadata_i=0
    while [ $_task_metadata_i -lt ${#REPO_NAMES[@]} ]; do
      name=$(repo_name_at "$_task_metadata_i")
      branch=$(metadata_task_branch_for_repo "$name") || branch=$(default_repo_task_branch_at "$_task_metadata_i" "$task")
      printf 'REPO_BRANCH %s %s\n' "$name" "$branch"
      _task_metadata_i=$((_task_metadata_i + 1))
    done
  } > "$file" || die "failed to write task metadata: $file"
}
```

- [x] **Step 4: Add metadata globals**

In `src/workbranch/globals.sh`, add:

```bash
TASK_BRANCH_REPOS=()
TASK_BRANCH_NAMES=()
```

- [x] **Step 5: Rebuild and run syntax check**

Run:

```bash
scripts/build-workbranch.sh
/bin/bash -n bin/workbranch install.sh tests/run.sh
```

Expected: exit 0.

---

## Task 3: Split default branch calculation from resolved branch lookup

**Files:**
- Modify: `src/workbranch/lib/project.sh`
- Test: `tests/run.sh`

- [x] **Step 1: Add tests for default branch naming**

Keep the existing `feature/cpq` test and add a `feat/cpq` variant:

```bash
test_add_uses_feat_parent_branch_as_default() {
  setup_remotes
  commit_to_remote_branch frontend feat/cpq parent-frontend
  project="$TMP_ROOT/work/fullstack"
  mkdir -p "$project"
  cat > "$project/.workbranch.config" <<EOF_CONFIG
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature
REPO frontend $TMP_ROOT/remotes/frontend.git feat/cpq
EOF_CONFIG
  (cd "$project" && "$WB" init >/dev/null 2>&1) || fail "init failed"

  out=$(cd "$project" && printf '\n' | "$WB" add ui 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "add failed: $out"
  assert_contains "$out" "Task branch for frontend [feat/cpq-ui]"
  assert_branch "$project/ui/frontend" "feat/cpq-ui"
}
```

- [x] **Step 2: Replace branch helpers in `project.sh`**

Change the branch functions to this shape:

```bash
default_branch_prefix() {
  if [ -n "$BRANCH_PREFIX" ]; then
    printf '%s' "$BRANCH_PREFIX"
  else
    printf 'feature'
  fi
}

default_feature_branch_for_task() { printf '%s/%s' "$(default_branch_prefix)" "$1"; }

base_prefixed_branch_for_task() {
  parent=$1
  task=$2
  printf '%s-%s' "$parent" "$task"
}

base_branch_looks_like_parent_task_branch() {
  base_branch=$1
  prefix=$(default_branch_prefix)
  case "$base_branch" in
    feature/*|feat/*) return 0 ;;
    "$prefix"/*) return 0 ;;
    *) return 1 ;;
  esac
}

default_repo_task_branch_at() {
  index=$1
  task=$2
  base_branch=$(repo_base_branch_at "$index")
  if base_branch_looks_like_parent_task_branch "$base_branch"; then
    base_prefixed_branch_for_task "$base_branch" "$task"
  else
    default_feature_branch_for_task "$task"
  fi
}

repo_task_branch_at() {
  index=$1
  task=$2
  name=$(repo_name_at "$index")
  load_task_metadata "$task"
  if metadata_task_branch_for_repo "$name"; then
    return 0
  fi
  path=$(task_repo_path "$task" "$name")
  if [ -d "$path/.git" ] || [ -f "$path/.git" ]; then
    current=$(git -C "$path" branch --show-current 2>/dev/null || printf '')
    if [ -n "$current" ]; then
      printf '%s' "$current"
      return 0
    fi
  fi
  default_repo_task_branch_at "$index" "$task"
}
```

- [x] **Step 3: Rebuild and run focused tests**

Run:

```bash
scripts/build-workbranch.sh
./tests/run.sh
```

Expected: tests still fail until add/resume prompting and metadata writing are implemented, but syntax should pass.

---

## Task 4: Prompt and persist branch names in `workbranch add`

**Files:**
- Modify: `src/workbranch/commands/add.sh`
- Test: `tests/run.sh`

- [x] **Step 1: Add helper for add-time prompting**

In `src/workbranch/commands/add.sh`, before `cmd_add`, add:

```bash
prompt_task_branches_for_add() {
  task=$1
  reset_task_metadata_cache
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    default_branch=$(default_repo_task_branch_at "$i" "$task")
    branch=$(prompt_with_default "Task branch for $name" "$default_branch")
    validate_branch_name "task branch" "$branch"
    set_task_metadata_branch "$name" "$branch"
    i=$((i + 1))
  done
}
```

- [x] **Step 2: Call the prompt after base preflight and before branch collision checks**

In `cmd_add`, after:

```bash
preflight_die_if_errors "add"
```

add:

```bash
prompt_task_branches_for_add "$task"
```

Then replace every branch lookup inside `cmd_add` with metadata-aware values:

```bash
branch=$(metadata_task_branch_for_repo "$name") || branch=$(default_repo_task_branch_at "$i" "$task")
```

- [x] **Step 3: Write metadata immediately after creating the task directory**

After:

```bash
mkdir -p "$task_dir" || die "failed to create task directory: $task_dir"
track_path "$task_dir"
```

add:

```bash
write_task_metadata "$task"
```

- [x] **Step 4: Run add tests**

Run:

```bash
scripts/build-workbranch.sh
./tests/run.sh
```

Expected: default add tests continue to pass because non-interactive EOF or blank input uses defaults. New override tests pass.

---

## Task 5: Prompt and persist branch names in `workbranch resume`

**Files:**
- Modify: `src/workbranch/commands/resume.sh`
- Test: `tests/run.sh`

- [x] **Step 1: Add resume override test for remote branch names**

Add this test near existing resume tests:

```bash
test_resume_prompts_for_non_default_remote_task_branch() {
  setup_project_fixture
  project="$TMP_ROOT/work/fullstack"
  commit_to_remote_branch frontend tk/login-frontend remote-frontend
  commit_to_remote_branch backend tk/login-backend remote-backend

  out=$(cd "$project" && printf 'tk/login-frontend\ntk/login-backend\n' | "$WB" resume login 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "resume with branch overrides failed: $out"

  assert_branch "$project/login/frontend" "tk/login-frontend"
  assert_branch "$project/login/backend" "tk/login-backend"
  assert_contains "$(cat "$project/login/.workbranch.task")" "REPO_BRANCH frontend tk/login-frontend"
  assert_contains "$(cat "$project/login/.workbranch.task")" "REPO_BRANCH backend tk/login-backend"
}
```

- [x] **Step 2: Add resume prompt helper**

In `src/workbranch/commands/resume.sh`, before `cmd_resume`, add:

```bash
prompt_task_branches_for_resume() {
  task=$1
  load_task_metadata "$task"
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    current=$(metadata_task_branch_for_repo "$name" || true)
    if [ -z "$current" ]; then
      current=$(default_repo_task_branch_at "$i" "$task")
    fi
    branch=$(prompt_with_default "Task branch for $name" "$current")
    validate_branch_name "task branch" "$branch"
    set_task_metadata_branch "$name" "$branch"
    i=$((i + 1))
  done
}
```

- [x] **Step 3: Call resume prompt before preflight branch existence checks**

After task directory existence is determined, call:

```bash
prompt_task_branches_for_resume "$task"
```

Then replace `branch=$(repo_task_branch_at "$i" "$task")` in `cmd_resume` with:

```bash
branch=$(metadata_task_branch_for_repo "$name") || branch=$(default_repo_task_branch_at "$i" "$task")
```

- [x] **Step 4: Persist metadata after creating or keeping the task directory**

After the task directory exists and before creating worktrees, call:

```bash
write_task_metadata "$task"
```

- [x] **Step 5: Run resume tests**

Run:

```bash
scripts/build-workbranch.sh
./tests/run.sh
```

Expected: new resume override test passes and existing resume defaults still pass.

---

## Task 6: Update later commands to use resolved task branches

**Files:**
- Modify: `src/workbranch/commands/push.sh`
- Modify: `src/workbranch/commands/land.sh`
- Modify: `src/workbranch/commands/update.sh`
- Modify: `src/workbranch/commands/remove.sh`
- Modify: `src/workbranch/lib/status-format.sh`
- Test: `tests/run.sh`

- [x] **Step 1: Replace direct default inference calls with resolved branch lookup**

In each changed command, keep calls named `repo_task_branch_at "$i" "$task"` once Task 3 makes that helper metadata-aware. Remove any duplicated `default_repo_task_branch_at` use from later commands except in add/resume prompt code.

- [x] **Step 2: Add a remove test for override branches**

Add:

```bash
test_remove_deletes_overridden_task_branches() {
  setup_project_fixture
  project="$TMP_ROOT/work/fullstack"
  out=$(cd "$project" && printf 'tk/login-frontend\ntk/login-backend\n' | "$WB" add login 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "add failed: $out"

  out=$(cd "$project" && "$WB" remove login --force 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "remove failed: $out"

  if git -C "$project/_base/frontend" show-ref --verify --quiet refs/heads/tk/login-frontend; then
    fail "expected remove to delete overridden frontend branch"
  fi
  if git -C "$project/_base/backend" show-ref --verify --quiet refs/heads/tk/login-backend; then
    fail "expected remove to delete overridden backend branch"
  fi
}
```

- [x] **Step 3: Add status/list coverage for override branches**

Extend the override add test or add a separate one:

```bash
test_status_shows_overridden_task_branches() {
  setup_project_fixture
  project="$TMP_ROOT/work/fullstack"
  out=$(cd "$project" && printf 'tk/login-frontend\ntk/login-backend\n' | "$WB" add login 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "add failed: $out"

  out=$(cd "$project" && "$WB" status login 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "status failed: $out"
  assert_contains "$out" "tk/login-frontend"
  assert_contains "$out" "tk/login-backend"
}
```

- [x] **Step 4: Run full integration suite**

Run:

```bash
scripts/build-workbranch.sh
./tests/run.sh
```

Expected: all tests pass.

---

## Task 7: Remove branch-prefix prompts from init/config UX

**Files:**
- Modify: `src/workbranch/commands/init.sh`
- Modify: `src/workbranch/commands/config.sh`
- Test: `tests/run.sh`

- [x] **Step 1: Update `cmd_init_interactive`**

Remove setup-guide line:

```bash
printf '    Branch prefix     task branch prefix, e.g. feature/login
' >&2
```

Replace the prompt:

```bash
BRANCH_PREFIX=$(prompt_with_default "Branch prefix" "feature")
validate_nonempty_no_space "branch_prefix" "$BRANCH_PREFIX"
```

with:

```bash
BRANCH_PREFIX="feature"
```

Replace summary output:

```bash
info "Branch prefix: $BRANCH_PREFIX"
```

with:

```bash
info "Default task branch prefix: $BRANCH_PREFIX"
```

Replace branch policy examples to emphasize add-time prompts:

```bash
info "Task branch defaults:"
info "  - [base repo] main        -> task1 -> [task repo] feature/task1"
info "  - [base repo] feature/XXX -> task1 -> [task repo] feature/XXX-task1"
info "  - You can override each task branch when running workbranch add."
```

- [x] **Step 2: Update `configure_project_settings`**

Remove branch-prefix prompt and change detection from `configure_project_settings`. Keep `BRANCH_PREFIX` unchanged if loaded from config, and set it defensively if missing:

```bash
[ -n "$BRANCH_PREFIX" ] || BRANCH_PREFIX="feature"
```

- [x] **Step 3: Update `configure_existing_project` display**

Replace:

```bash
info "Branch prefix: $BRANCH_PREFIX"
```

with:

```bash
info "Default task branch prefix: $BRANCH_PREFIX"
```

- [x] **Step 4: Remove config next-step branch prefix output**

Delete `CONFIG_BRANCH_PREFIX_OLD`, `CONFIG_BRANCH_PREFIX_NEW`, and the `print_config_next_steps` branch-prefix block. Keep branch-prefix parsing/writing in `src/workbranch/lib/config.sh`.

- [x] **Step 5: Update interactive tests**

Adjust tests that feed interactive `init` or `config` input so they no longer include a branch prefix answer. Existing assertions should change from prompt-specific behavior to config compatibility:

```bash
assert_contains "$(cat "$project/.workbranch.config")" "BRANCH_PREFIX feature"
```

Remove or rewrite tests that assert `cannot change BRANCH_PREFIX while task workspaces exist`, because branch prefix is no longer an interactive setting. Replace them with a rewrite compatibility test:

```bash
test_config_preserves_existing_branch_prefix_without_prompting() {
  setup_project_fixture
  project="$TMP_ROOT/work/fullstack"
  sed -i.bak 's/BRANCH_PREFIX feature/BRANCH_PREFIX ticket/' "$project/.workbranch.config"
  rm -f "$project/.workbranch.config.bak"

  out=$(cd "$project" && printf 'fullstack\n_base\nmain\n\nmain\n\n' | "$WB" config 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "config failed: $out"
  assert_contains "$(cat "$project/.workbranch.config")" "BRANCH_PREFIX ticket"
  assert_not_contains "$out" "Branch prefix [ticket]"
}
```

- [x] **Step 6: Run config/init tests and full suite**

Run:

```bash
scripts/build-workbranch.sh
./tests/run.sh
```

Expected: all tests pass.

---

## Task 8: Update docs and generated distribution

**Files:**
- Modify: `README.md`
- Modify: `docs/specs/0001-workbranch-mvp.md`
- Modify: `docs/git-operations.md`
- Modify: `bin/workbranch`

- [x] **Step 1: Update README command descriptions**

Change references to “branch prefix” as a prompted config setting. Describe branch naming as:

```markdown
`workbranch add <task>` uses `<task>` as the folder name, then prompts for each repo's task branch. Press Enter to accept the default branch name. Defaults are `feature/<task>` from main-style base branches and `<base-branch>-<task>` from `feature/*`, `feat/*`, or the configured legacy prefix.
```

- [x] **Step 2: Update MVP spec**

In `docs/specs/0001-workbranch-mvp.md`, replace the branch naming section with the explicit add-time prompt contract and metadata persistence. Keep `BRANCH_PREFIX feature` in the config example but label it as the default branch prompt prefix rather than a setup prompt.

- [x] **Step 3: Update git operations doc**

In `docs/git-operations.md`, update examples:

```text
base branch master       + task login + default prompt -> feature/login
base branch feature/cpq  + task task1 + default prompt -> feature/cpq-task1
base branch master       + task login + override tk/login -> tk/login
```

- [x] **Step 4: Rebuild generated CLI**

Run:

```bash
scripts/build-workbranch.sh
```

Expected: `bin/workbranch` is regenerated and `bash -n` passes inside the build script.

---


## Implementation Verification Notes

- Task 2-6 implementation verification: `scripts/build-workbranch.sh && ./tests/run.sh` was run after metadata/add/resume/later-command changes. Initial regressions were fixed: `.workbranch.task` no longer keeps removed task dirs, metadata lookup no longer leaks Bash globals across repos, and list coverage replaces the unsupported `workbranch status login` form.
- Task 7 verification: `scripts/build-workbranch.sh && ./tests/run.sh` exited 0 with 84 passing tests after removing branch-prefix prompts from init/config and preserving existing `BRANCH_PREFIX`.
- Task 8 verification: docs were updated and `bin/workbranch` was regenerated with `scripts/build-workbranch.sh`; final syntax/full-suite/whitespace checks remain in Task 9.

## Task 9: Final verification

**Files:**
- Verify all changed files

- [x] **Step 1: Run syntax checks**

Run:

```bash
/bin/bash -n bin/workbranch install.sh tests/run.sh
```

Expected: exit 0.

- [x] **Step 2: Run full integration suite**

Run:

```bash
./tests/run.sh
```

Expected: all tests pass, including generated-file freshness.

- [x] **Step 3: Check whitespace**

Run:

```bash
git diff --check
```

Expected: no output and exit 0.

- [x] **Step 4: Inspect final diff**

Run:

```bash
git diff -- src/workbranch bin/workbranch tests/run.sh README.md docs/specs/0001-workbranch-mvp.md docs/git-operations.md scripts/workbranch-sources.txt docs/plans/0005-explicit-task-branch-names.md
```

Expected: diff shows source-first changes, regenerated `bin/workbranch`, updated tests, updated docs, and this plan.

---

## Self-Review Notes

- Spec coverage: the plan covers explicit add-time branch prompts, default branch rules, removal of branch-prefix prompts, compatibility with existing `BRANCH_PREFIX`, persistence for later commands, tests, docs, and generated distribution.
- Placeholder scan: no `TBD`, `TODO`, or “implement later” placeholders are intentionally present.
- Risk called out: arbitrary branch overrides require persistence. The task-local metadata file is included so later commands do not silently fall back to `feature/<task>`.
- Compatibility: existing task workspaces without metadata keep working through current-branch fallback and default branch inference.

Final verification evidence:
- `/bin/bash -n bin/workbranch install.sh tests/run.sh` exited 0.
- `./tests/run.sh` exited 0 with 84 passing tests.
- `git diff --check` exited 0 with no whitespace errors.
- `git diff --stat` and targeted diff inspection showed source-first changes, regenerated `bin/workbranch`, tests, docs, source order, and this plan.
