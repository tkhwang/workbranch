# 0023 Companion Apple Developer ID 서명·공증 활성화 계획

> **agentic worker 지침:** 이 계획의 대부분은 **유지보수자(사람)의 수동 작업**이다 — Apple Developer 포털, Keychain Access(GUI), App Store Connect는 자동화할 수 없다. agent가 수행할 수 있는 부분은 (a) `.p12`/`.p8` 검증, (b) base64 인코딩, (c) `gh secret set` 등록, (d) `gh workflow run`으로 서명 파이프라인 검증, (e) `README.md`/`companion/README.md` 문구 갱신, (f) tap cask caveat 제거 PR, (g) `.github/workflows/companion-release.yml`의 cask **최초 생성 template**에서 stale ad-hoc caveat 제거뿐이다. `src/workbranch/**`, `bin/workbranch`, companion Swift 코드(`companion/Sources/**`, `companion/Tests/**`), release-please 설정은 **건드리지 않는다**. 워크플로의 서명/공증 실행 로직은 수정하지 않는다(서명/공증 step은 0020에서 이미 guarded 상태로 구현되어 있고, 이번에는 cask 재생성 시 notarized release에는 stale 문구가 되살아나지 않게 하고, unsigned/not-notarized fallback에는 recovery caveat을 보존하도록 template 문구만 조건화한다).
>
> **시리즈 위치:** 0020(companion brew 배포)의 마지막 미체크 follow-up 항목 — "Developer ID secrets 등록과 공증 활성화"를 실행하는 계획이다. 0020은 ad-hoc 서명 + `--no-quarantine`으로 배포 파이프라인을 완성했고, companion은 이미 `1.3.0`까지 release되어 운영 중이다. 이 계획은 **새 Apple 자격증명을 발급**해서 그 파이프라인을 Developer ID 서명 + notarization으로 업그레이드한다.

**목표:** `WorkbranchCompanion.app` release를 **새로 발급한** Developer ID Application 인증서로 서명하고 Apple notary 서비스로 공증·staple해서, 사용자가 `--no-quarantine` 없이 `brew install --cask tkhwang/tap/workbranch-companion`으로 설치할 수 있게 한다.

**배경 — 왜 "새로" 만드는가:** 과거 백업(`~/Documents/tkhwang.dev/apple-developer/Archive`)에 Developer ID Application 인증서(`Developer ID Application: Taekeun Hwang (KCH4T8K4RS)`, 2026-02 발급)와 notary `.p8`(Key ID `M3S4NCA49U`)이 존재하지만, **이번에는 재사용하지 않고 새 자격증명을 발급**한다. 새 인증서/키로 secret을 등록하고, 기존 백업 자격증명은 (한 번도 배포에 사용된 적 없으므로) 안전하게 revoke한다.

**아키텍처:** 변경 없음. 0020이 구축한 `companion-release.yml`의 guarded 구조를 그대로 쓴다 — secret 6개가 존재하면 `Sign with Developer ID` step(`codesign --options runtime --timestamp`)과 `Notarize and staple` step(`notarytool submit --wait` → `stapler staple` → 재zip)이 실행되고, 없으면 ad-hoc로 skip된다. 이 계획은 그 6개 secret을 채우는 것이 본질이다.

**검증 경로의 핵심:** `companion-release.yml`에는 `workflow_dispatch` (입력 `tag`)가 있다. 따라서 **새 release를 만들지 않고** 기존 태그 `workbranch-companion-v1.3.0`을 입력으로 워크플로를 수동 실행해서 서명·공증 파이프라인을 end-to-end 검증할 수 있다. 이 실행은 기존 release asset을 서명된 zip으로 `--clobber` 교체하고 cask sha256을 갱신하므로, 검증과 동시에 현재 배포본을 서명본으로 업그레이드하는 효과가 있다.

## 진행 상태 (2026-06-14)

