# 0037 Companion Settings and CLI Theme Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` or `$plan-execute auto` to implement this plan task-by-task. For `.ts`/`.tsx`/`.rs` edits, follow TypeScript/Rust guidance and lock semantics with tests before visual changes. For visual changes, follow `DESIGN.md`, drive `pnpm --filter @workbranch/companion tauri dev`, and visually verify the settings panel, font/theme application, and launch-at-login toggle before claiming completion. If the native menu-bar popover cannot be observed in the agent session, record the gap, run the Vite surface with Tauri IPC mocks as fallback visual evidence, and leave the task in `review` until a human/native GUI check completes.

**Goal:** Add a compact settings surface to the Workbranch Companion popover and shift the visual system toward a terminal/CLI-like developer HUD: icon-only refresh in the header, bottom view navigation for Main/Activity/Setting, launch-at-login toggle, fixed-width font selector, and color theme selector.

**Architecture:** Split this from 0036. Keep 0036 focused on project grouping and row hierarchy. In this plan, add preference state and settings UI to the Tauri React companion. Use official Tauri v2 plugins for OS/app persistence: `@tauri-apps/plugin-autostart` for launch-at-login and `@tauri-apps/plugin-store` for font/theme preferences. Do not change the CLI JSON contract, domain task model, watcher, or activity store.

**Tech Stack:** Tauri v2, React 18, TypeScript, Vite, Vitest, Biome, plain CSS, official Tauri plugins `autostart` and `store`. No Tailwind/shadcn/Radix.

---

## Product framing

The companion is becoming less of a generic dashboard and more of a command-line control panel for task worktrees. The settings surface should feel like a small terminal preferences pane, not a full app settings window.

User-visible additions:

1. Top-right toolbar keeps refresh as an icon-only control with an accessible label.
2. Bottom mobile-style view nav switches between `Main`, `Activity`, and `Setting`.
3. `Main` renders the project/task worktree view.
4. `Activity` renders a future-slice Activity report placeholder.
5. `Setting` renders launch-at-login, fixed-width font selector, and color theme selector.
6. The default visual feel moves from Raycast-like chrome toward fixed-width, terminal-inspired HUD styling.

## Current repo evidence

- `apps/workbranch-companion/src/App.tsx` currently renders a single refresh button in the top-right header and has no settings panel state.
- `apps/workbranch-companion/src/style.css` currently uses `Inter, ui-sans-serif, system-ui` at `:root`; only repo chips use a monospace stack.
- `apps/workbranch-companion/src/style.css` currently contains Raycast-era pink/violet literal gradients in `main`, `main::before`, `.task-in-progress .task-status-rail`, and `.current-step-strip`; these must be removed or routed through theme tokens for theme switching to affect the whole UI.
- `apps/workbranch-companion/package.json` has Tauri/React dependencies but no autostart/store plugins.
- `apps/workbranch-companion/src-tauri/src/lib.rs` currently initializes only `tauri_plugin_positioner`; no autostart/store plugin is wired.
- `apps/workbranch-companion/src-tauri/capabilities/default.json` must grant explicit plugin permissions when new Tauri plugins are exposed to the frontend.
- `DESIGN.md` currently records the 2026-06-17 Raycast direction as dominant; this plan supersedes that direction with terminal/CLI HUD styling and must append a new dated revision.
- Historical Swift plan `docs/plans/0027-companion-launch-at-login.md` resolved the product semantics for launch-at-login: system state is the source of truth, not project config, and the setting should be immediate-apply. The current Tauri app needs a fresh implementation path.
- Official Tauri v2 docs confirm:
  - Autostart JS API: `enable`, `disable`, `isEnabled` from `@tauri-apps/plugin-autostart`.
  - Autostart permissions: `autostart:allow-enable`, `autostart:allow-disable`, `autostart:allow-is-enabled`.
  - Autostart Rust init via `tauri_plugin_autostart::init(...)`.
  - Store plugin init via `tauri_plugin_store::Builder::new().build()` and permissions via `store:default`.

## Decision gates

