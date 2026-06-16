# Workbranch Companion

Native macOS menu bar companion and status monitor for workbranch task workspaces.

The app is a read-only status monitor and presentation client for the existing `workbranch` CLI. It does not read Git state directly; every refresh pulls `workbranch list --json` from each configured project root, then renders a compact project/task memo/repo branch/status summary with the task's active `TASK-WORKBRANCH.md` Plan and Steps. It renders only the current Plan on Home (first non-done, or the last Plan if all are done) and records observed `updatedAt` changes to a Companion-local activity log and renders active-time summaries inline in the default task rows and behind a footer report icon; no `workbranch report` CLI command is added.

## Requirements

- macOS 13 Ventura or newer
- Swift toolchain / Xcode Command Line Tools for local builds
- A working `workbranch` executable

## Install via Homebrew (recommended)

```bash
brew tap tkhwang/tap
brew install --cask tkhwang/tap/workbranch-companion
```

Published releases are signed with a Developer ID certificate and notarized, so
Homebrew installs no longer require Gatekeeper quarantine bypass flags.

## Release signing setup (maintainer guide)

The release workflow (`.github/workflows/companion-release.yml`) signs and
notarizes published zips when the Apple GitHub secrets below are registered.
The current release secrets are registered; keep this guide for credential
rotation or recovery:

1. Join the [Apple Developer Program](https://developer.apple.com/programs/) ($99/year).
2. Create a **Developer ID Application** certificate:
   - Keychain Access → Certificate Assistant → Request a Certificate From a
     Certificate Authority → save the CSR to disk.
   - [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates/add)
     → Developer ID Application → upload the CSR → download and double-click
     the `.cer` to install it into your login keychain.
3. Export the certificate + private key as `.p12`:
   - Keychain Access → My Certificates → right-click the
     "Developer ID Application: ..." entry → Export → set an export password.
4. Find your signing identity string:

   ```bash
   security find-identity -v -p codesigning
   # → "Developer ID Application: Your Name (TEAMID)"
   ```

5. Create an App Store Connect API key for notarization:
   - [appstoreconnect.apple.com/access/integrations/api](https://appstoreconnect.apple.com/access/integrations/api)
     → Team Keys → Generate API Key with **Developer** access → download the
     `.p8` file (downloadable only once) and note the **Key ID** and **Issuer ID**.
6. Register the six GitHub secrets:

   ```bash
   base64 -i DeveloperID.p12 | gh secret set APPLE_CERTIFICATE_P12 --repo tkhwang/workbranch
   gh secret set APPLE_CERTIFICATE_PASSWORD --repo tkhwang/workbranch   # the .p12 export password
   gh secret set APPLE_SIGNING_IDENTITY --repo tkhwang/workbranch      # e.g. "Developer ID Application: Your Name (TEAMID)"
   base64 -i AuthKey_XXXXXXXXXX.p8 | gh secret set APPLE_NOTARY_KEY --repo tkhwang/workbranch
   gh secret set APPLE_NOTARY_KEY_ID --repo tkhwang/workbranch         # the Key ID
   gh secret set APPLE_NOTARY_ISSUER_ID --repo tkhwang/workbranch      # the Issuer ID
   ```

7. Run `companion-release.yml` for the companion tag to verify Developer ID
   signing, notarization, stapling, release asset replacement, and cask sha256
   update.

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
~/.config/workbranch-companion/projects.md
```

Shape:

```text
# workbranch companion projects

workbranchBin: /optional/absolute/path/to/workbranch
fontName: Menlo
fontSize: 13
colorTheme: dracula

## projects
- /absolute/workbranch/project/root
```

`roots` are directories that contain `.workbranch.config`. GUI apps do not inherit your shell `PATH`, so set `workbranchBin` if `workbranch` is not installed at one of the known fallback paths:

- `/opt/homebrew/bin/workbranch`
- `/usr/local/bin/workbranch`
- `~/.local/bin/workbranch`

The gear icon in the popover opens companion settings. `Launch at login`
registers or unregisters WorkbranchCompanion with macOS Login Items immediately;
this setting is owned by System Settings and is not written to `projects.md`. If
macOS reports that approval is required, open System Settings → General → Login
Items and approve WorkbranchCompanion.

The font picker lists installed fixed-width system fonts, and `fontSize`
controls the display size. `colorTheme` can be `catppuccin`, `dracula`,
`onedark`, `nord`, or `tokyonight`; new configs default to `dracula`. The
settings UI shows the selected theme first and the other four themes as
candidates.

The app's **Open config** action creates an empty project-list skeleton if the file does not exist, then opens it in the default editor/Finder flow.

## Behavior

- Menu title still reflects aggregate task state for the macOS menu bar item.
- Popover rows use a terminal-style layout with project name, task name, non-duplicated task memo, repo name, repo branch, a warm current status line with `HH:mm` update time, Plan headers with their Steps, and today's task-level active-time label inline with the task name when available.
- The default popover main view stays task-focused; the footer navigation is Home, Report, Setting, and the report icon opens the activity report with time-window granularity: Today and Weekly show compact label-less project and `[*] Plan` rows, add a compact task identity row only when a project contains multiple tasks, and render indented Step rows under a Plan when the activity event contains a step snapshot, while Monthly rolls up to project totals. Empty Plan titles are not rendered, Plan rows use first-activity order within the selected window, and task-level status/session/last-edit diagnostic rows are omitted so the report stays Plan-focused. Existing historical activity lines without step snapshots remain readable and simply render Plan rows without Step rows; a later event with an empty Step snapshot clears older rendered Step rows for that Plan. The report uses the same `ActivityReport` model as the task-row active-time labels.
- Activity events are appended to `~/.local/state/workbranch/activity.jsonl` when Companion observes a task's second-resolution `updatedAt` increase. Fast repeated saves in the same second or debounce window may collapse into one event.
- Activity history is not pruned or deleted by v1; it is preserved even if the related project root or task workspace is later removed.
- Task rows are display-only: clicking a task does not edit memo text and no per-task action menu is shown.
- Notifications are baseline-safe: first load does not send macOS notifications for existing `notiCount`; later increases for the same root/task do.
- Refresh is event-driven through FSEvents with `.git/` events filtered out, per-root debounce, in-flight refresh limiting, and a 5-minute heartbeat fallback.

## Troubleshooting

- If the menu shows a binary error, set `workbranchBin` to an absolute executable path.
- If no tasks appear, confirm the configured root works with `workbranch list --json` from Terminal.
- If notifications do not appear, check macOS notification permissions for WorkbranchCompanion.

## Current release status

Release automation is implemented by plan 0020. Published companion releases are distributed as Homebrew cask zips signed with Developer ID and notarized through the registered Apple secrets.
