# 0038 모노레포 앱 디렉터리 단축 리네임 (`apps/cli` · `apps/companion`)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. 이 plan은 동작 변경이 아니라 경로 리네임이므로 TDD보다 **기존 테스트/CI를 green으로 유지하는 회귀 방지**가 핵심이다. 디렉터리 이동은 반드시 `git mv`로 히스토리를 보존한다. Bash 산출물(`bin/workbranch`)은 손으로 고치지 말고 `apps/cli/scripts/build-workbranch.sh`로 재빌드한다. `pnpm-lock.yaml`은 손으로 고치지 말고 `pnpm install`로 재생성한다.

**Goal:** 모노레포 내부 앱 디렉터리를 짧은 이름으로 통일한다: `apps/workbranch-cli → apps/cli`, `apps/workbranch-companion → apps/companion`. 외부에 노출되는 식별자(바이너리 이름 `workbranch`, npm scope `@workbranch/*`, release-please component/tag `workbranch`·`workbranch-companion`, Homebrew formula `workbranch`, 앱 번들 `WorkbranchCompanion.app`)는 **전부 그대로 유지**한다. "내부는 짧게, 외부 노출 지점에서만 풀네임" 원칙을 코드/설정/CI/문서 전반에 일관 적용한다.

**Architecture:** 순수 경로 리네임이며 동작·contract·external identity는 불변이다. 변경은 (1) `git mv` 2건, (2) 경로 문자열을 하드코딩한 live 설정/스크립트/CI/문서의 일괄 치환, (3) 빌드·lock 산출물 재생성으로 구성된다. release-please는 **경로 key**(내부)와 **component/package-name**(외부 tag)을 분리 관리하므로, manifest/config의 경로 key만 바꾸고 component/package-name은 유지하면 tag 연속성(`workbranch-companion-vX.Y.Z`)이 보존된다. `pnpm-workspace.yaml`은 glob(`apps/*`)이라 변경 불필요. 과거 plan 문서(`docs/plans/0032~0037`)는 그 시점의 사실 기록이므로 재작성하지 않는다.

**Tech Stack:** pnpm workspace(glob `apps/*`/`packages/*`), 순수 Bash CLI(`apps/cli`, package.json 없음), Tauri+React Companion(`@workbranch/companion`), `@workbranch/contract`, release-please(simple, separate-PRs), GitHub Actions(`ci.yml`/`companion-ci.yml`/`companion-release.yml`), Homebrew formula, `git mv`.

---

## 문제

- 모노레포 컨텍스트(`apps/`) 안에서 디렉터리 이름이 `workbranch-cli`/`workbranch-companion`이라 `workbranch/apps/workbranch-cli`처럼 `workbranch`가 중복돼 noise가 된다.
- 외부 노출 식별자(바이너리/패키지/tag/번들)는 이미 풀네임으로 잘 잡혀 있어, 디렉터리만 짧게 바꿔도 외부 호환성에는 영향이 없다.
- 단, 경로가 여러 live 파일(release-please 설정, CI 3종, Homebrew, install.sh, contract 테스트, release-config 검증 테스트, 빌드 스크립트, docs)에 하드코딩돼 있어 일괄·일관 치환이 필요하다.

## 현재 repo 근거

- 디렉터리: `apps/workbranch-cli/`(순수 Bash, **package.json 없음** → pnpm workspace 멤버가 아니라 glob에서 자연 제외됨), `apps/workbranch-companion/`(`package.json` name `@workbranch/companion`), `packages/contract/`(`@workbranch/contract`).
- `pnpm-workspace.yaml`: `apps/*`, `packages/*` — glob이라 **변경 불필요**.
- 루트 `package.json` 스크립트: `cli:build`/`cli:run`/`cli:test`가 `apps/workbranch-cli/...`를, `companion:run`이 `apps/workbranch-companion/...`를 하드코딩. companion filter는 패키지명 `@workbranch/companion` 사용(경로 무관 → 불변).
- 빌드 산출물: 루트 `bin/workbranch`(186k Bash 산출물, 내부에 경로 1곳)와 `apps/workbranch-cli/bin/workbranch`. 둘 다 `apps/cli/scripts/build-workbranch.sh`가 생성하므로 손으로 고치지 않는다.
- release-please:
  - `.release-please-manifest.json` key: `"."`(=`2.4.0`), `"apps/workbranch-companion"`(=`2.3.0`).
  - `release-please-config.json`: `packages` key `"apps/workbranch-companion"`; 루트 `.`의 `exclude-paths`에 `apps/workbranch-companion/**`; `extra-files`에 `apps/workbranch-cli/bin/workbranch`. **component/package-name**은 `workbranch`(루트)·`workbranch-companion`(companion)이며 tag는 이 값으로 생성된다(경로 key와 무관).
