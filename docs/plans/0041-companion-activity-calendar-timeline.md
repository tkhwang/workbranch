# 0041 Companion Activity 캘린더 타임라인 (daily / 3-day)

> **agentic worker 지침:** 실행 시 `superpowers:subagent-driven-development`(권장) 또는 `superpowers:executing-plans`를 사용한다. 동작 변경 전에는 `superpowers:test-driven-development`(red → green → refactor)를 따른다. 이 plan은 **Companion(Tauri/React) 전용**이다 — CLI, brief 포맷, `list --json` 계약, `activity.jsonl` 쓰기 경로(0028~0030)는 변경하지 않는다. 검증은 `apps/companion`에서 `pnpm test` + `pnpm typecheck` + `pnpm lint`, `apps/companion/src-tauri`에서 `cargo test`로 한다. Step은 checkbox(`- [ ]`)로 추적한다.
>
> **시리즈 위치:** 0032(Tauri/React 재작성)에서 Activity 뷰는 placeholder로 남았다(`App.tsx` "Activity reporting will land in a future companion slice"). 0028~0030이 Swift 시절 만든 activity 데이터 모델(activity.jsonl, 세션화 idle gap 25분/lead pad 5분)은 Tauri 재작성에서도 쓰기 경로(`activity.ts` + `activity_store.rs`)로 이식되어 계속 쌓이고 있다. 0041은 이 데이터를 **처음으로 읽어서** 캘린더 타임라인으로 표시하는 slice다.

**목표:** Activity 뷰를 placeholder에서 캘린더 타임라인으로 교체한다. 사용자가 daily/3-day 아이콘 토글과 날짜 네비게이션으로 "언제 어떤 task를 얼마나 했는지"를 세로 시간축 위의 색 블록으로 읽을 수 있다.

**아키텍처:** 기존 runtime 경계 유지 — Rust는 얇은 IO(`read_activity_events` 범위 필터), Activity Calendar feature folder(`src/activity/`)는 narrowing·세션화·lane 배치·시간축 계산 순수 TS와 React 표현 컴포넌트를 함께 소유한다. 세션화 상수는 `application/activity.ts`의 IDLE_GAP(25분)/LEAD_PAD(5분)를 재사용한다.

**Tech Stack:** Tauri 2 (Rust command), React 18, vitest(`renderToStaticMarkup` 패턴), biome, CSS 토큰(`styles/themes.css`).

## Global Constraints

- monorepo: pnpm workspace. Companion 명령은 `apps/companion`에서 실행한다.
- TS/TSX는 탭 들여쓰기 + biome (`pnpm lint`). 기존 파일 스타일(readonly type, 순수 함수, 의존성 주입)을 따른다.
- UI 의존성 추가 금지(달력/시간 라이브러리 금지 — `Date` 직접 사용). 새 crate 추가 금지.
- popover는 420px 폭 기준. DESIGN.md: terminal-native HUD — 파스텔 카드·글로시 스타일 금지, 기존 테마 토큰만 사용.
- `activity.jsonl` 스키마·쓰기 경로 불변. 읽기 command만 additive로 추가한다.
- 커밋은 Conventional Commits (`feat(companion): …`), 이모지 prefix 금지.

## 결정 사항 (사용자 확정)

1. **뷰 모드는 daily / 3-day만.** weekly는 이후 slice로 확장한다(토글은 모드 배열 기반으로 두어 추가가 국소 변경이 되게 한다).
2. **블록 색상·상단 chips = 프로젝트별.** 프로젝트명 해시 → 고정 팔레트 인덱스. chips 클릭으로 프로젝트 필터.
3. **범위는 캘린더 타임라인만.** 시간 합계/통계 리스트는 다음 slice(기존 `buildPlanReport` 활용 예정).
4. 이벤트는 불연속 관측이므로 **블록 = 세션**: 같은 task의 연속 이벤트를 idle gap 25분 기준으로 병합, 시작은 첫 이벤트 −5분, 단일 이벤트 블록은 최소 5분 길이 보장.
5. **Activity Calendar 신규 파일 배치 = feature folder.** 신규 TS/CSS 구현은 `apps/companion/src/activity/` 아래에 묶고, 테스트는 `apps/companion/tests/activity-calendar.test.tsx` 중심으로 둔다. 기존 `application/activity.ts`는 쓰기/리포트 상수 owner로 유지하고, 새 `activity/calendar.ts`는 읽기용 narrowing·calendar session 도메인을 소유한다.

## 구현 전 plan 보강 사항

- `tauriClient.readActivityEvents`는 `apps/companion/tests/activity-calendar.test.tsx`의 domain narrowing 테스트뿐 아니라 `apps/companion/tests/tauri-client.test.ts`에서 `invoke("read_activity_events", { fromEpoch, toEpoch })`와 lenient filtering을 별도 검증한다.
- Rust 테스트용 `tempdir_like()`는 새 crate 없이 구현하되, 병렬 `cargo test`에서 충돌하지 않도록 `std::process::id()` + `AtomicU64` counter 또는 test-name suffix로 테스트별 하위 폴더를 만든다.
- TS/TSX 예제와 구현은 non-null assertion(`!`)을 쓰지 않는다. 테스트에서는 `expect(value).toBeDefined()` 후 guard하고, 해시는 `char.charCodeAt(0)` 같은 total API를 쓴다.

## public contract (변경 / 비변경)

### 변경하지 않는 것
- `~/.local/state/workbranch/activity.jsonl` 스키마(v1)와 append 로직(`append_activity_events`).
- `workbranch list --json`, brief 포맷, CLI 명령.
- `ViewNav`의 3개 뷰 구조(Main/Activity/Settings).

