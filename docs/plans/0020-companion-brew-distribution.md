# 0020 Companion Homebrew Cask 배포 배관 계획

> **agentic worker 지침:** 실행 시 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용한다. 이 계획은 release automation과 배포 문서만 수정한다. `src/workbranch/**` 동작 변경과 `bin/workbranch` 재생성은 하지 않는다. companion Swift 코드(`companion/Sources/**`, `companion/Tests/**`)도 수정하지 않는다 — 유일한 예외는 `companion/scripts/build-app.sh`의 version marker/universal build 변경이다. 기존 CLI `v*` release 경로를 깨뜨리지 않는 것이 최우선 제약이다.
>
> **시리즈 위치:** menu bar companion의 배포 단계다. **이 계획은 0018(companion 배포 배관)을 대체하며, 0018 문서는 삭제한다.** 0018의 구조 결정(release-please two-package, `workbranch-companion-v*` component tag, path-filtered companion CI)은 계승하고, npm/SwiftBar/formula 전제는 폐기한다(companion은 0019에서 Swift/SPM native app으로 구현 완료). 현재 순서: 0015 memo/noti/json(완료) → 0019 native menu bar companion(완료) → **0020 brew cask 배포** → AGENTS.md producer/E2E 검증(별도 계획). hard dependency는 0019의 `companion/` 패키지와 `companion/scripts/build-app.sh`뿐이다.

**목표:** `WorkbranchCompanion.app`을 기존 `tkhwang/homebrew-tap`에서 `brew install --cask tkhwang/tap/workbranch-companion`으로 설치할 수 있게 한다. CLI는 기존 plain `v*` tag + `Formula/workbranch.rb` flow를 그대로 유지한다.

**아키텍처:** release-please manifest mode를 two-package로 구성한다(root `.` = `workbranch`, plain `v*` 보존 / `companion/` = `workbranch-companion`, component tag). companion release가 publish되면 전용 `companion-release.yml`이 macOS runner에서 universal `.app`을 조립하고, Apple secrets가 있으면 Developer ID 서명 + notarization, 없으면 ad-hoc 그대로 zip을 release asset으로 업로드한 뒤 **같은 job에서** tap의 `Casks/workbranch-companion.rb`를 bump한다(asset 업로드 후 같은 job에서 sha256을 계산하므로 race가 없다). 지금 단계는 ad-hoc + `--no-quarantine`으로 배포하고, Developer ID는 secrets 등록만으로 활성화되는 guarded 단계로 둔다.

**기술 스택:** release-please manifest config, GitHub Actions(macOS 15 runner — public repo라 무료), `ditto`/`codesign`/`notarytool`, Homebrew cask, 기존 `tkhwang/homebrew-tap`.

**제품 관점:** companion 제품 기능이 아니라 배포 배관이다. 사용자 경험 목표는 CLI와 동일한 한 줄 설치다: `brew install --cask tkhwang/tap/workbranch-companion` (ad-hoc 과도기에는 `--no-quarantine` 추가).

---

## 문제

0019로 companion이 local build/install 가능한 상태가 됐지만, 배포 채널이 없다. `companion/README.md`는 직접 `build-app.sh`를 돌리라고 안내하고, `homebrew-bump.yml`은 non-`v*` tag를 만나면 hard fail하므로 companion tag를 만들면 기존 workflow가 빨간불이 된다. 0018이 이 배관을 계획했지만 npm/SwiftBar 전제가 stale해서 실행 불가다.

## 현재 repo 근거

- `release-please-config.json`: root 단일 package, `release-type: simple`, `include-component-in-tag: false`, extra-file `bin/workbranch`.
- `.release-please-manifest.json`: `{".": "1.13.0"}`.
- `bin/workbranch:4`: `WORKBRANCH_VERSION=1.13.0 # x-release-please-version` — generic updater marker 패턴의 선례. root에 `version.txt`는 없다.
- `.github/workflows/homebrew-bump.yml`: release published 트리거. `v*` 외 tag는 **exit 1로 hard fail**. tap checkout에 `secrets.TAP_GITHUB_TOKEN` 사용(이 secret은 이미 등록되어 있다).
- `.github/workflows/ci.yml`: ubuntu runner, Bash suite 전용, `actions/checkout@v4`.
- `companion/scripts/build-app.sh`: SPM release build → `.app` 조립. **버전이 Info.plist heredoc 안에 `0.1.0`으로 하드코딩**되어 있고 ad-hoc codesign(`--sign -`)한다.
- `companion/Package.swift`: `swift build`/`swift test`/`swift run CompanionCoreTestRunner`로 검증(0019 evidence).
- git history에 이미 `feat(companion): ...` scope commit이 존재한다 — companion package를 manifest에 추가하면 release-please가 이 history로 첫 release PR(0.1.0)을 만들 수 있다.
- 이 repo는 public이다. GitHub macOS runner가 무료다.

## 결정 사항

- [x] **App Store를 거치지 않는다. 배포는 기존 tap + GitHub release asset.**
  - `tkhwang/homebrew-tap`에 `Formula/workbranch.rb` 옆에 `Casks/workbranch-companion.rb`를 추가한다. 설치 UX는 CLI와 동일한 구조다.

