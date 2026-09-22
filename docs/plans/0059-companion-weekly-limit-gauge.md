# 0059 Companion Weekly Limit Gauge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Before each behavior change use `superpowers:test-driven-development` (red → green → refactor). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Companion에 coding agent 계정(Claude Code Max, Codex 등)별 **다음 weekly limit reset 시각**을 등록하고, Main view 상단에서 계정마다 "이번 주 한도 window(마지막 reset → 다음 reset)가 공용 날짜축 위 어디에 놓여 있고, 지금이 그 안 어디인지"를 가로 막대 gauge + 모든 행을 관통하는 "지금" 세로선으로 보여준다. 사용자는 메뉴바를 열자마자 어느 계정이 방금 초기화됐고(FRESH), 어느 계정이 곧 초기화되는지(SOON), 각 계정의 다음 reset까지 얼마나 남았고 그것이 무슨 요일 몇 시인지를 task 목록을 읽기 전에 확인할 수 있어야 한다. 참고 이미지(`Claude Code Max Strategy.jpg`)의 "계정 행 + 공용 날짜축 + 오늘 세로선" 구조를 따라, 계정별 초기화 시점을 분산해 매일 초기화된 계정을 쓰는 운용을 Companion이 시각적으로 뒷받침한다.

**Architecture:** frontend 전용 기능이다. CLI, contract(JSON schema), Tauri command/Rust는 바꾸지 않는다. 계정 목록은 기존 `companion-preferences.json`/`companion-notes.json`과 같은 tauri plugin-store 패턴으로 `companion-limits.json`(key `accounts`)에 저장하고, `useLimitAccounts` hook이 optimistic update + 직렬화된 save queue + 실패 복원을 담당한다. 계정은 사용자가 `/usage`에서 읽은 **다음 reset 시점(anchor, epoch seconds)**을 저장하고, `src/domain/limits.ts`의 순수 함수가 anchor를 로컬 달력 7일 단위로 앞뒤 정규화해 현재 window(`마지막 reset`, `다음 reset`, 경과 비율, 남은 시간, phase)와 공용 시간축(`now − 7d … now + 7d`, 로컬 자정 셀, 축 비율)을 계산한다. `WeeklyLimitGauge`가 Main view에서 `AgentHeader` 아래·`StageBoard` 위에 날짜축 헤더와 계정별 막대 행을 CSS `subgrid`로 column 정렬해 렌더링하고, `SettingsPanel`의 새 `Weekly Limits` 섹션이 계정 추가/편집(`datetime-local`)/삭제를 제공한다. 시각 갱신은 기존 `useCurrentEpochSeconds`(60초)를 재사용한다.

**Tech Stack:** Tauri v2 + `@tauri-apps/plugin-store`(기존 `store:default` capability로 충분), React 18, TypeScript strict mode, plain CSS(기존 theme token만, `subgrid`는 최소 macOS 13.0/Safari 16 WebKit에서 지원), Vitest + `renderToStaticMarkup`, Biome, pnpm.

**Approved mockup:** https://claude.ai/artifact/DLHAkzBepmDFp5Vv3ZB6nM (2026-09-22. 실제 Companion CSS 위에 신규 패널·Settings 섹션을 그린 시안. 사용자 선택: D2 "B 다음 reset 날짜·시각", D4 "시각 표시". 시안의 토글 기본값이 확정 조합이다.)

**Reference:** 사용자 제공 이미지 `~/Downloads/Claude Code Max Strategy.jpg` — 계정 8개를 하루 간격으로 구독 시작해 매일 초기화된 계정의 한도를 100% 쓰는 "풍차 돌리기" 전략도. 계정 행 + 공용 날짜축 + "오늘" 세로선 구조.

---

## 승인된 사용자 문제와 흐름

1. 여러 coding agent 계정을 돌려 쓰는 사용자는 계정마다 다른 weekly limit reset 시각을 기억해야 한다 → Companion Settings에서 계정별 다음 reset 날짜·시각을 등록한다("계정 별로 weekly reset time 을 설정"). 입력값은 `/usage`가 보여주는 "Resets <날짜> <시각>"을 그대로 옮겨 적는 `datetime-local`이다(2026-09-22 시안에서 B 선택).
2. 지금 어느 계정을 써야 하는지 한눈에 알고 싶다 → Main view에서 공용 날짜축 위에 계정별 window 막대를 놓고 "지금" 세로선으로 현재 위치를 표시한다("체중계처럼 horizontal 에 gauge 가 있고, 특정 시점을 표시"; 참고 이미지 구조인 공용 날짜축 안 선택).
3. 각 행에는 남은 시간과 함께 reset 요일·시각(`2d 0h · Thu 15:00`)을 표시한다(시안에서 "시각 표시" 선택).
4. Companion은 사용량(%)을 알 수 없으므로 이 gauge는 **시간 기반**이다. 마지막 reset → 다음 reset 사이에서 현재 시각의 위치와 남은 시간을 보여주며, 실제 토큰 사용량은 표시하지 않는다.

## Decision Gates

### 사용자 확정 (2026-09-22)

- [x] G1. Main view 내 위치
  - Options: A) `AgentHeader` 아래·`StageBoard` 위 별도 패널(`WEEKLY LIMITS`), B) `StageBoard` 안 `00 BASE` 위에 새 그룹, C) Settings에서만 표시, D) 새 탭.
  - Current evidence: `apps/companion/src/App.tsx:218-241`은 Main view를 `<section className="view-panel">` 안에서 `StageBoard` + 빈 상태 문구로만 구성한다. `StageBoard`는 `WORKTREE STATUS` 캡션과 emphasis rail을 가진 지배적 surface다(`DESIGN.md` Information architecture 3).
  - Status: resolved(user, A) — 계정이 0개면 패널 자체를 렌더링하지 않아 기존 사용자에게는 변화가 없고, `StageBoard`의 prop/테스트를 건드리지 않는다. 한도 정보는 worktree 상태와 다른 축(계정)이므로 보드 안 그룹이 아니라 별도 quiet 패널로 둔다.
- [x] G2. gauge 의미
  - Options: A) 계정별 자(ruler) — 각 행이 자기 window(0% = 마지막 reset, 100% = 다음 reset)를 눈금으로 펼치고 바늘이 "지금"을 가리킴. B) **공용 절대 시간축** — 헤더에 날짜축(`now − 7d … now + 7d`)을 한 번 그리고 각 행은 자기 window 막대(마지막 reset → 다음 reset)를 그 축 위에 놓으며, "지금" 세로선은 모든 행을 관통한다(참고 이미지 구조).
  - Status: resolved(user, B) — 계정 간 reset 시점의 stagger가 한 화면에서 비교되도록 공용 축을 택했다. 모든 막대는 길이 7일(축의 50%)이고 항상 "지금" 선을 지나며, "지금" 선은 축 정중앙(50%)에 고정된다. 시간이 흐르면 막대가 왼쪽으로 흐르고, reset 순간에 막대가 7일 오른쪽으로 점프한다. 460px에서 하루 폭이 좁아지는 문제는 축 라벨을 격일로 숨겨 해결한다(D6).
- [x] G3. 실제 사용량(%) 표시
  - Options: A) 시간 기반 gauge만, B) 사용량 API/로컬 파일 연동.
  - Current evidence: Companion은 CLI JSON contract와 로컬 파일만 읽는다(`apps/companion/README.md` Scope). Claude Code/Codex의 계정 사용량을 안정적으로 읽는 공개 계약이 repo에 없다.
  - Status: resolved(기본값 채택, A) — 사용량 연동은 범위 밖으로 두고, 이 plan의 gauge는 "window 안의 시간 위치"임을 Settings hint 문구로 명확히 한다.

### plan-decision-grill 확정 (2026-09-22)

- [x] G4. 시간축 기준점
  - Impact: 무엇이 움직이고 무엇이 고정인지(사용자 체감), `axisRatio`/`limitAxisDays` 정의, 테스트 기대값.
  - Options: A) 오늘 중심 15일 달력 컬럼(`midnight(today−7d) … midnight(today+8d)`, 날짜 라벨 고정, 지금 선이 오늘 칸 안에서 이동, 자정에 축이 한 칸 이동), B) 지금 중심 14일 선형축(`now − 7d … now + 7d`, 지금 선 50% 고정, 막대·라벨이 매분 흐름, 양 끝 partial 셀).
  - Recommended default: A(참고 이미지 독법·라벨 고정·partial 셀 규칙 불필요).
  - Status: resolved(user, B) — "지금" 선이 항상 같은 자리에 있는 고정점을 우선한다. D2 "시간축과 격자", D4, D6, Task 1/4의 partial 셀 라벨 규칙(반나절 미만 숨김, 첫 라벨 셀 `M/D`)을 그대로 유지한다.
