# 0018 Companion SwiftBar Plugin Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` for all pure logic (renderer, action arg-building). Companion code lives under `companion/**` with its own Node toolchain; never import companion code into the bash CLI, and make no `src/workbranch/**` behavior changes in this plan. Unit tests must not invoke `osascript` or SwiftBar.

> **Series:** Part 4 of 4 of the menu bar companion initiative. Execution order: 0015 memo/noti/json → 0016 focus command → 0017 monorepo release plumbing → **0018 (this)**. **Hard dependencies:** 0015's `workbranch list --json` + `memo`/`noti`, 0016's `workbranch focus`, and 0017's release plumbing verified by one real `v*` release. The first companion release also requires the external tap follow-up (add `Formula/workbranch-companion.rb` to `tkhwang/homebrew-tap`).

**Goal:** Ship the menu bar companion: a SwiftBar plugin (single-file Node bundle, written in TypeScript) that shows every task workspace with its memo title and notification count, jumps to a workspace on click (`workbranch focus`), edits memos, and creates new workspaces (`workbranch add`) from the menu bar.

**Architecture:** Presentation-only client of the workbranch CLI. On each refresh (5s) it runs `workbranch list --json` per configured project root and renders SwiftBar menu lines. Menu clicks should call a single `workbranch-companion action <verb> ...` entrypoint, and that action runner shells out to `workbranch` with explicit argv and cwd; SwiftBar lines should not interpolate memo text or shell fragments directly. A pure `render.ts` (JSON in, menu lines out) carries all display logic and is fully unit-tested; `index.ts` is a thin shell-out/IO wrapper. Long-running actions (`workbranch add`) run detached with completion delivered via `osascript display notification`.

**Tech Stack:** TypeScript, Node 20+, esbuild (single-file bundle with `#!/usr/bin/env node` banner), vitest, SwiftBar (user-installed cask), osascript dialogs/notifications, Homebrew formula `workbranch-companion` (tap, external).

**Product fit:** This plan turns workbranch into a task cockpit: see each workspace memo, notice which task needs attention, and jump to the right terminal context without scanning Warp tabs.

---

## Problem Statement

With memo/noti/focus shipped (0015/0016), the remaining gap is glanceability and reach: seeing all workspaces' memos and notification state without visiting a terminal, and jumping or creating workspaces from anywhere. A SwiftBar plugin delivers this in days with no codesign/notarization pipeline, while the CLI contract keeps a future native SwiftUI app (or Raycast extension) cheap.

## Current Repo Evidence

- `workbranch list --json` (0015) is the data contract: `{project, root, tasks[{name, path, memoTitle, notiCount, repos[{name, branch, dirty}]}]}`.
- `workbranch focus <task>` (0016) validates-then-jumps; `workbranch memo`/`noti` (0015) mutate state; `workbranch add <task>` exists and takes minutes (worktrees + `REPO_SETUP` installs) — menu bar must not block on it.
- `companion/package.json` exists as a 0017 placeholder (private, stub scripts) — this plan replaces the stubs with real code.
- SwiftBar plugin contract: an executable in the plugins dir named `<name>.<interval>.<ext>`; stdout lines define the menu; `---` separates the bar title from dropdown; per-line params (`bash=`, `param1=`, `terminal=false`, `refresh=true`) bind click actions. The plan should keep those params pointed at the companion action runner, not at hand-built shell snippets.

## Decision Gates

- [x] SwiftBar plugin first; native SwiftUI app later if ever.
  - Reason: ships immediately, author's stack, no signing pipeline; CLI contract makes the rewrite cheap. SwiftBar is a cask, so the formula declares it via caveats (formulae cannot depend on casks).

- [x] Plugin language is TypeScript/Node, not bash.
  - Reason: JSON rendering and multi-root aggregation in bash is error-prone; author's primary stack is TS. Node 20+ is the only runtime requirement, declared as a formula dependency.

- [x] Multi-project support via `~/.config/workbranch-companion/config.json` (`{"roots": ["/abs/path", ...]}`).
  - Reason: `workbranch` is project-scoped by cwd; the companion needs explicit roots. Missing config ⇒ helpful menu item pointing at `workbranch-companion init`.

- [x] Accessibility permission is granted to **SwiftBar** (it spawns the plugin → `workbranch focus` → osascript).
  - Reason: TCC attributes automation to the responsible app. The installer's `doctor` explains this; the README shows the System Settings path.

