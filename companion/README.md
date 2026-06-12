# Workbranch Companion

Native macOS menu bar companion for workbranch task workspaces.

The app is a presentation/action client for the existing `workbranch` CLI. It does not read Git state directly; every refresh pulls `workbranch list --json` from each configured project root, then renders task memo titles, notification counts, and dirty markers.

## Requirements

- macOS 13 Ventura or newer
- Swift toolchain / Xcode Command Line Tools for local builds
- A working `workbranch` executable

## Build locally

```bash
cd companion
swift build
swift run CompanionCoreTestRunner
./scripts/build-app.sh
open dist/WorkbranchCompanion.app
```

`build-app.sh` creates `dist/WorkbranchCompanion.app`, writes an `LSUIElement=true` Info.plist so the app is menu-bar-only, and applies ad-hoc codesigning for local use.

## Config

Config path:

```text
~/.config/workbranch-companion/config.json
```

Shape:

```json
{
  "roots": ["/absolute/workbranch/project/root"],
  "workbranchBin": "/optional/absolute/path/to/workbranch"
}
```

`roots` are directories that contain `.workbranch.config`. GUI apps do not inherit your shell `PATH`, so set `workbranchBin` if `workbranch` is not installed at one of the known fallback paths:

- `/opt/homebrew/bin/workbranch`
- `/usr/local/bin/workbranch`
- `~/.local/bin/workbranch`

The app's **Open config** action creates an empty `roots: []` skeleton if the file does not exist, then opens it in the default editor/Finder flow.

## Behavior

- Menu title shows task count and number of roots with notifications, e.g. `⎇ 4 🔔2`.
- Popover rows show task name, memo title, `🔔N` notification count, and `●` when any repo is dirty.
- Clicking a task row enters inline memo edit mode. Saving calls `workbranch memo <task> <text>`; saving an empty memo calls `workbranch memo <task> --clear`.
- Secondary actions call existing CLI surfaces with argv arrays and explicit cwd: `noti clear`, `terminal`, `ide`, `finder`, and copy task path.
- New workspace starts detached through `workbranch add <task>` and sends a macOS notification that creation has started.
- Notifications are baseline-safe: first load does not send macOS notifications for existing `notiCount`; later increases for the same root/task do.
- Refresh is event-driven through FSEvents with `.git/` events filtered out, per-root debounce, in-flight refresh limiting, and a 5-minute heartbeat fallback.

## Troubleshooting

- If the menu shows a binary error, set `workbranchBin` to an absolute executable path.
- If no tasks appear, confirm the configured root works with `workbranch list --json` from Terminal.
- If macOS blocks a downloaded future release, public distribution will require Developer ID notarization. Local builds are ad-hoc signed.
- If notifications do not appear, check macOS notification permissions for WorkbranchCompanion.

## Current release status

This is a local preview app. Public Homebrew cask distribution, Developer ID signing, notarization, and release automation are deferred to the rewritten 0018 release-plumbing plan.