- [x] G5. reset 시각의 데이터 모델
  - Impact: `companion-limits.json` 영구 스키마(나중에 바꾸면 마이그레이션), Settings 입력 컨트롤, domain 계산, 테스트.
  - Options: A) 요일 + `HH:MM`(요일 select + time 입력, 매주 같은 요일·시각 자동 롤오버), B) 다음 reset 날짜·시각 anchor(`datetime-local` 입력, `/usage`의 "Resets …" 날짜를 그대로 입력, 지나면 7일 앞으로 롤오버), C) A 저장 + "next reset" 날짜 보조 입력을 요일/시각으로 변환.
  - Current evidence: `/usage`는 다음 reset을 날짜·시각으로 보여준다. 계정을 며칠 쉬면 window 시작이 바뀔 수 있어 어떤 모델이든 재입력이 필요하다. 시안 https://claude.ai/artifact/DLHAkzBepmDFp5Vv3ZB6nM 에서 A/B/C 비교.
  - Recommended default: A(요청 문구 "weekly reset time", 컨트롤 2개, 규칙이 그대로 읽힘).
  - Status: resolved(user, B) — `/usage` 값을 옮겨 적는 흐름을 우선한다. 저장은 `nextResetAt: number`(epoch seconds, 사용자가 입력한 anchor 그대로), 표시·계산은 anchor를 로컬 달력 7일 단위로 앞뒤 정규화한 "현재 window의 다음 reset"을 쓴다(D2 `resolveNextReset`). Settings의 `datetime-local`은 정규화된 다음 reset을 보여주므로 anchor가 몇 주 전 값이어도 현재 값으로 읽힌다. 요일/시각 select·time 입력(A)과 변환 보조 입력(C)은 만들지 않는다.
- [x] G6. 행 안 reset 시각 표시
  - Impact: facts column 폭(460px에서 축 폭), 행이 전달하는 정보.
  - Options: A) 표시(`2d 0h · Thu 15:00`), B) `title`/aria-label로만 제공(`2d 0h`).
  - Recommended default: B(460px 축 폭 확보; 막대 오른쪽 끝이 날짜를 보여줌).
  - Status: resolved(user, A) — 남은 시간 옆에 reset 요일·시각을 항상 표시한다. 460px에서는 라벨 column을 줄여(`minmax(48px, 64px)`) 축 폭을 확보하고, 시각 QA에서 축 폭이 150px 미만으로 떨어지거나 facts가 잘리면 후속 조정 항목으로 기록한다(자동 숨김은 이번 범위에 넣지 않는다).
- [x] G7. 저장 파일·신규 모듈 명명
  - Impact: `companion-<noun>.json`은 사용자 Application Support에 남는 영구 파일(변경 시 마이그레이션), 모듈/컴포넌트/CSS/테스트 이름은 이 기능의 도메인 어휘를 고정.
  - Current evidence: 기존 store 파일 `companion-preferences.json`/`companion-notes.json`은 모듈명(`preferences.ts`/`notes.ts`)과 저장 명사가 1:1. Companion 소스에 `account`/`limit`/`quota` 어휘 없음. UI 라벨은 `WEEKLY LIMITS`/`Weekly Limits`.
  - Options: A) **limits** — `companion-limits.json`, `domain/limits.ts`, `application/limits.ts`, `useLimitAccounts.ts`, `ui/WeeklyLimitGauge.tsx`, `styles/limit-gauge.css`, `tests/limits.test.ts`, `tests/weekly-limit-gauge.test.tsx`, CSS `limit-*`. B) **accounts** — `companion-accounts.json`, `domain/accounts.ts`, `useAccounts.ts`, `ui/AccountLimitBoard.tsx`, `styles/account-board.css`, CSS `account-*`.
  - Recommended default: A(파일명·모듈명·UI 라벨·CSS 접두어가 한 단어로 추적됨; 계정 개념은 파일 안 `accounts` 키로 드러남).
  - Status: resolved(user, A) — "변경 파일 구조"의 경로를 그대로 확정한다. 파일 안 배열 키는 `accounts`.

### 기본값 채택 (repo evidence)

- [x] 저장 위치
  - Status: resolved(기본값 채택) — tauri plugin-store `companion-limits.json`, key `accounts` → 계정 배열. `companion-notes.json`(`src/application/notes.ts`)과 같은 `load(file, { autoSave: false, defaults: {} })` 패턴. `src-tauri/capabilities/default.json`의 `store:default`로 추가 권한 없이 동작한다. preferences 파일에 섞지 않는다(배열 값·별도 마이그레이션 없음).
- [x] 계정 모델
  - Status: resolved(G5 반영) — `{ id: string, label: string, nextResetAt: number }`. `nextResetAt`은 로컬 `datetime-local` 입력을 epoch seconds로 바꾼 anchor다. timezone은 저장하지 않고 항상 현재 로컬 시간대로 해석한다.
- [x] anchor 정규화와 window 계산
  - Status: resolved(기본값 채택) — 로컬 달력으로 7일씩 옮긴다(`setDate`; wall-clock 시각 유지). `7 × 86400`초 덧셈은 DST 전환 주에 1시간씩 어긋나므로 금지한다. `다음 reset` = anchor를 `now < next` 이고 `next − 7일 <= now` 가 될 때까지 앞(과거 anchor)·뒤(7일 넘게 미래인 anchor)로 롤. `마지막 reset` = 다음 reset − 7일(달력). anchor가 정확히 `now`면 새 window의 시작(경과 0%)으로 본다. 저장 파일은 갱신하지 않는다(정규화는 읽을 때마다 순수 계산).
- [x] 시간축과 격자
  - Status: resolved(G4 반영) — 축은 **선형 절대 시간** `[now − 7·86400, now + 7·86400]`(정확히 14일, "지금" = 50%)이다. window 막대 양 끝과 격자선은 epoch를 축 비율로 변환해 놓는다. 격자선은 축 안의 **로컬 자정**마다 그리므로 DST 주에는 한 셀이 23h/25h로 보이며 이것이 올바른 표현이다. 축 라벨은 셀(자정~자정) 가운데에 놓는 날짜 숫자(`22`)만 쓰고, 월 정보는 캡션 오른쪽의 축 범위(`9/15 – 9/29`)가 준다(2026-09-22 시각 QA: 첫 라벨 셀의 `M/D` 라벨이 축 가장자리에서 잘리거나 이웃과 겹쳐 폐기). 폭이 반나절 미만인 양 끝 partial 셀은 라벨 없이 격자선만 둔다. 오늘 셀 라벨은 emphasis 색·굵게.
- [x] column 정렬
  - Status: resolved(기본값 채택) — 날짜축 헤더와 모든 계정 행이 같은 `label | axis | facts` column을 공유해야 막대가 축과 맞는다. 행마다 별도 grid를 두면 `auto` facts 폭이 행마다 달라지므로, `.limit-table` 하나가 column을 소유하고 헤더/목록/행은 `grid-template-columns: subgrid`로 참여한다. 최소 macOS 13.0(`src-tauri/tauri.conf.json`)의 WebKit은 subgrid를 지원한다. 새 dependency 없음.
- [x] phase token
  - Status: resolved(기본값 채택) — `fresh`: 경과 < 24h → `FRESH`(`--done`), `soon`: 남은 시간 < 24h → `SOON`(`--notify`), 그 외 `mid`(token 없음). 7일 window에서 둘이 동시에 참일 수 없다. 막대 채움·reset 마크 색도 phase를 따른다.
- [x] facts 문구
  - Status: resolved(G6 반영) — `남은 시간 · 요일 HH:MM [token]`. 요일·시각은 정규화된 다음 reset의 로컬 값(`formatResetPoint`). 행 `title`에는 전체 날짜(`Resets 2026-09-24 15:00`)를 둔다.
- [x] 행 정렬
  - Status: resolved(기본값 채택) — 사용자가 등록한 순서를 유지한다(0057 base 행과 같은 근거: 매번 같은 자리에서 읽는다). "다음 reset 순" 정렬은 범위 밖.
- [x] 계정 수·라벨
  - Status: resolved(기본값 채택) — 최대 12개(참고 이미지 8개 + 여유). 라벨은 trim 후 최대 40자, 빈 라벨은 허용하고 표시 시 `Account N`(등록 순번)으로 대체한다. 편집 중 빈 문자열 때문에 계정이 사라지지 않게 sanitize는 라벨로 항목을 버리지 않는다. id는 `crypto.randomUUID()`(WebKit/Node 지원)이며 테스트는 `createId`를 주입한다.
- [x] 새 계정 기본값
  - Status: resolved(기본값 채택) — label `Account N`, `nextResetAt` = 현재 시 정각(`HH:00`) + 7일(달력). 방금 초기화된 window로 시작해 사용자가 `/usage` 값을 덮어쓴다. 테스트는 `now`를 주입한다.