- [x] GitHub Actions Apple secret 6개 등록 확인: `APPLE_CERTIFICATE_P12`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_NOTARY_KEY`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID`.
- [x] `companion-release.yml` workflow_dispatch 검증: run `27480803909` success, `.p12` import, Developer ID `codesign`, `notarytool` Accepted, `stapler` validate 성공.
- [x] 배포 asset 로컬 검증: `WorkbranchCompanion-1.3.0.zip` sha256 `e3d19c4407fec8dafdbcad33ae068ad3213fb900ec8fa82634d9f1ce7be0282b`, `codesign --verify --deep --strict` 통과, `spctl` `source=Notarized Developer ID`, `xcrun stapler validate` 통과.
- [x] repo 문서 정리: `README.md`, `README.ko.md`, `companion/README.md`에서 Homebrew 설치 안내의 quarantine bypass 문구 제거.
- [x] workflow template 하드닝: Decision 1 보완에 따라 `.github/workflows/companion-release.yml`의 cask 최초 생성 template은 notarized release에는 caveat을 만들지 않고, unsigned/not-notarized fallback에는 Gatekeeper recovery caveat을 조건부로 유지한다.
- [ ] tap cask caveat 제거 PR: `tkhwang/homebrew-tap` local checkout에 caveat 제거 변경 준비 완료. commit/push/PR은 별도 git publish 단계에서 수행.
- [ ] 최종 사용자 경로 확인: caveat 제거 PR 반영 후 `brew install --cask tkhwang/tap/workbranch-companion`로 설치·실행 확인.

---

## 초기 문제(해결됨)

이 계획을 시작할 때는 0020으로 배포 배관은 완성됐지만 release가 **ad-hoc 서명**으로 나가고 있어, 사용자가 Gatekeeper를 우회하려고 `--no-quarantine`를 붙여야 했다. 당시 GitHub Actions secret에는 `RELEASE_PLEASE_TOKEN`, `TAP_GITHUB_TOKEN`만 있었고 Apple 관련 6개(`APPLE_CERTIFICATE_P12`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_NOTARY_KEY`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID`)가 등록되어 있지 않아 서명/공증 step이 항상 skip됐다.

현재 상태는 위 `진행 상태 (2026-06-14)`가 source of truth다. Apple secret 6개는 모두 등록 확인됐고, `companion-release.yml` workflow_dispatch run `27480803909`로 Developer ID 서명, notarization, staple, release asset 교체, cask sha256 갱신까지 검증됐다. 남은 작업은 secret 등록 자체가 아니라 tap caveat 제거 PR과 최종 사용자 설치 경로 확인이다.

## 근거와 검증 기록

- `.github/workflows/companion-release.yml`:
  - `Sign with Developer ID (skipped until secrets are set)` step — `APPLE_CERTIFICATE_P12`가 비어 있으면 `exit 0`(ad-hoc 유지), 있으면 임시 keychain에 `.p12` import 후 `codesign --force --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY"`.
  - `Notarize and staple (skipped until secrets are set)` step — `APPLE_NOTARY_KEY`가 비어 있으면 `exit 0`, 있으면 `xcrun notarytool submit "$ZIP_NAME" --key … --key-id … --issuer … --wait` → `xcrun stapler staple` → `ditto`로 재zip.
  - `workflow_dispatch` 입력 `tag`로 임의 companion 태그를 수동 재실행 가능.
  - **중요(부분 등록 위험):** 두 step은 "해당 secret이 **존재하면** 무조건 실행"한다. `APPLE_CERTIFICATE_P12`만 등록하고 password를 빠뜨리면 `security import`가 실패해 release 워크플로가 깨진다. → **6개를 한 번에** 등록해야 한다.
