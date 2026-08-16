# Design

## Source of truth
- Status: Active
- Last refreshed: 2026-07-24
- Primary product surfaces: Workbranch Companion macOS menu bar popover.
- Evidence reviewed:
  - `docs/plans/0032-companion-tauri-react-rewrite.md`
  - `docs/plans/0033-companion-responsiveness-nonblocking-commands-and-watch-scope.md`
  - `docs/plans/0037-companion-settings-cli-theme.md`
  - `docs/plans/0039-companion-action-icons-top-and-theme-lineup.md`
  - `apps/companion/src/App.tsx`
  - `apps/companion/src/ui/StageBoard.tsx`
  - `apps/companion/src/ui/TaskRow.tsx`
  - `apps/companion/src/style.css`
  - `https://brainless.swerdlow.dev/components`
  - Brainless `claude-header`, `claude-message`, `codex-header`, and `codex-message` registry sources reviewed on 2026-07-20

## Brand
- Personality: fast, focused, terminal-native, command-line HUD.
- Trust signals: fast refresh, clear task stage, visible repo dirty/branch state, fixed-width readability, restrained terminal accents.
- Avoid: marketing hero layouts, oversized cards, large SaaS rows, generic dashboard cards, decorative animation, glossy neon chrome, soft-elevation card stacks, and mixed UI typography that weakens the terminal identity.

## Product goals
- Goals:
  - Show active worktree tasks grouped into Plan, Execution, and Review stages at a glance.
  - Make blocked state, progress, and notification counts scannable without opening task details.
  - Keep repo branch/dirty state visible without competing with task progress.
  - Keep actions discoverable but visually secondary.
  - Let the user choose a Claude Code or Codex CLI experience that applies to Main, Activity, and Settings.
- Non-goals:
  - Task lifecycle mutation UI.
  - Full activity report implementation.
  - New UI dependency stack.
- Success signals:
  - A user can identify active/blocked work in under three seconds.
  - A user can identify each active task's stage without expanding any row.
  - The popover remains readable at its 460px native minimum width.

## Personas and jobs
- Primary personas: developers using `workbranch` task workspaces and AI agents.
- User jobs:
  - Check what is currently in progress.
  - See which repo/branch is dirty.
  - Open task in IDE/terminal/Finder.
  - Notice notification counts on stage cards without duplicating them in repository metadata rows.
- Key contexts of use: quick menu bar glance while coding, before switching tasks, during AI-agent execution.

## Information architecture
- Primary navigation: an inset floating terminal tab bar anchored to the viewport bottom with three destinations: Main, Activity, Settings.
- Core screens: Main stage board and repository metadata list, Activity report, Settings preferences view.
- Content hierarchy:
  1. Compact global inventory (`projects · tasks`) and icon-only refresh.
  2. Active view content.
  3. Main view: three-column `PLAN | EXECUTION | REVIEW` board for active tasks, followed by project-grouped task metadata rows with repo branch/dirty state and launch actions.
  4. Activity view: existing day/three-day calendar, session selection, and reload behavior inside the agent shell.
  5. Settings view: launch-at-login, font, and agent theme controls.
  6. Screen-reader live status in the agent shell; routine `Updated`/`Ready` text stays out of the visible header.

## Design principles
- Principle 1: Status is a launcher signal, not a paragraph. Use compact dots, counts, and labels.
- Principle 2: Stage beats step detail. Main shows where work is now; checklist and current-step detail remain outside this compact surface.
- Principle 3: Developer metadata should be monospace and subdued until dirty/blocked.
- Tradeoffs: density is preferred over spaciousness, but tap/click targets remain at least 32px high where practical.

