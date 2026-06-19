# Design

## Source of truth
- Status: Active
- Last refreshed: 2026-06-18
- Primary product surfaces: Workbranch Companion macOS menu bar popover.
- Evidence reviewed:
  - `docs/plans/0032-companion-tauri-react-rewrite.md`
  - `docs/plans/0033-companion-responsiveness-nonblocking-commands-and-watch-scope.md`
  - `docs/plans/0037-companion-settings-cli-theme.md`
  - `apps/companion/src/App.tsx`
  - `apps/companion/src/ui/TaskRow.tsx`
  - `apps/companion/src/style.css`

## Brand
- Personality: fast, focused, terminal-native, command-line HUD.
- Trust signals: fast refresh, clear current step, visible repo dirty/branch state, fixed-width readability, restrained terminal accents.
- Avoid: marketing hero layouts, oversized cards, large SaaS rows, generic dashboard cards, decorative animation, glossy neon chrome. Tasteful elevation and a sans/mono type hierarchy are welcome.

## Product goals
- Goals:
  - Show active worktree tasks and their active plan status at a glance.
  - Make the current plan step feel like the selected command/result in a launcher.
  - Keep repo branch/dirty state visible without competing with task progress.
  - Keep actions discoverable but visually secondary.
- Non-goals:
  - Task lifecycle mutation UI.
  - Full activity report implementation.
  - New UI dependency stack.
- Success signals:
  - A user can identify active/blocked work in under three seconds.
  - A user can find the current step without expanding every row.
  - The popover remains readable at approximately 360px width.

## Personas and jobs
- Primary personas: developers using `workbranch` task workspaces and AI agents.
- User jobs:
  - Check what is currently in progress.
  - See which repo/branch is dirty.
  - Open task in IDE/terminal/Finder.
  - Notice notification counts as visible status without clearing them from this surface.
- Key contexts of use: quick menu bar glance while coding, before switching tasks, during AI-agent execution.

## Information architecture
- Primary navigation: bottom mobile-style view bar with three destinations: Main, Activity, Setting.
- Core screens: Main task list, Activity report placeholder, Setting preferences view.
- Content hierarchy:
  1. Global inventory + status rollup and icon-only refresh.
  2. Active view content.
  3. Main view: project group header, task name/status/progress/notification, repo branch/dirty state, active plan/current step, actions.
  4. Activity view: future report placeholder only in this slice.
  5. Setting view: launch-at-login, font, and theme controls.
  6. Persistent live status footer and bottom view navigation.

## Design principles
- Principle 1: Status is a launcher signal, not a paragraph. Use compact dots, counts, and labels.
- Principle 2: Current work beats historical detail. The active/current step is always above the full checklist.
- Principle 3: Developer metadata should be monospace and subdued until dirty/blocked.
- Tradeoffs: density is preferred over spaciousness, but tap/click targets remain at least 32px high where practical.

## Visual language
- Color: terminal-like theme presets (`terminal-dark`, `amber-crt`, `green-mono`, `high-contrast`) with complete token sets for surfaces, lines, text, accents, status colors, and shell/component backgrounds.
- Typography: dual-axis. UI chrome (task/project names, headings, button and nav labels, settings controls) uses a system sans stack for hierarchy and readability; developer data (repo/branch/path, counts, plan label) stays monospace. The user-selectable font preference controls the monospace data stack.
- Spacing/layout rhythm: compact terminal/preferences rhythm, 8px grid, row-first grouping, prompt-like separators, subtle grid or border lines, no large cards.
- Shape/radius/elevation: one fixed radius scale (`6px` controls, `10px` rows, `14px` shell); depth from clearly stepped tonal surfaces, soft elevation shadows on cards, and hairline borders; cards lift on hover. Avoid heavy gradients and glossy neon glow.
- Motion: 120ms press/reveal feedback only; respect reduced motion.
- Imagery/iconography: text glyphs and status dots only; no decorative illustration.

