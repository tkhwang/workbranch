# Design

## Source of truth
- Status: Active
- Last refreshed: 2026-06-17
- Primary product surfaces: Workbranch Companion macOS menu bar popover.
- Evidence reviewed:
  - `docs/plans/0032-companion-tauri-react-rewrite.md`
  - `docs/plans/0033-companion-responsiveness-nonblocking-commands-and-watch-scope.md`
  - `apps/workbranch-companion/src/App.tsx`
  - `apps/workbranch-companion/src/ui/TaskRow.tsx`
  - `apps/workbranch-companion/src/style.css`

## Brand
- Personality: fast, focused, developer-native, command-oriented.
- Trust signals: fast refresh, clear current step, visible repo dirty/branch state, sleek dark chrome, restrained accent glow.
- Avoid: marketing hero layouts, oversized cards, large SaaS rows, generic dashboard cards, generic shadcn look, decorative animation.

## Product goals
- Goals:
  - Show active worktree tasks and their active plan status at a glance.
  - Make the current plan step feel like the selected command/result in a launcher.
  - Keep repo branch/dirty state visible without competing with task progress.
  - Keep actions discoverable but visually secondary.
- Non-goals:
  - Task lifecycle mutation UI.
  - Full project dashboard or report view redesign.
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
- Primary navigation: single popover grouped by project, with groups sorted by most recent task update.
- Core screens: project-grouped task list, expanded task details, error rows.
- Content hierarchy:
  1. Global inventory + status rollup and refresh.
  2. Project group header (name + task count).
  3. Task name + status dot + progress + notification.
  4. Repo branch/dirty state.
  5. Active plan / current step, then nested plan steps.
  6. Actions (IDE, Terminal, Finder).

## Design principles
- Principle 1: Status is a launcher signal, not a paragraph. Use compact dots, counts, and labels.
- Principle 2: Current work beats historical detail. The active/current step is always above the full checklist.
- Principle 3: Developer metadata should be monospace and subdued until dirty/blocked.
- Tradeoffs: density is preferred over spaciousness, but tap/click targets remain at least 32px high where practical.

## Visual language
- Color: Raycast-style dark chrome with restrained red-pink/violet active accents, red blocked accent, green done accent, amber notification accent.
- Typography: system UI for labels; monospace only for repo/branch/path-like metadata.
- Spacing/layout rhythm: compact command-palette rhythm, 8px grid, row-first grouping, no large cards.
- Shape/radius/elevation: one fixed radius scale (`6px` controls, `10px` rows, `14px` shell); depth from dark chrome background steps, soft inset highlights, and hairline borders.
- Motion: 120ms press/reveal feedback only; respect reduced motion.
- Imagery/iconography: text glyphs and status dots only; no decorative illustration.

## Components
- Existing components to reuse: `TaskRow`, action buttons, native `details/summary` disclosure.
- New/changed components:
  - global inventory/status summary,
  - project group header,
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
- Screen-reader semantics: preserve button `aria-label`s; use meaningful text labels for status where visible.
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
- Framework/styling system: React 18 + plain CSS; no Tailwind/shadcn in this refresh. Primary reference is Raycast; Linear remains only a secondary status-hierarchy cue.
- Design-token constraints: CSS custom properties in `style.css`.
- Performance constraints: no extra runtime package; no animation loops; preserve 0033 responsiveness fixes.
- Compatibility constraints: no CLI/contract/Rust port changes.
- Test/screenshot expectations: Vitest static markup tests plus `pnpm --filter @workbranch/companion tauri build`; run a browser/app screenshot review before final handoff.

## Open questions
- [ ] Whether a later v2 should add shadcn/Radix primitives after the plain CSS refresh proves the needed component gaps.


## Direction revision
- 2026-06-17: Primary reference changed from Linear to Raycast after implementation review. Keep Linear only as a secondary cue for compact status hierarchy; the dominant feel should be a Raycast-like menu command/status popover, not a SaaS issue-list dashboard.
