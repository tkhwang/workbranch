# 0010 Conventional Task Identity and Branch Naming Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` before every behavior change. Steps use checkbox (`- [x]`) syntax for tracking. Make source changes under `src/workbranch/**`, rebuild with `scripts/build-workbranch.sh`, then verify syntax checks, targeted tests, `./tests/run.sh`, and `git diff --check`. Do not edit `bin/workbranch` by hand.

**Goal:** Remove the hidden default branch-prefix mental model by making new task identity explicit: users choose a conventional task type and detail name, then `workbranch` derives a safe task folder from those two values and suggests each repo's task branch from that repo's configured base branch.

**Architecture:** Keep base branch ownership in `workbranch config`, keep task folder names and Git branch names as separate surfaces, and change `workbranch add` so the default interactive path derives the task folder from `type + detail`. The task folder becomes `type+detail-name`; repo default branches use `type/detail-name` for main/master-style bases and `<base-branch>-<detail-name>` for parent feature bases such as `feature/cpq`; repo-specific branch overrides and `.workbranch.task` metadata remain the source of truth for later commands.

**Tech Stack:** Portable Bash, Git worktrees, line-oriented `.workbranch.config`, task metadata in `<task>/.workbranch.task`, generated single-file CLI via `scripts/build-workbranch.sh`, integration tests in `tests/run.sh`.

---

## Problem Statement

Current behavior still requires users to understand a hidden relationship between config-time `BRANCH_PREFIX`, the typed task name, the base repo branch, and the default task branch:

```text
BRANCH_PREFIX feature + workbranch add login -> folder login + branch feature/login
base branch feat/cpq + workbranch add ui -> folder ui + branch feat/cpq-ui
```

That is powerful but implicit. A user who only wants to create a task workspace must know that a config-level prefix will later become part of the branch name. The product direction is to remove this hidden setup-time decision and ask for task intent at creation time instead.

The new mental model should be:

```text
task type   = feat
detail name = branch-name

folder      = feat+branch-name
branch      = feat/branch-name          # when repo base is main/master
branch      = feature/cpq-branch-name   # when repo base is feature/cpq
```

The folder and branch are visibly related, but they are not the same string. This preserves file-system safety and Git branch convention at the same time.

## Current Repo Evidence

- `README.md` documents that `workbranch add <task>` uses `<task>` as the folder and defaults branches from `BRANCH_PREFIX`, `feature/*`, or `feat/*` base branches.
- `docs/specs/0001-workbranch-mvp.md` says task folder names and Git branch names are separate values, but still documents `BRANCH_PREFIX` as default branch prompt input in interactive setup.
- `src/workbranch/commands/init.sh` currently prompts `Default task branch prefix` and summarizes it.
- `src/workbranch/commands/config.sh` preserves existing `BRANCH_PREFIX` and displays `Default task branch prefix` during existing-project config.
- `src/workbranch/lib/config.sh` requires and writes `BRANCH_PREFIX`.
- `src/workbranch/lib/project.sh` computes defaults through `default_branch_prefix`, `default_feature_branch_for_task`, `base_branch_looks_like_parent_task_branch`, and `default_repo_task_branch_at`.
- `src/workbranch/commands/add.sh` accepts exactly one `<task>`, validates it with `validate_safe_name`, prompts repo task branches, writes `.workbranch.task`, and creates `<task>/<repo>` linked worktrees.
- Tests already cover branch defaults and overrides in `tests/cases/add.sh`, config prefix preservation in `tests/cases/config.sh`, and interactive prefix setup in `tests/cases/interactive-init.sh`.

## Product Decisions

1. **Task identity is explicit at add time.**
   - Ask for a conventional task type and detail name when the user runs interactive `workbranch add` without a task argument.
   - Derive the task folder from those values.

2. **Folder and branch remain separate surfaces.**
   - Folder/workspace key: `feat+branch-name`.
   - Default branch for main/master-style bases: `feat/branch-name`.
   - Default branch for parent feature bases such as `feature/cpq`: `feature/cpq-branch-name`.
   - Later commands still operate by task folder name: `workbranch status feat+branch-name`, `workbranch path feat+branch-name`, `workbranch remove feat+branch-name`.