## Visual language
- Color: Settings exposes two fixed-dark agent themes. Claude Code uses low-saturation warm-graphite surfaces and neutral warm-gray borders; `#cd694a` remains the identity anchor but is reserved for compact prompt, focus, and active-state signals rather than broad backgrounds. Stage cards use existing neutral surfaces while blocked, review, done, and notification semantics use their existing tokens. `#c0caf5` remains primary terminal text and `#9aa5ce` is the brighter muted text. Codex uses brighter cool-neutral surfaces and borders, `#ededed` for primary text, `#a8a8ad` for muted text, and `#5cc2e0` only for command-like actions and links. Existing Companion, Light, Dark, System, and legacy family values migrate to Claude Code.
- Typography: the agent shell, navigation, content panels, form controls, task metadata, and activity labels use the user-selected monospace stack. The fixed-dark type scale is raised by one pixel with no production size below `10px`, except that the narrow-width agent header remains `13px`; explicit WebKit antialias smoothing is removed so native rendering controls glyph weight. Weight, contrast, spacing, and rules create hierarchy instead of a sans/mono split.
- Spacing/layout rhythm: compact terminal rhythm, 8px grid, row-first grouping, prompt markers, and thin rules. Main, Activity, and Settings use the same expanded agent header so switching tabs does not shift the content vertically.
- Shape/radius/elevation: agent headers use a restrained `6px` radius from the Brainless reference. Stage columns, cards, panels, and rows use square or near-square corners, flat tonal separation, and hairline borders. The bottom navigation may use a pill radius and one restrained shadow to separate it from scrolling content. Do not use card hover lift, gradient, or decorative shadows elsewhere.
- Motion: 120ms press/reveal feedback only; respect reduced motion.
- Imagery/iconography: status state uses quiet color dots with accessible labels; avoid status checkmark glyphs in task headers. Stage cards use terse text cues for blocked, progress, and notifications. No decorative illustration.

## Components
- Existing components to reuse: action buttons, `TerminalPanel`, `PromptLine`, `StatusToken`, activity calendar behavior, and settings preference controls.
- New/changed components:
  - shared `AgentShell` that applies `claude` or `codex` to all views,
  - shared expanded `AgentHeader` for Main, Activity, and Settings with one theme-neutral text anatomy,
  - `AgentTabs` as an inset floating bottom terminal navigation,
  - shared `TerminalPanel`, `PromptLine`, and `StatusToken` primitives,
  - compact global inventory summary limited to project and task counts,
  - `StageBoard` with three fixed columns and compact active-task cards, enclosed by one strong outer status frame with a theme emphasis rail so the board reads as Main's primary surface,
  - project group header,
  - top toolbar with icon-only refresh/quit controls and screen-reader-only live status,
  - Settings view preferences panel,
  - Settings preference sections always use the Claude Code `fieldset`/`legend` anatomy in both themes; the selected theme still owns colors and control state,
  - Activity report view,
  - switch row for launch-at-login,
  - font select row,
  - agent theme segmented control (`Claude Code`, `Codex`) with Claude Code as the default and migration target,
  - `TaskMetaRow` containing task name/status, a full-width repository metadata stack, and a separate full-width IDE/Terminal/Finder action row split into equal thirds,
  - StageCard metadata containing project label, optional blocked cue, progress, and board-only notification `+N`.
- Variants and states: todo, planning, in-progress, review, blocked, done, notification present, dirty repo. In-progress identity uses the compact status marker rather than recoloring the full Task perimeter.
- Done visibility: done tasks are excluded from StageBoard but remain visible in TaskMetaRow so IDE/Terminal/Finder actions stay available.
- Shared header anatomy: Claude Code and Codex use the same text-only title block: `Workbranch Companion` above `projects · tasks`. The top banner contains no Workbranch mark, product icon, or Claude/Codex prompt prefix; theme identity comes from surrounding color tokens rather than different header geometry. Task metadata rows may retain their theme-specific prompt and action accents.
- Token/component ownership: `style.css` is the CSS import manifest; `src/styles/base.css`, `themes.css`, `chrome.css`, `stage-board.css`, `task-details.css`, `task-actions.css`, `status-groups.css`, `settings.css`, and `motion.css` own CSS custom properties and component classes by surface.

