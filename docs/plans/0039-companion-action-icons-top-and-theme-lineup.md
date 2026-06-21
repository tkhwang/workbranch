# 0039 Companion 작업 액션 아이콘 상단 이동 + 테마 라인업 정리

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` 또는 `$plan-execute auto` 로 task 단위 구현. `.tsx`/`.ts` 편집은 먼저 테스트로 동작을 고정한 뒤 시각 변경을 적용한다(테마/레이아웃은 토큰·구조 변경이라 테스트가 회귀 방지의 1차 방어선). 시각 변경은 `DESIGN.md` 를 따르고 `pnpm --filter @workbranch/companion tauri dev`(또는 Vite + IPC mock fallback)로 (1) step 이 길어진 카드에서 IDE/Terminal/Finder 가 상단에 보이는지, (2) 4개 테마 × light/dark 가 전체 UI에 적용되는지 직접 확인한 뒤 완료를 선언한다. 네이티브 tray popover 를 관찰할 수 없으면 gap 을 기록하고 Vite fallback 캡처로 대체, task 는 `review` 로 둔다.

**Goal:** Companion 작업 카드(`TaskRow`)에서 두 가지를 개선한다.
1. **액션 아이콘 상단 이동:** IDE · Terminal · Finder 실행 버튼이 현재 `task-detail` 의 맨 아래(steps 뒤)에 있어 plan/step 이 길어지면 화면 밖으로 밀려 찾기 어렵다. repo/branch(repo chips)가 보이는 상단 헤더 행으로 올려, step 길이와 무관하게 항상 같은 위치에서 보이게 한다.
2. **테마 라인업 정리:** follow-up 결정에 따라 dark 라인업에서 Gruvbox 를 Dracula 로 교체한다. Settings 모델은 family+mode 구조라 `solarized / dracula / catppuccin / github` 4개 패밀리 각각 dark/light 값을 유지하고, gruvbox·nord 기존 사용자는 가까운 패밀리로 마이그레이션한다.

**Architecture:** 두 기능은 서로 독립이지만 같은 카드 UI 표면이라 한 plan/PR 로 묶는다. 기능 1은 `TaskRow.tsx` 의 JSX 순서 재배치 + CSS 레이아웃 변경(순수 프레젠테이션, 도메인/contract 불변). 기능 2는 테마 패밀리 메타데이터(`themePreferences.ts`) · 기본값/마이그레이션(`preferences.ts`) · 테마 토큰 CSS(`themes.css`) · 스와치 CSS(`settings.css`) 를 lockstep 으로 교체한다. CLI JSON contract, 도메인 task 모델, watcher, activity store, autostart/store 플러그인 배선은 변경하지 않는다.

**Tech Stack:** Tauri v2, React 18, TypeScript, Vite, Vitest, Biome, plain CSS(테마 토큰). Tailwind/shadcn/Radix 미사용. 0037(테마/설정 도입)·0038(앱 디렉터리 `apps/companion` 리네임) 이후 상태 기준.

---

## 문제

### 기능 1 — 액션 아이콘이 너무 아래에 있음
`apps/companion/src/ui/TaskRow.tsx` 의 확장 카드 구조는 `task-detail` 안에서 다음 순서다:

```
[summary]  ● feat-task2
└ .task-detail
   ├ RepoChips        frontend feature/cpq-task2 · backend feature/cpq-task2   ← 상단
   ├ CurrentStep      (현재 단계 strip)
   ├ .steps           ☐ … ☐ … ☐ …    ← plan/step 이 길수록 길어짐
   └ .task-actions    IDE · Terminal · Finder   ← 마지막 자식이라 계속 아래로 밀림 ❌
```

`.task-actions` 가 `.task-detail` 의 **마지막 자식**(`TaskRow.tsx:182-202`)이라 step 개수에 비례해 아래로 밀린다. plan/step 이 길어지면 스크롤해야만 실행 버튼이 보인다.

### 기능 2 — light 가 없는 테마에 가짜 light 가 들어가 있고, 일부 테마 정체성이 약함
`apps/companion/src/application/themePreferences.ts` 는 4개 패밀리 × light/dark = 8개 테마 값을 정의한다. 그러나:

| 패밀리 | Dark | Light | 판정 |
|---|---|---|---|
| Solarized | ✅ 공식 | ✅ 공식 | 유지 |
| Dracula | ✅ 공식 | companion light counterpart | **유지**(follow-up: Gruvbox 대신 Dracula) |
| Catppuccin | ✅ 공식 | ✅ 공식 | 유지 |
| GitHub | ✅ 공식 | ✅ 공식 | 유지 |
| Gruvbox | ✅ 공식 | ✅ 공식 | **제거**(사용자 follow-up 으로 Dracula 가 대체) |
| Nord | ✅ 공식 | ❌ 공식 light 없음(`nord-light` 임의 생성) | **제거** |

→ follow-up 후 핵심은 Dracula dark 의 공식 background `#282A36` 와 blue-gray surface/comment 계열(`Current Line`/`Comment` `#6272A4`, `Selection` `#44475A`)을 실제 UI role 에 반영하는 것이다. family+mode 설정 구조를 유지하기 위해 Dracula light 는 companion-maintained counterpart 로 제공한다.