- 경로 문자열을 하드코딩한 live 파일(과거 plan 제외):
  - `apps/workbranch-cli`: `install.sh`(3), 루트 `package.json`(3), `packaging/homebrew/workbranch.rb`(2), `release-please-config.json`(1), `docs/architecture.md`(9), `docs/git-operations.md`(1), `packages/contract/tests/contract.test.mjs`(1, `apps/workbranch-cli/bin/workbranch`), `.github/workflows/ci.yml`(9 lines / 14 occurrences), `apps/workbranch-cli/{install.sh, scripts/build-workbranch.sh, tests/cases/meta.sh, tests/cases/release-config.sh}`.
  - `apps/workbranch-companion`: 루트 `package.json`(1), `.release-please-manifest.json`(1), `release-please-config.json`(2), `.gitignore`(3), `README.md`(2)/`README.ko.md`(2), `DESIGN.md`(3), `docs/architecture.md`(1), `.github/workflows/{companion-ci.yml(3), companion-release.yml(1)}`, `apps/workbranch-companion/README.md`(2).
  - 검증 테스트 `apps/workbranch-cli/tests/cases/release-config.sh`는 release-please 설정 경로(`apps/workbranch-companion`, `apps/workbranch-cli/bin/workbranch` 등)를 **명시 단언**한다(13곳) → 설정과 lockstep으로 갱신해야 green 유지.
- 재생성 산출물: `pnpm-lock.yaml`(companion 경로 1) → `pnpm install`로 재생성. `bin/workbranch`·`apps/cli/bin/workbranch` → 빌드로 재생성.
- 과거 plan: `docs/plans/0032~0037`이 옛 경로를 다수 포함하나 **시점 기록이므로 재작성하지 않는다**(이 plan의 비범위로 명시).

## 결정 사항 (확정됨)

- **디렉터리(내부):** `apps/workbranch-cli → apps/cli`, `apps/workbranch-companion → apps/companion`. 이동은 `git mv`. **Status:** resolved 2026-06-19 via `$plan-decision-grill` Decision 1, option A.
- **외부 식별자(불변):** 바이너리 `workbranch`(루트 `bin/workbranch` 경로 포함), npm name `@workbranch/companion`·`@workbranch/contract`, release-please component/package-name `workbranch`·`workbranch-companion`(→ git tag 형식 불변), Homebrew formula 파일/이름 `workbranch`, 앱 번들 `WorkbranchCompanion.app`, Tauri product/identifier. **하나도 바꾸지 않는다.**
- **release-please:** manifest/config의 **경로 key만** `apps/companion`으로 바꾸고, `apps/workbranch-companion`(=`2.3.0`)의 버전 값을 새 key `apps/companion`으로 **그대로 이전**한다. component/package-name/tag 설정은 불변.
- **pnpm-workspace.yaml:** glob 유지 — 변경하지 않는다.
- **과거 plan 문서:** `docs/plans/0032~0037`의 옛 경로 문자열은 **재작성하지 않는다.** (이 0038 문서가 리네임 시점을 기록한다.)
- **산출물 직접편집 금지:** `bin/workbranch`, `apps/cli/bin/workbranch`는 빌드로, `pnpm-lock.yaml`은 `pnpm install`로만 갱신.

### 결정 기록