3. **Use `+` as the folder-safe slash escape.**
   - Git branches use `/` because `feat/branch-name` is the familiar conventional branch shape.
   - Task folders use `+` because a literal `/` creates nested directories and makes the task root ambiguous, while `+` stays readable and does not need shell quoting in normal CLI usage.
   - Rejected alternatives:
     - `feat/branch-name` as folder: ambiguous task root and nested path semantics.
     - `feat-branch-name`: readable, but the type/detail boundary is weak.
     - `feat__branch-name`: safe, but it looks like an internal escape sequence rather than a user-facing task key.
     - `feat_branch-name`: single underscore is too common inside names and does not clearly mean slash.
     - `feat.branch-name`: workable, but dot suggests file extension or hidden-file semantics more than branch identity.
     - `feat|branch-name`: visually clear, but `|` is a shell pipe operator and would require quoting in common command usage.

4. **Do not move base-branch decisions into `add`.**
   - `workbranch config` remains the place to change base repo branches.
   - `workbranch add` may show each repo base branch for context, but it must not ask for or change base branches.

5. **Keep repo-specific branch overrides.**
   - After deriving the task folder, each repo gets a task branch prompt with a base-aware default.
   - User overrides continue to be stored as `REPO_BRANCH <repo> <branch>` in `<task>/.workbranch.task`.

6. **Keep legacy compatibility.**
   - Existing `.workbranch.config` files with `BRANCH_PREFIX` continue to parse.
   - Existing task folders such as `login` continue to work.
   - Interactive `workbranch add <detail>` enters the conventional task identity flow and uses `<detail>` as the editable detail default.
   - Existing non-interactive `workbranch add <task>` remains supported for scripts and user-chosen task names.
   - The `type+detail` form is the recommended conventional task key, not the only valid task key.
   - A task key without `+` remains valid when it passes the legacy safe-name rule; its default branch naming is deliberately classified as legacy/default fallback.

7. **Normalize task command arguments for shell completion.**
   - Commands that take a task key should accept a trailing `/` added by shell completion.
   - `workbranch remove feat+branch-name/` should behave like `workbranch remove feat+branch-name`.
   - This is only trailing-slash normalization, not path support: `feat+branch-name/frontend`, `./feat+branch-name`, and nested paths remain invalid task keys.
   - Apply this consistently to task-taking commands: `add`, `path`, `finder`, `ide`, `terminal`, `update <task>`, `push <task>`, `land <task>`, and `remove`.

## Resolved Decision Gate

- [x] **Interactive vs non-interactive `workbranch add <task>` default branch rule**
  - Impact: script compatibility, mental model, and whether legacy `BRANCH_PREFIX` remains visible in new task creation.
  - Current evidence: `README.md`, `docs/specs/0001-workbranch-mvp.md`, and `src/workbranch/lib/project.sh` currently default `workbranch add login` to `feature/login` from `BRANCH_PREFIX` or `feature` fallback.
  - Resolution: in an interactive terminal, `workbranch add <detail>` enters the same task identity prompt as zero-arg `workbranch add`, using `<detail>` as the editable Task detail name default. If `<task>` contains exactly one `+` with a known conventional type, derive the default branch by replacing that delimiter with `/` as a direct shorthand. In non-interactive use, no-plus `<task>` values remain explicit task keys and use the existing legacy default branch rule.
  - Rationale: This matches the user-facing creation flow (`add task1` asks for type and recommends `feat+task1`) while preserving automation and arbitrary no-plus task names for scripts.
  - Rejected alternative: make every non-TTY `workbranch add <task>` prompt or reject non-`type+detail` names. That would enforce clarity faster, but it is a breaking change for scripts and current README examples.

- [x] **Repo base-aware branch defaults for conventional task keys**
  - Impact: feature-parent workflows should keep parent context in new task branches.
  - Resolution: `type+detail` remains the task folder identity. For each repo, default branch is `type/detail` when the base branch is main/master-style, and `<base-branch>-<detail>` when the base branch is a parent feature branch such as `feature/cpq` or `feat/cpq`.
  - Rationale: `feat+task1` keeps the conventional task identity while `feature/cpq-task1` preserves the repo's actual parent branch context.
  - Rejected alternative: always use `type/detail` for conventional task keys. That loses the parent feature context for repos based on `feature/cpq`.

## Target UX

### New recommended interactive path

```bash
workbranch add
```

Prompts:

```text
[*] Task type [feat]: feat
[*] Task detail name: branch-name
[*] Task folder: feat+branch-name

[*] Repo frontend
[*]   base branch: main
[*]   task repo branch [feat/branch-name]:
[*]   task repo folder: feat+branch-name/frontend

[*] Repo backend
[*]   base branch: feature/cpq
[*]   task repo branch [feature/cpq-branch-name]:
[*]   task repo folder: feat+branch-name/backend
```