- `Update cask version and sha256` step의 python: cask 파일이 **이미 존재하면** version/sha256 두 줄만 정규식 치환하고 **caveat 블록은 건드리지 않는다**. cask가 없을 때(최초 생성)는 notarization 성공 여부에 따라 caveat을 조건부 생성한다. → tap에서 caveat을 한 번 수동 제거하면 이후 signed/notarized 자동 bump가 caveat-free 상태를 보존하고, unsigned/not-notarized 최초 생성 fallback에는 recovery caveat을 남긴다.
- `companion/README.md`: "Release signing setup (maintainer guide)" 섹션에 동일한 secret 6개 이름과 등록 절차가 이미 문서화되어 있다(0020 Task 6). 이 계획은 그 가이드를 실행하고, `README.md`, `README.ko.md`, `companion/README.md` 설치 안내의 `--no-quarantine` 문구를 정리한다.
- 등록된 secret(초기 상태): `RELEASE_PLEASE_TOKEN`, `TAP_GITHUB_TOKEN`. Apple secret 6개 부재.
- 등록된 secret(2026-06-14 확인): `APPLE_CERTIFICATE_P12`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_NOTARY_KEY`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID` 6개가 모두 존재한다.
- 검증 실행(2026-06-14): `companion-release.yml` workflow_dispatch run `27480803909`가 성공했고, 로그에서 `.p12` import, Developer ID `codesign`, `notarytool` Accepted, `stapler` validate 성공을 확인했다.
- 배포 asset 검증(2026-06-14): `WorkbranchCompanion-1.3.0.zip` sha256 `e3d19c4407fec8dafdbcad33ae068ad3213fb900ec8fa82634d9f1ce7be0282b`, `codesign --verify --deep --strict` 통과, `spctl` `source=Notarized Developer ID`, `xcrun stapler validate` 통과.
- tap cask(원격 `tkhwang/homebrew-tap`): version/sha256은 서명본과 일치하지만, caveat 블록은 아직 ad-hoc/`--no-quarantine` 안내를 담고 있다.
- repo public docs: `README.md`, `README.ko.md`, `companion/README.md` 모두 아직 ad-hoc/`--no-quarantine` 안내를 담고 있었다.
- companion 현재 버전: `.release-please-manifest.json`의 `"companion": "1.3.0"`. 최신 companion 태그 `workbranch-companion-v1.3.0` 존재.

## 결정 사항

- [x] **Decision 1: workflow 최초 생성 cask template 하드닝을 포함한다.**
  - 영향: public cask 생성 경로와 설치 안내 계약.
  - 근거: 서명/공증이 활성화된 뒤에도 `.github/workflows/companion-release.yml`의 cask 최초 생성 template에는 ad-hoc/`--no-quarantine` caveat이 남아 있었다.
  - 결정: 서명/공증 실행 로직의 fallback 계약은 유지하고, workflow env로 notarization 성공 여부를 기록해 최초 생성 cask template에서 caveat을 조건부로 만든다.
  - 상태: resolved: A(포함).

- [ ] **자격증명은 전부 새로 발급한다. 백업(Archive)은 재사용하지 않고 revoke한다.**
  - 백업 인증서/키는 한 번도 배포 서명에 쓰이지 않았으므로 revoke해도 기존 사용자에게 영향이 없다.
  - Apple은 Developer ID Application 인증서 개수에 상한이 있으므로(계정당 소수), 새로 만들기 전에 또는 직후에 옛 인증서를 revoke해 슬롯을 정리한다.

- [ ] **Team/identity 문자열은 동일 계정이면 그대로다.**
  - 같은 Apple Developer 계정(Team `KCH4T8K4RS`)으로 재발급하면 새 Developer ID Application 인증서의 common name도 `Developer ID Application: Taekeun Hwang (KCH4T8K4RS)`가 된다. 즉 `APPLE_SIGNING_IDENTITY` 값은 바뀌지 않을 가능성이 크다 — 단, 발급 후 `security find-identity`로 **반드시 실제 문자열을 확인**해서 등록한다(이름/팀이 다르면 그 값을 쓴다).

- [ ] **notary API 키도 새로 발급한다.**
  - 새 App Store Connect API 키(`.p8`)를 **Developer** 접근 권한으로 발급한다. `.p8`는 단 한 번만 다운로드 가능하므로 즉시 안전한 곳에 보관한다. Key ID는 파일명/포털에서, Issuer ID는 Keys 탭 상단에서 얻는다. 옛 키 `M3S4NCA49U`는 revoke한다.