### 추가하는 것 (additive)
- Rust command `read_activity_events { fromEpoch, toEpoch }` → 범위 내 이벤트 JSON 배열. 구버전 라인(plan 필드 없음)·깨진 라인에 관대해야 하므로 Rust는 `serde_json::Value`로 라인 파싱만 하고 스키마 검증은 TS가 한다.
- Activity Calendar feature module `src/activity/calendar.ts` (아래 Interfaces) + `src/activity/ActivityCalendarView.tsx` + `src/activity/activity-calendar.css`.
- 테마 토큰 `--cal-1`~`--cal-6` (프로젝트 팔레트, 두 테마 모두).

## 파일 구조 (touched)

```text
apps/companion/src-tauri/src/activity_store.rs   # read_activity_events_in_range + 단위 테스트
apps/companion/src-tauri/src/lib.rs              # #[tauri::command] read_activity_events 등록
apps/companion/src/infrastructure/tauriClient.ts # readActivityEvents 바인딩 + lenient narrowing
apps/companion/src/activity/calendar.ts          # NEW: narrowing + 세션화·lane·시간축·날짜 계산 (feature-local pure module)
apps/companion/src/activity/ActivityCalendarView.tsx  # NEW: 헤더(날짜 네비+모드 토글+chips) + 타임라인
apps/companion/src/App.tsx                       # placeholder → ActivityCalendarView 교체
apps/companion/src/style.css                     # @import "./activity/activity-calendar.css"
apps/companion/src/activity/activity-calendar.css  # NEW: 타임라인 레이아웃
apps/companion/src/styles/themes.css             # --cal-1..6 팔레트 (양 테마)
apps/companion/tests/activity-calendar.test.tsx  # NEW: narrowing/domain/view 테스트
```

---

### Task 1: Rust `read_activity_events` command

**Files:**
- Modify: `apps/companion/src-tauri/src/activity_store.rs`
- Modify: `apps/companion/src-tauri/src/lib.rs` (command + `generate_handler!` 등록)

**Interfaces:**
- Produces (Rust): `pub(crate) fn read_activity_events_in_range(path: &Path, from_epoch: u64, to_epoch: u64) -> Result<Vec<serde_json::Value>, CompanionError>` 및 `pub(crate) fn read_activity_events_default(from_epoch: u64, to_epoch: u64) -> ...` (기존 `activity_log_path(None)` 재사용).
- Produces (IPC): `invoke("read_activity_events", { fromEpoch, toEpoch })` → `unknown[]` (Task 2가 소비).

- [x] **Step 1: 실패하는 Rust 테스트 작성** — `activity_store.rs` 하단 `#[cfg(test)] mod tests`:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write as _;

    fn write_lines(dir: &std::path::Path, lines: &[&str]) -> PathBuf {
        let path = dir.join("activity.jsonl");
        let mut file = std::fs::File::create(&path).unwrap();
        for line in lines {
            writeln!(file, "{line}").unwrap();
        }
        path
    }

    #[test]
    fn reads_events_within_range_inclusive() {
        let dir = tempdir_like(); // std::env::temp_dir() + unique suffix, 아래 참고
        let path = write_lines(
            &dir,
            &[
                r#"{"v":1,"observedAt":100,"project":"a","task":"t1"}"#,
                r#"{"v":1,"observedAt":200,"project":"a","task":"t1"}"#,
                r#"{"v":1,"observedAt":300,"project":"a","task":"t1"}"#,
            ],
        );
        let events = read_activity_events_in_range(&path, 150, 300).unwrap();
        assert_eq!(events.len(), 2);
        assert_eq!(events[0]["observedAt"], 200);
    }

    #[test]
    fn skips_unparseable_and_legacy_lines_without_observed_at() {
        let dir = tempdir_like();
        let path = write_lines(
            &dir,
            &[
                "not json at all",
                r#"{"v":1,"project":"a","task":"t"}"#,
                r#"{"v":1,"observedAt":100,"project":"a","task":"t","plan":"P","planIndex":0}"#,
            ],
        );
        let events = read_activity_events_in_range(&path, 0, 1_000).unwrap();
        assert_eq!(events.len(), 1);
    }

    #[test]
    fn missing_file_returns_empty() {
        let dir = tempdir_like();
        let events =
            read_activity_events_in_range(&dir.join("absent.jsonl"), 0, 10).unwrap();
        assert!(events.is_empty());
    }
}
```

`tempdir_like()`는 새 crate 금지 제약 때문에 `std::env::temp_dir()` + `std::process::id()` + `static AtomicU64` counter로 테스트별 하위 폴더를 만든다(병렬 `cargo test` 충돌 방지). 예: `wb-activity-test-{pid}-{counter}`를 `fs::create_dir_all`로 만들고 각 테스트가 독립 `activity.jsonl`을 쓴다.

- [x] **Step 2: 테스트 실패 확인** — Run: `cd apps/companion/src-tauri && cargo test read_activity`
  Expected: FAIL (`read_activity_events_in_range` not found — compile error)

- [x] **Step 3: 최소 구현** — `activity_store.rs`:

```rust
use std::io::{BufRead, BufReader};

pub(crate) fn read_activity_events_default(
    from_epoch: u64,
    to_epoch: u64,
) -> Result<Vec<serde_json::Value>, CompanionError> {
    let path = activity_log_path(None)?;
    read_activity_events_in_range(&path, from_epoch, to_epoch)
}