- [x] **지금은 ad-hoc 서명 + `--no-quarantine` 설치. Developer ID + notarization은 guarded 후속 활성화.**
  - Apple Developer 멤버십 없이 오늘 전체 파이프라인을 완성/검증할 수 있다.
  - release workflow는 `APPLE_CERTIFICATE_P12` 등 secrets가 **있으면** Developer ID 서명 + notarization + staple을 수행하고, **없으면** ad-hoc 그대로 진행한다. workflow 수정 없이 secrets 등록만으로 업그레이드된다.
  - secrets 발급/등록 step-by-step 가이드를 `companion/README.md`에 둔다(Task 6).

- [x] **release-please two-package. root 동작 보존이 최우선.**
  - root `.`: plain `v*` tag(`include-component-in-tag: false`)와 `bin/workbranch` extra-file은 보존하되, `exclude-paths`로 `companion/`, `.github/`, `docs/`, root companion docs(`README.md`, `README.ko.md`), release-please metadata만 건드린 배포/문서/companion commit은 CLI release 후보에서 제외한다.
  - `companion`: `package-name`과 `component`를 모두 `workbranch-companion`으로 명시하고, `include-component-in-tag: true` → tag `workbranch-companion-vX.Y.Z`, changelog `companion/CHANGELOG.md`, extra-file `scripts/build-app.sh`(package 상대 경로).
  - `release-please-config.json` / `.release-please-manifest.json`도 exact file path로 root exclude에 넣는다. 그래도 release plumbing/config/docs/workflow commit은 `chore(release): ...`처럼 non-releasing type으로 둔다. companion source 변경 commit(`feat(companion): ...`)과 섞지 않는다.
  - manifest seed는 `"companion": "0.0.0"` — 기존 `feat(companion)` history가 첫 release PR을 0.1.0으로 제안하게 한다.

- [x] **버전 single source는 release-please. `build-app.sh`가 Info.plist에 주입한다.**
  - `APP_VERSION="0.1.0" # x-release-please-version` 변수를 두고 `CFBundleShortVersionString`/`CFBundleVersion`에 interpolate한다. `bin/workbranch`와 같은 generic marker 패턴이다.

- [x] **release artifact는 universal binary zip.**
  - CI release build는 `--arch arm64 --arch x86_64`로 Intel Mac도 커버한다. local build는 기존대로 native 단일 arch(빌드 시간 절약). `WORKBRANCH_COMPANION_UNIVERSAL=1` env로 분기한다.
  - zip은 `ditto -c -k --keepParent`로 만든다(`.app` bundle 메타데이터 보존). asset 이름: `WorkbranchCompanion-X.Y.Z.zip`.

- [x] **cask bump는 `companion-release.yml` 안에서 수행한다. `homebrew-bump.yml`에 넣지 않는다.**
  - 두 workflow가 같은 release published 이벤트에 트리거되면 zip asset 업로드 전에 cask가 sha256을 계산하려는 race가 생긴다. asset 업로드 직후 같은 job에서 bump하면 순서가 보장된다.
  - `homebrew-bump.yml`은 `workbranch-companion-*` tag에서 조용히 skip하도록 job-level `if`만 추가한다(현재는 hard fail). `v*` 경로 동작은 무변경.
  - cask 파일이 tap에 아직 없으면 `Casks/workbranch-companion.rb`를 같은 job에서 생성한다. 첫 companion release부터 문서화된 `brew install --cask tkhwang/tap/workbranch-companion` 경로가 실제로 생겨야 하므로 silent skip은 금지한다.

- [x] **companion CI는 별도 path-filtered workflow.** (0018 계승)
  - `companion-ci.yml`: `companion/**` trigger, macOS 15 runner, `swift build` + `swift test` + `swift run CompanionCoreTestRunner` + `build-app.sh` smoke. 기존 `ci.yml`은 수정하지 않는다.

- [x] **commit discipline.** (0018 계승)
  - companion source 변경은 `feat(companion):`/`fix(companion):` scope로 두고 `companion/**` 안에만 담아 companion release만 만든다.
  - release plumbing/config/docs/workflow 변경은 `chore(release):`, `chore(ci):`, `docs(companion):`처럼 root CLI release를 만들지 않는 type으로 둔다.
  - CLI와 companion을 동시 release할 의도가 아니면 mixed commit 금지. 특히 `release-please-config.json` / `.release-please-manifest.json` 변경을 `feat(companion):` commit에 섞지 않는다.

- [x] **0018 문서는 삭제한다.**
  - 0018은 한 번도 실행되지 않았고 전제가 stale하다. 결정 이력은 git history와 이 문서의 계승 표기로 충분하다. 0015/0019의 0018 참조는 0020으로 갱신한다(superseded 문서인 0017은 역사 보존을 위해 그대로 둔다).

- [ ] **Developer ID secrets 등록과 공증 활성화는 follow-up.**
  - 사용자가 Apple Developer Program 가입 후 Task 6의 가이드대로 secrets를 등록하면 다음 release부터 공증된 zip이 나간다. 그 시점에 cask caveats(`--no-quarantine` 안내)를 제거하는 tap PR을 한 번 더 만든다.

- [ ] **Sparkle 등 in-app 자동 업데이트는 scope 밖.** 업데이트는 `brew upgrade --cask`로 한다.

## public release contract

1. CLI release (무변경):
   - tag: `vX.Y.Z`, changelog: root `CHANGELOG.md`, formula: `Formula/workbranch.rb`
2. Companion release:
   - tag: `workbranch-companion-vX.Y.Z`
   - changelog: `companion/CHANGELOG.md`
   - GitHub release asset: `WorkbranchCompanion-X.Y.Z.zip` (universal, ad-hoc 또는 notarized)
   - cask: `tkhwang/homebrew-tap`의 `Casks/workbranch-companion.rb` (자동 bump)