- [ ] **6개 secret은 한 번에 등록한다(부분 등록 금지).**
  - 워크플로의 "secret 있으면 실행" 구조 때문에 부분 등록은 다음 release를 깨뜨린다. 등록 전 `.p12` 내용을 로컬 검증해 잘못된 password/빈 키로 인한 release 실패를 예방한다.

- [ ] **검증은 `workflow_dispatch`로 기존 태그를 재실행해서 한다.**
  - `workbranch-companion-v1.3.0`을 입력으로 `companion-release.yml`을 수동 실행한다. 새 버전을 cut하지 않고 서명→공증→staple→asset 교체→cask sha256 갱신 전 과정을 검증한다. 부수효과로 현재 배포본이 서명본으로 업그레이드된다.

- [ ] **서명·공증 확인 후 `--no-quarantine` 안내를 제거한다.**
  - tap의 `Casks/workbranch-companion.rb`에서 caveat 블록을 제거하는 PR을 한 번 만든다(이후 자동 bump가 caveat-free를 유지). 같은 변경을 `companion/README.md` 설치 섹션에도 반영한다.

- [x] **워크플로/Swift/release-please 경계:** Swift/release-please/서명·공증 실행 로직은 수정하지 않는다. 단, Decision 1에 따라 `.github/workflows/companion-release.yml`의 cask 최초 생성 template에서 notarized release에는 caveat을 생략하고 unsigned/not-notarized fallback에는 caveat을 유지한다.

## 자격증명 → secret 매핑 (목표 상태)

