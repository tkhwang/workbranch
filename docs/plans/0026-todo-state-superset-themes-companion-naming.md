# 0026 `todo` 초기 상태 · Superset 테마 정리 · Companion 정체성 명확화 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:test-driven-development` before every behavior change. Make Bash source changes under `src/workbranch/**`, register new modules in `scripts/workbranch-sources.txt`, rebuild with `scripts/build-workbranch.sh`, then verify syntax checks, targeted tests, `./tests/run.sh`, and `git diff --check`. Do not edit `bin/workbranch` by hand. Companion 변경은 `companion/Sources/**`에서 하고 `companion/Sources/CompanionCoreTestRunner`로 검증한다.

**Goal:** 세 가지 독립 개선을 한 배치로 반영한다. (1) task 라이프사이클 맨 앞에 `todo` 상태를 추가해 "아직 시작 안 함"과 "계획 중(planning)"을 구분하고 초기 planning 단계에서도 status가 갱신되도록 가이드를 강화한다. (2) 색상 테마를 Superset 마켓플레이스에서 선별한 5종(Catppuccin Mocha · Dracula · One Dark Pro · Nord · Tokyo Night)으로 정리하고, 설정 UI는 선택된 1개 + 후보 4개 구조로 명확히 보여준다. 아직 만드는 단계이므로 기존 제거 테마 문자열 호환성은 유지하지 않는다. (3) Companion 이름은 그대로 두되 README/UI 텍스트로 "status monitor" 정체성을 명확히 한다.

**Architecture:** 세 섹션은 서로 독립적이며 공유 contract만 건드린다. `todo`는 기존 status 문자열 열거에 한 항목을 추가하는 additive 변경이라 Bash status 파서·기본 템플릿·AGENTS.md 가이드·Companion glyph/색상 매핑만 확장한다. 테마는 `CompanionColorTheme` enum과 `TerminalPalette` 팔레트를 새 5개 contract로 교체한다. 설정값은 선택된 1개 theme이고 UI는 나머지 4개를 candidate로 보여준다. 제거된/legacy 테마 문자열은 마이그레이션하지 않고 invalid config로 처리한다. 네이밍은 코드 식별자(타겟·디렉터리·config 키)를 일절 바꾸지 않고 사용자 노출 텍스트만 보강한다.

**Tech Stack:** Portable Bash, Git worktrees, 라인 지향 companion `projects.md` config, `<task>/TASK-WORKBRANCH.md` task brief, `scripts/build-workbranch.sh` 단일 파일 빌드, `tests/run.sh` 통합 테스트, Swift Package(`companion/`)의 `CompanionCore`/`CompanionApp` 타겟과 `CompanionCoreTestRunner` 검증.

---

## 문제

1. **초기 status가 실제 상태를 반영하지 못함.** `write_default_task_brief`가 기본 brief를 `status: planning`으로 만든다(`src/workbranch/lib/task-state.sh:153,154,167`). 그래서 에이전트가 아직 손대지 않은 task와 실제로 계획을 세우는 중인 task가 모두 `planning`으로 보인다. 또한 최초 planning 작업 동안 에이전트가 status를 잘 갱신하지 않아 Companion에서 진행 상황이 죽은 것처럼 보인다.
2. **테마가 목표 Superset 계열과 어긋남.** 이번 slice에서 맞출 Superset marketplace 선별 5종은 Catppuccin Mocha / Dracula / One Dark Pro / Nord / Tokyo Night인데, Companion은 `dracula/matrix/amber/nord/solarized` 5종이라 일부만 겹친다.
3. **Companion의 정체성이 텍스트로 드러나지 않음.** 사용자는 이 앱을 사실상 status·notification·monitor로 쓰는데 README/UI에는 그 성격이 명시돼 있지 않다.

## 현재 repo 근거

- status 라이프사이클 문자열은 `planning | in-progress | review | blocked | done` 5종으로, Bash와 Companion 양쪽에 하드코딩돼 있다.
  - 파서 허용목록: `src/workbranch/lib/task-state.sh:65` (`task_explicit_status`).
  - 무체크리스트 fallback: `src/workbranch/lib/task-state.sh:85` (`task_status` → `planning`).
  - 기본 brief 템플릿(ko/en): `src/workbranch/lib/task-state.sh:150-168`.
  - AGENTS.md 가이드 텍스트도 같은 파일의 heredoc(`:210`, `:243`)과 repo 루트 `AGENTS.md:25`에 중복 기재된다.
  - Companion glyph 매핑: `companion/Sources/CompanionCore/MenuState.swift:374-378`.
  - Companion 색상 매핑: `companion/Sources/CompanionApp/Views/RowView.swift:200-204` (그리고 `:281-282`에서 `in-progress`/`blocked` 카운트, `:368`에서 `blocked` 자동 펼침).
