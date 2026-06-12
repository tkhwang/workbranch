# 0017 Monorepo Release Plumbing Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. This plan changes release automation only — no `src/workbranch/**` behavior changes, no `bin/workbranch` regeneration. Verification is config-validation and workflow dry runs; the final acceptance gate is observing one real `v*` release flow end-to-end.

> **Series:** Part 3 of 4 of the menu bar companion initiative. Execution order: 0015 memo/noti/json → 0016 focus command → **0017 (this)** → 0018 companion SwiftBar plugin. **This plan must land alone and be verified by one real `v*` release before 0018's first companion release.** It deliberately contains no companion code; it only prepares the repo to release a second artifact.

**Goal:** Convert the repo's release automation from a single root package to a two-package monorepo: the existing `workbranch` bash CLI keeps its `v*` tags and `Formula/workbranch.rb` brew flow unchanged, and a new `companion/` package releases independently as `workbranch-companion-v*` tags feeding a future `Formula/workbranch-companion.rb`.

**Architecture:** release-please manifest mode with two packages: root (`.`) stays `workbranch` with `include-component-in-tag: false` (existing `v*` tag shape preserved), and `companion/` becomes `workbranch-companion` (`release-type: node`, `include-component-in-tag: true`). `homebrew-bump.yml` branches on tag prefix to decide which tap formula to update, guarded so companion releases are a no-op until the tap formula exists. CI gains a path-filtered companion job.

**Tech Stack:** release-please (manifest/config JSON), GitHub Actions, Homebrew tap `tkhwang/homebrew-tap` (external repo).

**Product fit:** This plan protects the existing CLI release path before the companion exists. The user-facing menu bar work should not start releasing until one normal CLI `v*` release proves that release-please and Homebrew still behave exactly as they did before the repo gained a second package.

---

## Problem Statement

The companion menu bar app (0018) is TypeScript/Node with its own version cadence; coupling its releases to the bash CLI's `v*` stream would force lockstep versions and pollute the CLI changelog. The repo decision (companion initiative) is monorepo + independent brew artifacts, which requires multi-package release plumbing. This is the riskiest infrastructural step of the initiative — a mis-tagged release would break the existing brew pipeline for current users — so it ships alone, before any companion code depends on it.

## Current Repo Evidence

- `release-please-config.json`: single package `"."`, `release-type: simple`, `include-component-in-tag: false`, extra-file version bump into `bin/workbranch` (`x-release-please-version` marker in `WORKBRANCH_VERSION=`).
- `.release-please-manifest.json`: single root entry at the current version.
- `.github/workflows/homebrew-bump.yml`: fires on release publish; **hard-fails unless the tag starts with `v`**; recomputes the tarball sha256 and rewrites `Formula/workbranch.rb` in `tkhwang/homebrew-tap` using `TAP_GITHUB_TOKEN`.
- `.github/workflows/release-please.yml`, `ci.yml`: existing release PR + bash test pipeline.

## Decision Gates

- [x] Root package stays at `"."` — no `cli/` directory move.
  - Reason: moving bash sources would churn every open branch, build script, and test path for zero user value. release-please supports root + subdirectory packages side by side.

- [x] Existing `v*` tag shape is a compatibility contract.
  - Reason: `homebrew-bump.yml` and any user pin parse `v*`. `include-component-in-tag: false` on the root package preserves it exactly.

- [x] Companion package registered now with a placeholder, even though 0018 ships the real code.
  - Reason: plumbing must be provable before the artifact exists; a minimal `companion/package.json` (version 0.0.1, private build stub) lets release-please validate the package without publishing anything meaningful.

- [x] Companion branch of homebrew-bump is guarded until the tap formula exists.
  - Reason: a `workbranch-companion-v*` release must not fail the workflow while `Formula/workbranch-companion.rb` is absent in the tap; guard with a formula-file existence check and a logged skip.

- [ ] Companion CI path filtering mechanism.
  - Impact: a mistaken workflow trigger can skip the bash CLI suite or run npm jobs on every CLI-only PR.
  - Current evidence: GitHub Actions supports `paths` at the workflow trigger level, not as a simple job-level key inside `jobs.<job>`.
  - Recommended default: keep the existing bash `test` job triggers unchanged and add a lightweight path-filter step/job (for example `dorny/paths-filter` or an equivalent git diff script) that controls only the companion job with `if:`. Include `.github/workflows/ci.yml` in the companion filter so workflow edits test the new job.
  - Alternative: split companion CI into a second workflow with `on.pull_request.paths`. Simpler, but it separates release readiness evidence from the main CI page.
  - Status: unresolved.

- [ ] Companion placeholder lockfile.
  - Impact: CI reproducibility and whether `npm ci` can run without fallback noise.
  - Current evidence: the target structure has `companion/package.json` but no lockfile; the task currently says `npm ci || npm install`.
  - Recommended default: commit `companion/package-lock.json` in 0017 even for the placeholder package, then use `npm ci` without fallback. 0018 updates the lockfile when real dependencies arrive.
  - Alternative: avoid a lockfile until 0018 and use `npm install` in CI. Faster to scaffold, weaker as release plumbing evidence.
  - Status: unresolved.