- [x] 잘못된 날짜 입력
  - Status: resolved(기본값 채택) — `datetime-local`이 빈 값(WebKit에서 clear)이나 파싱 불가 값을 내면 이전 값을 유지하고 저장하지 않는다. 과거·먼 미래 날짜는 거부하지 않고 정규화가 흡수한다.
- [x] 삭제
  - Status: resolved(기본값 채택) — Settings의 행 `×` 버튼으로 즉시 삭제, 확인 대화상자·undo 없음(설정 화면 안에서만 가능하고 재등록 비용이 낮다).
- [x] 표시 조건
  - Status: resolved(기본값 채택) — 계정이 0개면 Main에 패널을 렌더링하지 않는다. Settings 섹션은 항상 보이며 0개일 때 `No accounts yet` hint를 보여준다.
- [x] 갱신 주기
  - Status: resolved(repo evidence) — `useCurrentEpochSeconds`(`src/ui/useCurrentEpochSeconds.ts`, 60초 interval)를 `WeeklyLimitGauge` 안에서 호출한다. 분 단위 표시이므로 충분하며 애니메이션 루프는 두지 않는다(`DESIGN.md` Performance constraints). 60초마다 축·막대·격자를 함께 재계산한다.
- [x] Tauri 미가용(브라우저 dev)
  - Status: resolved(repo evidence) — `useCompanionSettings`와 같이 `isTauri()`가 false면 store를 열지 않고 빈 목록 + `Tauri runtime unavailable` status로 동작한다.
- [x] 문구 언어
  - Status: resolved(repo evidence) — 기존 Companion UI 문구가 영어이므로 caption/hint/aria도 영어(`WEEKLY LIMITS`, `Add account`, `FRESH`, `SOON`).
- [x] `.tsx` test fixture 검증 방식
  - Status: resolved(repo evidence, 0057과 동일) — `tsconfig.json`의 `tests/**/*.ts` 범위를 넓히지 않는다. 새 `.tsx` 테스트는 기존 `settings-panel.test.tsx`의 element-tree 순회 helper 방식과 `renderToStaticMarkup` 문자열 검증을 따른다.
- [x] 최종 QA surface
  - Status: resolved(기본값 채택) — Vitest/typecheck/lint/Vite build/Tauri build를 필수로 통과시키고, production `WeeklyLimitGauge` + `SettingsPanel`을 `renderToStaticMarkup`으로 뽑아 headless Chrome에서 Claude/Codex × 520/460 × medium/extra-large capture로 overflow·정렬·색을 확인한다. 실제 Tauri 앱에서 계정 등록·재시작 후 복원은 사용자 확인 항목으로 남긴다.

## 결정 사항

### D1. 계정 모델·sanitize·persistence (`apps/companion/src/application/limits.ts`)

```ts
export const COMPANION_LIMITS_STORE_FILE = "companion-limits.json";
export const LIMIT_ACCOUNTS_STORE_KEY = "accounts";
export const MAX_LIMIT_ACCOUNTS = 12;
export const LIMIT_LABEL_MAX_LENGTH = 40;

export type LimitAccount = {
	readonly id: string;          // non-empty, unique
	readonly label: string;       // trimmed, 0..40 chars ("" allowed)
	readonly nextResetAt: number; // epoch seconds; 사용자가 입력한 다음 reset anchor(정규화 전)
};
export type LimitAccounts = readonly LimitAccount[];
export type CompanionLimitStore = {
	readonly get: <T>(key: string) => Promise<T | undefined>;
	readonly set: (key: string, value: unknown) => Promise<void>;
	readonly save: () => Promise<void>;
};

export function isEpochSeconds(value: unknown): value is number; // Number.isSafeInteger(value) && value > 0
export function sanitizeLimitAccounts(value: unknown): LimitAccounts;
export function newLimitAccount(existing: LimitAccounts, now: Date, createId: () => string): LimitAccount;
export function limitAccountDisplayLabel(account: LimitAccount, index: number): string; // label || `Account ${index + 1}`
export function shouldRestoreFailedAccountsUpdate(current: LimitAccounts, attempted: LimitAccounts): boolean; // current === attempted
export async function loadCompanionLimitStore(): Promise<CompanionLimitStore>;
export async function readLimitAccounts(store: CompanionLimitStore): Promise<LimitAccounts>;
export async function writeLimitAccounts(store: CompanionLimitStore, accounts: LimitAccounts): Promise<void>;
```

- `sanitizeLimitAccounts`: 배열이 아니면 `[]`. 각 항목은 object이고 `id`가 비어 있지 않은 string, `nextResetAt`이 `isEpochSeconds`일 때만 유지한다. `label`은 string이 아니면 `""`, string이면 trim 후 40자로 자른다. 같은 `id`는 첫 항목만 남기고, 12개를 넘으면 앞 12개만 남긴다. 손상된 항목 때문에 전체를 버리지 않는다.
- `newLimitAccount`: `label = "Account " + (existing.length + 1)`, `nextResetAt = addLocalDays(now를 정시로 내림, 7)`.
- `writeLimitAccounts`는 `store.set("accounts", accounts)` 후 `store.save()`. `readLimitAccounts`는 `sanitizeLimitAccounts(await store.get("accounts"))`.
- save 직렬화는 기존 `enqueuePreferenceSave`(`preferences.ts`)를 재사용한다.

### D2. window·시간축 순수 함수 (`apps/companion/src/domain/limits.ts`)

```ts
export const WEEKDAY_LABELS: readonly string[]; // ["Sun", "Mon", ... "Sat"]
export const LIMIT_WINDOW_DAYS = 7;
export type LimitPhase = "fresh" | "mid" | "soon";
export const LIMIT_PHASE_BOUNDARY_SECONDS = 24 * 60 * 60;
export type LimitWindow = {
	readonly startAt: number;          // epoch seconds, 마지막 reset
	readonly endAt: number;            // epoch seconds, 다음 reset(정규화됨)
	readonly elapsedRatio: number;     // [0, 1] — window 안 경과 비율(aria "N% elapsed")
	readonly remainingSeconds: number; // > 0 (reset 순간에는 window 길이 전체)
	readonly phase: LimitPhase;
};
export function addLocalDays(epochSeconds: number, days: number): number;               // setDate 기반, wall-clock 유지
export function resolveNextReset(anchorEpochSeconds: number, nowEpochSeconds: number): number; // now < next && addLocalDays(next, -7) <= now
export function limitWindowAt(account: { nextResetAt: number }, nowEpochSeconds: number): LimitWindow;
export function formatRemaining(seconds: number): string;        // "3d 4h" | "4h 12m" | "12m" | "<1m"
export function formatResetPoint(epochSeconds: number): string;  // "Thu 15:00" (local)
export function formatResetDate(epochSeconds: number): string;   // "2026-09-24 15:00" (title용)
export function formatMonthDay(epochSeconds: number): string;    // "9/15" (캡션의 축 범위용)
export function formatDateTimeLocal(epochSeconds: number): string;      // "2026-09-24T15:00" (datetime-local value)
export function parseDateTimeLocal(value: string): number | undefined; // 로컬 해석, 형식 오류/NaN → undefined

export const LIMIT_AXIS_HALF_SPAN_SECONDS = 7 * 24 * 60 * 60; // 축 = [now − 7d, now + 7d]
export type LimitAxisDay = {
	readonly startRatio: number; // 셀 시작(축 시작 또는 로컬 자정)의 축 비율
	readonly endRatio: number;   // 셀 끝(다음 로컬 자정 또는 축 끝)의 축 비율
	readonly label: string;      // "22"(날짜 숫자) | ""(반나절 미만 partial 셀)
	readonly today: boolean;     // now가 속한 로컬 날짜
};
export function axisRatio(epochSeconds: number, nowEpochSeconds: number): number; // clamp((t − (now − 7d)) / 14d, 0, 1)
export function limitAxisDays(nowEpochSeconds: number): readonly LimitAxisDay[];  // 축을 로컬 자정으로 나눈 셀, 시간순
```