3. 설치:
   - ad-hoc 과도기: `brew install --cask --no-quarantine tkhwang/tap/workbranch-companion`
   - Developer ID 활성화 후: `brew install --cask tkhwang/tap/workbranch-companion`

## 파일 구조

```text
release-please-config.json                       # root + companion two-package
.release-please-manifest.json                    # "." + "companion" version
.github/workflows/homebrew-bump.yml              # companion tag skip guard 추가
.github/workflows/companion-ci.yml               # 신규: swift build/test, macOS 15 runner
.github/workflows/companion-release.yml          # 신규: app 조립/서명(guarded)/zip/asset/cask bump
companion/scripts/build-app.sh                   # version marker + universal build 분기
companion/CHANGELOG.md                           # seed
companion/README.md                              # brew 설치 섹션 + Apple secrets 가이드
docs/plans/0018-companion-release-plumbing.md    # 삭제
docs/plans/0015-task-memo-noti-and-json-listing.md  # 시리즈 참조 0018 → 0020
docs/plans/0019-companion-native-menubar-app.md     # 시리즈 참조 0018 → 0020
(외부) tkhwang/homebrew-tap: Casks/workbranch-companion.rb  # Task 7에서 추가
```

## 구현 작업

### Task 1: build-app.sh version marker와 universal build

**Files:**
- Modify: `companion/scripts/build-app.sh`

- [x] **Step 1: version 변수와 universal 분기 추가**

`build-app.sh`를 다음 내용으로 교체한다(변경점: `APP_VERSION` marker, `WORKBRANCH_COMPANION_UNIVERSAL` 분기, Info.plist heredoc unquote + 버전 interpolate):

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_VERSION="0.1.0" # x-release-please-version

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
COMPANION_DIR=$(cd "$SCRIPT_DIR/.." && pwd -P)
APP_DIR="$COMPANION_DIR/dist/WorkbranchCompanion.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$COMPANION_DIR"
if [ "${WORKBRANCH_COMPANION_UNIVERSAL:-0}" = "1" ]; then
  swift build -c release --product WorkbranchCompanion --arch arm64 --arch x86_64
  BINARY_SRC="$COMPANION_DIR/.build/apple/Products/Release/WorkbranchCompanion"
else
  swift build -c release --product WorkbranchCompanion
  BINARY_SRC="$COMPANION_DIR/.build/release/WorkbranchCompanion"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY_SRC" "$MACOS_DIR/WorkbranchCompanion"
chmod +x "$MACOS_DIR/WorkbranchCompanion"
cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>WorkbranchCompanion</string>
  <key>CFBundleIdentifier</key>
  <string>com.tkhwang.workbranch-companion</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>WorkbranchCompanion</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --sign - "$APP_DIR" >/dev/null
printf '[+] Built %s (v%s)\n' "$APP_DIR" "$APP_VERSION"
```

- [x] **Step 2: 검증**

```bash
bash -n companion/scripts/build-app.sh
cd companion && ./scripts/build-app.sh
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" companion/dist/WorkbranchCompanion.app/Contents/Info.plist
```

Expected: 마지막 명령이 `0.1.0` 출력. app launch smoke: `open companion/dist/WorkbranchCompanion.app` 후 `pgrep -fl WorkbranchCompanion`.

검증 결과(2026-06-13): `bash -n companion/scripts/build-app.sh`, `cd companion && ./scripts/build-app.sh`, `PlistBuddy` `CFBundleShortVersionString=0.1.0` / `CFBundleVersion=0.1.0`, `open -n` 후 현재 checkout의 `WorkbranchCompanion` process 확인.

- [ ] **Step 3: Commit**

plan-execute 안전 게이트에 따라 이 실행에서는 commit하지 않는다. 적용 시 아래 커밋을 별도로 수행한다.

```bash
git add companion/scripts/build-app.sh
git commit -m "feat(companion): stamp app version from release-please marker and support universal build"
```

### Task 2: release-please two-package config

**Files:**
- Modify: `release-please-config.json`
- Modify: `.release-please-manifest.json`
- Create: `companion/CHANGELOG.md`

- [x] **Step 1: config에 companion package 추가**

`release-please-config.json` 전체:

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "release-type": "simple",
  "include-component-in-tag": false,
  "packages": {
    ".": {
      "package-name": "workbranch",
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

주의: `extra-files`의 `path`는 package 디렉토리 기준 상대 경로다(`companion/scripts/build-app.sh`가 아니라 `scripts/build-app.sh`). `exclude-paths`는 commit의 relevant files가 모두 지정 path에 속할 때 해당 package parsing에서 제외한다. companion-only 배포/문서 commit이 root README나 release-please metadata를 같이 건드릴 수 있으므로 이 root-level 파일들도 exact path로 root package exclude에 포함한다.

- [x] **Step 2: manifest seed**

`.release-please-manifest.json` 전체(root 버전은 그 시점의 실제 값 유지 — 아래는 작성 시점 값):

```json
{
  ".": "1.13.0",
  "companion": "0.0.0"
}
```

- [x] **Step 3: changelog seed**

`companion/CHANGELOG.md` 생성:

```markdown
# Changelog
```

- [x] **Step 4: 검증**

```bash
python3 -c "import json; json.load(open('release-please-config.json')); json.load(open('.release-please-manifest.json'))" && echo OK
```

Expected: `OK`. `git diff release-please-config.json`으로 root package가 `include-component-in-tag: false`, `bin/workbranch` extra-file, `exclude-paths`에 `companion`, `.github`, `docs`, `README.md`, `README.ko.md`, `release-please-config.json`, `.release-please-manifest.json`을 갖고 companion package가 `component: "workbranch-companion"`를 명시하는지 확인한다.

검증 결과(2026-06-13): `python3` JSON parse OK, diff에서 root `exclude-paths`, companion `component`, manifest `"companion": "0.0.0"` 확인.

- [ ] **Step 5: Commit**

plan-execute 안전 게이트에 따라 이 실행에서는 commit하지 않는다. 적용 시 아래 커밋을 별도로 수행한다.

```bash
git add release-please-config.json .release-please-manifest.json companion/CHANGELOG.md
git commit -m "chore(release): add companion package to release-please manifest"
```

### Task 3: homebrew-bump.yml companion tag skip guard

**Files:**
- Modify: `.github/workflows/homebrew-bump.yml`

- [x] **Step 1: job-level if 추가**

`jobs.bump-homebrew-formula`에 한 줄 추가(기존 step 무변경 — `v*` 경로 동작 보존):

```yaml
jobs:
  bump-homebrew-formula:
    name: Update tkhwang/homebrew-tap
    runs-on: ubuntu-latest
    if: ${{ !startsWith(github.event.release.tag_name, 'workbranch-companion-') }}
