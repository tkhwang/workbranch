# 0027 Companion "로그인 시 자동 실행" 설정 추가 계획

> **agentic worker 지침:** 실행 시 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용한다. 동작 변경 전에는 `superpowers:test-driven-development` 흐름(red → green → refactor)을 따른다. 이 slice는 companion(`companion/Sources/**`)만 바꾸므로 CLI(`src/workbranch/**`)·`bin/workbranch`는 건드리지 않는다. companion 검증은 `(cd companion && swift build && swift run CompanionCoreTestRunner)`로 한다. 검증 순서: 관련 테스트 red/green → `swift build` → `CompanionCoreTestRunner` → `git diff --check`. 문서를 건드리면 EN/KO를 같은 PR에서 동기화한다.
>
> **시리즈 위치:** 0019(native menu-bar app) → 0021/0025/0026(companion UX)에서 만든 메뉴바 companion 위에 얹는 작은 **시스템 설정 연동** slice다. 새 CLI 계약이나 JSON 필드를 만들지 않고, companion이 자기 자신을 macOS 로그인 항목으로 등록/해제하는 토글만 추가한다.

**목표:** 사용자가 companion 설정 패널에서 "로그인 시 자동 실행(Launch at login)"을 켜고 끌 수 있게 한다. 켜면 macOS 로그인 시 메뉴바 companion이 자동 실행되고, 끄면 더 이상 자동 실행되지 않는다.

**아키텍처 한 줄 요약:** macOS 13+ `ServiceManagement`의 `SMAppService.mainApp`을 source of truth로 삼아 토글이 즉시 `register()`/`unregister()`를 호출한다. config 파일(`projects.md`)에는 저장하지 않는다 — 시스템이 등록 상태의 단일 진실 소스다.

**기술 스택:** Swift/SwiftUI companion(`companion/Package.swift`, macOS 13+), `ServiceManagement` 프레임워크, `CompanionCoreTestRunner` 소스 인바리언트 + 순수 로직 테스트 하니스.

**제품 관점:** companion은 작업 상태를 상시 모니터링하는 메뉴바 앱이라 매번 수동 실행은 번거롭다. 로그인 자동 실행은 "상시 떠 있는 status monitor" 사용 모델을 완성한다. 시스템 토글이므로 즉시 적용·즉시 반영되어야 하며, 실패(승인 필요 등)는 사용자가 알 수 있어야 한다.

---

## 문제

1. **자동 실행 수단이 없다.** 현재 companion은 사용자가 직접 앱을 실행해야 메뉴바에 뜬다. 재부팅/재로그인 후 다시 띄워야 하며, status 모니터로 쓰기에 불편하다.
2. **설정 패널에 startup 항목이 없다.** `AppearanceSettingsView`는 글꼴/테마만 다루고, 시스템 동작(로그인 실행)을 켜는 UI가 없다.
3. **로그인 항목은 config가 아니라 시스템 상태다.** 글꼴/테마는 `projects.md`에 저장되는 draft/Save 모델이지만, 로그인 항목 등록은 OS가 소유하는 상태다. 기존 Save 흐름에 끼워 넣으면 "Cancel 했는데 시스템 등록은 그대로"처럼 어긋난다.

## 현재 repo 근거

