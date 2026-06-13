# Workbranch Companion

Native macOS menu bar companion for workbranch task workspaces.

The app is a read-only presentation client for the existing `workbranch` CLI. It does not read Git state directly; every refresh pulls `workbranch list --json` from each configured project root, then renders a compact project/task memo/repo branch/dirty/status summary with the task's `TASK-WORKBRANCH.md` status items.

## Requirements

- macOS 13 Ventura or newer
- Swift toolchain / Xcode Command Line Tools for local builds
- A working `workbranch` executable

## Install via Homebrew (recommended)

```bash
brew tap tkhwang/tap
brew install --cask --no-quarantine tkhwang/tap/workbranch-companion
```

`--no-quarantine` is required while releases are ad-hoc signed: macOS Gatekeeper
blocks downloaded apps without a Developer ID signature. If you installed without
the flag and see an "app is damaged" warning, run:

```bash
xattr -dr com.apple.quarantine "/Applications/WorkbranchCompanion.app"
```

Once releases are signed with a Developer ID certificate and notarized
(see below), the flag will no longer be needed.

## Release signing setup (maintainer guide)

The release workflow (`.github/workflows/companion-release.yml`) ships ad-hoc
signed zips until Apple credentials are registered as GitHub secrets. To enable
Developer ID signing + notarization:

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

7. The next companion release is signed and notarized automatically. Then send
   a tap PR removing the `--no-quarantine` caveat from
   `Casks/workbranch-companion.rb`.

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

The gear icon in the popover opens companion settings for the terminal display.
The font picker lists installed fixed-width system fonts, and `fontSize`
controls the display size. `colorTheme` can be `dracula`, `matrix`, `amber`,
`nord`, or `solarized`; new configs default to `dracula`.

The app's **Open config** action creates an empty project-list skeleton if the file does not exist, then opens it in the default editor/Finder flow.

## Behavior

- Menu title still reflects aggregate task state for the macOS menu bar item.
- Popover rows use a terminal-style layout with project name, task name, task memo, repo name, repo branch, repo dirty state, task status, and the task status checklist items.
- Task rows are display-only: clicking a task does not edit memo text and no per-task action menu is shown.
- Notifications are baseline-safe: first load does not send macOS notifications for existing `notiCount`; later increases for the same root/task do.
- Refresh is event-driven through FSEvents with `.git/` events filtered out, per-root debounce, in-flight refresh limiting, and a 5-minute heartbeat fallback.

## Troubleshooting

- If the menu shows a binary error, set `workbranchBin` to an absolute executable path.
- If no tasks appear, confirm the configured root works with `workbranch list --json` from Terminal.
- If macOS blocks an ad-hoc signed Homebrew install, reinstall with `--no-quarantine` or clear the quarantine xattr shown above.
- If notifications do not appear, check macOS notification permissions for WorkbranchCompanion.

## Current release status

Release automation is implemented by plan 0020. Published companion releases are distributed as Homebrew cask zips; Developer ID signing and notarization activate automatically once the Apple secrets above are registered.
