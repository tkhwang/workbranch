# 0018 Companion 배포 배관 계획

> **상태: 재작성 필요. 이 계획을 현재 형태로 실행하지 않는다.**
> 0017(SwiftBar/TypeScript)이 [0019](0019-companion-native-menubar-app.md)(native SwiftUI app)로 대체되면서 이 계획의 npm/`package.json`/SwiftBar bundle/formula 전제가 stale해졌다. public 배포 전 "GitHub release에 `.app` zip + 개인 tap `Casks/workbranch-companion.rb` + `swift build` CI + Developer ID 서명/notarization" 기준으로 재작성한다. release-please two-package 구성과 tag 분리(`workbranch-companion-v*`) 방향 자체는 유효하다.

> **agentic worker 지침:** 이 계획은 release automation만 수정한다. `src/workbranch/**` 동작 변경과 `bin/workbranch` 재생성은 하지 않는다. 실행 시 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용하고, workflow/config 검증과 실제 `v*` CLI release 관찰을 acceptance gate로 삼는다.
>
> **시리즈 위치:** companion 공개 배포 직전에 실행하는 deferred distribution step이다. 현재 순서: 0015 memo/noti/json → 0017 메모 우선 local companion → **0018 배포 배관**. 이 계획은 companion을 local로 만들거나 설치하는 데 필요하지 않다.

**목표:** 이미 구현된 `companion/` 패키지를 Bash CLI와 독립적으로 release할 수 있게 한다. CLI는 기존 plain `v*` tag와 `Formula/workbranch.rb` Homebrew flow를 유지하고, companion은 나중에 `workbranch-companion-v*` tag와 별도 formula로 배포한다.

**아키텍처:** release-please manifest mode를 두 package로 구성한다. root package `.`는 `workbranch`로 유지하고 `include-component-in-tag: false`로 기존 `v*` tag shape를 보존한다. `companion/`은 `workbranch-companion` component package로 추가한다. `homebrew-bump.yml`은 tag prefix에 따라 CLI formula 또는 companion formula를 dispatch하며, companion formula가 tap에 없으면 성공 skip한다.

**기술 스택:** release-please config/manifest JSON, GitHub Actions, npm package metadata, Homebrew tap `tkhwang/homebrew-tap`.

**제품 관점:** 이 계획은 companion 제품 기능이 아니라 배포 배관이다. task memo UX를 빠르게 검증하기 위해 0017 local companion 이후, public companion release 직전에 실행한다.

---

## 문제

CLI와 companion은 release cadence가 다르다. CLI는 이미 `v*` tag와 Homebrew formula flow가 있고, companion은 Node/SwiftBar artifact로 별도 changelog와 package lifecycle이 필요하다. release automation을 잘못 바꾸면 기존 `brew upgrade workbranch`가 깨질 수 있으므로 이 계획은 단독으로 landing하고 실제 CLI release를 관찰해야 한다.

## 현재 repo 근거

- `release-please-config.json`: 현재 root package만 관리하고 `bin/workbranch` version marker를 갱신한다.
- `.release-please-manifest.json`: 현재 root version만 가진다.
- `.github/workflows/homebrew-bump.yml`: 현재 `v*` tag만 허용하고 `Formula/workbranch.rb`만 갱신한다.
- `.github/workflows/ci.yml`: Bash CLI integration suite를 실행한다.
- 이 계획 실행 시점에는 0017이 만든 `companion/package.json`, `package-lock.json`, build/test/typecheck script, SwiftBar bundle이 존재해야 한다.

## 결정 사항

- [x] **0016 dependency 없음.**
  - focus/open-warp는 release plumbing과 무관하다. companion launch action은 기존 `finder`, `ide`, `terminal`로 충분하다.

- [x] **0017 이후 실행.**
  - 임시 `companion/package.json`을 만들지 않는다. 0017의 실제 package를 대상으로 release plumbing을 붙인다.

- [x] **root package는 `.` 유지, tag는 plain `v*` 유지.**
  - 기존 CLI 사용자와 Homebrew formula 호환성을 보존한다.

- [x] **companion tag shape:** `workbranch-companion-vX.Y.Z`.
  - CLI release와 companion release를 명확히 분리한다.

- [x] **companion CI는 별도 path-filtered workflow.**
  - `.github/workflows/companion-ci.yml`을 추가하고 기존 `.github/workflows/ci.yml`은 CLI 전용으로 유지한다.

- [x] **lockfile 필수, `npm ci` 사용.**
  - `companion/package-lock.json`을 기준으로 reproducible install을 검증한다.

- [x] **tap formula는 외부 follow-up.**
  - `Formula/workbranch-companion.rb`가 없으면 companion tag path는 log 후 exit 0 한다.

## public release contract