- **Decision 0 — 내부 앱 디렉터리 canonical path 확정:** 2026-06-19 `$plan-decision-grill`에서 option A로 확정했다. 내부 앱 경로는 `apps/cli`와 `apps/companion`으로 짧게 통일하고, 외부 식별자는 아래 public contract처럼 유지한다. 대안 B(`apps/workbranch-cli`/`apps/workbranch-companion` 유지)는 리네임 리스크는 낮지만 monorepo 경로 noise를 해결하지 못하므로 채택하지 않는다.
- **Decision 1 — 경로 key만 이동, component/tag 유지:** release-please의 `packages` key와 manifest key는 "추적 대상 경로"라는 내부 식별자이고, tag는 `component`/`include-component-in-tag`로 결정된다. 따라서 경로 key를 `apps/companion`으로 바꿔도 component를 `workbranch-companion`으로 유지하면 다음 릴리스 tag는 그대로 `workbranch-companion-v2.4.0`이 된다. 버전 값(`2.3.0`)을 새 key로 이전하므로 버전 연속성도 보존된다.
- **Decision 2 — 과거 plan 비범위:** 0032~0037은 작성 시점의 디렉터리 구조를 기록한 문서다. 일괄 치환으로 과거 기록을 바꾸면 "그때 무엇을 했는가"가 왜곡된다. live 동작과 무관하므로 손대지 않는다. 현재 구조는 이 0038 문서가 단일 출처로 기록한다.
- **Decision 3 — npm name은 이미 scope라 불변:** `@workbranch/companion`/`@workbranch/contract`는 경로가 아니라 패키지명이므로 디렉터리 리네임과 독립이다. 루트 스크립트의 companion 동작은 대부분 `--filter @workbranch/companion`을 쓰므로 경로 변경 영향이 없고, 오직 파일 경로를 직접 쓰는 스크립트(`companion:run`의 번들 open 경로)만 갱신한다.

## public contract (불변 — 회귀 금지 기준)

- CLI 바이너리 이름·위치: `workbranch`, 배포 산출물 루트 `bin/workbranch` 유지.
- npm 패키지명: `@workbranch/companion`, `@workbranch/contract` 유지.
- release tag 형식: 루트 `vX.Y.Z`(component 미포함), companion `workbranch-companion-vX.Y.Z` 유지.
- Homebrew formula 이름/설치 바이너리: `workbranch` 유지.
- 앱 번들/식별자: `WorkbranchCompanion.app`, Tauri product name/identifier 유지.

## 파일 구조

```text
# git mv (디렉터리 이동)
apps/workbranch-cli/        → apps/cli/
apps/workbranch-companion/  → apps/companion/

# 경로 문자열 치환 (live 설정/스크립트/CI)
package.json                       # cli:* / companion:run 경로
release-please-config.json         # packages key, exclude-paths, extra-files (component/package-name 불변)
.release-please-manifest.json      # key apps/workbranch-companion → apps/companion (버전 값 이전)
.gitignore                         # companion icons/target 경로
.github/workflows/ci.yml           # cli 경로 전체(현재 9 lines / 14 occurrences)
.github/workflows/companion-ci.yml # companion 경로 3곳
.github/workflows/companion-release.yml  # companion 경로 1곳
packaging/homebrew/workbranch.rb   # build/install 경로 (formula 이름은 불변)
install.sh                         # 루트 인스톨러 cli 경로 3곳

# 앱 내부 자기경로 참조 + 검증 테스트
apps/cli/install.sh
apps/cli/scripts/build-workbranch.sh
apps/cli/tests/cases/meta.sh
apps/cli/tests/cases/release-config.sh    # release-please 경로 단언 (설정과 lockstep)
packages/contract/tests/contract.test.mjs # apps/cli/bin/workbranch
apps/companion/README.md

# 문서
docs/architecture.md, docs/git-operations.md, README.md, README.ko.md, DESIGN.md

# 재생성 (직접 편집 금지)
bin/workbranch, apps/cli/bin/workbranch   # build-workbranch.sh 재빌드
pnpm-lock.yaml                            # pnpm install

# 비범위 (재작성 금지)
docs/plans/0032..0037-*.md
```