Result:

```text
fullstack
├── .workbranch.config
├── _base
│   ├── frontend
│   └── backend
└── feat+branch-name
    ├── .workbranch.task
    ├── frontend     # branch feat/branch-name unless overridden
    └── backend      # branch feature/cpq-branch-name unless overridden
```

Metadata:

```text
# Workbranch task metadata
# This file stores branch names chosen when the task workspace was created.
REPO_BRANCH frontend feat/branch-name
REPO_BRANCH backend feature/cpq-branch-name
```

### Explicit shorthand path

```bash
workbranch add feat+branch-name
```

Default branch prompt on a main/master-style base:

```text
[*] Repo frontend
[*]   base branch: main
[*]   task repo branch [feat/branch-name]:
[*]   task repo folder: feat+branch-name/frontend
```

### Legacy-compatible path

```bash
workbranch add login
```

Default branch prompt remains compatible in this slice:

```text
[*] Repo frontend base branch: main
[*] Task branch for frontend [feature/login]:
```

The docs should describe this as supported compatibility, not the recommended mental model.

## Validation Rules

### Task type

Allowed values for the first slice:

```text
feat
fix
chore
docs
refactor
test
perf
ci
build
revert
```

Rules:

- Safe path segment only: `[A-Za-z0-9._-]+` is already available through `validate_safe_name`, but the recommended built-in values are lowercase conventional types.
- No slash, whitespace, or empty value.
- Default prompt value: `feat`.

### Detail name

Rules:

- Use the existing safe-name rule: `[A-Za-z0-9._-]+`.
- Reject empty, `.`, and `..` through existing validation.
- Recommended examples use kebab case: `branch-name`, `login-api`, `fix-status-output`.

### Task folder / task key

Rules:

- The canonical task key and folder for conventional tasks is `<type>+<detail>`.
- `type+detail` is recommended for new conventional tasks, but not mandatory for every explicit task key.
- `+` is allowed only as the task type/detail delimiter.
- Type and detail remain individually validated with the safe-name rule.
- Existing and user-chosen non-conventional task keys such as `login` or `implement-login` remain valid through the legacy safe-name rule.
- A task key with `+` but without a known conventional type should be rejected rather than silently treated as legacy shorthand, because `+` is now reserved for conventional identity.
- Task command arguments may include completion-added trailing `/` characters; strip trailing `/` before validation.
- Do not strip or interpret leading paths or embedded slashes. After trailing-slash normalization, the existing validation rules still reject `/`.

### Derived values

```text
task folder    = <type>+<detail>
default branch = <type>/<detail>
```

`+` is the folder-safe representation of the branch slash. Use this wording in prompts and docs:

```text
Git branch uses slash:     feat/branch-name
Folder uses slash escape:  feat+branch-name
```

Do not use `{type}/{detail}` as the task folder. It creates nested directories (`feat/branch-name/<repo>`) and makes it unclear whether the task workspace is `feat` or `feat/branch-name`.

If a user enters an explicit task folder containing exactly one `+` delimiter:

```text
feat+branch-name -> feat/branch-name
fix+path-output  -> fix/path-output
```

Additional `+` characters are rejected because `+` is reserved for the type/detail boundary:

```text
feat+a+b -> invalid task key
```

## Target File Structure

```text
src/workbranch/lib/task-identity.sh        # new: parse, validate, derive task folder/default branch
src/workbranch/lib/project.sh              # use task identity before legacy BRANCH_PREFIX defaults
src/workbranch/commands/add.sh             # support zero-arg interactive add and derived defaults
src/workbranch/commands/path.sh            # normalize trailing slash in task argument
src/workbranch/commands/tool-launcher.sh   # normalize trailing slash for finder/ide/terminal task argument
src/workbranch/commands/update.sh          # normalize trailing slash in optional task argument
src/workbranch/commands/push.sh            # normalize trailing slash in optional task argument
src/workbranch/commands/land.sh            # normalize trailing slash in task argument
src/workbranch/commands/remove.sh          # normalize trailing slash in task argument
src/workbranch/commands/init.sh            # remove new-project task branch prefix prompt from user-facing setup
src/workbranch/commands/config.sh          # stop presenting legacy prefix as a current mental model
src/workbranch/usage.sh                    # update add usage to `add [<task>] [--from <ref>]`
src/workbranch/lib/config.sh               # keep BRANCH_PREFIX parse/write compatibility; make default internal
scripts/workbranch-sources.txt             # include task-identity before project/add command modules
README.md                                  # document new mental model and compatibility path
README.ko.md                               # Korean docs mirror for new mental model
README.md / docs/specs/0001-workbranch-mvp.md # source contract updates
docs/git-operations.md                     # update examples only if they mention feature/<task> defaults
tests/cases/add.sh                         # new add prompt and derived default branch tests
tests/cases/config.sh                      # remove user-visible prefix assertions or reframe compatibility
tests/cases/interactive-init.sh            # remove prefix prompt test, add no-prefix setup assertion
tests/cases/path.sh                        # trailing-slash task argument regression
tests/cases/remove.sh                      # trailing-slash task argument regression
tests/cases/status.sh                      # ensure list/status display handles feat+folder + feat/branch
tests/cases/meta.sh                        # update help usage assertion for optional add task
tests/run.sh                               # register new tests in stable order
bin/workbranch                             # regenerated only by scripts/build-workbranch.sh
```

