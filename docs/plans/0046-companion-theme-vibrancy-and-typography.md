# Companion Theme Vibrancy and Typography Legibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Use `superpowers:test-driven-development` for every CSS contract change and finish with the native visual QA gate.

**Goal:** Lift the fixed-dark Claude Code and Codex themes out of their current gray-on-gray look (theme-tinted structure, visible status colors, brighter secondary text), make all text legible (remove thin-glyph font smoothing, raise every font size by one pixel), and keep the native Companion window usable at its user-approved 460px minimum width.

**Architecture:** Theme and typography changes are CSS-token and CSS-rule edits guarded by the existing `readCssContract` tests in `apps/companion/tests/app-shell.test.tsx`. Claude uses low-saturation warm-graphite structure with orange reserved for compact identity signals; Codex uses cool-neutral toned-up surfaces; both get status-colored `StatusToken` text and a one-pixel type-scale sweep. The user-approved repo/branch information correction is one narrow markup exception in `TaskRow.tsx`: repository name becomes plain text and only `branchName` remains a chip.

**Tech Stack:** Tauri v2, React 18, TypeScript 5.9, Vite 7, Vitest 4, Biome 2, plain CSS. Do not add any dependency.

---

## Source of truth and fixed decisions

- Base contract: `docs/plans/0045-companion-agent-shell-claude-codex-themes.md` (completed) and `DESIGN.md`; this plan must update `DESIGN.md` before implementation so the active design contract reflects the 2026-07-24 direction.
- User decision (2026-07-24): the current shell reads as too drab (칙칙함) and text as blurry (흐릿함). Chosen direction: **theme color reinforcement + brightness tone-up** and **font size +1px with rendering fixes**.
- Follow-up user decision (2026-07-24): the first Claude re-tint made broad backgrounds too orange. This decision supersedes the earlier Task 1 terracotta surface/line/selection values: broad Claude structure returns to low-saturation warm graphite, while orange remains on compact accents only. Codex stays unchanged.
- Identity anchors stay untouched: Claude `--text: #c0caf5`, `--accent: #cd694a`, `--emphasis: #cd694a`; Codex `--text: #ededed`, `--accent: #5cc2e0`, `--emphasis: #ededed`.
- Pinned contracts that must NOT change: `--button-bg`/`--button-bg-hover` values, `main { padding: 12px }`, narrow-width `.agent-header h1 { font-size: 13px }`, `word-break: keep-all` on `.step-text`, step-marker rules (`.step-marker-done` must not use `var(--done)`), no gradients, no new box shadows, `--cal-1..6`/`--cal-bg-1..6` values, status palette values (`--blocked`, `--review`, `--done`, `--notify` and their softs).
- User decision (2026-07-24): the native Companion window uses **460px as both its initial width and minimum width**. Native visual QA uses the 460px product boundary; the previous ~360px capture is no longer an acceptance target.
- Production markup exception: only `apps/companion/src/ui/TaskRow.tsx` may change to render repository name as text and `branchName` as the chip. Do not modify other production `.tsx`, Rust, contract, or CLI files. The theme, status, and typography work remains CSS-driven.
- Commit gates run only with explicit user authorization.

## Decision gates

- [x] **Active design source of truth follows the 2026-07-24 user decision**
  - Impact: visual contract and future regression reviews.
  - Evidence: this plan records the newer user decision, while `DESIGN.md` still records the superseded 2026-07-23 neutral-structure direction.
  - Resolution: update `DESIGN.md` in this slice and append a 2026-07-24 direction revision; do not leave contradictory active guidance.
- [x] **Focused CSS tests use the package binary explicitly**
  - Impact: whether RED/GREEN steps execute any tests.
  - Evidence: `apps/companion/package.json` defines `test`, not a `vitest` script; `pnpm --filter @workbranch/companion vitest run ...` exits without running tests.
  - Resolution: use `pnpm --filter @workbranch/companion exec vitest run ...` for focused and direct Vitest runs.
- [x] **The +1px sweep is an exact selector contract, not only a 10px floor**
  - Impact: typography acceptance and regression meaning.
  - Evidence: the acceptance criterion requires the documented map everywhere; a `9px` residue check alone cannot detect unchanged `10px`, `11px`, `12px`, or `13px` declarations.
  - Resolution: add explicit contract expectations for every selector/value in Task 3's size map, while preserving the narrow-header 13px exception.
