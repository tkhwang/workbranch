# 0040 Feature-Base Name-Only Task Prompt and Mirrored Task Folder Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` before every behavior change. Steps use checkbox (`- [ ]`) syntax for tracking. Make source changes under `apps/cli/src/workbranch/**`, rebuild with `apps/cli/scripts/build-workbranch.sh`, then verify syntax checks, targeted tests, `apps/cli/tests/run.sh`, and `git diff --check`. Do not edit `bin/workbranch` or `apps/cli/bin/workbranch` by hand.

**Goal:** When a project's repos are based on a parent feature branch such as `feature/cpq`, stop asking for a conventional task *type* that is never used, ask only for the task *name*, and make the task folder mirror the resulting branch (`feature/cpq-task1` → folder `feature-cpq-task1`) instead of dropping the parent context (`feat-task1`).

**Architecture:** The task folder and the Git branch stay separate surfaces, but they become *visibly consistent*: a folder is the branch with `/` replaced by `-`. The conventional `type` only carries meaning when it actually appears in the branch (main/master-style bases → `feat/task1`). On parent feature bases the branch is `feature/cpq-task1`, so the type is vestigial; the creation prompt drops it and asks for the name only. Branch derivation is decoupled from re-parsing a conventional `type-` prefix out of the folder, so a parent-slug folder (`feature-cpq-task1`) still resolves to `feature/cpq-task1` rather than `feature/cpq-feature-cpq-task1`. The rule is applied only when it is unambiguous: every repo shares one identical parent feature base.

**Tech Stack:** Portable Bash, Git worktrees, line-oriented `.workbranch.config`, task metadata in `<task>/.workbranch.task`, generated single-file CLI via `apps/cli/scripts/build-workbranch.sh`, integration tests in `apps/cli/tests/run.sh`.

---

## Problem Statement

`workbranch add` derives task identity from a conventional commit type plus a detail name. On main/master-style bases this is correct: `feat` + `task1` → folder `feat-task1`, branch `feat/task1`. The type is part of the branch, so asking for it is meaningful.

On a parent feature base such as `feature/cpq`, the branch is built from the *parent* slug, not the type:

```text
base feature/cpq + add feat-task1
  branch -> feature/cpq-task1     # type "feat" is dropped
  folder -> feat-task1            # type "feat" is kept, parent "cpq" is dropped
```

Two problems follow:

1. **The prompt asks for a value it then ignores.** The user picks `feat`, but the branch never uses it. This is confusing.
2. **The folder loses the parent context the branch keeps.** The branch nests under `feature/cpq` but the folder (`feat-task1`) does not mention `cpq`, so the folder and branch tell different stories.

The desired model on a parent feature base:

```text
base feature/cpq + name task1
  prompt -> Task name: task1       # no type prompt
  branch -> feature/cpq-task1
  folder -> feature-cpq-task1      # folder = branch with "/" -> "-"
```

On main/master-style bases nothing changes:

```text
base main + type feat + detail task1
  prompt -> Task type [feat], Task detail name
  branch -> feat/task1
  folder -> feat-task1             # folder = branch with "/" -> "-"
```

## Current Repo Evidence

- `apps/cli/src/workbranch/lib/task-identity.sh`
  - `task_folder_from_identity` produces `type-detail` (uses `-`); `task_branch_from_identity` produces `type/detail`.
  - `task_identity_type_from_folder`/`task_identity_detail_from_folder` split on the first `-`.
  - `validate_task_detail_name "$value" "$type"` validates the branch ref `"$type/$value"` via `git check-ref-format --branch`.
  - `task_branch_from_folder_identity` returns the conventional branch only when the folder begins with a *known* type (`feat|fix|chore|docs|refactor|test|perf|ci|build|revert`); otherwise it returns non-zero.
- `apps/cli/src/workbranch/lib/project.sh`
  - `base_branch_looks_like_parent_task_branch` matches `feature/*`, `feat/*`, and `"$prefix"/*`.
  - `base_prefixed_branch_for_task "$parent" "$task"` joins with `-` → `feature/cpq-task1`.
  - `default_repo_task_branch_at` tries `task_branch_from_folder_identity` first; if that succeeds and the base looks like a parent branch it uses `base_prefixed_branch_for_task "$base_branch" "$(detail)"`, otherwise it returns the conventional `type/detail`; if folder identity fails it falls back to base-prefixed or `default_feature_branch_for_task`.