- [x] **Scope split from 0036:** resolved to a new 0037 plan. Rationale: settings/preferences plus OS launch-at-login are not just presentation hierarchy and would make 0036 too broad.
- [x] **Visual direction:** resolved to **command-line CLI / terminal HUD**. Rationale: fixed-width type, compact status lines, and theme presets match a developer worktree monitor better than generic app chrome.
- [x] **Launch at login implementation:** resolved to official Tauri `autostart` plugin. Rationale: it is the current Tauri v2 path for `enable`/`disable`/`isEnabled` and avoids hand-written LaunchAgent plumbing.
- [x] **Preference persistence:** resolved to official Tauri `store` plugin. Rationale: font/theme are app preferences, not workbranch project config or CLI contract; store gives explicit app-owned persistence without adding ad-hoc files.
- [x] **Font choices:** resolved to fixed-width fonts only. Rationale: the UI identity should not be breakable by proportional fonts. The selector exposes a curated list and stores a font token, not arbitrary CSS text.
- [x] **Theme choices:** resolved to a small fixed preset list. Rationale: app stays designed and testable; no custom color editor in this slice.
- [x] **Theme token contract:** resolved to a full companion theme token set, not only background/foreground/accent. Rationale: current CSS uses surfaces, line colors, muted/faint text, status colors, soft state backgrounds, focus outlines, badges, shell gradients, and current-step highlights. Every preset must define the complete token surface so switching themes changes the whole UI and does not leave Raycast pink/violet literals behind.
- [x] **Theme control shape:** resolved to a labeled native `select` for the theme choice, with optional non-interactive preview chips/swatches only as decoration. Rationale: the product requirement says "selector"; the accessibility requirement already names a `theme select`; a radio/swatches control would change markup, tests, and focus order without improving this compact settings slice.
- [x] **Autostart launcher/fidelity:** resolved to `MacosLauncher::LaunchAgent` with no extra launch arguments, via the official Tauri autostart plugin. Rationale: this matches the Tauri v2 documented macOS path and keeps the menu-bar app startup behavior simple. Tradeoff: unlike the older Swift `SMAppService` plan, this plugin path exposes the frontend boolean `isEnabled()` contract and does not preserve a separate `.requiresApproval` state; approval-required messaging from 0027 is not part of this Tauri plugin slice.
- [x] **Preference store contract:** resolved to app-owned Tauri store file `companion-preferences.json`, with top-level `font` and `theme` keys only. Rationale: stable key names keep future migration clear, avoid project config drift, and make tests focus on pure sanitization plus thin store I/O helpers.
- [x] **Visual QA fallback:** resolved to native `tauri dev` as the desired manual gate and Vite+IPC-mock visual verification as the documented fallback when the agent cannot observe the macOS tray popover. Rationale: 0036 hit the same native observation limitation, so this plan should make the fallback explicit instead of treating native observation as guaranteed.
- [x] **View navigation shape:** updated to bottom mobile-style view navigation with `Main`, `Activity`, and `Setting`; top-right header keeps refresh as an icon-only control. Rationale: settings and future reports are screen-level destinations, not header actions.

## Preference contract

Add a small companion settings model in TypeScript:

```ts
export type CompanionFont = "system-mono" | "sf-mono" | "menlo" | "monaco" | "jetbrains-mono";
export type CompanionTheme = "terminal-dark" | "amber-crt" | "green-mono" | "high-contrast";

export type CompanionPreferences = {
	readonly font: CompanionFont;
	readonly theme: CompanionTheme;
};
```

Defaults:

- `font: "system-mono"`
- `theme: "terminal-dark"`
- launch-at-login default is read from `isEnabled()` and not duplicated in the store.

Store contract:

- Store file: `companion-preferences.json`.
- Stored keys: top-level `font` and `theme` only.
- Stored shape: `{ font: CompanionFont, theme: CompanionTheme }`; do not store launch-at-login state.
- Load behavior: missing store, missing keys, or unknown values sanitize to defaults; if a stored value is sanitized, apply the sanitized value and surface a concise footer/status message.
- Save behavior: save the complete sanitized `{ font, theme }` pair after every preference change; if load discovers invalid stored values, attempt one best-effort save of the sanitized pair so future launches are clean.
- Test boundary: pure default/sanitizer/option-list behavior is covered by unit tests; Tauri store I/O helpers are thin wrappers and may be mocked in app-shell tests instead of integration-testing the plugin itself.

Font display labels:

- `System Mono` -> CSS stack: `ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace`
- `SF Mono` -> `SFMono-Regular, ui-monospace, Menlo, Monaco, Consolas, monospace`
- `Menlo` -> `Menlo, ui-monospace, Monaco, Consolas, monospace`
- `Monaco` -> `Monaco, ui-monospace, Menlo, Consolas, monospace`
- `JetBrains Mono` -> `"JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace`