- [x] **Native release build is part of the final automated gate**
  - Impact: Tauri integration and release-bundle readiness.
  - Evidence: `DESIGN.md` requires a Tauri build, and `pnpm --filter @workbranch/companion build` runs only TypeScript plus Vite.
  - Resolution: run `pnpm companion:build` and `git diff --check` in Task 4 in addition to test/typecheck/lint/Vite build.
- [x] **Native window boundary is 460px**
  - Impact: usable density, truncation behavior, and what native visual QA proves.
  - Evidence: the ~361px native capture was visibly too narrow during Task 4 QA; the existing Tauri window starts at 420px and has no explicit minimum-width contract.
  - Resolution: set the Tauri window `width` and `minWidth` to `460`, and run native visual QA at 460px rather than maintaining a separate ~360px target.
- [x] **Repository text and branch chip use a minimal separator**
  - Impact: Main-view information hierarchy and the smallest production markup exception in this slice.
  - Evidence: native QA showed that combining repository name and branch name inside one chip implies they are one identifier, while the user explicitly identified them as separate concepts.
  - Resolved structure: render repository name as plain text and only `branchName` inside a chip; keep each repo/branch pair together when wrapping. The dirty working-tree marker stays associated with the repository text rather than the branch chip.
  - Resolution: use `backend [branchName]` with spacing and no literal `|`. The branch chip already supplies the visual boundary, avoiding redundant chrome at 460px.

No high-impact unresolved decision remains. The 460px window contract and `repo text + branch chip` presentation are final, so implementation may resume in auto mode.

## File structure

### Modify

- `DESIGN.md`: replace the superseded neutral-Claude color direction and append the 2026-07-24 direction revision.
- `apps/companion/tests/app-shell.test.tsx`: replace the neutral-Claude contract, update `--muted` anchors, add tone-up, status-color, and typography contracts.
- `apps/companion/tests/task-row.test.tsx`: update the existing selected-summary token contract to the final neutral `#c0caf5` translucent value.
- `apps/companion/src/ui/TaskRow.tsx`: render repository name as text and only `branchName` as a chip, with dirty state attached to the repository identity.
- `apps/companion/src/styles/themes.css`: new Claude and Codex token values.
- `apps/companion/src/styles/base.css`: root/body background, remove font smoothing, bump size variables.
- `apps/companion/src/styles/agent-shell.css`: status token colors and size sweep.
- `apps/companion/src/styles/task-details.css`, `task-actions.css`, `chrome.css`, `settings.css`: size sweep.
- `apps/companion/src/activity/activity-calendar.css`: size sweep.
- `apps/companion/src-tauri/tauri.conf.json`: set the initial and minimum native window width to 460px.
- `../TASK-WORKBRANCH.md`: progress only.

No file is created or removed. `TaskRow.tsx` is the only production markup change.

---

### Task 1: Re-tint the Claude and Codex theme tokens

**Files:**
- Modify: `DESIGN.md`
- Modify: `apps/companion/tests/app-shell.test.tsx`
- Modify: `apps/companion/tests/task-row.test.tsx`
- Modify: `apps/companion/src/styles/themes.css`
- Modify: `apps/companion/src/styles/base.css`

**Interfaces:**
- Consumes: existing `readCssContract()` helper at the top of `app-shell.test.tsx`.
- Produces: final token values consumed visually by every stylesheet; later tasks rely on `--muted`, `--line`, `--line-strong`, `--surface-0..3` having the values fixed here.

- [x] **Step 1: Synchronize the active design source of truth**

Update `DESIGN.md` before production CSS:

- In **Visual language / Color**, use low-saturation warm-graphite Claude surfaces and warm-neutral structural lines, neutral `#c0caf5` translucent selected/current-step backgrounds, brighter per-theme muted text, and unchanged identity anchors. Orange remains limited to compact prompt, focus, action, and active-state signals.
- In **Visual language / Typography**, record the one-pixel type-scale increase, 10px production minimum, preserved narrow-header 13px exception, and removal of explicit thin-glyph WebKit smoothing.
- Append a `2026-07-24` direction revision recording the final warm-graphite structure and explicitly superseding the rejected broad terracotta treatment.
- Keep the existing no-gradient, restrained-shadow, fixed-dark, monospace, and cross-view consistency contracts.

Evidence (2026-07-24, synchronized after Task 6): `DESIGN.md` records low-saturation warm-graphite Claude structure, neutral selected/current-step fills, compact orange identity signals, brighter cool-neutral Codex structure, the typography floor/exception, native smoothing, and the final 2026-07-24 direction revision.