- `apps/cli/src/workbranch/commands/add.sh`
  - `prompt_task_identity_for_add` always asks `Task type [feat]` then `Task detail name`, then builds the folder via `task_folder_from_identity`.
  - `resolve_task_for_add` routes zero-arg and interactive-bare-name input into the identity prompt; conventional `type-detail` args bypass it.
  - `cmd_add` calls `require_project` (config + bases loaded) **before** `resolve_task_for_add`, so repo base branches are already known when the identity prompt runs.
- Tests
  - `apps/cli/tests/cases/add.sh:92` `test_add_derives_conventional_branch_from_parent_feature_base`: `add feat-task1` on `feature/cpq` asserts folder `feat-task1` and branch `feature/cpq-task1`. This explicit-shorthand behavior is preserved by this plan.

Reproduction with the installed `2.7.0` binary confirms the current behavior on a single `feature/cpq` repo: folder `feat-task1`, branch `feature/cpq-task1`.

## Product Decisions

1. **Folder mirrors branch.** A task folder is the task branch with `/` replaced by `-`.
   - main/master base: branch `feat/task1` → folder `feat-task1` (unchanged).
   - parent feature base: branch `feature/cpq-task1` → folder `feature-cpq-task1` (new).

2. **No type prompt when the type is unused.** When every repo shares one identical parent feature base, interactive/zero-arg `workbranch add` asks for the task **name** only and does not ask for a conventional type.

3. **Apply only when unambiguous.** The name-only + mirrored-folder behavior applies only when *all* repos share the *same* parent feature base. Mixed bases (e.g. `feature/cpq` + `main`, or `feature/cpq` + `feature/xyz`) keep the conventional `type` + `detail` prompt and the conventional `type-detail` folder, because the type is still needed by at least one repo's branch and a single mirrored folder is no longer well defined.

4. **Backward compatibility is preserved, with TTY bare-name input treated as interactive.**
   - Explicit `workbranch add feat-task1` on a `feature/cpq` base keeps folder `feat-task1` and branch `feature/cpq-task1` (existing test stays green).
   - Non-interactive bare keys such as `workbranch add login` keep legacy folder `login`.
   - Interactive/TTY bare-name input such as `workbranch add login` follows the same base-aware prompt flow as zero-arg `workbranch add`: main/master bases ask for `Task type` with `login` prefilled as the detail; shared parent feature bases ask for `Task name` with `login` prefilled and create the mirrored parent folder.
   - Explicit parent-slug keys such as `workbranch add feature-cpq-task1` are accepted and resolve to branch `feature/cpq-task1`.

5. **Branch derivation is decoupled from folder type-parsing.** A parent-slug folder (`feature-cpq-task1`) must resolve to `feature/cpq-task1`, not `feature/cpq-feature-cpq-task1`.

6. **No change to base-branch ownership.** Base branches remain owned by `workbranch config`; `add` only reads them.

## Decision Gate (resolved in conversation)

- [x] **Folder format on parent feature bases**
  - Resolution: folder = branch with `/` → `-` (`feature/cpq-task1` → `feature-cpq-task1`).
  - Rationale: folder and branch tell the same story; the parent context is preserved.
  - Rejected: keep `feat-task1` (loses parent context, the reported problem).

- [x] **Drop the type prompt on parent feature bases**
  - Resolution: ask name only when all repos share one parent feature base.
  - Rationale: the type never reaches the branch or the mirrored folder, so prompting for it is noise.
  - Rejected: always ask type then silently ignore it.

- [x] **Explicit `add feat-task1` on a feature base**
  - Resolution: keep current behavior — folder `feat-task1`, branch `feature/cpq-task1`.
  - Rationale: backward compatibility with scripts and the existing test; the recommended path is the name-only interactive flow.
  - Rejected: rewrite the folder to `feature-cpq-task1` (breaks compatibility and an existing test).

