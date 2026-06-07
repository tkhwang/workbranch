# 0011 Shell Completion Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` before every behavior change. Make source changes under `src/workbranch/**`, register new modules in `scripts/workbranch-sources.txt`, rebuild with `scripts/build-workbranch.sh`, then verify syntax checks, targeted tests, `./tests/run.sh`, and `git diff --check`. Do not edit `bin/workbranch` by hand.

**Goal:** Add `workbranch completion <shell>` so users get tab-completion for commands, task keys, `--repo` values, and `--from`/option flags in bash, zsh, and fish, removing the need to remember exact task folder names.

**Architecture:** Ship completion as a generated script printed by a new `completion` command. The completion script stays thin: static command/flag lists are hard-coded in the script, while dynamic values (task keys, repo names) are produced at completion time by hidden helper subcommands that reuse existing project discovery. This keeps completion in sync with real workspace state without duplicating discovery logic.

**Tech Stack:** Portable Bash, Git worktrees, line-oriented `.workbranch.config`, task metadata in `<task>/.workbranch.task`, generated single-file CLI via `scripts/build-workbranch.sh`, integration tests in `tests/run.sh`.

---

## Problem Statement

Every existing-task command (`remove`, `update`, `push`, `land`, `path`, `finder`, `ide`, `terminal`) requires the exact task folder key such as `feat-login`. Users must either remember it or run `workbranch list` first. There is no completion, even though `normalize_task_argument` already tolerates a completion-added trailing `/` (see `src/workbranch/lib/task-identity.sh`), which shows completion was anticipated but never delivered.

The product goal is: typing `workbranch update <TAB>` lists existing task keys; `workbranch status --repo <TAB>` lists configured repos; `workbranch <TAB>` lists commands.

## Current Repo Evidence

- Commands are dispatched in `src/workbranch/main.sh` via a `case "$cmd"` block (`config init add list path ide finder terminal status pull update push land remove version help`).
- Help text already enumerates commands and flags in `src/workbranch/usage.sh` (`usage_plain` and `usage_enhanced`).
- Task workspaces are discovered by iterating `"$PROJECT_ROOT"/*` and testing `is_task_workspace_path` (`src/workbranch/lib/status-format.sh`, used by `src/workbranch/commands/status.sh` and `src/workbranch/commands/list.sh`).
- Repo names live in `REPO_NAMES`, accessed via `repo_name_at` (`src/workbranch/lib/config.sh`).
- `parse_repo_option` consumes `--repo <repo>` into `FILTER_REPO`; `add` parses `--from <ref>`.
- `require_project` resolves `PROJECT_ROOT` by walking up to `.workbranch.config`.
- The single-file CLI is generated; modules are concatenated in `scripts/workbranch-sources.txt` order by `scripts/build-workbranch.sh`.
- The installer (`install.sh`) copies only the `workbranch` binary; it does not install completion.

## Product Decisions

1. **`workbranch completion <shell>` prints a script to stdout.**
   - Supported shells: `bash`, `zsh`, `fish`.
   - No argument or unknown shell prints usage and exits non-zero.
   - Printing only; it never writes to user rc files. Docs show how to source it.

2. **Dynamic values come from hidden helper subcommands.**
   - `workbranch __complete-tasks` prints existing task keys, one per line.
   - `workbranch __complete-repos` prints configured repo names, one per line.
   - `workbranch __complete-commands` prints user-facing command names, one per line.
   - Hidden commands are not shown in `help`/usage and are double-underscore-prefixed to signal internal use.
   - Outside a project, `__complete-tasks`/`__complete-repos` exit 0 with no output (completion must never error or block).

3. **Completion is platform-agnostic.**
   - `completion` and the `__complete-*` helpers run on every platform where the binary can print text (they do not touch Git worktrees or app launchers), so treat them like `help`/`version` in `main.sh` and keep them usable even when `WORKBRANCH_TEST_PLATFORM=other`.