- [ ] Tap repo changes (`tkhwang/homebrew-tap`: add `Formula/workbranch-companion.rb`) — external follow-up, executed alongside 0018's first release.

## Product Decisions

1. **Tag shapes:** CLI `vX.Y.Z` (unchanged); companion `workbranch-companion-vX.Y.Z`.
2. **Changelogs:** root `CHANGELOG.md` stays CLI-only; `companion/CHANGELOG.md` is companion-only. Conventional-commit scoping: commits touching `companion/**` use `feat(companion): ...` so release-please attributes them correctly.
3. **No npm publish.** The companion releases as a GitHub release tarball consumed by the future brew formula; `companion/package.json` is `"private": true`.
4. **CI:** companion job (`npm ci && npm run typecheck && npm test && npm run build`) runs only when `companion/**` changes; bash job untouched.

## Target File Structure

```text
release-please-config.json          # two packages: "." (workbranch) + "companion" (workbranch-companion)
.release-please-manifest.json       # add "companion": "0.0.1"
.github/workflows/homebrew-bump.yml # case "$TAG_NAME": v* → workbranch.rb | workbranch-companion-v* → workbranch-companion.rb (guarded)
.github/workflows/ci.yml            # companion job with paths filter
companion/package.json              # placeholder: private, version 0.0.1, stub scripts (real code arrives in 0018)
companion/package-lock.json          # placeholder lockfile if the CI decision resolves to npm ci
companion/CHANGELOG.md              # seeded by release-please
```

## Implementation Tasks

### Task 1: release-please two-package config

- [ ] Add `companion/package.json` placeholder (`"name": "workbranch-companion"`, `"private": true`, `"version": "0.0.1"`, stub `build`/`test`/`typecheck` scripts that exit 0 with a "placeholder until 0018" note). If the lockfile decision resolves to npm ci, add `companion/package-lock.json` in the same slice.
- [ ] `release-please-config.json`: keep root package entry byte-compatible in behavior (package-name, extra-files, `include-component-in-tag: false`); add `"companion"` entry (`package-name: workbranch-companion`, `release-type: node`, `include-component-in-tag: true`).
- [ ] `.release-please-manifest.json`: add `"companion": "0.0.1"`.
- [ ] Verify: validate against the release-please config schema; run release-please CLI dry-run locally if available, otherwise rely on the bot's PR output on a scratch branch.

### Task 2: homebrew-bump tag branching

- [ ] Replace the `case "$TAG_NAME" in v*) ;; *) exit 1 ;; esac` guard with a dispatch:
  - `workbranch-companion-v*` → target `Formula/workbranch-companion.rb`, strip prefix for the version; **if the formula file does not exist in the tap checkout, log "tap formula not present yet — skipping" and exit 0**.
  - `v*` → current behavior, byte-for-byte tarball/sha256/`workbranch.rb` logic.
  - anything else → fail (unchanged safety).
- [ ] Order matters: match `workbranch-companion-v*` before `v*`? (It must — `v*` would never match it, but keep the specific case first anyway for clarity.)
- [ ] Verify with `act` or a workflow-lint pass; review the diff against the current workflow to confirm the `v*` path is untouched.

### Task 3: CI companion job

- [ ] Add a `companion` job to `ci.yml`: Node 20, working-directory `companion/`, `npm ci` if a lockfile is committed (otherwise the resolved fallback), `npm run typecheck && npm test && npm run build`; gate the job with the resolved path-filter mechanism for `companion/**` plus `.github/workflows/ci.yml`.
- [ ] Confirm the bash job's triggers/matrix are unchanged and still run on CLI-only PRs.

### Task 4: Acceptance — observe one real release

- [ ] Merge this plan's changes alone.
- [ ] Let the next CLI change (e.g. 0015/0016 if not yet released) produce a release-please PR; confirm: PR bumps only the root package, tag is plain `v*`, `bin/workbranch` version marker bumps, homebrew-bump updates `Formula/workbranch.rb`, `brew upgrade workbranch` works.
- [ ] Confirm release-please opened (or can open) a separate `workbranch-companion` release PR and that publishing it would hit the guarded skip path. (Optionally publish `workbranch-companion-v0.0.1` to prove the skip; harmless.) Do not start 0018 release work until this evidence is recorded.

## Risks

- **Mis-tagging breaks the existing brew flow.** Mitigation: root package config preserved exactly; this plan lands alone; acceptance gate is a real observed `v*` release before 0018 begins releasing.
- **release-please manifest-mode migration surprises** (e.g. it wants to re-baseline versions). Mitigation: keep the manifest's root version matching the latest real tag; scratch-branch dry run before merging to the default branch.
- **Conventional-commit scope discipline** — a `feat:` commit touching `companion/**` and `src/**` together would bump both packages. Mitigation: note in AGENTS.md/PR template that companion changes use the `companion` scope and avoid mixed commits.
