# Design

## Source of truth
- Status: Active
- Last refreshed: 2026-10-05
- Primary product surfaces: Workbranch Companion macOS menu bar popover.
- Evidence reviewed:
  - `docs/plans/0032-companion-tauri-react-rewrite.md`
  - `docs/plans/0033-companion-responsiveness-nonblocking-commands-and-watch-scope.md`
  - `docs/plans/0037-companion-settings-cli-theme.md`
  - `docs/plans/0039-companion-action-icons-top-and-theme-lineup.md`
  - `docs/plans/0054-companion-worktree-status-and-all-repositories.md`
  - `apps/companion/src/App.tsx`
  - `apps/companion/src/ui/StageBoard.tsx`
  - `apps/companion/src/ui/TaskRow.tsx`
  - `apps/companion/src/style.css`
  - `https://brainless.swerdlow.dev/components`
  - Brainless `claude-header`, `claude-message`, `codex-header`, and `codex-message` registry sources reviewed on 2026-07-20

## Brand
- Personality: fast, focused, terminal-native, command-line HUD.
- Trust signals: fast refresh, observed agent state and freshness, visible repo dirty/branch state, fixed-width readability, restrained terminal accents.
- Avoid: marketing hero layouts, oversized cards, large SaaS rows, generic dashboard cards, decorative animation, glossy neon chrome, soft-elevation card stacks, and mixed UI typography that weakens the terminal identity.

## Product goals
- Goals:
  - Show each workspace once with waiting, running, turn-ended and unknown session counts.
  - Make intervention needs and the latest tool activity scannable without opening session details.
  - Keep repo branch/dirty state available as supporting details.
  - Keep actions discoverable but visually secondary.
  - Let the user choose a Claude Code or Codex CLI experience that applies to Main, Usage, and Settings.
  - Show how much of each agent's plan limits is used and how many tokens each agent burned, without signing in anywhere.
- Non-goals:
  - Task lifecycle mutation UI.
  - New UI dependency stack.
  - OAuth, API keys, Keychain or network reads for usage; Companion reads only files the agents already write, so limits can lag and must say so.
- Success signals:
  - A user can identify active/blocked work in under three seconds.
  - A user can identify which workspace needs attention without expanding it.
  - A user can expand a workspace to inspect its sessions and repository facts.
  - The popover remains readable at its 460px native minimum width.

## Personas and jobs
- Primary personas: developers using `workbranch` task workspaces and AI agents.
- User jobs:
  - Check what is currently in progress.
  - See which repo/branch is dirty.
  - Open task in IDE/terminal/Finder.
  - Find the workspace requiring a response and inspect the matching session.
- Key contexts of use: quick menu bar glance while coding, before switching tasks, during AI-agent execution.

## Information architecture
- Primary navigation: an inset floating terminal tab bar anchored to the viewport bottom with three destinations: Main, Usage, Settings.
- Core screens: Main runtime-grouped workspace view, Usage detail view, Settings preferences view.
- Content hierarchy:
  1. Compact global inventory (`projects · tasks`) and two icon-only controls: update check and quit. Opening the window from the tray refreshes everything, so there is no manual refresh control.
  2. Active view content.
  3. Main view: a Claude | Codex usage summary (limits plus 14-day tokens), runtime session counts, a `내 응답 대기 | 실행 중 | 턴 종료 · 검토` kanban board, then a `WORKSPACES` inventory for session-less, unknown and inactive tasks. Every card shows IDE/Terminal/Finder launchers and repo/branch Git facts without expanding; expanding adds last commits and session request/activity/response excerpts. Base repositories remain in a supporting disclosure.
  4. Usage view: per-agent limits and today's token mix, one daily chart with both agents on a shared scale, and a last-7-days table.
  5. Settings view: launch-at-login, menu bar display, font, text size, and agent theme.
  6. Screen-reader live status in the agent shell; routine `Updated`/`Ready` text stays out of the visible header.

## Design principles
- Principle 1: Status is a launcher signal, not a paragraph. Use compact dots, counts, and labels.
- Principle 2: Observed status and its evidence stay together. Never imply a completed task from a finished agent turn.
- Principle 3: Developer metadata should be monospace and subdued until dirty/blocked.
- Tradeoffs: density is preferred over spaciousness, but tap/click targets remain at least 32px high where practical.

