# 0004 Homebrew Release Automation Plan

## Objective

Distribute `workbranch` through two channels that both track the latest code, with releases driven automatically from `main`:

1. **Homebrew tap** — `brew install tkhwang/tap/workbranch` (versioned, from GitHub Releases).
2. **curl installer** — `curl -fsSL https://raw.githubusercontent.com/tkhwang/workbranch/main/install.sh | bash` (always main HEAD).

When meaningful changes merge to `main`, a new version is released automatically (gated by a release PR), the GitHub Release is created, and the tap formula is bumped — without manual sha256 editing.

## Decisions already locked (from discussion)

| Topic | Decision |
|---|---|
| Tap name | `tkhwang/tap` → repo `github.com/tkhwang/homebrew-tap`, install as `tkhwang/tap/workbranch` |
| Version automation | release-please (conventional commits, Release PR gate) |
| Formula install | build from source in the formula (`scripts/build-workbranch.sh`), zero runtime deps |
| curl install | serves `main/bin/workbranch` (real-time latest); main kept in sync by CI |
| Casks | none — CLI uses a Formula only |

## Repositories

```text
tkhwang/workbranch        (this repo — source of truth)
  ├── src/workbranch/**          source modules
  ├── bin/workbranch             generated single-file (committed, kept fresh by CI)
  ├── install.sh                 curl installer (already serves main HEAD)
  ├── packaging/homebrew/workbranch.rb   staging copy of the formula
  ├── .github/workflows/         ci + release-please + formula-bump
  ├── release-please-config.json
  └── .release-please-manifest.json

tkhwang/homebrew-tap      (new repo — the brew tap)
  └── Formula/workbranch.rb      the live formula brew installs from
```

The repo's `packaging/homebrew/workbranch.rb` is the **authoring/staging** copy. The live formula lives in the tap repo; the bump workflow keeps the tap copy in sync on each release.

## Automation flow

```text
feat/fix commits ── PR ──> main
                            │
                            ├─ CI (on PR & push): build, freshness, tests, shellcheck
                            │
                            ▼
                   release-please watches main
                            │  opens/updates "Release PR" (version + CHANGELOG)
                            ▼
              [you] merge the Release PR  ──> tag vX.Y.Z + GitHub Release
                            │
                            ▼
                 formula-bump workflow (on release published)
                            │  compute tarball sha256
                            │  rewrite url + sha256 in Formula/workbranch.rb
                            ▼
                   push to tkhwang/homebrew-tap
                            │
                            ▼
              brew install tkhwang/tap/workbranch  (latest release)

curl install.sh ── always reads main/bin/workbranch ── latest, independent of releases
```

## Why curl-latest already works

`install.sh` downloads `main/bin/workbranch` via raw.githubusercontent. So "latest" only requires that `main`'s committed `bin/workbranch` always matches `src/`. The test suite already enforces this: `tests/run.sh` → `test_generated_workbranch_is_up_to_date` rebuilds and `cmp`s against the committed file. **Running `tests/run.sh` in CI on every PR is the freshness guarantee** — no auto-commit machinery needed.

## Implementation phases

### Phase 1 — CI quality gate (`.github/workflows/ci.yml`)
- Triggers: `pull_request`, `push` to `main`.
- Steps: checkout → `bash -n` syntax check (bin/workbranch, install.sh, tests/run.sh) → `./tests/run.sh` (includes freshness + integration) → `shellcheck` on `src/workbranch/**`, `scripts/**`, `install.sh`.
- Outcome: stale `bin/workbranch` or broken behavior blocks merge → main is always installable via curl.
- Status: completed — added `.github/workflows/ci.yml`; verified with `./scripts/build-workbranch.sh`, `/bin/bash -n bin/workbranch install.sh tests/run.sh`, `./tests/run.sh` (`Tests passed: 60`), ShellCheck on installer/scripts/source modules, and `git diff --check`.

### Phase 2 — release-please (`.github/workflows/release-please.yml` + config)
- `release-please-config.json`: `release-type: simple`, package at repo root, changelog on.
- `.release-please-manifest.json`: seed current version.
- Workflow on `push` to `main` runs `googleapis/release-please-action`, maintaining the Release PR and, on its merge, creating tag + GitHub Release.
- Status: completed — added `.github/workflows/release-please.yml`, `release-please-config.json`, and `.release-please-manifest.json` seeded at `0.1.0`; uses `RELEASE_PLEASE_TOKEN` so release-created events can trigger downstream workflows. Verified JSON/workflow structure plus `./scripts/build-workbranch.sh`, `/bin/bash -n bin/workbranch install.sh tests/run.sh`, `./tests/run.sh` (`Tests passed: 60`), ShellCheck, and `git diff --check`.