4. **Static lists live in the generated script.**
   - Command names and per-command flags are written literally into the completion script.
   - Only task keys and repo names are resolved dynamically.

5. **Completion display colors are shell-owned.**
   - The generated completion scripts must not inject ANSI color codes into completion candidates.
   - Candidate color, including light-gray/dim preview text, is controlled by the user's shell, completion framework, and terminal theme.
   - This slice may provide plain candidates and shell-native descriptions where practical, but it does not promise custom colored candidate text.

6. **Per-command argument awareness.**
   - Existing task-key completion applies to: `remove update push land path finder ide terminal`.
   - `add` does not complete existing task keys because it creates a new workspace; it only completes its own flags.
   - `--repo <value>` completes repo names for commands that accept `--repo`: `status pull update push land path finder ide terminal`.
   - `add --from <value>` does not complete refs in this slice (refs are unbounded); only the flag itself completes.

7. **Command-specific flag matrix.**
   - `add`: `--from`
   - `config`: `--rewrite`
   - `remove`: `--force`
   - `update`: `--all`, `--repo`
   - `status`, `pull`, `push`, `land`, `path`, `finder`, `ide`, `terminal`: `--repo`
   - `init`, `list`, `help`, `version`, `completion`: no command-specific flags in this slice.

## Target UX

```bash
$ workbranch <TAB>
add  completion  config  finder  help  ide  init  land  list  path  pull  push  remove  status  terminal  update  version

$ workbranch update <TAB>
feat-login  fix-status-output

$ workbranch status --repo <TAB>
backend  frontend

# Enable (bash)
$ workbranch completion bash > ~/.local/share/bash-completion/completions/workbranch
# Enable (zsh): place on an fpath dir, or:
$ workbranch completion zsh > "${fpath[1]}/_workbranch"
# Enable (fish)
$ workbranch completion fish > ~/.config/fish/completions/workbranch.fish
```

## Decision Gates

- [x] Completion artifact placement
  - Impact: new source module and test case file names/locations.
  - Current evidence: command modules live under `src/workbranch/commands/*.sh`; generated source order is controlled by `scripts/workbranch-sources.txt`; test cases live under `tests/cases/*.sh` and are sourced by `tests/run.sh`.
  - Recommended default: create `src/workbranch/commands/completion.sh` and `tests/cases/completion.sh`, registered immediately before `src/workbranch/main.sh` and in the completion-related section of `tests/run.sh`.
  - Recommended rationale: this keeps completion with other user-facing command implementations, preserves the generated single-file build model, and keeps shell-completion tests isolated from unrelated meta/display tests. The main alternative, putting helpers in `src/workbranch/lib/completion.sh`, would be less aligned because the primary behavior is a command surface (`workbranch completion <shell>` plus hidden command handlers), not a reusable library used by multiple commands.
  - Status: resolved: use `src/workbranch/commands/completion.sh` and `tests/cases/completion.sh`.

## Target File Structure

```text
src/workbranch/commands/completion.sh   # new: cmd_completion + __complete-* helpers
src/workbranch/main.sh                   # dispatch completion + hidden __complete-* (exempt from platform gate)
src/workbranch/usage.sh                  # document `completion <shell>` under a new section
scripts/workbranch-sources.txt           # register completion.sh before main.sh
tests/cases/completion.sh                # new integration tests
tests/run.sh                             # register completion tests
README.md                                # document enabling completion
README.ko.md                             # Korean mirror
bin/workbranch                           # regenerated only by scripts/build-workbranch.sh
```

## Implementation Tasks

### Task 1: Hidden discovery helpers with focused tests

**Files:**
- Create: `src/workbranch/commands/completion.sh`
- Modify: `src/workbranch/main.sh`, `scripts/workbranch-sources.txt`, `tests/cases/completion.sh`, `tests/run.sh`