Theme presets:

- `terminal-dark`: near-black background, white/gray text, restrained cyan/blue accent.
- `amber-crt`: near-black background, amber foreground/accent.
- `green-mono`: near-black background, green terminal foreground/accent.
- `high-contrast`: black background, high-contrast white text, stronger borders.

Every theme preset must define the complete CSS token interface used by the companion shell and components:

- Surfaces: `--surface-0`, `--surface-1`, `--surface-2`, `--surface-3`.
- Lines/text: `--line`, `--line-strong`, `--text`, `--muted`, `--faint`.
- Accent/focus: `--accent`, `--accent-soft`, focus outline color.
- Status colors and soft backgrounds: `--blocked`, `--blocked-soft`, `--review`, `--review-soft`, `--done`, `--done-soft`, `--notify`, `--notify-soft`.
- Shell/component backgrounds: `--shell-bg`, `--shell-topline`, `--task-bg`, `--button-bg`, `--button-bg-hover`, `--current-step-bg`, `--active-rail-bg`.
- Typography: `--app-font-family`.

No component CSS should keep hard-coded Raycast pink/violet literals outside the `terminal-dark` token definitions; amber/green/high-contrast themes must not inherit pink/violet shell glow, hairline, current-step, badge, or status-rail accents.

## File structure

Modify:

- `DESIGN.md` — update visual language, typography, color/theme tokens, and settings components to reflect CLI-like companion direction.
- `apps/workbranch-companion/package.json` and lockfile — add official Tauri plugin packages.
- `apps/workbranch-companion/src-tauri/Cargo.toml` / `Cargo.lock` — add autostart/store Rust plugin dependencies through the Tauri add flow.
- `apps/workbranch-companion/src-tauri/src/lib.rs` — initialize autostart and store plugins.
- `apps/workbranch-companion/src-tauri/capabilities/default.json` — add autostart and store permissions.
- `apps/workbranch-companion/src/App.tsx` — add view state, icon-only refresh, bottom view navigation wiring, runtime guard, preference application, and launch-at-login status wiring.
- `apps/workbranch-companion/src/style.css` — add CLI-like theme variables, font-family variable, settings view styles, toolbar styles, bottom view-nav styles, and theme classes.
- `apps/workbranch-companion/tests/**/*.test.tsx?` — add focused preference/settings tests.
- `rust-toolchain.toml` — pin repo-local Rust toolchain to `1.95.0` so normal `pnpm tauri dev/build` commands satisfy `rust-version = "1.95"` without manual environment overrides.
- `../TASK-WORKBRANCH.md` — task progress updates only.

Create:

- `apps/workbranch-companion/src/application/preferences.ts` — preference types, defaults, font/theme option lists, sanitizers, and store helpers.
- `apps/workbranch-companion/src/application/useCompanionSettings.ts` — settings lifecycle hook for store/autostart state and browser-safe non-Tauri fallback.
- `apps/workbranch-companion/src/ui/SettingsPanel.tsx` — Setting view UI.
- `apps/workbranch-companion/src/ui/ViewNav.tsx` — bottom view navigation.
- `apps/workbranch-companion/tests/preferences.test.ts` — preference sanitization/default coverage.
- `apps/workbranch-companion/tests/settings-panel.test.tsx` — static markup / callback coverage.
- `apps/workbranch-companion/tests/view-nav.test.tsx` — bottom nav markup and click delegation coverage.

Do not modify:

- `apps/workbranch-cli/**`
- `packages/contract/**`
- `apps/workbranch-companion/src/domain/**`
- `apps/workbranch-companion/src/infrastructure/acl.ts`
- watcher/activity-store behavior except plugin initialization required by this settings slice.

## Task 1: Update design contract for CLI-like settings direction

**Files:** Modify `DESIGN.md`, `../TASK-WORKBRANCH.md`

- [x] Update **Brand** personality to terminal/CLI-like developer HUD, not generic app dashboard.
- [x] Update **Visual language**:
  - typography defaults to fixed-width UI;
  - theme tokens include `terminal-dark`, `amber-crt`, `green-mono`, `high-contrast`;
  - avoid heavy gradients; prefer prompt-like separators, subtle grid/border lines, compact density.