## 현재 repo 근거

- 액션 렌더: `apps/companion/src/ui/TaskRow.tsx:161-206` — `TaskRow` 가 `RepoChips → CurrentStep → steps → task-actions` 순으로 렌더. 액션 종류는 `TASK_ACTION_KINDS = ["ide","terminal","finder"]`(`TaskRow.tsx:16`), 버튼은 아이콘(`TaskActionIcon`) + 텍스트 라벨(`TASK_ACTION_LABELS`)로 구성.
- 액션 스타일: `apps/companion/src/styles/task-actions.css` — `.task-actions`(flex, `margin-top:9px`, `--surface-1` 배경 바), `.task-action`, `.task-action-icon`, `.task-action-separator`.
- repo chips 스타일: `apps/companion/src/styles/task-details.css:148-190` — `.repo-chips`(flex wrap, `margin-top:8px`), `.repo-chip`.
- 테마 메타: `apps/companion/src/application/themePreferences.ts` —
  - `COMPANION_THEME_VALUES`(8값), `COMPANION_THEME_FAMILY_VALUES`(`solarized/dracula/catppuccin/github`), `THEME_BY_FAMILY_AND_MODE`, `COMPANION_THEME_OPTIONS`, `isCompanionTheme`/`isCompanionThemeFamily`, legacy(`PREVIOUS_COMPANION_THEME_VALUES`, `themeFamilyFromLegacyTheme`, `themeModeFromLegacyTheme`), `resolvedThemeValue`.
- 기본값/마이그레이션: `apps/companion/src/application/preferences.ts` —
  - `DEFAULT_COMPANION_PREFERENCES.themeFamily = "solarized"`(`preferences.ts:72-76`).
  - `sanitizeCompanionPreferences`(`preferences.ts:122-151`)는 `input.themeFamily` 가 유효 패밀리가 아니면 legacy `theme` 값으로, 그것도 없으면 default 로 폴백. 저장된 `themeFamily:"gruvbox"|"nord"` 문자열은 제거 후 유효하지 않게 되므로 **패밀리 문자열 마이그레이션이 없으면 무조건 default 로 떨어진다.**
- 테마 토큰 CSS: `apps/companion/src/styles/themes.css` — `main[data-theme="solarized-dark"]` … `github-light` 8블록(각 surface/line/text/muted/faint/accent(+strong/soft)/blocked/review/done/notify(+soft)/shell-bg/current-step-bg 정의) + `main[data-theme$="-light"]` 그림자 + `main[data-font="…"]` + `main::before`.
- 스와치 CSS: `apps/companion/src/styles/settings.css:212-265` — `.theme-swatch-<value>` 8개(각 `--theme-swatch-surface/accent/secondary/success`). `SettingsPanel.tsx:160-167` 가 `theme-swatch-${option.value}` 클래스를 사용하고, mode 토글로 현재 모드 패밀리만 노출(`SettingsPanel.tsx:51-53`).
- 테스트: `apps/companion/tests/preferences.test.ts`(기본값/sanitize/옵션 단언), `tests/settings-panel.test.tsx`(테마/모드 옵션·라벨 단언), `tests/task-row.test.tsx`(액션 버튼/마크업 단언), `tests/app-shell.test.tsx`(초기 `data-theme`, 8개 theme selector/swatch CSS contract 단언). 이 4개가 변경 영향권.
- 외부 contract 무관: 테마/액션은 전부 companion 프론트엔드 프레젠테이션. `packages/contract/**`, `apps/cli/**`, `apps/companion/src/domain/**`, watcher/activity store 불변.

## 결정 사항 (확정됨 — 2026-06-21)

