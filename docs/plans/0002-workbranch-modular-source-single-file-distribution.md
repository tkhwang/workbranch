# Workbranch Modular Source / Single-File Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Use `superpowers:test-driven-development` before behavior changes.

**Goal:** Refactor `workbranch` so developers edit a modular Bash source tree while both curl/wget and Homebrew install the same generated single-file executable.

**Architecture:** Keep `workbranch` as a single-file distributed CLI, but make that file a generated artifact. Authoring source lives under `src/workbranch/**`, `scripts/build-workbranch.sh` concatenates sources in a deterministic order, and `bin/workbranch` remains the tracked install artifact for raw download, release tarballs, and Homebrew formula installation.

**Tech Stack:** Bash, Git worktree, existing `tests/run.sh` integration suite, Homebrew formula packaging, curl/wget raw-file install.

---

## Decision Summary

Use this split:

```text
source of truth for editing:  src/workbranch/**
generated install artifact:   bin/workbranch
installer input:              bin/workbranch
Homebrew formula input:       bin/workbranch from release tarball
```

This preserves the original reason for a single file: curl/wget installation stays simple. It also removes the current maintenance problem: future command work happens in focused files such as `src/workbranch/commands/update.sh` and `src/workbranch/git-ops.sh` instead of a 1600+ line monolith.

Homebrew compatibility supports this direction: formulae are created from URLs/tarballs and can install files into `bin`; `libexec` is available for private multi-file runtime payloads, but this plan intentionally avoids that because both install channels should run the same artifact. References: <https://docs.brew.sh/Formula-Cookbook>, <https://docs.brew.sh/rubydoc/Formula>.

## Current State and Constraints

- Current CLI entrypoint: `bin/workbranch`.
- Current installer: `install.sh` expects an installable `bin/workbranch` payload.
- Current integration suite: `tests/run.sh`, previously verified at 35 passing tests.
- User-facing CLI output should keep concise `[*]`, `[+]`, `[-]` prefixes.
- Legacy config compatibility must remain intact: `.tasktree.config` and `.monotree.config` remain accepted where currently supported.
- `workbranch pull` / `workbranch update` base-branch/rebase preflight guarantees must remain intact.
- Do not introduce a runtime dependency or require Homebrew for curl/wget users.
- Do not make Homebrew and curl/wget install different runtime layouts.

## Target File Structure

```text
bin/
  workbranch                         # generated, tracked, executable install artifact

src/workbranch/
  globals.sh                         # global variables and arrays
  usage.sh                           # help text only
  lib/
    output.sh                        # info/success/die
    validation.sh                    # safe-name and whitespace validation
    config.sh                        # parse/write config and legacy rewrite parser
    project.sh                       # project discovery and path helpers
    preflight.sh                     # preflight error collector and git safety checks
    rollback.sh                      # command-created path/worktree/branch rollback
    status-format.sh                 # status table formatting and diff labels
    prompts.sh                       # interactive init/config prompts
    task-setup.sh                    # TASK_SETUP execution contract
  commands/
    config.sh
    init.sh
    setup.sh
    add.sh
    list.sh
    status.sh
    pull.sh
    update.sh
    push.sh
    land.sh
    remove.sh
  git-ops.sh                         # exact git command wrappers documented by docs/git-operations.md
  main.sh                            # command dispatch only

scripts/
  workbranch-sources.txt             # deterministic bundle manifest
  build-workbranch.sh                # builds bin/workbranch from src/workbranch/**

packaging/homebrew/
  workbranch.rb                      # formula template for tap/release process
```

## Layering Rules

1. `commands/*.sh` may orchestrate workflow and call `preflight_*`, `workbranch_git_*`, and domain helpers.
2. `commands/*.sh` must not embed raw mutating Git commands except for trivial read-only checks already present before the split. Prefer `git-ops.sh` for documented operations.
3. `git-ops.sh` contains the exact mutating Git commands mirrored by `docs/git-operations.md`.
4. `preflight.sh` collects all pre-mutation safety checks and error formatting.
5. `config.sh` owns strict config parsing and legacy rewrite parsing.
6. `main.sh` only parses the top-level command name and dispatches to `cmd_*`.
7. `bin/workbranch` is generated; direct edits to it are overwritten by `scripts/build-workbranch.sh`.

## Acceptance Criteria