| GitHub Secret | 값/출처 | 비고 |
|---|---|---|
| `APPLE_CERTIFICATE_P12` | 새 `.p12`의 base64 | `base64 -i NewCert.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | 새 `.p12` export 비밀번호 | Keychain export 시 설정 |
| `APPLE_SIGNING_IDENTITY` | `security find-identity -v -p codesigning` 출력 문자열 | 예: `Developer ID Application: Taekeun Hwang (KCH4T8K4RS)` |
| `APPLE_NOTARY_KEY` | 새 `.p8`의 base64 | `base64 -i AuthKey_XXXX.p8` |
| `APPLE_NOTARY_KEY_ID` | 새 API 키의 Key ID | 파일명/포털 |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect Issuer ID(UUID) | Keys 탭 상단 |

## 파일 구조

```text
(외부, 수동) Apple Developer 포털: 새 Developer ID Application 인증서, 옛 인증서 revoke
(외부, 수동) Keychain Access: CSR 생성, .cer 설치, .p12 export
(외부, 수동) App Store Connect: 새 notary API 키 발급, Issuer ID 확인, 옛 키 revoke
(외부, 명령) GitHub repo secrets: 6개 등록 (gh secret set)
(외부, 검증) GitHub Actions: companion-release.yml workflow_dispatch (tag=workbranch-companion-v1.3.0)
(외부 repo) tkhwang/homebrew-tap: Casks/workbranch-companion.rb caveat 제거 PR
README.md                                       # companion 설치 섹션 --no-quarantine 제거
README.ko.md                                    # localized companion 설치 섹션 --no-quarantine 제거
companion/README.md                             # 설치 섹션 --no-quarantine 제거, 가이드 최신화
.github/workflows/companion-release.yml          # 최초-생성 cask caveat 조건화 — Decision 1/P2 review resolved
```

## 구현 작업

### Task 1: 옛 자격증명 revoke (정리)

이 task는 Apple 포털에서 수동으로 진행한다. 코드 변경 없음.

- [ ] **Step 1: 옛 Developer ID Application 인증서 확인**
  - [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates/list)에서 `Developer ID Application: Taekeun Hwang (KCH4T8K4RS)`(2026-02 발급) 항목을 확인한다.
  - 이 인증서로 배포 서명한 적이 없으므로 revoke 가능. 단, **새 인증서 발급 후 revoke해도 무방**하다(슬롯 상한에 걸리면 먼저 revoke).

- [ ] **Step 2: 옛 notary API 키 revoke**
  - [appstoreconnect.apple.com/access/integrations/api](https://appstoreconnect.apple.com/access/integrations/api)에서 Key ID `M3S4NCA49U` 키를 Revoke한다.

- [ ] **Step 3: 백업 디렉토리 보관/정리**
  - `~/Documents/tkhwang.dev/apple-developer/Archive`의 옛 자료는 더 이상 쓰지 않는다. 새 자격증명은 별도 안전 위치에 보관한다.

### Task 2: 새 Developer ID Application 인증서 발급

수동(Keychain Access + Apple 포털).

- [ ] **Step 1: CSR 생성**
  - Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority → User Email Address 입력, "Saved to disk" 선택 → `CertificateSigningRequest.certSigningRequest` 저장.

- [ ] **Step 2: 인증서 발급/설치**
  - [developer.apple.com/account/resources/certificates/add](https://developer.apple.com/account/resources/certificates/add) → **Developer ID Application** 선택 → 위 CSR 업로드 → 발급된 `.cer` 다운로드 → 더블클릭해 login keychain에 설치.

- [ ] **Step 3: `.p12` export**
  - Keychain Access → My Certificates → 새 "Developer ID Application: …" 항목 우클릭 → Export → `.p12` 저장, **export 비밀번호 설정**(이 값이 `APPLE_CERTIFICATE_PASSWORD`).

- [ ] **Step 4: signing identity 문자열 확인**

```bash
security find-identity -v -p codesigning
# → "Developer ID Application: Taekeun Hwang (KCH4T8K4RS)" 형태의 문자열을 그대로 사용
```

Expected: Developer ID Application 항목이 1개 이상. 그 따옴표 안 문자열이 `APPLE_SIGNING_IDENTITY`.

### Task 3: 새 App Store Connect notary API 키 발급

수동(App Store Connect).

- [ ] **Step 1: API 키 생성**
  - [appstoreconnect.apple.com/access/integrations/api](https://appstoreconnect.apple.com/access/integrations/api) → Keys 탭 → Generate API Key → 접근 권한 **Developer** → `.p8` 다운로드(**한 번만 가능**).

- [ ] **Step 2: Key ID / Issuer ID 기록**
  - Key ID: 새 키 행 또는 파일명 `AuthKey_<KEYID>.p8`에서.
  - Issuer ID: Keys 탭 상단의 "Issuer ID"(UUID).

### Task 4: `.p12` 검증 후 GitHub secret 6개 등록

agent 수행 가능(파일 경로/Issuer ID/password를 전달받으면). 등록 전 검증을 반드시 먼저 한다.

- [ ] **Step 1: 새 `.p12` 로컬 검증**

```bash
P12=/path/to/NewCert.p12
read -rs PW            # .p12 export 비밀번호 입력 (화면 미표시)
# 인증서 subject가 Developer ID Application인지
openssl pkcs12 -in "$P12" -nokeys -passin pass:"$PW" 2>/dev/null | openssl x509 -noout -subject
# 개인키가 포함되어 있는지(>=1 이어야 함)
openssl pkcs12 -in "$P12" -nocerts -nodes -passin pass:"$PW" 2>/dev/null | grep -c "PRIVATE KEY"
```

Expected: subject에 `CN=Developer ID Application: Taekeun Hwang (KCH4T8K4RS)`, 개인키 카운트 `>= 1`. 둘 중 하나라도 실패하면 export를 다시 한다(개인키 미포함 `.p12`는 서명 불가).

- [ ] **Step 2: notary `.p8` 검증**

```bash
head -1 /path/to/AuthKey_XXXX.p8   # "-----BEGIN PRIVATE KEY-----"
```

- [ ] **Step 3: secret 6개 등록(한 번에)**

```bash
REPO=tkhwang/workbranch