## Visual language
- Color: Settings exposes two fixed-dark agent themes. Claude Code uses low-saturation warm-graphite surfaces and neutral warm-gray borders; `#cd694a` remains the identity anchor but is reserved for compact prompt, focus, and active-state signals rather than broad backgrounds. Stage cards use existing neutral surfaces while blocked, review, done, and notification semantics use their existing tokens. `#c0caf5` remains primary terminal text and `#9aa5ce` is the brighter muted text. Codex uses brighter cool-neutral surfaces and borders, `#ededed` for primary text, `#a8a8ad` for muted text, and `#5cc2e0` only for command-like actions and links. Existing Companion, Light, Dark, System, and legacy family values migrate to Claude Code.
- Typography: the agent shell, navigation, content panels, form controls, task metadata, and activity labels use the user-selected monospace stack. The fixed-dark type scale is raised by one pixel with no production size below `10px`, except that the narrow-width agent header remains `13px`; explicit WebKit antialias smoothing is removed so native rendering controls glyph weight. Weight, contrast, spacing, and rules create hierarchy instead of a sans/mono split.
- Spacing/layout rhythm: compact terminal rhythm, 8px grid, row-first grouping, prompt markers, and thin rules. Main, Usage, and Settings use the same expanded agent header so switching tabs does not shift the content vertically.
- Shape/radius/elevation: 6px agent headers, 8px runtime task corners, 6px session panels, neutral tonal separation and thin borders. No card lift or decorative gradient.
- Motion: 120ms press/reveal feedback, plus a spinner on the button of a running action; respect reduced motion.
- Imagery/iconography: compact state dots with text labels. Use existing IDE/Terminal/Finder icons on the first line of every runtime card; no decorative illustrations or task-complete checkmarks.