- [x] **Multi-repo with mixed or differing bases**
  - Resolution: keep the conventional `type` + `detail` prompt and `type-detail` folder.
  - Rationale: type is still required by main/master repos; a single mirrored folder is undefined when branches differ.

- [x] **Interactive bare-name input on parent feature bases**
  - Resolution: `workbranch add <taskName>` in a TTY is interactive input, not a legacy explicit key. If all repos share one parent feature base, ask only `Task name [<taskName>]` and create the mirrored folder from the chosen name; if bases are main/master or mixed, keep the conventional `Task type` + `Task detail name [<taskName>]` flow.
  - Rationale: this matches the current routing shape (`add <detail>` already enters the prompt flow in a TTY) while making the prompt reflect whether the conventional type will actually affect the branch/folder.
  - Rejected: treat TTY `add <taskName>` as legacy explicit folder `taskName` on parent feature bases (would preserve compatibility but keep a surprising split between zero-arg and prefilled interactive add).

## Target UX

### Parent feature base (recommended new path)

Config: every repo based on `feature/cpq`.

```bash
workbranch add
```

Prompts:

```text
[*] Task name: task1
[*] Task folder: feature-cpq-task1

[*] Repo app
[*]   base branch: feature/cpq
[*]   task repo branch [feature/cpq-task1]:
[*]   task repo folder: feature-cpq-task1/app
```

Result:

```text
project
├── .workbranch.config
├── _base
│   └── app
└── feature-cpq-task1
    ├── .workbranch.task        # REPO_BRANCH app feature/cpq-task1
    └── app                      # branch feature/cpq-task1
```

### main/master base (unchanged)

```bash
workbranch add
```

```text
[*] Task type [feat]: feat
[*] Task detail name: task1
[*] Task folder: feat-task1
...
[*]   task repo branch [feat/task1]:
```

### Interactive bare name (base-aware)

```bash
workbranch add task1
```

On main/master-style bases this is still the conventional interactive flow with the provided name as the editable detail default:

```text
[*] Task type [feat]: feat
[*] Task detail name [task1]: task1
[*] Task folder: feat-task1
```

On a shared parent feature base this is the name-only interactive flow with the provided name as the editable default:

```text
[*] Task name [task1]: task1
[*] Task folder: feature-cpq-task1
```

### Explicit shorthand (unchanged / additive)

```bash
workbranch add feat-task1            # folder feat-task1, branch feature/cpq-task1 (compat)
workbranch add feature-cpq-task1     # folder feature-cpq-task1, branch feature/cpq-task1 (additive)
```

## Validation Rules

- **Name (parent feature base):** reuse the safe-name rule, and validate the *resulting* branch ref `feature/cpq-<name>` with `git check-ref-format --branch` (not `feat/<name>`).
- **Parent slug:** `feature/cpq` → `feature-cpq` is `base` with every `/` replaced by `-`. The slug must remain a safe folder segment.
- **Folder:** `feature-cpq-task1` passes existing `validate_task_folder_name` (no known conventional type prefix → legacy safe-name path). Confirm with a test rather than assuming.
- **Empty / `.` / `..`:** rejected by the existing safe-name validation.

## Target File Structure

```text
apps/cli/src/workbranch/lib/task-identity.sh   # parent-slug folder helpers; base-aware name validation
apps/cli/src/workbranch/lib/project.sh         # all-repos-share-parent-base detection; branch derivation for parent-slug folders
apps/cli/src/workbranch/commands/add.sh        # name-only identity prompt when all repos share a parent feature base
apps/cli/tests/cases/add.sh                    # new prompt/folder/branch coverage; keep existing parent-base shorthand test
apps/cli/tests/run.sh                          # register new tests in stable order
docs/task-identity.md                          # document folder-mirrors-branch + name-only prompt
docs/task-identity.ko.md                       # Korean mirror
docs/git-operations.md                         # update add naming examples
README.md / README.ko.md                       # mental-model note if the add section shows folder/branch examples
bin/workbranch, apps/cli/bin/workbranch        # regenerated only by scripts/build-workbranch.sh
```

## Implementation Tasks

### Task 1: Decouple branch derivation for parent-slug folders (TDD)