base64 -i /path/to/NewCert.p12      | gh secret set APPLE_CERTIFICATE_P12 --repo "$REPO"
gh secret set APPLE_CERTIFICATE_PASSWORD --repo "$REPO"   # .p12 export 비밀번호(대화형 입력)
gh secret set APPLE_SIGNING_IDENTITY     --repo "$REPO" --body "Developer ID Application: Taekeun Hwang (KCH4T8K4RS)"
base64 -i /path/to/AuthKey_XXXX.p8  | gh secret set APPLE_NOTARY_KEY --repo "$REPO"
gh secret set APPLE_NOTARY_KEY_ID        --repo "$REPO" --body "<새 Key ID>"
gh secret set APPLE_NOTARY_ISSUER_ID     --repo "$REPO" --body "<Issuer ID UUID>"
```

주의: `APPLE_SIGNING_IDENTITY`는 Task 2 Step 4에서 확인한 **실제 문자열**을 쓴다(팀/이름이 다르면 다른 값). macOS `base64 -i`의 줄바꿈은 워크플로의 `base64 -d`가 무시하므로 무방하다.

- [x] **Step 4: 등록 확인**

```bash
gh secret list --repo tkhwang/workbranch
```

Expected: `APPLE_CERTIFICATE_P12`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_NOTARY_KEY`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID` 6개가 모두 보인다(`TAP_GITHUB_TOKEN`, `RELEASE_PLEASE_TOKEN`과 함께).

### Task 5: 서명·공증 파이프라인 검증 (새 release 없이)

- [x] **Step 1: 기존 태그로 워크플로 수동 실행**

```bash
gh workflow run companion-release.yml \
  -f tag=workbranch-companion-v1.3.0 \
  --repo tkhwang/workbranch
gh run watch --repo tkhwang/workbranch
```

- [x] **Step 2: 로그에서 서명/공증 실제 실행 확인**
  - `Sign with Developer ID` step이 `[skip]`이 **아니라** `codesign … --sign "Developer ID Application…"`을 수행했는지.
  - `Notarize and staple` step이 `notarytool submit … --wait`에서 **Accepted**를 받고 `stapler staple`이 성공했는지.

- [x] **Step 3: 배포 asset의 서명/공증 검증(로컬)**

```bash
cd "$(mktemp -d)"
curl -fsSL -o app.zip \
  https://github.com/tkhwang/workbranch/releases/download/workbranch-companion-v1.3.0/WorkbranchCompanion-1.3.0.zip