- `addLocalDays`: `new Date(epoch * 1000)`에서 `setDate(getDate() + days)` 후 원래 `getHours/getMinutes/getSeconds`를 `setHours`로 재적용해 DST 주에도 wall-clock을 유지한다. 존재하지 않는 로컬 시각(DST 봄 전환)은 JS `Date`의 기본 보정을 그대로 따른다.
- `resolveNextReset`: `(now − anchor) / 7일`의 주 수만큼 먼저 점프한 뒤 `next <= now`면 `+7일`, `addLocalDays(next, −7) > now`면 `−7일`을 반복해 `now < next <= now + 7일(달력)` 범위로 맞춘다. anchor가 `now`와 같으면 `+7일`(새 window 시작).
- `limitWindowAt`: `endAt = resolveNextReset(account.nextResetAt, now)`, `startAt = addLocalDays(endAt, −7)`. `elapsedRatio = clamp((now − startAt) / (endAt − startAt), 0, 1)`. `phase`: `now − startAt < 24h → fresh`, `endAt − now < 24h → soon`, else `mid`. 경계값(정확히 24h)은 `mid`.
- `axisRatio`: 선형 절대 시간. `now`는 항상 정확히 `0.5`. window의 `startAt`/`endAt`은 항상 축 안에 있으므로 clamp는 방어용이다.
- `limitAxisDays`: 축 시작 시각의 로컬 날짜부터 축 끝의 로컬 날짜까지 셀을 만든다. 각 셀의 경계는 `new Date(y, m, d)`(로컬 자정)의 epoch를 `axisRatio`로 변환한 값이며 양 끝은 0/1로 clamp된다. 폭(`endRatio − startRatio`)이 `0.5일 / 14일` 미만이면 `label = ""`, 그 외 라벨은 날짜 숫자(`String(getDate())`). `today`는 `now`의 로컬 날짜와 같은 셀 하나만 참. 월 정보는 `formatMonthDay(now ∓ 7d)`로 캡션이 표시한다.
- `formatRemaining`: `d > 0 → "{d}d {h}h"`, `h > 0 → "{h}h {m}m"`, `m > 0 → "{m}m"`, 그 외 `"<1m"`. 기존 `TaskRow`의 상대 시간 포맷과 목적이 달라 공유하지 않는다.
- `parseDateTimeLocal`: `/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/` 형식만 받고 `new Date(y, m − 1, d, h, min)`(로컬)으로 만든 뒤 `Number.isNaN` 검사. 초는 버린다.
- domain은 application을 import하지 않는다.

### D3. `useLimitAccounts` hook (`apps/companion/src/application/useLimitAccounts.ts`)

```ts
export type LimitAccountsState = {
	readonly accounts: LimitAccounts;
	readonly saveAccounts: (next: LimitAccounts) => Promise<void>;
};
export function useLimitAccounts(options: {
	readonly onError: (error: unknown) => void;
	readonly onStatus: (status: string) => void;
}): LimitAccountsState;
```

- `useCompanionSettings`의 구조를 그대로 따른다: mount 시 `isTauri()`일 때만 store를 열어 `readLimitAccounts`로 초기화, `cancelled` 가드, 실패는 `onError`.
- `saveAccounts(next)`: `isTauri()`가 아니면 `onStatus("Tauri runtime unavailable")`. optimistic `setAccounts(next)` → `enqueuePreferenceSave`로 `writeLimitAccounts` 직렬화 → 성공 시 `onStatus("Weekly limits updated")`, 실패 시 `shouldRestoreFailedAccountsUpdate(current, next)`가 참일 때만 이전 값으로 복원 후 `onError`.
- store 인스턴스는 `useRef<Promise<CompanionLimitStore>>`로 한 번만 열고 재사용한다(`useRepoNotes`의 `storePromiseRef`와 동일).

### D4. `WeeklyLimitGauge` (`apps/companion/src/ui/WeeklyLimitGauge.tsx`)

```ts
export type WeeklyLimitGaugeProps = {
	readonly accounts: LimitAccounts;
	readonly nowSeconds?: number; // 테스트 주입; 없으면 useCurrentEpochSeconds()
};
```

렌더링 구조(계정 0개면 `null`; 모든 percent는 `toFixed(3)`):

```html
<section class="limit-board" aria-label="Weekly limits">
  <h2 class="limit-caption">
    <span>WEEKLY LIMITS <span class="limit-count">3</span></span>
    <span class="limit-axis-range">9/15 – 9/29</span>   <!-- 축 범위 = 월 정보 -->
  </h2>
  <div class="limit-table">
    <div class="limit-axis-row" aria-hidden="true">
      <span class="limit-axis-gutter"></span>
      <div class="limit-axis">
        <span class="limit-axis-day" data-tier="2" style="left:1.396%"></span>      <!-- 반나절 미만 partial 셀 -->
        <span class="limit-axis-day" data-edge="start" data-tier="1" style="left:6.399%">16</span>
        …
        <span class="limit-axis-day" data-tier="0" data-today="true" style="left:49.256%">22</span>
        …
        <span class="limit-axis-now" style="left:50.000%"></span>   <!-- 지금 마커(▴) -->
      </div>
      <span class="limit-axis-gutter"></span>
    </div>
    <ul class="limit-list">
      <li class="limit-row" data-phase="mid"
          title="Resets 2026-09-24 15:00"
          aria-label="Account 1: 2d 0h until reset, Thu 15:00, 71% elapsed">
        <span class="limit-label" title="Account 1">Account 1</span>
        <svg class="limit-scale" aria-hidden="true" width="100%" height="24">
          <line class="limit-grid" x1="2.792%" x2="2.792%" y1="0" y2="24" />   <!-- 로컬 자정마다 -->
          …
          <rect class="limit-rest" x="50.000%" y="8" width="14.400%" height="8" />   <!-- 지금 → 다음 reset -->
          <rect class="limit-fill" x="14.400%" y="8" width="35.600%" height="8" />   <!-- 마지막 reset → 지금 -->
          <line class="limit-reset-mark" x1="14.400%" x2="14.400%" y1="5" y2="19" /> <!-- 마지막 reset -->
          <line class="limit-reset-mark" x1="64.400%" x2="64.400%" y1="5" y2="19" /> <!-- 다음 reset -->
          <line class="limit-now" x1="50.000%" x2="50.000%" y1="0" y2="24" />       <!-- 지금 -->
        </svg>
        <span class="limit-facts">
          <span class="limit-remaining">2d 0h</span>
          <span class="limit-sep" aria-hidden="true">·</span>
          <span class="limit-reset">Thu 15:00</span>
          <span class="limit-token">SOON</span>   <!-- phase가 fresh/soon일 때만 -->
        </span>
      </li>
    </ul>
  </div>
</section>
```

- 축 라벨 위치 = `(startRatio + endRatio) / 2`, `data-tier`는 **오늘 셀로부터의 거리** 기준 `0`(4의 배수, 오늘 포함)/`1`(짝수)/`2`(홀수)로 축 폭에 따라 솎는 단계 — 오늘을 항상 tier 0에 두어야 항상 보이는 오늘 라벨이 이웃과 겹치지 않는다(2026-09-22 시각 QA에서 절대 index 기준은 오늘 라벨 충돌로 실패). 오늘 셀은 `data-today="true"`.
- SVG는 `viewBox` 없이 `width="100%"`와 percent 좌표를 써서 폭에 따라 x만 늘어나고 stroke/높이는 고정된다. 행 사이 세로 여백 없이 SVG 높이(24px)로 리듬을 만들어 `.limit-now` 선이 행을 넘어 이어진다.
- SVG 안에 텍스트를 두지 않는다(10px 미만 글자 금지 규칙과 폭 제약 회피). 날짜 라벨·남은 시간·reset 시각은 HTML이 소유한다.
- 새 focusable 요소 없음(gauge는 비대화형). 스크린리더는 `li`의 `aria-label` 한 문장으로 계정/남은 시간/reset 시각/경과율을 읽는다. 축 헤더는 `aria-hidden`.
- `nowSeconds`가 없으면 `useCurrentEpochSeconds()`로 60초마다 재계산한다.

### D5. Settings `Weekly Limits` 섹션 (`apps/companion/src/ui/SettingsPanel.tsx`, `SettingsView.tsx`)

`SettingsPanel`/`SettingsView` props 추가: `accounts: LimitAccounts`, `onAccountsChange(next: LimitAccounts)`, 선택 `now?: () => Date`, `createId?: () => string`(기본 `() => new Date()`, `() => crypto.randomUUID()`). 기존 Theme 패널 아래에 `TerminalPanel anatomy="claude" label="Weekly Limits"`를 추가한다.

```html
<ul class="limit-settings-list">
  <li class="limit-settings-row">
    <input class="limit-settings-name" type="text" maxlength="40"
           aria-label="Account 1 label" placeholder="Account 1" value="…" />
    <input type="datetime-local" step="60" aria-label="Account 1 next reset" value="2026-09-24T15:00" />
    <button class="limit-settings-remove" aria-label="Remove Account 1">×</button>
  </li>
</ul>
<button class="limit-settings-add" disabled={accounts.length >= 12}>+ Add account</button>
<p class="settings-hint">Enter the next reset shown in /usage. After it passes, the next reset moves forward 7 days. Main shows each account's window on a shared two-week axis — it does not read actual usage. (3/12)</p>
```

- `datetime-local`의 `value`는 `formatDateTimeLocal(resolveNextReset(account.nextResetAt, now()))` — 저장된 anchor가 아니라 현재 window의 다음 reset을 보여준다.
- 모든 변경은 `onAccountsChange(next)`로 전체 배열을 올린다(label `onChange`, datetime `onChange`, remove click, add click). label은 controlled input이며 즉시 상태에 반영된다(save queue가 쓰기를 직렬화한다).
- datetime `onChange`: `parseDateTimeLocal(value)`가 `undefined`(빈 값·형식 오류)면 호출하지 않고 이전 값을 유지한다. 유효하면 `nextResetAt`에 그 epoch를 저장한다(정규화하지 않고 입력값 그대로).
- Add는 `newLimitAccount(accounts, now(), createId())`를 뒤에 붙인다. 12개면 disabled.
- 0개일 때 목록 대신 `No accounts yet` hint 한 줄.