## Implementation Tasks

### Task 1: Lock task identity parsing with focused tests

**Files:**
- Create: `src/workbranch/lib/task-identity.sh`
- Modify: `scripts/workbranch-sources.txt`
- Modify: `tests/cases/add.sh`
- Modify: `tests/run.sh`

- [x] Add failing integration coverage for `workbranch add feat+branch-name` deriving `feat/branch-name` as the default branch.

  Test shape in `tests/cases/add.sh`:

  ```bash
  test_add_derives_branch_from_conventional_task_folder() {
    new_fixture
    cd "$project" || fail "cd project failed"

    out=$(printf '\n\n' | "$WORKBRANCH" add feat+branch-name 2>&1)
    status=$?

    [ "$status" -eq 0 ] || fail "add with conventional task folder failed: $out"
    assert_contains "$out" "Task branch for frontend [feat/branch-name]"
    assert_contains "$out" "Task branch for backend [feat/branch-name]"
    assert_branch "$project/feat+branch-name/frontend" "feat/branch-name"
    assert_branch "$project/feat+branch-name/backend" "feat/branch-name"
    assert_contains "$(cat "$project/feat+branch-name/.workbranch.task")" "REPO_BRANCH frontend feat/branch-name"
    assert_contains "$(cat "$project/feat+branch-name/.workbranch.task")" "REPO_BRANCH backend feat/branch-name"
  }
  ```

- [x] Register the test in `tests/run.sh` near the other `add` branch-name tests.

  Add after `test_add_uses_feat_parent_branch_as_default`:

  ```bash
  run_test test_add_derives_branch_from_conventional_task_folder
  ```

- [x] Run the targeted failing test.

  Command:

  ```bash
  ./tests/run.sh
  ```

  Expected before implementation: the suite fails at `test_add_derives_branch_from_conventional_task_folder` because `feat+branch-name` still defaults through legacy `feature/feat+branch-name`. The runner currently has no single-test filter, so use the full suite and read the named failure.

- [x] Add `src/workbranch/lib/task-identity.sh` with these helpers:

  ```bash
  conventional_task_type_is_known() {
    case "$1" in
      feat|fix|chore|docs|refactor|test|perf|ci|build|revert) return 0 ;;
      *) return 1 ;;
    esac
  }

  task_identity_has_delimiter() {
    case "$1" in
      *+*) return 0 ;;
      *) return 1 ;;
    esac
  }

  task_identity_type_from_folder() {
    printf '%s' "${1%%+*}"
  }

  task_identity_detail_from_folder() {
    printf '%s' "${1#*+}"
  }

  normalize_task_argument() {
    local value
    value=$1
    while [ -n "$value" ]; do
      case "$value" in
        */) value=${value%/} ;;
        *) break ;;
      esac
    done
    printf '%s' "$value"
  }

  task_identity_has_multiple_delimiters() {
    local rest
    task_identity_has_delimiter "$1" || return 1
    rest=${1#*+}
    case "$rest" in
      *+*) return 0 ;;
      *) return 1 ;;
    esac
  }

  validate_task_type() {
    local value
    value=$1
    validate_safe_name "task type" "$value"
    conventional_task_type_is_known "$value" || die "invalid task type '$value' (expected feat, fix, chore, docs, refactor, test, perf, ci, build, or revert)"
  }

  validate_task_detail_name() {
    validate_safe_name "task detail name" "$1"
  }

  validate_task_folder_name() {
    local value type detail
    value=$(normalize_task_argument "$1")
    [ -n "$value" ] || die "invalid task '$1' (expected task key)"
    if task_identity_has_delimiter "$value"; then
      task_identity_has_multiple_delimiters "$value" && die "invalid task '$value' (expected exactly one + delimiter)"
      type=$(task_identity_type_from_folder "$value")
      detail=$(task_identity_detail_from_folder "$value")
      validate_task_type "$type"
      validate_task_detail_name "$detail"
      return 0
    fi
    validate_safe_name "task" "$value"
  }

  task_folder_from_identity() {
    local type detail
    type=$1
    detail=$2
    validate_task_type "$type"
    validate_task_detail_name "$detail"
    printf '%s+%s' "$type" "$detail"
  }

  task_branch_from_identity() {
    local type detail
    type=$1
    detail=$2
    validate_task_type "$type"
    validate_task_detail_name "$detail"
    printf '%s/%s' "$type" "$detail"
  }

  task_branch_from_folder_identity() {
    local task type detail
    task=$(normalize_task_argument "$1")
    task_identity_has_delimiter "$task" || return 1
    task_identity_has_multiple_delimiters "$task" && die "invalid task '$task' (expected exactly one + delimiter)"
    type=$(task_identity_type_from_folder "$task")
    detail=$(task_identity_detail_from_folder "$task")
    conventional_task_type_is_known "$type" || return 1
    task_branch_from_identity "$type" "$detail"
  }
  ```