- [x] **기능 1 액션 위치:** `$AskUserQuestion`(2026-06-21)에서 **A안(상단 헤더 행)** 선택. repo chips 와 같은 줄(상단)에 액션을 두고, step 길이와 무관하게 상단 고정. Rationale: 요청한 "feature/branch/repoName 상단" 의도에 정확히 부합하고 변경 범위 최소.
- [x] **기능 1 라벨 유지:** 버튼은 현행 **아이콘 + 텍스트 라벨**(IDE/Terminal/Finder) 유지. Rationale: 찾기 쉬움(discoverability)이 이 작업의 목적이므로 라벨 제거는 역행. 가로 공간 부족 시 액션 그룹이 repo chips **아래 줄로 wrap**(여전히 steps 위, 상단권). icon-only 축약은 비채택.
- [x] **기능 1 접힘 상태 비노출:** 액션은 카드가 펼쳐졌을 때만(`task-detail` 내부) 노출. summary 상시 노출(접힘 상태)은 비채택 — 토글 클릭과 충돌(`stopPropagation` 필요)하고 스코프 확대. Rationale: A안으로 충분.
- [x] **기능 2 라인업:** `$AskUserQuestion`(2026-06-21)에서 **Solarized · Dracula · Catppuccin · GitHub** 선택(Dracula 는 dark 공식 + companion light counterpart). gruvbox·nord 제거.
- [x] **기본 패밀리:** 기본값은 **`solarized`** 를 유지. `themeMode` 는 `system` 유지. Rationale: solarized 는 light/dark 정본이 가장 오래된 표준이고 대비가 안전한 중립 기본.
- [x] **레거시 마이그레이션:** 기존 사용자 보존. 패밀리 문자열·legacy 테마 값 모두 매핑.
  - `gruvbox` → **`dracula`** (사용자 follow-up 으로 Gruvbox slot 을 Dracula 가 대체).
  - `nord` → **`solarized`** (쿨 블루 액센트 근접).
  - mode(light/dark/system)는 그대로 보존.
  - Rationale: 제거된 패밀리를 default 로 떨구지 않고 가장 가까운 생존 패밀리로 옮겨 사용자 설정 연속성 유지.
- [x] **테마 컨트롤 형태 불변:** mode 토글 + 패밀리 버튼 그리드 + 스와치(`SettingsPanel`) 구조는 유지하고 데이터만 교체. Rationale: 0037 에서 확정된 컨트롤 셰이프 재변경 금지.
- [x] **토큰 완전성:** 신규 테마(catppuccin/github)는 기존 8테마와 **동일한 토큰 전체 집합**을 light/dark 각각 정의(누락 시 깨짐). Rationale: 0037 의 "모든 프리셋은 완전한 토큰 표면 정의" 원칙 계승.

## 테마 색 기준 (canonical anchors)

지원 패밀리는 아래 브랜드 색을 기준으로 기존 토큰 구조(`--surface-0..3`, `--line`, `--line-strong`, `--text`, `--muted`, `--faint`, `--accent`, `--accent-strong`, `--accent-soft`, `--blocked`/`-soft`, `--review`/`-soft`, `--done`/`-soft`, `--notify`/`-soft`, `--shell-bg`, `--current-step-bg`)를 채운다. light 는 surface 를 밝게/텍스트를 어둡게 뒤집고 accent 는 대비를 위해 약간 진하게(기존 light 처리 방식과 동일).

- **Dracula Dark:** background `#282a36`, current line/comment `#6272a4`, selection/surface `#44475a`, foreground `#f8f8f2`, purple `#bd93f9`, pink `#ff79c6`, green `#50fa7b`, yellow `#f1fa8c`.
- **Dracula Light (companion counterpart):** light foreground/background inversion around `#f8f8f2/#282a36`, preserving blue-gray `#6272a4` in faint/line roles and Dracula purple as the accent.
- **Catppuccin Mocha (dark):** base `#1e1e2e`, mantle `#181825`, surface0 `#313244`, surface1 `#45475a`, surface2 `#585b70`, text `#cdd6f4`, subtext `#a6adc8`, overlay `#7f849c`, accent(mauve) `#cba6f7`(strong `#ddb6f9`), blocked(red) `#f38ba8`, review(pink) `#f5c2e7`, done(green) `#a6e3a1`, notify(yellow) `#f9e2af`.
- **Catppuccin Latte (light):** base `#eff1f5`, surface0 `#ccd0da`, surface1 `#bcc0cc`, surface2 `#acb0be`, text `#4c4f69`, subtext `#6c6f85`, accent(mauve) `#8839ef`, blocked(red) `#d20f39`, review(pink/mauve) `#ea76cb`, done(green) `#40a02b`, notify(yellow) `#df8e1d`.
- **GitHub Dark (Primer):** canvas `#0d1117`, subtle `#161b22`, border `#30363d`, fg `#e6edf3`, fg.muted `#7d8590`, fg.subtle `#6e7681`, accent `#2f81f7`(strong `#58a6ff`), danger(red) `#f85149`, purple(review) `#a371f7`, success(green) `#3fb950`, attention(yellow) `#d29922`.
- **GitHub Light (Primer):** canvas `#ffffff`, subtle `#f6f8fa`, border `#d0d7de`, fg `#1f2328`, fg.muted `#656d76`, fg.subtle `#6e7781`, accent `#0969da`, danger(red) `#cf222e`, purple(review) `#8250df`, success(green) `#1a7f37`, attention(yellow) `#9a6700`.