- 테마는 `CompanionColorTheme`(`companion/Sources/CompanionCore/Config.swift:19-45`)에 enum·`default`·`parse`·`label`로 정의되고, 색상값은 `companion/Sources/CompanionApp/Views/TerminalStyle.swift:23-72`의 `switch theme`에 있다.
  - `parse`는 legacy alias `green→matrix`, `blue→nord`를 매핑하고, 알 수 없는 값은 `nil`을 반환한다. `Config.load`(`Config.swift:108-114`)는 `nil`이면 `unsupportedColorTheme`를 throw해 config 로드 전체가 실패한다. 이번 plan은 아직 만드는 단계의 새 theme contract이므로 이 reject 동작을 유지한다.
  - 테마 관련 테스트: `companion/Sources/CompanionCoreTestRunner/main.swift:313,323,332,336` (`amber` 사용, legacy `green→matrix` 기대).
- Companion 사용자 노출 텍스트: `companion/README.md`, repo `README.md`/`README.ko.md`, popover 헤더(`companion/Sources/CompanionApp/Views/CompanionPopoverView.swift`), 설정 화면 헤더 `"Companion Settings"`(`AppearanceSettingsView.swift:29`).

## 결정 사항 (확정됨)

### 라이프사이클
- 새 상태 `todo`를 라이프사이클 맨 앞에 추가한다: **`todo` → planning → in-progress → review → done** (+ `blocked`).
- 기본 brief 템플릿은 `status: todo`(ko는 `상태: todo` + `status: todo`)로 시작한다.
- 에이전트가 의미 있는 작업(계획 포함)을 시작하면 즉시 `todo → planning`으로 전환한다. 이 규칙을 AGENTS.md 가이드에 명시한다.
- `task_status` fallback: 명시 status가 없을 때 `done_count == 0`이면 `todo`를 반환한다. 체크리스트 일부 완료(`0 < done_count < total_count`) → `in-progress`, 전부 완료(`done_count == total_count && total_count > 0`) → `done`은 그대로다.
- Companion 표시: glyph `todo → ·`, 색상 `todo → .muted`. (planning은 `○`/`.muted` 유지 — glyph와 라벨 `TODO`로 구분.)

### 결정 기록
- **Decision 1 — `todo` fallback semantics:** `status:`가 없는 brief에서 checklist가 있더라도 완료 항목이 0개이면 `todo`로 본다. 이유: `todo`의 public 의미는 "아직 시작 안 함"이고, 새 기본 brief도 checklist를 가진 채 `status: todo`로 시작하므로 `status:` 줄이 누락된 수동/구형 brief도 같은 의미를 유지해야 한다.
- **Decision 2 — Superset theme scope:** 이번 slice는 Superset marketplace의 전체 theme set을 1:1 동기화하지 않고, Catppuccin Mocha / Dracula / One Dark Pro / Nord / Tokyo Night 5개를 선별 적용한다. 이유: current Companion 설정 UI와 enum은 5개 테마 구조이고, 전체 marketplace 동기화는 variant/light theme 포함 여부와 지속적인 catalog drift 관리를 별도 제품 결정으로 만든다.
- **Decision 3 — theme selection and compatibility:** theme contract는 새 5종으로 고정하고, 설정 화면은 선택된 1개 theme + 후보 4개 theme로 구성한다. 아직 만드는 단계라 제거된 `matrix`/`amber`/`solarized` 및 legacy alias(`green`, `blue`) 호환성은 유지하지 않는다. invalid/old `colorTheme:` 값은 fallback 없이 config validation error로 둔다.