- [x] Add `src/workbranch/lib/task-identity.sh` to `scripts/workbranch-sources.txt` before `src/workbranch/lib/project.sh`.

- [x] Update `src/workbranch/lib/project.sh` so `default_repo_task_branch_at` first tries `task_branch_from_folder_identity "$task"` before falling back to the existing base-branch/legacy-prefix rule.

  Required shape:

  ```bash
  default_repo_task_branch_at() {
    local index task base_branch identity_branch
    index=$1
    task=$2
    if identity_branch=$(task_branch_from_folder_identity "$task"); then
      printf '%s' "$identity_branch"
      return 0
    fi
    base_branch=$(repo_base_branch_at "$index")
    if base_branch_looks_like_parent_task_branch "$base_branch"; then
      base_prefixed_branch_for_task "$base_branch" "$task"
    else
      default_feature_branch_for_task "$task"
    fi
  }
  ```

- [x] Rebuild and run the targeted test.

  Commands:

  ```bash
  scripts/build-workbranch.sh
  ./tests/run.sh
  ```

  Expected: the full suite passes through `test_add_derives_branch_from_conventional_task_folder`; any later failures must be fixed before moving on.

### Task 2: Add zero-argument `workbranch add` interactive identity prompts

**Files:**
- Modify: `src/workbranch/commands/add.sh`
- Modify: `tests/cases/add.sh`
- Modify: `tests/run.sh`

- [x] Add failing coverage for zero-arg `workbranch add` deriving the folder from prompts and repo-specific branch defaults from each repo base branch.

  Test shape:

  ```bash
  test_add_prompts_for_task_type_and_detail_without_task_argument() {
    new_fixture
    cd "$project" || fail "cd project failed"

    out=$(printf 'feat\nbranch-name\n\n\n' | "$WORKBRANCH" add 2>&1)
    status=$?

    [ "$status" -eq 0 ] || fail "interactive add failed: $out"
    assert_contains "$out" "Task type [feat]"
    assert_contains "$out" "Task detail name"
    assert_contains "$out" "Task folder: feat+branch-name"
    assert_branch "$project/feat+branch-name/frontend" "feat/branch-name"
    assert_branch "$project/feat+branch-name/backend" "feat/branch-name"
  }
  ```

- [x] Register the test in `tests/run.sh` after `test_add_derives_branch_from_conventional_task_folder`.

- [x] Run the targeted failing test.

  ```bash
  ./tests/run.sh
  ```

  Expected before implementation: the suite fails at `test_add_prompts_for_task_type_and_detail_without_task_argument` with a usage error because `parse_add_options` currently requires exactly one positional task.

- [x] Update `parse_add_options` to accept zero or one task argument.

  Required behavior:

  ```text
  workbranch add                 # interactive task identity prompt
  workbranch add <detail>        # interactive identity prompt with detail default
  workbranch add type+detail     # explicit conventional shorthand path
  workbranch add --from <ref>    # interactive identity prompt with source ref
  workbranch add <task> --from <ref>
  ```

  Usage errors should say:

  ```text
  usage: workbranch add [<task>] [--from <ref>]
  ```