> 정확한 중간 surface 단계(`--surface-1..3`)와 `*-soft`(rgba 0.13~0.18) 값은 기존 themes.css 패턴을 그대로 따라 보간한다. light 의 `--shadow-soft/strong` 은 기존 `main[data-theme$="-light"]` 규칙이 자동 적용된다.

### 테마 role mapping 검증 기준

이번 변경은 "비슷한 hex 몇 개가 존재한다"가 아니라 **각 테마의 대표 색이 실제 UI role 에 배치되는지**를 기준으로 검증한다. 구현자는 아래 role mapping 을 `themes.css`/`settings.css`에 반영하고, CSS contract 테스트가 신규 8개 selector 와 swatch 를 모두 확인하도록 갱신한다.

| 패밀리 | Mode | 핵심 정체성 | Required role mapping |
|---|---|---|---|
| Solarized | dark | blue-green low-contrast terminal | `surface-0=#002b36`, `surface-1=#073642`, text 계열은 `#eee8d5/#93a1a1/#657b83`, `accent=#268bd2`, status 는 공식 red/violet/green/yellow |
| Solarized | light | warm ivory paper + same accent scale | `surface-0=#fdf6e3`, `surface-1/2`는 `#eee8d5` 계열, text 계열은 `#073642/#586e75/#839496`, `accent=#268bd2`, status 는 공식 red/violet/green/yellow |
| Dracula | dark | blue-gray editor background + purple/pink accents | `surface-0=#282a36`, stepped surfaces include `#44475a/#6272a4`, `text=#f8f8f2`, `accent=#bd93f9`, status uses official red/pink/green/yellow |
| Dracula | light | companion light counterpart for mode parity | `surface-0=#f8f8f2`, text `#282a36`, faint/line roles preserve Dracula blue-gray `#6272a4`, accent derives from Dracula purple |
| Catppuccin | dark | Mocha: cozy dark base + pastel mauve | `surface-0=#1e1e2e`, `surface-1=#181825` 또는 `#313244`, stepped surfaces use Catppuccin surface/overlay values only, `text=#cdd6f4`, `accent=#cba6f7`, status uses official red/pink/green/yellow |
| Catppuccin | light | Latte: light base + high-contrast mauve | `surface-0=#eff1f5`, stepped surfaces use Latte surface values, `text=#4c4f69`, `accent=#8839ef`, status uses official red/pink/green/yellow |
| GitHub | dark | Primer dark canvas + functional blue | `surface-0=#0d1117`, `surface-1=#161b22`, borders near `#30363d`, `text=#e6edf3`, `muted=#7d8590`, `accent=#2f81f7/#58a6ff`, status uses Primer danger/purple/success/attention |
| GitHub | light | Primer light canvas + functional blue | `surface-0=#ffffff`, `surface-1=#f6f8fa`, borders near `#d0d7de`, `text=#1f2328`, `muted=#656d76`, `accent=#0969da`, status uses Primer danger/purple/success/attention |

Removed themes are treated as migration inputs only:

- Gruvbox 는 follow-up 으로 Dracula 가 대체하므로 신규 라인업에서는 제거하고 기존 `gruvbox`/`gruvbox-*` 값은 `dracula` 로 마이그레이션한다.
- Nord dark 는 Polar Night/Snow Storm role 은 비교적 맞지만 공식 light 가 없으므로 신규 라인업에서는 제거한다.

## 파일 구조

```text
# 기능 1 — 액션 아이콘 상단 이동
apps/companion/src/ui/TaskRow.tsx              # JSX 재배치: RepoChips+actions 를 상단 헤더 행으로
apps/companion/src/styles/task-details.css     # 상단 헤더 행(.task-detail-header) 레이아웃
apps/companion/src/styles/task-actions.css     # .task-actions 의 margin/정렬을 헤더 행 문맥에 맞게 조정
apps/companion/tests/task-row.test.tsx         # 액션이 steps 앞(상단)에 위치하는지 단언 추가

# 기능 2 — 테마 라인업 정리
apps/companion/src/application/themePreferences.ts  # 패밀리/값/옵션/타입가드/legacy 매핑 교체
apps/companion/src/application/preferences.ts       # 패밀리 문자열 마이그레이션
apps/companion/src/styles/themes.css                # gruvbox/nord 제거, dracula/catppuccin/github 토큰 유지
apps/companion/src/styles/settings.css              # .theme-swatch-* 교체(gruvbox/nord→dracula/github 등)
apps/companion/tests/preferences.test.ts            # 기본값/마이그레이션/옵션 단언 갱신
apps/companion/tests/settings-panel.test.tsx        # 테마 옵션/라벨 단언 갱신
apps/companion/tests/app-shell.test.tsx             # 기본 data-theme + 8개 theme selector/swatch contract 갱신

# 공통
DESIGN.md                                       # 액션 위치 + 테마 라인업 변경 dated revision 추가
../TASK-WORKBRANCH.md                           # 진행 상황 기록만

# 변경 금지
packages/contract/**, apps/cli/**
apps/companion/src/domain/**, apps/companion/src/infrastructure/acl.ts
watcher/activity store 동작, autostart/store 플러그인 배선
docs/plans/0032..0038-*.md (과거 기록)
```