- `companion/Sources/CompanionApp/CompanionApp.swift:4` — `@main struct WorkbranchCompanionApp: App`, `MenuBarExtra(...)`, `.menuBarExtraStyle(.window)`. 순수 메뉴바 앱.
- `companion/Package.swift:6` — `platforms: [.macOS(.v13)]`. 따라서 `SMAppService`(macOS 13+) 무조건 사용 가능, `@available` 분기 불필요.
- `companion/scripts/build-app.sh:38-39` — `CFBundleIdentifier = com.tkhwang.workbranch-companion`, `:52-53` `LSUIElement = true`(Dock 미표시 메뉴바 앱). `:60` `codesign --force --sign -`(ad-hoc 서명).
- `companion/Sources/CompanionApp/Views/AppearanceSettingsView.swift:5` — `AppearanceSettingsView`는 `fontName`/`fontSize`/`colorTheme` 바인딩과 `onOpenConfig/onCancel/onSave/onThemeChange` 콜백을 받는다. body는 `header → fontSection → themeSection → preview → footer`(`:16-22`). `themeSection`의 테마 타일은 `onThemeChange(theme)`로 **즉시 반영**(draft에는 남기되 라이브 콜백)하는 선례가 있다(`:92-95`).
- `companion/Sources/CompanionApp/Views/CompanionPopoverView.swift:111-127` — `settingsPanel`이 `AppearanceSettingsView`를 인라인으로 그린다. `:129-134` `openSettings()`는 store 값을 draft `@State`로 복사한다. `:136-144` `saveSettings()`는 `store.saveAppearance(...)` 성공 시에만 패널을 닫는다. footer(`:96-100`)는 `store.statusMessage`를 한 줄로 보여준다.
- `companion/Sources/CompanionApp/StateStore.swift:8-28` — `@MainActor final class StateStore: ObservableObject`. `@Published private(set) var statusMessage`(`:11`)가 사용자 피드백 채널. `init(configURL:)`(`:30`)는 config 로드 + watcher + 초기 refresh를 수행. `saveAppearance(...)`(`:282`)는 config 파일에 쓰고 `statusMessage`를 갱신하는 패턴.
- `companion/Sources/CompanionCore/Config.swift:55` — `CompanionConfig`는 roots/workbranchBin/font/colorTheme만 직렬화한다. 로그인 항목 필드는 없다(추가하지 않는다).
- `companion/Sources/CompanionCoreTestRunner/CompanionCoreTestRunnerTests.swift:473` — `runAppSourceInvariantTests()`는 App 소스를 **텍스트로 읽어** 필수 배선을 `expect(... .contains(...))`로 잠근다. 이 runner는 `import CompanionCore`만 하며 **CompanionApp 타입은 import하지 못한다**(`:2`). → 순수 로직 단위 테스트는 CompanionCore에 있어야 import 가능하고, App-side 배선은 소스 인바리언트로만 잠근다.
- `companion/Sources/CompanionApp/StateStore.swift:475-490` 부근(runner 내부) — runner는 `StateStore`/`AppearanceSettingsView`/`CompanionPopoverView` 소스 문자열을 이미 읽고 있어, 신규 인바리언트를 같은 자리에서 추가하기 쉽다.

## 결정 사항 (확정 제안 — 실행 전 확인)

1. **API: `SMAppService.mainApp` (macOS 13+).** `register()`/`unregister()`로 로그인 항목을 토글하고 `status == .enabled`로 현재 상태를 읽는다. 레거시 `SMLoginItemSetEnabled`(별도 helper 번들 필요)나 손수 LaunchAgent plist 작성은 쓰지 않는다.
2. **Source of truth = 시스템.** 로그인 항목 상태는 `projects.md`에 저장하지 않는다. 토글은 `SMAppService` 상태를 직접 읽고 쓴다. 앱 시작 시 `StateStore`가 `status`를 읽어 토글 초기값으로 쓴다.
3. **즉시 적용(immediate-apply), draft/Save 비대상.** 토글은 누르는 즉시 register/unregister 한다. 글꼴/테마처럼 Save를 기다리지 않으며 Cancel로 되돌지 않는다(시스템 동작이므로). UI는 store-backed 바인딩으로 항상 실제 시스템 상태를 반영한다.
4. **테스트 가능성: 순수 로직은 CompanionCore, 시스템 글루는 CompanionApp.** `LoginItemStatus` enum + `LoginItemControlling.status` + 토글 결과 해석(순수 함수)을 **CompanionCore**에 두어 `CompanionCoreTestRunner`가 import해 단위 테스트한다. `SMAppService` 의존 구현(`SMAppServiceLoginItemController`)은 **CompanionApp**에 두고, App-side 상태 mapping은 소스 인바리언트로 잠근다.
5. **실패/승인 필요 피드백은 `statusMessage`로.** register 후 `SMAppService.status == .requiresApproval`이면 throw 여부와 무관하게 "System Settings > General > Login Items에서 승인하세요" 메시지를 footer에 보여준다. 실제 throw는 "Launch at login failed: …"로 표면화하되, 승인 필요 상태를 Bool 실패로 뭉개지 않는다.

## 결정 게이트 (확정)