- [x] Add `prompt_task_identity_for_add` in `src/workbranch/commands/add.sh`:

  ```bash
  prompt_task_identity_for_add() {
    local type detail task
    type=$(prompt_with_default "Task type" "feat")
    validate_task_type "$type"
    detail=$(prompt_required "Task detail name")
    validate_task_detail_name "$detail"
    task=$(task_folder_from_identity "$type" "$detail")
    info "Task folder: $task"
    printf '%s' "$task"
  }
  ```

- [x] Update `cmd_add` to set `task` from the prompt when no positional task is provided.

  Required shape:

  ```bash
  if [ ${#ARGS[@]} -eq 0 ]; then
    task=$(prompt_task_identity_for_add)
  else
    task=$(normalize_task_argument "${ARGS[0]}")
  fi
  validate_task_folder_name "$task"
  ```

  Implementation note: `prompt_task_identity_for_add` must print user-facing `info` lines to stderr through `info`, and print only the task folder to stdout so command substitution captures the folder cleanly.

- [x] Replace direct `validate_safe_name "task" "$task"` call sites with `normalize_task_argument` + `validate_task_folder_name` for every task-taking command:
  - `src/workbranch/commands/add.sh`
  - `src/workbranch/commands/path.sh`
  - `src/workbranch/commands/tool-launcher.sh`
  - `src/workbranch/commands/update.sh`
  - `src/workbranch/commands/push.sh`
  - `src/workbranch/commands/land.sh`
  - `src/workbranch/commands/remove.sh`

- [x] Add trailing-slash regressions:
  - `workbranch path feat+branch-name/` prints the same task path as `workbranch path feat+branch-name`.
  - `workbranch remove feat+branch-name/ --force` removes the same task workspace and branches as `workbranch remove feat+branch-name --force`.
  - Keep an invalid-path assertion such as `workbranch path feat+branch-name/frontend` failing as an invalid task key.

- [x] Rebuild and run targeted add tests.

  ```bash
  scripts/build-workbranch.sh
  ./tests/run.sh
  ```

  Expected: the full suite passes through the new add tests and existing branch override tests.

### Task 3: Reframe `BRANCH_PREFIX` as compatibility config, not current setup UX

**Files:**
- Modify: `src/workbranch/commands/init.sh`
- Modify: `src/workbranch/commands/config.sh`
- Modify: `src/workbranch/lib/config.sh`
- Modify: `tests/cases/interactive-init.sh`
- Modify: `tests/cases/config.sh`

- [x] Replace the interactive init prefix test with a no-prefix-prompt test.

  Current test to remove or rewrite:

  ```bash
  test_interactive_init_accepts_task_branch_prefix_override
  ```

  New test shape:

  ```bash
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
INPUT
)
    out=$(cd "$TMP_ROOT/work" && printf '%s' "$input" | WORKBRANCH_TEST_PLATFORM=macos run_expect_success "$WORKBRANCH" init)

    assert_not_contains "$out" "Default task branch prefix"
    assert_contains "$out" "Task identity:"
    assert_contains "$out" "folder type+detail"
    assert_contains "$out" "Each repo suggests a task branch from its base branch"
    assert_contains "$(cat "$TMP_ROOT/work/fullstack/.workbranch.config")" "BRANCH_PREFIX feature"
  }
  ```

- [x] Update `src/workbranch/commands/init.sh`:
  - Remove the prompt `Default task branch prefix`.
  - Set `BRANCH_PREFIX=feature` internally before writing config.
  - Replace summary line `Default task branch prefix: ...` with task identity guidance:

    ```text
    Task identity:
      - New tasks can be created with workbranch add.
      - workbranch asks for task type and detail name, then derives folder type+detail.
      - Each repo suggests a task branch from its base branch, and you can override it.
    ```

- [x] Update `src/workbranch/commands/config.sh`:
  - Keep preserving existing `BRANCH_PREFIX`.
  - Stop displaying `Default task branch prefix: $BRANCH_PREFIX` as a normal current setting.
  - If useful, display a compatibility line instead:

    ```text
    Legacy branch prefix: <value> (kept for existing shorthand defaults)
    ```

- [x] Update `src/workbranch/lib/config.sh`:
  - Keep parsing `BRANCH_PREFIX`.
  - Keep writing `BRANCH_PREFIX ${BRANCH_PREFIX:-feature}` for now so existing config completeness remains stable.
  - Make `validate_config_complete` tolerate missing `BRANCH_PREFIX` by defaulting to `feature` before validation completes, if the implementation chooses to stop writing it in a later slice.

  Minimal compatible shape for this slice:

  ```bash
  [ -n "$BRANCH_PREFIX" ] || BRANCH_PREFIX="feature"
  ```

  This default belongs after parsing and before config completeness checks.