pub(crate) fn read_activity_events_in_range(
    path: &Path,
    from_epoch: u64,
    to_epoch: u64,
) -> Result<Vec<serde_json::Value>, CompanionError> {
    let file = match std::fs::File::open(path) {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(Vec::new());
        }
        Err(error) => return Err(error.into()),
    };
    let mut events = Vec::new();
    for line in BufReader::new(file).lines() {
        let line = line?;
        let Ok(value) = serde_json::from_str::<serde_json::Value>(&line) else {
            continue;
        };
        let Some(observed_at) = value.get("observedAt").and_then(serde_json::Value::as_u64)
        else {
            continue;
        };
        if observed_at >= from_epoch && observed_at <= to_epoch {
            events.push(value);
        }
    }
    Ok(events)
}
```

`lib.rs`에 command 추가 및 `generate_handler!` 목록의 `append_activity_events` 뒤에 등록:

```rust
#[tauri::command]
async fn read_activity_events(
    from_epoch: u64,
    to_epoch: u64,
) -> Result<Vec<serde_json::Value>, CompanionError> {
    tauri::async_runtime::spawn_blocking(move || {
        activity_store::read_activity_events_default(from_epoch, to_epoch)
    })
    .await
    .map_err(|error| std::io::Error::other(error.to_string()))?
}
```

(Tauri 2는 snake_case 인자를 JS의 camelCase `{ fromEpoch, toEpoch }`로 매핑한다.)

- [x] **Step 4: 테스트 통과 확인** — Run: `cd apps/companion/src-tauri && cargo test`
  Expected: 신규 3개 포함 전체 PASS
- [ ] **Step 5: 커밋** — safety gate로 자동 실행 보류: `git add apps/companion/src-tauri && git commit -m "feat(companion): add read_activity_events tauri command"`

---

### Task 2: `tauriClient.readActivityEvents` + lenient narrowing

**Files:**
- Modify: `apps/companion/src/infrastructure/tauriClient.ts`
- Test: `apps/companion/tests/activity-calendar.test.tsx` (narrowing 함수는 feature-local pure module에 두고 여기서 테스트)
- Test: `apps/companion/tests/tauri-client.test.ts` (`readActivityEvents` IPC 바인딩과 filtering 검증)
- Modify: `apps/companion/src/activity/calendar.ts` (NEW 파일 시작 — narrowing만 이 Task에서)

**Interfaces:**
- Produces: `type CalendarEventInput = { readonly observedAt: number; readonly root: string; readonly project: string; readonly task: string; readonly status?: string; readonly planTitle?: string; readonly planStatus?: string }` (`activity/calendar.ts`)
- Produces: `function calendarEventFromUnknown(value: unknown): CalendarEventInput | undefined` (`activity/calendar.ts`)
- Produces: `async function readActivityEvents(fromEpoch: number, toEpoch: number): Promise<readonly CalendarEventInput[]>` (`tauriClient.ts`) — Task 4가 소비.

- [x] **Step 1: 실패하는 테스트 작성** — `tests/activity-calendar.test.tsx`:

```ts
import { describe, expect, it } from "vitest";
import { calendarEventFromUnknown } from "../src/activity/calendar";

describe("calendarEventFromUnknown", () => {
	it("accepts a modern event and keeps optional plan fields", () => {
		const event = calendarEventFromUnknown({
			v: 1,
			observedAt: 100,
			root: "/r",
			project: "workbranch",
			task: "feat-x",
			status: "in-progress",
			planTitle: "Plan A",
			planStatus: "in-progress",
		});
		expect(event).toEqual({
			observedAt: 100,
			root: "/r",
			project: "workbranch",
			task: "feat-x",
			status: "in-progress",
			planTitle: "Plan A",
			planStatus: "in-progress",
		});
	});

	it("accepts a legacy event without plan fields", () => {
		const event = calendarEventFromUnknown({
			v: 1,
			observedAt: 100,
			root: "/r",
			project: "workbranch",
			task: "feat-x",
			status: "done",
		});
		expect(event?.planTitle).toBeUndefined();
	});

	it("rejects records missing observedAt, project, or task", () => {
		expect(calendarEventFromUnknown({ project: "a", task: "t" })).toBeUndefined();
		expect(calendarEventFromUnknown("junk")).toBeUndefined();
		expect(calendarEventFromUnknown(null)).toBeUndefined();
	});
});
```


`tests/tauri-client.test.ts`에도 실패하는 바인딩 테스트를 추가한다:

```ts
import { readActivityEvents } from "../src/infrastructure/tauriClient";

it("invokes the Tauri activity read command and filters invalid rows", async () => {
	tauri.invoke.mockResolvedValue([
		{ observedAt: 100, root: "/r", project: "workbranch", task: "feat-x" },
		{ observedAt: 200, project: "missing-root", task: "bad" },
	]);

	await expect(readActivityEvents(0, 300)).resolves.toEqual([
		{ observedAt: 100, root: "/r", project: "workbranch", task: "feat-x" },
	]);
	expect(tauri.invoke).toHaveBeenCalledWith("read_activity_events", {
		fromEpoch: 0,
		toEpoch: 300,
	});
});
```

- [x] **Step 2: 실패 확인** — Run: `cd apps/companion && pnpm test -- activity-calendar tauri-client`
  Expected: FAIL (`activity/calendar.ts` 또는 `readActivityEvents` 없음)
- [x] **Step 3: 최소 구현** — `src/activity/calendar.ts`:

```ts
export type CalendarEventInput = {
	readonly observedAt: number;
	readonly root: string;
	readonly project: string;
	readonly task: string;
	readonly status?: string;
	readonly planTitle?: string;
	readonly planStatus?: string;
};

