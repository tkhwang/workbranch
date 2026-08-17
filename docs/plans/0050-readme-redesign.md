# Workbranch README Redesign

## Goal

Redesign `README.md` and `README.ko.md` around one product story: the CLI makes Git worktrees easier to operate, while Companion monitors the tasks running in those worktrees and launches local tools.

## Project Story

- Audience: developers and AI-assisted teams that work across one or more Git repositories.
- One-sentence value: manage every repository for a task under one worktree root, then monitor that work from the macOS menu bar.
- Primary proof: a shared task workspace connected to CLI commands on one side and Companion task monitoring on the other.
- First successful action: install the CLI, run `workbranch init`, and create a task workspace.
- Visual theme: a compact terminal-native system view derived from Companion's Codex palette and Stage Board.

## Selected Direction

Use the approved Shared Task Spine composition.

The hero places the task workspace at the center. The CLI panel on the left shows worktree mutation commands such as `add`, `refresh`, `land`, and `push`. The Companion panel on the right shows PLAN, EXECUTION, and REVIEW monitoring plus Finder, IDE, and terminal actions.

This layout presents CLI and Companion as two surfaces over the same local task state. It avoids describing them as unrelated products or implying that Companion performs Git lifecycle operations.

## Visual System

- Palette: `#121214` background, `#EDEDED` foreground, `#5CC2E0` CLI accent, `#BB9AF7` Companion accent, `#A8A8AD` muted text, and `#414147` rules.
- Typography: system sans-serif for the project name and system monospace for commands, labels, branches, and status.
- Shape: 5px outer and panel radii, 1px rules, and one 2px accent rule across the hero.
- Motif: the shared task root connects worktree control to task monitoring.
- Composition: compact technical density with no gradients, ornamental grid, remote fonts, or heavy shadow.

## Asset

Create one static, language-neutral asset at `assets/readme/hero.svg`.

- Canvas: `1200 × 420` with a full-width `viewBox`.
- GitHub embed: `width="100%"` with descriptive alt text in each README language.
- Desktop target: all content remains inside the canvas and readable at a 900px rendered width.
- Mobile target: the overall CLI → task workspace → Companion relationship remains visible at 360px. Commands and detail remain available in Markdown.
- Accessibility: include `<title>` and `<desc>`. Do not place installation commands or required instructions only inside the image.

Both README variants use the same hero because its copy consists of the product name, commands, filesystem names, and UI labels already used by the product.

## README Structure

Keep the detailed command and workflow sections, but tighten the opening in both languages:

1. Repository name and language switch.
2. Shared Task Spine hero.
3. CI, release, license, and platform badges.
4. A short localized value statement.
5. The existing demo GIF as immediate proof.
6. A concise CLI and Companion role comparison.
7. Quick start and installation.
8. Existing task structure, update, ship, command, Companion, and reference sections.

Remove repeated opening explanations when the hero and role comparison already communicate the same point. Keep commands, compatibility, Git behavior, and source-of-truth details in Markdown.

## Localization

The English and Korean READMEs keep matching section order, command examples, tables, and links. Each language uses natural prose rather than line-by-line literal translation. Product labels and command names remain unchanged.

## Validation

- Run `python3 /Users/tommyhwang/.agents/skills/beautify-github-readme/scripts/audit_readme.py` for both README files.
- Validate SVG XML and reject scripts, `foreignObject`, remote assets, and remote fonts.
- Render the hero at full size, 900px, and 360px; inspect clipping, contrast, and text scale.
- Render both README files through GitHub-flavored Markdown.
- Verify every relative link and image path.
- Run `git diff --check`.

No CLI, Companion, package, or generated distribution file changes are in scope.