### D6. CSS는 기존 token만 사용한다

`apps/companion/src/styles/limit-gauge.css`(신규, `style.css` 매니페스트에서 `stage-board.css` 다음에 import):

| selector | 스펙 |
|---|---|
| `.limit-board` | 배경 `--surface-1`, `border: 1px solid var(--line)`, radius 5px, `margin-bottom: 10px`, `padding: 0 10px 6px`, `min-width: 0`. `StageBoard`의 emphasis rail은 쓰지 않는다(보드가 지배적 surface). |
| `.limit-caption` | `--fs-label` 700, `letter-spacing: 0.04em`, 색 `--muted`, `padding: 8px 0 6px`, `border-bottom: 1px solid var(--line)`, `margin: 0 0 4px` |
| `.limit-count` | `--faint` 400, `tabular-nums` |
| `.limit-table` | `display: grid; grid-template-columns: minmax(64px, 96px) minmax(0, 1fr) auto; column-gap: 8px; min-width: 0` — column의 단일 소유자 |
| `.limit-axis-row`, `.limit-list`, `.limit-row` | `display: grid; grid-column: 1 / -1; grid-template-columns: subgrid; align-items: center; min-width: 0`. `.limit-list`는 `list-style: none; margin: 0; padding: 0`. `.limit-row`는 `padding: 0 2px`(세로 padding 없음 — `.limit-now` 연속) |
| `.limit-axis` | `position: relative; height: 16px; overflow: hidden; border-bottom: 1px solid var(--line); container-type: inline-size; font-size: var(--fs-label)` — 라벨 솎기의 size container |
| `.limit-axis-day` | `position: absolute; top: 0; transform: translateX(-50%); --fs-label; color: var(--faint); tabular-nums; white-space: nowrap`; `data-tier`는 오늘 셀로부터의 거리가 4의 배수면 `"0"`(오늘 포함), 짝수면 `"1"`, 홀수면 `"2"`; `[data-today="true"]` → `color: var(--emphasis); font-weight: 700`; 셀 중심이 축의 8% 미만/92% 초과면 `data-edge="start"/"end"`로 `transform: none` / `translateX(-100%)`(가장자리 라벨이 축 밖으로 잘리지 않게 안쪽으로 앵커) |
| `.limit-axis-now` | `position: absolute; bottom: 0; transform: translateX(-50%); width: 0; height: 0; border-left/right: 4px solid transparent; border-bottom: 4px solid var(--emphasis)`(▴ 마커) |
| `.limit-label` | `--fs-body` 600 `--text`, `min-width: 0`, ellipsis + `title` |
| `.limit-scale` | `display: block; width: 100%; height: 24px; overflow: visible; min-width: 0` |
| `.limit-grid` | `stroke: var(--line)`, `stroke-opacity: 0.7`, width 1 (`color-mix`는 macOS 13.0 WebKit 미지원 가능성이 있어 쓰지 않는다) |
| `.limit-rest` | `fill: var(--surface-3)` |
| `.limit-fill` | `fill: var(--emphasis-soft)`; `[data-phase="fresh"]` → `--done-soft`, `[data-phase="soon"]` → `--notify-soft` |
| `.limit-reset-mark` | `stroke: var(--line-strong)`, width 1; fresh → `--done`, soon → `--notify` |
| `.limit-now` | `stroke: var(--emphasis)`, width 1 |
| `.limit-facts` | `--fs-meta` `--muted`, `display: inline-flex; gap: 5px; align-items: center; justify-self: end; white-space: nowrap; tabular-nums` |
| `.limit-remaining` | `--text` 600 |
| `.limit-reset` | `--faint` |
| `.limit-token` | pill: `border-radius: 999px`, `--fs-label` 700, `padding: 0 6px`, `letter-spacing: 0.04em`; fresh → `--done-soft`/`--done`, soon → `--notify-soft`/`--notify` |
| `@media (max-width: 480px)` | `.limit-table` grid `minmax(48px, 64px) minmax(0, 1fr) auto` |
| `@container (max-width: 25.5em)` / `@container (max-width: 12.7em)` | 축 자체 폭(라벨 em 기준 — 11px에서 ≈280px/≈140px, 하루 ≈20px/≈10px)으로 라벨을 솎는다: 25.5em 이하면 `data-tier="2"`(홀수 셀) 숨김, 12.7em 이하면 `data-tier="1"`(4의 배수가 아닌 짝수 셀)도 숨김. 오늘은 항상 표시. 글자 크기가 커지면 em 기준이라 임계도 같이 커지므로 별도 `main[data-font-size]` 규칙이 필요 없다. (2026-09-22 시각 QA에서 520px에서도 facts 폭 때문에 축이 ≈180px라 viewport media query만으로는 라벨이 겹쳐 container query로 교체) |

`apps/companion/src/styles/settings.css` 추가:

| selector | 스펙 |
|---|---|
| `.limit-settings-list` | `list-style: none; margin: 0 0 8px; padding: 0; display: grid; gap: 6px; container-type: inline-size; font-size: var(--fs-ui)` — 행 접기의 size container |
| `.limit-settings-row` | grid `minmax(0, 1fr) auto 32px`, `gap: 6px`, `align-items: center` |
| `.limit-settings-row input[type="text"], .limit-settings-row input[type="datetime-local"]` | `chrome.css`의 select와 같은 외형: 배경 `--button-bg`, `border: 1px solid var(--line)`, radius 6px, `min-height: 32px`, `padding: 6px 10px`, 색 `--text`, `min-width: 0`, `color-scheme: dark`(WebKit 날짜 picker가 어두운 톤으로 뜨도록) |
| `.limit-settings-remove` | `min-width: 32px; padding: 4px`; hover 시 `--blocked` 테두리/글자(`.agent-control-quit`과 동일) |
| `.limit-settings-add` | `justify-self: start` |
| `.limit-settings-empty` | `--faint`, `--fs-meta`, `margin: 0 0 8px` |
| `@container (max-width: 30em)` | 목록 폭이 컨트롤 30em(medium 14px → 420px, extra-large → 546px) 이하면 `.limit-settings-row` grid `minmax(0, 1fr) 32px`; `datetime-local`은 `grid-column: 1; grid-row: 2`; remove는 `grid-row: 1 / 3`. 460px 팝오버와 큰 글자 모두 여기에 걸린다(2026-09-22 시각 QA: extra-large 520px에서 viewport media query만으로는 label input이 90px로 눌려 container query로 교체) |

motion.css는 건드리지 않는다(막대는 60초마다 위치가 바뀔 뿐 transition 없음).

## UI 가이드

```text
┌ .agent-header ─────────────────────────────────────────────┐
│ Workbranch Companion                               ↻  ⏻   │
│ 3 projects · 4 tasks                                        │
└─────────────────────────────────────────────────────────────┘
┌ .limit-board ──────────────────────────────────────────────┐
│ WEEKLY LIMITS 3                                9/15 – 9/29  │ ← 캡션 오른쪽 = 축 범위(월 정보)
│              16  17  18  19  20  21  22  23  24  25  26  27  28  29   │ ← 축 라벨(날짜 숫자, 오늘 22 강조, 반나절 미만 첫 셀은 빈 라벨)
│                                         ▴                   │
│ Account 1     ┃▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│░░░░░░░░░┃  2d 0h · Thu 15:00 SOON │ ← soon: notify
│ Account 2                 ┃▓▓▓▓▓▓▓▓▓▓│░░░░░░░░░░░░░░░░░░░░┃ 6d 20h · Wed 09:00 FRESH│ ← fresh: done
│ Account 3           ┃▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│░░░░░░░░░░░░░░┃  4d 9h · Sat 00:00      │ ← mid: emphasis
│               ↑ 마지막 reset             │            ↑ 다음 reset            │
│                                    지금(50%, 모든 행 관통)                    │
└─────────────────────────────────────────────────────────────┘
┌ .stage-board ──────────────────────────────────────────────┐
│ WORKTREE STATUS 2                                           │
│ 00 BASE ────────────────────────────────────────────────5   │
│ ...                                                         │
```