- [x] **G1. `SMAppService.mainApp` 채택.**
  - Impact: 로그인 항목 구현 방식 / helper 번들 필요 여부 / 최소 OS.
  - Evidence: 배포 타깃이 `.macOS(.v13)`이라 `SMAppService` 무조건 가용. `mainApp`은 별도 helper 타깃 없이 메인 앱 자체를 등록한다.
  - Decision: `SMAppService.mainApp` 사용. Rejected: `SMLoginItemSetEnabled`(deprecated, helper 번들 필요), 수동 LaunchAgent plist(경로/escape/cleanup 부담).
  - Status: resolved from repo/SDK evidence.

- [x] **G2. 로그인 상태는 config에 저장하지 않고 시스템에서 읽는다.**
  - Impact: 상태의 단일 진실 소스 / config 포맷 변경 여부.
  - Evidence: 시스템 설정에서 사용자가 직접 끌 수 있어 config 값과 실제 상태가 갈라질 수 있다. `CompanionConfig`는 현재 로그인 필드가 없다.
  - Decision: `projects.md` 불변, `SMAppService.status`를 읽음. Rejected: config에 `launchAtLogin: true/false` 추가(시스템과 desync 위험 + 포맷/파서/테스트 변경 비용).
  - Status: resolved from repo evidence.

- [x] **G3. 토글은 즉시 적용, Save/Cancel 비대상.**
  - Impact: 설정 패널 UX 일관성.
  - Evidence: 테마 타일은 라이브 콜백 선례가 있고, 로그인 등록은 시스템 부작용이라 Cancel 되돌림이 직관에 어긋난다.
  - Decision: store-backed 바인딩으로 즉시 register/unregister. Rejected: draft에 담아 Save 시 적용(Cancel 시 시스템 상태와 어긋남).
  - Status: resolved from lifecycle/UX evidence.

- [x] **G4. 순수 로직은 CompanionCore에 배치하고 상태 enum을 보존한다.**
  - Impact: 단위 테스트 가능성 / 모듈 경계.
  - Evidence: `CompanionCoreTestRunner`는 `import CompanionCore`만 하므로 App 타입을 직접 테스트하지 못한다. 기존 split(Core=로직, App=시스템 글루)과 일치.
  - Decision: `companion/Sources/CompanionCore/LoginItem.swift`에 `LoginItemStatus` enum + `LoginItemControlling.status` + 순수 결과 해석(`LoginItemToggleOutcome.resolve`)을 둔다. `companion/Sources/CompanionApp/LoginItemController.swift`에는 `SMAppService.Status` → `LoginItemStatus` mapping과 `register()`/`unregister()`만 둔다.
  - Rejected: Core를 `isEnabled: Bool`만으로 유지하고 `.requiresApproval`을 App 문자열 분기로 처리(승인 필요 상태가 테스트 가능한 계약에서 사라짐).
  - Status: resolved by user decision A.

- [x] **G5. local ad-hoc 빌드와 published signed 빌드의 QA 경로를 분리한다. (리스크)**
  - Impact: 실제 등록 성공 여부.
  - Evidence: `SMAppService.mainApp.register()`는 유효한 코드 서명이 필요하다. local `companion/scripts/build-app.sh`는 여전히 ad-hoc 서명 + `dist/` 실행 경로지만, 0023은 published release의 Developer ID 서명·notarization·stapling 검증을 완료했다. 따라서 QA는 local 한계와 published/Homebrew 경로를 분리해야 한다.
  - Decision: 기능/코드는 그대로 추가하되, local ad-hoc/`dist/` 빌드에서는 승인 필요/실패 가능성을 PR에 기록한다. 실제 user-path QA는 `/Applications`에 설치된 signed build(Homebrew cask 또는 signed release asset)에서 수행한다.
  - Rejected: 서명 이슈 해결 전까지 기능 보류(설정 UI/로직은 서명과 독립적이고, signed release 경로는 이미 검증됨).
  - Status: resolved from current 0023/release evidence.

## 변경 계획

### 1. (신규) `companion/Sources/CompanionCore/LoginItem.swift` — 상태 enum + 프로토콜 + 순수 결과 해석

- `public enum LoginItemStatus: Equatable, Sendable`:
  - `case notRegistered` — 등록되지 않았거나 해제됨.
  - `case enabled` — 등록+승인되어 로그인 시 실행 가능.
  - `case requiresApproval` — 등록됐지만 System Settings 승인이 필요하거나 사용자가 승인을 회수함.
  - `case notFound` — 시스템이 서비스를 찾지 못하는 오류 상태.