- [ ] Notification *producers* (agent hooks calling `workbranch noti add`) — separate follow-up plan once this UI proves the display loop.
- [ ] Action execution boundary.
  - Impact: memo text, paths, and task names cross from SwiftBar menu text into shell commands.
  - Current evidence: the current product decisions bind click actions directly to `workbranch` commands via SwiftBar params, while the target structure already includes `actions.ts` and `cli.ts`.
  - Recommended default: SwiftBar lines call `workbranch-companion action <verb> --root <root> --task <task> ...`; the action runner uses `child_process.spawn` with argv arrays and `cwd` set to the project root. Render tests assert params, and action tests assert argv construction. Do not embed memo text in shell snippets.
  - Alternative: render direct `workbranch` / `osascript` commands in menu lines. Fewer files, higher quoting and injection risk.
  - Status: unresolved.

- [ ] Minimum CLI version.
  - Impact: the companion must refuse old CLIs that do not have 0015/0016 contracts.
  - Current evidence: 0018 plans a version gate but 0015/0016 release versions are not known yet.
  - Recommended default: leave a placeholder in this plan (`MIN_WORKBRANCH_VERSION = <first release containing 0015 and 0016>`) and set it during 0018 implementation after the CLI release version is known.
  - Alternative: feature-detect by probing `list --json` and `focus --help`. More flexible, but slower and harder to explain in support messages.
  - Status: unresolved.

- [ ] New-workspace action scope.
  - Impact: `workbranch add` can take minutes and run repo setup commands; running it from the wrong project root creates the wrong workspace.
  - Current evidence: multi-project config stores roots explicitly, and workbranch commands are project-scoped by cwd.
  - Recommended default: every menu action carries its project root; `workbranch-companion action add --root <root> --task <name>` validates the name, spawns detached work in that root, logs to a predictable file, and reports completion/failure through a notification.
  - Alternative: infer root from the plugin process cwd. Reject; SwiftBar does not run inside a workbranch project.
  - Status: unresolved.

- [ ] Raycast extension / native app — out of scope.

## Product Decisions