1. CLI release:
   - tag: `vX.Y.Z`
   - changelog: root `CHANGELOG.md`
   - formula: `Formula/workbranch.rb`
   - generated CLI version marker 유지

2. Companion release:
   - tag: `workbranch-companion-vX.Y.Z`
   - changelog: `companion/CHANGELOG.md`
   - formula: future `Formula/workbranch-companion.rb`
   - npm publish 없음, GitHub release artifact/Homebrew 기반

3. commit discipline:
   - companion-only 변경은 `feat(companion): ...`, `fix(companion): ...` scope 사용
   - CLI와 companion을 동시에 release하려는 의도가 아니면 mixed commit 금지

## 파일 구조

```text
release-please-config.json           # root + companion package
.release-please-manifest.json        # root version + companion version
.github/workflows/homebrew-bump.yml  # v* / workbranch-companion-v* dispatch
.github/workflows/companion-ci.yml   # companion npm ci/typecheck/test/build
companion/package.json               # 0017에서 만든 실제 package metadata/scripts
companion/package-lock.json          # npm ci 기준 lockfile
companion/CHANGELOG.md               # companion release notes
```

## 구현 작업

### Task 1: companion package preflight

- [ ] `companion/package.json`이 존재하고 `private: true`, `typecheck`, `test`, `build` script를 가진다.
- [ ] `companion/package-lock.json`이 존재한다.
- [ ] `cd companion && npm ci`가 성공한다.
- [ ] `cd companion && npm run typecheck && npm test && npm run build`가 성공한다.

### Task 2: release-please two-package config

- [ ] `release-please-config.json`에서 root package behavior를 보존한다.
  - `include-component-in-tag: false` 유지
  - 기존 extra-file version bump 유지
- [ ] `companion` package entry를 추가한다.
  - `package-name: workbranch-companion`
  - Node-compatible release type
  - `include-component-in-tag: true`
- [ ] `.release-please-manifest.json`에 현재 companion version을 추가한다.
- [ ] 필요하면 `companion/CHANGELOG.md`를 seed한다.
- [ ] release-please dry run 또는 scratch branch PR로 root/companion release section을 확인한다.

### Task 3: Homebrew bump tag dispatch

- [ ] `.github/workflows/homebrew-bump.yml`의 tag guard를 dispatch로 바꾼다.
  - `v*`: 기존 `Formula/workbranch.rb` update path 유지
  - `workbranch-companion-v*`: `Formula/workbranch-companion.rb` update path
  - formula file이 없으면 “tap formula not present yet — skipping” 로그 후 exit 0
  - 그 외 tag는 fail
- [ ] `v*` path diff가 기존 tarball/sha256/formula update 동작을 바꾸지 않는지 확인한다.
- [ ] 가능한 경우 workflow lint 또는 local dry run으로 세 tag shape를 검증한다.

### Task 4: Companion CI workflow

- [ ] `.github/workflows/companion-ci.yml` 추가.
- [ ] Node 20 사용, `working-directory: companion` 설정.
- [ ] trigger path:
  - `companion/**`
  - `.github/workflows/companion-ci.yml`
  - `release-please-config.json`
  - `.release-please-manifest.json`
- [ ] job command:
  - `npm ci`
  - `npm run typecheck`
  - `npm test`
  - `npm run build`
- [ ] 기존 `.github/workflows/ci.yml`는 CLI-only PR에서 계속 Bash suite를 실행하도록 변경하지 않는다.

### Task 5: public companion release 전 acceptance

- [ ] 0018 변경은 단독으로 merge한다.
- [ ] 변경 후 실제 CLI release를 하나 관찰한다.
  - release-please root PR 생성
  - tag가 plain `v*`
  - `bin/workbranch` version marker bump
  - `homebrew-bump.yml`이 `Formula/workbranch.rb` 갱신
  - `brew upgrade workbranch` 성공
- [ ] `tkhwang/homebrew-tap`에 `Formula/workbranch-companion.rb`를 별도 외부 변경으로 추가한다.
- [ ] 첫 companion release를 publish하고 `workbranch-companion-v*` path가 formula를 갱신하는지 확인한다.

## 검증

- release-please config/manifest JSON parse
- companion package `npm ci/typecheck/test/build`
- workflow lint 또는 dry run
- 실제 CLI `v*` release 관찰
- 첫 companion release 전 tap formula 존재 확인

## 위험과 완화

- **기존 CLI release 파손:** root config와 `v*` path를 보존하고, 0018을 단독 landing한다.
- **release-please manifest migration surprise:** dry run 또는 scratch PR로 확인한다.
- **mixed commit으로 양쪽 package가 동시에 bump:** companion/CLI commit을 분리한다.
- **companion formula 부재:** guarded skip으로 workflow 실패를 막는다.
