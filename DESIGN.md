# Design

## Source of truth
- Status: Active
- Last refreshed: 2026-06-21
- Primary product surfaces: Workbranch Companion macOS menu bar popover.
- Evidence reviewed:
  - `docs/plans/0032-companion-tauri-react-rewrite.md`
  - `docs/plans/0033-companion-responsiveness-nonblocking-commands-and-watch-scope.md`
  - `docs/plans/0037-companion-settings-cli-theme.md`
  - `docs/plans/0039-companion-action-icons-top-and-theme-lineup.md`
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
- Primary navigation: sticky floating bottom view bar with three destinations: Main, Activity, Setting.
- Core screens: Main task list, Activity report stub, Setting preferences view.
- Content hierarchy:
  1. Global inventory + status rollup and icon-only refresh.
  2. Active view content.
  3. Main view: project group header, task name/status/progress/notification, repo branch/dirty state, active plan/current step, actions.
  4. Activity view: future report stub only in this slice.
  5. Setting view: launch-at-login, font, and theme controls.
  6. Screen-reader live status in the top toolbar and bottom view navigation; routine `Updated`/`Ready` text stays out of the visible top line.

## Design principles
- Principle 1: Status is a launcher signal, not a paragraph. Use compact dots, counts, and labels.
- Principle 2: Current work beats historical detail. The active/current step is always above the full checklist.
- Principle 3: Developer metadata should be monospace and subdued until dirty/blocked.
- Tradeoffs: density is preferred over spaciousness, but tap/click targets remain at least 32px high where practical.

## Visual language
- Color: Settings exposes one curated companion palette rather than parallel color families. Dark mode resolves to Catppuccin-inspired surfaces (`#1e1e2e`, `#181825`) with lavender/pink accents (`#cba6f7`, `#f5c2e7`) because it is the preferred dark look. Light mode is white/neutral rather than yellow: near-white surfaces (`#ffffff`, `#fbfcff`, `#f4f6fb`) with dark slate text (`#242633`) and a subtle lavender accent (`#7c3aed`). The visible setting is only `Light | Dark | System`; legacy theme families and concrete theme values collapse to this Companion palette while preserving mode.
- Typography: dual-axis. UI chrome (task/project names, headings, button and nav labels, settings controls) uses a system sans stack for hierarchy and readability; developer data (repo/branch/path, counts, plan label) stays monospace. The user-selectable font preference controls the monospace data stack.
- Spacing/layout rhythm: compact terminal/preferences rhythm, 8px grid, row-first grouping, prompt-like separators, subtle grid or border lines, no large cards.
- Shape/radius/elevation: one fixed radius scale (`6px` controls, `10px` rows, `14px` shell); depth from clearly stepped tonal surfaces, soft elevation shadows on cards, and hairline borders; cards lift on hover. Avoid heavy gradients and glossy neon glow.
- Motion: 120ms press/reveal feedback only; respect reduced motion.
- Imagery/iconography: status state uses quiet color dots with accessible labels; avoid status checkmark glyphs in task headers. Checklist rows use a separate aligned marker column instead of checkmark or checkbox text prefixes; depth 0 uses a small quiet square marker, depth 1+ keeps circular markers, and completed markers use neutral muted tones rather than loud green. No decorative illustration.

## Components
- Existing components to reuse: `TaskRow`, action buttons, native `details/summary` disclosure.
- New/changed components:
  - global inventory/status summary,
  - project group header,
  - top toolbar with icon-only refresh/quit controls and screen-reader-only live status,
  - sticky floating bottom view navigation for Main, Activity, and Setting,
  - Setting view preferences panel,
  - Activity report stub view,
  - switch row for launch-at-login,
  - font select row,
  - theme mode segmented control (`Light`, `Dark`, `System`) with no visible color-family grid,
  - launcher-like task summary line,
  - current-step strip,
  - detail header row containing repo chips and a full-width IDE/Terminal/Finder action bar split into equal thirds above current step and checklist content,
  - nested step tree with aligned status markers separate from step text: small depth 0 square, depth 1 circle, deeper levels smaller circles.
- Variants and states: todo, planning, in-progress, review, blocked, done, notification present, dirty repo.
- Token/component ownership: `style.css` is the CSS import manifest; `src/styles/base.css`, `themes.css`, `chrome.css`, `task-details.css`, `status-groups.css`, `settings.css`, and `motion.css` own CSS custom properties and component classes by surface.