- [x] **Step 2: Lock the final warm-graphite and compact-orange contract**

In `apps/companion/tests/app-shell.test.tsx`, delete the test `"keeps Claude structural surfaces neutral and reserves orange for accents"` (currently around lines 186-198) and add these two tests in its place:

```tsx
it("reserves Claude orange for compact accents instead of structural backgrounds", () => {
	const css = readCssContract("src/style.css");

	expect(css).toMatch(
		/main\[data-theme="claude"\]\s*\{[^}]*--line:\s*#403b38;[^}]*--line-strong:\s*#625952;/s,
	);
	expect(css).toMatch(
		/main\[data-theme="claude"\]\s*\{[^}]*--emphasis-soft:\s*rgba\(205,\s*105,\s*74,\s*0\.14\);[^}]*--task-selected-summary-bg:\s*rgba\(192,\s*202,\s*245,\s*0\.06\);/s,
	);
	expect(css).toMatch(
		/main\[data-theme="claude"\]\s*\{[^}]*--current-step-bg:\s*rgba\(192,\s*202,\s*245,\s*0\.08\);/s,
	);
	expect(css).not.toMatch(
		/main\[data-theme="claude"\]\s*\{[^}]*--line:\s*rgba\(205,\s*105,\s*74/s,
	);
});

it("tones up both fixed-dark themes with tinted surfaces and lines", () => {
	const css = readCssContract("src/style.css");

	expect(css).toMatch(
		/main\[data-theme="claude"\]\s*\{[^}]*--surface-0:\s*#131313;[^}]*--surface-1:\s*#1a1918;[^}]*--surface-2:\s*#22201f;[^}]*--surface-3:\s*#2c2927;/s,
	);
	expect(css).toMatch(
		/main\[data-theme="codex"\]\s*\{[^}]*--surface-0:\s*#121214;[^}]*--surface-1:\s*#18181b;[^}]*--surface-2:\s*#202024;[^}]*--surface-3:\s*#2b2b30;/s,
	);
	expect(css).toMatch(
		/main\[data-theme="codex"\]\s*\{[^}]*--line:\s*#414147;[^}]*--line-strong:\s*#60606a;/s,
	);
	expect(css).toMatch(/:root\s*\{[^}]*background:\s*#131313/s);
	expect(css).toMatch(/body\s*\{[^}]*background:\s*#131313/s);
});
```

In the existing test `"uses a readable text token for small secondary copy"`, replace the single line `expect(css).toContain("--muted: #949494");` with:

```tsx
expect(css).toContain("--muted: #9aa5ce");
expect(css).toContain("--muted: #a8a8ad");
expect(css).not.toContain("--muted: #949494");
expect(css).toContain("--faint: #767c99");
expect(css).toContain("--faint: #6b6b70");
expect(css).not.toContain("--faint: #626262");
expect(css).not.toContain("--faint: #5d5d5d");
```

- [x] **Step 3: Run the focused test and confirm RED**

```bash
pnpm --filter @workbranch/companion exec vitest run tests/app-shell.test.tsx
```

Expected: the final palette/readability contracts fail against the pre-change `#3a3a3a`, `#0e0e0e`, `#949494`, `#626262`, and `#5d5d5d` values; every unrelated test stays green.

Evidence (2026-07-24, final contract): the focused RED run failed only on the intended Claude surface/line/fill and readability differences. Task 6 later replaced the intermediate terracotta values before the final GREEN proof.

- [x] **Step 4: Replace both token blocks in `themes.css`**

Replace the two theme blocks (keep the `main[data-font=...]` selectors at the bottom untouched):