## Components
- Existing components to reuse: action buttons, `TerminalPanel`, `PromptLine`, `StatusToken`, `ProviderIcon`, and settings preference controls.
- New/changed components:
  - shared `AgentShell` that applies `claude` or `codex` to all views,
  - shared expanded `AgentHeader` for Main, Usage, and Settings with one theme-neutral text anatomy,
  - update control before quit: a text `↓` inside a 1.5px circular border (`arrow.down.circle`, download the new version) so it pairs with the outline `⏻`; after a check finds an installed package outdated it turns `--notify` with a 6px dot and its label becomes `Updates available`,
  - `UpdatePanel` below the header (opened by the update control, closed explicitly): CLI and Companion rows with installed/latest versions, the running Companion version, one update action whose label names the restart, and the shared connection log disclosure,
  - `AgentTabs` as an inset floating bottom terminal navigation,
  - shared `TerminalPanel`, `PromptLine`, and `StatusToken` primitives,
  - compact global inventory summary limited to project and task counts,
  - `StageBoard` renders runtime state as kanban columns: waiting (`내 응답 대기`), running (`실행 중`) and finished (`턴 종료 · 검토`). Unknown/session-less and inactive tasks move to the `WORKSPACES` inventory below the board. Cards remount when they change columns, so expanded keys and the open note draft live in `StageBoard` state and survive column moves,
  - top toolbar with icon-only update/quit controls and screen-reader-only live status,
  - Settings view preferences panel,
  - Settings preference sections always use the Claude Code `fieldset`/`legend` anatomy in both themes; the selected theme still owns colors and control state,
  - Usage detail view,
  - switch row for launch-at-login,
  - font select row,
  - agent theme segmented control (`Claude Code`, `Codex`) with Claude Code as the default and migration target,
  - `RuntimeCard` (variants `card` and `row`) puts the project name (ellipsized) beside the icon-only launcher group on line one, then the task name on its own full-width line, the latest request, a state line (pill for the lead state such as `권한 승인 대기`, `실행 중`, `턴 종료`, `중단됨`/`오류로 종료`; plain faint `+N <state>` / `관측 불명 N` text for other sessions; one provider icon per distinct provider, lead session first, and the observation age pushed to the right), and one excerpt line (tool activity, or the last response on review cards). The repo block names a shared branch once with a branch icon, then one row per repo with name, compact facts and the note button; repos on different branches show their branch under their own row. The disclosure adds last commits and per-session details. Single click toggles the disclosure; double-click opens the IDE for repo-bearing tasks; the card carries no hover tooltip,
  - `StageRepoRow` containing repo/branch identity, compact Git facts (`●N` dirty files, `↑N`, `↓N`, and `CLEAN` only when none apply, with the full `DIRTY N FILES · BEHIND N` text in title/aria-label); in cards, repo names wrap at hyphens instead of truncating, last-commit relative time when expanded, and an inline note editor persisted in `companion-notes.json` by `repo:branch` key.
  - `BaseRepoRow` inside `StageBoard`, showing base branch, dirty and cached origin/base-branch differences. Quiet dots identify clean rows; notify/blocked tokens identify warning/problem rows. PULL/PUSH/CHECK pills are non-interactive guidance, not execution controls. Dirty + behind is warn/CHECK until clean, then PULL; ahead-only is PUSH, dirty-only has no pill. Missing, mismatch, divergence, missing remote and inspection errors use CHECK. Inspection errors show UNAVAILABLE with a safe reason, never sentinel CLEAN/0 facts, and do not hide healthy sibling repositories or tasks.
  - `UsageSummary` above the stage board: always two columns, one per agent (`ProviderIcon`, name, plan such as `max 20x`, and `Nh 전 관측`) with compact limit rows (`label | bar | % | remaining · Day HH:MM`; under 560px the reset text drops below the bar) and a `today · 7d` foot. A 5h row appears only when the agent reports a 5h window (Claude today); a window whose reset passed reads 0%, a never-started one reads `미시작`. Below the columns, a `DAILY TOKENS · 7d` chart pairs both agents per day for the last seven days ending today: each day is a tinted slot (weekends darker, today outlined) over a two-line axis of day number (with the month on the first day and on the 1st) and Korean weekday initial, and each day lists both agents' totals in their colors. A `Usage 탭에서 자세히 ›` link opens the Usage view. It is the first block in Main, above the setup onboarding panel, and absent until the first snapshot loads.
  - `UsageView`: the same columns with detail limit rows (large %, full-width bar) and a TODAY block (total, `in · out`, `cache r · w`, 7d; `오늘 사용 없음 · 어제 N` when idle), a `DAILY TOKENS · 14d` chart pairing both agents per day on one scale, a `LAST 7 DAYS` table, and a footnote that only local files are read.
- Variants and states: running/waiting/finished/idle with independent observed/uncertain/stale confidence. Unknown or unobserved workspaces remain visible.
- Shared header anatomy: Claude Code and Codex use the same text-only title block: `Workbranch Companion` above `projects · tasks`. The top banner contains no Workbranch mark, product icon, or Claude/Codex prompt prefix; theme identity comes from surrounding color tokens rather than different header geometry. Task metadata rows may retain their theme-specific prompt and action accents.
- Token/component ownership: `style.css` is the CSS import manifest; `src/styles/base.css`, `themes.css`, `chrome.css`, `stage-board.css`, `limit-gauge.css`, `task-details.css`, `task-actions.css`, `status-groups.css`, `settings.css`, and `motion.css` own CSS custom properties and component classes by surface.

## Accessibility
- Target standard: keyboard-operable popover controls and readable contrast.
- Keyboard/focus behavior: native task disclosure and launch controls are keyboard operable. Group changes preserve task component identity and editing state.
- Contrast/readability: stage headers, task status text, repository metadata, and note states must pass practical dark-mode contrast; disabled action may be muted but legible.
- Screen-reader semantics: runtime sections have labelled headings; native disclosure buttons expose aria-expanded, launcher controls expose aria-label/title/disabled, and status text conveys meaning independently of color.
- Reduced motion and sensory considerations: disable transform transitions under `prefers-reduced-motion: reduce`.

