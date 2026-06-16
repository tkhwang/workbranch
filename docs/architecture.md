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

`src/workbranch/lib/tool-launcher.sh` owns editor/terminal presets, task path resolution, and configured tool execution. `src/workbranch/commands/path.sh` owns the stdout-only path command. `src/workbranch/commands/tool-launcher.sh` owns `editor` and `terminal` orchestration. These commands are not Git operations and do not modify repositories.


## Task root boundary

A task root (`<task>`) is a workbranch metadata/agent workspace outside Git. The actual Git repositories live under `<task>/<repo>`. Workbranch-owned task-root state is limited to the current-Plan `TASK-WORKBRANCH.md`, generated `AGENTS.md`, `.workbranch/` (including Plan archives under `.workbranch/plans/done/`), and `.workbranch.task`; other task-root entries are non-git leftovers. Remove flows first remove repo worktrees and task branches, then known metadata, then list any non-git leftovers and ask once before deleting the remaining task root unless `--force` is used.

`workbranch terminal <task>` opens the task root by default, while `workbranch ide <task>` opens repo worktrees. `PREFERRED_LANGUAGE en|ko` only affects generated task briefs and generated agent guidance; it is not full CLI localization.


## Companion activity boundary

Workbranch Companion owns activity-time tracking as local presentation state. The CLI continues to expose task state through `workbranch list --json`; there is no `workbranch report` command. Companion observes second-resolution `updatedAt` increases from `TASK-WORKBRANCH.md`, appends activity events to `~/.local/state/workbranch/activity.jsonl`, and computes today/week/month rollups in `CompanionCore`. Task briefs use `# <plan>` H1 sections with Plan-local `status:` lines. The brief is intended to contain the current Plan; completed Plans are archived by `workbranch done <task>` or confirmed land/finalize/pull prompts into `.workbranch/plans/done/<timestamp>-<slug>.md`. `workbranch list --json` keeps flat task fields for compatibility and exposes `plans[]` with 0-based Plan indexes; the Companion Home view renders only the active Plan while activity events still carry optional `plan` and `planIndex` fields for per-Plan time rows.

The activity log is append-only history. It is not removed by `workbranch prune`, `workbranch remove`, or Companion root self-heal, because deleted repo/task workspaces may still matter for later retrospectives. v1 does not provide activity-log deletion, compression, or rotation; if long-term size becomes a real issue, add an archive/rotation plan that preserves history by default.

## Distribution boundary

All install channels use the same generated `bin/workbranch` artifact:

- direct curl/wget downloads
- `install.sh`
- Homebrew formula installation from a release tarball

Homebrew can support multi-file runtime payloads through private install directories, but this project intentionally keeps the runtime as one file so all install channels behave the same.

## Optional packaging checks

Run these only when Homebrew is available locally:

```bash
brew audit --strict --online packaging/homebrew/workbranch.rb
brew test packaging/homebrew/workbranch.rb
```
