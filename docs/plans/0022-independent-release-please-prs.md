# 0022 Independent Release Please PRs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `workbranch` CLI와 `workbranch-companion`이 같은 repository 안에 있어도 release-please가 각각 독립 release PR과 독립 version bump를 만들도록 고친다.

**Architecture:** 현재 `release-please-config.json`은 root package(`.`)와 companion package(`companion`)를 모두 선언하지만 top-level `separate-pull-requests`가 없어 release-please가 후보 PR을 하나의 manifest PR로 merge한다. 변경은 release-please 설정을 최소 수정해 component별 PR 분리를 켜고, root package component identity를 명시해 이전처럼 workbranch 전용 release branch/PR이 예측 가능하게 생성되도록 한다. `companion-release.yml`은 release published 후속 배포 workflow이므로 PR 분리 로직에는 손대지 않는다.

**Tech Stack:** release-please action v4 / release-please 17.x manifest mode, GitHub Actions, JSON config, 기존 Bash CLI build/test suite, Swift companion build/test.

---

## 문제 요약

현재 닫힌 PR과 workflow log 기준으로 release 동작은 다음과 같다.

- PR #53은 companion-only release였다. 변경 파일은 `.release-please-manifest.json`, `companion/CHANGELOG.md`, `companion/scripts/build-app.sh`뿐이고 `workbranch` root release는 없었다.
- PR #55는 root package와 companion package가 모두 releasable 상태였지만 release-please가 `Merging 2 pull requests`를 수행한 뒤 `chore: release main` PR 하나로 묶었다.
- 현재 `release-please-config.json`에는 `packages["."]`와 `packages["companion"]`가 모두 있지만 top-level `separate-pull-requests`가 없다.
- `companion-release.yml`은 `workbranch-companion-v*` GitHub Release published event 뒤에 앱 zip/cask를 처리한다. release PR 생성 책임이 없다.

따라서 root cause는 companion workflow가 `workbranch` release를 막는 것이 아니라, manifest releaser의 기본 병합 동작을 그대로 사용하고 있는 것이다.

## 현재 파일 근거

- `release-please-config.json:3-4`: repo 전체 기본 release type과 tag component 포함 여부를 정의한다.
- `release-please-config.json:5-36`: `.`와 `companion` 두 package가 선언되어 있다.
- `release-please-config.json:6-23`: root package는 `package-name: workbranch`와 `bin/workbranch` extra-file updater를 가진다.
- `release-please-config.json:24-35`: companion package는 `component: workbranch-companion`, component tag, package-relative `scripts/build-app.sh` extra-file updater를 가진다. 실제 repository 파일 경로는 `companion/scripts/build-app.sh`다.
- `.github/workflows/release-please.yml:3-6`: `main` push에서 release-please를 실행한다.
- `.github/workflows/release-please.yml:21-24`: config/manifest 파일만 넘긴다. PR 분리 여부는 workflow가 아니라 config가 결정한다.
- `.github/workflows/companion-release.yml:3-22`: companion GitHub Release published event 또는 manual dispatch에서만 실행된다.

## Decision Gates

- [x] **DG1 — root release PR identity**
  - Impact: release PR title/branch identity and any title/branch-based review or automation expectations.
  - Current evidence: `release-please-config.json` root package has no `component`; current repo grep found no `.github`/`scripts` automation depending on `chore: release main`; open release PR list is empty.
  - Decision: add `component: "workbranch"` to `packages["."]`.
  - Rationale: keeps public root tags as `vX.Y.Z` via `include-component-in-tag: false` while making independent root release PR identity explicit.
  - Status: resolved by user: A — add `component: "workbranch"`.

## 결정 사항

- [x] **top-level `separate-pull-requests: true`를 사용한다.**
  - 이유: manifest mode의 기본은 package 후보들을 하나의 release PR로 합치는 동작이다. 기대 동작은 package별 독립 PR이므로 release-please가 제공하는 정식 옵션을 사용한다.

- [x] **root package에 `component: "workbranch"`를 명시한다.**
  - 이유: 현재 log에서 root 후보의 `component`가 빈 값으로 잡혀 group PR 제목 경고가 발생했다. 독립 PR 모드에서는 root PR branch/title이 예측 가능해야 하므로 root component identity를 명시한다.
  - tag는 기존 public contract인 `vX.Y.Z`를 유지해야 하므로 root package는 `include-component-in-tag: false`를 유지한다.