### Phase 3 — formula bump (`.github/workflows/homebrew-bump.yml`)
- Trigger: `release: published`.
- Steps: derive tag + tarball URL (`.../archive/refs/tags/<tag>.tar.gz`) → download → `sha256sum` → rewrite `url`/`sha256` in the tap's `Formula/workbranch.rb` → commit & push to `tkhwang/homebrew-tap` using the cross-repo credential.
- Also updates the staging copy `packaging/homebrew/workbranch.rb` in this repo for parity (optional commit back).
- Status: completed — added `.github/workflows/homebrew-bump.yml`; on `release: published`, it checks out `tkhwang/homebrew-tap` with `TAP_GITHUB_TOKEN`, computes the GitHub tag tarball SHA, rewrites the tap `Formula/workbranch.rb`, and pushes a conventional `chore(workbranch): ...` commit when changed. Staging formula parity remains in Phase 4 rather than an automatic commit-back loop. Verified the formula rewrite logic with a local fixture plus `./scripts/build-workbranch.sh`, `/bin/bash -n bin/workbranch install.sh tests/run.sh`, `./tests/run.sh` (`Tests passed: 60`), ShellCheck, and `git diff --check`.

### Phase 4 — formula (build-from-source)
- Update `packaging/homebrew/workbranch.rb` and seed the tap's `Formula/workbranch.rb`:
  ```ruby
  def install
    system "scripts/build-workbranch.sh"
    bin.install "bin/workbranch"
  end
  test do
    assert_match "Usage:", shell_output("#{bin}/workbranch help")
  end
  ```
- GitHub source tarball contains `src/`, `scripts/` → build runs in Homebrew's sandbox with no external deps.
- Status: completed — updated `packaging/homebrew/workbranch.rb` to run `scripts/build-workbranch.sh` before installing `bin/workbranch`. Verified Ruby syntax and actual Homebrew install/test behavior via a temporary local tap and local source tarball (`brew install --build-from-source`, `brew test`, `workbranch help`), then confirmed cleanup left no `workbranch` formula installed and no temp tap. Also reran `./scripts/build-workbranch.sh`, `/bin/bash -n bin/workbranch install.sh tests/run.sh`, `./tests/run.sh` (`Tests passed: 60`), ShellCheck, and `git diff --check`.

### Phase 5 — supporting files & docs
- Add `LICENSE` (MIT) — required because the formula declares `license "MIT"` and none exists today.
- README: add Homebrew + curl install sections.
- Bootstrap the `tkhwang/homebrew-tap` repo with `Formula/workbranch.rb` and a short README.
- Status: completed — added `LICENSE`, updated README install instructions for `brew install tkhwang/tap/workbranch` plus the curl installer, created public `tkhwang/homebrew-tap`, and seeded it with `Formula/workbranch.rb` + README. Tap repo was committed and pushed through the personal SSH alias `git@github.com-personal:tkhwang/homebrew-tap.git` with personal git identity. Verified `gh repo view`, fresh clone via the personal SSH alias, formula Ruby syntax, and `brew tap tkhwang/tap`.

## Decision Gates

> Resolve these before implementing. One question at a time; recommended defaults included.

- [ ] **DG1 — Cross-repo push credential** (workbranch Actions → homebrew-tap)
  - Impact: security surface + setup; the formula-bump workflow cannot push to the tap repo without it.
  - Evidence: no existing workflows/secrets; standard `GITHUB_TOKEN` cannot push to a *different* repo.
  - Options: A) fine-grained PAT (contents:write on homebrew-tap only) as a secret (Recommended); B) deploy key on tap repo; C) GitHub App.
  - Recommended default: A — fine-grained PAT scoped to just `homebrew-tap`, stored as `TAP_GITHUB_TOKEN`.
  - Recommended rationale: least-privilege, simplest to set up, easy to rotate; deploy keys are per-repo SSH that's clumsier in Actions; a GitHub App is overkill for one tap. Choose B only if org policy forbids PATs.
  - Status: resolved: A — use a fine-grained PAT scoped to `tkhwang/homebrew-tap` with contents write, stored in the `workbranch` repo as `TAP_GITHUB_TOKEN`.