**Files:** `apps/cli/src/workbranch/lib/task-identity.sh`, `apps/cli/src/workbranch/lib/project.sh`, `apps/cli/tests/cases/add.sh`, `apps/cli/tests/run.sh`

- [x] Add a failing test: explicit `workbranch add feature-cpq-task1` on a single `feature/cpq` repo creates folder `feature-cpq-task1` and branch `feature/cpq-task1` (must NOT be `feature/cpq-feature-cpq-task1`).
- [x] Add helper `parent_branch_to_folder_slug` (base with `/` → `-`) and `task_folder_from_parent_base` (`<slug>-<name>`) in `lib/task-identity.sh`.
- [x] Update `default_repo_task_branch_at` in `lib/project.sh`: when `base_branch_looks_like_parent_task_branch` is true and `task` begins with `<parent-slug>-`, recover `name=${task#<slug>-}` and return `base_prefixed_branch_for_task "$base_branch" "$name"`. Place this check before the existing folder-identity logic so it wins for parent-slug folders while leaving `feat-task1` and bare names on their current paths.
- [x] Rebuild (`apps/cli/scripts/build-workbranch.sh`) and run targeted tests; full suite remains in Task 5.

Task 1 verification: `apps/cli/scripts/build-workbranch.sh`, `/bin/bash -n` on changed shell/test files, and targeted `test_add_parent_slug_task_folder_maps_to_parent_prefixed_branch` passed.

### Task 2: Detect a shared parent feature base across repos

**Files:** `apps/cli/src/workbranch/lib/project.sh`, `apps/cli/tests/cases/add.sh`, `apps/cli/tests/run.sh`

- [x] Add `all_repos_share_parent_feature_base`: returns success and prints the common base only when every repo base satisfies `base_branch_looks_like_parent_task_branch` AND all repo bases are byte-identical; otherwise returns non-zero.
- [x] Unit-style integration coverage (via a fixture): single `feature/cpq` repo → success printing `feature/cpq`; two `feature/cpq` repos → success; `feature/cpq` + `main` → failure; `feature/cpq` + `feature/xyz` → failure; single `main` repo → failure.
- [x] Run targeted helper test; full suite remains in Task 5.

Task 2 verification: targeted `test_all_repos_share_parent_feature_base_detects_only_identical_parent_bases` passed.

### Task 3: Name-only interactive prompt and mirrored folder

**Files:** `apps/cli/src/workbranch/commands/add.sh`, `apps/cli/tests/cases/add.sh`, `apps/cli/tests/run.sh`

- [x] Add a failing test: zero-arg `workbranch add` on a single `feature/cpq` repo prompts `Task name` (and NOT `Task type`), reports `Task folder: feature-cpq-task1`, creates folder `feature-cpq-task1`, and branch `feature/cpq-task1`.
- [x] Add a failing test: interactive/TTY `workbranch add task1` on a single `feature/cpq` repo prompts `Task name [task1]` (and NOT `Task type`), reports `Task folder: feature-cpq-task1`, creates folder `feature-cpq-task1`, and branch `feature/cpq-task1`.
- [x] Add a failing test: zero-arg `workbranch add` on a single `main` repo still prompts `Task type [feat]` and `Task detail name` and creates `feat-task1` / `feat/task1`.
- [x] Add a failing test: interactive/TTY `workbranch add task1` on a single `main` repo still prompts `Task type [feat]` and `Task detail name [task1]` and creates `feat-task1` / `feat/task1`.
- [x] Add a failing test: mixed multi-repo (`feature/cpq` + `main`) still prompts `Task type` and creates a `feat-...` folder.
- [x] Add a failing test: non-interactive `workbranch add task1` on a single `feature/cpq` repo keeps legacy folder `task1` and branch `feature/cpq-task1`.
- [x] In `prompt_task_identity_for_add` (and the routing in `resolve_task_for_add`): when `all_repos_share_parent_feature_base` succeeds, prompt for the name only, using any TTY bare-name argument as the editable default, validate the name against the real `feature/cpq-<name>` branch ref, set folder via `task_folder_from_parent_base`, and print `Task folder: <folder>`. Otherwise keep the existing type + detail flow unchanged, including using a TTY bare-name argument as the editable detail default.
- [x] Ensure user-facing prompt lines go to stderr and only the folder is printed to stdout (existing command-substitution contract).
- [x] Rebuild and run targeted tests; full suite remains in Task 5, including `test_add_derives_conventional_branch_from_parent_feature_base` (explicit `feat-task1` still → folder `feat-task1`, branch `feature/cpq-task1`).