function optionalString(value: unknown): string | undefined {
	return typeof value === "string" && value !== "" ? value : undefined;
}

export function calendarEventFromUnknown(
	value: unknown,
): CalendarEventInput | undefined {
	if (typeof value !== "object" || value === null) {
		return undefined;
	}
	const record = value as Record<string, unknown>;
	if (
		typeof record.observedAt !== "number" ||
		typeof record.root !== "string" ||
		typeof record.project !== "string" ||
		typeof record.task !== "string"
	) {
		return undefined;
	}
	return {
		observedAt: record.observedAt,
		root: record.root,
		project: record.project,
		task: record.task,
		status: optionalString(record.status),
		planTitle: optionalString(record.planTitle) ?? optionalString(record.plan),
		planStatus: optionalString(record.planStatus),
	};
}
```

`tauriClient.ts`에 추가:

```ts
import { calendarEventFromUnknown, type CalendarEventInput } from "../activity/calendar";

export async function readActivityEvents(
	fromEpoch: number,
	toEpoch: number,
): Promise<readonly CalendarEventInput[]> {
	const raw = await invoke<readonly unknown[]>("read_activity_events", {
		fromEpoch,
		toEpoch,
	});
	return raw
		.map(calendarEventFromUnknown)
		.filter((event): event is CalendarEventInput => event !== undefined);
}
```

- [x] **Step 4: 통과 확인** — Run: `cd apps/companion && pnpm test -- activity-calendar tauri-client && pnpm typecheck`
  Expected: PASS
- [ ] **Step 5: 커밋** — safety gate로 자동 실행 보류: `git commit -m "feat(companion): parse activity events for calendar domain"`

---

### Task 3: 세션화 + lane + 시간축 (순수 도메인)

**Files:**
- Modify: `apps/companion/src/activity/calendar.ts`
- Modify: `apps/companion/src/application/activity.ts` (상수 export만: `export const IDLE_GAP_SECONDS`, `export const LEAD_PAD_SECONDS`)
- Test: `apps/companion/tests/activity-calendar.test.tsx`

**Interfaces (Produces — Task 4가 그대로 소비):**

```ts
export type CalendarSession = {
	readonly key: string;          // root\u0000task\u0000start
	readonly root: string;
	readonly project: string;
	readonly task: string;
	readonly start: number;        // epoch seconds (lead pad 적용)
	readonly end: number;          // epoch seconds (최소 길이 보장)
	readonly status: string;       // 세션 마지막 이벤트의 status ?? "in-progress"
	readonly planTitles: readonly string[]; // 세션에 등장한 planTitle 중복 제거, 등장 순
};
export type LaneSession = CalendarSession & {
	readonly lane: number;
	readonly laneCount: number;
};
export const MIN_SESSION_SECONDS: number; // 5 * 60
export function sessionsFromEvents(events: readonly CalendarEventInput[]): readonly CalendarSession[];
export function clipToRange(sessions: readonly CalendarSession[], from: number, to: number): readonly CalendarSession[];
export function assignLanes(sessions: readonly CalendarSession[]): readonly LaneSession[];
export function hourRange(sessions: readonly CalendarSession[], dayStart: number): { readonly startHour: number; readonly endHour: number }; // 기본 9..19, 세션 포함하도록 확장
export function startOfDayEpoch(anchor: Date): number;   // 로컬 자정
export function addDays(epoch: number, days: number): number; // epoch + days * 86400
export function projectColorIndex(project: string, paletteSize: number): number; // 안정 해시 % size
```

- [x] **Step 1: 실패하는 테스트 작성** — `tests/activity-calendar.test.tsx`에 추가:

```ts
import {
	addDays,
	assignLanes,
	clipToRange,
	hourRange,
	projectColorIndex,
	sessionsFromEvents,
	startOfDayEpoch,
} from "../src/activity/calendar";

const BASE = 1_781_400_000; // 임의 기준 epoch (초)

function event(observedAt: number, task = "feat-x", planTitle?: string) {
	return { observedAt, root: "/r", project: "workbranch", task, status: "in-progress", planTitle };
}

describe("sessionsFromEvents", () => {
	it("merges consecutive events of one task within the idle gap", () => {
		const sessions = sessionsFromEvents([
			event(BASE),
			event(BASE + 600),
			event(BASE + 1200),
		]);
		expect(sessions).toHaveLength(1);
		expect(sessions[0]?.start).toBe(BASE - 300); // lead pad 5m
		expect(sessions[0]?.end).toBe(BASE + 1200);
	});

	it("splits into two sessions when the gap exceeds 25 minutes", () => {
		const sessions = sessionsFromEvents([event(BASE), event(BASE + 26 * 60)]);
		expect(sessions).toHaveLength(2);
	});

	it("keeps different tasks in separate sessions", () => {
		const sessions = sessionsFromEvents([event(BASE, "a"), event(BASE + 60, "b")]);
		expect(sessions).toHaveLength(2);
	});

	it("guarantees a minimum block length for single-event sessions", () => {
		const sessions = sessionsFromEvents([event(BASE)]);
		expect((sessions[0]?.end ?? 0) - (sessions[0]?.start ?? 0)).toBe(300 + 300);
	});

	it("collects plan titles in order without duplicates", () => {
		const sessions = sessionsFromEvents([
			event(BASE, "a", "P1"),
			event(BASE + 60, "a", "P2"),
			event(BASE + 120, "a", "P1"),
		]);
		expect(sessions[0]?.planTitles).toEqual(["P1", "P2"]);
	});
});