## 구현 작업

> 각 Task 후 관련 테스트를 즉시 돌려 green 유지. 기능 1·2 는 독립이라 순서 무관하나, 한 브랜치에서 진행한다.

### Task 1: 액션 아이콘을 상단 헤더 행으로 이동 (구조)
**Files:** `apps/companion/src/ui/TaskRow.tsx`

- [x] `task-detail` 첫 자식으로 헤더 행(`.task-detail-header`)을 만들어 그 안에 `RepoChips`(좌측, 신축)와 `.task-actions`(우측, 고정)를 배치.
- [x] 기존 위치(steps 뒤)의 `.task-actions` 렌더 블록을 제거(중복 금지). 액션 생성 로직(`taskActionsFor`, `onAction`, `TaskActionIcon`, 라벨/aria-label)은 그대로 재사용.
- [x] 렌더 순서: `task-detail-header(RepoChips + actions) → CurrentStep → steps`.
- [x] repos 가 없을 때도 액션 행은 보이도록(현재 `RepoChips` 는 빈 배열이면 `null` 반환) 헤더 행 자체는 액션이 있으면 항상 렌더.
- [x] Acceptance: 카드 펼침 시 액션 버튼이 repo chips 와 같은 헤더 영역에 있고 steps 보다 위에 온다.

### Task 2: 상단 헤더 행 레이아웃 CSS
**Files:** `apps/companion/src/styles/task-details.css`, `apps/companion/src/styles/task-actions.css`

- [x] `.task-detail-header`: `display:flex; align-items:flex-start; justify-content:space-between; gap:8px; flex-wrap:wrap`. repo chips 컨테이너는 `flex:1 1 auto; min-width:0`(내부 wrap 유지), 액션 그룹은 `flex:0 0 auto`.
- [x] 좁은 폭에서 액션 그룹이 repo chips 아래 줄로 wrap 되도록 허용(여전히 steps 위). 가로 넘침/overflow 없는지 확인.
- [x] `.task-actions` 의 `margin-top` 등 기존 하단 문맥용 간격을 헤더 행 문맥에 맞게 조정(상단 첫 요소이므로 `RepoChips`/`task-detail` 의 `margin-top` 과 이중 간격이 생기지 않게).
- [x] 기존 `.task-action` / `.task-action-icon` / `.task-action-separator` 스타일은 유지.
- [x] Acceptance: 넓은 폭=한 줄(좌 chips / 우 actions), 좁은 폭=2줄 wrap, 어느 경우든 steps 위에 위치하며 시각 회귀 없음.

### Task 3: 테마 메타데이터 교체 (gruvbox/nord → dracula/github)
**Files:** `apps/companion/src/application/themePreferences.ts`

- [x] `COMPANION_THEME_FAMILY_VALUES` = `["solarized","dracula","catppuccin","github"]`.
- [x] `COMPANION_THEME_VALUES` = solarized/dracula/catppuccin/github 각 `-dark`/`-light` 8값.
- [x] `THEME_BY_FAMILY_AND_MODE` 와 `COMPANION_THEME_OPTIONS`(familyLabel: `Solarized`/`Dracula`/`Catppuccin`/`GitHub`, label: `… Dark`/`… Light`, mode) 갱신.
- [x] `isCompanionTheme`/`isCompanionThemeFamily` 의 case 를 신규 값으로 교체.
- [x] 레거시 처리: `PREVIOUS_COMPANION_THEME_VALUES` 에 제거되는 `gruvbox-dark/gruvbox-light/nord-dark/nord-light` 를 추가(기존 terminal-dark/amber-crt/green-mono/high-contrast 와 함께). `themeFamilyFromLegacyTheme` 에서 `gruvbox-*`→`dracula`, `nord-*`→`solarized` 로 매핑하고, 기존 legacy 4종 매핑도 생존 패밀리로 재지정(`high-contrast`→`github`, `terminal-dark`→`github`, `amber-crt`→`dracula`, `green-mono`→`solarized`). `themeModeFromLegacyTheme` 에 신규 legacy 값의 모드 추가.
- [x] `isLegacyCompanionTheme` 가 신규 + 제거된 값 모두 인식하는지 확인.
- [x] Acceptance: `tsc` 통과, 옵션 8개(4패밀리×2모드), 타입가드가 gruvbox/nord 를 더 이상 유효 패밀리로 보지 않음.