```css
main[data-theme="claude"] {
	--surface-0: #131313;
	--surface-1: #1a1918;
	--surface-2: #22201f;
	--surface-3: #2c2927;
	--line: #403b38;
	--line-strong: #625952;
	--text: #c0caf5;
	--muted: #9aa5ce;
	--faint: #767c99;
	--accent: #cd694a;
	--accent-strong: #e08567;
	--accent-soft: rgba(205, 105, 74, 0.14);
	--emphasis: #cd694a;
	--emphasis-soft: rgba(205, 105, 74, 0.14);
	--task-selected-summary-bg: rgba(192, 202, 245, 0.06);
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
	--current-step-bg: rgba(192, 202, 245, 0.08);
	--cal-1: #cd694a;
	--cal-2: #7dcfff;
	--cal-3: #87d787;
	--cal-4: #e0af68;
	--cal-5: #bb9af7;
	--cal-6: #f7768e;
	--cal-bg-1: rgba(205, 105, 74, 0.18);
	--cal-bg-2: rgba(125, 207, 255, 0.18);
	--cal-bg-3: rgba(135, 215, 135, 0.18);
	--cal-bg-4: rgba(224, 175, 104, 0.18);
	--cal-bg-5: rgba(187, 154, 247, 0.18);
	--cal-bg-6: rgba(247, 118, 142, 0.18);
}

main[data-theme="codex"] {
	--surface-0: #121214;
	--surface-1: #18181b;
	--surface-2: #202024;
	--surface-3: #2b2b30;
	--line: #414147;
	--line-strong: #60606a;
	--text: #ededed;
	--muted: #a8a8ad;
	--faint: #6b6b70;
	--accent: #5cc2e0;
	--accent-strong: #8bdcf2;
	--accent-soft: rgba(92, 194, 224, 0.14);
	--emphasis: #ededed;
	--emphasis-soft: rgba(237, 237, 237, 0.1);
	--task-selected-summary-bg: rgba(237, 237, 237, 0.06);
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
	--cal-bg-1: rgba(92, 194, 224, 0.18);
	--cal-bg-2: rgba(246, 226, 183, 0.18);
	--cal-bg-3: rgba(171, 223, 167, 0.18);
	--cal-bg-4: rgba(167, 167, 167, 0.18);
	--cal-bg-5: rgba(242, 160, 160, 0.18);
	--cal-bg-6: rgba(187, 154, 247, 0.18);
}
```

Final contract: Claude surfaces 0-3 and structural lines use the warm-graphite ramp, while `--task-selected-summary-bg` and `--current-step-bg` use neutral `#c0caf5` translucency. Claude orange identity values, Codex tokens, status/calendar tokens, and button backgrounds remain unchanged. `base.css` must still not define `--surface-0:` (a test asserts this).

- [x] **Step 5: Update the hardcoded pre-theme background in `base.css`**

In `apps/companion/src/styles/base.css` replace both `background: #0e0e0e;` declarations (`:root` and `body`) with `background: #131313;` so the pre-hydration flash matches the final Claude default surface. Leave `color: #c0caf5;` as is.

- [x] **Step 6: Run the focused test and residue checks, confirm GREEN**

```bash
pnpm --filter @workbranch/companion exec vitest run tests/app-shell.test.tsx
rg -n '#0e0e0e|#131110|#1a1715|#221e1b|#2d2824|#949494|#3a3a3a|#565656|#626262|#5d5d5d' apps/companion/src
```

Expected: all app-shell tests pass; the `rg` search returns no production matches.

Evidence (2026-07-24, synchronized after Task 6): focused Vitest passed `app-shell.test.tsx` and `task-row.test.tsx` (2 files / 39 tests), and the rejected-token residue search returned no production matches.

- [x] **Step 7: Commit gate**

Only with explicit user authorization:

```bash
git add DESIGN.md apps/companion/src/styles/themes.css apps/companion/src/styles/base.css apps/companion/tests/app-shell.test.tsx
git commit -m "feat(companion): re-tint claude and codex theme tokens"
```

Evidence (2026-07-24): intentionally skipped because the user did not authorize a commit; implementation remains uncommitted for review.

---

### Task 2: Surface task states through colored status tokens

**Files:**
- Modify: `apps/companion/tests/app-shell.test.tsx`
- Modify: `apps/companion/src/styles/agent-shell.css`

**Interfaces:**
- Consumes: `StatusToken` markup already renders `.status-token[data-status="..."]` with a visible text label (see `src/ui/StatusToken.tsx`; no TSX change).
- Produces: state-colored token text used by Main task rows in both themes.

- [x] **Step 1: Write the failing status-color contract**

Add to `apps/companion/tests/app-shell.test.tsx`:

```tsx
it("colors status token text by state instead of relying on the dot alone", () => {
	const css = readCssContract("src/style.css");

	expect(css).toMatch(
		/\.status-token\s*\{[^}]*color:\s*var\(--muted\)/s,
	);
	expect(css).toMatch(
		/\.status-token\[data-status="in-progress"\]\s*\{[^}]*color:\s*var\(--emphasis\)/s,
	);
	expect(css).toMatch(
		/\.status-token\[data-status="blocked"\]\s*\{[^}]*color:\s*var\(--blocked\)/s,
	);
	expect(css).toMatch(
		/\.status-token\[data-status="review"\]\s*\{[^}]*color:\s*var\(--review\)/s,
	);
	expect(css).toMatch(
		/\.status-token\[data-status="done"\]\s*\{[^}]*color:\s*var\(--done\)/s,
	);
	expect(css).toMatch(
		/\.status-token-marker\s*\{[^}]*height:\s*7px[^}]*width:\s*7px/s,
	);
	expect(css).not.toMatch(
		/\.status-token\[data-status="(?:todo|planning)"\]\s*\{[^}]*color:/s,
	);
});
```

- [x] **Step 2: Run the focused test and confirm RED**

```bash
pnpm --filter @workbranch/companion exec vitest run tests/app-shell.test.tsx
```

Expected: only the new status-color test fails (no `color:` rules exist on the state selectors yet, marker is 6px).

Evidence (2026-07-24): focused Vitest executed 26 tests; only the new status-color contract failed and the remaining 25 passed.

- [x] **Step 3: Implement the status colors in `agent-shell.css`**

Change `.status-token-marker` from `height: 6px; width: 6px;` to `height: 7px; width: 7px;` and extend the four existing per-state marker rules so each state also colors the token text. The final block reads:

```css
.status-token-marker {
	background: var(--faint);
	border-radius: 50%;
	height: 7px;
	width: 7px;
}

.status-token[data-status="in-progress"] {
	color: var(--emphasis);
}

.status-token[data-status="in-progress"] .status-token-marker {
	background: var(--emphasis);
}

.status-token[data-status="blocked"] {
	color: var(--blocked);
}

.status-token[data-status="blocked"] .status-token-marker {
	background: var(--blocked);
}

.status-token[data-status="review"] {
	color: var(--review);
}

.status-token[data-status="review"] .status-token-marker {
	background: var(--review);
}

.status-token[data-status="done"] {
	color: var(--done);
}

.status-token[data-status="done"] .status-token-marker {
	background: var(--done);
}
```

Todo/planning states intentionally keep the default muted color. Do not touch `.step-marker*` rules (a contract test forbids `var(--done)` there).

- [x] **Step 4: Run the focused test and confirm GREEN**

```bash
pnpm --filter @workbranch/companion exec vitest run tests/app-shell.test.tsx tests/agent-primitives.test.tsx
```

Expected: all pass, including the untouched primitive markup contracts.

Evidence (2026-07-24): focused app-shell and primitive suites passed 32/32 tests across 2 files.

- [x] **Step 5: Commit gate**

Only with explicit user authorization:

```bash
git add apps/companion/src/styles/agent-shell.css apps/companion/tests/app-shell.test.tsx
git commit -m "feat(companion): color status tokens by task state"
```

Evidence (2026-07-24): intentionally skipped because the user did not authorize a commit; implementation remains uncommitted for review.

---

### Task 3: Typography legibility sweep (+1px, no thin smoothing)

**Files:**
- Modify: `apps/companion/tests/app-shell.test.tsx`
- Modify: `apps/companion/src/styles/base.css`
- Modify: `apps/companion/src/styles/agent-shell.css`
- Modify: `apps/companion/src/styles/task-details.css`
- Modify: `apps/companion/src/styles/task-actions.css`
- Modify: `apps/companion/src/styles/chrome.css`
- Modify: `apps/companion/src/styles/settings.css`
- Modify: `apps/companion/src/activity/activity-calendar.css`

**Interfaces:**
- Consumes: token values from Task 1 (unchanged here).
- Produces: the final type scale; the narrow-width `.agent-header h1 { font-size: 13px }` contract is intentionally preserved.

- [x] **Step 1: Write the failing typography contract**

Add to `apps/companion/tests/app-shell.test.tsx`:

```tsx
it("keeps companion typography at a legible fixed-dark scale", () => {
	const css = readCssContract("src/style.css");

	expect(css).not.toContain("-webkit-font-smoothing");
	expect(css).not.toMatch(/font-size:\s*9px/);
	expect(css).toMatch(/main\s*\{[^}]*--floating-tabs-font-size:\s*12px/s);
	expect(css).toMatch(/main\s*\{[^}]*--progress-pill-font-size:\s*11px/s);
	expect(css).toMatch(
		/\.steps\s*\{[^}]*font-size:\s*12px[^}]*line-height:\s*1\.5/s,
	);
	expect(css).toMatch(/\.task-name\s*\{[^}]*font-size:\s*13px/s);
	expect(css).toMatch(/\.current-step\s*\{[^}]*font-size:\s*12px/s);
});
```