describe("assignLanes", () => {
	it("places overlapping sessions in separate lanes with a shared lane count", () => {
		const sessions = sessionsFromEvents([event(BASE, "a"), event(BASE + 60, "b")]);
		expect(sessions).toHaveLength(2);
		const [a, b] = sessions;
		if (a === undefined || b === undefined) {
			throw new Error("expected two sessions");
		}
		const lanes = assignLanes([a, b]);
		expect(new Set(lanes.map((s) => s.lane))).toEqual(new Set([0, 1]));
		expect(lanes.every((s) => s.laneCount === 2)).toBe(true);
	});

	it("reuses lane 0 for non-overlapping sessions", () => {
		const sessions = sessionsFromEvents([event(BASE, "a"), event(BASE + 7200, "b")]);
		const lanes = assignLanes(sessions);
		expect(lanes.every((s) => s.lane === 0 && s.laneCount === 1)).toBe(true);
	});
});

describe("clipToRange / hourRange / date helpers", () => {
	it("clips a session crossing midnight to the day range", () => {
		const day = startOfDayEpoch(new Date(2026, 6, 4));
		const [session] = sessionsFromEvents([
			event(day - 600, "a"),
			event(day + 600, "a"),
		]);
		if (session === undefined) {
			throw new Error("expected a session");
		}
		const clipped = clipToRange([session], day, addDays(day, 1));
		expect(clipped[0]?.start).toBe(day);
		expect(clipped[0]?.end).toBe(day + 600);
	});

	it("drops sessions fully outside the range", () => {
		const day = startOfDayEpoch(new Date(2026, 6, 4));
		const [session] = sessionsFromEvents([event(day - 7200, "a")]);
		if (session === undefined) {
			throw new Error("expected a session");
		}
		expect(clipToRange([session], day, addDays(day, 1))).toHaveLength(0);
	});

	it("expands the default 9-19 hour range to include sessions", () => {
		const day = startOfDayEpoch(new Date(2026, 6, 4));
		const [early] = sessionsFromEvents([event(day + 6 * 3600, "a")]);
		if (early === undefined) {
			throw new Error("expected a session");
		}
		const range = hourRange([early], day);
		expect(range.startHour).toBeLessThanOrEqual(5); // 05:55 lead pad 포함
		expect(range.endHour).toBe(19);
		expect(hourRange([], day)).toEqual({ startHour: 9, endHour: 19 });
	});

	it("hashes project names to a stable palette index", () => {
		expect(projectColorIndex("workbranch", 6)).toBe(projectColorIndex("workbranch", 6));
		expect(projectColorIndex("workbranch", 6)).toBeGreaterThanOrEqual(0);
		expect(projectColorIndex("workbranch", 6)).toBeLessThan(6);
	});
});
```

- [x] **Step 2: 실패 확인** — Run: `cd apps/companion && pnpm test -- activity-calendar` → FAIL
- [x] **Step 3: 최소 구현** — `activity/calendar.ts`에 추가 (핵심 로직):

```ts
import { IDLE_GAP_SECONDS, LEAD_PAD_SECONDS } from "../application/activity";

export const MIN_SESSION_SECONDS = 5 * 60;

export type CalendarSession = {
	readonly key: string;
	readonly root: string;
	readonly project: string;
	readonly task: string;
	readonly start: number;
	readonly end: number;
	readonly status: string;
	readonly planTitles: readonly string[];
};
export type LaneSession = CalendarSession & {
	readonly lane: number;
	readonly laneCount: number;
};

function sessionKey(root: string, task: string, start: number): string {
	return [root, task, String(start)].join("\u0000");
}

export function sessionsFromEvents(
	events: readonly CalendarEventInput[],
): readonly CalendarSession[] {
	const byTask = new Map<string, CalendarEventInput[]>();
	for (const event of events) {
		const key = [event.root, event.project, event.task].join("\u0000");
		const bucket = byTask.get(key) ?? [];
		bucket.push(event);
		byTask.set(key, bucket);
	}
	const sessions: CalendarSession[] = [];
	for (const bucket of byTask.values()) {
		const sorted = [...bucket].sort((a, b) => a.observedAt - b.observedAt);
		let run: CalendarEventInput[] = [];
		const flush = (): void => {
			const first = run[0];
			const last = run.at(-1);
			if (first === undefined || last === undefined) {
				return;
			}
			const start = first.observedAt - LEAD_PAD_SECONDS;
			const end = Math.max(last.observedAt, first.observedAt + MIN_SESSION_SECONDS);
			const planTitles: string[] = [];
			for (const item of run) {
				if (item.planTitle !== undefined && !planTitles.includes(item.planTitle)) {
					planTitles.push(item.planTitle);
				}
			}
			sessions.push({
				key: sessionKey(first.root, first.task, start),
				root: first.root,
				project: first.project,
				task: first.task,
				start,
				end,
				status: last.status ?? "in-progress",
				planTitles,
			});
			run = [];
		};
		for (const item of sorted) {
			const previous = run.at(-1);
			if (previous !== undefined && item.observedAt - previous.observedAt > IDLE_GAP_SECONDS) {
				flush();
			}
			run.push(item);
		}
		flush();
	}
	return sessions.sort((a, b) => a.start - b.start);
}

export function clipToRange(
	sessions: readonly CalendarSession[],
	from: number,
	to: number,
): readonly CalendarSession[] {
	return sessions
		.filter((session) => session.end > from && session.start < to)
		.map((session) => ({
			...session,
			start: Math.max(session.start, from),
			end: Math.min(session.end, to),
		}));
}