- [ ] **DG2 — Commit convention switch (enable release-please)**
  - Impact: whether automatic versioning works at all; AGENTS.md currently documents emoji-prefixed commits, which the default parser won't read.
  - Evidence: AGENTS.md "emoji-prefixed Conventional Commit style"; recent history `🐛 fix(...)`. You confirmed emoji can be dropped.
  - Options: A) switch to plain Conventional Commits + update AGENTS.md, no CI enforcement (Recommended); B) same + add commitlint PR check; C) keep emoji + configure a custom release-please parser.
  - Recommended default: A — adopt `feat:`/`fix:`/`feat!:` etc., update AGENTS.md, rely on discipline.
  - Recommended rationale: smallest change that makes release-please reliable; commitlint can be added later if drift appears; custom emoji parsing is fragile and undermines the standard tooling everyone recognizes.
  - Status: resolved: A — switch to plain Conventional Commits without emoji prefixes and update `AGENTS.md`; do not add commitlint in this slice.

- [ ] **DG3 — `homebrew-tap` repo bootstrap (who/how + initial state)**
  - Impact: introduces a new external repo (a new "artifact"); install command depends on it existing with a valid formula.
  - Evidence: repo does not exist yet; remote is `tkhwang/workbranch`.
  - Options: A) I create `tkhwang/homebrew-tap` via `gh`, seed `Formula/workbranch.rb` + README, you push the first real release to populate sha256 (Recommended); B) you create it manually, I only provide file contents.
  - Recommended default: A, with the seeded formula carrying a placeholder url/sha until the first release bumps it.
  - Recommended rationale: fewer manual steps and guarantees the layout/name matches the workflow; you keep control by approving the `gh repo create`. Pick B if you prefer to own repo creation/visibility settings yourself.
  - Status: resolved: A — create `tkhwang/homebrew-tap` via `gh`, seed `Formula/workbranch.rb` + README, and keep the seeded formula as a placeholder until the first release bump writes the real release URL/sha.
  - Implementation constraint: this machine has both work and personal GitHub SSH identities. Personal GitHub operations must use the `github.com-personal` SSH host alias (for example `git@github.com-personal:tkhwang/homebrew-tap.git`) and set the intended personal `git config user.name` / `user.email` before committing or pushing the tap repo.

- [ ] **DG4 — Initial version seed**
  - Impact: the first released version number and the `.release-please-manifest.json` seed.
  - Evidence: no tags/VERSION today; formula stub used `v0.0.0`.
  - Options: A) seed `0.1.0` and let the first release cut `0.1.0`/`0.1.1` (Recommended); B) seed `0.0.0` and start from `0.0.1`.
  - Recommended default: A — `0.1.0` signals "first usable release" without implying 1.0 stability.
  - Recommended rationale: conventional for a tool that's feature-complete-ish but pre-stable; trivially reversible, so low stakes.
  - Status: resolved: A — seed `0.1.0` in `.release-please-manifest.json` and start the first usable release on the `0.1.x` line.

- [ ] **DG5 — Release-please token and downstream workflow trigger**
  - Impact: whether the `release: published` Homebrew bump workflow actually runs after release-please creates a GitHub Release.
  - Evidence: release-please-action docs state that resources created with the default `GITHUB_TOKEN` do not trigger future workflow runs, including workflows triggered by release events; they recommend a PAT when downstream workflows must run.
  - Options: A) use a second fine-grained PAT secret for release-please, scoped to `tkhwang/workbranch` with contents/pull-request/issue permissions as needed (Recommended); B) broaden `TAP_GITHUB_TOKEN` to cover both `workbranch` and `homebrew-tap`; C) keep default `GITHUB_TOKEN` and manually trigger/run the formula bump after releases.
  - Recommended default: A — store the workbranch release token separately, for example as `RELEASE_PLEASE_TOKEN`.
  - Recommended rationale: separating release creation from tap pushing keeps least-privilege boundaries clear. Broadening the tap token creates unnecessary cross-repo blast radius, while default `GITHUB_TOKEN` undermines the no-manual-sha automation goal because the release-published bump workflow may not fire.
  - Status: resolved: A — use a separate fine-grained PAT secret named `RELEASE_PLEASE_TOKEN`, scoped to `tkhwang/workbranch`, so release-created events can trigger the downstream Homebrew bump workflow.

## Out of scope / follow-ups
- Optional `WORKBRANCH_VERSION` env in `install.sh` to fetch a pinned release tarball (curl currently = latest only).
- commitlint / PR title lint enforcement.
- Bottle (precompiled) builds — unnecessary for a pure-bash formula.

## Verification
- `ci.yml` green on a test PR (tests + shellcheck + freshness).
- Dummy tag → release-please opens a Release PR; merging it creates a Release.
- formula-bump pushes a correct `url`/`sha256` to the tap.
- `brew install tkhwang/tap/workbranch` installs and `workbranch help` works; `brew test` passes.
- curl installer fetches a working `bin/workbranch` from `main`.

## Source contract
No separate spec: this is build/release infrastructure, not user-facing CLI behavior. AGENTS.md packaging note and README install sections are the user-facing surface.