## 구현 작업

> 각 Task 후 가능한 검증을 즉시 돌려 green을 유지한다. Task 1~2(이동)와 Task 3~10(치환)은 한 PR/브랜치 안에서 순서대로 진행한다 — 이동만 한 중간 상태는 빌드/테스트가 깨지므로 커밋 분할 시 주의.

### Task 1: `apps/workbranch-cli → apps/cli` 이동
- `git mv apps/workbranch-cli apps/cli` (히스토리 보존).
- 이 시점엔 경로 참조가 깨진 상태 — 후속 Task에서 치환.
- Acceptance: `apps/cli/`가 존재하고 `git status`에 rename으로 잡힌다.

### Task 2: `apps/workbranch-companion → apps/companion` 이동
- `git mv apps/workbranch-companion apps/companion`.
- Acceptance: `apps/companion/`가 존재하고 rename으로 잡힌다.

### Task 3: 루트 `package.json` 스크립트 경로 치환
- `cli:build`/`cli:run`/`cli:test`의 `apps/workbranch-cli` → `apps/cli`.
- `companion:run`의 번들 open 경로 `apps/workbranch-companion/...` → `apps/companion/...`. 번들명 `WorkbranchCompanion.app`은 유지.
- companion filter(`--filter @workbranch/companion`)는 변경하지 않는다.
- Acceptance: `pnpm run cli:test`, `pnpm run cli:build`가 새 경로로 정상 수행된다.

### Task 4: release-please config/manifest 경로 key 이전
- `release-please-config.json`: `packages` key `"apps/workbranch-companion"` → `"apps/companion"`; 루트 `.`의 `exclude-paths` 내 `apps/workbranch-companion/**` → `apps/companion/**`; `extra-files`의 `apps/workbranch-cli/bin/workbranch` → `apps/cli/bin/workbranch`. **`component`/`package-name`(`workbranch`, `workbranch-companion`)은 변경 금지.**
- `.release-please-manifest.json`: key `"apps/workbranch-companion"`을 `"apps/companion"`으로 바꾸고 값 `2.3.0`을 그대로 이전. `"."` key는 불변.
- Acceptance: 두 파일이 valid JSON이고, companion 항목의 component/tag 설정과 버전 값이 보존된다.

### Task 5: `release-config.sh` 검증 테스트 동기화
- `apps/cli/tests/cases/release-config.sh`의 단언 경로를 Task 4와 lockstep으로 갱신: `packages['apps/workbranch-companion']` → `['apps/companion']`, `exclude-paths`의 `apps/workbranch-companion/**`, `extra-files`의 `apps/workbranch-cli/bin/workbranch`, manifest key `apps/workbranch-companion`, companion 파일 경로(`apps/workbranch-companion/...` → `apps/companion/...`), formula 내 build/install 경로, `sync-release-markers.mjs` 경로 등 13곳 전부.
- Acceptance: 이 케이스가 새 설정과 일치해 통과한다(아래 Task 11 `tests/run.sh`에서 확인).

### Task 6: CLI 앱 내부 자기경로 참조 치환
- `apps/cli/install.sh`, `apps/cli/scripts/build-workbranch.sh`, `apps/cli/tests/cases/meta.sh`의 `apps/workbranch-cli` → `apps/cli`.
- `packages/contract/tests/contract.test.mjs`의 `apps/workbranch-cli/bin/workbranch` → `apps/cli/bin/workbranch`.
- Acceptance: 빌드 스크립트가 새 경로 산출물을 만들고, contract 테스트가 새 바이너리 경로를 찾는다.

### Task 7: 루트 인스톨러 / Homebrew 치환
- `install.sh`(루트)의 `apps/workbranch-cli` 3곳 → `apps/cli`.
- `packaging/homebrew/workbranch.rb`의 `system "apps/workbranch-cli/scripts/build-workbranch.sh"`, `bin.install "apps/workbranch-cli/bin/workbranch"` → `apps/cli/...`. formula 클래스/이름은 불변.
- Acceptance: formula의 build/install 경로가 새 구조를 가리키고 `release-config.sh`의 formula 경로 단언과 일치한다.

