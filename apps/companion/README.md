# Workbranch Companion

Tauri v2 + React menu bar companion for the `workbranch` CLI.

## Scope

The companion is a presentation-first consumer of the CLI JSON contract. It reads task state through `workbranch list --global --json`, maps the DTOs through `packages/contract`, and delegates only the v1 allowlisted operational actions to the CLI: memo edit/clear, notification clear, Finder/IDE/terminal launch, and copy path. Task lifecycle and Git mutation commands remain CLI-only.

Agent usage comes from the Rust `usage_snapshot` command (`src-tauri/src/usage.rs`), which reads only files the agents already write: Claude Code transcripts under `~/.claude/projects` (each response counted once by `message.id` + `requestId`) and the `/usage` result Claude Code caches in `~/.claude.json`, plus Codex rollouts under `~/.codex/sessions` and `~/.codex/archived_sessions` (token deltas from `total_token_usage`, limits from `rate_limits`). `CLAUDE_CONFIG_DIR` and `CODEX_HOME` are honored. It never signs in or touches the network, keeps parsed files in memory keyed by size and mtime, and returns 15-minute token buckets that the frontend folds into local days. Daily totals match ccusage.

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