- `public protocol LoginItemControlling`:
  - `var status: LoginItemStatus { get }` — 현재 시스템 로그인 항목 상태.
  - `func setEnabled(_ enabled: Bool) throws` — 등록/해제, 실패 시 throw.
- `public enum LoginItemToggleOutcome` + `public static func resolve(requested: Bool, statusAfter: LoginItemStatus, errorDescription: String? = nil) -> (launchAtLogin: Bool, message: String)` 순수 함수:
  - `statusAfter == .enabled` → `(true, "Launch at login enabled")`.
  - `!requested && statusAfter == .notRegistered` → `(false, "Launch at login disabled")`.
  - `statusAfter == .requiresApproval` → `(false, "Approve workbranch in System Settings > General > Login Items")`.
  - `errorDescription != nil` → `(statusAfter == .enabled, "Launch at login failed: …")`.
  - `statusAfter == .notFound` 또는 요청과 상태가 불일치하는 나머지 경우 → `(false, "Launch at login unavailable; check System Settings > General > Login Items")`.
  - `ServiceManagement` import 없음(순수). 메시지 문자열과 상태별 우선순위(`requiresApproval`이 단순 실패보다 우선)를 테스트로 잠근다.

### 2. (신규) `companion/Sources/CompanionApp/LoginItemController.swift` — SMAppService 구현

- `import ServiceManagement` + `import CompanionCore`.
- `struct SMAppServiceLoginItemController: LoginItemControlling`:
  - `status` → `SMAppService.mainApp.status`를 `LoginItemStatus`로 mapping한다(`.enabled`, `.requiresApproval`, `.notRegistered`, `.notFound`, `@unknown default`).
  - `setEnabled(_:)` → true면 `register()`, false면 `unregister()`.
- SwiftPM 글로브가 자동 수집하므로 `Package.swift` 변경 불필요.

### 3. `companion/Sources/CompanionApp/StateStore.swift` — 상태 + 토글 메서드

- 프로퍼티 추가: `@Published private(set) var launchAtLogin: Bool`, `private let loginItem: LoginItemControlling`.
- `init`에 파라미터 추가: `init(configURL: URL = ..., loginItem: LoginItemControlling = SMAppServiceLoginItemController())`. (문자열 `init(configURL:`은 유지되어 기존 인바리언트와 호환.) 본문 초입에서 `self.loginItem = loginItem; self.launchAtLogin = (loginItem.status == .enabled)`.
- 메서드 추가:
  ```swift
  func setLaunchAtLogin(_ enabled: Bool) {
      let errorDescription: String?
      do {
          try loginItem.setEnabled(enabled)
          errorDescription = nil
      } catch {
          errorDescription = String(describing: error)
      }
      let outcome = LoginItemToggleOutcome.resolve(
          requested: enabled,
          statusAfter: loginItem.status,
          errorDescription: errorDescription
      )
      launchAtLogin = outcome.launchAtLogin
      statusMessage = outcome.message
  }
  ```
- config 파일 쓰기 없음, watcher/refresh 영향 없음.

### 4. `companion/Sources/CompanionApp/Views/AppearanceSettingsView.swift` — 토글 UI

- 바인딩 추가: `@Binding var launchAtLogin: Bool`.
- `startupSection` 추가 후 body에 배치(예: `header` 바로 아래):
  ```swift
  private var startupSection: some View {
      VStack(alignment: .leading, spacing: 8) {
          Text("Startup").font(.caption).foregroundStyle(.secondary)
          Toggle(isOn: $launchAtLogin) { Text("Launch at login") }
              .toggleStyle(.switch)
      }
  }
  ```
- body: `header → startupSection → fontSection → themeSection → preview → footer`. 토글은 store-backed 바인딩이라 draft/Save와 무관(아래 5번에서 주입).

### 5. `companion/Sources/CompanionApp/Views/CompanionPopoverView.swift` — store-backed 바인딩 배선