The contract is not complete with the snippet above alone. In the same test, add one explicit `toMatch` expectation for **every** selector and final value listed in Step 3 below, including Agent Header/controls/status, Task details/actions/errors, every Settings label/control, and every Activity calendar label/detail/narrow-mode override. The existing narrow-width `.agent-header h1 { font-size: 13px }` expectation remains the explicit exception. A GREEN result must fail if any old `10px`, `11px`, `12px`, or `13px` declaration that is listed for increase remains unchanged.

- [x] **Step 2: Run the focused test and confirm RED**

```bash
pnpm --filter @workbranch/companion exec vitest run tests/app-shell.test.tsx
```

Expected: only the new typography test fails (smoothing present, 9px sizes present, old variable values).

Evidence (2026-07-24): focused Vitest executed 27 tests; only the exact typography contract failed and the remaining 26 passed.

- [x] **Step 3: Apply the exact size map**

`base.css`:
- Delete the line `-webkit-font-smoothing: antialiased;` from `:root` (keep `text-rendering: optimizelegibility;`).
- `--floating-tabs-font-size: 11px` → `12px`.
- `--progress-pill-font-size: 10px` → `11px`.

`agent-shell.css`:
- `.terminal-panel legend` `font-size: 10px` → `11px`.
- `.agent-header h1` `font-size: 14px` → `15px` (leave the `@media (max-width: 400px)` override at `13px`).
- `.agent-inventory` `10px` → `11px`.
- `.agent-control` `15px` → `16px`.
- `.terminal-panel-heading` `10px` → `11px`.
- `.status-token` `10px` → `11px`.

`task-details.css`:
- `.task-name` `12px` → `13px`.
- `.task-notification` `10px` → `11px`.
- `.plan-title` `9px` → `10px`.
- `.current-step` `11px` → `12px`.
- `.repo-name` and `.repo-branch-chip` use `11px` after Task 4 replaces the combined `.repo-chip`.
- `.repo-dot` `9px` → `10px`.
- `.steps` `font-size: 11px` → `12px` and `line-height: 1.45` → `1.5`.
- `.error, .empty` `12px` → `13px`.

`task-actions.css`:
- `.task-action` `10px` → `11px`.

`chrome.css`:
- `.app-error` `12px` → `13px`.

`settings.css`:
- `.settings-panel h2` `13px` → `14px`.
- `.settings-panel p, .settings-hint` `10px` → `11px`.
- `.settings-row label` `11px` → `12px`.
- `.settings-row-select::after` `11px` → `12px`.
- `.font-preview` `11px` → `12px`.
- `.font-preview-label` `9px` → `10px`.
- `.agent-theme-button` `10px` → `11px`.

`activity-calendar.css`:
- `.cal-title` `13px` → `14px`.
- `.cal-nav-button, .cal-today-button, .cal-mode-button, .cal-chip` `11px` → `12px`.
- `.cal-hour-label` `10px` → `11px`.
- `.cal-day-heading` `10px` → `11px`.
- `.cal-block-task` `11px` → `12px`.
- `.cal-block-time` `10px` → `11px`.
- `.cal-block-plan` `9px` → `10px`.
- `.cal-timeline[data-mode="day"] .cal-session[data-width="narrow"] .cal-block-task` `10px` → `11px`.
- `.cal-timeline[data-mode="day"] .cal-session[data-width="narrow"] .cal-block-time` `9px` → `10px`.
- `.cal-detail strong` `12px` → `13px`.
- `.cal-detail span, .cal-detail li` `10px` → `11px`.

No other declaration changes in this task.

- [x] **Step 4: Run the full companion suite and residue checks, confirm GREEN**

```bash
pnpm --filter @workbranch/companion exec vitest run
rg -n 'font-size:\s*9px|-webkit-font-smoothing' apps/companion/src
```

Expected: all test files pass (the narrow-header 13px and progress-pill/tab variable contracts keep passing); `rg` returns no matches.

Evidence (2026-07-24): full Companion Vitest passed 15 files / 123 tests, including the synchronized TaskRow selected-summary contract; the typography residue search returned no matches.

- [x] **Step 5: Commit gate**

Only with explicit user authorization:

```bash
git add apps/companion/src/styles apps/companion/src/activity/activity-calendar.css apps/companion/tests/app-shell.test.tsx
git commit -m "feat(companion): raise type scale and drop thin font smoothing"
```