## Components
- Existing components to reuse: `TaskRow`, action buttons, native `details/summary` disclosure.
- New/changed components:
  - global inventory/status summary,
  - project group header,
  - top toolbar with icon-only refresh control,
  - bottom view navigation for Main, Activity, and Setting,
  - Setting view preferences panel,
  - Activity report placeholder view,
  - switch row for launch-at-login,
  - font select row,
  - theme select row with optional non-interactive preview chips,
  - launcher-like task summary line,
  - current-step strip,
  - repo chips,
  - action bar limited to IDE, Terminal, and Finder,
  - nested step tree.
- Variants and states: todo, planning, in-progress, review, blocked, done, notification present, dirty repo.
- Token/component ownership: `style.css` owns CSS custom properties and component classes.

## Accessibility
- Target standard: keyboard-operable popover controls and readable contrast.
- Keyboard/focus behavior: buttons and `summary` expose clear focus rings.
- Contrast/readability: status text and current step must pass practical dark-mode contrast; disabled action may be muted but legible.
- Screen-reader semantics: preserve button `aria-label`s; bottom view buttons expose destination labels and `aria-current`; settings controls use associated labels, switch state text, and a live status footer.
- Reduced motion and sensory considerations: disable transform transitions under `prefers-reduced-motion: reduce`.

## Responsive behavior
- Supported breakpoints/devices: narrow menu popover around 360-460px width.
- Layout adaptations: actions wrap; repo chips wrap; long task/step names truncate with accessible full text via `title`.
- Touch/hover differences: hover is enhancement only; core state is visible without hover.

## Interaction states
- Loading: footer/status line reports refresh status.
- Empty: concise empty message with setup hint.
- Error: root-scoped error row with red accent.
- Success: status footer says `Updated` / `Action complete`.
- Disabled: disabled action has muted text and no press transform.
- Offline/slow network: not applicable; CLI/local filesystem driven.

## Content voice
- Tone: terse, operational, developer-native.
- Terminology: task, plan, step, repo, branch, dirty.
- Microcopy rules: prefer short row action labels (`IDE`, `Terminal`, `Finder`) over sentences; omit `Copy`/`Memo`/`Noti`/`Clear` row vocabulary because those companion actions are removed, not hidden.

## Implementation constraints
- Framework/styling system: React 18 + plain CSS; no Tailwind/shadcn in this refresh. Primary reference is a modern developer HUD with a terminal core (mono data) and a modern shell (sans chrome, stepped surfaces, soft elevation); Raycast remains a secondary compact-popover cue.
- Design-token constraints: CSS custom properties in `style.css`.
- Performance constraints: no extra runtime package; no animation loops; preserve 0033 responsiveness fixes.
- Compatibility constraints: no CLI/contract/Rust port changes.
- Test/screenshot expectations: Vitest static markup tests plus `pnpm --filter @workbranch/companion tauri build`; run a browser/app screenshot review before final handoff.

## Open questions
- [ ] Whether a later v2 should add shadcn/Radix primitives after the plain CSS refresh proves the needed component gaps.


## Direction revision
- 2026-06-17: Primary reference changed from Linear to Raycast after implementation review. Keep Linear only as a secondary cue for compact status hierarchy; the dominant feel should be a Raycast-like menu command/status popover, not a SaaS issue-list dashboard.
- 2026-06-18: Primary direction changed from Raycast-like chrome to a terminal/CLI developer HUD for companion settings, fonts, and theme presets. Treat the 2026-06-17 Raycast direction as superseded for shell color, typography, and settings components; keep only the compact status hierarchy lessons. Later on 2026-06-18, navigation changed to view-level bottom tabs: Main, Activity report placeholder, and Setting, while the top-right header keeps refresh as an icon-only control.
- 2026-06-18 (refresh): Direction refined from a mono-only terminal HUD to a **modern developer HUD — terminal core, modern shell**. The strict mono-only typography and hairline-only depth produced a flat, low-contrast, drab popover. Corrections: (1) dual-axis typography — system sans for names/headings/controls, monospace kept for developer data; (2) clearly stepped tonal surfaces plus soft card elevation with hover lift, replacing near-invisible translucent cards; (3) accent (cyan in terminal-dark) stays the single signal color but appears on more touchpoints (project rail, current-step left rail, active states). This supersedes the mono-only typography line and the hairline-only depth line above. Identity, density, status-as-launcher, and the four theme presets are unchanged.