```

기존 step 내부의 `case "$TAG_NAME" in v*)` guard는 그대로 둔다(그 외 tag hard fail 유지 — companion tag는 job 자체가 안 돌므로 도달하지 않는다).

- [x] **Step 2: 검증**

```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/homebrew-bump.yml'); puts 'OK'"
git diff .github/workflows/homebrew-bump.yml
```

Expected: `OK`, diff가 `if:` 한 줄 추가뿐.

검증 결과(2026-06-13): `ruby -ryaml` parse OK(로컬 Ruby PATH warning은 비차단), diff는 `if: ${{ !startsWith(github.event.release.tag_name, 'workbranch-companion-') }}` 한 줄 추가뿐.

- [ ] **Step 3: Commit**

plan-execute 안전 게이트에 따라 이 실행에서는 commit하지 않는다. 적용 시 아래 커밋을 별도로 수행한다.

```bash
git add .github/workflows/homebrew-bump.yml
git commit -m "fix(ci): skip formula bump for companion release tags"
```

### Task 4: companion-ci.yml

**Files:**
- Create: `.github/workflows/companion-ci.yml`

- [x] **Step 1: workflow 작성**

```yaml
name: Companion CI

on:
  pull_request:
    paths:
      - "companion/**"
      - ".github/workflows/companion-ci.yml"
  push:
    branches:
      - main
    paths:
      - "companion/**"
      - ".github/workflows/companion-ci.yml"

permissions:
  contents: read

jobs:
  test:
    name: Build and test companion
    runs-on: macos-15
    defaults:
      run:
        working-directory: companion
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build
        run: swift build

      - name: Test
        run: swift test

      - name: Core test runner
        run: swift run CompanionCoreTestRunner

      - name: App bundle smoke
        run: ./scripts/build-app.sh
