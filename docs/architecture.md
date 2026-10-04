# Workbranch architecture

`workbranch` is a pnpm-workspace monorepo. Deployable apps live under `apps/*`: the Bash CLI supplier app is authored under `apps/cli/src/workbranch/**`, the Tauri/React companion consumer app lives under `apps/companion/**`, and the shared JSON contract snapshot lives under `packages/contract/**`. The CLI is still distributed as one generated executable at root `bin/workbranch` for raw install compatibility, with the canonical generated app artifact at `apps/cli/bin/workbranch`.

## Edit/build rule

- Edit `apps/cli/src/workbranch/**`.
- Run `apps/cli/scripts/build-workbranch.sh`.
- Commit source changes plus both generated artifacts: `apps/cli/bin/workbranch` and root compatibility `bin/workbranch`.
- Do not hand-edit `bin/workbranch`.

## Command boundary

Each user command should have one `apps/cli/src/workbranch/commands/<command>.sh` file.

A command file owns orchestration:

1. parse command-specific args
2. validate project/config/task names
3. run preflight checks before mutation
4. call `workbranch_git_*` functions for documented Git operations
5. print concise user-facing status

`apps/cli/src/workbranch/git-ops.sh` owns the exact mutating Git commands mirrored by `docs/git-operations.md`.

`apps/cli/src/workbranch/lib/preflight.sh` owns safety checks and aggregate preflight failure reporting.

`apps/cli/src/workbranch/lib/tool-launcher.sh` owns editor/terminal presets, task path resolution, and configured tool execution. It also owns the VS Code-family rule that prefers the app's bundled CLI (`<App>.app/Contents/Resources/app/bin/<cli> --new-window <repo-path>`) over `open -na ... --args`, so an already-open repo window is focused instead of leaving the IDE behind the caller. When the IDE was already running (`lsappinfo find bundlepath=...`), the launcher waits for the CLI's helper instance to exit (polling `ps -axo command=`, about two seconds at most) and then activates the IDE with `open -a <App>.app`, because the helper's exit hands focus back to the caller and focusing the IDE's current key window alone does not bring the app forward. That focus hand-back can land a moment after the helper is gone, so the launcher re-checks the frontmost app (`lsappinfo front`, with the ASN normalized to the `ASN:0x0-0x...:` form that `lsappinfo info` accepts on macOS Sonoma and later) four times over about three quarters of a second and repeats `open -a` only while the IDE is not in front. `WORKBRANCH_TEST_APPLICATIONS_DIR` overrides the `/Applications` and `~/Applications` lookup roots for tests. `apps/cli/src/workbranch/commands/path.sh` owns the stdout-only path command. `apps/cli/src/workbranch/commands/tool-launcher.sh` owns `editor` and `terminal` orchestration. These commands are not Git operations and do not modify repositories.


## Task root boundary

A task root is metadata outside Git; repositories live under `<task>/<repo>`. Generated AGENTS.md describes this boundary but does not require status reporting. `.workbranch.task` identifies the workspace and notifications remain under `.workbranch/`. Legacy briefs and plan archives are removed through explicit runtime migration; Git worktree removal safety checks are unchanged.

## Runtime and setup boundaries

The Rust collector owns canonical Claude/Codex/Grok observations and embedded SQLite at `~/.workbranch/runtime/state.sqlite3`. Agent hooks invoke it independently of Companion. The CLI exposes Git inventory with list schema 2 and runtime with a separate snapshot schema 1. Companion refreshes runtime without re-running Git; historical activity reports are no longer fed by task briefs.

The Companion native setup port locates Homebrew and checks the CLI/collector capability contract even before the CLI is installed. Installation actions accept fixed enum/argv combinations for `tkhwang/tap/workbranch`, with bounded logs, process deadlines and one active setup action per app. Provider connection actions delegate to the CLI and native provider plugin managers without bypassing trust. Onboarding and Settings share one controller. Configuration and fresh event receipt are separate states.

## Distribution boundary

`apps/cli/bin/workbranch` is generated from CLI sources, with `bin/workbranch` as the compatible raw-install mirror. The CLI and standalone embedded-SQLite collector are distributed together through the installer and Homebrew formula. Companion is a separate Homebrew cask; its onboarding calls Homebrew rather than bundling or overwriting an independently managed CLI. A compatible formula must be published before releasing a Companion that requires it.

## Optional packaging checks

Run these only when Homebrew is available locally:

```bash
brew audit --strict --online packaging/homebrew/workbranch.rb
brew test packaging/homebrew/workbranch.rb
```