## Accessibility
- Target standard: keyboard-operable popover controls and readable contrast.
- Keyboard/focus behavior: buttons and `summary` expose clear focus rings.
- Contrast/readability: status text and StageCard metadata must pass practical dark-mode contrast; disabled action may be muted but legible.
- Screen-reader semantics: preserve button `aria-label`s; agent tab buttons expose destination labels and `aria-current`; settings controls use associated labels, switch state text, and the agent shell keeps a screen-reader-only `role="status"` region with polite live updates.
- Reduced motion and sensory considerations: disable transform transitions under `prefers-reduced-motion: reduce`.

## Responsive behavior
- Supported breakpoints/devices: the native menu popover opens at 460px and cannot resize below 460px.
- Layout adaptations: the shared expanded header keeps its internal columns consistent on every tab. At 460px, StageBoard keeps three equal `minmax(0, 1fr)` columns without horizontal overflow. Each StageCard and TaskMetaRow uses `min-width: 0`; StageCard task/worktree names wrap to their full value with variable card height, while TaskMetaRow task names remain single-line ellipsized with full text in `title`. Each repository/branch pair occupies the full metadata width with the plain branch name taking the remaining inline space, and the action group always sits below metadata as a full-width three-column row.
- Touch/hover differences: hover is enhancement only; core state is visible without hover.

## Interaction states
- Loading: screen-reader live status reports refresh state without adding a visible top-line chip.
- Empty: concise empty message with setup hint.
- Error: root-scoped error row with red accent; operation failures such as refresh/action/preference errors also render a visible alert row while routine Ready/Updated statuses stay screen-reader-only.
- Success: routine `Updated` / `Action complete` messages are not shown as a visible top-line chip; they remain available to assistive tech.
- Disabled: disabled action has muted text and no press transform.
- Theme selection: Settings is the only visible theme switch surface. Selection applies to every view immediately and persists through the existing preference store. Unsupported and legacy theme values migrate to Claude Code.
- Offline/slow network: not applicable; CLI/local filesystem driven.

## Content voice
- Tone: terse, operational, developer-native.
- Terminology: task, stage, status, project, repo, branch, dirty.
- Microcopy rules: prefer short row action labels (`IDE`, `Terminal`, `Finder`) over sentences; omit `Copy`/`Memo`/`Noti`/`Clear` row vocabulary because those companion actions are removed, not hidden.

## Implementation constraints
- Framework/styling system: React 18 + plain CSS. Adapt the structure and accessibility behavior of the Brainless Claude and Codex components into local reusable primitives. Do not add Tailwind, shadcn, or a new runtime package.
- Design-token constraints: CSS custom properties remain in the existing theme/base files; `style.css` is the import manifest.
- Performance constraints: no extra runtime package; no animation loops; preserve 0033 responsiveness fixes.
- Compatibility constraints: the CLI brief template changes, but schema v1 wire contract and Rust ports remain unchanged; `memoTitle` stays required on the v1 wire only.
- Scope constraints: do not add keyboard shortcuts or display shortcut hints for behavior that does not exist.
- Test/screenshot expectations: cover preference migration, persistence, both theme variants, the 460px native window boundary, and the Main/Activity/Settings shell contracts with Vitest. Run typecheck, lint, Vite build, Tauri build, then inspect both themes on all three tabs at 460px before final handoff.

