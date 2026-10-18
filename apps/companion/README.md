# Workbranch Companion

Tauri v2 + React menu bar companion for the `workbranch` CLI.

## Scope

The companion is a presentation-first consumer of the CLI JSON contract. It reads task state through `workbranch list --global --json`, maps the DTOs through `packages/contract`, and delegates only the v1 allowlisted operational actions to the CLI: memo edit/clear, notification clear, Finder/IDE/terminal launch, and copy path. Task lifecycle and Git mutation commands remain CLI-only.

Agent runtime state comes from `RuntimeService` (`src-tauri/src/runtime_service.rs`). It watches the runtime directory, reads `workbranch runtime --json` once writes settle and at least every 60 seconds, and pushes each result to every window as the `runtime-snapshot` event and to the screensaver in process; a window that opens later asks for the latest one with `runtime_snapshot`. Windows check the document against the contract themselves. See `docs/specs/comp/runtime-snapshot.md`.

The opt-in screensaver (`src-tauri/src/screensaver.rs` and `src-tauri/src/screensaver/`) keeps the Mac from idle sleep while agents work. When the macOS screen saver starts or the screen locks, it locks the Mac if needed, shows the dashboard (`dashboard.html`, its own Vite entry and `dashboard` capability) on every display above the lock screen, and keeps the display on; input moves the dashboard aside to reveal the lock screen. If locking is unavailable, the lock indicator is hidden and it never locks by itself. A pure state machine (`screensaver/machine.rs`) decides and a `Platform` trait acts, so transitions are unit-tested without the OS. It relies on private macOS APIs, `SACLockScreenImmediate`, a SkyLight space above the lock screen and the webview background that Tauri's `macOSPrivateApi` controls, so the app cannot ship through the Mac App Store. `WORKBRANCH_SCREENSAVER_NO_LOCK=1` starts it as if the lock were unavailable. See `docs/specs/comp/screensaver.md`.

The IDE action moves the windows the IDE opens onto the screen the companion is on (`src-tauri/src/ide_window.rs` and `src-tauri/src/ide_window/macos.rs`). Zed reopens a project's window where it last was, or else where its last window was, and none of the supported IDEs takes a target screen, so `workbranch_run` reads the companion window's monitor, notes every CoreGraphics window number (which covers every Space and needs no permission) before running `workbranch ide`, and then moves each new standard window of Zed, VS Code, Cursor or Antigravity IDE through the Accessibility API, once, centered at its size and shrunk to fit. `_AXUIElementGetWindow`, a private call probed at runtime, maps an Accessibility window to its window number. A repo window that was already open stays where it is. Following stops 10 seconds after the command ends if no new window appears, or else 3 seconds after the later of the command's end and the last new window; a move the IDE does not take, such as an Accessibility call that times out while it is busy, is tried again up to five times. Nothing moves until Settings › General › IDE Windows is switched on (the `ideWindow` preference, read on each IDE action) and macOS granted the Accessibility permission. Switching it on shows macOS's permission prompt; Settings reads the permission again each time it opens and, while it is missing, offers to open the Accessibility list in System Settings (`ide_window_access`, `ide_window_request_access`, `ide_window_open_access_settings`). Under `pnpm tauri dev` the companion runs as a plain binary under your terminal, so macOS checks and prompts for the terminal app's Accessibility permission instead; test this with the bundled app. Each ad-hoc signed local build counts as a new app to macOS, so remove WorkbranchCompanion from the Accessibility list and allow it again after rebuilding.

Agent usage comes from the Rust `usage_snapshot` command (`src-tauri/src/usage.rs`), which reads only files the agents already write: Claude Code transcripts under `~/.claude/projects` (each response counted once by `message.id` + `requestId`) and the `/usage` result Claude Code caches in `~/.claude.json` (or, when the opt-in Live Claude Limits relay in `src-tauri/src/claude_statusline.rs` is on, the newer `rate_limits` Claude Code passed to its status line, saved in the companion's data directory), plus Codex rollouts under `~/.codex/sessions` and `~/.codex/archived_sessions` (token deltas from `total_token_usage`, with a file's first event counted by its `last_token_usage` and identical events shared by forked rollouts counted once; cache reads and writes split out of input; limits from `rate_limits`, whose reset may be epoch seconds or an RFC3339 string). `CLAUDE_CONFIG_DIR` and `CODEX_HOME` are honored. It never signs in or touches the network, keeps parsed files in memory keyed by size and mtime, and returns 15-minute token buckets that the frontend folds into local days. Daily totals match ccusage.

## Development

```bash
pnpm install
pnpm --filter @workbranch/companion lint
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion test
cargo test --manifest-path apps/companion/src-tauri/Cargo.toml
pnpm --filter @workbranch/companion tauri build
```

The macOS bundle is emitted at:

```text
apps/companion/src-tauri/target/release/bundle/macos/WorkbranchCompanion.app
```