### Task 8: GitHub Actions 워크플로 치환
- `.github/workflows/ci.yml`의 cli 경로 전체(현재 9 lines / 14 occurrences: `bash -n`, `tests/run.sh`, 플랫폼 스모크, shellcheck `find` 경로) → `apps/cli/...`.
- `.github/workflows/companion-ci.yml`(3), `companion-release.yml`(1)의 `apps/workbranch-companion` → `apps/companion`.
- Acceptance: 워크플로 YAML이 유효하고 모든 step 경로가 새 디렉터리를 가리킨다(원격 CI에서 최종 확인).

### Task 9: `.gitignore` 및 companion README 치환
- `.gitignore`의 companion 경로 3곳(`!apps/workbranch-companion/src-tauri/icons/`, `...icons/**`, `apps/workbranch-companion/src-tauri/target/`) → `apps/companion/...`. 아이콘 negation과 target ignore 동작이 유지되는지 확인.
- `apps/companion/README.md`의 자기경로 2곳 → `apps/companion`.
- Acceptance: companion 빌드 산출물(`apps/companion/src-tauri/target/`)이 다시 ignore되고 아이콘은 추적 유지된다.

### Task 10: 문서 경로 동기화
- `docs/architecture.md`(cli 9 + companion 1), `docs/git-operations.md`(1), `README.md`/`README.ko.md`(companion 2씩), `DESIGN.md`(3)의 경로 문자열을 새 디렉터리로 치환.
- **`docs/plans/0032~0037`은 건드리지 않는다**(Decision 2).
- Acceptance: live 문서의 경로가 현재 구조와 일치하고, 과거 plan은 변경되지 않는다.

### Task 11: 산출물 재생성 + 전체 검증
- `apps/cli/scripts/build-workbranch.sh`로 `apps/cli/bin/workbranch`와 루트 `bin/workbranch` 재생성(내부 경로 문자열 갱신 포함).
- `pnpm install`로 `pnpm-lock.yaml` 재생성(companion 경로 반영).
- Acceptance: 산출물·lock에 옛 경로가 남지 않고 빌드/설치가 정상.


## 실행 결과 (2026-06-19)

- Task 1~2: `git mv apps/workbranch-cli apps/cli`, `git mv apps/workbranch-companion apps/companion` 적용. `git status`에서 두 앱 디렉터리가 rename으로 추적된다.
- Task 3~10: live 설정/스크립트/CI/문서 경로를 `apps/cli`·`apps/companion`으로 동기화했다. 외부 식별자(`workbranch`, `@workbranch/companion`, `workbranch-companion`, `WorkbranchCompanion.app`)는 유지했다.
- Task 11: `apps/cli/scripts/build-workbranch.sh`로 `apps/cli/bin/workbranch`와 루트 `bin/workbranch`를 재생성했고, `pnpm install`로 `pnpm-lock.yaml`을 재생성했다.
- Review fix: `apps/companion/src-tauri/Cargo.lock`의 `workbranch-companion` version line에 `# x-release-please-version` marker를 복구했고, `pnpm --filter @workbranch/companion tauri build` 이후에도 marker가 유지되도록 `apps/companion/package.json`에 `posttauri: pnpm run sync:release-markers`를 추가했다.
- Review fix: `apps/companion/src-tauri/src/workbranch_bin.rs`의 local CLI fallback을 rename 후 경로 `../../cli/bin/workbranch`로 수정했고, 같은 경로를 고정하는 unit test를 추가했다. CI 실패 재현 seam인 `cargo test --manifest-path apps/companion/src-tauri/Cargo.toml`은 17 tests passed.
- 검증 evidence:
  - old-path live check: `rg "apps/workbranch-cli|apps/workbranch-companion" ... | grep -v "docs/plans/003[2-8]"` → 0건.
  - syntax/release config: `/bin/bash -n bin/workbranch apps/cli/bin/workbranch install.sh apps/cli/install.sh apps/cli/tests/run.sh apps/cli/scripts/build-workbranch.sh`, release-please JSON assertion, `git diff --check` 통과.
  - CLI: `pnpm run cli:build`, `pnpm run cli:test` → `Tests passed: 273`; `pnpm run cli:run -- version` → `workbranch 2.4.0`; `pnpm run cli:run -- help` smoke 통과.
  - workspace/companion: `pnpm -r --if-present run test`, `pnpm --filter @workbranch/companion test`, `pnpm run companion:check-release-markers`, `pnpm run typecheck`, `pnpm run lint`, `pnpm run build` 통과. `pnpm run lint`는 기존 `apps/companion/src/infrastructure/parseContract.ts`의 `useLiteralKeys` info diagnostics를 출력하지만 exit 0.
  - workflows/Rust/Tauri: Ruby YAML parse for workflows 통과, `cargo test --manifest-path apps/companion/src-tauri/Cargo.toml` 16 tests passed, `pnpm run companion:build`가 `apps/companion/src-tauri/target/release/bundle/macos/WorkbranchCompanion.app` 번들 생성까지 통과.