## Open questions
- [ ] Whether a later release should restore a light appearance as a separate axis after the two fixed-dark agent themes ship.


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
- 2026-07-20: Replaced the Companion `Light | Dark | System` direction with two fixed-dark agent themes: Claude Code and Codex. Both themes apply to Main, Activity, and Settings and change component anatomy as well as tokens. The app uses an Agent Shell with terminal tabs and local React/plain-CSS primitives adapted from the Brainless component semantics. Claude Code is the default and migration target. Existing behavior and Tauri/Rust contracts remain unchanged.
- 2026-07-23: Removed the visible `Claude Code` legend from the expanded Main header so neither theme displays an agent product name as a banner label. The Settings theme-picker labels remain unchanged.
- 2026-07-23 (tab stability): Main, Activity, and Settings now share the same expanded `AgentHeader` anatomy and size. The compact secondary-view bar was removed so tab changes preserve a stable top-banner footprint.
- 2026-07-23 (floating navigation): Moved `AgentTabs` from below the header to an inset floating bottom bar while preserving the terminal theme. Expanded tasks now use selected-row background emphasis and progress is shown in a compact pill.
- 2026-07-23 (selected Task tone): Reduced the expanded Task summary from the broad `--emphasis-soft` fill to a theme-owned low-opacity surface tint with a narrow `2px` inline-start accent. The selected state remains visible through the boundary, prompt marker, border, and progress pill without creating a wide saturated band.
- 2026-07-23 (Claude accent restraint): Replaced Claude's orange structural borders and broad selected/current fills with Codex-like graphite borders and cool neutral translucent surfaces. Claude orange remains only on compact identity, focus, prompt, and active-state signals.
- 2026-07-23 (header inventory): Limited both theme headers to `projects · tasks`, removed Codex-only model/directory metadata, and aligned the Claude/Codex banner footprint.
- 2026-07-23 (text-only header): Removed the Workbranch mark and Claude/Codex prompt prefixes from the top banner. Both themes now share the exact `Workbranch Companion` plus `projects · tasks` text structure and header geometry.
- 2026-07-23 (Settings anatomy): Standardized Startup, Font, and Theme sections on the Claude Code `fieldset`/`legend` structure in both themes while preserving each theme's color tokens and selected state.
- 2026-07-24 (theme vibrancy and typography): Superseded the 2026-07-23 Claude accent-restraint direction after the neutral shell read as too drab. Claude structure now uses warm terracotta-tinted surfaces and lines, Codex uses brighter cool-neutral surfaces, muted text is brighter in both themes, status labels carry state colors, and the fixed-dark type scale increases by one pixel with native font smoothing.
- 2026-07-24 (native width and repository identity): Set 460px as both the initial and minimum native window width. Repository and branch identities no longer share one chip: the repository is plain text, only the branch name is a chip, dirty state stays with the repository, and no literal `|` separator is rendered.
- 2026-07-24 (Claude background restraint): User review found the terracotta structure visually excessive. Claude keeps its orange identity for compact accents, while broad surfaces, borders, selected summaries, and current-step fills move to low-saturation warm graphite and neutral translucent tones. Codex tokens remain unchanged.
- 2026-08-16 (stage-first Main): Replaced expanded current-step/checklist task details with a fixed three-column `PLAN | EXECUTION | REVIEW` StageBoard above compact project-grouped TaskMetaRows. `todo`/`planning` map to Plan, `in-progress`/`blocked` map to Execution, and `review` maps to Review; `blocked` is an execution-only pause that returns to `in-progress`. Done tasks stay out of the board but remain in metadata rows. Notification `+N` appears only on StageCards. Schema v1 keeps `memoTitle` for wire compatibility while Companion domain state no longer preserves it.
- 2026-08-16 (stage-frame and metadata scan): Made StageBoard the dominant Main surface through one strong outer frame and theme emphasis rail while keeping its three internal columns compact. TaskMetaRow repository metadata now uses the full row width, with IDE/Terminal/Finder moved to a separate full-width equal-third row below it so branch and dirty information cannot be squeezed by actions.
- 2026-08-16 (branch de-boxing): Removed the branch chip border, radius, and padding. Branch names remain muted, full-width, and ellipsized beside the repository identity, but render as plain text so the StageBoard, TaskMetaRow, and tool group are the only structural boxes in the Main hierarchy.
- 2026-08-16 (full worktree identity): Replaced StageCard's single-line task ellipsis with unrestricted natural wrapping. Worktree names often share a long prefix, so preserving the full distinguishing suffix takes priority over uniform card height; the lower TaskMetaRow keeps its compact single-line behavior.