- `settingsPanel`의 `AppearanceSettingsView(...)` 호출에 `launchAtLogin:` 인자를 추가하되, draft `@State`가 아니라 store를 직접 읽고 쓰는 바인딩을 넘긴다:
  ```swift
  launchAtLogin: Binding(
      get: { store.launchAtLogin },
      set: { store.setLaunchAtLogin($0) }
  )
  ```
- `openSettings()`/`saveSettings()`는 글꼴/테마 draft만 다루고 로그인 토글은 건드리지 않는다(즉시 적용이라 draft 복사·Save 불필요). 실패/승인 필요 메시지는 footer의 `store.statusMessage`로 자동 노출된다.

### 6. 문서 동기화

- 사용자 노출 설정이 추가되므로 `companion/README.md`에 "Launch at login" 토글과 승인 필요 시 System Settings 확인 경로를 추가한다.
- repo root 설치 안내가 companion 설정을 설명하는 경우 `README.md`/`README.ko.md`도 같은 PR에서 동기화한다. 단순 local 개발용 `build-app.sh` 설명은 ad-hoc 서명 한계를 유지하고, published/Homebrew 경로는 Developer ID 서명+notarization 상태와 구분한다.

---

## 테스트 계획 (TDD: 먼저 빨갛게)

### (단위) `CompanionCore` 순수 결과 해석 — runner에 `runLoginItemTests()` 추가

`import CompanionCore`로 직접 호출 가능:
- `resolve(requested: true, statusAfter: .enabled) == (true, "Launch at login enabled")`.
- `resolve(requested: false, statusAfter: .notRegistered) == (false, "Launch at login disabled")`.
- `resolve(requested: true, statusAfter: .requiresApproval)`의 `launchAtLogin == false` 이고 message가 "System Settings"/"Login Items" 안내를 포함.
- `resolve(requested: true, statusAfter: .notRegistered, errorDescription: "...")`의 `launchAtLogin == false` 이고 message가 "failed"를 포함.
- `resolve(requested: true, statusAfter: .requiresApproval, errorDescription: "...")`는 단순 failed보다 승인 안내를 우선한다.
- `resolve(requested: true, statusAfter: .notFound)`는 unavailable/check System Settings 메시지를 반환한다.
- runner 내부에 `FakeLoginItemController: LoginItemControlling`(저장된 `LoginItemStatus` + `setEnabled` 시 enabled/notRegistered/requiresApproval/notFound/throw 모드)을 정의해 프로토콜 계약을 행위로 검증한다.

### (소스 인바리언트) `runAppSourceInvariantTests()`에 배선 잠금 추가

기존 패턴(`expect(... .contains(...))`)을 따른다:
- `StateStore`: `"@Published private(set) var launchAtLogin"`, `"func setLaunchAtLogin"`, `"loginItem: LoginItemControlling"`, `"loginItem.status"`, `"LoginItemToggleOutcome.resolve"` 포함. (그리고 `init(configURL:` 문자열이 여전히 존재 → 기존 init 인바리언트 회귀 없음.)
- `LoginItemController.swift`(App): 파일 존재 + `"import ServiceManagement"`, `"SMAppService.mainApp"`, `"register()"`, `"unregister()"`, `".requiresApproval"`, `"@unknown default"` 포함.
- `LoginItem.swift`(Core): 파일 존재 + `"enum LoginItemStatus"`, `"protocol LoginItemControlling"`, `"var status: LoginItemStatus"`, `"func resolve("` 포함, 그리고 `!contains("import ServiceManagement")`(순수 유지).
- `AppearanceSettingsView`: `"Launch at login"`, `"Toggle(isOn: $launchAtLogin)"`(또는 `"$launchAtLogin"`), `"@Binding var launchAtLogin"` 포함.
- `CompanionPopoverView`: `"store.setLaunchAtLogin"`, `"store.launchAtLogin"` 포함. 그리고 `openSettings`/`saveSettings` 본문에 `launchAtLogin` draft 처리가 **없음**을 잠근다(즉시 적용 계약 보존).
- runner 진입부(`do { ... }`)에 `try runLoginItemTests()` 호출 추가.

### (수동 QA) 실제 등록 동작