- [x] **`companion-release.yml`은 수정하지 않는다.**
  - 이유: 해당 workflow는 release PR 생성기가 아니라 companion release published 후속 배포기다. PR 분리 문제를 여기서 고치면 책임 경계가 흐려진다.

- [x] **release-please PR branch naming만으로 성공을 판단하지 않는다.**
  - 성공 기준은 package별 독립 open PR 개수와 각 PR의 변경 파일/본문이다. branch 이름은 release-please 내부 구현 변화 가능성이 있으므로 보조 증거로만 둔다.

## Decision Grill Notes

- **No further user-blocking decision: existing combined PR handling.** Current open PR list is empty, so there is no live combined `chore: release main` PR to choose how to close. The plan keeps this as a post-merge verification gate for future/open PRs.
- **No further user-blocking decision: verification depth.** For the config-only implementation, correctness is defined by JSON config assertions, title/branch automation grep, diff check, and post-merge release-please evidence. CLI/Swift build suites are intentionally skipped unless the implementation diff expands beyond release config/docs.
- **No further user-blocking decision: companion workflow ownership.** Repo evidence shows `.github/workflows/companion-release.yml` is release-published/tag scoped, not release PR generation. The plan leaves it unchanged.
- **Follow-up/later slice:** if README/docs-only changes should trigger root CLI releases, revisit root `exclude-paths`; this plan preserves the 0020 release-plumbing decision to exclude docs/README from root release candidates.

## 목표 동작

1. `src/workbranch/**`, `scripts/workbranch-sources.txt`, `bin/workbranch`, `tests/**` 등 root package 대상 releasable commit이 `main`에 들어오면 `workbranch` release PR이 별도로 생성된다.
2. `companion/**` 대상 releasable commit이 `main`에 들어오면 `workbranch-companion` release PR이 별도로 생성된다.
3. 같은 merge commit이 root와 companion 양쪽 path를 모두 건드려도 release-please는 하나의 combined PR이 아니라 두 개의 PR을 만든다.
4. root release tag는 계속 `vX.Y.Z` 형식이다.
5. companion release tag는 계속 `workbranch-companion-vX.Y.Z` 형식이다.
6. companion release가 published되면 기존처럼 `.github/workflows/companion-release.yml`이 companion tag에서만 실행되고, root `v*` release에서는 skip된다.

## 파일 구조

```text
release-please-config.json              # 수정: top-level separate-pull-requests, root component 명시
.github/workflows/release-please.yml    # 변경 없음: config-file/manifest-file 사용 유지
.github/workflows/companion-release.yml # 변경 없음: published companion release 후속 배포 유지
docs/plans/0022-independent-release-please-prs.md # 이 계획 문서
```

## 구현 작업

### Task 1: release-please config를 독립 PR 모드로 전환

**Files:**
- Modify: `release-please-config.json`

- [x] **Step 1: JSON syntax baseline 확인**

Run:

```bash
python3 -m json.tool release-please-config.json >/tmp/workbranch-release-please-config.before.json
```

Expected:

```text
# exit 0, stdout redirected, stderr empty
```