Evidence (2026-07-24): intentionally skipped because the user did not authorize a commit; implementation remains uncommitted for review.

---

### Task 4: Enforce the 460px native boundary and separate repo/branch presentation

**Files:**
- Modify: `DESIGN.md`
- Modify: `apps/companion/tests/app-shell.test.tsx`
- Modify: `apps/companion/tests/task-row.test.tsx`
- Modify: `apps/companion/src/ui/TaskRow.tsx`
- Modify: `apps/companion/src/styles/task-details.css`
- Modify: `apps/companion/src-tauri/tauri.conf.json`

- [x] **Step 1: Write failing boundary and markup contract tests**

In `app-shell.test.tsx`, read `src-tauri/tauri.conf.json` and require the first native window to use both `width: 460` and `minWidth: 460`.

In `task-row.test.tsx`, require each rendered repository pair to contain:

- plain repository text outside the branch chip,
- one chip containing only the branch name,
- dirty state attached to the repository identity,
- no literal `|` separator.

Run the two focused tests and confirm they fail because the existing window is 420px without `minWidth` and the existing `.repo-chip` combines both values.

Evidence (2026-07-24): focused Vitest ran 39 tests and failed exactly 2 new contracts: Tauri reported `width: 420` with no `minWidth`, and `TaskRow` still rendered `repo-chip repo-dirty` instead of the required repo text plus branch-only chip.

- [x] **Step 2: Implement the smallest production correction**

- Set `width` and `minWidth` to `460` in `src-tauri/tauri.conf.json`.
- In `TaskRow.tsx`, keep each repository and branch as one non-breaking/wrapping pair, render repository name as plain text, render only `branchName` inside the branch chip, and keep the dirty marker on the repository text.
- In `task-details.css`, replace the combined `.repo-chip` styling with pair, repository-text, and branch-chip rules. Do not add a `|` pseudo-element or literal separator.
- Update `DESIGN.md` with the 460px minimum native boundary and the repo-text/branch-chip information hierarchy.

Evidence (2026-07-24): `TaskRow.tsx` now renders `repo-pair` with plain `repo-name` plus `repo-branch-chip`, keeps the dirty dot inside the repo identity, and renders no separator. CSS owns pair/text/chip styling, Tauri declares `width`/`minWidth: 460`, and `DESIGN.md` records both contracts.

- [x] **Step 3: Prove the focused contracts green**

```bash
pnpm --filter @workbranch/companion exec vitest run tests/app-shell.test.tsx tests/task-row.test.tsx
```

Expected: both files pass, including the new 460px and repo/branch assertions.

Evidence (2026-07-24): focused Vitest passed 2 files / 39 tests. The first GREEN run exposed only an overbroad negative assertion matching `.repo-chips`; narrowing it to the exact obsolete `.repo-chip` classes produced the clean pass.

---

### Task 5: Regression proof and native visual QA

**Files:**
- Update progress only: `../TASK-WORKBRANCH.md`

- [x] **Step 1: Run the full automated proof set**

From the repository root:

```bash
pnpm --filter @workbranch/companion test
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
pnpm --filter @workbranch/companion build
pnpm companion:build
git diff --check
```

Expected: every command exits 0, including the Tauri release build and whitespace check (the known informational `useLiteralKeys` Biome diagnostics are acceptable as long as lint exits 0).

Evidence (2026-07-24, refreshed after Task 4): Companion Vitest passed 15 files / 124 tests; TypeScript typecheck, Biome lint, Vite production build, Tauri release build, and `git diff --check` all exited 0. Biome reported only the 42 accepted informational `useLiteralKeys` diagnostics in `parseContract.ts`. The Tauri bundle was produced at `apps/companion/src-tauri/target/release/bundle/macos/WorkbranchCompanion.app`.

- [x] **Step 2: Native visual QA in both themes**

```bash
pnpm companion:dev
```

Inspect at the 460px minimum width:

1. Claude / Main: warm-graphite panels and borders, neutral `#c0caf5` translucent selection/current-step backgrounds, compact orange identity signals, colored DONE/BLOCKED status text, Korean step text crisp at 12px.
2. Claude / Activity + Settings: same header footprint, brighter secondary text, no washed-out gray.
3. Codex / Main + Activity + Settings: cool toned-up surfaces, cyan still limited to command-like actions, status colors visible.
4. Both themes: font smoothing change renders glyphs heavier/sharper; no layout overflow at the supported 460px boundary from the +1px sweep (task rows, chips, tabs, calendar, long Korean/`path` truncation).

