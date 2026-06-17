# 0037 Companion Settings and CLI Theme Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` or `$plan-execute auto` to implement this plan task-by-task. For `.ts`/`.tsx`/`.rs` edits, follow TypeScript/Rust guidance and lock semantics with tests before visual changes. For visual changes, follow `DESIGN.md`, drive `pnpm --filter @workbranch/companion tauri dev`, and visually verify the settings panel, font/theme application, and launch-at-login toggle before claiming completion.

**Goal:** Add a compact settings surface to the Workbranch Companion popover and shift the visual system toward a terminal/CLI-like developer HUD: a settings icon beside refresh, launch-at-login toggle, fixed-width font selector, and color theme selector.

**Architecture:** Split this from 0036. Keep 0036 focused on project grouping and row hierarchy. In this plan, add preference state and settings UI to the Tauri React companion. Use official Tauri v2 plugins for OS/app persistence: `@tauri-apps/plugin-autostart` for launch-at-login and `@tauri-apps/plugin-store` for font/theme preferences. Do not change the CLI JSON contract, domain task model, watcher, or activity store.

**Tech Stack:** Tauri v2, React 18, TypeScript, Vite, Vitest, Biome, plain CSS, official Tauri plugins `autostart` and `store`. No Tailwind/shadcn/Radix.

---

## Product framing

The companion is becoming less of a generic dashboard and more of a command-line control panel for task worktrees. The settings surface should feel like a small terminal preferences pane, not a full app settings window.

User-visible additions:

1. Top-right toolbar becomes `Refresh | Settings` with compact icon buttons and accessible labels.
2. Settings icon opens an in-popover settings panel.
3. `Launch at login` toggles app autostart.
4. Font selector offers only fixed-width fonts.
5. Color theme selector switches between CLI-like themes.
6. The default visual feel moves from Raycast-like chrome toward fixed-width, terminal-inspired HUD styling.

## Current repo evidence

- `apps/workbranch-companion/src/App.tsx` currently renders a single refresh button in the top-right header and has no settings panel state.
- `apps/workbranch-companion/src/style.css` currently uses `Inter, ui-sans-serif, system-ui` at `:root`; only repo chips use a monospace stack.
- `apps/workbranch-companion/package.json` has Tauri/React dependencies but no autostart/store plugins.
- `apps/workbranch-companion/src-tauri/src/lib.rs` currently initializes only `tauri_plugin_positioner`; no autostart/store plugin is wired.
- `apps/workbranch-companion/src-tauri/capabilities/default.json` must grant explicit plugin permissions when new Tauri plugins are exposed to the frontend.
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

## File structure

Modify:

- `DESIGN.md` — update visual language, typography, color/theme tokens, and settings components to reflect CLI-like companion direction.
- `apps/workbranch-companion/package.json` and lockfile — add official Tauri plugin packages.
- `apps/workbranch-companion/src-tauri/Cargo.toml` / `Cargo.lock` — add autostart/store Rust plugin dependencies through the Tauri add flow.
- `apps/workbranch-companion/src-tauri/src/lib.rs` — initialize autostart and store plugins.
- `apps/workbranch-companion/src-tauri/capabilities/default.json` — add autostart and store permissions.
- `apps/workbranch-companion/src/App.tsx` — add toolbar settings button, settings panel state, preference loading/application, and launch-at-login status wiring.
- `apps/workbranch-companion/src/style.css` — add CLI-like theme variables, font-family variable, settings panel styles, toolbar styles, and theme classes.
- `apps/workbranch-companion/tests/**/*.test.tsx?` — add focused preference/settings tests.
- `TASK-WORKBRANCH.md` — task progress updates only.

Create:

- `apps/workbranch-companion/src/application/preferences.ts` — preference types, defaults, font/theme option lists, sanitizers, and store helpers.
- `apps/workbranch-companion/src/ui/SettingsPanel.tsx` — settings panel UI.
- `apps/workbranch-companion/tests/preferences.test.ts` — preference sanitization/default coverage.
- `apps/workbranch-companion/tests/settings-panel.test.tsx` — static markup / callback coverage.

Do not modify:

- `apps/workbranch-cli/**`
- `packages/contract/**`
- `apps/workbranch-companion/src/domain/**`
- `apps/workbranch-companion/src/infrastructure/acl.ts`
- watcher/activity-store behavior except plugin initialization required by this settings slice.

## Task 1: Update design contract for CLI-like settings direction

**Files:** Modify `DESIGN.md`, `../TASK-WORKBRANCH.md`

- [ ] Update **Brand** personality to terminal/CLI-like developer HUD, not generic app dashboard.
- [ ] Update **Visual language**:
  - typography defaults to fixed-width UI;
  - theme tokens include `terminal-dark`, `amber-crt`, `green-mono`, `high-contrast`;
  - avoid heavy gradients; prefer prompt-like separators, subtle grid/border lines, compact density.
- [ ] Update **Components** to include top toolbar, settings button, settings panel, switch row, select row, and theme swatches.
- [ ] Update **Accessibility** to require real button labels for refresh/settings, select labels, and switch state text.
- [ ] Verify no placeholders: `rg -n "TBD|TODO|placeholder|fill in" DESIGN.md` -> no matches.

## Task 2: Add official Tauri plugins