- [x] **Step 2: `release-please-config.json`을 다음 내용으로 교체**

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "release-type": "simple",
  "include-component-in-tag": false,
  "separate-pull-requests": true,
  "packages": {
    ".": {
      "package-name": "workbranch",
      "component": "workbranch",
      "include-component-in-tag": false,
      "exclude-paths": [
        "companion",
        ".github",
        "docs",
        "README.md",
        "README.ko.md",
        "release-please-config.json",
        ".release-please-manifest.json"
      ],
      "extra-files": [
        {
          "type": "generic",
          "path": "bin/workbranch"
        }
      ]
    },
    "companion": {
      "package-name": "workbranch-companion",
      "component": "workbranch-companion",
      "release-type": "simple",
      "include-component-in-tag": true,
      "extra-files": [
        {
          "type": "generic",
          "path": "scripts/build-app.sh"
        }
      ]
    }
  }
}
```

- [x] **Step 3: JSON syntax와 핵심 설정을 검증**

Run:

```bash
python3 - <<'PY'
import json
from pathlib import Path
cfg = json.loads(Path('release-please-config.json').read_text())
assert cfg['separate-pull-requests'] is True
root = cfg['packages']['.']
companion = cfg['packages']['companion']
assert root['package-name'] == 'workbranch'
assert root['component'] == 'workbranch'
assert root['include-component-in-tag'] is False
assert {'type': 'generic', 'path': 'bin/workbranch'} in root['extra-files']
assert companion['package-name'] == 'workbranch-companion'
assert companion['component'] == 'workbranch-companion'
assert companion['include-component-in-tag'] is True
assert {'type': 'generic', 'path': 'scripts/build-app.sh'} in companion['extra-files']
print('release-please config ok')
PY
```

Expected:

```text
release-please config ok
```

- [ ] **Step 4: Commit — safety gate, not executed**

```bash
git add release-please-config.json docs/plans/0022-independent-release-please-prs.md
git commit -m "fix(release): split workbranch and companion release PRs"
```

Commit body should use the repo Lore protocol if a body is added:

```text
Constraint: release-please manifest mode groups package candidates unless separate PR mode is enabled
Confidence: high
Scope-risk: narrow
Tested: python3 JSON config assertions
Not-tested: live GitHub PR creation until merged to main
```

### Task 2: Local release-please dry-run validation

**Files:**
- No source changes expected.
- Temporary output only under `/tmp`.

- [x] **Step 1: Check release-please CLI availability**

Run:

```bash
npx --yes release-please --version
```

Expected:

```text
# Prints a release-please version and exits 0.
```

If network/npm is unavailable, record the exact error and continue with Task 3. Do not change repository config to work around local npm availability.

- [ ] **Step 2: Run dry-run against current repository state without creating PRs — partial only**

Run:

```bash
GITHUB_TOKEN="${GITHUB_TOKEN:-${RELEASE_PLEASE_TOKEN:-}}" \
npx --yes release-please release-pr \
  --repo-url=tkhwang/workbranch \
  --target-branch=main \
  --config-file=release-please-config.json \
  --manifest-file=.release-please-manifest.json \
  --dry-run 2>&1 | tee /tmp/workbranch-release-please-dry-run.log
```

Expected:

```text
# exit 0 if a valid GitHub token is available
# meaningful only when HEAD/main has pending releasable commits for both root and companion paths
# output includes separate strategy/candidate handling for path . and path companion only in that mixed pending-commit case
# output does not include "Merging 2 pull requests" for the independent-PR scenario
```

If there are no pending releasable commits for one or both packages, dry-run can only prove that the config parses and the command runs; it cannot prove two-PR behavior. If the command exits non-zero because no token is available, keep the log as partial evidence and rely on Task 4 after merge.

- [ ] **Step 3: Inspect dry-run log for independent mode signal — partial only**

Run:

```bash
rg -n 'separate|Building candidate release pull request for path|Merging [0-9]+ pull requests|path: \.|path: companion' /tmp/workbranch-release-please-dry-run.log
```

Expected:

```text
# path . and path companion are both visible when releasable commits exist
# "Merging 2 pull requests" is absent after separate-pull-requests is enabled
```

### Task 3: Repository verification before merging the config PR

**Files:**
- No additional source changes expected.

- [x] **Step 1: JSON config assertion**

Run the same assertion from Task 1 Step 3 after all edits are complete:

```bash
python3 - <<'PY'
import json
from pathlib import Path
cfg = json.loads(Path('release-please-config.json').read_text())
assert cfg['separate-pull-requests'] is True
root = cfg['packages']['.']
companion = cfg['packages']['companion']
assert root['package-name'] == 'workbranch'
assert root['component'] == 'workbranch'
assert root['include-component-in-tag'] is False
assert {'type': 'generic', 'path': 'bin/workbranch'} in root['extra-files']
assert companion['package-name'] == 'workbranch-companion'
assert companion['component'] == 'workbranch-companion'
assert companion['include-component-in-tag'] is True
assert {'type': 'generic', 'path': 'scripts/build-app.sh'} in companion['extra-files']
print('release-please config ok')
PY
```

Expected:

```text
release-please config ok
```

- [x] **Step 2: Whitespace/diff guard**

Run:

```bash
git diff --check
git diff -- release-please-config.json docs/plans/0022-independent-release-please-prs.md
```

Expected:

```text
# git diff --check exits 0
# diff only contains release config and this plan document
```

- [x] **Step 3: Skip unrelated build suites unless the diff expands**

Do not run `./scripts/build-workbranch.sh`, `./tests/run.sh`, or Swift companion tests for the config-only diff. This change does not alter Bash CLI source, generated `bin/workbranch`, Swift source, or runtime behavior. If implementation expands beyond `release-please-config.json` and this plan document, reintroduce the matching suite for the changed surface.

### Task 4: Post-merge live GitHub verification

**Files:**
- No repository changes unless verification exposes a defect.

- [ ] **Step 1: After the config PR merges to `main`, inspect the release-please run**

Run:

```bash
gh run list --repo tkhwang/workbranch --workflow release-please.yml --limit 5
```

Expected:

```text
# latest main-push release-please run completed successfully
```

- [ ] **Step 2: Check transition of any pre-existing combined release PR**

Before judging the new behavior, inspect whether a combined `chore: release main` PR already exists from the old config:

```bash
gh pr list --repo tkhwang/workbranch --state open --search 'chore: release main in:title' \
  --json number,title,headRefName,files,url \
  --jq '.[] | {number,title,headRefName,files:[.files[].path],url}'