- signed build(Homebrew cask 또는 Developer ID 서명 release asset)를 `/Applications`에 두고 토글 ON → 로그아웃/로그인(또는 재부팅) 후 메뉴바에 자동 등장 확인. 토글 OFF → 자동 실행 안 됨 확인.
- `SMAppService.mainApp.status`가 `.requiresApproval`일 때 footer 안내 메시지가 뜨고, System Settings에서 승인 후 `.enabled`로 반영되는지 확인.
- local ad-hoc/`dist/` 실행 빌드에서의 동작 한계(승인 필요/실패 가능)를 PR 본문에 기록한다.

---

## 검증 순서

1. (red→green) `runLoginItemTests()` 순수 resolve + Fake 계약 테스트.
2. (red→green) `runAppSourceInvariantTests()` 신규 배선 인바리언트.
3. `(cd companion && swift build)` 성공.
4. `(cd companion && swift run CompanionCoreTestRunner)` → `CompanionCoreTestRunner: PASS`.
5. `git diff --check`.
6. (수동) signed build(Homebrew cask 또는 Developer ID 서명 release asset)를 `/Applications`에 설치한 뒤 로그인 자동 실행 QA.

## 롤아웃 / 호환성

- **비파괴 추가.** 새 CLI 동작/디렉티브/JSON 필드 없음. `projects.md` 포맷 불변. 로그인 항목은 사용자가 토글하기 전까지 등록되지 않는다(기본 OFF = 기존 동작).
- macOS 13+ 전용 API지만 배포 타깃이 이미 13이라 추가 게이팅 불필요.
- local ad-hoc 서명/비표준 실행 위치에서는 `register()`가 승인 필요/실패할 수 있음 → 사용자에게 `statusMessage`로 안내. 안정 동작은 signed build + `/Applications` 설치 전제이며, published release의 Developer ID 서명·notarization은 0023에서 검증 완료된 상태다.
- 끄면 `unregister()`로 깔끔히 해제되어 잔여 LaunchAgent가 남지 않는다.

## 실행 순서 요약

1. (red) Core `LoginItemToggleOutcome.resolve` + Fake 계약 테스트.
2. (green) Core `LoginItem.swift`(프로토콜 + resolve) 추가.
3. App `LoginItemController.swift`(SMAppService 구현) 추가.
4. `StateStore`에 `launchAtLogin` 상태 + `setLaunchAtLogin` + init 주입 배선.
5. `AppearanceSettingsView` startup 토글 + `CompanionPopoverView` store-backed 바인딩.
6. 소스 인바리언트 추가 → `swift build` + `CompanionCoreTestRunner` + `git diff --check`.
7. README/companion README 문서 동기화(필요한 EN/KO 표면 함께 반영).
8. 수동 QA(signed build, 로그인 자동 실행).

---

## 실행 결과

- [x] 설정 패널에 "Launch at login" 토글이 보이고, 켜면 `SMAppService.mainApp.register()`, 끄면 `unregister()`가 즉시 호출된다.
- [x] 토글 초기값이 실제 시스템 등록 상태(`status == .enabled`)를 반영한다.
- [x] register 후 승인 필요/실패 시 footer `statusMessage`로 안내된다.
- [x] 로그인 상태는 `projects.md`에 저장되지 않는다(시스템이 단일 진실 소스).
- [x] `LoginItemToggleOutcome.resolve` 순수 테스트 + App 배선 소스 인바리언트가 그린.

검증 evidence:

- `(cd companion && swift build)` → PASS (`Build complete!`).
- `(cd companion && swift run CompanionCoreTestRunner)` → PASS (`CompanionCoreTestRunner: PASS`).
- `(cd companion && swift test)` → PASS (`Build complete!`, exit 0).
- `(cd companion && ./scripts/build-app.sh)` → PASS (`dist/WorkbranchCompanion.app` v1.8.0 생성).
- `codesign --verify --deep --strict --verbose=2 companion/dist/WorkbranchCompanion.app` → PASS (`valid on disk`, `satisfies its Designated Requirement`).
- `plutil -p companion/dist/WorkbranchCompanion.app/Contents/Info.plist` → PASS (`CFBundleIdentifier = com.tkhwang.workbranch-companion`, `LSMinimumSystemVersion = 13.0`, `LSUIElement = true`).
- `git diff --check` → PASS.
- 수동 QA(signed build 로그인 자동 실행) → 미실행. 실제 ON/OFF 토글은 macOS Login Items 시스템 상태를 변경하므로 자동 검증에서는 수행하지 않았다.