## Responsive behavior
- Supported breakpoints/devices: the native menu popover opens at 860×760, remains resizable, and cannot resize below 460px wide.
- Layout adaptations: the shared expanded header keeps its internal columns consistent on every tab. The runtime board is an inline-size container: at 720px of board width and above, the three kanban columns sit side by side and the `WORKSPACES` inventory uses two columns; below that, the same columns stack as lanes in the same order. Task actions stay compact on the task line where space allows and wrap without horizontal overflow at 460px. Repo/fact/commit/note rows use `min-width: 0`; long task, repo, branch, note, and last-commit strings ellipsize with complete values in `title`/accessibility data.
- Base row facts use a bounded flexible grid track with ellipsis and complete title/aria text. At 480px and below, facts move to a bounded second line; state dots and action pills remain visible. Validate internal row clipping, not just document overflow, including long branch names and the largest font setting.
- Touch/hover differences: hover is enhancement only; single click toggles task session details. Explicit launcher buttons invoke configured tools.

## Interaction states
- Loading: screen-reader live status reports refresh state without adding a visible top-line chip.
- Empty: concise empty message with setup hint.
- Error: root-scoped error rows preserve partial-global-read details while successfully loaded stage groups remain visible. Operation failures such as refresh/action/preference/note errors also render a visible alert row while routine Ready/Updated statuses stay screen-reader-only.
- Success: routine `Updated` / `Action complete` messages are not shown as a visible top-line chip; they remain available to assistive tech.
- Disabled: every disabled button has muted text (`--faint`, 0.55 opacity) and no press transform, so an unavailable action never looks clickable.
- Pending: a long-running action (CLI install/update/repair, agent connect/disconnect, update check/apply, runtime migration) keeps its own button with `aria-busy`, a small ring spinner and a `… 중…` label at full text color while sibling actions wait muted. Reduced motion stops the spinner; the label still reports progress.
- Runtime card selection: pointer single click or native activation selects the task in place and toggles its details. Pointer double-click opens the configured IDE target only for repo-bearing tasks and leaves the disclosure as it was; keyboard users use the IDE launcher button. Repo-less tasks expose `NO REPOSITORIES`, disabled IDE, and enabled Terminal/Finder actions. Selection no longer synchronizes to a second surface or calls `scrollIntoView`.
- Repo note editing: each repo/branch exposes one edit button. Opening autofocuses the textarea; command/control-enter saves, Escape cancels and restores the prior value, blur saves, and saving blank text removes the key. Notes persist in `companion-notes.json` under `repo:branch` and survive task/worktree removal.
- Usage freshness: the snapshot reloads every 60 seconds and whenever the window opens. Each agent shows its limits' observation age; a 5h reading older than one hour or a weekly reading older than six hours is stale: its bar and percentage dim and the age turns `--notify`. Read failures keep the last good snapshot on screen with the error below it. Token totals include cache reads (ccusage-compatible) and the detail view breaks out input, output, cache read and cache write.
- Theme selection: Settings is the only visible theme switch surface. Selection applies to every view immediately and persists through the existing preference store. Unsupported and legacy theme values migrate to Claude Code.
- Offline/slow network: not applicable; CLI/local filesystem driven.

## Content voice
- Tone: terse, operational, developer-native.
- Terminology: task, stage, status, project, repo, branch, dirty.
- Microcopy rules: task actions use icon-only IDE/Terminal/Finder controls with accessible names and tooltips rather than visible text. Omit `Copy`/`Memo`/`Noti`/`Clear` row vocabulary because those companion actions are removed, not hidden.