```

Expected:

```text
# if no old combined PR exists, output is empty and no transition cleanup is needed
# if an old combined PR exists, record its number and files before the next release-please run
```

After the new config reaches `main` and release-please runs once, re-run the same command. Expected result is one of:

```text
# old combined PR is closed/replaced by separate package PRs
# old combined PR remains open but no longer updates; close it manually after confirming separate PRs exist
# old combined PR remains open and keeps updating; treat as a release-please config defect and stop before merging any release PR
```

- [ ] **Step 3: Confirm no combined release PR is created for mixed changes**

For a future merge that touches both root and companion paths, run:

```bash
gh pr list --repo tkhwang/workbranch --state open --search 'autorelease: pending' \
  --json number,title,headRefName,files,url \
  --jq '.[] | {number,title,headRefName,files:[.files[].path],url}'
```

Expected:

```text
# one open release PR contains root files only:
#   .release-please-manifest.json, CHANGELOG.md, bin/workbranch
# one open release PR contains companion files only:
#   .release-please-manifest.json, companion/CHANGELOG.md, companion/scripts/build-app.sh
# no single PR contains both CHANGELOG.md and companion/CHANGELOG.md
```

- [ ] **Step 4: Confirm tags after merging release PRs**

Run after each release PR is merged:

```bash
gh release list --repo tkhwang/workbranch --limit 10
```

Expected:

```text
# workbranch release uses vX.Y.Z
# companion release uses workbranch-companion-vX.Y.Z
```

- [ ] **Step 5: Confirm companion release workflow remains correctly scoped**

Run:

```bash
gh run list --repo tkhwang/workbranch --workflow companion-release.yml --limit 5
```

Expected:

```text
# workbranch-companion-v* release events run build-and-publish
# root v* release events are skipped by the existing startsWith(github.event.release.tag_name, 'workbranch-companion-v') guard
```

## Acceptance Criteria

- [ ] Existing open release PRs are checked before merge; any old combined `chore: release main` PR is either replaced, closed, or explicitly handled before merging new release PRs.
- [ ] `release-please-config.json` has top-level `"separate-pull-requests": true`.
- [ ] `packages["."].component` is `"workbranch"`.
- [ ] `packages["."].include-component-in-tag` remains `false`, preserving `vX.Y.Z` root tags.
- [ ] `packages["companion"].include-component-in-tag` remains `true`, preserving `workbranch-companion-vX.Y.Z` tags.
- [ ] `packages["."].extra-files` still updates `bin/workbranch`.
- [ ] `packages["companion"].extra-files` still contains package-relative `scripts/build-app.sh`, which updates repository file `companion/scripts/build-app.sh`.
- [ ] `.github/workflows/companion-release.yml` is unchanged unless a separate defect is found.
- [ ] Local JSON assertion command prints `release-please config ok`.
- [ ] `git diff --check` exits 0.
- [ ] After merge to `main`, a mixed root+companion releasable change creates two release PRs, not one combined PR.

## Risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Root component identity changes PR title/branch shape unexpectedly | Release PR still works, but reviewer expectation or title-grep automation can break | Add `component: "workbranch"` explicitly, search workflows/scripts for release PR title assumptions before merge, and judge success by files/body rather than branch name alone |
| `exclude-paths` hides root-relevant README/docs release notes | Root release may omit docs-only commits | Keep current exclude policy in this plan; if docs-only releases are desired, create a separate plan because it changes release semantics |
| Dry-run cannot run locally without token/network or without mixed pending commits | Local proof incomplete or misleading | Treat dry-run as optional partial evidence; only use it as two-PR evidence when both packages have pending releasable commits; live GitHub Actions run after merge is the authoritative gate |
| Two release PRs both edit `.release-please-manifest.json` | Merge order may require release-please to refresh the remaining PR | Expected release-please behavior is to update open PRs on later main pushes; verify remaining PR after first release PR merge |
| Companion published release still triggers app distribution | Desired behavior, but root release must not run companion distribution | Keep `companion-release.yml` tag guard and verify root `v*` release run is skipped |

## Verification checklist

First check whether any local or CI automation assumes the old combined PR title:

```bash
rg -n 'chore: release main|release-please--branches--main|autorelease: pending' .github scripts docs README.md README.ko.md
```

Expected: any hits are reviewed. Tag-based workflows such as `companion-release.yml` are not affected by PR title changes.

Then validate config shape:

```bash
python3 - <<'PY'
import json
from pathlib import Path
cfg = json.loads(Path('release-please-config.json').read_text())
assert cfg['separate-pull-requests'] is True
assert cfg['packages']['.']['component'] == 'workbranch'
assert cfg['packages']['.']['include-component-in-tag'] is False
assert cfg['packages']['companion']['component'] == 'workbranch-companion'
assert cfg['packages']['companion']['include-component-in-tag'] is True
print('release-please config ok')
PY
git diff --check
```

Optional, when GitHub token/npm are available:

```bash
GITHUB_TOKEN="${GITHUB_TOKEN:-${RELEASE_PLEASE_TOKEN:-}}" \
npx --yes release-please release-pr \
  --repo-url=tkhwang/workbranch \
  --target-branch=main \
  --config-file=release-please-config.json \
  --manifest-file=.release-please-manifest.json \
  --dry-run