export function assignLanes(
	sessions: readonly CalendarSession[],
): readonly LaneSession[] {
	const sorted = [...sessions].sort((a, b) => a.start - b.start);
	const result: Array<CalendarSession & { lane: number; laneCount: number }> = [];
	let cluster: Array<CalendarSession & { lane: number; laneCount: number }> = [];
	let clusterEnd = Number.NEGATIVE_INFINITY;
	const closeCluster = (): void => {
		const laneCount = Math.max(0, ...cluster.map((s) => s.lane)) + 1;
		for (const session of cluster) {
			result.push({ ...session, laneCount });
		}
		cluster = [];
	};
	for (const session of sorted) {
		if (cluster.length > 0 && session.start >= clusterEnd) {
			closeCluster();
			clusterEnd = Number.NEGATIVE_INFINITY;
		}
		const laneEnds: number[] = [];
		for (const placed of cluster) {
			laneEnds[placed.lane] = Math.max(laneEnds[placed.lane] ?? 0, placed.end);
		}
		let lane = laneEnds.findIndex((end) => end <= session.start);
		if (lane === -1) {
			lane = laneEnds.length;
		}
		cluster.push({ ...session, lane, laneCount: 1 });
		clusterEnd = Math.max(clusterEnd, session.end);
	}
	if (cluster.length > 0) {
		closeCluster();
	}
	return result;
}

export function hourRange(
	sessions: readonly CalendarSession[],
	dayStart: number,
): { readonly startHour: number; readonly endHour: number } {
	let startHour = 9;
	let endHour = 19;
	for (const session of sessions) {
		startHour = Math.min(startHour, Math.floor((session.start - dayStart) / 3600));
		endHour = Math.max(endHour, Math.ceil((session.end - dayStart) / 3600));
	}
	return { startHour: Math.max(0, startHour), endHour: Math.min(24, endHour) };
}

export function startOfDayEpoch(anchor: Date): number {
	const day = new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate());
	return Math.floor(day.getTime() / 1000);
}

export function addDays(epoch: number, days: number): number {
	return epoch + days * 86_400;
}

export function projectColorIndex(project: string, paletteSize: number): number {
	let hash = 0;
	for (const char of project) {
		hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
	}
	return hash % paletteSize;
}
```

`application/activity.ts`의 두 상수를 `export const`로 변경한다(값·사용처 불변).

- [x] **Step 4: 통과 확인** — Run: `cd apps/companion && pnpm test && pnpm typecheck && pnpm lint`
  Expected: 테스트/typecheck PASS. 전체 lint는 기존 `parseContract.ts` useLiteralKeys baseline 진단으로 FAIL, 변경 파일 targeted lint PASS.
- [ ] **Step 5: 커밋** — safety gate로 자동 실행 보류: `git commit -m "feat(companion): derive calendar sessions and lanes from activity events"`

---

### Task 4: `ActivityCalendarView` UI + 스타일 + App 연결

**Files:**
- Create: `apps/companion/src/activity/ActivityCalendarView.tsx`
- Create: `apps/companion/src/activity/activity-calendar.css`
- Modify: `apps/companion/src/style.css` (`@import "./activity/activity-calendar.css";` 추가 — 기존 import 목록 뒤)
- Modify: `apps/companion/src/styles/themes.css` (양 테마에 `--cal-1`~`--cal-6`)
- Modify: `apps/companion/src/App.tsx` (placeholder section 교체)
- Test: `apps/companion/tests/activity-calendar.test.tsx`

**Interfaces:**
- Consumes: Task 2의 `readActivityEvents`, Task 3의 도메인 함수 전부.
- Produces:

```tsx
export type CalendarMode = "day" | "three-day";
export const CALENDAR_MODES: readonly { mode: CalendarMode; label: string; ariaLabel: string }[];
// 데이터 로더는 주입해 테스트 가능하게 한다 (workspaceMonitor 패턴과 동일 사상)
export function ActivityCalendarView({ loadEvents, today }: {
	readonly loadEvents: (fromEpoch: number, toEpoch: number) => Promise<readonly CalendarEventInput[]>;
	readonly today: () => Date;
}): JSX.Element;
// 표현 전용 — 테스트가 직접 렌더
export function CalendarTimeline({ days, sessions, mode, selectedKey, onSelect }: {
	readonly days: readonly number[];          // 각 날의 startOfDayEpoch
	readonly sessions: readonly LaneSession[]; // 이미 clip+lane 처리됨
	readonly mode: CalendarMode;
	readonly selectedKey: string | undefined;
	readonly onSelect: (key: string | undefined) => void;
}): JSX.Element;
```

**컴포넌트 동작 명세:**
- 헤더 1행: `‹` `›` 버튼(aria-label "Previous period"/"Next period", anchor를 mode 일수만큼 이동), 가운데 날짜 라벨(daily: `Sat, Jul 4` / 오늘이면 `Today, Jul 4`; 3-day: `Jul 4 – Jul 6`), `Today` 버튼(aria-label "Go to today"), 우측에 모드 토글 — `CALENDAR_MODES` 배열을 map해 아이콘 버튼 렌더(`aria-label`: "Day view" / "Three day view", 활성은 `aria-pressed="true"`). 아이콘은 ViewNav처럼 inline SVG: day = 세로 막대 1개(`<rect x="9" y="4" width="6" height="16" rx="1"/>`), three-day = 세로 막대 3개.
- 헤더 2행: 프로젝트 chips — 조회 결과에 등장한 project를 정렬해 `<button className="cal-chip" data-color={index}>` 로 나열, 색 점 + 이름. 클릭 시 해당 프로젝트만 표시/해제(모두 해제 상태 = 전체 표시). `aria-pressed`로 활성 노출.
- 본문: 좌측 시간 라벨 열(`hourRange` 결과, `9 AM` 형식), 우측 day 컬럼들(daily 1개, 3-day 3개, 3-day는 컬럼 상단에 요일·일 라벨). 각 컬럼은 `position: relative`, 세션 블록은 `top/height` % 계산(`(start - dayStart - startHour*3600) / ((endHour-startHour)*3600)`), lane은 `left/width` % 분할. 블록 배경은 `var(--cal-N)` 기반 soft(예: `color-mix(in srgb, var(--cal-1) 18%, transparent)`) + 왼쪽 3px 실선 보더 `var(--cal-N)`.
- 블록 내용: daily = task명 + `HH:mm–HH:mm`(마지막 planTitle 한 줄 muted), 3-day = task명만(overflow ellipsis). 블록은 `<button>`으로 클릭 → `onSelect(key)`.
- 선택 상세: 타임라인 아래 고정 패널 — `project / task`, 시간 범위, `planTitles` 목록. 선택 없으면 렌더 안 함.
- 로딩/빈 상태: 이벤트 0건이면 기존 `.empty` 클래스로 `No activity recorded for this period.` 표시. `loadEvents` 실패 시 같은 자리에서 `.error`로 메시지 표시(앱 전역 상태는 건드리지 않는다).
- 데이터 로드: `useEffect`로 `[anchorEpoch, mode]` 변경 시 `loadEvents(rangeStart - IDLE_GAP_SECONDS, rangeEnd)` 호출(경계 세션이 range 밖 이벤트로 시작할 수 있어 앞쪽 여유를 둔다). 언마운트 후 setState 방지 cancelled 플래그 사용(App.tsx의 monitor effect 패턴).

- [x] **Step 1: 실패하는 뷰 테스트 작성** — `tests/activity-calendar.test.tsx` (view-nav 패턴: `renderToStaticMarkup` + `collectButtons`):

```tsx
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import {
	addDays,
	assignLanes,
	sessionsFromEvents,
	startOfDayEpoch,
} from "../src/activity/calendar";
import {
	CALENDAR_MODES,
	CalendarTimeline,
} from "../src/activity/ActivityCalendarView";