### 테마
- 최종 테마 5종은 Superset marketplace 전체 동기화가 아니라 dark/popular 계열로 선별한 5종이다: `catppuccin`(Catppuccin Mocha) · `dracula` · `onedark`(One Dark Pro) · `nord` · `tokyonight`(Tokyo Night).
- 제거: `matrix`, `amber`, `solarized`. 유지: `dracula`, `nord`. 추가: `catppuccin`, `onedark`, `tokyonight`.
- `default`는 `dracula` 유지(Superset 선별 5종에 포함됨).
- **호환성:** 아직 만드는 단계의 새 contract이므로 제거된 `matrix`/`amber`/`solarized` 및 legacy `green`/`blue` alias는 유지하지 않는다. `Config.load`에서 허용 5종이 아닌 `colorTheme:` 값은 기존처럼 `unsupportedColorTheme` validation error로 처리한다.

### 네이밍
- 코드 식별자(Swift 타겟 `CompanionApp`/`CompanionCore`, 디렉터리 `companion/`, config 키 `colorTheme`/`fontName` 등, `.workbranch.config` 헤더)는 **변경하지 않는다.**
- README와 UI에 "workbranch status monitor — task 상태·알림·모니터" 성격의 한 줄 부제만 보강한다.

## public contract

### `TASK-WORKBRANCH.md` status 필드
- 허용값: `todo | planning | in-progress | review | blocked | done`.
- 기본 brief는 `todo`로 생성된다(기존: `planning`). 기존에 생성된 brief 파일은 건드리지 않는다(`write_default_task_brief`는 파일이 있으면 no-op, `:148`).

### Companion `projects.md` `colorTheme:`
- 허용값: `catppuccin | dracula | onedark | nord | tokyonight`.
- 알 수 없는/제거된 값(`matrix`/`amber`/`solarized`/`green`/`blue` 포함)은 fallback 없이 `unsupportedColorTheme` validation error로 둔다.

## 파일 구조

```text
# Bash CLI
src/workbranch/lib/task-state.sh   # status 허용목록 + fallback + 기본 템플릿 + 가이드 heredoc
AGENTS.md                          # repo 루트 가이드(중복 텍스트)

# Companion
companion/Sources/CompanionCore/Config.swift              # CompanionColorTheme enum/default/parse/label
companion/Sources/CompanionApp/Views/TerminalStyle.swift  # TerminalPalette 색상값
companion/Sources/CompanionApp/Views/AppearanceSettingsView.swift  # selected 1 + candidate 4 theme UI
companion/Sources/CompanionCore/MenuState.swift           # status glyph 매핑
companion/Sources/CompanionApp/Views/RowView.swift        # status 색상 매핑

# 사용자 텍스트
companion/README.md, README.md, README.ko.md, docs/usage.md, docs/usage.ko.md, docs/specs/0001-workbranch-mvp.md
companion/Sources/CompanionApp/Views/CompanionPopoverView.swift  # popover 헤더 부제(선택)
```

## 구현 작업

> 각 Task는 TDD: 먼저 실패 테스트(또는 검증 시나리오) → 구현 → 통과 순서. Bash 변경 후 `scripts/build-workbranch.sh` 재빌드.

### Task 1: Bash status 파서에 `todo` 추가 (`task-state.sh`)
- `task_explicit_status` 허용목록(`:65`)에 `todo`를 추가한다.
- `task_status` fallback(`:84-90`): `done_count -eq 0`이면 `todo`, `0 < done_count < total_count`이면 `in-progress`, `done_count == total_count && total_count > 0`이면 `done`을 반환한다.
- 테스트: `tests/cases/`의 status 관련 케이스(있으면)에서 `status: todo`가 그대로 보존되고, status·체크리스트가 모두 없는 brief 및 checklist가 있지만 완료 항목이 0개인 brief가 `todo`로 나오는지 검증을 추가한다.
- Acceptance: brief에 `status: todo`를 쓰면 `task_status`가 `todo`를 반환하고, status·체크리스트가 모두 없는 brief도 `todo`, checklist가 있지만 완료 항목이 0개인 brief도 `todo`를 반환한다. 일부 완료 checklist는 `in-progress`, 전부 완료 checklist는 `done`을 유지한다.

### Task 2: 기본 brief 템플릿을 `todo`로 (`task-state.sh`)
- `write_default_task_brief` ko heredoc(`:153,154`)과 en heredoc(`:167`)의 `planning` → `todo`. ko는 `상태: todo` / `status: todo` 둘 다.
- 첫 체크리스트 항목 텍스트(`주요: 작업 시작` / `Major: Start work`)는 유지.
- Acceptance: 새 task 생성 시 brief가 `status: todo`로 시작한다.