### Task 4: 기본값 + 패밀리 문자열 마이그레이션
**Files:** `apps/companion/src/application/preferences.ts`

- [x] `DEFAULT_COMPANION_PREFERENCES.themeFamily` = `"solarized"`(themeMode `system` 유지).
- [x] `sanitizeCompanionPreferences` 에 **제거된 패밀리 문자열 마이그레이션** 추가: 저장된 `themeFamily` 가 `"gruvbox"`→`"dracula"`, `"nord"`→`"solarized"` 로 매핑된 뒤 유효성 검사. 즉 우선순위: 유효 신규 패밀리 > 제거된 패밀리 매핑 > legacy `theme` 값 유래 > default. (작은 헬퍼 `migrateRemovedThemeFamily(value)` 로 분리.)
- [x] 마이그레이션/폴백이 일어나면 `sanitized:true` 로 보고(앱 셸이 footer/status 안내 표시).
- [x] Acceptance: 저장값 `themeFamily:"gruvbox"` → `dracula`(모드 보존), `"nord"` → `solarized`, 알 수 없는 값 → `solarized` default.

### Task 5: 테마 토큰 CSS 교체
**Files:** `apps/companion/src/styles/themes.css`

- [x] `main[data-theme="gruvbox-dark"]`, `gruvbox-light`, `nord-dark`, `nord-light` 블록을 제거한다.
- [x] `dracula-dark`, `dracula-light`, `catppuccin-*`, `github-*` 블록을 유지/추가 — 위 "테마 색 기준"의 brand 색으로 **기존 8테마와 동일한 토큰 전 집합**을 채움(surfaces/line/text/muted/faint/accent(+strong/soft)/blocked/review/done/notify(+soft)/shell-bg/current-step-bg).
- [x] `main[data-theme$="-light"]`, `main[data-font="…"]`, `main::before` 규칙은 유지(자동으로 신규 light 에도 적용).
- [x] gruvbox/nord 잔존 literal 이 없는지 grep: `rg "gruvbox|nord" apps/companion/src/styles/themes.css` → 0건.
- [x] Acceptance: 4패밀리×2모드 = 8개 `data-theme` 블록이 완전한 토큰으로 정의됨.

### Task 6: 스와치 CSS 교체
**Files:** `apps/companion/src/styles/settings.css`

- [x] `.theme-swatch-gruvbox-dark/-light`, `.theme-swatch-nord-dark/-light` 제거.
- [x] `.theme-swatch-dracula-dark/-light`, `.theme-swatch-catppuccin-dark/-light`, `.theme-swatch-github-dark/-light` 유지/추가 — 각 `--theme-swatch-surface/accent/secondary/success` 를 해당 테마 brand 색으로(`SettingsPanel` 의 `theme-swatch-${value}` 와 값 매칭).
- [x] Acceptance: 설정 패널의 4개 패밀리 버튼 스와치가 light/dark 모드별로 올바른 색을 표시(빈/누락 스와치 없음).

### Task 7: 테스트 갱신
**Files:** `apps/companion/tests/preferences.test.ts`, `tests/settings-panel.test.tsx`, `tests/task-row.test.tsx`, `tests/app-shell.test.tsx`

- [x] `preferences.test.ts`: 기본 패밀리 `solarized` 단언, `gruvbox`→`dracula`·`nord`→`solarized` 마이그레이션(모드 보존) 단언, 옵션 목록이 신규 4패밀리만 포함하고 dracula/nord 미포함 단언.
- [x] `settings-panel.test.tsx`: 테마 옵션/라벨이 `Solarized/Dracula/Catppuccin/GitHub` 인지 단언, gruvbox/nord 라벨 부재 단언.
- [x] `task-row.test.tsx`: 액션 버튼(IDE/Terminal/Finder)이 존재하고, DOM 순서상 steps 목록보다 **앞**(상단 헤더)에 오는지 단언 추가(예: 헤더 컨테이너 내 존재 또는 `compareDocumentPosition`).
- [x] `app-shell.test.tsx`: 초기 static markup 의 `data-theme` 단언을 `solarized-*` 기본값에 맞게 갱신하고, CSS contract loop 의 8개 theme selector/swatch 목록을 `solarized/dracula/catppuccin/github` 로 교체. gruvbox/nord selector/swatch 가 없음을 단언.
- [x] CSS contract 테스트는 단순 selector 존재만 보지 말고, 신규 8개 theme block 과 swatch 가 위 **테마 role mapping 검증 기준**의 핵심 색을 최소 1개 이상 포함하는지 단언(예: GitHub dark canvas `#0d1117`, Catppuccin Mocha base `#1e1e2e`, Solarized base03 `#002b36`, Dracula background `#282a36` and comment/current-line `#6272a4`).
- [x] Acceptance: `pnpm --filter @workbranch/companion test` 전체 green.