const DAY = startOfDayEpoch(new Date(2026, 6, 4));

function laneSessions(observedAts: readonly number[], task = "feat-x") {
	return assignLanes(
		sessionsFromEvents(
			observedAts.map((observedAt) => ({
				observedAt,
				root: "/r",
				project: "workbranch",
				task,
				status: "in-progress" as const,
			})),
		),
	);
}

describe("CalendarTimeline", () => {
	it("renders a session block with task name and time range in day mode", () => {
		const html = renderToStaticMarkup(
			<CalendarTimeline
				days={[DAY]}
				mode="day"
				selectedKey={undefined}
				onSelect={() => {}}
				sessions={laneSessions([DAY + 10 * 3600])}
			/>,
		);
		expect(html).toContain("feat-x");
		expect(html).toContain("9 AM"); // 기본 시간축 라벨
	});

	it("renders three day columns in three-day mode", () => {
		const html = renderToStaticMarkup(
			<CalendarTimeline
				days={[DAY, addDays(DAY, 1), addDays(DAY, 2)]}
				mode="three-day"
				selectedKey={undefined}
				onSelect={() => {}}
				sessions={[]}
			/>,
		);
		expect(html.match(/cal-day-column/g)?.length).toBe(3);
	});
});

describe("CALENDAR_MODES", () => {
	it("offers exactly day and three-day modes for this slice", () => {
		expect(CALENDAR_MODES.map((item) => item.mode)).toEqual(["day", "three-day"]);
	});
});
```

- [x] **Step 2: 실패 확인** — Run: `cd apps/companion && pnpm test -- activity-calendar` → FAIL
- [x] **Step 3: 구현** — 위 동작 명세대로 `ActivityCalendarView.tsx` / `activity-calendar.css` 작성, `themes.css` 팔레트 추가:

```css
/* themes.css — catppuccin-dark 블록에 */
	--cal-1: #cba6f7; --cal-2: #89b4fa; --cal-3: #a6e3a1;
	--cal-4: #f9e2af; --cal-5: #f5c2e7; --cal-6: #94e2d5;
/* breakfast-light 블록에 */
	--cal-1: #7c3aed; --cal-2: #1d4ed8; --cal-3: #2f9e44;
	--cal-4: #d97706; --cal-5: #db2777; --cal-6: #0d9488;