Task 3 verification: `apps/cli/scripts/build-workbranch.sh`, `/bin/bash -n` on changed shell/test files, and targeted add prompt/compatibility tests passed.

### Task 4: Documentation

**Files:** `docs/task-identity.md`, `docs/task-identity.ko.md`, `docs/git-operations.md`, `README.md`, `README.ko.md`

- [x] Document the folder-mirrors-branch rule and the name-only prompt for parent feature bases; keep the main/master examples unchanged.
- [x] Update the parent-base examples (e.g. `docs/git-operations.md` naming table) so the folder column reads `feature-cpq-task1` for parent feature bases, while preserving the explicit-`feat-task1` compatibility note.
- [x] Mirror in Korean docs.
- [x] `git diff --check` clean; `rg` for stale `feat-task1` folder claims on feature bases.

Task 4 verification: `git diff --check` passed for changed files; stale search leaves only explicit compatibility / historical problem-description references.

### Task 5: Full generated-surface verification

**Files:** `bin/workbranch`, `apps/cli/bin/workbranch` (generated only)

- [x] `apps/cli/scripts/build-workbranch.sh` exits 0 and regenerates the CLI.
- [x] `/bin/bash -n` on generated `bin/workbranch`, `install.sh`, `apps/cli/tests/run.sh` exits 0.
- [x] `apps/cli/tests/run.sh` passes; record the final `Tests passed: N`.
- [x] `git diff --check` exits 0.
- [x] Manual CLI smoke on a temp single `feature/cpq` fixture: `workbranch add` prompts name only → `feature-cpq-task1`; `workbranch path feature-cpq-task1`, `workbranch list`, `workbranch remove feature-cpq-task1 --force` all operate on the folder identity.

Task 5 verification: `apps/cli/scripts/build-workbranch.sh` passed; `/bin/bash -n` passed for generated CLI, installer, test runner, changed shell/test files; `apps/cli/tests/run.sh` passed with `Tests passed: 281`; `git diff --check` passed; manual temp-project smoke passed for add/path/list/remove on `feature-cpq-task1`.

## Acceptance Criteria

- On a project where all repos share one parent feature base, zero-arg `workbranch add` asks for the task name only (no type prompt) and creates folder `feature-cpq-<name>` with branch `feature/cpq-<name>`.
- On a project where all repos share one parent feature base, interactive/TTY `workbranch add <taskName>` asks for `Task name [<taskName>]` only and creates folder `feature-cpq-<chosen-name>` with branch `feature/cpq-<chosen-name>`.
- On main/master-style bases, the type + detail prompt and `feat-<name>` / `feat/<name>` behavior are unchanged, including interactive/TTY `workbranch add <taskName>` pre-filling `<taskName>` as the detail.
- Mixed/differing bases keep the conventional type + detail prompt and `type-detail` folder.
- Explicit `workbranch add feat-task1` on a feature base keeps folder `feat-task1`, branch `feature/cpq-task1`.
- Explicit `workbranch add feature-cpq-task1` resolves to branch `feature/cpq-task1` (no doubled segment).
- `.workbranch.task` remains the per-repo branch source of truth; later commands operate by folder identity.
- `bin/workbranch` regenerated from source; syntax checks, targeted tests, full `apps/cli/tests/run.sh`, manual smoke, and `git diff --check` pass.

## Non-Goals

- Do not change `workbranch add feat-task1` explicit-shorthand folder behavior.
- Do not rename or migrate existing task folders or `.workbranch.task` files.
- Do not change base repo branch configuration semantics or move base ownership into `add`.
- Do not remove `BRANCH_PREFIX` parsing or per-repo branch override prompts.
- Do not introduce non-Bash dependencies.