1. **Bar title:** compact glyph + counts, e.g. `⌥4 🔔2` (4 tasks, 2 tasks with notifications); `🔔` segment omitted when zero. Errors render as `⌥!`.
2. **Dropdown, per project root:** header line with project name; one line per task: `task3 — draft-tree 가이드 작성 🔔2` (title truncated ~40 chars, `(no memo)` dimmed when empty, `●` suffix when any repo dirty). Click → `workbranch-companion action focus --root <root> --task task3` (`terminal=false refresh=true`).
3. **Per-task submenu:** `Edit memo…` (action runner opens osascript `display dialog` with current memo as default answer, then calls `workbranch memo <task> <answer>` with argv), `Clear notifications` (→ `noti clear`), `Open in IDE` / `Reveal in Finder` (existing launchers), `Copy path`.
4. **Global items:** `New workspace…` (dialog → validate `^[a-z0-9][a-z0-9-]*$` → spawn detached `workbranch add <name>` from the selected project root with stdout/stderr to `/tmp/workbranch-add-<root-hash>-<name>.log`, then `display notification` on success/failure), `Refresh now`, `Open config`.
5. **Failure visibility:** any `workbranch` invocation failure renders an error menu item with captured stderr — never a blank/empty menu.
6. **`workbranch-companion` installer CLI** (bundled bin): `install` (build artifact → SwiftBar plugins dir as `workbranch.5s.js`, resolving the dir from SwiftBar's `defaults` domain when customized), `uninstall`, `init` (write config skeleton), `doctor` (SwiftBar present? `workbranch` on PATH and ≥ minimum version? Accessibility hint? config valid?).
7. **Version coupling:** the plugin checks `workbranch --version` once per refresh cycle batch and renders a "CLI too old (need ≥ X.Y.Z)" item instead of crashing when the contract predates `list --json`.

## Target File Structure

```text
companion/package.json              # real deps/scripts (esbuild, vitest, typescript) — replaces 0017 placeholder
companion/tsconfig.json
companion/src/index.ts              # entry: config load → spawn list --json per root → render → stdout
companion/src/render.ts             # pure: CompanionState → SwiftBar lines (unit-tested)
companion/src/actions.ts            # pure arg-builders for focus/memo/noti/add + osascript dialog strings (unit-tested)
companion/src/action-runner.ts      # executes menu actions with argv arrays and explicit cwd
companion/src/cli.ts                # workbranch-companion installer/action entry (install/uninstall/init/doctor/action)
companion/src/exec.ts               # thin child_process wrappers (mocked in tests)
companion/test/render.test.ts       # snapshot fixtures: memo/no-memo/noti/dirty/error/empty-config
companion/test/actions.test.ts
companion/README.md                 # install, permissions, troubleshooting
packaging/companion-formula-notes.md# tap follow-up: formula skeleton + caveats (SwiftBar cask, Node dep, Accessibility)
README.md / README.ko.md            # companion section
```

## Implementation Tasks

### Task 1: Scaffold + renderer (TDD)

- [ ] Replace the 0017 placeholder `package.json` with real scripts: `build` (esbuild → `dist/workbranch.5s.js`, node shebang banner, minify off), `typecheck`, `test` (vitest). Commit with `feat(companion): ...` scope (0017 decision).
- [ ] RED: render tests from a fixture state — 4-task project covering memo/no-memo/notification/dirty; assert exact SwiftBar lines including `bash=`, `param1=`, `terminal=false`, and `refresh=true` params pointing at `workbranch-companion action`; error-state fixture renders `⌥!` + stderr item; zero-roots fixture renders the `init` hint.
- [ ] GREEN: implement `render.ts` as a pure function; no IO imports allowed (enforce by keeping `exec.ts` out of its import graph).

### Task 2: Data loading + entry point

- [ ] `index.ts`: read config (`~/.config/workbranch-companion/config.json`), locate `workbranch` (`WORKBRANCH_BIN` env → `command -v` → `/opt/homebrew/bin/workbranch`), run `list --json` per root with a 3s timeout, aggregate into `CompanionState` (per-root errors captured, not thrown), print rendered lines.
- [ ] Version gate: parse `workbranch --version`; below minimum → render upgrade item, skip data calls.
- [ ] Unit-test the aggregation with mocked `exec.ts` (success, timeout, malformed JSON, partial multi-root failure).

### Task 3: Actions (TDD on arg-building)

- [ ] `actions.ts` + `action-runner.ts`: builders produce exact SwiftBar params for `workbranch-companion action`; the runner implements focus, edit-memo dialog (default answer = current memo; cancel ⇒ no-op; result passed as argv, never interpolated), clear-noti, new-workspace (name validation `^[a-z0-9][a-z0-9-]*$`, detached spawn with root-scoped log file, completion notification command), copy path, open IDE/Finder.
- [ ] Unit tests: quoting/escaping (Hangul memo, spaces, quotes), root/task argv construction, invalid workspace names rejected before any spawn.

### Task 4: Installer CLI

- [ ] `cli.ts`: `install` (resolve SwiftBar plugins dir: `defaults read com.ameba.SwiftBar PluginDirectory` fallback `~/Library/Application Support/SwiftBar/Plugins`; copy built bundle as `workbranch.5s.js`, `chmod +x`), `uninstall`, `init` (config skeleton with cwd's project root if it has `.workbranch.config`), `doctor` (checks from Product Decision 6, each with a fix-it hint).
- [ ] Manual checklist: fresh install on the dev machine → menu renders real projects; focus/memo/new-workspace round-trip; kill SwiftBar → relaunch → plugin persists.

### Task 5: Docs + release

- [ ] `companion/README.md`: install (`brew install --cask swiftbar`, `brew install tkhwang/tap/workbranch-companion`, `workbranch-companion install`, grant Accessibility to SwiftBar), troubleshooting (blank menu, `-1728` assistive access, stale Node).
- [ ] `packaging/companion-formula-notes.md`: formula skeleton (installs bundle + bin; `depends_on "node"`; caveats text) for the tap follow-up.
- [ ] Root README/README.ko: companion section with a screenshot placeholder.
- [ ] External follow-up at first release: add `Formula/workbranch-companion.rb` to `tkhwang/homebrew-tap`; publish `workbranch-companion-v0.1.0`; verify the 0017 homebrew-bump companion path updates the formula.

## Risks

- **5s refresh × N roots × `git status` cost.** `list --json` is local-only (0015 decision); if latency shows, lengthen the interval (rename to `workbranch.10s.js`) before adding `--fast` modes.
- **osascript dialog UX is modal and basic.** Acceptable for v1; a native app (future) owns rich input. Dialogs always offer Cancel ⇒ no-op.
- **SwiftBar plugins dir customization drift.** `install` resolves via `defaults` with fallback; `doctor` verifies the bundle is where SwiftBar looks.
- **Contract drift between CLI and plugin.** Version gate (Product Decision 7) + render tests pinned to the 0015 JSON fixture; bump the minimum CLI version whenever the contract changes.