### Task 3: AGENTS.md 가이드 갱신 (heredoc + repo 루트)
- `task-state.sh`의 가이드 heredoc(ko `:210`, en `:243`)과 repo 루트 `AGENTS.md`의 status 규칙(`:25`)을 동기화한다.
- 허용값 목록에 `todo`를 추가: `todo | planning | in-progress | review | blocked | done`.
- "작업 진행 업데이트 규칙"에 명시 추가: **계획(planning)을 포함해 의미 있는 작업을 시작하면 즉시 `todo`에서 `planning`으로 status를 갱신한다. 초기 planning 단계에서도 status·checklist를 갱신한다.**
- Acceptance: 세 위치(heredoc ko/en, repo AGENTS.md)의 status 문구가 일치하고 `todo` 및 초기 갱신 규칙을 포함한다.

### Task 4: Companion status glyph/색상에 `todo` 추가
- `MenuState.swift:374-378` glyph switch에 `case "todo": return "·"` 추가.
- `RowView.swift:200-204` 색상 switch에 `case "todo": return .muted` 추가.
- glyph/색상 switch의 `default` 분기가 깨지지 않는지 확인(미지 status는 기존 default 유지).
- Acceptance: status `todo`인 task가 Companion에서 `·` glyph + muted 색 + `TODO` 라벨로 표시된다.

### Task 5: `CompanionColorTheme` enum 교체 (`Config.swift`)
- enum case: `matrix`/`amber`/`solarized` 제거, `catppuccin`/`onedark`/`tokyonight` 추가. 순서는 Superset 표기 순서(`catppuccin, dracula, onedark, nord, tokyonight`) 권장 — `allCases` 순서가 설정 화면 타일 순서를 결정한다.
- `default`는 `.dracula` 유지.
- `label`: `Catppuccin Mocha` / `Dracula` / `One Dark Pro` / `Nord` / `Tokyo Night`.
- `parse`: legacy alias `green`/`blue` 매핑을 모두 제거한다. 허용 5종만 rawValue로 parse하고, 알 수 없는 값은 `nil`을 반환한다.
- Acceptance: enum이 5종이고 label이 위와 같다. `allCases`는 selected 1 + candidate 4 UI의 후보 source로 사용할 수 있다.

### Task 6: invalid/legacy theme validation 유지 (`Config.swift`)
- `Config.load`의 `colorTheme:` 처리(`:108-114`)는 `parse`가 `nil`이면 계속 `unsupportedColorTheme`를 throw한다.
- 제거된 `matrix`/`amber`/`solarized` 및 legacy alias `green`/`blue`는 모두 invalid 값으로 처리한다.
- Acceptance: `colorTheme: matrix`(또는 `amber`/`solarized`/`green`/`blue`/`neon`)가 있는 config를 load하면 `unsupportedColorTheme`로 실패하고, 허용 5종만 정상 load된다.

### Task 7: 테마 팔레트 색상값 (`TerminalStyle.swift`)
- `switch theme`에서 `.matrix`/`.amber`/`.solarized` 케이스를 제거하고 `.catppuccin`/`.onedark`/`.tokyonight` 케이스를 추가한다. `.dracula`/`.nord`는 유지.
- 각 테마의 표준 팔레트를 `background/panel/text/muted/accent/command/warning/error`에 매핑한다. 참고 기준값(공식 팔레트, sRGB):
  - **Catppuccin Mocha:** base `#1e1e2e` / mantle `#181825` / text `#cdd6f4` / overlay `#7f849c` / green `#a6e3a1`(accent) / sky `#89dceb`(command) / yellow `#f9e2af`(warning) / red `#f38ba8`(error).
  - **One Dark Pro:** bg `#282c34` / panel `#21252b` / text `#abb2bf` / muted `#5c6370` / green `#98c379`(accent) / blue `#61afef`(command) / yellow `#e5c07b`(warning) / red `#e06c75`(error).
  - **Tokyo Night:** bg `#1a1b26` / panel `#16161e` / text `#c0caf5` / muted `#565f89` / green `#9ece6a`(accent) / cyan `#7dcfff`(command) / yellow `#e0af68`(warning) / red `#f7768e`(error).