- [x] Update **Components** to include top icon-only refresh toolbar, bottom view nav, Setting view, Activity report placeholder view, switch row, font select row, theme select row, and optional non-interactive theme preview chips.
- [x] Update **Accessibility** to require real button labels for refresh/view nav, `aria-current` for active view, select labels, and switch state text.
- [x] Append a new **Direction revision** entry dated with the implementation date that supersedes the 2026-06-17 Raycast direction with terminal/CLI HUD direction.
- [x] Verify no placeholders: `rg -n "TBD|TODO|placeholder|fill in" DESIGN.md` -> no matches. Evidence: `rg -n "TBD|TODO|placeholder|fill in" DESIGN.md` returned no matches.

## Task 2: Add official Tauri plugins

**Files:** Modify package/Cargo/capabilities/lib.rs surfaces

- [x] Add autostart plugin via Tauri CLI from `apps/workbranch-companion`:

  ```bash
  pnpm tauri add autostart
  ```

- [x] Add store plugin via Tauri CLI from `apps/workbranch-companion`:

  ```bash
  pnpm tauri add store
  ```

- [x] Confirm `src-tauri/src/lib.rs` initializes:
  - `tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, None)` or the equivalent imported `MacosLauncher::LaunchAgent` form with no launch args.
  - `tauri_plugin_store::Builder::new().build()`
- [x] Confirm `src-tauri/capabilities/default.json` includes:
  - `autostart:allow-enable`
  - `autostart:allow-disable`
  - `autostart:allow-is-enabled`
  - `store:default`
- [x] Document in comments or plan result that Tauri autostart uses the plugin boolean `isEnabled()` contract and does not expose the older Swift plan's `.requiresApproval` state. Evidence: decision gate records boolean `isEnabled()` tradeoff and `lib.rs` uses `MacosLauncher::LaunchAgent` with no args.

## Task 3: Preference model and persistence

**Files:** Create `src/application/preferences.ts`; Create/modify tests

- [x] Add `CompanionFont`, `CompanionTheme`, `CompanionPreferences`, defaults, and option arrays.
- [x] Add sanitizers so unknown stored values fall back to defaults.
- [x] Add store helpers around `@tauri-apps/plugin-store` that load and save only top-level `font` and `theme` in `companion-preferences.json`.
- [x] Loading invalid persisted values sanitizes to defaults, returns whether sanitization happened, and lets the app shell surface the footer/status message.
- [x] Saving always writes the complete sanitized `{ font, theme }` pair; launch-at-login is never read from or written to the store.
- [ ] Tests:
  - [x] default preferences are terminal-dark + system-mono;
  - [x] invalid font/theme sanitize to defaults;
  - [x] option arrays contain only fixed-width font choices;
  - [x] theme list includes the four resolved presets;
  - [x] store serialization helpers include only `font` and `theme` keys. Evidence: `pnpm test -- tests/preferences.test.ts` passed.

## Task 4: Settings panel UI

**Files:** Create `src/ui/SettingsPanel.tsx`; Create `tests/settings-panel.test.tsx`

- [x] Render a compact CLI-like Setting view selected from the bottom view nav.
- [x] Include sections:
  - [x] `Startup` with `Launch at login` toggle;
  - [x] `Font` select with fixed-width options only;
  - [x] `Theme` select with four presets and optional non-interactive preview chips.
- [x] The launch-at-login toggle is immediate-apply and calls `enable()`/`disable()` through an injected callback.
- [x] Font/theme updates save preferences and update the app immediately.
- [x] Font/theme update callbacks must report preference save or sanitization failures to the app shell; do not swallow errors inside the panel.
- [x] Static markup tests assert labels, option names, and accessible control names.

### Accessibility Requirements

- Use semantic grouping: render the `Startup`, `Font`, and `Theme` sections as `fieldset` elements, each with a visible `legend` child.
- The bottom view-nav buttons must have `aria-label`s that name their destinations, e.g. `Open Setting`, and the active view must expose `aria-current="page"`.
- Every form control must have an associated `label` element using the `for`/`id` pattern: launch-at-login toggle, font select, and theme select.
- Keyboard focus order must include the icon-only refresh control, the current view controls, then bottom view-nav buttons in source order: Main, Activity, Setting.
- State changes must be announced to screen readers: launch-at-login activation/deactivation and preference save/update results should use an appropriate ARIA live region or equivalent role/state change.

## Task 5: App shell wiring

**Files:** Modify `src/App.tsx`