## Accessibility
- Target standard: keyboard-operable popover controls and readable contrast.
- Keyboard/focus behavior: buttons and `summary` expose clear focus rings.
- Contrast/readability: status text and current step must pass practical dark-mode contrast; disabled action may be muted but legible.
- Screen-reader semantics: preserve button `aria-label`s; bottom view buttons expose destination labels and `aria-current`; settings controls use associated labels, switch state text, and the toolbar keeps a screen-reader-only `role="status"` region with polite live updates.
- Reduced motion and sensory considerations: disable transform transitions under `prefers-reduced-motion: reduce`.

## Responsive behavior
- Supported breakpoints/devices: narrow menu popover around 360-460px width.
- Layout adaptations: the detail header keeps repo chips above a full-width launch-action row; IDE, Terminal, and Finder each occupy one third of that row above steps; repo chips wrap; long task/step names truncate with accessible full text via `title`.
- Touch/hover differences: hover is enhancement only; core state is visible without hover.

## Interaction states
- Loading: screen-reader live status reports refresh state without adding a visible top-line chip.
- Empty: concise empty message with setup hint.
- Error: root-scoped error row with red accent; operation failures such as refresh/action/preference errors also render a visible alert row while routine Ready/Updated statuses stay screen-reader-only.
- Success: routine `Updated` / `Action complete` messages are not shown as a visible top-line chip; they remain available to assistive tech.
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
- 2026-06-18: Primary direction changed from Raycast-like chrome to a terminal/CLI developer HUD for companion settings, fonts, and theme presets. Treat the 2026-06-17 Raycast direction as superseded for shell color, typography, and settings components; keep only the compact status hierarchy lessons. Later on 2026-06-18, navigation changed to view-level bottom tabs: Main, Activity report stub, and Setting, while the top-right header keeps refresh as an icon-only control.
- 2026-06-18 (refresh): Direction refined from a mono-only terminal HUD to a **modern developer HUD — terminal core, modern shell**. The strict mono-only typography and hairline-only depth produced a flat, low-contrast, drab popover. Corrections: (1) dual-axis typography — system sans for names/headings/controls, monospace kept for developer data; (2) clearly stepped tonal surfaces plus soft card elevation with hover lift, replacing near-invisible translucent cards; (3) accent (cyan in terminal-dark) stays the single signal color but appears on more touchpoints (project rail, current-step left rail, active states). This supersedes the mono-only typography line and the hairline-only depth line above. Identity, density, status-as-launcher, and the theme preset direction now expands to four famous families with dark/light variants.
- 2026-06-21: Task detail launch controls move from the bottom of expanded checklist content into the top detail header next to repo chips, wrapping above steps on narrow widths. Theme lineup was initially narrowed to Solarized, Gruvbox, Catppuccin, and GitHub with removed Dracula/Nord migrations.
- 2026-06-21 (follow-up): Launch controls now occupy a full-width action row in equal thirds. Dark theme lineup replaces Gruvbox with Dracula, so the active families are Solarized, Dracula, Catppuccin, and GitHub; old `gruvbox` settings migrate to `dracula`, while `nord` still migrates to `solarized`. Checklist status moved from loose `✓`/`☐` text prefixes to an aligned marker column so row text scans cleanly; follow-up tuning makes depth 0 a smaller, lighter square marker, keeps depth 1 circular, and lowers completed markers to neutral muted tones instead of bright green.
- 2026-06-22: Added Breakfast as the default companion theme family after reviewing tokens4breakfast.app. The palette shifts the first-run menu bar popover from cool terminal blue toward warm parchment/espresso/amber while keeping compact developer-HUD density and preserving existing terminal/editor theme choices. Legacy `amber-crt` and removed `gruvbox` settings now migrate to Breakfast as the nearest warm theme.
- 2026-06-22 (settings simplification): Collapsed the visible color theme family picker into a single Companion palette with only `Light | Dark | System` controls. Dark mode now resolves to Catppuccin as the preferred dark look; light mode keeps the same calm direction but shifts from yellow Breakfast parchment to a whiter neutral surface palette. Existing stored theme families migrate to Companion while preserving mode.

- 2026-06-22 (toolbar): Removed the visible top toolbar status chip after review; the top line now keeps task inventory plus icon controls only. A screen-reader-only polite live region preserves status announcements without showing routine `Updated` text in the popover chrome.

- 2026-06-23: Light mode shifted from yellow/warm Breakfast parchment to a whiter neutral palette with subtle lavender accents after visual review.