- 축: `now − 7d … now + 7d`. 격자선은 로컬 자정, 라벨은 셀 가운데의 날짜 숫자, 월 정보는 캡션의 축 범위(`9/15 – 9/29`), 오늘 라벨 emphasis + `▴` 마커.
- 막대: 항상 축의 50% 길이(7일). 왼쪽 끝 = 마지막 reset, 오른쪽 끝 = 다음 reset, 두 끝에 reset 마크. `▓` = 경과(phase 색), `░` = 남은 시간(`--surface-3`).
- facts: `남은 시간 · 요일 HH:MM [FRESH|SOON]`. 요일·시각은 정규화된 다음 reset.
- 축 폭이 좁아지면(container query, 라벨 em 기준) 날짜 라벨을 격일 → 4일 간격으로 솎는다(오늘은 항상 표시). 460px 이하에서는 라벨 column도 축소. facts는 유지.
- 10px 미만 글자 금지 규칙 유지. 라벨 `--fs-body`, facts `--fs-meta`, 축 라벨·pill `--fs-label`.
- 가로 overflow 금지: 계정 라벨 ellipsis + `title`, 축 라벨은 `.limit-axis`의 `overflow: hidden`으로 양 끝만 잘림, facts는 최대 `6d 23h · Wed 09:00 FRESH`. 각 행의 내부 폭, 헤더/행 column 정렬, 460px에서 축 폭(≥150px 목표)을 시각 QA로 확인한다.

Settings:

```text
┌ WEEKLY LIMITS ──────────────────────────────────────────┐
│ [Account 1        ] [2026-09-24 15:00      ] [×]         │
│ [Account 2        ] [2026-09-23 09:00      ] [×]         │
│ [+ Add account]                                          │
│ Enter the next reset shown in /usage. After it passes,   │
│ the next reset moves forward 7 days. Main shows each     │
│ account's window on a shared two-week axis — it does not │
│ read actual usage. (2/12)                                │
└──────────────────────────────────────────────────────────┘
```

## 범위 밖

- Claude/Codex 실제 사용량(토큰·%) 조회 및 표시(G3)
- 계정별 자(ruler) + 바늘 형태(G2 A안), 오늘 중심 달력 컬럼 축(G4 A안), 요일+시각 입력(G5 A안)·변환 보조 입력(G5 C안) — 모두 미채택
- reset 도래 시 anchor를 저장 파일에 자동 갱신(정규화는 읽을 때만)
- 5시간 session window gauge, 일 단위 초기화 등 weekly 이외 주기
- reset 도래 시 알림(notification), 메뉴바 아이콘 변화
- "다음 reset 순" 정렬, 계정 drag 정렬, 계정별 색상 선택
- 축 범위 변경(줌·스크롤), 패널 접기/펼치기(계정이 많아 높이가 부담되면 후속 plan), 460px에서 reset 시각 자동 숨김(QA 결과에 따라 후속)
- CLI, contract, Tauri command/Rust, activity log 변경
- 계정 목록의 기기 간 동기화

## 변경 파일 구조

```text
apps/companion/src/domain/limits.ts                 # addLocalDays, resolveNextReset, limitWindowAt, axisRatio, limitAxisDays, format*/parse*
apps/companion/src/application/limits.ts            # LimitAccount 모델, sanitize, newLimitAccount, store read/write
apps/companion/src/application/useLimitAccounts.ts  # hook: load/optimistic save/restore
apps/companion/src/ui/WeeklyLimitGauge.tsx          # Main 날짜축 + 계정 막대 패널
apps/companion/src/ui/SettingsPanel.tsx             # Weekly Limits 섹션
apps/companion/src/ui/SettingsView.tsx              # accounts props 통과
apps/companion/src/App.tsx                          # useLimitAccounts 배선, Main/Settings 연결
apps/companion/src/styles/limit-gauge.css           # 신규 gauge 스타일(subgrid)
apps/companion/src/styles/settings.css              # 계정 편집 행 스타일
apps/companion/src/style.css                        # limit-gauge.css import
apps/companion/tests/limits.test.ts                 # domain 계산 + 축 + sanitize/store 계약
apps/companion/tests/weekly-limit-gauge.test.tsx    # gauge 렌더링/aria/CSS 계약
apps/companion/tests/settings-panel.test.tsx        # 계정 추가/편집/삭제/12개 제한
apps/companion/tests/app-shell.test.tsx             # 배선·import 매니페스트 계약
apps/companion/README.md                            # Scope에 companion-limits.json
DESIGN.md                                           # IA/Components/토큰 소유/Direction history
README.md, README.ko.md                             # View with Companion 항목
```

---

### Task 1: domain window·시간축 계산 (red → green)

**Files:**
- Create: `apps/companion/tests/limits.test.ts`
- Create: `apps/companion/src/domain/limits.ts`

- [x] **Step 1: failing test 작성** — 테스트 파일 상단에서 `process.env["TZ"] = "Asia/Seoul"`을 고정한다(`.ts` 테스트는 typecheck 대상이라 `noPropertyAccessFromIndexSignature` 때문에 대괄호 접근). 고정 `now = 2026-09-22T14:37:00+09:00`(화).
  - `addLocalDays`: `+7`/`−7`이 wall-clock을 유지하고, `America/New_York`에서 2026-03-08(봄 전환)을 가로지르면 epoch 차이가 `7 * 86400 − 3600`, 2026-11-01(가을 전환)이면 `+3600`임을 확인한 뒤 TZ를 되돌린다.
  - `resolveNextReset`: (a) anchor 9/24 15:00(미래 2일) → 그대로, (b) anchor 9/17 15:00(지난주) → 9/24 15:00, (c) anchor 2026-06-04 15:00(수 개월 전, 목) → 9/24 15:00, (d) anchor 10/8 15:00(16일 뒤) → 9/24 15:00(뒤로 롤), (e) anchor == now → now + 7일, (f) anchor = now + 7일 정확히 → 그대로(경계 `<=`).
  - `limitWindowAt`: 경과 0%/50%/100% 직전의 `elapsedRatio`·`remainingSeconds`, phase 경계(경과 23h59m59s → fresh, 24h → mid, 남은 24h → mid, 23h59m59s → soon), `startAt == addLocalDays(endAt, −7)`.
  - `axisRatio`: `now`는 `0.5`, `now − 7d`는 `0`, `now + 7d`는 `1`, 축 밖은 clamp. anchor 9/24 15:00 → `axisRatio(endAt) ≈ 0.644`(소수 3자리), `axisRatio(startAt) ≈ 0.144`.
  - `limitAxisDays`: 같은 `now`에서 셀 15개(9/15 partial 9.4h < 반나절 → label `""`, 9/16…9/28 → `"16"`…`"28"`, 9/29 partial 14.6h → `"29"`), `today`는 `"22"` 셀 하나, 셀이 빈틈없이 이어지고(`startRatio === 이전 endRatio`) 첫 셀 0·마지막 셀 1. `now = 2026-09-22T05:00+09:00`이면 첫 셀(19h)은 `"15"`, 마지막 셀(5h)은 `label: ""`. `now = 2026-09-28`이면 라벨이 `…,29,30,1,2,…`로 이어지고 첫 라벨 `"22"`. `America/New_York`에서 2026-11-01을 포함하면 해당 셀(`"1"`) 폭이 `25h / 336h`. `formatMonthDay(now ∓ 7d)` → `"9/15"`/`"9/29"`.
  - `formatRemaining`: `3d 4h`, `4h 12m`, `12m`, `<1m`, 정확히 `1d 0h`. `formatResetPoint(9/24 15:00) === "Thu 15:00"`, `formatResetDate(...) === "2026-09-24 15:00"`, `formatDateTimeLocal(...) === "2026-09-24T15:00"`. `parseDateTimeLocal("2026-09-24T15:00")`은 같은 epoch, `"2026-09-24T15:00:30"`은 초 버림, `""`/`"2026-13-01T00:00"`/`"abc"`는 `undefined`.
- [x] **Step 2: red 확인** — `pnpm --filter @workbranch/companion test tests/limits.test.ts`가 import 실패로 빨간 상태임을 확인한다.
- [x] **Step 3: 구현** — D2대로 `src/domain/limits.ts`를 작성한다. 로컬 달력 API만 사용하고 epoch 덧셈으로 주를 옮기지 않는다. 축 셀 경계는 `new Date(y, m, d)`로 로컬 자정을 얻는다. `resolveNextReset`은 주 단위 점프 후 ±1주 보정 루프로 구현해 anchor가 수년 떨어져도 상수 시간에 끝난다.
- [x] **Step 4: green + lint/typecheck** — 해당 테스트, `typecheck`, `lint`를 통과시킨다. (2026-09-22: 20/20 PASS, tsc PASS, biome 오류 0·info 8)

### Task 2: 계정 모델·sanitize·store (red → green)

**Files:**
- Modify: `apps/companion/tests/limits.test.ts`
- Create: `apps/companion/src/application/limits.ts`