### Task 8: DESIGN.md / 디자인 계약 갱신
**Files:** `DESIGN.md`, `../TASK-WORKBRANCH.md`

- [x] **Components:** 작업 카드의 액션 컨트롤이 detail 하단 → **detail 상단 헤더 행**(repo chips 와 동행)으로 이동했음을 반영.
- [x] **Color/theme tokens:** 지원 테마 패밀리를 `Solarized/Dracula/Catppuccin/GitHub`(각 light+dark)로 갱신, gruvbox/nord 제거 및 마이그레이션 매핑 기록.
- [x] 구현일자 기준 **Direction revision** 항목 추가.
- [x] 플레이스홀더 부재 확인: `rg -n "TBD|TODO|placeholder|fill in" DESIGN.md` → 0건.

## 검증

리포 루트에서:

- [x] `pnpm --filter @workbranch/companion test` → 전체 통과(갱신된 preferences/settings-panel/task-row 포함).
- [x] `pnpm --filter @workbranch/companion typecheck` → 통과.
- [x] `pnpm --filter @workbranch/companion lint` → 신규 lint 에러 없음(기존 `parseContract.ts` info diagnostics 만 허용).
- [x] `pnpm --filter @workbranch/companion build` → Vite 프로덕션 빌드 통과.
- [x] 잔존 확인: `rg -n "gruvbox|nord" apps/companion/src` → themePreferences 의 legacy 마이그레이션 매핑 외에는 0건(themes.css/settings.css 에 gruvbox/nord 토큰·스와치 없음).
- [x] 색상 충실도 확인: `themes.css`/`settings.css` 의 신규 8개 theme/swatch 가 위 role mapping 핵심 색을 포함하고, retained themes(Solarized/Dracula)는 공식 palette role 을 유지한다. 단순히 비슷한 임의 보간색만 있는 상태는 실패로 본다.
- [x] `git diff --check` → 통과.

수동 시각/동작 게이트 (`tauri dev` 또는 Vite + IPC mock fallback):

- [ ] step 이 많은(스크롤 필요) 카드에서 IDE/Terminal/Finder 가 펼침 즉시 상단(steps 위)에 보인다.
- [ ] 넓은 폭=한 줄, 좁은 폭=액션 그룹 wrap, 어느 경우든 steps 위 유지.
- [ ] 액션 클릭이 기존과 동일하게 IDE/Terminal/Finder 실행 콜백을 호출(카드 토글에 영향 없음).
- [ ] 설정 패널에서 4개 패밀리(Solarized/Dracula/Catppuccin/GitHub) × Light/Dark/System 전환 시 전체 UI 가 일관되게 바뀌고 gruvbox/nord 잔재가 남지 않는다.
- [ ] 각 테마에서 대비/포커스 링/배지/상태색이 읽힌다.
- [ ] 기존 설정에 gruvbox/nord 가 저장돼 있던 경우(또는 강제 주입 시) dracula/solarized 로 마이그레이션되고 footer/status 에 안내가 뜬다.

네이티브 tray popover 관찰 gap: tray popover 직접 상호작용이 불가하면 기록하고 Vite fallback 캡처로 대체, 해당 task 는 `review` 로 둔다. 이번 실행에서는 non-interactive 환경이라 수동 tray 관찰은 미수행하고 automated/static 검증과 Tauri build evidence 로 대체했다.

## 2026-06-21 추가 변경

- 사용자 follow-up 으로 action bar 는 top header 안에서 full width 를 차지하고 IDE/Terminal/Finder 세 버튼이 각각 1/3 폭을 가진다. 기존 separator 는 레이아웃 폭을 차지하지 않도록 숨긴다.
- dark theme lineup 에서 Gruvbox 를 Dracula 로 교체한다. Settings model 은 family+mode 구조라 Dracula family 는 dark/light 값을 모두 제공하고, 기존 `gruvbox` family 또는 `gruvbox-*` legacy 값은 `dracula` 로 마이그레이션한다.
- 체크리스트 step status 는 `✓`/`☐` 텍스트 prefix 대신 별도 marker column 으로 분리한다. 완료 step 은 neutral marker, 미완료 step 은 pending ring 을 쓰고 step text 는 별도 span 으로 렌더해 긴 문장도 marker 와 섞이지 않게 한다. Depth 0 marker 는 smaller/lighter square, depth 1 marker 는 circle, 더 깊은 depth 는 더 작은 circle 로 구분한다.

## 구현/검증 evidence