- [x] Add a failing test asserting `workbranch __complete-tasks` lists created task keys and `__complete-repos` lists repo names.

  ```bash
  test_complete_helpers_list_tasks_and_repos() {
    new_fixture
    cd "$FIXTURE_PROJECT" || fail "cd project failed"
    run_expect_success "$WORKBRANCH" init >/dev/null
    printf '\n\n' | "$WORKBRANCH" add feat-login >/dev/null 2>&1 || fail "add failed"

    tasks=$("$WORKBRANCH" __complete-tasks)
    repos=$("$WORKBRANCH" __complete-repos)

    assert_contains "$tasks" "feat-login"
    assert_contains "$repos" "frontend"
    assert_contains "$repos" "backend"
  }

  test_complete_tasks_is_silent_outside_project() {
    TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
    out=$(cd "$TMP_ROOT" && "$WORKBRANCH" __complete-tasks; echo "status=$?")
    assert_contains "$out" "status=0"
  }
  ```

- [x] Register both tests in `tests/run.sh`.

- [x] Implement helpers in `src/workbranch/commands/completion.sh`:

  ```bash
  cmd_complete_tasks() {
    find_project_root || return 0
    parse_project_config 2>/dev/null || return 0
    for path in "$PROJECT_ROOT"/*; do
      is_task_workspace_path "$path" || continue
      printf '%s\n' "${path##*/}"
    done
  }

  cmd_complete_repos() {
    find_project_root || return 0
    parse_project_config 2>/dev/null || return 0
    i=0
    while [ $i -lt ${#REPO_NAMES[@]} ]; do
      repo_name_at "$i"; printf '\n'
      i=$((i + 1))
    done
  }

  cmd_complete_commands() {
    printf '%s\n' add completion config finder help ide init land list path pull push remove status terminal update version
  }
  ```

- [x] Dispatch the hidden commands in `src/workbranch/main.sh`, exempting them from the platform gate like `help`/`version`:

  ```bash
  case "$cmd" in
    help|-h|--help|version|-v|--version|config|ide|finder|terminal|completion|__complete-tasks|__complete-repos|__complete-commands) ;;
    *) require_core_supported_platform ;;
  esac
  ...
    completion) cmd_completion "$@" ;;
    __complete-tasks) cmd_complete_tasks ;;
    __complete-repos) cmd_complete_repos ;;
    __complete-commands) cmd_complete_commands ;;
  ```

- [x] Add `src/workbranch/commands/completion.sh` to `scripts/workbranch-sources.txt` immediately before `src/workbranch/main.sh`.

- [x] Rebuild and run: `scripts/build-workbranch.sh && ./tests/run.sh`. Evidence: `Tests passed: 144`.

### Task 2: `completion bash` and `completion zsh` script emission

**Files:**
- Modify: `src/workbranch/commands/completion.sh`, `tests/cases/completion.sh`, `tests/run.sh`

- [x] Add failing tests asserting the emitted scripts contain the expected shell hooks and call back into the binary.

  ```bash
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

    COMP_WORDS=(workbranch status --repo "")
    COMP_CWORD=3
    _workbranch
    assert_contains "${COMPREPLY[*]}" "frontend"
    assert_contains "${COMPREPLY[*]}" "backend"
  }

  test_completion_bash_uses_command_specific_flags() {
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

    COMP_WORDS=(workbranch add --)
    COMP_CWORD=2
    _workbranch
    assert_contains "${COMPREPLY[*]}" "--from"
    assert_not_contains "${COMPREPLY[*]}" "--force"
  }
  ```

- [x] Implement `cmd_completion`:
  - `cmd_completion bash` prints a bash completion function `_workbranch` that:
    - completes command names on the first word via `workbranch __complete-commands`;
    - after an existing-task command, completes `$(workbranch __complete-tasks)`;
    - does not complete existing tasks for `add`;
    - after `--repo`, completes `$(workbranch __complete-repos)`;
    - offers only the flags valid for the current command when the current word starts with `-`.
  - `cmd_completion zsh` prints a `#compdef workbranch` function using `_describe`/`compadd` backed by the same helpers.
  - Unknown/missing shell: print `usage: workbranch completion <bash|zsh|fish>` to stderr and `return 1`.
  - Use single-quoted heredocs so `$` in the generated script is not expanded at build time.