- [x] Update `tests/cases/config.sh`:
  - Keep `test_config_preserves_existing_branch_prefix_without_prompting` because it guards legacy compatibility.
  - Change assertions that present `Default task branch prefix` as normal UX to the new compatibility wording or no-prefix behavior.

- [x] Rebuild and run targeted config/init tests.

  ```bash
  scripts/build-workbranch.sh
  ./tests/run.sh
  ```

  Expected: the full suite passes through the interactive init and config prefix compatibility tests.

### Task 4: Update docs/specs to teach the new mental model

**Files:**
- Modify: `README.md`
- Modify: `README.ko.md`
- Modify: `docs/specs/0001-workbranch-mvp.md`
- Modify: `src/workbranch/usage.sh`
- Modify: `tests/cases/meta.sh`
- Modify: `docs/git-operations.md` only if current examples mention old default branch names as the recommended flow

- [x] Update Quick start in `README.md` from `workbranch add login` to the recommended prompt flow:

  ```bash
  workbranch init
  workbranch add
  cd feat+login/<repo>
  # work on the task
  workbranch update feat+login
  workbranch push feat+login
  workbranch remove feat+login
  ```

- [x] Add a concise mental-model section in `README.md`:

  ```markdown
  ## Task identity and branch names

  New task creation asks for two values:

  | Prompt | Example | Used for |
  | --- | --- | --- |
  | Task type | `feat` | Git branch prefix |
  | Task detail name | `login` | Folder/branch detail |

  `workbranch` derives:

  - task folder: `feat+login`
  - default Git branch: `feat/login`

  Folder names and branch names stay separate because folders must be path-safe while Git branches normally use `/`. `workbranch` uses `+` as the folder-safe slash escape, so `feat+login` is the task-folder form of `feat/login`. Repo-specific branch prompts still let you override the default per repo.
  ```

- [x] Document compatibility:

  ```markdown
  Interactive `workbranch add <detail>` enters the same creation flow, using `<detail>` as the default Task detail name. `workbranch add feat+login` remains a direct shorthand for the conventional task key. Non-interactive scripts can still pass task keys without `+`; those legacy explicit keys keep branch-prefix defaults for compatibility.
  ```

- [x] Mirror the same contract in `README.ko.md`.

- [x] Update `docs/specs/0001-workbranch-mvp.md`:
  - Config rules: `BRANCH_PREFIX` is retained for compatibility, not a setup-time mental model.
  - Branch names section: replace primary examples with `feat+login -> feat/login`.
  - `workbranch init`: remove the step that asks for default task branch prefix.
  - `workbranch add`: update usage to `workbranch add [<task>] [--from <ref>]`.
  - Add explicit zero-arg prompt behavior.

- [x] Update help/usage surfaces:
  - Change `src/workbranch/usage.sh` plain and enhanced help from `add <task> [--from <ref>]` to `add [<task>] [--from <ref>]`.
  - Update `tests/cases/meta.sh:test_help_groups_commands` to assert the new optional-task usage.

- [x] Run documentation checks.

  ```bash
  rg -n "Default task branch prefix|default task branch prefix|workbranch add login|feature/<task>|BRANCH_PREFIX is retained for compatibility and as the default" README.md README.ko.md docs/specs docs/git-operations.md
  git diff --check
  ```

  Expected: no stale user-facing text that presents `BRANCH_PREFIX` as the recommended mental model.

### Task 5: Verify branch workflow consumers with conventional folders

**Files:**
- Modify: `tests/cases/status.sh`
- Modify: `tests/cases/remove.sh` if existing stale-worktree fallback needs explicit conventional-folder coverage
- Modify: `tests/cases/git-flow.sh` if push/land examples need conventional-folder coverage
- Modify: `tests/run.sh`

- [x] Add a status/list regression showing folder and branch separately.

  Test shape:

  ```bash
  test_list_shows_conventional_task_folder_and_branch() {
    new_fixture
    cd "$project" || fail "cd project failed"

    printf '\n\n' | "$WORKBRANCH" add feat+branch-name >/dev/null 2>&1 || fail "add failed"
    out=$("$WORKBRANCH" list 2>&1)

    assert_contains "$out" "feat+branch-name"
    assert_contains "$out" "feat/branch-name"
  }
  ```