ditto -x -k app.zip .
codesign --verify --deep --strict --verbose=2 WorkbranchCompanion.app
codesign -dvvv WorkbranchCompanion.app 2>&1 | grep -E "Authority|TeamIdentifier|Timestamp"
spctl -a -vvv -t install WorkbranchCompanion.app
xcrun stapler validate WorkbranchCompanion.app
```

Expected: `codesign --verify` 통과, Authority에 `Developer ID Application: Taekeun Hwang (KCH4T8K4RS)` + `Developer ID Certification Authority` + `Apple Root CA`, `spctl`이 `accepted` + `source=Notarized Developer ID`, `stapler validate`가 `The validate action worked`.

- [x] **Step 4: cask sha256 갱신 확인**
  - tap의 `Casks/workbranch-companion.rb` sha256이 새(서명된) zip과 일치하는지 확인. 워크플로가 자동 push했어야 한다.

### Task 6: `--no-quarantine` 안내 제거 및 문서 정리

서명·공증이 검증된 **후에만** 수행한다.

- [ ] **Step 1: tap cask caveat 제거 PR**
  - `tkhwang/homebrew-tap`의 `Casks/workbranch-companion.rb`에서 `caveats <<~EOS … EOS` 블록을 제거하는 local 변경은 준비했다. commit/push/PR을 만든다. version/sha256 줄은 유지(자동 bump 정규식이 계속 매칭되어야 한다).
  - 이후 companion release의 자동 bump는 caveat을 다시 추가하지 않는다(기존-파일 경로는 version/sha256만 치환).

- [x] **Step 2: repo README 갱신**
  - `README.md`와 `README.ko.md`의 companion 설치 명령에서 `--no-quarantine`를 제거한다.
  - `companion/README.md`의 "Install via Homebrew" 섹션의 명령에서 `--no-quarantine`를 제거: `brew install --cask tkhwang/tap/workbranch-companion`.
  - ad-hoc/`--no-quarantine`/`xattr -dr com.apple.quarantine` 안내 문단을 "releases are signed with a Developer ID certificate and notarized" 사실 서술로 교체.
  - "Release signing setup (maintainer guide)"는 유지하되, secret이 이제 **등록 완료**임을 한 줄로 표기(재발급 시 절차 참고용).

- [x] **Step 3: 워크플로 최초-생성 caveat 하드닝(Decision 1)**
  - `companion-release.yml`의 cask **최초 생성** 분기(파일 부재 시)에 들어가는 unconditional ad-hoc caveat은, 서명·공증이 상시화된 지금은 부정확하다. 다만 secret 부재/임시 제거 fallback은 여전히 ad-hoc 또는 not-notarized zip을 publish할 수 있으므로, 이 분기에서 `APPLE_RELEASE_NOTARIZED`가 `1`일 때만 caveat을 생략하고 그렇지 않으면 Gatekeeper recovery caveat을 유지한다. 현재 tap에 cask가 존재하므로 기존 release 업데이트 동작상 영향은 없다 — fallback 문서 계약을 보존하는 template 정리다.
  - 변경 시 commit type은 `chore(ci):`로 두어 root CLI release를 만들지 않는다(0020 commit discipline 계승).

- [x] **Step 4: 검증**

```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/companion-release.yml'); puts 'OK'"   # Step 3 수행 시
grep -RIn "no-quarantine" README.md README.ko.md companion/README.md   # 출력 없어야 함
grep -n "no-quarantine" .github/workflows/companion-release.yml   # unsigned/not-notarized fallback caveat에서만 출력되어야 함
```

## 검증 (acceptance)

- secret 6개 등록(`gh secret list`에 모두 표시).
- `companion-release.yml` `workflow_dispatch`(tag=`workbranch-companion-v1.3.0`) 실행이 green이며 서명/공증 step이 skip이 아니다.
- 배포 zip이 `codesign --verify --deep --strict` 통과, `spctl`이 `Notarized Developer ID`로 accept, `stapler validate` 통과.
- tap cask sha256이 서명본과 일치.
- caveat 제거 후 `brew install --cask tkhwang/tap/workbranch-companion`(`--no-quarantine` 없이) 설치 성공, app 실행, menu bar icon 표시.

```bash
# 최종 사용자 경로 확인
brew untap tkhwang/tap 2>/dev/null; brew tap tkhwang/tap
brew install --cask tkhwang/tap/workbranch-companion
open "/Applications/WorkbranchCompanion.app"
pgrep -fl WorkbranchCompanion
spctl -a -vvv -t install "/Applications/WorkbranchCompanion.app"
```

## 위험과 완화

- **부분 secret 등록으로 release 파손:** 워크플로는 secret이 "있으면 실행"한다. → Task 4에서 6개를 한 번에 등록하고, 등록 전 `.p12`(개인키 포함)·`.p8`를 로컬 검증한다.
- **잘못된 signing identity 문자열:** 이름/팀이 옛 값과 다를 수 있다. → `security find-identity`로 실제 문자열을 확인해 등록한다.
- **개인키 없는 `.p12`:** export 시 인증서만 내보내면 서명 불가. → Task 4 Step 1에서 `PRIVATE KEY` 카운트로 검증.
- **notary Issuer/Key ID 혼동:** Key ID(짧은 영숫자)와 Issuer ID(UUID)는 다르다. → 매핑 표와 검증 step에서 구분.
- **검증 실행이 운영 asset을 덮어씀:** `workflow_dispatch`가 `--clobber`로 1.3.0 asset을 교체한다. → 이는 의도된 효과(서명본 업그레이드)다. 실패 시 동일 태그로 재실행하면 멱등.
- **caveat 조기 제거:** 서명·공증 검증 **전에** caveat을 지우면 ad-hoc 배포본에 `--no-quarantine` 안내가 사라져 사용자가 막힌다. → Task 6은 Task 5 검증 통과 후에만 수행.
- **인증서 만료(2031):** Developer ID Application 인증서는 5년 만료. → 만료 전 재발급은 이 계획의 Task 2~4를 반복하면 된다(가이드는 `companion/README.md`에 유지).