```

- [x] **Step 2: 검증**

```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/companion-ci.yml'); puts 'OK'"
```

Expected: `OK`. PR을 열면 이 workflow가 `companion/**` 변경(Task 1)에 의해 실제로 트리거되어 green인지가 최종 acceptance다.

검증 결과(2026-06-13): `.github/workflows/companion-ci.yml` 생성, `runs-on: macos-15`로 Swift tools 6.0 호환 runner 사용, `ruby -ryaml` parse OK(로컬 Ruby PATH warning은 비차단).

- [ ] **Step 3: Commit**

plan-execute 안전 게이트에 따라 이 실행에서는 commit하지 않는다. 적용 시 아래 커밋을 별도로 수행한다.

```bash
git add .github/workflows/companion-ci.yml
git commit -m "chore(ci): add path-filtered companion CI on macOS"
```

### Task 5: companion-release.yml (조립 → guarded 서명/공증 → zip → asset → cask bump)

**Files:**
- Create: `.github/workflows/companion-release.yml`

- [x] **Step 1: workflow 작성**

```yaml
name: Companion Release

on:
  release:
    types:
      - published
  workflow_dispatch:
    inputs:
      tag:
        description: "Companion release tag (workbranch-companion-vX.Y.Z)"
        required: true

permissions:
  contents: write

jobs:
  build-and-publish:
    name: Build, package, and publish companion app
    runs-on: macos-15
    if: ${{ github.event_name == 'workflow_dispatch' || startsWith(github.event.release.tag_name, 'workbranch-companion-v') }}
    env:
      TAG_NAME: ${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.event.release.tag_name }}

    steps:
      - name: Validate tag
        run: |
          set -euo pipefail
          case "$TAG_NAME" in
            workbranch-companion-v*) ;;
            *)
              echo "not a companion release tag: $TAG_NAME" >&2
              exit 1
              ;;
          esac

      - name: Checkout
        uses: actions/checkout@v4
        with:
          ref: ${{ env.TAG_NAME }}

      - name: Build universal app bundle
        run: WORKBRANCH_COMPANION_UNIVERSAL=1 ./companion/scripts/build-app.sh

      - name: Sign with Developer ID (skipped until secrets are set)
        env:
          APPLE_CERTIFICATE_P12: ${{ secrets.APPLE_CERTIFICATE_P12 }}
          APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
          APPLE_SIGNING_IDENTITY: ${{ secrets.APPLE_SIGNING_IDENTITY }}
        run: |
          set -euo pipefail
          if [ -z "${APPLE_CERTIFICATE_P12:-}" ]; then
            echo "[skip] APPLE_CERTIFICATE_P12 not set — keeping ad-hoc signature"
            exit 0
          fi
          KEYCHAIN_PATH="$RUNNER_TEMP/companion-signing.keychain-db"
          KEYCHAIN_PASSWORD=$(uuidgen)
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 1800 "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          printf '%s' "$APPLE_CERTIFICATE_P12" | base64 -d > "$RUNNER_TEMP/cert.p12"
          security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN_PATH" \
            -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S "apple-tool:,apple:" -s \
            -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db
          /usr/bin/codesign --force --options runtime --timestamp \
            --sign "$APPLE_SIGNING_IDENTITY" companion/dist/WorkbranchCompanion.app

      - name: Package zip
        run: |
          set -euo pipefail
          VERSION="${TAG_NAME#workbranch-companion-v}"
          ZIP_NAME="WorkbranchCompanion-${VERSION}.zip"
          ditto -c -k --keepParent companion/dist/WorkbranchCompanion.app "$ZIP_NAME"
          {
            echo "VERSION=$VERSION"
            echo "ZIP_NAME=$ZIP_NAME"
          } >> "$GITHUB_ENV"

      - name: Notarize and staple (skipped until secrets are set)
        env:
          APPLE_NOTARY_KEY: ${{ secrets.APPLE_NOTARY_KEY }}
          APPLE_NOTARY_KEY_ID: ${{ secrets.APPLE_NOTARY_KEY_ID }}
          APPLE_NOTARY_ISSUER_ID: ${{ secrets.APPLE_NOTARY_ISSUER_ID }}
        run: |
          set -euo pipefail
          if [ -z "${APPLE_NOTARY_KEY:-}" ]; then
            echo "[skip] APPLE_NOTARY_KEY not set — publishing without notarization"
            exit 0
          fi
          printf '%s' "$APPLE_NOTARY_KEY" | base64 -d > "$RUNNER_TEMP/notary-key.p8"
          xcrun notarytool submit "$ZIP_NAME" \
            --key "$RUNNER_TEMP/notary-key.p8" \
            --key-id "$APPLE_NOTARY_KEY_ID" \
            --issuer "$APPLE_NOTARY_ISSUER_ID" \
            --wait
          xcrun stapler staple companion/dist/WorkbranchCompanion.app
          ditto -c -k --keepParent companion/dist/WorkbranchCompanion.app "$ZIP_NAME"

      - name: Upload release asset
        env:
          GH_TOKEN: ${{ github.token }}
        run: gh release upload "$TAG_NAME" "$ZIP_NAME" --clobber --repo "$GITHUB_REPOSITORY"

      - name: Checkout Homebrew tap
        uses: actions/checkout@v4
        with:
          repository: tkhwang/homebrew-tap
          token: ${{ secrets.TAP_GITHUB_TOKEN }}
          path: homebrew-tap
          persist-credentials: false

      - name: Update cask version and sha256
        run: |
          set -euo pipefail
          CASK_PATH="homebrew-tap/Casks/workbranch-companion.rb"
          ZIP_SHA=$(shasum -a 256 "$ZIP_NAME" | awk '{print $1}')
          CASK_PATH="$CASK_PATH" CASK_VERSION="$VERSION" CASK_SHA="$ZIP_SHA" python3 - <<'PY'
          import os
          import re
          from pathlib import Path

          cask = Path(os.environ["CASK_PATH"])
          version = os.environ["CASK_VERSION"]
          sha = os.environ["CASK_SHA"]
          if cask.exists():
              text = cask.read_text()
              text, version_count = re.subn(
                  r'^  version ".*"$',
                  f'  version "{version}"',
                  text,
                  count=1,
                  flags=re.MULTILINE,
              )
              text, sha_count = re.subn(
                  r'^  sha256 ".*"$',
                  f'  sha256 "{sha}"',
                  text,
                  count=1,
                  flags=re.MULTILINE,
              )
              if version_count != 1 or sha_count != 1:
                  raise SystemExit("expected exactly one version and one sha256 line in cask")
          else:
              cask.parent.mkdir(parents=True, exist_ok=True)
              text = f'''cask "workbranch-companion" do
            version "{version}"
            sha256 "{sha}"

            url "https://github.com/tkhwang/workbranch/releases/download/workbranch-companion-v#{{version}}/WorkbranchCompanion-#{{version}}.zip"
            name "Workbranch Companion"
            desc "Menu bar companion for the workbranch CLI"
            homepage "https://github.com/tkhwang/workbranch"

            depends_on macos: ">= :ventura"

            app "WorkbranchCompanion.app"

            caveats <<~EOS
              This app is currently ad-hoc signed. Install with --no-quarantine:
                brew install --cask --no-quarantine tkhwang/tap/workbranch-companion
              If already installed and blocked by Gatekeeper:
                xattr -dr com.apple.quarantine "/Applications/WorkbranchCompanion.app"
            EOS
          end
          '''
          cask.write_text(text)
          PY
          echo "CASK_CHANGED=1" >> "$GITHUB_ENV"

      - name: Commit and push cask update
        if: ${{ env.CASK_CHANGED == '1' }}
        working-directory: homebrew-tap
        env:
          TAP_GITHUB_TOKEN: ${{ secrets.TAP_GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          if [ -z "$(git status --porcelain -- Casks/workbranch-companion.rb)" ]; then
            echo "Casks/workbranch-companion.rb is already up to date for ${TAG_NAME}"
            exit 0
          fi
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add Casks/workbranch-companion.rb
          git commit -m "chore(workbranch-companion): update cask for ${TAG_NAME}"
          auth_header=$(printf 'x-access-token:%s' "$TAP_GITHUB_TOKEN" | base64 | tr -d '\n')
          git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic ${auth_header}" \
            push https://github.com/tkhwang/homebrew-tap.git HEAD:main
```

주의 (macOS runner 차이): `base64 -w0`은 GNU 전용이라 macOS에서 동작하지 않는다 — push auth header는 `base64 | tr -d '\n'`을 쓴다. `shasum -a 256`은 macOS 기본 제공이다.

- [x] **Step 2: 검증**

```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/companion-release.yml'); puts 'OK'"
```

Expected: `OK`. 추가로 서명/공증 step의 shell 부분만 로컬에서 `bash -n` 가능하도록 임시 파일로 추출해 syntax check해도 좋다. 실제 동작 검증은 Task 7의 첫 release에서 한다.

검증 결과(2026-06-13): `.github/workflows/companion-release.yml` 생성, `runs-on: macos-15`로 Swift tools 6.0 호환 runner 사용, `ruby -ryaml` parse OK, workflow의 모든 `run:` shell block `bash -n` OK(로컬 Ruby PATH warning은 비차단).

- [ ] **Step 3: Commit**

plan-execute 안전 게이트에 따라 이 실행에서는 commit하지 않는다. 적용 시 아래 커밋을 별도로 수행한다.

```bash
git add .github/workflows/companion-release.yml
git commit -m "chore(ci): add companion release pipeline with guarded signing and cask bump"
```

### Task 6: 문서 — brew 설치 섹션, Apple secrets 가이드, plan 참조 정리

**Files:**
- Modify: `companion/README.md`
- Modify: `README.md`
- Modify: `README.ko.md`
- Modify: `docs/plans/0015-task-memo-noti-and-json-listing.md` (시리즈 참조 1곳)
- Modify: `docs/plans/0019-companion-native-menubar-app.md` (시리즈/결정 참조)
- Delete: `docs/plans/0018-companion-release-plumbing.md` — **이 계획 작성 시점에 이미 삭제됨.** 파일이 없으면 이 항목은 완료된 것이다.

- [x] **Step 1: companion/README.md에 Homebrew 설치 섹션 추가**

기존 local build 안내 위에 추가:

````markdown
## Install via Homebrew (recommended)

```bash
brew tap tkhwang/tap
brew install --cask --no-quarantine tkhwang/tap/workbranch-companion
```

`--no-quarantine` is required while releases are ad-hoc signed: macOS Gatekeeper
blocks downloaded apps without a Developer ID signature. If you installed without
the flag and see an "app is damaged" warning, run:

```bash
xattr -dr com.apple.quarantine "/Applications/WorkbranchCompanion.app"
```

Once releases are signed with a Developer ID certificate and notarized
(see below), the flag will no longer be needed.

## Release signing setup (maintainer guide)

The release workflow (`.github/workflows/companion-release.yml`) ships ad-hoc
signed zips until Apple credentials are registered as GitHub secrets. To enable
Developer ID signing + notarization:

1. Join the [Apple Developer Program](https://developer.apple.com/programs/) ($99/year).
2. Create a **Developer ID Application** certificate:
   - Keychain Access → Certificate Assistant → Request a Certificate From a
     Certificate Authority → save the CSR to disk.
   - [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates/add)
     → Developer ID Application → upload the CSR → download and double-click
     the `.cer` to install it into your login keychain.
3. Export the certificate + private key as `.p12`:
   - Keychain Access → My Certificates → right-click the
     "Developer ID Application: ..." entry → Export → set an export password.
4. Find your signing identity string:

   ```bash
   security find-identity -v -p codesigning
   # → "Developer ID Application: Your Name (TEAMID)"
   ```

5. Create an App Store Connect API key for notarization:
   - [appstoreconnect.apple.com/access/integrations/api](https://appstoreconnect.apple.com/access/integrations/api)
     → Team Keys → Generate API Key with **Developer** access → download the
     `.p8` file (downloadable only once) and note the **Key ID** and **Issuer ID**.
6. Register the six GitHub secrets:

   ```bash
   base64 -i DeveloperID.p12 | gh secret set APPLE_CERTIFICATE_P12 --repo tkhwang/workbranch
   gh secret set APPLE_CERTIFICATE_PASSWORD --repo tkhwang/workbranch   # the .p12 export password
   gh secret set APPLE_SIGNING_IDENTITY --repo tkhwang/workbranch      # e.g. "Developer ID Application: Your Name (TEAMID)"
   base64 -i AuthKey_XXXXXXXXXX.p8 | gh secret set APPLE_NOTARY_KEY --repo tkhwang/workbranch
   gh secret set APPLE_NOTARY_KEY_ID --repo tkhwang/workbranch         # the Key ID
   gh secret set APPLE_NOTARY_ISSUER_ID --repo tkhwang/workbranch      # the Issuer ID
   ```

7. The next companion release is signed and notarized automatically. Then send
   a tap PR removing the `--no-quarantine` caveat from
   `Casks/workbranch-companion.rb`.
````

기존 README 하단의 "deferred to the rewritten 0018 release-plumbing plan" 문장은 "release automation is implemented by plan 0020"으로 교체한다.

- [x] **Step 2: plan 참조 정리**

- `docs/plans/0015-task-memo-noti-and-json-listing.md:5`: `0018 (re-written with cask/native assumptions)` → `0020 (brew cask distribution)`.
- `docs/plans/0019-companion-native-menubar-app.md`: 시리즈 위치(line 5)의 `0018 배포 배관(cask 기준으로 재작성 필요)` → `0020 brew cask 배포`, 본문 내 "재작성될 0018" 계열 표현은 `0020`으로 치환(파일 구조 항의 `0018 ... 재작성 필요 표기` 라인은 `0018 삭제(0020이 대체)`로 수정).
- `README.md` / `README.ko.md`: companion section의 local preview/public cask planned 문구를 Homebrew cask 설치 안내로 갱신한다.
- `docs/plans/0018-companion-release-plumbing.md`가 남아 있으면 `git rm`으로 삭제한다(plan 작성 시점에 이미 삭제되어 보통은 불필요).
- 0017과 0020은 superseded/대체 이력을 설명하는 문서이므로 내부의 0018 언급을 유지할 수 있다.

- [x] **Step 3: 검증**

```bash
grep -rn "0018" docs/plans/ companion/README.md README.md README.ko.md | grep -v -E "0017-companion-swiftbar-plugin.md|0020-companion-brew-distribution.md"
```

로컬 검증 결과(2026-06-13):

- `cd companion && swift build && swift test && swift run CompanionCoreTestRunner` 통과.
- `bash -n companion/scripts/build-app.sh`, native `./scripts/build-app.sh`, `PlistBuddy` version 확인 통과.
- `WORKBRANCH_COMPANION_UNIVERSAL=1 ./scripts/build-app.sh`는 이 machine의 selected developer dir가 Command Line Tools(`/Library/Developer/CommandLineTools`)이고 `xcrun --find xcbuild`가 실패해서 로컬 검증 불가. 단일 arch `swift build -c release --product WorkbranchCompanion --arch $(uname -m)`은 통과했고, universal path의 실제 검증은 Xcode 16 계열이 기본인 GitHub `macos-15` runner의 `companion-release.yml` acceptance로 둔다.
- release JSON parse, workflow YAML parse, `companion-release.yml` 모든 `run:` shell block `bash -n`, stale doc grep, `/bin/bash -n bin/workbranch install.sh tests/run.sh scripts/build-workbranch.sh companion/scripts/build-app.sh`, `git diff --check` 통과.
- `./tests/run.sh` 통과: `Tests passed: 208`.

Expected: 출력 없음(0017/0020 내부 역사 언급 제외).

검증 결과(2026-06-13): 0017/0020 이력 문서 제외 후 `0018` grep 출력 없음. `README.md`, `README.ko.md`, `companion/README.md`, `0015`, `0019`에서 `local preview`, `public cask distribution is planned separately`, `release-plumbing plan`, `재작성 필요`, `별도 release-plumbing` stale 문구 grep 출력 없음.

- [ ] **Step 4: Commit**

plan-execute 안전 게이트에 따라 이 실행에서는 commit하지 않는다. 적용 시 아래 커밋을 별도로 수행한다.

```bash
git add companion/README.md README.md README.ko.md docs/plans/
git commit -m "docs(companion): add brew install and signing guide, replace plan 0018 with 0020"
```

### Task 7: 첫 release rollout (merge 후, 일부 수동)

이 task는 PR merge 이후 GitHub에서 진행한다. 코드 변경 없음.

- [ ] **Step 1: 0020 PR 단독 merge**

mixed commit 없이 이 계획의 변경만 담은 PR을 merge한다. 0020의 release-plumbing/docs/workflow commit은 non-releasing type이어야 하며, root `exclude-paths`와 commit discipline 때문에 CLI root release PR은 새로 생기면 안 된다(이미 pending CLI 변경이 있던 경우는 별도). companion release PR(`release: workbranch-companion 0.1.0`)이 생성되는지 확인한다.

- [ ] **Step 2: companion release PR 검토/merge**

- PR이 `companion/CHANGELOG.md`에 기존 `feat(companion)` history를 채우는지 확인.
- PR이 `companion/scripts/build-app.sh`의 `APP_VERSION`을 `0.1.0`으로 유지/갱신하는지 확인.
- PR이 companion source/history만 release 대상으로 삼고, root(`.`) version / `bin/workbranch` / `CHANGELOG.md`를 건드리지 않는지 확인 — 건드린다면 merge하지 말고 root `exclude-paths`와 commit type을 점검한다.
- merge → tag `workbranch-companion-v0.1.0` + GitHub release 생성 확인.

- [ ] **Step 3: companion-release.yml 동작 확인**

- Actions에서 run이 green인지 확인.
- release에 `WorkbranchCompanion-0.1.0.zip` asset이 붙었는지 확인.
- tap에 `Casks/workbranch-companion.rb`가 생성되거나 기존 cask가 version/sha256 bump되었는지 확인.
- `homebrew-bump.yml`이 companion tag에서 skip되었는지 확인(job이 실행 안 됨).

- [ ] **Step 4: tap cask 내용 확인**

workflow가 생성/갱신한 `tkhwang/homebrew-tap`의 `Casks/workbranch-companion.rb`가 release asset sha256과 일치하는지 확인한다:

```bash
curl -fsSL -o /tmp/WorkbranchCompanion-0.1.0.zip \
  https://github.com/tkhwang/workbranch/releases/download/workbranch-companion-v0.1.0/WorkbranchCompanion-0.1.0.zip
shasum -a 256 /tmp/WorkbranchCompanion-0.1.0.zip
```

```ruby
cask "workbranch-companion" do
  version "0.1.0"
  sha256 "<위에서 계산한 sha256>"

  url "https://github.com/tkhwang/workbranch/releases/download/workbranch-companion-v#{version}/WorkbranchCompanion-#{version}.zip"
  name "Workbranch Companion"
  desc "Menu bar companion for the workbranch CLI"
  homepage "https://github.com/tkhwang/workbranch"

  depends_on macos: ">= :ventura"

  app "WorkbranchCompanion.app"

  caveats <<~EOS
    This app is currently ad-hoc signed. Install with --no-quarantine:
      brew install --cask --no-quarantine tkhwang/tap/workbranch-companion
    If already installed and blocked by Gatekeeper:
      xattr -dr com.apple.quarantine "/Applications/WorkbranchCompanion.app"
  EOS
end
```

- [ ] **Step 5: 설치 검증**

```bash
brew untap tkhwang/tap 2>/dev/null; brew tap tkhwang/tap
brew install --cask --no-quarantine tkhwang/tap/workbranch-companion
open "/Applications/WorkbranchCompanion.app"
pgrep -fl WorkbranchCompanion
```

Expected: 설치 성공, app process 확인, menu bar에 icon 표시. `brew uninstall --cask workbranch-companion`으로 정리 가능.

- [ ] **Step 6: 차기 companion release에서 cask 자동 bump 확인**

다음 `workbranch-companion-v*` release에서 `companion-release.yml`이 기존 cask의 version/sha256을 자동 갱신하고 tap에 push하는지 확인한다.

- [ ] **Step 7: CLI release 무손상 확인**

0020 merge 이후 첫 CLI `v*` release에서 기존 경로가 그대로 동작하는지 관찰한다: release-please root PR → plain `v*` tag → `bin/workbranch` marker bump → `homebrew-bump.yml`이 `Formula/workbranch.rb` 갱신 → `brew upgrade workbranch` 성공.

## 검증

```bash
# 로컬 (PR 전)
bash -n companion/scripts/build-app.sh
cd companion && ./scripts/build-app.sh && /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" dist/WorkbranchCompanion.app/Contents/Info.plist
python3 -c "import json; json.load(open('release-please-config.json')); json.load(open('.release-please-manifest.json'))"
ruby -ryaml -e "%w[.github/workflows/companion-ci.yml .github/workflows/companion-release.yml .github/workflows/homebrew-bump.yml].each { |f| YAML.load_file(f) }; puts 'OK'"
grep -rn "0018" docs/plans/ companion/README.md README.md README.ko.md | grep -v -E "0017-companion-swiftbar-plugin.md|0020-companion-brew-distribution.md"
```

merge 후 acceptance (Task 7):

- companion release PR 생성 → merge → `workbranch-companion-v0.1.0` release + zip asset
- `homebrew-bump.yml` companion tag skip
- 첫 companion release에서 cask 생성 후 `brew install --cask --no-quarantine` + app 실행
- 두 번째 companion release에서 기존 cask 자동 bump
- 첫 CLI `v*` release 무손상 관찰

## 위험과 완화

- **기존 CLI release 파손:** root는 plain `v*` tag와 `bin/workbranch` extra-file을 보존하고, `exclude-paths`로 `companion`/`.github`/`docs`와 root companion docs/metadata-only commit을 root release에서 제외한다. release plumbing/config/docs/workflow commit은 계속 non-releasing commit type으로 관리한다. companion release PR이 root 버전을 건드리면 merge하지 않는다.
- **release-please two-package 전환 surprise:** manifest seed `0.0.0` + 기존 `feat(companion)` history 조합이 첫 PR에서 의도(0.1.0)와 다른 버전을 제안할 수 있다. release PR 검토 단계(Task 7 Step 2)를 acceptance gate로 두고, 어긋나면 config의 `release-as`로 한 번 고정한다.
- **sha256 race:** cask bump를 zip asset 업로드와 같은 job에서 순서대로 수행해 구조적으로 제거한다.
- **Gatekeeper (ad-hoc 과도기):** cask caveats + README로 `--no-quarantine`을 안내한다. Developer ID secrets 등록 후 자동으로 서명/공증되며, 그 시점에 caveats 제거 tap PR을 만든다.
- **macOS 15 runner 명령 차이:** `base64 -w0` 미지원 → `base64 | tr -d '\n'`. workflow 작성 시 ubuntu용 homebrew-bump.yml을 그대로 복사하지 않는다.
- **universal build 경로:** `--arch` 동시 지정 시 SPM 출력 경로가 `.build/apple/Products/Release/`로 바뀐다. build-app.sh가 분기로 처리하고, CI smoke(companion-ci.yml은 native, companion-release.yml은 universal)로 양쪽을 커버한다.
- **첫 release에서 cask 부재:** silent skip 금지. workflow가 `Casks/workbranch-companion.rb`를 생성해 첫 release부터 문서화된 brew install 경로를 제공한다. 기존 cask가 있으면 version/sha256만 bump한다.