- [x] Replace single refresh button with an icon-only refresh control in the top-right toolbar.
- [x] Add screen-level view state for Main, Activity, and Setting.
- [x] On app startup, load preferences from store, sanitize them, and apply theme/font classes or data attributes to the root shell.
- [x] Before `isEnabled()` resolves, render launch-at-login as off/disabled or loading rather than pretending the persisted store owns the value.
- [x] On settings change, save preferences and update root shell immediately.
- [x] On font/theme preference failures, keep or restore the last valid applied preferences and set the existing footer/status message, matching the launch-at-login failure pattern.
- [x] If a stored or incoming font/theme value sanitizes to a fallback, apply the sanitized value and surface a concise footer/status message instead of silently changing the selection.
- [x] On app startup, call `isEnabled()` to initialize launch-at-login state.
- [x] On launch-at-login toggle:
  - [x] true -> `enable()`, then refresh `isEnabled()`;
  - [x] false -> `disable()`, then refresh `isEnabled()`;
  - [x] failures set the existing footer/status message.
- [x] Add `role="status"` and `aria-live="polite"` to the existing footer/status line so launch-at-login, font, and theme results are announced.
- [x] Keep task refresh/watch behavior unchanged.

## Task 6: CLI-like style system

**Files:** Modify `src/style.css`

- [x] Replace proportional root stack with `var(--app-font-family)` defaulting to fixed-width.
- [x] Add root classes or data attributes for `font-*` and `theme-*` preferences.
- [x] Define the full theme token interface for the four presets: surfaces, line/text, accent/focus, status colors and soft backgrounds, shell/component backgrounds, and typography.
- [x] Replace or tokenize all existing hard-coded Raycast pink/violet gradients and literals in `main`, `main::before`, `.task-in-progress .task-status-rail`, `.current-step-strip`, badges, dirty/error/notification treatments, and any other component styles affected by theme switching.
- [x] Style toolbar as a compact icon-only refresh control with an `aria-label`; do not rely on emoji glyphs.
- [x] Style bottom view navigation as a mobile-style icon menu for Main, Activity, and Setting.
- [x] Style Setting view as terminal-like block: thin border, compact section labels, aligned select/switch rows, no modal-heavy chrome.
- [x] Preserve readable contrast and focus rings across all themes.
- [x] Add a focused style regression check, static assertion, or documented grep to ensure legacy `rgba(255, 95, 143...)`, `rgba(124, 92, 255...)`, and `#ff5f8f` do not remain outside explicit theme token definitions.

Evidence for Tasks 3-6: `pnpm test -- tests/app-shell.test.tsx tests/preferences.test.ts tests/settings-panel.test.tsx tests/task-row.test.tsx tests/project-group.test.tsx` passed; after view-nav update, full `pnpm --filter @workbranch/companion test` passed with 11 files / 30 tests. `pnpm typecheck` passed; legacy Raycast color grep returned no matches. `App.tsx` is 250 nonblank/noncomment LOC after extracting `useCompanionSettings.ts` and `ViewNav.tsx`.

## Task 7: Verification

Automated from repo root:

- [x] `pnpm --filter @workbranch/companion test` -> 11 test files, 30 tests passed after bottom view-nav update.
- [x] `pnpm --filter @workbranch/companion typecheck` -> passed.
- [x] `pnpm --filter @workbranch/companion lint` -> passed with existing `parseContract.ts` `useLiteralKeys` info diagnostics only; no lint errors.
- [x] `pnpm --filter @workbranch/companion build` -> Vite production build passed.
- [x] `cargo test --manifest-path apps/workbranch-companion/src-tauri/Cargo.toml` -> 16 Rust tests passed, 0 failed.
- [x] `git diff --check` -> passed.

Tauri/plugin verification:

- [x] `rust-toolchain.toml` pins `1.95.0`; `rustc --version` now reports `rustc 1.95.0` from the repo without manual `RUSTUP_TOOLCHAIN`.
- [x] `pnpm --filter @workbranch/companion tauri build` -> passed and bundled `WorkbranchCompanion.app`.
- [x] `pnpm --filter @workbranch/companion tauri dev` -> reached Vite ready + Cargo `Info Watching .../src-tauri` without the previous `rustc 1.93.1 is not supported` failure; process was terminated intentionally after the startup smoke.

Manual visual/behavior gate:

- [x] Vite fallback surface captured in Chrome headless at 375, 768, and 1280 px: `/tmp/workbranch-companion-visual/companion-375.png`, `/tmp/workbranch-companion-visual/companion-768.png`, `/tmp/workbranch-companion-visual/companion-1280.png`.
- [x] Setting view opened through Chrome DevTools Protocol and captured: `/tmp/workbranch-companion-visual/companion-settings-1280.png` for the earlier panel pass and `/tmp/workbranch-companion-visual/view-setting-390.png` for the bottom-nav pass.
- [x] Browser fallback no longer shows Tauri IPC/plugin page errors; non-Tauri runtime now skips store/autostart/watch effects and leaves footer `Ready`.
- [x] Captured bottom-nav views show icon-only refresh, Main view, Activity report placeholder, Setting view, launch-at-login switch, fixed-width font select, four theme choices, and preview chips in the terminal HUD style. Additional captures: `/tmp/workbranch-companion-visual/view-main-390.png`, `/tmp/workbranch-companion-visual/view-activity-390.png`, `/tmp/workbranch-companion-visual/view-setting-390.png`.

Native tray popover observation gap:

- The native `tauri dev` process starts under Rust 1.95, but this agent session still cannot directly interact with the macOS menu-bar tray popover. Leave this task in `review` until a human/native GUI check confirms the tray popover and signed launch-at-login behavior.

Signed launch-at-login gate:

- Build or install a signed/notarized app path when available (`brew install --cask tkhwang/tap/workbranch-companion` or a signed release asset in `/Applications`).
- Verify launch-at-login ON/OFF against the installed app path, not only `tauri dev`.
- [ ] Signed installation was not available in this implementation session; launch-at-login is plugin/API-smoke-tested and remains a release QA follow-up.

Manual checks:

- Header shows icon-only refresh control.
- Bottom view nav switches between Main, Activity, and Setting without disrupting task refresh/watch behavior.
- Launch-at-login toggle reflects `isEnabled()` and reports errors in the footer/status line.
- Font selector contains only fixed-width choices and changes the whole companion UI.
- Theme selector changes the whole companion UI across the four presets.
- No Raycast pink/violet shell glow, top hairline, current-step glow, active rail, badge, or status color leaks into amber-crt, green-mono, or high-contrast.
- CLI-like visual feel is stronger than 0036/Raycast: fixed-width text, terminal-like density, less glossy app chrome.
- Keyboard focus rings, labels, empty/error states, and narrow width remain readable.

## Acceptance criteria

- `docs/plans/0036-companion-project-grouped-ui.md` remains focused on project grouping/action hierarchy; settings/theme work lives in this 0037 plan.
- Top-right toolbar includes icon-only refresh.
- Bottom view nav includes Main, Activity, and Setting destinations.
- Setting view includes launch-at-login, fixed-width font selector, and color theme selector.
- Launch-at-login uses official Tauri autostart plugin and does not store duplicate launch state in workbranch project config.
- Font/theme preferences persist through official Tauri store plugin.
- Preference persistence uses only `companion-preferences.json` top-level `font` and `theme` keys; launch-at-login is never persisted there.
- All selectable fonts are fixed-width options; arbitrary fonts are not accepted.
- Theme presets are fixed and covered by tests.
- Every theme preset defines the complete theme token interface, and implementation removes or tokenizes legacy hard-coded Raycast gradient/color literals.
- UI visual direction is updated in `DESIGN.md` and implemented via CSS tokens/classes, not ad-hoc inline styles.
- CLI contract, task domain model, ACL mapping, watcher behavior, and activity store behavior are unchanged.

## Non-goals

- Do not add task lifecycle mutation UI.
- Do not add arbitrary custom theme editor or arbitrary font input.
- Do not introduce Tailwind/shadcn/Radix.
- Do not change `workbranch list --json` / `list --global --json` schemaVersion 1.
- Do not merge this work back into 0036; 0036 should remain independently implementable.

## Self-review checklist for this plan

- [x] Split scope from 0036 is explicit.
- [x] Setting view includes launch-at-login, fixed-width font selection, and color theme selection, reached from bottom view nav.
- [x] CLI-like visual direction is reflected in design-contract tasks.
- [x] Official Tauri v2 autostart/store plugin paths and permissions are captured.
- [x] Preference persistence excludes project config and CLI contract changes.
- [x] Tests and manual visual gate cover bottom view navigation, settings behavior, and theme/font application.
- [x] No TBD/TODO placeholders.