- [x] **Step 1: failing test 작성** — `sanitizeLimitAccounts`: 비배열 → `[]`; id 없음/`nextResetAt`이 문자열·`NaN`·`0`·소수 항목 제거; label 비문자열 → `""`; 41자 → 40자 trim; 중복 id 첫 항목 유지; 13개 → 12개. `newLimitAccount([], new Date("2026-09-22T14:37:00+09:00"), () => "id-1")` → `{ id: "id-1", label: "Account 1", nextResetAt: epoch(2026-09-29T14:00+09:00) }`. `limitAccountDisplayLabel({ label: "" }, 2) === "Account 3"`. `readLimitAccounts`/`writeLimitAccounts`: `notes.test.ts`처럼 `vi.mock("@tauri-apps/plugin-store")`로 `get/set/save` 호출 순서와 key `accounts`를 검증한다. `shouldRestoreFailedAccountsUpdate`는 참조 동일성.
- [x] **Step 2: red 확인**.
- [x] **Step 3: 구현** — D1대로 작성한다. `loadCompanionLimitStore`는 `notes.ts`와 동일한 `load(file, { autoSave: false, defaults: {} })`.
- [x] **Step 4: green + lint/typecheck**. (2026-09-22: `tests/limits.test.ts` 32/32 PASS, tsc PASS, biome 오류 0)

### Task 3: `useLimitAccounts` hook + App 배선 (red → green)

**Files:**
- Modify: `apps/companion/tests/app-shell.test.tsx`
- Create: `apps/companion/src/application/useLimitAccounts.ts`
- Modify: `apps/companion/src/App.tsx`

- [x] **Step 1: failing test 작성** — `app-shell.test.tsx`의 source-contract 방식으로 `App.tsx`가 `useLimitAccounts`를 호출하고, `<WeeklyLimitGauge`가 `<StageBoard` 보다 앞에 있으며(`indexOf` 비교), `accounts.length > 0` 조건으로 감싸고, `SettingsView`에 `accounts=`/`onAccountsChange=`를 넘기는지 검증한다. `style.css`가 `./styles/limit-gauge.css`를 import하는지도 검증한다.
- [x] **Step 2: red 확인**.
- [x] **Step 3: 구현** — D3대로 hook을 작성하고 `App.tsx`에서 `const { accounts, saveAccounts } = useLimitAccounts({ onError: showError, onStatus: showStatus })`를 추가한다. Main `view-panel` 첫 자식으로 `{accounts.length > 0 ? <WeeklyLimitGauge accounts={accounts} /> : null}`, Settings에 props 전달. (Task 4/5를 먼저 끝냈으므로 stub 없이 배선했다.)
- [x] **Step 4: green + lint/typecheck**. (2026-09-22: 전체 suite 17 files / 242 tests PASS, tsc PASS, biome 오류 0·info 94)

### Task 4: `WeeklyLimitGauge` + CSS (red → green)

**Files:**
- Create: `apps/companion/tests/weekly-limit-gauge.test.tsx`
- Create: `apps/companion/src/ui/WeeklyLimitGauge.tsx`
- Create: `apps/companion/src/styles/limit-gauge.css`
- Modify: `apps/companion/src/style.css`

- [ ] **Step 1: failing test 작성** — `process.env.TZ = "Asia/Seoul"`, `renderToStaticMarkup(<WeeklyLimitGauge accounts={…} nowSeconds={fixed} />)`로:
  - (a) 0개 → 빈 문자열, (b) 3개 → `aria-label="Weekly limits"`, `WEEKLY LIMITS`, `.limit-count` 3, `li` 3개 등록 순서.
  - (c) 캡션 오른쪽 `.limit-axis-range`가 `9/15 – 9/29`. 축 헤더: `aria-hidden="true"`, 셀 15개(첫 셀 빈 라벨, `16`…`29`), `data-today="true"`가 `22` 하나이며 tier 0, `data-tier` 분포 0/1/2 = 3/4/8(오늘 index 7 기준 3·7·11이 tier 0), `.limit-axis-now`가 `left:50.000%`.
  - (d) anchor 9/24 15:00 계정: `.limit-fill x="14.400%" width="35.600%"`, `.limit-rest x="50.000%" width="14.400%"`, `.limit-reset-mark` 2개(`14.400%`, `64.400%`), `.limit-now x1="50.000%"`, `.limit-grid` 14개(로컬 자정 수). anchor가 지난주 값(9/17 15:00)이어도 같은 좌표(정규화).
  - (e) fresh/soon/mid의 `data-phase`와 token 유무, (f) facts가 `2d 0h`, `·`, `Thu 15:00` 순서이고 `aria-label`이 `"<label>: 2d 0h until reset, Thu 15:00, 71% elapsed"` 형식이며 행 `title`이 `Resets 2026-09-24 15:00`, (g) 빈 label은 `Account N`, 긴 label은 `title`에 전체 값, (h) SVG `aria-hidden="true"`이며 `<text>` 없음.
  - CSS 계약: `limit-gauge.css`에 표 D6의 selector, `.limit-table`의 `grid-template-columns: minmax(64px, 96px) minmax(0, 1fr) auto`, `.limit-axis-row`/`.limit-list`/`.limit-row`의 `grid-template-columns: subgrid`, `.limit-axis`의 `container-type: inline-size`, `@media (max-width: 480px)` 블록의 라벨 column 축소, `@container (max-width: 25.5em)`/`(12.7em)` 블록의 `data-tier` 숨김, `main[data-font-size=…]` 규칙 없음, `var(--` 참조가 `themes.css`/`base.css`에 정의된 token만 사용(`activity-calendar.test.tsx`의 token 검사 방식 재사용).
- [x] **Step 2: red 확인**.
- [x] **Step 3: 구현** — D4/D6대로 컴포넌트와 CSS를 작성하고 `style.css`에 import를 추가한다. percent 좌표는 `toFixed(3)`.
- [x] **Step 4: green + lint/typecheck**. (2026-09-22: `tests/weekly-limit-gauge.test.tsx` 10/10 PASS, tsc PASS, biome 오류·경고 0)

> 실행 순서 메모(2026-09-22, auto 모드): Task 3의 stub을 만들지 않기 위해 Task 4 → Task 5 → Task 3 순서로 진행한다. 각 Task의 red → green 경계는 그대로 유지한다.

### Task 5: Settings `Weekly Limits` 섹션 (red → green)

**Files:**
- Modify: `apps/companion/tests/settings-panel.test.tsx`
- Modify: `apps/companion/src/ui/SettingsPanel.tsx`, `apps/companion/src/ui/SettingsView.tsx`
- Modify: `apps/companion/src/styles/settings.css`

- [x] **Step 1: failing test 작성** — 기존 `collectByType` helper(`input` 수집)로: (a) 0개 → `No accounts yet` hint + Add 버튼, (b) Add 클릭 → `onAccountsChange([newLimitAccount(...)])`(주입한 `now`/`createId`로 결정적), (c) label input `onChange("Work")` → 해당 항목만 갱신된 배열, (d) datetime input의 `value`가 anchor가 지난주 값이어도 정규화된 `"2026-09-24T15:00"`, (e) datetime `onChange("2026-09-30T09:30")` → `nextResetAt: epoch(로컬 9/30 09:30)`, 빈 값/`"abc"` → 호출 없음, (f) Remove 클릭 → 해당 id 제거, (g) 12개면 Add `disabled`, (h) `(3/12)` 카운터 hint, (i) `renderToStaticMarkup`에 `aria-label="Account 2 next reset"`, `type="datetime-local"`, `step="60"` 등 접근성 이름·속성. `SettingsView`가 props를 그대로 통과시키는지 source-contract로 확인한다. CSS 계약: `settings.css`에 `.limit-settings-row` grid `minmax(0, 1fr) auto 32px`와 480px 블록. 기존 "exactly two agent themes" 테스트의 `<button` 수는 Add 버튼 때문에 2 → 3으로 갱신.
- [x] **Step 2: red 확인**.
- [x] **Step 3: 구현** — D5/D6대로 작성한다. 기존 Startup/Font/Text Size/Theme 섹션과 `TerminalPanel` anatomy를 동일하게 유지한다. 계정 행은 `collectByType`가 순회할 수 있도록 별도 컴포넌트가 아니라 함수 호출(`limitAccountRows`)로 inline 렌더링한다.
- [x] **Step 4: green + lint/typecheck**. (2026-09-22: `tests/settings-panel.test.tsx` 17/17 PASS, biome 오류·경고 0; tsc는 App 배선(Task 3) 전까지 `SettingsView` props 누락으로 실패 — Task 3에서 해소)

### Task 6: 문서 동기화와 전체 검증

**Files:**
- Modify: `DESIGN.md`, `README.md`, `README.ko.md`, `apps/companion/README.md`