- `bin/workbranch` remains a single executable file that can be downloaded and run without any sibling files.
- `scripts/build-workbranch.sh` deterministically rebuilds `bin/workbranch` from `src/workbranch/**`.
- A test fails if `bin/workbranch` is stale relative to `src/workbranch/**`.
- Existing 35 integration tests still pass after the modular split.
- Installer behavior remains compatible with current checkout, pipe, and standalone flows.
- Homebrew packaging installs the same generated `bin/workbranch` artifact that curl/wget installs.
- The public command contract in `docs/git-operations.md` remains aligned with `src/workbranch/git-ops.sh`.
- No new runtime dependencies are introduced.

## Implementation Tasks

### Task 1: Establish generated artifact pipeline without changing behavior

**Files:**

- Create: `src/workbranch/monolith.sh`
- Create: `scripts/workbranch-sources.txt`
- Create: `scripts/build-workbranch.sh`
- Modify: `bin/workbranch`
- Test: `tests/run.sh`

- [ ] **Step 1: Copy the current executable body into source**

Run:

```bash
mkdir -p src/workbranch scripts
tail -n +2 bin/workbranch > src/workbranch/monolith.sh
```

Expected: `src/workbranch/monolith.sh` contains the current script body without the shebang.

- [ ] **Step 2: Create the initial source manifest**

Create `scripts/workbranch-sources.txt`:

```text
# Ordered source files for generated bin/workbranch.
# Do not list bin/workbranch here; it is the generated output.
src/workbranch/monolith.sh
```

- [ ] **Step 3: Create the build script**

Create `scripts/build-workbranch.sh`:

```bash
#!/usr/bin/env bash
set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
manifest=${WORKBRANCH_SOURCE_MANIFEST:-"$repo_root/scripts/workbranch-sources.txt"}
out=${1:-"$repo_root/bin/workbranch"}
tmp="$out.tmp.$$"

{
  printf '#!/usr/bin/env bash\n'
  printf '# Generated by scripts/build-workbranch.sh; edit src/workbranch/** instead.\n'
  printf '# shellcheck shell=bash\n'
  while IFS= read -r source_path || [ -n "$source_path" ]; do
    case "$source_path" in
      ''|'#'*) continue ;;
    esac
    full_path="$repo_root/$source_path"
    [ -f "$full_path" ] || {
      printf 'missing source file: %s\n' "$source_path" >&2
      exit 1
    }
    printf '\n# ----- %s -----\n' "$source_path"
    sed '1{/^#!/d;}' "$full_path"
  done < "$manifest"
} > "$tmp"

/bin/bash -n "$tmp"
mv "$tmp" "$out"
chmod +x "$out"
```

- [ ] **Step 4: Build the generated executable**

Run:

```bash
chmod +x scripts/build-workbranch.sh
./scripts/build-workbranch.sh
/bin/bash -n bin/workbranch scripts/build-workbranch.sh install.sh tests/run.sh
```

Expected: syntax check passes. Behavior may not be byte-identical because the generated header is new, but command behavior must remain unchanged.

- [ ] **Step 5: Add stale-artifact regression test**

Add this test to `tests/run.sh` near the other top-level smoke tests:

```bash
test_generated_workbranch_is_up_to_date() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  generated="$TMP_ROOT/workbranch.generated"
  "$REPO_ROOT/scripts/build-workbranch.sh" "$generated" >/dev/null
  cmp "$generated" "$WORKBRANCH" >/dev/null || fail "bin/workbranch is stale; run scripts/build-workbranch.sh"
}
```

Register it near the start of `main()` after the executable/git checks:

```bash
run_test test_generated_workbranch_is_up_to_date
```

- [ ] **Step 6: Verify**

Run:

```bash
/bin/bash -n bin/workbranch scripts/build-workbranch.sh install.sh tests/run.sh
git diff --check
/bin/bash ./tests/run.sh
```

Expected: all tests pass, including the new stale-artifact test.

- [ ] **Step 7: Commit checkpoint**

Use a Lore-style commit message if committing:

```text
Preserve single-file installs while introducing generated source

Constraint: curl/wget and Homebrew must install the same single-file artifact.
Rejected: multi-file runtime layout | would make install channels diverge.
Confidence: high
Scope-risk: narrow
Directive: edit src/workbranch/** and rebuild bin/workbranch; do not hand-edit generated output.
Tested: /bin/bash -n bin/workbranch scripts/build-workbranch.sh install.sh tests/run.sh; git diff --check; /bin/bash ./tests/run.sh
```

### Task 2: Split the monolith into source modules mechanically

**Files:**

- Create: `src/workbranch/globals.sh`
- Create: `src/workbranch/usage.sh`
- Create: `src/workbranch/lib/*.sh`
- Create: `src/workbranch/commands/*.sh`
- Create: `src/workbranch/git-ops.sh`
- Create: `src/workbranch/main.sh`
- Modify: `scripts/workbranch-sources.txt`
- Modify: `bin/workbranch`
- Delete after split: `src/workbranch/monolith.sh`