- [x] Add a push or land smoke only if existing branch-override tests do not already prove metadata consumers. Prefer reusing current tests unless a real gap appears.

  Existing proof to review before adding more tests:

  ```text
  tests/cases/add.sh:test_add_task_branch_override_is_used_by_later_commands
  tests/cases/remove.sh:test_remove_deletes_overridden_task_branches
  tests/cases/status.sh:test_list_shows_overridden_task_branches
  ```

- [x] Run targeted consumers.

  ```bash
  scripts/build-workbranch.sh
  ./tests/run.sh
  ```

  Expected: the full suite passes through the conventional-folder list regression and the existing metadata consumer tests.

### Task 6: Full generated-surface verification

**Files:**
- Generated: `bin/workbranch`

- [x] Rebuild the generated CLI.

  ```bash
  scripts/build-workbranch.sh
  ```

  Expected: exits 0 and `bin/workbranch` is regenerated from `src/workbranch/**`.

- [x] Run syntax checks.

  ```bash
  /bin/bash -n bin/workbranch install.sh tests/run.sh
  ```

  Expected: exits 0.

- [x] Run the full integration suite.

  ```bash
  ./tests/run.sh
  ```

  Expected: all tests pass. Report the final `Tests passed: N` line from the actual run.

- [x] Run whitespace check.

  ```bash
  git diff --check
  ```

  Expected: exits 0.

- [x] Manual QA through the CLI surface.

  Use a temporary fixture or the existing test harness pattern to exercise:

  ```bash
  workbranch add
  workbranch path feat+branch-name
  workbranch list
  workbranch remove feat+branch-name --force
  ```

  Expected observable behavior:

  - `workbranch add` asks for task type and detail name.
  - It creates `feat+branch-name/<repo>` folders.
  - Task worktrees are on `feat/branch-name` for main/master-style bases and `<base-branch>-branch-name` for parent feature bases unless overridden.
  - `path`, `list`, and `remove` use the folder identity and show/use the branch metadata correctly.
  - `workbranch path feat+branch-name/` and `workbranch remove feat+branch-name/ --force` tolerate the completion-added trailing slash.

## Completion Evidence

- Build: `scripts/build-workbranch.sh` exited 0 and regenerated `bin/workbranch`.
- Syntax: `/bin/bash -n bin/workbranch install.sh tests/run.sh` exited 0.
- Full integration suite: `./tests/run.sh` exited 0 with `Tests passed: 138`.
- Whitespace: `git diff --check` exited 0.
- Manual CLI smoke: temporary project verified `workbranch add` zero-arg prompts, `feat+branch-name` branches, `workbranch path feat+branch-name/`, `workbranch list`, and `workbranch remove feat+branch-name/ --force`.
- Follow-up evidence after interactive `add <detail>` correction: `./tests/run.sh` exited 0 with `Tests passed: 140`; added PTY coverage for `workbranch add implement-login` prompting `Task type [feat]` and `Task detail name [implement-login]`; added forced-color coverage for add repo/branch logs.
- Follow-up evidence after repo base-aware branch defaults: `./tests/run.sh` exited 0 with `Tests passed: 141`; added coverage for `feat+task1` on `feature/cpq` deriving `feature/cpq-task1`; removed the global `Default task branch` line in favor of repo-specific branch prompts.

## Acceptance Criteria

- New recommended task creation requires no config-time branch prefix knowledge.
- `workbranch add` with no positional task asks for task type and detail name.
- `feat+branch-name` folder identity derives `feat/branch-name` on main/master-style bases and `<base-branch>-branch-name` on parent feature bases.
- Task-taking commands tolerate completion-added trailing `/` on task keys without accepting nested paths as task names.
- Folder and branch remain separate; `.workbranch.task` remains the later-command branch source of truth.
- Base repo branch settings remain under `workbranch config`, not `workbranch add`.
- Interactive `workbranch add <detail>` asks for type and uses `<detail>` as the editable detail default.
- Existing non-interactive `workbranch add <task>` and existing `BRANCH_PREFIX` configs keep working.
- Docs teach the new mental model first and legacy prefix behavior only as compatibility.
- `bin/workbranch` is regenerated from source.
- Syntax checks, targeted tests, full `./tests/run.sh`, manual CLI smoke, and `git diff --check` pass.

## Non-Goals

- Do not remove `BRANCH_PREFIX` parsing in this slice.
- Do not rename existing task folders.
- Do not migrate existing `.workbranch.task` files.
- Do not change base repo branch configuration semantics.
- Do not remove repo-specific task branch override prompts.
- Do not introduce non-Bash dependencies.