- [x] **Step 1: DESIGN.md** — Information architecture 3(Main 첫 요소로 optional `WEEKLY LIMITS` 패널: 공용 2주 날짜축 + 계정별 window 막대 + 지금 선 + 남은 시간·reset 시각)·5(Settings에 weekly limit 계정 편집: 라벨 + 다음 reset `datetime-local`) 갱신, Components에 `WeeklyLimitGauge`/계정 편집 행 추가, Token/component ownership에 `limit-gauge.css` 추가, Interaction states에 계정 편집(즉시 저장, 실패 복원, 빈 label 대체, 잘못된 날짜 무시, anchor 정규화 표시) 추가, Non-goals에 사용량 API 미연동 명시, Implementation constraints에 `subgrid`·container query(macOS 13 WebKit) 사용 기록, Direction revision에 `2026-09-22 (weekly limit gauge)` 기록.
- [x] **Step 2: README** — "View with Companion"의 Main/Settings bullet(EN 214·217행, KO 대응 행)에 weekly limit gauge와 계정 설정을 한 구절씩 추가. `apps/companion/README.md` Scope에 `companion-limits.json`을 frontend-owned 로컬 상태로 추가.
- [x] **Step 3: quality gates** — 아래를 모두 통과시킨다. Tauri build는 background로 실행한다. (2026-09-22: test 17 files / 243 PASS, typecheck PASS, lint 오류 0·info 95, Vite build PASS, Tauri release bundle PASS `src-tauri/target/release/bundle/macos/WorkbranchCompanion.app`, `git diff --check` PASS)

```bash
pnpm --filter @workbranch/companion test
pnpm --filter @workbranch/companion typecheck
pnpm --filter @workbranch/companion lint
pnpm --filter @workbranch/companion build
pnpm companion:build
git diff --check
```

- [x] **Step 4: deterministic Chrome visual QA** — production `AgentHeader` + `WeeklyLimitGauge` + `StageBoard`, 그리고 `SettingsPanel`을 `renderToStaticMarkup`으로 뽑아 `style.css` 전체를 인라인한 harness HTML을 만들고 Claude/Codex × 520/460 × medium/extra-large × {3, 12 계정} × {fresh, mid, soon, 40자 label, 월 경계 축} capture를 저장한다. 확인 항목: 헤더 축 라벨의 x와 각 행 `.limit-grid`/`.limit-now`의 x가 일치(subgrid 정렬, `getBoundingClientRect` 비교), 막대 길이가 축의 50%, 지금 선이 행 사이에서 끊기지 않음, phase 색, 축 라벨 겹침 없음, 각 `li`와 facts의 내부 폭(`scrollWidth <= clientWidth`), Settings 행이 좁은 폭·큰 글자에서 2행으로 접히고 `datetime-local`이 잘리지 않음. 문서 폭 검사만으로 통과시키지 않는다.
  - 2026-09-22 결과: 14 capture(Main 10 + Settings 4) 전부 geometry PASS(`scratchpad/qa/report.mjs`). 이 머신의 headless Chrome은 500px 미만 창을 열지 못해 460px 변형은 `main{width:460px}` + `@media (max-width: 480px)` 강제 적용으로 렌더링했다(container query는 실제 요소 폭에 반응). 축 폭: 520px medium 182px, 460px medium 154px, 520px XL 137px, 460px XL 109px(≥150px 목표는 XL에서 미달 — 라벨 4일 간격 솎기로 겹침 없이 읽히므로 후속 조정 불필요로 판단). QA 중 세 가지를 고쳤다: (1) 절대 index 기준 라벨 솎기가 오늘 라벨과 충돌 → 오늘 기준 거리 tier, (2) viewport media query만으로는 520px에서도 라벨 겹침 → 축 폭 container query, (3) 첫 라벨 셀의 `M/D`가 가장자리에서 잘리거나 이웃과 겹침 → 날짜 숫자만 쓰고 캡션에 축 범위 표시 + 가장자리 셀 안쪽 앵커. 임시 harness(`tests/qa-harness.test.tsx`)는 캡처 후 삭제했다.
- [ ] **Step 5: 실제 앱 확인(사용자)** — 사용자가 Companion을 재빌드·실행해 Settings에서 계정 2개 이상을 `/usage` 날짜로 등록하고, Main 상단 축·막대·남은 시간·reset 요일 시각이 맞는지, 앱 재시작 후 계정이 복원되는지(`~/Library/Application Support/<bundle>/companion-limits.json`), 계정을 모두 지우면 패널이 사라지는지 확인한다.

## 완료 기준

- [x] Settings에서 계정을 최대 12개까지 추가/편집(label, 다음 reset 날짜·시각)/삭제할 수 있고, 값은 `companion-limits.json`에 `{ id, label, nextResetAt }`로 저장돼 재시작 후 복원된다(store read/write는 단위 테스트, 실제 앱 재시작 복원은 Task 6 Step 5 사용자 확인). `datetime-local`은 저장된 anchor가 과거여도 정규화된 다음 reset을 보여주고, 잘못된 입력은 무시된다. 저장 실패 시 이전 값으로 복원되고 오류가 표시된다.
- [x] 계정이 1개 이상이면 Main view 헤더 아래·`StageBoard` 위에 `WEEKLY LIMITS N` 패널이 나타난다. 헤더 축은 `now − 7d … now + 7d`를 로컬 자정 셀로 나눠 날짜 숫자를 표시하고(월 정보는 캡션의 축 범위) 오늘을 강조한다. 계정마다 등록 순서로 라벨·window 막대(마지막 reset → 다음 reset, 항상 축의 50%)·경과 채움·reset 마크·`남은 시간 · 요일 HH:MM`이 보이고, 지금 선(50%)이 모든 행을 끊김 없이 관통한다. 경과 24h 미만은 `FRESH`(done 색), 남은 24h 미만은 `SOON`(notify 색), 그 외는 token 없이 emphasis 색이다. 계정이 0개면 패널이 없다.
- [x] reset window는 anchor를 로컬 달력 7일 단위로 앞뒤 정규화해 계산되고, DST 전환 주에도 wall-clock `HH:MM`이 유지되며, 정확히 reset 시각에는 막대가 지금 선에서 시작한다(경과 0%). 축 격자는 로컬 자정을 따르며 DST 전환일 셀은 23h/25h 폭이다. 표시는 60초마다 갱신되며 애니메이션 루프가 없다.
- [x] 스크린리더는 각 행을 `"<label>: <remaining> until reset, <Day HH:MM>, <N>% elapsed"` 한 문장으로 읽고, 축 헤더는 숨겨지며, Settings 컨트롤은 모두 `Account N …` 접근성 이름을 가진다. gauge에 새 focusable 요소가 없다.
- [x] 520px/460px, Claude/Codex, medium/extra-large 모두에서 헤더 축과 행 막대의 column이 정렬되고, gauge 행과 Settings 행에 가로 overflow가 없으며, 축 라벨이 겹치지 않고, 40자 label은 ellipsis + `title`로 처리된다.
- [x] CLI/contract/Tauri Rust 변경 없음. Companion full tests/typecheck/lint/Vite build/Tauri build, `git diff --check`가 전부 통과한다.

## 실행 결과 (2026-09-22)

- Task 1–5 및 Task 6 Step 1–4를 `kickoff auto` 모드로 완료했다. 각 Task는 failing test → red 확인 → 구현 → green → typecheck/lint 순서를 지켰고, Task 3의 stub을 피하려고 Task 4 → 5 → 3 순서로 실행했다. Task 6 Step 5(실제 앱에서 계정 등록·재시작 복원)는 사용자 확인 항목으로 남긴다. 커밋·푸시·사용자 registry 변경 없음.
- 검증: Companion 17 files / 243 tests PASS(기존 189 + 신규 54: `limits.test.ts` 32, `weekly-limit-gauge.test.tsx` 11, `settings-panel.test.tsx` +10, `app-shell.test.tsx` +1), `tsc --noEmit` PASS, biome 오류·경고 0(info 95, 기존 75 + `process.env["TZ"]` 대괄호·template literal 권고), Vite build PASS, Tauri release bundle PASS, `git diff --check` PASS.
- 시각 QA: production 컴포넌트를 `renderToStaticMarkup`으로 뽑은 14 capture(Claude/Codex × 520/460 × medium/extra-large × 3/12 계정, Settings 4)에서 subgrid 정렬·막대 50%·지금 선 연속·overflow·라벨 겹침·datetime 잘림 검사 전부 PASS. QA 중 라벨 솎기(오늘 기준 tier + container query), 첫 라벨 셀 `M/D` 폐기 + 캡션 축 범위, 가장자리 라벨 안쪽 앵커, Settings 행 접기 container query를 보완했고 plan D2/D4/D6에 반영했다.
- 남은 리스크: 축 폭이 좁아(520px에서 ≈180px, extra-large 460px에서 ≈110px) 막대가 작게 보인다 — G6(행에 reset 시각 표시) 선택의 대가이며 라벨은 겹치지 않는다. 사용자가 실제로 좁다고 느끼면 후속으로 460px에서 reset 시각 숨김 또는 facts 축약을 검토한다. `datetime-local` 네이티브 picker의 모양은 WebKit(Tauri)에서 Chrome 캡처와 다를 수 있으므로 Step 5에서 확인한다.