- [x] Verify the emitted bash script is itself syntactically valid:

  ```bash
  "$WORKBRANCH" completion bash | /bin/bash -n -
  ```

- [x] Rebuild and run the suite. Evidence: `Tests passed: 149`; `bin/workbranch completion bash | /bin/bash -n -` exited 0.

### Task 3: `completion fish` and usage/help surface

**Files:**
- Modify: `src/workbranch/commands/completion.sh`, `src/workbranch/usage.sh`, `tests/cases/completion.sh`, `tests/cases/meta.sh`, `tests/run.sh`

- [x] Add a failing test for `completion fish`:

  ```bash
  test_completion_fish_emits_complete_command() {
    out=$("$WORKBRANCH" completion fish)
    assert_contains "$out" "complete -c workbranch"
    assert_contains "$out" "__complete-tasks"
  }
  ```

- [x] Implement the fish branch using `complete -c workbranch` rules, deriving tasks/repos from `(workbranch __complete-tasks)` / `(workbranch __complete-repos)`.

- [x] Add a `Completion` section to both `usage_plain` and `usage_enhanced` in `src/workbranch/usage.sh`:

  ```text
  Completion:
    completion <shell>   Print a shell completion script (bash, zsh, fish)
  ```

- [x] Update `tests/cases/meta.sh:test_help_groups_commands` to assert the new completion usage line appears.

- [x] Rebuild and run the suite. Evidence: `Tests passed: 150`.

### Task 4: Docs and full verification

**Files:**
- Modify: `README.md`, `README.ko.md`
- Generated: `bin/workbranch`

- [x] Add a "Shell completion" section to `README.md` and mirror it in `README.ko.md` showing the three enable commands from Target UX.

- [x] Rebuild: `scripts/build-workbranch.sh`.

- [x] Syntax check: `/bin/bash -n bin/workbranch install.sh tests/run.sh`.

- [x] Full suite: `./tests/run.sh` (report final `Tests passed: N`). Evidence: `Tests passed: 150`.

- [x] Platform smoke: `WORKBRANCH_TEST_PLATFORM=other bin/workbranch completion bash >/dev/null` and `WORKBRANCH_TEST_PLATFORM=other bin/workbranch __complete-commands` both exit 0.

- [x] Emitted-script syntax: `bin/workbranch completion bash | /bin/bash -n -`.

- [x] Whitespace: `git diff --check`.

- [x] Manual smoke in a fixture: source `workbranch completion bash`, call `_workbranch` with `COMP_WORDS`/`COMP_CWORD`, and confirm `workbranch update <TAB>` lists task keys while `workbranch status --repo <TAB>` lists repos. Evidence: `update` completed `feat-login`; `status --repo` completed `frontend backend`.

## Acceptance Criteria

- `workbranch completion bash|zsh|fish` prints a valid, sourceable completion script.
- After sourcing, command names, task keys, and `--repo` repo names complete correctly.
- Hidden `__complete-*` helpers are silent (exit 0, no output) outside a project and never block.
- `completion` and `__complete-*` work on macOS, Linux, and WSL.
- Help/usage documents the `completion` command; README explains enabling it in all three shells.
- `bin/workbranch` is regenerated from source; syntax checks, full `./tests/run.sh`, and `git diff --check` pass.

## Non-Goals

- Do not auto-install completion from `install.sh` (separate follow-up).
- Do not complete `--from <ref>` git ref values.
- Do not add completion for PowerShell or other shells.
- Do not introduce non-Bash runtime dependencies.
- Do not force custom colors or ANSI styling in completion candidates; completion display colors remain shell/terminal-owned.