```

`App.tsx` placeholder 교체:

```tsx
{currentView === "activity" ? (
	<section className="activity-view view-panel" aria-label="Activity calendar">
		<ActivityCalendarView
			loadEvents={readActivityEvents}
			today={() => new Date()}
		/>
	</section>
) : null}
```

(`ActivityCalendarView`는 `./activity/ActivityCalendarView`에서, `readActivityEvents`는 tauriClient import 목록에서 추가한다. Tauri 런타임이 없으면 `loadEvents`가 reject되고 컴포넌트가 로컬 에러 표시로 처리한다.)

- [x] **Step 4: 통과 확인** — Run: `cd apps/companion && pnpm test && pnpm typecheck && pnpm lint`
  Expected: PASS. `app-shell.test.tsx` 변경 필요 없음.
- [ ] **Step 5: 커밋** — safety gate로 자동 실행 보류: `git commit -m "feat(companion): activity calendar timeline with day and three-day views"`

---

### Task 5: 수동 검증 + 문서 동기화

**Files:**
- Modify: `apps/companion/README.md` (Activity 뷰 설명 — 현재 뷰 목록 문단)
- Modify: `README.md`, `README.ko.md` (Companion 기능 소개에 Activity calendar 한 줄, EN/KO 동일 PR 동기화)

- [x] **Step 1: 실데이터 검증** — `pnpm tauri dev` GUI 육안 확인은 비대화형 실행에서 객관 판정 불가라 자동 대체 검증으로 기록. `~/.local/state/workbranch/activity.jsonl` 존재, 9,839개 event, latest local `2026-07-05 05:17:30`; production build/test/cargo 검증으로 Tauri surface 컴파일 확인.
- [x] **Step 2: 문서 갱신** — 세 README에 Activity calendar 설명 반영(EN/KO 동기화).
- [x] **Step 3: 최종 검증** — Run:

```bash
cd apps/companion && pnpm test && pnpm typecheck && pnpm lint && pnpm build
cd src-tauri && cargo test
cd ../../.. && git diff --check
```

- [ ] **Step 4: 커밋** — safety gate로 자동 실행 보류: `git commit -m "docs(companion): document activity calendar view"`

---

## 롤아웃 / 호환성

- **비파괴.** `activity.jsonl` 쓰기 경로·스키마 불변, 읽기 command만 추가. 구버전 라인(plan 필드 없음)은 legacy로 정상 표시되고, 깨진 라인은 조용히 건너뛴다.
- 10MB(~1만 라인) 로그 전체를 라인 스캔하지만 Rust `BufReader` + `spawn_blocking`이라 UI는 블록되지 않는다. 로그가 수십 MB로 커지면 후속에서 tail 인덱싱 고려.

## 미해결 / 후속

- **Weekly 뷰**: `CALENDAR_MODES`에 `{ mode: "week" }` 추가 + 컬럼 렌더(블록만·클릭 상세) — 이번 slice에서 제외(사용자 결정).
- **시간 합계/통계**: 캘린더 아래 task/plan별 합계 리스트(`buildPlanReport` 재사용) — 다음 slice.
- **라이브 갱신**: 현재는 뷰 진입/날짜 변경 시 로드. `roots-changed` 이벤트 연동 리프레시는 후속.
- 앵커 날짜 접근성(스크린리더용 날짜 선택기)은 후속.

## 실행 결과

- [x] Task 1 — Rust read command (`cargo test read_activity`, `cargo test` PASS)
- [x] Task 2 — tauriClient + narrowing (`pnpm test -- activity-calendar tauri-client`, `pnpm typecheck` PASS)
- [x] Task 3 — 세션화/lane/시간축 도메인 (`pnpm test -- activity-calendar`, `pnpm test`, `pnpm typecheck` PASS; 변경 파일 lint PASS)
- [x] Task 4 — ActivityCalendarView UI + App 연결 (`pnpm test`, `pnpm typecheck`, `pnpm lint` PASS)
- [x] Task 5 — 실데이터 자동 검증 + 문서 (`pnpm test/typecheck/lint/build`, `cargo test`, `git diff --check` PASS; GUI 육안은 미실행)

### 검증 기록

- 2026-07-05 Task 1: `cd apps/companion/src-tauri && cargo test read_activity && cargo test` — PASS (22 tests).
- 2026-07-05 Task 2: `cd apps/companion && pnpm test -- activity-calendar tauri-client && pnpm typecheck` — PASS (13 files, 64 tests; typecheck PASS).
- 2026-07-05 Task 3: `cd apps/companion && pnpm test -- activity-calendar && pnpm test && pnpm typecheck` — PASS (13 files, 75 tests; typecheck PASS).
- 2026-07-05 Task 3 lint: `pnpm exec biome check src/activity/calendar.ts src/infrastructure/tauriClient.ts tests/activity-calendar.test.tsx` — PASS. 당시 전체 lint는 변경 중 import 정렬 오류와 기존 `parseContract.ts` info 진단을 함께 출력했고, final 전체 lint는 PASS.
- 2026-07-05 Task 4: `cd apps/companion && pnpm test -- activity-calendar && pnpm test && pnpm typecheck && pnpm lint` — PASS (13 files, 78 tests; typecheck PASS; lint exit 0 with existing info diagnostics).
- 2026-07-05 Task 5 실데이터: `~/.local/state/workbranch/activity.jsonl` — PASS (9,839 events, latest local `2026-07-05 05:17:30`). `pnpm tauri dev` GUI 육안 확인은 비대화형 환경이라 미실행.
- 2026-07-05 Final: `cd apps/companion && pnpm test && pnpm typecheck && pnpm lint && pnpm build; cd src-tauri && cargo test; cd ../../.. && git diff --check` — PASS (13 files, 78 tests; build PASS; cargo 22 tests PASS; diff check PASS).
- 2026-07-05 Post-review visual fix: one-day compact session text clipping corrected by rendering compact day blocks as task/time only with taller min-height. `cd apps/companion && pnpm test && pnpm typecheck && pnpm lint && pnpm build; cd ../.. && git diff --check` — PASS (13 files, 80 tests; build PASS; diff check PASS).
- 2026-07-05 Post-review visual fix 2: one-day overlapping narrow-lane blocks now suppress plan row and use narrow typography while keeping selected detail as the full-information surface. `cd apps/companion && pnpm test && pnpm typecheck && pnpm lint && pnpm build; cd ../.. && git diff --check` — PASS (13 files, 81 tests; build PASS; diff check PASS).
- (실행 시 기록)
