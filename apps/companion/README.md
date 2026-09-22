# Workbranch Companion

Tauri v2 + React menu bar companion for the `workbranch` CLI.

## Scope

The companion is a presentation-first consumer of the CLI JSON contract. It reads task state through `workbranch list --global --json`, maps the DTOs through `packages/contract`, and delegates only the v1 allowlisted operational actions to the CLI: memo edit/clear, notification clear, Finder/IDE/terminal launch, and copy path. Task lifecycle and Git mutation commands remain CLI-only.

The Activity view reads the local append-only activity log and renders project-colored task sessions in day or three-day calendar timelines. It is a navigation/reporting surface only; activity recording still comes from normal Companion refreshes and CLI state changes.

Weekly limit accounts are frontend-owned state in the Tauri store file `companion-limits.json` (next to `companion-preferences.json` and `companion-notes.json`). Each account stores a label and the next reset instant entered from the coding agent's `/usage` output; the Main view derives the current seven-day window from that anchor and never reads actual usage.

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