## 최종 검증

```bash
# 옛 경로 잔존 확인 (live 파일에 0건이어야 함; 과거 plan과 현재 0038 plan 자체는 제외)
grep -rIl "apps/workbranch-cli\|apps/workbranch-companion" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=target \
  . | grep -v "docs/plans/003[2-8]"

# CLI
pnpm run cli:build
pnpm run cli:test                 # release-config.sh 케이스 포함 통과
/bin/bash -n bin/workbranch apps/cli/bin/workbranch
git diff --check

# 워크스페이스 / contract
pnpm install
pnpm -r --if-present run test     # @workbranch/contract contract.test.mjs 포함

# Companion (환경 가능 시)
pnpm --filter @workbranch/companion test
pnpm run companion:check-release-markers

# release-please 설정 정합성
python3 - <<'PY'
import json
cfg = json.load(open('release-please-config.json'))
man = json.load(open('.release-please-manifest.json'))
assert 'apps/companion' in cfg['packages'] and 'apps/workbranch-companion' not in cfg['packages']
assert cfg['packages']['apps/companion']['component'] == 'workbranch-companion'  # tag 불변
assert man['apps/companion'] == '2.3.0' and 'apps/workbranch-companion' not in man
print('release-please paths migrated, component/version preserved')
PY
```

- 수동 확인: `git log --follow apps/cli/bin/workbranch`로 히스토리 보존 확인.
- 수동 확인: 다음 release-please PR(또는 dry-run)에서 companion tag가 `workbranch-companion-vX.Y.Z` 형식을 유지하는지 확인.

## 롤아웃 / 호환성

- **외부 호환성 영향 없음:** 바이너리·패키지명·tag·formula·번들 식별자 전부 불변. 사용자 설치/업데이트 경로 변화 없음.
- **release-please 연속성:** 경로 key만 이동하고 component/버전 값을 보존하므로 다음 릴리스가 끊기지 않는다. 머지 후 첫 release PR에서 tag 형식만 한 번 눈으로 확인.
- **단일 PR 권장:** 디렉터리 이동(Task 1~2)과 경로 치환(Task 3~10)은 한 PR로 묶어 중간 broken 상태가 main에 들어가지 않게 한다.
- **과거 plan:** 0032~0037은 의도적으로 보존 — 리뷰어가 "왜 옛 경로가 남았나" 묻지 않도록 PR 설명에 Decision 2를 명시한다.

## 미해결 / 후속

- CLI에 향후 `package.json`을 추가해 pnpm workspace 정식 멤버로 만들 경우 name은 `@workbranch/cli`(scope) 권장 — 이번 범위 밖.
- 루트 산출물 `bin/workbranch`의 존재 자체(배포 편의용 복제본)는 이번에 유지. 추후 `apps/cli/bin/workbranch` 단일 출처로 정리할지는 별도 결정.