**Files:** Modify package/Cargo/capabilities/lib.rs surfaces

- [ ] Add autostart plugin via Tauri CLI from `apps/workbranch-companion`:

  ```bash
  pnpm tauri add autostart
  ```

- [ ] Add store plugin via Tauri CLI from `apps/workbranch-companion`:

  ```bash
  pnpm tauri add store
  ```

- [ ] Confirm `src-tauri/src/lib.rs` initializes:
  - `tauri_plugin_autostart::init(...)`
  - `tauri_plugin_store::Builder::new().build()`
- [ ] Confirm `src-tauri/capabilities/default.json` includes:
  - `autostart:allow-enable`
  - `autostart:allow-disable`
  - `autostart:allow-is-enabled`
  - `store:default`

## Task 3: Preference model and persistence

**Files:** Create `src/application/preferences.ts`; Create/modify tests

- [ ] Add `CompanionFont`, `CompanionTheme`, `CompanionPreferences`, defaults, and option arrays.
- [ ] Add sanitizers so unknown stored values fall back to defaults.
- [ ] Add store helpers around `@tauri-apps/plugin-store` that load and save only `{ font, theme }`.
- [ ] Tests:
  - default preferences are terminal-dark + system-mono;
  - invalid font/theme sanitize to defaults;
  - option arrays contain only fixed-width font choices;
  - theme list includes the four resolved presets.

## Task 4: Settings panel UI

**Files:** Create `src/ui/SettingsPanel.tsx`; Create `tests/settings-panel.test.tsx`

- [ ] Render a compact CLI-like panel opened from the top toolbar.
- [ ] Include sections:
  - `Startup` with `Launch at login` toggle;
  - `Font` select with fixed-width options only;
  - `Theme` select/swatches with four presets.
- [ ] The launch-at-login toggle is immediate-apply and calls `enable()`/`disable()` through an injected callback.
- [ ] Font/theme updates save preferences and update the app immediately.
- [ ] Static markup tests assert labels, option names, and accessible control names.

## Task 5: App shell wiring

**Files:** Modify `src/App.tsx`

- [ ] Replace single refresh button with a toolbar group: Refresh and Settings controls separated by a thin divider.
- [ ] Add settings panel open/close state.
- [ ] On app startup, load preferences from store and apply theme/font classes to the root shell.
- [ ] On settings change, save preferences and update root shell immediately.
- [ ] On app startup, call `isEnabled()` to initialize launch-at-login state.
- [ ] On launch-at-login toggle:
  - true -> `enable()`, then refresh `isEnabled()`;
  - false -> `disable()`, then refresh `isEnabled()`;
  - failures set the existing footer/status message.
- [ ] Keep task refresh/watch behavior unchanged.

## Task 6: CLI-like style system

**Files:** Modify `src/style.css`

- [ ] Replace proportional root stack with `var(--app-font-family)` defaulting to fixed-width.
- [ ] Add root classes or data attributes for `font-*` and `theme-*` preferences.
- [ ] Define theme variables for the four presets.
- [ ] Style toolbar as compact command controls. Use text labels or inline SVG icons with `aria-label`s; do not rely on emoji glyphs for refresh/settings icons.
- [ ] Style settings panel as terminal-like block: thin border, compact section labels, aligned select/switch rows, no modal-heavy chrome.
- [ ] Preserve readable contrast and focus rings across all themes.

## Task 7: Verification

Automated from repo root:

```bash
pnpm --filter @workbranch/companion test
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
pnpm --filter @workbranch/companion build
git diff --check
```

Tauri/plugin verification:

```bash
pnpm --filter @workbranch/companion tauri build
```

Manual visual/behavior gate:

```bash
pnpm --filter @workbranch/companion tauri dev
```

Manual checks:

- Header shows refresh and settings controls separated visually.
- Settings panel opens/closes without disrupting task refresh/watch behavior.
- Launch-at-login toggle reflects `isEnabled()` and reports errors in the footer/status line.
- Font selector contains only fixed-width choices and changes the whole companion UI.
- Theme selector changes the whole companion UI across the four presets.
- CLI-like visual feel is stronger than 0036/Raycast: fixed-width text, terminal-like density, less glossy app chrome.
- Keyboard focus rings, labels, empty/error states, and narrow width remain readable.

## Acceptance criteria

- `docs/plans/0036-companion-project-grouped-ui.md` remains focused on project grouping/action hierarchy; settings/theme work lives in this 0037 plan.
- Top-right toolbar includes refresh and settings controls.
- Settings panel includes launch-at-login, fixed-width font selector, and color theme selector.
- Launch-at-login uses official Tauri autostart plugin and does not store duplicate launch state in workbranch project config.
- Font/theme preferences persist through official Tauri store plugin.
- All selectable fonts are fixed-width options; arbitrary fonts are not accepted.
- Theme presets are fixed and covered by tests.
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
- [x] Settings includes launch-at-login, fixed-width font selection, and color theme selection.
- [x] CLI-like visual direction is reflected in design-contract tasks.
- [x] Official Tauri v2 autostart/store plugin paths and permissions are captured.
- [x] Preference persistence excludes project config and CLI contract changes.
- [x] Tests and manual visual gate cover settings behavior and theme/font application.
- [x] No TBD/TODO placeholders.