- RED: `pnpm --filter @workbranch/companion test -- tests/task-row.test.tsx tests/preferences.test.ts tests/settings-panel.test.tsx tests/app-shell.test.tsx` failed against the new contract before production changes(default/theme options/action order mismatches).
- GREEN targeted/full: `pnpm --filter @workbranch/companion test` → 12 files / 54 tests passed.
- Type/build: `pnpm --filter @workbranch/companion typecheck`, `pnpm --filter @workbranch/companion build`, and `pnpm --filter @workbranch/companion tauri build` passed.
- Lint: `pnpm --filter @workbranch/companion lint` exited 0 with existing `parseContract.ts` info diagnostics only.
- Residual grep: `themes.css`/`settings.css` contain no `gruvbox|nord`; `apps/companion/src` retains those literals only in legacy migration inputs.
- DESIGN: `rg -n "TBD|TODO|placeholder|fill in" DESIGN.md` returned no matches.
- Diff hygiene: `git diff --check` passed.
- Manual visual gap: native tray popover was not visually inspected in this non-interactive run; coverage is static markup/CSS contract tests plus Vite/Tauri builds. Keep human visual review focused on long-step cards and all 8 theme modes before release.
- FOLLOW-UP GREEN: targeted suite `pnpm test -- tests/preferences.test.ts tests/settings-panel.test.tsx tests/app-shell.test.tsx` passed after action thirds + Dracula lineup changes.
- FOLLOW-UP RED/GREEN: `tests/task-row.test.tsx` and `tests/app-shell.test.tsx` first failed against the new checklist marker contract, then passed after replacing `✓`/`☐` prefixes with `.step-marker-*` markup and grid CSS. Later follow-up CSS tests locked smaller/lighter depth 0 square, depth 1 circle, and neutral completed markers instead of bright green.

## Acceptance criteria

- 작업 카드 펼침 시 IDE/Terminal/Finder 액션이 repo/branch 가 있는 **상단 헤더 행**에 위치하며, plan/step 길이와 무관하게 steps 위에 고정된다(아이콘+라벨 유지).
- Checklist step status 는 checkmark/checkbox glyph 텍스트가 아니라 정렬된 marker column 으로 표현되어야 하며, step text 앞에 `✓`/`☐` prefix 가 남으면 실패다. Depth 0은 smaller/lighter square marker, depth 1은 circle marker, completed marker는 muted/faint neutral tone 이다.
- 액션 실행 동작(IDE/Terminal/Finder 콜백)·접근성 라벨은 기존과 동일하다.
- 지원 테마 패밀리는 **Solarized / Dracula / Catppuccin / GitHub** 4종이며, 각각 dark/light 토큰을 완전히 정의한다.
- 각 테마는 공식/대표 palette 의 핵심 색을 UI role 에 반영한다. 특히 surface/text/accent/status 가 theme identity 를 보여야 하며, "비슷한 어두운 배경 + 임의 accent" 수준이면 미완료다.
- gruvbox·nord 패밀리/테마 값/토큰/스와치가 제거되고, 기존 사용자 설정은 `gruvbox→dracula`, `nord→solarized`(모드 보존)로 마이그레이션된다.
- 기본 패밀리는 `solarized`(모드 `system`)이며 모든 변경이 테스트로 커버된다.
- CLI contract, task 도메인 모델, ACL, watcher, activity store, autostart/store 배선은 불변.

## Non-goals

- 커스텀 테마 에디터/임의 색 입력 추가 안 함.
- 액션을 접힘(summary) 상태에서 상시 노출하거나 sticky 로 만들지 않음(A안 범위 한정).
- 액션 아이콘 디자인/세트 변경 안 함(위치만 이동).
- 새 폰트/뷰/설정 항목 추가 안 함.
- `workbranch list --json` 등 CLI 스키마 변경 안 함.
- 과거 plan(0032~0038) 재작성 안 함.

## Self-review checklist for this plan

- [x] 기능 1(액션 상단 이동)·기능 2(테마 라인업) 모두 확정된 사용자 결정(2026-06-21 AskUserQuestion)을 반영.
- [x] gruvbox 제거에 따른 라인업 변경·패밀리 문자열 마이그레이션을 명시(놓치면 default 폴백 버그).
- [x] themePreferences/preferences/themes.css/settings.css/테스트의 lockstep 변경을 모두 열거.
- [x] 신규 테마는 기존과 동일한 완전 토큰 집합으로 정의하도록 요구.
- [x] 각 theme 의 official/canonical palette 가 실제 UI role 에 반영되는지 확인하는 role mapping 기준을 추가.
- [x] `app-shell.test.tsx` 의 기본 theme 및 CSS selector/swatch contract 갱신 누락을 테스트 작업 범위에 추가.
- [x] CLI contract/도메인/watcher 불변, 과거 plan 비범위 명시.
- [x] TBD/TODO 플레이스홀더 없음.