```

## Execution Evidence

- Task 1 Step 1: `python3 -m json.tool release-please-config.json >/tmp/workbranch-release-please-config.before.json` exited 0 (`baseline-json-ok`).
- Task 1 Step 2: `release-please-config.json` now has top-level `"separate-pull-requests": true`, root `component: "workbranch"`, root `include-component-in-tag: false`, and unchanged companion package-relative `scripts/build-app.sh` extra-file.
- Task 1 Step 3 / Task 3 Step 1: JSON assertion printed `release-please config ok`.
- Task 2 Step 1: `npx --yes release-please --version` printed `17.9.0`.
- Task 2 Step 2/3: non-local dry-run with explicit `gh auth token` exited 0 but fetched config from `main`, so it only proves remote release-please access and current no-pending-release state (`Would open 0 pull requests`). `--local --local-path .` is blocked in this linked worktree because release-please tries `git checkout main` and `main` is already checked out at `/Users/tommyhwang/Documents/git-tkhwang/workbranch/_base/workbranch`. Treat dry-run as partial evidence only; post-merge GitHub run remains authoritative.
- Task 3 Step 2: `git diff --check` exited 0. Title/branch automation grep found only this plan document; no `.github`/`scripts` dependency on `chore: release main` was found.
- Task 3 Step 3: CLI/Swift suites intentionally skipped because the diff is config/doc only.
- Task 4 pre-check: current open combined `chore: release main` PR check returned empty output. Full Task 4 remains post-merge verification.
- Commit/push were not executed because plan-execute safety gates stop before git commit/push without explicit user request.

## Rollback plan

If independent PR mode creates unusable release PRs, revert only the `release-please-config.json` change from Task 1:

```bash
git revert <commit-that-added-separate-pull-requests>
```

Rollback returns to current combined manifest PR behavior. It does not alter existing tags/releases.

## Self-review

- Spec coverage: Covers the user expectation that `workbranch` and `companion` source changes submit independent release PRs and bump versions independently.
- Placeholder scan: No placeholder or unspecified implementation step remains.
- Verification coverage: Includes JSON assertions, diff checks, optional release-please dry-run with its evidence limits, open combined PR transition checks, and live GitHub post-merge checks.
