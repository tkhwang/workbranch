# Companion Agent Shell Claude Code / Codex Themes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Use `superpowers:test-driven-development` for every behavior or markup contract change and `omo:visual-qa` for the final UI gate.

**Goal:** Replace the current Companion light/dark appearance system with two fixed-dark Claude Code and Codex themes, then apply a Brainless-inspired Agent Shell to Main, Activity, and Settings without changing task, calendar, action, or Tauri behavior.

**Architecture:** `CompanionPreferences` stores one `theme: "claude" | "codex"` value; old `themeFamily`, `themeMode`, and legacy concrete themes migrate to `claude`. `App` renders the same expanded theme-specific `AgentHeader` above Main, Activity, and Settings, view content built from shared `TerminalPanel`, `PromptLine`, and `StatusToken` primitives, and an inset floating-bottom `AgentTabs`. Claude and Codex share data flow and component interfaces but may render different semantic markup and markers; they are not palette-only variants.

**Tech Stack:** Tauri v2, React 18, TypeScript 5.9, Vite 7, Vitest 4, Biome 2, plain CSS. Do not add Tailwind, shadcn, Radix, Brainless packages, or another runtime dependency.

---

## Source of truth and fixed decisions

- Design contract: `DESIGN.md`, revision dated `2026-07-20`.
- Visual reference: [Brainless Components](https://brainless.swerdlow.dev/components), specifically `claude-header`, `claude-message`, `codex-header`, and `codex-message`.
- Theme choices are exactly `Claude Code` and `Codex`.
- Both themes are fixed dark. Remove the visible and internal `Light | Dark | System` mode axis.
- Claude Code is the default for new installs and the migration target for all unsupported or legacy theme settings.
- The theme picker appears only in Settings and persists through the existing Tauri preference store.
- Main, Activity, and Settings use the same expanded header so tab changes preserve the top-banner footprint.
- Navigation uses an inset floating bottom terminal tab bar with protected content padding.
- Expanded `details[open]` tasks receive selected-row background emphasis and progress uses a compact pill.
- Do not add keyboard shortcuts, a shortcut hint bar, or labels that imply shortcuts.
- Preserve `details/summary`, action callbacks, workspace refresh, activity reload/selection, launch-at-login, and IPC contracts.
- Do not modify `apps/cli/**`, `packages/contract/**`, Companion Rust commands, activity storage, or domain models.
- `docs/plans/0044-companion-agent-shell-claude-codex-themes.md` is an untracked conflicting draft and is not an input to this plan. Execute this `0045` plan only.

## File structure

### Create

- `apps/companion/src/ui/AgentHeader.tsx`: shared expanded header with distinct Claude and Codex anatomy.
- `apps/companion/src/ui/AgentTabs.tsx`: accessible floating bottom navigation for Main, Activity, and Settings.
- `apps/companion/src/ui/TerminalPanel.tsx`: Claude fieldset/legend and Codex ruled-section variants behind one interface.
- `apps/companion/src/ui/PromptLine.tsx`: theme-specific `❯` or `›` prompt row.
- `apps/companion/src/ui/StatusToken.tsx`: text-plus-marker state indicator for todo/planning/in-progress/review/blocked/done.
- `apps/companion/src/ui/AgentThemePicker.tsx`: Settings-only Claude Code/Codex segmented control.
- `apps/companion/src/styles/agent-shell.css`: shared Agent Header, Agent Bar, tabs, panel, prompt, and status primitive styles.
- `apps/companion/tests/agent-primitives.test.tsx`: static semantic contracts for the new primitives.

### Modify

- `apps/companion/src/application/themePreferences.ts`: fixed `claude | codex` theme model.
- `apps/companion/src/application/preferences.ts`: new store shape and legacy migration.
- `apps/companion/src/App.tsx`: Agent Shell composition and removal of system-mode resolution.
- `apps/companion/src/ui/ProjectGroup.tsx`: render project content through `TerminalPanel`.
- `apps/companion/src/ui/TaskRow.tsx`: `PromptLine`, `StatusToken`, flat metadata/actions, unchanged disclosure behavior.
- `apps/companion/src/ui/SettingsView.tsx`: pass the active theme into the settings shell surface.
- `apps/companion/src/ui/SettingsPanel.tsx`: replace mode buttons with `AgentThemePicker`.
- `apps/companion/src/style.css`: import the new `agent-shell.css` stylesheet.
- `apps/companion/src/styles/base.css`: fixed-dark base and monospace hierarchy.
- `apps/companion/src/styles/themes.css`: exact Claude and Codex token blocks.
- `apps/companion/src/styles/chrome.css`: shared expanded header and shell chrome.
- `apps/companion/src/styles/task-details.css`: prompt rows, panels, details, steps, metadata.
- `apps/companion/src/styles/task-actions.css`: flat text actions.
- `apps/companion/src/styles/status-groups.css`: terminal project and status hierarchy.
- `apps/companion/src/styles/settings.css`: terminal form controls and theme picker.
- `apps/companion/src/styles/motion.css`: reduced-motion coverage for new selectors.
- `apps/companion/src/activity/activity-calendar.css`: token-driven fixed-dark calendar surfaces.
- `apps/companion/tests/preferences.test.ts`: default, migration, persistence, and failure rollback.
- `apps/companion/tests/settings-panel.test.tsx`: two-theme picker contract.
- `apps/companion/tests/app-shell.test.tsx`: shared header/tabs/view composition and theme attributes.
- `apps/companion/tests/project-group.test.tsx`: theme-aware panel contract.
- `apps/companion/tests/task-row.test.tsx`: prompt and status primitive contracts.
- `apps/companion/tests/activity-calendar.test.tsx`: preserve layout fallbacks while checking theme-token usage.

### Remove after references reach zero

- `apps/companion/src/application/systemThemeMode.ts`.
- `apps/companion/src/ui/ViewNav.tsx`.
- `apps/companion/src/ui/AppSummary.tsx`.
- `apps/companion/src/ui/AppToolbar.tsx`.
- `apps/companion/src/ui/TaskActionIcon.tsx` if all three task actions become accessible text buttons.

Do not remove any file until `rg` proves that no production or test import remains.

---

### Task 1: Lock the fixed-theme preference contract

**Files:**
- Modify: `apps/companion/tests/preferences.test.ts`
- Modify: `apps/companion/src/application/themePreferences.ts`
- Modify: `apps/companion/src/application/preferences.ts`
- Remove after green: `apps/companion/src/application/systemThemeMode.ts`

- [x] **Step 1: Write failing tests for the new type and migration contract**

Add or replace assertions so the test file proves this exact public shape:

```ts
expect(COMPANION_THEME_OPTIONS).toEqual([
	{ value: "claude", label: "Claude Code" },
	{ value: "codex", label: "Codex" },
]);
expect(DEFAULT_COMPANION_PREFERENCES).toEqual({
	font: "system-mono",
	theme: "claude",
});
expect(
	sanitizeCompanionPreferences({
		font: "menlo",
		themeFamily: "companion",
		themeMode: "light",
	}),
).toEqual({
	preferences: { font: "menlo", theme: "claude" },
	sanitized: true,
});
expect(
	sanitizeCompanionPreferences({ font: "menlo", theme: "codex" }),
).toEqual({
	preferences: { font: "menlo", theme: "codex" },
	sanitized: false,
});
```

Also assert that `preferencesToStoreEntries()` returns only `{ font, theme }`, `writeCompanionPreferences()` writes only `font` and `theme`, and the failed-save rollback comparison uses those two fields.

- [x] **Step 2: Run the focused test and confirm RED**

Run:

```bash
pnpm --filter @workbranch/companion vitest run tests/preferences.test.ts
```

Expected: failures mention the missing `theme` property, old `themeFamily/themeMode` fields, and the old two concrete palette values.

- [x] **Step 3: Replace `themePreferences.ts` with the fixed two-theme model**

Implement this interface and remove mode/family/resolution exports:

```ts
const COMPANION_THEME_VALUES = ["claude", "codex"] as const;

export type CompanionTheme = (typeof COMPANION_THEME_VALUES)[number];

export type CompanionThemeOption = {
	readonly value: CompanionTheme;
	readonly label: string;
};

export const COMPANION_THEME_OPTIONS: readonly CompanionThemeOption[] = [
	{ value: "claude", label: "Claude Code" },
	{ value: "codex", label: "Codex" },
];

const COMPANION_THEME_SET = new Set<unknown>(COMPANION_THEME_VALUES);

export function isCompanionTheme(value: unknown): value is CompanionTheme {
	return COMPANION_THEME_SET.has(value);
}
```

- [x] **Step 4: Simplify `CompanionPreferences` and migrate old values**

Use the new stored shape:

```ts
export type CompanionPreferences = {
	readonly font: CompanionFont;
	readonly theme: CompanionTheme;
};

export const DEFAULT_COMPANION_PREFERENCES: CompanionPreferences = {
	font: "system-mono",
	theme: "claude",
};

export function sanitizeCompanionPreferences(input: {
	readonly font?: unknown;
	readonly theme?: unknown;
	readonly themeFamily?: unknown;
	readonly themeMode?: unknown;
}): PreferenceSanitizationResult {
	const font = isCompanionFont(input.font)
		? input.font
		: DEFAULT_COMPANION_PREFERENCES.font;
	const theme = isCompanionTheme(input.theme)
		? input.theme
		: isCompanionTheme(input.themeFamily)
			? input.themeFamily
			: DEFAULT_COMPANION_PREFERENCES.theme;
	return {
		preferences: { font, theme },
		sanitized: font !== input.font || theme !== input.theme,
	};
}
```

`readCompanionPreferences()` must read `theme`, `themeFamily`, and `themeMode`; the latter two are migration inputs only. `writeCompanionPreferences()` must write `font` and `theme`. Do not attempt to delete old keys from the store because the current store abstraction has no delete contract and valid `theme` takes precedence on future reads.

- [x] **Step 5: Run focused tests and typecheck**

```bash
pnpm --filter @workbranch/companion vitest run tests/preferences.test.ts
pnpm --filter @workbranch/companion typecheck
```

Expected: preference tests pass; typecheck now reports only downstream consumers that still reference the removed mode/family fields.

Evidence (2026-07-20): `pnpm --filter @workbranch/companion exec vitest run tests/preferences.test.ts` passed 11/11. `typecheck` now reports only the planned downstream references in `App`, `SettingsPanel`, `SettingsView`, and `systemThemeMode.ts`; Tasks 4 and 6 remove them.

- [x] **Step 6: Remove system-mode code after downstream references are handled in Task 4**

After `rg -n "useSystemThemeMode|CompanionThemeMode|CompanionResolvedThemeMode" apps/companion/src apps/companion/tests` returns only the files being removed or updated, delete `apps/companion/src/application/systemThemeMode.ts`.

Evidence (2026-07-23): `systemThemeMode.ts` and every production reference were removed. Source-only residue checks for `useSystemThemeMode` and former light/system selectors returned no matches.

- [ ] **Step 7: Commit gate**

Only with explicit user authorization:

```bash
git add apps/companion/src/application apps/companion/tests/preferences.test.ts
git commit -m "refactor(companion): replace appearance modes with agent themes"
```

---

### Task 2: Define the Claude and Codex token contracts

**Files:**
- Modify: `apps/companion/tests/app-shell.test.tsx`
- Modify: `apps/companion/src/styles/themes.css`
- Modify: `apps/companion/src/styles/base.css`

- [x] **Step 1: Write failing CSS contract assertions**

Read `src/styles/themes.css` and assert exactly two theme selectors, no light selector, and the identity anchors:

```ts
expect(css).toContain('main[data-theme="claude"]');
expect(css).toContain('main[data-theme="codex"]');
expect(css).toContain("--accent: #cd694a");
expect(css).toContain("--emphasis: #cd694a");
expect(css).toContain("--text: #c0caf5");
expect(css).toContain("--accent: #5cc2e0");
expect(css).toContain("--emphasis: #ededed");
expect(css).toContain("--text: #ededed");
expect(css).not.toContain('data-theme$="-light"');
expect(css).not.toMatch(/gradient\(/);
```

- [x] **Step 2: Run the focused test and confirm RED**

```bash
pnpm --filter @workbranch/companion vitest run tests/app-shell.test.tsx
```

Expected: failures name `catppuccin-dark`, `breakfast-light`, light selectors, and gradients.

- [x] **Step 3: Replace theme blocks with complete fixed-dark tokens**

Define every existing semantic token in both blocks. Use these exact identity anchors and keep status colors readable:

```css
main[data-theme="claude"] {
	--surface-0: #0e0e0e;
	--surface-1: #131313;
	--surface-2: #1b1b1b;
	--surface-3: #252525;
	--line: rgba(205, 105, 74, 0.32);
	--line-strong: #cd694a;
	--text: #c0caf5;
	--muted: #949494;
	--faint: #626262;
	--accent: #cd694a;
	--accent-strong: #e08567;
	--accent-soft: rgba(205, 105, 74, 0.14);
	--emphasis: #cd694a;
	--emphasis-soft: rgba(205, 105, 74, 0.14);
	--blocked: #f7768e;
	--blocked-soft: rgba(247, 118, 142, 0.14);
	--review: #bb9af7;
	--review-soft: rgba(187, 154, 247, 0.14);
	--done: #87d787;
	--done-soft: rgba(135, 215, 135, 0.14);
	--notify: #e0af68;
	--notify-soft: rgba(224, 175, 104, 0.14);
	--button-bg: rgba(192, 202, 245, 0.06);
	--button-bg-hover: rgba(192, 202, 245, 0.12);
	--current-step-bg: var(--emphasis-soft);
	--cal-1: #cd694a;
	--cal-2: #7dcfff;
	--cal-3: #87d787;
	--cal-4: #e0af68;
	--cal-5: #bb9af7;
	--cal-6: #f7768e;
}

main[data-theme="codex"] {
	--surface-0: #0f0f0f;
	--surface-1: #141414;
	--surface-2: #1c1c1c;
	--surface-3: #262626;
	--line: #3a3a3a;
	--line-strong: #565656;
	--text: #ededed;
	--muted: #7a7a7a;
	--faint: #5d5d5d;
	--accent: #5cc2e0;
	--accent-strong: #8bdcf2;
	--accent-soft: rgba(92, 194, 224, 0.14);
	--emphasis: #ededed;
	--emphasis-soft: rgba(237, 237, 237, 0.1);
	--blocked: #f2a0a0;
	--blocked-soft: rgba(242, 160, 160, 0.14);
	--review: #bb9af7;
	--review-soft: rgba(187, 154, 247, 0.14);
	--done: #abdfa7;
	--done-soft: rgba(171, 223, 167, 0.14);
	--notify: #f6e2b7;
	--notify-soft: rgba(246, 226, 183, 0.14);
	--button-bg: rgba(237, 237, 237, 0.06);
	--button-bg-hover: rgba(237, 237, 237, 0.12);
	--current-step-bg: var(--emphasis-soft);
	--cal-1: #5cc2e0;
	--cal-2: #f6e2b7;
	--cal-3: #abdfa7;
	--cal-4: #a7a7a7;
	--cal-5: #f2a0a0;
	--cal-6: #bb9af7;
}
```

Preserve the font selectors at the bottom of `themes.css`. Remove `main::before`, `--shell-topline`, light-only shadow overrides, and all gradients.

- [x] **Step 4: Make Claude the fixed-dark base fallback**

In `base.css`, set `:root`, `body`, and the `main` fallback to the Claude values. Remove `body:has(main[data-theme$="-light"])`, `--ui-font-family`, shadow tokens, `--radius-shell`, and `--radius-row`. Set `main` to `background: var(--surface-0)` and `font-family: var(--app-font-family)`.

- [x] **Step 5: Run the focused test and CSS residue checks**

```bash
pnpm --filter @workbranch/companion vitest run tests/app-shell.test.tsx
rg -n 'catppuccin|breakfast|data-theme\$="-light"|gradient\(|shell-topline' apps/companion/src/styles apps/companion/src/activity
```

Expected: test passes; `rg` returns no production CSS matches.

Evidence (2026-07-20): the named fixed-theme CSS contract in `app-shell.test.tsx` passed and the production residue search returned no matches. The whole `app-shell.test.tsx` remains intentionally staged until Tasks 4 and 5 replace its obsolete App/bottom-nav/card assertions.

- [ ] **Step 6: Commit gate**

Only with explicit user authorization:

```bash
git add apps/companion/src/styles apps/companion/tests/app-shell.test.tsx
git commit -m "feat(companion): add claude and codex theme tokens"
```

---

### Task 3: Build the reusable Agent primitives

**Files:**
- Create: `apps/companion/src/ui/AgentHeader.tsx`
- Create: `apps/companion/src/ui/AgentTabs.tsx`
- Create: `apps/companion/src/ui/TerminalPanel.tsx`
- Create: `apps/companion/src/ui/PromptLine.tsx`
- Create: `apps/companion/src/ui/StatusToken.tsx`
- Create: `apps/companion/tests/agent-primitives.test.tsx`

- [x] **Step 1: Write failing semantic rendering tests**

Use `renderToStaticMarkup` to prove these contracts:

```tsx
const controls = {
	status: "Ready",
	onRefresh: () => {},
	onQuit: () => {},
};

expect(renderToStaticMarkup(<AgentHeader theme="claude" summary={summary} {...controls} />))
	.toContain("<fieldset");
expect(renderToStaticMarkup(<AgentHeader theme="claude" summary={summary} {...controls} />))
	.toContain("Claude Code");
expect(renderToStaticMarkup(<AgentHeader theme="codex" summary={summary} {...controls} />))
	.toContain("&gt;_ Workbranch Companion");
expect(renderToStaticMarkup(<PromptLine theme="claude">Current step</PromptLine>))
	.toContain("❯");
expect(renderToStaticMarkup(<PromptLine theme="codex">Current step</PromptLine>))
	.toContain("›");
```

For `AgentTabs`, assert three buttons, visible labels, `aria-current="page"` only on the active view, and no SVG. For `TerminalPanel`, assert Claude renders `fieldset/legend` and Codex renders `section` with a visible heading. For `StatusToken`, assert the text label remains visible instead of relying on color.

- [x] **Step 2: Run the focused test and confirm RED**

```bash
pnpm --filter @workbranch/companion vitest run tests/agent-primitives.test.tsx
```

Expected: module resolution fails for the six new primitive files.

- [x] **Step 3: Implement the exact primitive interfaces**

Use these exported props so later tasks do not invent parallel APIs:

```ts
export type AgentHeaderProps = {
	readonly theme: CompanionTheme;
	readonly summary: MenuSummary;
	readonly status: string;
	readonly onRefresh: () => void;
	readonly onQuit: () => void;
};

export type CompanionView = "main" | "activity" | "settings";

export type AgentTabsProps = {
	readonly currentView: CompanionView;
	readonly onViewChange: (view: CompanionView) => void;
};

export type TerminalPanelProps = {
	readonly theme: CompanionTheme;
	readonly label: string;
	readonly className?: string;
	readonly children: React.ReactNode;
};

export type PromptLineProps = {
	readonly theme: CompanionTheme;
	readonly current?: boolean;
	readonly children: React.ReactNode;
};

export type StatusTokenProps = {
	readonly status: PlanStatus;
};
```

Keep refresh and quit as real `<button>` elements with `aria-label`s. Use text glyphs `↻` and `⏻`; do not add an icon package. The Claude expanded header uses a semantic `fieldset` with the neutral accessible name `Workbranch Companion`, no visible agent product-name legend, a locally drawn pixel-style Workbranch SVG mark, and `❯`. The Codex header uses a bordered `section`, `>_ Workbranch Companion`, and model/directory-style metadata rows. Do not copy Claude or OpenAI logos.

- [x] **Step 4: Run primitive tests and typecheck**

```bash
pnpm --filter @workbranch/companion vitest run tests/agent-primitives.test.tsx
pnpm --filter @workbranch/companion typecheck
```

Expected: primitive tests pass; typecheck may still report old App/Settings imports until Tasks 4 and 6.

Evidence (2026-07-20): primitive tests passed 6/6 and targeted Biome passed after formatting. Typecheck reports only the staged App/Settings/system-mode references identified by the plan.

- [ ] **Step 5: Commit gate**

Only with explicit user authorization:

```bash
git add apps/companion/src/ui/Agent*.tsx apps/companion/src/ui/TerminalPanel.tsx apps/companion/src/ui/PromptLine.tsx apps/companion/src/ui/StatusToken.tsx apps/companion/tests/agent-primitives.test.tsx
git commit -m "feat(companion): add agent shell primitives"
```

---

### Task 4: Compose the global Agent Shell

**Files:**
- Modify: `apps/companion/src/App.tsx`
- Modify: `apps/companion/tests/app-shell.test.tsx`
- Modify: `apps/companion/src/styles/chrome.css`
- Create: `apps/companion/src/styles/agent-shell.css`
- Modify: `apps/companion/src/style.css`
- Remove after green: `apps/companion/src/ui/ViewNav.tsx`
- Remove after green: `apps/companion/src/ui/AppSummary.tsx`
- Remove after green: `apps/companion/src/ui/AppToolbar.tsx`
- Remove after green: `apps/companion/src/application/systemThemeMode.ts`

- [x] **Step 1: Write failing shell composition tests**

Assert source and static contracts for:

```tsx
<main data-font={preferences.font} data-theme={preferences.theme}>
	<AgentHeader />
	<StatusAlert />
	{/* active view */}
	<AgentTabs />
</main>
```

The tests must reject `useSystemThemeMode`, `resolvedCompanionTheme`, `ViewNav`, `AgentBar`, `HintBar`, `onKeyDown`, and shortcut labels. They must assert every view uses the shared `AgentHeader` and `AgentTabs` follows the active view as floating viewport navigation.

- [x] **Step 2: Run the focused shell tests and confirm RED**

```bash
pnpm --filter @workbranch/companion vitest run tests/app-shell.test.tsx tests/agent-primitives.test.tsx
```

Expected: old imports and bottom navigation assertions fail.

- [x] **Step 3: Recompose `App` without changing application behavior**

Set `const activeTheme = preferences.theme`. Pass the current theme to the headers and project groups. Keep `refresh`, `handleQuit`, `handleTaskAction`, workspace-monitor effects, `activityReloadToken`, error rendering, and all Tauri calls byte-for-byte equivalent except for moved props.

Render order:

```tsx
<main data-font={preferences.font} data-theme={activeTheme}>
	<AgentHeader
		theme={activeTheme}
		summary={model.summary}
		status={status}
		onRefresh={() => void refresh()}
		onQuit={handleQuit}
	/>
	<StatusAlert message={visibleError} />
	{/* existing active view blocks */}
	<AgentTabs currentView={currentView} onViewChange={setCurrentView} />
</main>
```

- [x] **Step 4: Implement shell CSS and floating-bottom navigation**

`agent-shell.css` owns `.agent-header`, `.agent-tabs`, `.terminal-panel`, `.prompt-line`, and `.status-token`. `chrome.css` keeps only generic shell/control rules that are still used. Use `--emphasis` for selection/current-row boundaries and `--accent` for command-like actions and links. Use 1px borders, restrained radii, no gradient, 32px minimum control height, and visible `:focus-visible` rings. The floating tab bar is the only shell element allowed a functional separation shadow and pill radius.

- [x] **Step 5: Remove obsolete modules after reference checks**

```bash
rg -n 'ViewNav|AppSummary|AppToolbar|useSystemThemeMode|resolvedCompanionTheme' apps/companion/src apps/companion/tests
```

Expected before deletion: only obsolete files and tests being replaced. Delete the obsolete files, update imports, then rerun the same command and expect no matches.

- [x] **Step 6: Run shell tests, typecheck, and lint**

```bash
pnpm --filter @workbranch/companion vitest run tests/app-shell.test.tsx tests/agent-primitives.test.tsx
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
```

Expected: all commands pass, apart from any already-known informational Biome diagnostic that does not produce a nonzero exit.

Evidence (2026-07-20): `app-shell`, `agent-primitives`, and `agent-tabs` passed 26/26; full Companion lint exited 0 with pre-existing informational `parseContract.ts` diagnostics. Production references to the removed modules are zero. Full typecheck remains staged on the Task 6 Settings conversion only.

- [ ] **Step 7: Commit gate**

Only with explicit user authorization:

```bash
git add apps/companion/src/App.tsx apps/companion/src/ui apps/companion/src/styles apps/companion/src/style.css apps/companion/tests
git commit -m "feat(companion): apply agent shell across views"
```

---

### Task 5: Convert Main to theme-aware terminal components

**Files:**
- Modify: `apps/companion/src/ui/ProjectGroup.tsx`
- Modify: `apps/companion/src/ui/TaskRow.tsx`
- Modify: `apps/companion/tests/project-group.test.tsx`
- Modify: `apps/companion/tests/task-row.test.tsx`
- Modify: `apps/companion/src/styles/task-details.css`
- Modify: `apps/companion/src/styles/task-actions.css`
- Modify: `apps/companion/src/styles/status-groups.css`
- Remove after green: `apps/companion/src/ui/TaskActionIcon.tsx`

- [x] **Step 1: Write failing Main markup tests**

Update fixtures to pass `theme="claude"` or `theme="codex"`. Assert:

```tsx
expect(claudeHtml).toContain('data-terminal-panel="claude"');
expect(claudeHtml).toContain("<fieldset");
expect(claudeHtml).toContain("❯");
expect(codexHtml).toContain('data-terminal-panel="codex"');
expect(codexHtml).toContain("›");
expect(html).toContain("RUN");
expect(html).toContain("IDE");
expect(html).toContain("Terminal");
expect(html).toContain("Finder");
expect(html).not.toContain("<svg");
```

Preserve assertions for `<details>/<summary>`, repo/branch/dirty information, notifications, current step, checklist depth, and action callbacks.

- [x] **Step 2: Run focused tests and confirm RED**

```bash
pnpm --filter @workbranch/companion vitest run tests/project-group.test.tsx tests/task-row.test.tsx
```

Expected: missing `theme` props and new primitive selectors fail.

- [x] **Step 3: Pass theme through `ProjectGroup` and `TaskRow`**

Use these props:

```ts
type ProjectGroupProps = {
	readonly group: ProjectGroupModel;
	readonly theme: CompanionTheme;
	readonly onAction: TaskActionHandler;
};

export type TaskActionHandler = (
	root: string,
	task: Task,
	kind: TaskActionKind,
) => void;

type TaskRowProps = {
	readonly root: string;
	readonly task: Task;
	readonly theme: CompanionTheme;
	readonly expanded: boolean;
	readonly onAction: TaskActionHandler;
};
```

Wrap each project with `TerminalPanel`. Use `StatusToken` for the visible state, `PromptLine` for task/current-step emphasis, and plain text buttons for IDE/Terminal/Finder. Keep the existing action kind union and callbacks unchanged.

- [x] **Step 4: Flatten Main CSS without removing information**

Remove card shadows, hover lift, pill-only metadata, and large radii. Keep the aligned checklist marker column and depth indentation from the current implementation. Use theme-specific prompt markers through rendered markup, not CSS-only `content`, so static tests and assistive review can verify them. Mark decorative prompt glyphs `aria-hidden="true"`; keep state text visible.

- [x] **Step 5: Run focused tests and static residue checks**

```bash
pnpm --filter @workbranch/companion vitest run tests/project-group.test.tsx tests/task-row.test.tsx
rg -n 'box-shadow|translateY|border-radius:\s*(1[0-9]|[7-9])px' apps/companion/src/styles/task-details.css apps/companion/src/styles/task-actions.css apps/companion/src/styles/status-groups.css
```

Expected: tests pass; residue search returns no Main-card elevation or large-radius declarations.

Evidence (2026-07-20): `project-group`, `task-row`, and `agent-primitives` passed 16/16. Main CSS residue search found no box shadow, hover lift, or 7px+ non-circular radius in the scoped files.

- [ ] **Step 6: Commit gate**

Only with explicit user authorization:

```bash
git add apps/companion/src/ui/ProjectGroup.tsx apps/companion/src/ui/TaskRow.tsx apps/companion/src/ui/TaskActionIcon.tsx apps/companion/src/styles apps/companion/tests/project-group.test.tsx apps/companion/tests/task-row.test.tsx
git commit -m "feat(companion): render main tasks as agent terminal panels"
```

---

### Task 6: Replace Settings appearance mode with the agent theme picker

**Files:**
- Create: `apps/companion/src/ui/AgentThemePicker.tsx`
- Modify: `apps/companion/src/ui/SettingsPanel.tsx`
- Modify: `apps/companion/src/ui/SettingsView.tsx`
- Modify: `apps/companion/tests/settings-panel.test.tsx`
- Modify: `apps/companion/src/styles/settings.css`

- [x] **Step 1: Write failing Settings tests**

Assert the picker has exactly two buttons and sends the complete new preference shape:

```tsx
expect(html).toContain("Claude Code");
expect(html).toContain("Codex");
expect(html).not.toContain("Light");
expect(html).not.toContain("Dark");
expect(html).not.toContain("System");

onPreferencesChange({
	...preferences,
	theme: "codex",
});
```

Keep assertions for launch-at-login, loading/disabled state, font selection, and font preview.

- [x] **Step 2: Run the focused test and confirm RED**

```bash
pnpm --filter @workbranch/companion vitest run tests/settings-panel.test.tsx
```

Expected: old theme mode labels and old preference fields fail.

- [x] **Step 3: Implement `AgentThemePicker` and replace the mode section**

Use this interface:

```ts
type AgentThemePickerProps = {
	readonly value: CompanionTheme;
	readonly onChange: (theme: CompanionTheme) => void;
};
```

Render a labelled group with two `<button type="button">` controls, `aria-pressed`, and visible focus. `SettingsPanel` calls `onPreferencesChange({ ...preferences, theme })`. Remove `systemThemeMode`, `modeHint`, `COMPANION_THEME_MODE_OPTIONS`, and all mode copy.

- [x] **Step 4: Apply terminal form styling**

Keep native checkbox and select semantics. Use a `TerminalPanel` for Startup, Font, and Theme sections. Claude uses fieldset legends; Codex uses ruled headings. Do not hide labels or replace native inputs with non-semantic divs.

- [x] **Step 5: Run Settings tests and typecheck**

```bash
pnpm --filter @workbranch/companion vitest run tests/settings-panel.test.tsx tests/preferences.test.ts
pnpm --filter @workbranch/companion typecheck
```

Expected: both files pass and no mode/family type remains in Settings code.

Evidence (2026-07-20): Settings and preference tests passed 16/16 and Companion typecheck exited 0. The old mode/family/system-mode Settings contract is removed. The generic `System Mono` font label remains by design; only the appearance `System` option was removed.

- [ ] **Step 6: Commit gate**

Only with explicit user authorization:

```bash
git add apps/companion/src/ui/AgentThemePicker.tsx apps/companion/src/ui/SettingsPanel.tsx apps/companion/src/ui/SettingsView.tsx apps/companion/src/styles/settings.css apps/companion/tests/settings-panel.test.tsx
git commit -m "feat(companion): add claude and codex theme picker"
```

---

### Task 7: Restyle Activity without changing calendar behavior

**Files:**
- Modify: `apps/companion/src/activity/activity-calendar.css`
- Modify only if a semantic wrapper is needed: `apps/companion/src/activity/ActivityCalendarView.tsx`
- Modify: `apps/companion/tests/activity-calendar.test.tsx`

- [x] **Step 1: Add failing CSS contract coverage without weakening behavior tests**

Keep all current session, lane, loading, selection, and fallback assertions. Add checks that calendar CSS uses `var(--surface-*)`, `var(--line)`, and `var(--cal-1)` through `var(--cal-6)`, while the main calendar containers contain no gradient, box shadow, or radius above 6px.

- [x] **Step 2: Run Activity tests and confirm RED only for new visual contracts**

```bash
pnpm --filter @workbranch/companion vitest run tests/activity-calendar.test.tsx
```

Expected: existing behavioral tests stay green; only the new flat-terminal CSS assertions fail.

- [x] **Step 3: Restyle the existing calendar classes**

Keep the current DOM, day/three-day modes, lane calculations, minimum session height, project color fallback, `color-mix` enhancement, reload policy, and selected session behavior. Change only CSS: flat background, 1px rules, 0–6px radii, theme calendar tokens, monospace labels, and token-driven selected/focus state.

- [x] **Step 4: Run Activity tests and focused typecheck**

```bash
pnpm --filter @workbranch/companion vitest run tests/activity-calendar.test.tsx
pnpm --filter @workbranch/companion typecheck
```

Expected: all Activity tests and typecheck pass.

Evidence (2026-07-20): Activity tests passed 37/37 and Companion typecheck exited 0. Session/lane/layout/fallback behavior stayed covered while the new flat token contract passed.

- [ ] **Step 5: Commit gate**

Only with explicit user authorization:

```bash
git add apps/companion/src/activity apps/companion/tests/activity-calendar.test.tsx
git commit -m "feat(companion): align activity with agent themes"
```

---

### Task 8: Close the implementation with regression and visual proof

**Files:**
- Modify if implementation details changed the contract: `DESIGN.md`
- Update progress only: `../TASK-WORKBRANCH.md`

- [x] **Step 1: Run the full automated proof set**

From the repository root:

```bash
pnpm --filter @workbranch/companion test
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
pnpm --filter @workbranch/companion build
pnpm --filter @workbranch/companion tauri build
git diff --check
```

Expected: every command exits 0. If a pre-existing informational diagnostic remains, record the exact output and confirm the command still exits 0.

Evidence (2026-07-23): full Vitest passed 15 files / 116 tests; Companion typecheck, lint, Vite build, Tauri release build, and `git diff --check` all exited 0. Lint retained 42 existing informational `useLiteralKeys` diagnostics and no errors. The macOS app bundle was generated at `apps/companion/src-tauri/target/release/bundle/macos/WorkbranchCompanion.app`.

- [x] **Step 2: Prove removed concepts and forbidden additions are absent**

```bash
rg -n 'themeFamily|themeMode|Light|System|useSystemThemeMode|data-theme\$="-light"' apps/companion/src apps/companion/tests
rg -n 'HintBar|shortcut|⌘1|onKeyDown|addEventListener\("keydown"' apps/companion/src apps/companion/tests
rg -n 'tailwind|shadcn|@radix|brainless' apps/companion/package.json pnpm-lock.yaml
```

Expected: no production/test matches for removed appearance modes or shortcuts. Package searches return no newly introduced dependency; documentation comments may mention Brainless only where provenance requires it.

Evidence (2026-07-23): production source contains no system-theme hook, former light selector, shortcut bar, or QA instrumentation residue. `themeFamily` and `themeMode` remain only as the planned read-only migration inputs plus migration fixtures. `package.json` and `pnpm-lock.yaml` have no implementation diff.

- [x] **Step 3: Run the native visual QA gate in both themes**

Start Companion:

```bash
pnpm companion:dev
```

Inspect these six states at approximately 360px and 460px widths:

1. Claude Code / Main: semantic fieldset header without a visible agent product-name legend, pixel-style Workbranch mark, `❯` prompt rows, readable project panels.
2. Claude Code / Activity: same expanded header footprint as Main, readable day and three-day modes, session selection and details.
3. Claude Code / Settings: same expanded header footprint as Main, accessible controls, Claude selected in the two-choice picker.
4. Codex / Main: `>_ Workbranch Companion` launch card, `›` prompt rows, monochrome selection/current-step emphasis, and cyan limited to command-like actions and links.
5. Codex / Activity: same expanded header footprint as Main, monochrome calendar with tokenized session colors and visible selection.
6. Codex / Settings: same expanded header footprint as Main, Codex selected, restart persistence confirmed.

For every state, verify keyboard focus, task disclosure, IDE/Terminal/Finder actions, refresh, quit, launch-at-login, font change, error display, long text truncation, and reduced motion. Do not claim native visual QA if the Tauri window was not observed.

Evidence (2026-07-23): the native Tauri app was observed across Claude/Codex × Main/Activity/Settings at 360px and 460px. The 12 final full-window states passed independent visual-design and visual-fidelity reviews with HIGH confidence. The user-reported tab ambiguity was resolved with active fill, 700-weight label, and a 2px theme indicator; CJK wrapping, helper contrast, focus, actions, refresh, login toggle, font, and reduced-motion states were also exercised.

- [x] **Step 4: Record migration proof**

Start once with an existing preference store containing `themeFamily: "companion"` and any former `themeMode`; verify Claude Code loads and the next save writes `theme: "claude"`. Restart after selecting Codex and verify Codex remains selected.

Evidence (2026-07-23): a legacy store loaded Claude and wrote the canonical `theme: "claude"`; selecting Codex and restarting preserved `theme: "codex"`.

- [x] **Step 5: Update task state and archive only after all gates pass**

Set `../TASK-WORKBRANCH.md` to `status: done` only after automated and native visual proof passes. Keep `DESIGN.md` as the current contract. Archive the active plan according to the workbranch done workflow; do not archive on test-only evidence when visual QA remains open.

Evidence (2026-07-23): automated proof, native visual proof, migration proof, dependency checks, and cleanup checks passed. Commit gates were intentionally skipped because no explicit commit authorization was given; the branch and worktree remain available for review.

---

## Acceptance criteria

- Settings offers exactly `Claude Code | Codex`; no Light, Dark, or System mode remains.
- New installs and every unsupported/legacy theme value resolve to Claude Code.
- Theme selection applies immediately to Main, Activity, and Settings and persists after restart.
- Main, Activity, and Settings share the same theme-specific expanded header and preserve its footprint across tab changes.
- Floating bottom terminal tabs remain visible above scrolling content without covering the final row.
- Expanded tasks use selected-row background emphasis and show progress in a compact pill.
- Claude and Codex use different header, panel, and prompt anatomy through shared interfaces.
- No shortcut bar or keyboard shortcut is added.
- Main preserves task disclosure, status, progress, repository metadata, current step, nested checklist, notifications, and actions.
- Activity preserves day/three-day layout, reload behavior, selection, session details, overlap handling, and static color fallbacks.
- Settings preserves launch-at-login and font behavior.
- No CLI, contract, domain, Rust command, watcher, or activity-store behavior changes.
- No new runtime dependency is added.
- Tests, typecheck, lint, Vite build, Tauri build, diff check, and native visual QA pass.

## Out of scope

- Light appearance, system appearance following, user-defined colors, and third themes.
- Keyboard shortcuts, command palette, vim navigation, or shortcut hints.
- New task lifecycle mutations or Activity features.
- CLI output/schema changes, tray icon changes, Rust command changes, and package contract changes.
- Copying Claude or OpenAI trademarks, logos, or product copy. Use Workbranch identity with the referenced terminal grammar.