## Implementation constraints
- Framework/styling system: React 18 + plain CSS. Adapt the structure and accessibility behavior of the Brainless Claude and Codex components into local reusable primitives. Do not add Tailwind, shadcn, or a new runtime package.
- Design-token constraints: CSS custom properties remain in the existing theme/base files; `style.css` is the import manifest.
- Performance constraints: no extra runtime package; no animation loops; preserve 0033 responsiveness fixes.
- Compatibility constraints: schema v1 adds optional project-level `baseRepos`; each present base repo has ten required fields including nullable `inspectionError`. Missing `baseRepos` from older CLI output maps to an empty group. Tauri command shape and Rust ports remain unchanged; Companion delegates configured IDE/path behavior to the existing task-level launcher commands. Status reads never fetch; pills reflect cached remote-tracking refs rather than guaranteeing the next Git command can execute.
- Layout constraints: the usage summary and Usage view are `usage` size containers; their agent columns sit side by side from 720px (matching the runtime board's three-column breakpoint) and stack below it, so the 460px minimum still reads one agent per row.
- Scope constraints: do not add keyboard shortcuts or display shortcut hints for behavior that does not exist.
- Test/screenshot expectations: cover both theme variants, the 860px primary and 460px minimum boundaries, lifecycle-ordered stage groups, current work, repo facts, note edit/save/cancel/delete, task selection/actions, usage summary/detail states, and Main/Usage/Settings shell contracts with Vitest. Run typecheck, lint, Vite build, Tauri build, then inspect both themes at both widths before final handoff.

## Open questions
- [ ] Whether a later release should restore a light appearance as a separate axis after the two fixed-dark agent themes ship.



## Direction revision
- 2026-10-05 (runtime kanban, 0061): Main renders hook runtime state as `내 응답 대기 | 실행 중 | 턴 종료 · 검토` kanban columns (BITL-style waiting/running/needs-review) in an 860px default window, stacking as lanes below 720px of board width. IDE/Terminal/Finder launchers and repo/branch facts move from the disclosure to every card's always-visible area because task-level IDE launch is a primary job. Session-less, unknown and inactive tasks stay launchable in a `WORKSPACES` inventory. Supersedes 0060's single-column, launchers-in-details placement.
- 2026-10-05: Hook-driven runtime groups replace manual brief/stage reporting; see 0060.

- 2026-09-07 (base repo status group): Added compact `00 BASE` above PLAN using the existing stage header and theme tokens. Repo-local inspection errors remain visible without hiding healthy data. Dirty + behind advises CHECK before PULL. Full facts remain accessible while bounded grid tracks prevent silent clipping at 520px/460px.
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
- 2026-08-17 (shared stage-role header and plan-level cards): Replaced the three independent column headers with one shared two-row StageBoard header. Stage names occupy the first row; `AI·ME | AI | ME` roles and faint per-stage counts occupy the second. PLAN now contains planning tasks only, while todo remains available in TaskMetaRow. StageCards add the active Plan title plus compact repository names and dirty cues, with long repository names ellipsized at the 460px minimum width.
- 2026-08-18 (StageCard IDE launcher): Made each active StageCard an IDE-launch entry point without adding visible card chrome. Pointer double-click reuses the existing IDE task action, while the overlay native button's device-independent click preserves Enter, Space, voice, switch, and accessibility API activation; pointer single-click remains inert.
- 2026-08-20 (repo activity grouped feed): Replaced the narrow three-column StageBoard with full-width vertical PLAN/EXECUTION/REVIEW task-feed sections. Todo/done with `dirty` or `ahead > 0` derive into EXECUTION; clean todo/done remain in `OTHER N`. Each task row shows a two-line repo/branch activity stack with explicit `last commit` context, preserving the native IDE-launch overlay and 460px minimum-width contract.
- 2026-08-20 (per-task inset lifecycle): Runtime feedback showed that separate PLAN/EXECUTION/REVIEW sections did not explain where an individual task sat in the whole workflow, while a bare stepper still read like ordinary task metadata. After two HTML comparison rounds, the final choice is option B: a bordered inset Stage panel containing a `STAGE · <CURRENT>` header and connected three-node stepper on every task. Repo activity remains outside and full-width below the panel; clean todo/done remain in `OTHER N`.
- 2026-08-24 (worktree matrix + all repositories): Replaced the per-task inset lifecycle/detail selection with a two-level Main surface. The top `WORKTREE STATUS` matrix uses `PLAN | EXECUTION | REVIEW` ownership (`AI/Human | AI | Human`) to locate every active task; the lower `ALL REPOSITORIES` queue shows every repo belonging to those same active tasks and never filters siblings on selection. Matrix selection only highlights and scrolls to the matching task card. Queue priority is review, blocked, execution, then plan; clean todo/done are excluded, while dirty/ahead todo/done derive into execution. Task actions reuse configured CLI launchers. The native window opens at 720×760, remains resizable, and preserves a 460px compact fallback.
- 2026-08-26 (repo-less navigator completion): Kept every active matrix task in the lower queue, including tasks with zero repositories. Repo-less cards render `NO REPOSITORIES`, preserve selection/highlight/nearest-scroll, disable IDE and matrix IDE shortcuts, and keep task-root Terminal/Finder actions enabled.
- 2026-08-26 (partial global inventory): Kept successfully loaded task/repository rows visible when one or more configured roots fail, while marking the queue heading `INCOMPLETE — N ROOT(S) UNAVAILABLE`. Missing repository counts are never inferred, and existing root-scoped error details remain visible.
- 2026-08-26 (stage-grouped main + repo/branch notes): Replaced the 3-column matrix and separate repository queue with one vertical `01 PLAN → 02 EXECUTION → 03 REVIEW` surface. Each active task appears once with current work, repo/branch Git facts, actions, and frontend-owned inline repo notes stored in `companion-notes.json` by `repo:branch`. The native window opens at 520×760 with a 460px minimum.
- 2026-08-31 (idle inventory + brief summary): Replaced the aggregate `IDLE N` footer with an always-visible compact IDLE section for every successfully loaded clean todo/done task, preserving repo-bearing IDE and task-root Terminal/Finder actions while disabling IDE for repo-less tasks. Repo commit lines use a git-commit icon plus subject/relative time with tooltip and accessible context. Current work resolves as checklist item, then the one-line brief summary parsed from directly below `status:`, then a distinct Plan title. Newly generated task guidance requires agents to maintain that summary; existing workspaces are not migrated.
- 2026-09-22 (weekly limit gauge): Added an optional `WEEKLY LIMITS` panel between the agent header and the worktree status board plus a Settings section for weekly-limit accounts. Users record each coding-agent account's next reset from `/usage` as a `datetime-local` anchor stored in `companion-limits.json`; the gauge draws every account's current seven-day window on a shared `now − 7d … now + 7d` axis with a fixed centre now line, remaining time, reset weekday/time, and FRESH/SOON pills. Alternatives rejected in review: a per-account ruler with a moving needle, a today-centred calendar-column axis, and weekday+time input. The gauge is time-based only and never reads actual usage.

- 2026-10-05 (update check): Added a header update control and an `UpdatePanel` that reuses the connection-step anatomy. The check is click-only because it runs `brew update`; the dot appears only after a check found an installed, outdated package. The single update button upgrades the CLI before the Companion and says `업데이트 후 재시작` whenever the Companion will restart.
- 2026-10-05 (two-icon header): Removed the `↻` refresh control; fs watches, the 1s runtime poll and the 5-minute heartbeat already cover routine changes, and the window now refreshes everything when the tray opens it, which also covers newly registered projects and retry after errors. The header keeps `update | quit`. The update icon became a CSS-ringed `↓` after `↥`/`⤒` read too small, filled `⬆︎` outweighed `⏻`, and `⭱`/`⮉` depended on non-system fonts. `↓` reads as downloading the new version, like the `↓N` behind fact; `↻` was rejected because it meant refresh-tasks until now, while this control runs a slow, networked `brew update`.
- 2026-10-06 (setup progress): Setup and update buttons now show their own running state (spinner plus `연결 중…`-style label) because the only progress line sat at the bottom of a long panel and scrolled out of view, so clicks looked ignored. Disabled buttons became visibly muted after a missing-agent `연결` looked enabled yet did nothing. An action's result moved beside its button for the same reason. Agent lookup also reads the login shell PATH: a Finder launch had reported a version-manager-installed Codex as `Agent 미설치`.
- 2026-10-07 (local usage): Replaced the brief-fed Activity calendar and the manual, time-only `WEEKLY LIMITS` gauge. Main now opens with a Claude | Codex usage summary (limits plus 14-day token bars) and the third tab became Usage (per-agent detail, shared daily chart, 7-day table). Data comes only from the agents' local files — Claude transcripts and its cached `/usage` in `~/.claude.json`, Codex rollouts — so nothing asks for OAuth or Keychain access; the cost is freshness, which every limit row states. HTML comparison rounds chose the side-by-side Usage B layout and the chart-below-limits Main summary; Codex shows no 5h row because its plan reports none.
- 2026-10-07 (menu bar icon and usage title): The tray icon became an outline of the app icon's ghost (`icons/tray-template.svg`, shipped as the 36px template so it stays sharp on Retina). Settings › Menu Bar composes the text beside it: toggles for Claude 5h, Claude weekly, Codex weekly and today's tokens, each with a one-line description, plus a Used % | Remaining % switch, under a menu bar preview drawn in the system font with sample numbers. The result reads `CL 42·63  CO 18 · 31.0M`: `CL`/`CO` name the agent because a template title is plain text with no colour, an agent's windows join with `·` in 5h → weekly order, and turning every item off leaves the icon alone. A Rust thread recomputes it every minute from the same local usage files and parse cache as the Usage view, so it stays current while the window is hidden; a reading past its stale window shows `–` and an agent with no reading is left out. Earlier rounds tried four fixed presets (highest limit, per-agent highest, limit + tokens) in a dropdown and then as preview cards; review replaced them because which limits matter, and whether remaining or used reads better, differs per person. The HTML comparison also covered gauges drawn inside the ghost; plain text won because it reads exactly and needs no per-tick icon rendering.

## Agent runtime surface (0060)

The Main surface uses runtime groups: waiting for you, running, turn ended, unknown, and inactive. A task appears once and shows session counts; expanding it shows provider-specific request/activity/response excerpts with observation time. Unknown/stale observations never masquerade as idle or confirmed running. Turn ended is not task completion.

Compact priority groups show request-first titles, provider/repository identity and current tool activity. Existing monospace size tokens, Claude/Codex themes and 460px minimum width remain. Neutral surfaces and small rounded corners separate groups; warm attention, green execution and amber turn-end dots carry semantic accents. Entire cards are not recolored by state. Task disclosure, focus and selection survive runtime refreshes; command strings are displayed as text. No remote allow/deny controls are introduced.

Git facts, base repositories, repo notes and launchers remain supporting details. Runtime reads have their own coalesced polling path and never trigger a Git refresh. Migration discovery renders the CLI dry-run result and its action invokes the same CLI apply path, reporting errors and retry state. Legacy agent sessions must restart to reload guidance after migration.


## Runtime kanban (0061)

Columns come straight from the existing runtime roles; no plan/execution phase is inferred. A task appears once, in the column of its representative role (waiting > running > finished), and other observed sessions surface as `+N <state>` chips. Stale or uncertain observations never enter a live column: they stay in `WORKSPACES` tagged `관측 불명`, beside `세션 없음` and `비활성`. Card borders take a faint tint of the lead session's provider (`--provider-claude-line` orange, `--provider-codex-line` cyan, `--provider-grok-line` silver); waiting cards add an outer `--runtime-waiting-ring` instead of recolouring the border, so provider and attention read together. Inventory rows stay untinted. Review cards prefer the last response excerpt over the last tool activity. Runtime state colours are theme tokens (`--runtime-waiting`, `--runtime-running`, `--runtime-finished`, `--runtime-unknown` and their soft fills) shared by both themes. Providers render as a 14px `ProviderIcon` instead of names: simplified marks (Claude spark, Codex hexagon, Grok slashed ring) coloured with the matching `--provider-claude`, `--provider-codex` and `--provider-grok` tokens, each with a `title` and `role="img"` accessible name (`Claude Code`, `Codex`, `Grok Build`). They are not brand artwork.

## Onboarding and Settings connections

The first-run connection panel and Settings share the same two steps: prepare Workbranch CLI/collector through Homebrew, then connect individual agents. Provider rows are Claude Code, Codex and Grok Build; missing agent executables disable connection and explain the prerequisite. Agent executables are looked up on the GUI-safe PATH and then on the PATH of the user's interactive login shell (`$SHELL -ilc`, resolved once per launch in its own session with a 10s deadline), because Finder and login-item launches inherit only launchd's sparse PATH and agents installed through version managers would otherwise read as missing. Installation progress is visible on the clicked button, with bounded detailed logs in a disclosure. The action's result (error or next step) appears inside the CLI step or agent row that ran it; status-check failures stay at the top of the panel. No package or hook configuration is changed merely by viewing the panel.

Configured, disabled, trust-required, first-event waiting and historical receipts are distinct. Only an event newer than the current connection verification baseline earns a receipt confirmation. A successful connect keeps its trust/first-event instructions visible instead of immediately dismissing onboarding. Existing terminal panel anatomy, font tokens, theme colors and 460px minimum width apply.