Do not claim visual QA without observing the Tauri window.

Evidence (2026-07-24): observed the real Tauri window at logical `460x680` and captured the complete Claude/Codex × Main/Activity/Settings matrix in `/tmp/workbranch-companion-0046/final/`. The six fresh RGBA PNGs and `manifest.json` cover DONE/BLOCKED, clean/dirty repository identity, branch-only chips, long Korean/path wrapping, calendar density, Settings controls, and stable shared chrome. Dual independent visual review passed after a fresh fidelity retry corrected an image-reading false positive; design-system/functional and fidelity/CJK verdicts are both PASS.

- [x] **Step 3: Update task state**

Record progress in `../TASK-WORKBRANCH.md` after automated and visual proof both pass.

Evidence (2026-07-24): task brief records the refreshed automated gates, native capture manifest, independent review verdicts, restored installed app state, and the intentionally uncommitted branch.

---

### Task 6: Reduce Claude background saturation after visual review

**Files:**
- Modify: `DESIGN.md`
- Modify: `apps/companion/src/styles/themes.css`
- Modify: `apps/companion/src/styles/base.css`
- Modify: `apps/companion/tests/app-shell.test.tsx`
- Modify: `apps/companion/tests/task-row.test.tsx`

- [x] **Step 1: Lock the revised palette contract and confirm RED**
  - Require Claude surfaces `#131313`, `#1a1918`, `#22201f`, `#2c2927` and warm-neutral lines `#403b38`, `#625952`.
  - Require selected/current-step fills to use neutral `#c0caf5` translucency instead of terracotta translucency.
  - Preserve Claude `#cd694a` accent/emphasis values and all Codex values.
  - Evidence: focused `app-shell.test.tsx` ran 28 tests and failed only on the new Claude surface contract.

- [x] **Step 2: Apply the warm-graphite palette and synchronize `DESIGN.md`**
  - Broad surfaces and structural borders use the revised low-saturation values.
  - Orange remains on compact prompt, focus, action, and active-state signals.
  - Root/body pre-hydration background matches Claude `--surface-0`.

- [x] **Step 3: Prove focused contracts and inspect the live app without focus churn**
  - Evidence: focused Vitest passed 2 files / 39 tests and `git diff --check` passed.
  - Evidence: captured the already-running native Tauri window by window id without activating it at `/tmp/workbranch-companion-0046/followup/claude-main-warm-graphite-460.png`; broad orange structure is removed while orange identity signals remain.

---

## Acceptance criteria

- Claude theme structure uses low-saturation warm graphite with neutral selected/current-step fills; orange is reserved for compact identity signals. Codex carries brighter cool-neutral surfaces; identity anchors (`--text`, `--accent`, `--emphasis`) are unchanged.
- Secondary text uses the brighter `--muted` values (`#9aa5ce` Claude, `#a8a8ad` Codex); `#949494` no longer appears in production CSS.
- Status tokens show state-colored text and 7px markers for in-progress/blocked/review/done; todo/planning stay muted.
- `-webkit-font-smoothing` is removed and no production `font-size` is below 10px; the documented +1px map is applied everywhere including Settings and the Activity calendar.
- Pinned contracts still hold: button backgrounds, `main` padding, narrow header 13px, keep-all wrapping, step-marker rules, calendar token fills, no gradients, radius limits.
- The native window opens at 460px and cannot be resized below 460px; the full Claude/Codex visual matrix is observed at that boundary.
- Repository name is plain text, only `branchName` is displayed as a chip, and dirty state remains associated with the repository rather than the branch.
- No production `.tsx` change except the scoped `TaskRow.tsx` information-structure correction; no Rust, contract, CLI, or dependency change; the existing CSS contract test `.tsx` is updated; `pnpm --filter @workbranch/companion test|typecheck|lint|build`, `pnpm companion:build`, and `git diff --check` all exit 0; native visual QA observed in both themes.

## Out of scope

- New theme values beyond Claude/Codex, light modes, or user-configurable colors.
- Markup or component changes beyond the approved `TaskRow.tsx` repo-text/branch-chip correction; behavior or IPC changes; icon or font-family additions.
- Activity calendar behavior, lane math, or DOM changes.
- Any change under `apps/cli/**`, `packages/contract/**`, or Companion Rust code.