- `rule`은 기존대로 `Color.white.opacity(0.10)` 공통.
- Acceptance: 5개 테마 모두 `TerminalPalette(theme:)`가 컴파일되고 설정 화면 미리보기/타일이 정상 렌더된다.

### Task 8: 설정 화면 theme 선택 UI (`AppearanceSettingsView.swift`)
- 설정 화면은 현재 `colorTheme` 1개를 selected/current theme로 먼저 보여주고, 나머지 4개 `CompanionColorTheme.allCases.filter { $0 != colorTheme }`를 candidate theme로 보여준다.
- Candidate tile을 클릭하면 draft `colorTheme`가 즉시 바뀌고 기존 `onThemeChange(theme)` live preview 동작을 유지한다.
- Acceptance: 항상 selected theme 1개와 candidate theme 4개가 구분되어 보이며, 선택 변경 후 새 selected 1개 + candidate 4개 구성이 다시 계산된다.

### Task 9: 테마 테스트 갱신 (`CompanionCoreTestRunner/main.swift`)
- `:313,323,332` `amber` 사용을 살아있는 테마(예: `tokyonight`)로 교체.
- `:336` legacy `green→matrix` 기대 테스트를 제거하고, `green`/`blue`가 모두 `unsupportedColorTheme`로 rejected 되는지 검증한다.
- 새 검증 추가: 제거 테마(`matrix`/`amber`/`solarized`)가 포함된 config가 fallback 없이 `unsupportedColorTheme`로 rejected 되는지(Task 6).
- Acceptance: `CompanionCoreTestRunner` 전체 통과. 설정 UI source/assertion은 선택된 1개 theme와 후보 4개 theme가 구분되는 렌더 구조를 확인한다.

### Task 10: 네이밍 정체성 텍스트 보강
- `companion/README.md`, repo `README.md`/`README.ko.md`에 Companion 소개 부제로 "workbranch status monitor — task 상태·알림·모니터" 한 줄 추가.
- `docs/usage.md`, `docs/usage.ko.md`, `docs/specs/0001-workbranch-mvp.md`의 task status 허용값/기본 예시를 `todo` 포함 contract로 동기화하고, README의 stale `config.json` 안내는 current `projects.md` 경로로 정리한다.
- (선택) `CompanionPopoverView` 헤더 또는 메뉴바 툴팁에 동일 부제 노출. 코드 식별자·config 키·타겟명은 변경하지 않는다.
- Acceptance: README에서 Companion이 status monitor임이 한 줄로 드러나고, public docs/spec의 status enum과 companion config path가 current contract와 일치하며, 빌드/타겟/config 키에는 변화가 없다.

## 최종 검증

```bash
# Bash
bash -n src/workbranch/**/*.sh
scripts/build-workbranch.sh
./tests/run.sh
git diff --check

# Companion
swift build --package-path companion
swift run --package-path companion CompanionCoreTestRunner   # 또는 repo 표준 러너 호출 방식
```

- 수동 확인: 새 task 생성 → brief가 `status: todo` → Companion에서 `·`/TODO 표시. 계획 시작 후 `planning`으로 바뀌면 색/glyph가 갱신됨.
- 수동 확인: 설정 화면에 선택된 1개 Superset 계열 테마와 후보 4개 테마가 구분되어 보이고 미리보기 색이 맞음. `colorTheme: amber` 같은 제거 theme config는 validation error로 드러난다.

## 롤아웃 / 호환성

- `todo`는 additive — 기존 brief 파일은 그대로 유지되고(파일 존재 시 템플릿 no-op) 기존 status 값도 모두 유효하다.
- 테마는 새 5종 contract로 고정한다. 아직 만드는 단계라 제거 theme/legacy alias 호환성은 유지하지 않으며, invalid config는 validation error로 드러낸다. 사용자 문서에는 허용 5종과 selected 1 + candidate 4 구조를 안내한다.
- 네이밍은 사용자 텍스트만 바뀌므로 호환성 영향 없음.

## 미해결 / 후속

- Superset marketplace와 1:1 전체 동기화를 더 강하게 원하면 추후 Light variant(Catppuccin Latte 등)와 추가 테마 catalog 관리 계획으로 분리 가능 — 이번 범위 밖.
- `todo` 상태에 대한 Companion 정렬 우선순위(예: todo를 맨 위/아래로)는 현재 정렬 로직 유지. 필요 시 별도 plan.