- [ ] **Step 1: Create module files by moving contiguous sections only**

Move code without behavior edits. Use these boundaries:

```text
globals.sh          current global variables and arrays
usage.sh            usage()
lib/output.sh       info(), success(), die()
lib/validation.sh   is_safe_name(), has_whitespace(), validate_*()
lib/config.sh       repo arrays, config parsing, write_config()
lib/project.sh      find_project_root(), require_project(), path helpers, branch naming
lib/preflight.sh    is_git_dirty(), preflight_*(), git ref checks, rebase checks
lib/rollback.sh     rollback_created(), fail_with_rollback(), track_*()
lib/prompts.sh      prompt_*(), expand_path(), cmd_init_interactive support helpers
lib/task-setup.sh   repo_names_joined(), run_task_setup()
lib/status-format.sh status table and diff formatting helpers
commands/*.sh       one file per cmd_* implementation
git-ops.sh          workbranch_git_* definitions
main.sh             main() only
```

- [ ] **Step 2: Update the source manifest in dependency order**

Replace `scripts/workbranch-sources.txt` with:

```text
src/workbranch/globals.sh
src/workbranch/lib/output.sh
src/workbranch/usage.sh
src/workbranch/lib/validation.sh
src/workbranch/lib/config.sh
src/workbranch/lib/project.sh
src/workbranch/lib/preflight.sh
src/workbranch/lib/rollback.sh
src/workbranch/lib/prompts.sh
src/workbranch/lib/task-setup.sh
src/workbranch/lib/status-format.sh
src/workbranch/commands/config.sh
src/workbranch/commands/init.sh
src/workbranch/commands/setup.sh
src/workbranch/commands/add.sh
src/workbranch/commands/list.sh
src/workbranch/commands/status.sh
src/workbranch/commands/pull.sh
src/workbranch/commands/update.sh
src/workbranch/commands/push.sh
src/workbranch/commands/land.sh
src/workbranch/commands/remove.sh
src/workbranch/git-ops.sh
src/workbranch/main.sh
```

- [ ] **Step 3: Rebuild**

Run:

```bash
./scripts/build-workbranch.sh
/bin/bash -n bin/workbranch scripts/build-workbranch.sh install.sh tests/run.sh
```

Expected: syntax check passes.

- [ ] **Step 4: Verify behavior is unchanged**

Run:

```bash
/bin/bash ./tests/run.sh
```

Expected: all tests pass.

- [ ] **Step 5: Commit checkpoint**

Use a Lore-style commit message if committing:

```text
Make workbranch commands editable without changing runtime shape

Constraint: bin/workbranch remains the install artifact for every channel.
Rejected: splitting runtime files | would complicate curl/wget installs and Homebrew parity.
Confidence: medium
Scope-risk: moderate
Directive: keep manifest order explicit; command modules should orchestrate, git-ops should execute documented Git commands.
Tested: /bin/bash -n bin/workbranch scripts/build-workbranch.sh install.sh tests/run.sh; /bin/bash ./tests/run.sh
```

### Task 3: Add command-boundary documentation for maintainers

**Files:**

- Modify: `docs/git-operations.md`
- Modify: `README.md`
- Create: `docs/architecture.md`

- [ ] **Step 1: Create architecture documentation**

Create `docs/architecture.md`:

```markdown
# Workbranch architecture

`workbranch` is authored as modular Bash under `src/workbranch/**` and distributed as one generated executable at `bin/workbranch`.

## Edit/build rule

- Edit `src/workbranch/**`.
- Run `scripts/build-workbranch.sh`.
- Commit both source changes and the regenerated `bin/workbranch`.
- Do not hand-edit `bin/workbranch`.

## Command boundary

Each user command should have one `src/workbranch/commands/<command>.sh` file.

A command file owns orchestration:

1. parse command-specific args
2. validate project/config/task names
3. run preflight checks before mutation
4. call `workbranch_git_*` functions for documented Git operations
5. print concise user-facing status

`src/workbranch/git-ops.sh` owns the exact mutating Git commands mirrored by `docs/git-operations.md`.

`src/workbranch/lib/preflight.sh` owns safety checks and aggregate preflight failure reporting.
```

- [ ] **Step 2: Link architecture from README**

Add a short maintainer section to `README.md`:

```markdown
## Development

`workbranch` is developed as modular Bash under `src/workbranch/**`, then bundled into the single-file executable `bin/workbranch`.

```bash
scripts/build-workbranch.sh
/bin/bash ./tests/run.sh
```

Do not edit `bin/workbranch` directly. See [`docs/architecture.md`](docs/architecture.md).
```

- [ ] **Step 3: Add source pointer to git operations doc**

Update the existing source pointer in `docs/git-operations.md` to reference `src/workbranch/git-ops.sh` and mention that `bin/workbranch` is generated.

- [ ] **Step 4: Verify docs and generated artifact**

Run:

```bash
./scripts/build-workbranch.sh
git diff --check
/bin/bash ./tests/run.sh
```

Expected: generated artifact is current and tests pass.

### Task 4: Preserve and test installer parity

**Files:**

- Modify: `install.sh`
- Modify: `tests/run.sh`
- Modify: `README.md`

- [ ] **Step 1: Keep installer payload resolution pointed at `bin/workbranch`**

Review `install.sh` and preserve these rules:

```text
checkout install: copy ./bin/workbranch from the checkout
pipe install: do not infer cwd as source
standalone install: download from WORKBRANCH_RAW_BASE_URL/bin/workbranch
```

If current code already satisfies this, make no installer code change.

- [ ] **Step 2: Add generated-artifact assertion to installer tests**

Extend the existing pipe/standalone installer tests so they assert installed `workbranch help` contains the generated marker only indirectly through behavior, not by relying on comments:

```bash
out=$("$installed_path" help 2>&1)
assert_contains "$out" "Usage:"
assert_contains "$out" "workbranch <command> [args]"
```

- [ ] **Step 3: Document direct curl and wget artifact install**

Add to README near Install:

```markdown
### Direct single-file install

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/tkhwang/workbranch/main/bin/workbranch -o ~/.local/bin/workbranch
chmod +x ~/.local/bin/workbranch
```

```bash
mkdir -p ~/.local/bin
wget -qO ~/.local/bin/workbranch https://raw.githubusercontent.com/tkhwang/workbranch/main/bin/workbranch
chmod +x ~/.local/bin/workbranch
```

The direct file, installer script, and Homebrew formula all install the same generated `bin/workbranch` artifact.
```

- [ ] **Step 4: Verify installer tests**

Run:

```bash
./scripts/build-workbranch.sh
/bin/bash -n bin/workbranch install.sh tests/run.sh
/bin/bash ./tests/run.sh
```

Expected: installer tests still pass.

### Task 5: Add Homebrew formula template for the same artifact

**Files:**

- Create: `packaging/homebrew/workbranch.rb`
- Modify: `README.md`

- [ ] **Step 1: Create formula template**

Create `packaging/homebrew/workbranch.rb`:

```ruby
class Workbranch < Formula
  desc "Simplify branch operations for Git worktree-based development"
  homepage "https://github.com/tkhwang/workbranch"
  url "https://github.com/tkhwang/workbranch/archive/refs/tags/v0.0.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_TARBALL_SHA256"
  license "MIT"

  def install
    bin.install "bin/workbranch"
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/workbranch help")
  end
end
```

Release process replaces `v0.0.0` and `REPLACE_WITH_RELEASE_TARBALL_SHA256` before publishing to the tap.

- [ ] **Step 2: Document Homebrew release path**

Add to README:

```markdown
### Homebrew

Planned install shape:

```bash
brew tap tkhwang/workbranch
brew install workbranch
```

The formula installs `bin/workbranch` from the release tarball, so Homebrew and direct download use the same generated executable.
```

- [ ] **Step 3: Add optional local formula validation command**

Add to `docs/architecture.md` or README development section:

```bash
brew audit --strict --online packaging/homebrew/workbranch.rb
brew test packaging/homebrew/workbranch.rb
```

Mark these as optional because Homebrew may not be installed in every contributor environment.

- [ ] **Step 4: Verify non-Homebrew gates**

Run:

```bash
./scripts/build-workbranch.sh
git diff --check
/bin/bash ./tests/run.sh
```

Expected: tests pass without requiring Homebrew.

### Task 6: Refactor command internals after the split

**Files:**

- Modify: `src/workbranch/commands/add.sh`
- Modify: `src/workbranch/commands/update.sh`
- Modify: `src/workbranch/commands/push.sh`
- Modify: `src/workbranch/commands/land.sh`
- Modify: `src/workbranch/lib/config.sh`
- Modify: `src/workbranch/lib/preflight.sh`
- Modify: `src/workbranch/git-ops.sh`
- Modify: `bin/workbranch`
- Modify: `tests/run.sh`

Implement this task only after Tasks 1-5 are green.

- [ ] **Step 1: Write failing regression for `add` base preflight**

Add `test_add_preflight_requires_clean_base_on_configured_branch`:

```bash
test_add_preflight_requires_clean_base_on_configured_branch() {
  new_fixture
  project="$FIXTURE_PROJECT"
  cd "$project" || return 1

  run_expect_success "$WORKBRANCH" init >/dev/null
  git -C "$project/_base/frontend" checkout -b unrelated >/dev/null 2>&1
  printf '%s\n' "dirty base" > "$project/_base/frontend/dirty.txt"

  out=$(run_expect_fail "$WORKBRANCH" add login)
  assert_contains "$out" "Cannot add: preflight failed"
  assert_contains "$out" "_base/frontend expected branch master, got unrelated"
  assert_contains "$out" "_base/frontend dirty worktree"
  assert_not_exists "$project/login"
}
```

Register it before existing add tests.

- [ ] **Step 2: Verify RED**

Run:

```bash
/bin/bash ./tests/run.sh
```

Expected: the new test fails because `workbranch add` does not yet aggregate those base preflight errors.

- [ ] **Step 3: Implement minimal `add` preflight**

In `src/workbranch/commands/add.sh`, add a preflight pass before creating `task_dir`:

```bash
reset_preflight
i=0
while [ $i -lt ${#REPO_NAMES[@]} ]; do
  name=$(repo_name_at "$i")
  base=$(base_repo_path "$name")
  base_branch=$(repo_base_branch_at "$i")
  base_label="$BASE_DIR/$name"
  if [ ! -d "$base/.git" ] && [ ! -f "$base/.git" ]; then
    preflight_error "$base_label missing git repo"
    i=$((i + 1))
    continue
  fi
  preflight_require_current_branch "$base_label" "$base" "$base_branch"
  preflight_require_clean "$base_label" "$base"
  preflight_require_no_rebase "$base_label" "$base"
  i=$((i + 1))
done
preflight_die_if_errors "add"
```

Rebuild:

```bash
./scripts/build-workbranch.sh
```

- [ ] **Step 4: Verify GREEN**

Run:

```bash
/bin/bash ./tests/run.sh
```

Expected: all tests pass.

- [ ] **Step 5: Remove accidental complexity one category at a time**

Apply these cleanup passes sequentially, rebuilding and testing after each pass:

```text
1. Replace eval-based Bash array reads with native array reads.
2. Delete unused land git-op helpers if still unused after the split.
3. Unify strict and legacy config parser validation while preserving behavior.
4. Disable pathname expansion during config tokenization.
5. Document or remove the `update --all` alias; prefer documenting because it is backward compatible.
6. Report retained task directories when `remove` cannot delete the task directory because user files remain.
7. Document the `TASK_SETUP` trust model.
```

After each cleanup pass run:

```bash
./scripts/build-workbranch.sh
/bin/bash ./tests/run.sh
```

Expected: tests stay green after every pass.

## Verification Matrix

Run this full matrix before claiming completion:

```bash
./scripts/build-workbranch.sh
/bin/bash -n bin/workbranch scripts/build-workbranch.sh install.sh tests/run.sh
git diff --check
/bin/bash ./tests/run.sh
```

Optional when available:

```bash
shellcheck bin/workbranch scripts/build-workbranch.sh install.sh tests/run.sh
brew audit --strict --online packaging/homebrew/workbranch.rb
brew test packaging/homebrew/workbranch.rb
```

## Release Checklist

For a tagged release:

```bash
./scripts/build-workbranch.sh
/bin/bash ./tests/run.sh
git diff --exit-code bin/workbranch
```

Then:

1. Tag the release.
2. Publish the source tarball or GitHub release.
3. Compute the tarball SHA256.
4. Update the Homebrew formula URL and SHA256 in the tap.
5. Verify direct install uses the tagged `bin/workbranch` raw URL.
6. Verify Homebrew install and direct curl/wget install report the same `workbranch help` output.

## Explicitly Deferred

- Multi-file runtime installation under Homebrew `libexec`.
- Rewriting the CLI in another language.
- Replacing the existing installer UX.
- Changing command semantics while doing the mechanical source split.
- Adding ShellCheck as a required dependency.

## Self-Review

- Spec coverage: covers modular source, generated single-file distribution, curl/wget install, Homebrew install, tests, and command-boundary maintainability.
- Placeholder scan: formula version and SHA placeholders are intentionally release-time values and are explicitly bounded to `packaging/homebrew/workbranch.rb`.
- Scope check: plan is one refactoring project with a mechanical split first and behavior hardening only after the generated artifact pipeline is proven.
