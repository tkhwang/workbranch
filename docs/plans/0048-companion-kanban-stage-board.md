# 0048 Companion Kanban stage board + status-only agent 프로토콜

> **agentic worker 지침:** 실행 시 `superpowers:executing-plans`를 사용한다. 동작 변경 전에는 `superpowers:test-driven-development`(red → green → refactor)를 따른다. 이 plan은 **CLI 템플릿(shell) + Companion(React) + docs/design**를 가로지르는 slice다. CLI는 `apps/cli/src/workbranch/**` 수정 후 `apps/cli/scripts/build-workbranch.sh`로 재생성하고 `apps/cli/tests/run.sh`로 검증한다. Companion은 `apps/companion`에서 `pnpm test` + `pnpm typecheck` + `pnpm lint`로 검증한다. Step은 checkbox(`- [ ]`)로 추적한다.
>
> **시리즈 위치:** 0021이 brief 기반 진행 표시를, 0029/0031이 Plan/Step 계층과 current-only brief를, 0032가 Tauri/React companion을 만들었다. 이 slice는 그 위에서 **표시 철학을 뒤집는다**: step-tree cockpit → stage-first 칸반. agent가 유지해야 하는 상태를 `status:` 한 줄로 줄여 토큰 비용을 낮춘다. (참고: 0047 번호는 진행 중인 review-tool-launcher task가 사용하므로 건너뛴다.)

**목표:** companion main 뷰를 PLAN | EXECUTION | REVIEW 3컬럼 칸반 스트립 + task별 repo meta/실행 버튼 행으로 재구성하고, 생성되는 `AGENTS.md`의 agent 업데이트 프로토콜을 "stage 전환 시 `status:` 한 줄 갱신"으로 다이어트한다.

## 배경 / 조사 결과 (2026-08-16)

Write 쪽과 read 쪽의 불균형이 코드로 확인됐다.

**Write (agent 토큰 비용):** `task-state.sh:write_task_agent_guidance`가 생성하는 `AGENTS.md`는 6개 시점(시작/재개, step 변경마다, 검증 전, 검증 후, blocked, final response 직전)마다 brief 전체 rewrite + substep 체크리스트 유지를 요구한다. 실사용 증거: feat-add-review brief는 27줄, "RED 3건 확인, targeted GREEN 3/3" 수준의 substep까지 기록됐다.

**Read (companion 실소비):**

| 데이터 | 소비 | 비고 |
|---|---|---|
| `status:` | ✅ 핵심 | StatusToken + active/blocked 요약 |
| repos(name/branch/dirty) | ✅ RepoChips + 액션 버튼 | CLI가 git에서 직접 계산 — agent 비용 0 |
| progress N/M, currentItem | 배지 1줄 | 부수적 |
| step tree 전체 | expanded detail 렌더 | 실질 소비 낮음 (사용자 확인) |
| `## 메모`/Notes | ❌ 미표시 | 파서가 H2 이하 전부 무시 (`task-state.sh:80`) |
| `memoTitle` | ❌ dead field | contract→파싱→model까지 오지만 어떤 UI도 렌더 안 함 |
| `notifications.jsonl` | 배지만 | 전 task 0 byte — 실사용 없음 |

즉 가장 비싼 write(step/메모 유지)가 가장 안 읽히고, 가장 잘 읽히는 데이터(repo meta)는 agent 비용이 0이다.

## 결정 사항 (2026-08-16, 사용자 확정)

> **D1. agent 프로토콜은 status-only.** 생성 `AGENTS.md`는 stage 전환 시 `status:` 한 줄 갱신만 요구한다: `todo → planning`(계획을 포함한 의미 있는 작업을 시작하면 즉시) `→ in-progress`(구현 시작) `→ review`(구현 완료, 검증/리뷰) `→ done`(완료). `blocked`는 `in-progress`에서만 진입하고 해제 시 `in-progress`로 복원한다. step 체크리스트·메모는 "사용자가 요청할 때만"으로 강등한다. 기본 brief 템플릿도 `# <task>` + `status: todo` 2줄로 축소한다.
>
> **D2. 보드는 3컬럼 + blocked 배지 + done 숨김.** 컬럼 매핑: PLAN ← `todo`,`planning` · EXECUTION ← `in-progress` · REVIEW ← `review`. `blocked`는 Execution 전용 pause 상태로 `in-progress`에서만 진입하고, 해제 시 항상 `in-progress`로 복원한다. 따라서 EXECUTION 컬럼에 blocked 강조 배지로 표시한다. `done`은 보드에서 제외한다(요약 카운트는 유지).
>
> **D3. 안 읽히는 데이터는 semantic model에서 먼저 정리한다.** 이번 slice에서는 Companion domain `Task`와 ACL/UI에서 `memoTitle`을 제거하되, 독립 배포 호환을 위해 schema v1의 CLI JSON·`@workbranch/contract` DTO·파서 필수 검증은 유지한다. 새 Companion은 v1 `memoTitle`을 wire compatibility field로만 수용하고 semantic state에는 보존하지 않는다. 실제 wire 필드 제거는 후속 schema v2 slice에서 dual-read/배포 순서와 함께 처리한다. noti 배지는 유지(데이터 있으면 표시). `plan:` 등 다른 필드는 건드리지 않는다.
>
> **D4. 레이아웃 = 상단 칸반 스트립 + 하단 repo meta 행.** 창 폭 460px에서 3컬럼 카드에 repo chip과 버튼까지 넣을 수 없다. 카드에는 task 이름 + (blocked 배지) + (progress N/M, 있을 때만) + (`notiCount > 0`일 때 `+N`)만 표시하고, 스트립 아래에 project별로 task 행(task 이름 + RepoChips + IDE/Terminal/Finder 버튼)을 나열한다. notification 배지는 StageCard에만 두고 TaskMetaRow에는 중복하지 않는다. `done`은 StageBoard에서만 제외하고, 완료 task를 다시 열 수 있도록 하단 TaskMetaRow에는 유지한다. step tree/CurrentStep 렌더는 main 뷰에서 제거한다.
>
> **D5. 파싱·계약의 checklist 지원은 유지.** brief 파서(`task_load_plans`), `items[]`/`plans[]`/progress 필드, activity calendar(plan signature 기반)는 변경하지 않는다. 구 brief가 여전히 파싱되고, step을 쓰는 task도 progress 배지로 반영된다. 제거는 **UI 렌더와 agent 요구사항**에 한정한다.
>
> **D6. StageCard task/worktree 이름은 전체 줄바꿈으로 표시한다.** 3컬럼의 single-line ellipsis는 `feature-cpq-...`처럼 공통 prefix만 남기고 실제 식별 suffix를 숨긴다. 카드 높이의 균일성보다 정확한 task 식별을 우선해 이름을 생략하지 않고 하이픈/필요 시 임의 지점에서 자연 줄바꿈한다. `title`은 보조 정보로 유지한다.

## Decision Gates

- [x] `memoTitle` wire 제거 시점
  - Impact: public JSON contract, 독립 Homebrew 배포, 기존 Companion refresh 호환성
  - Evidence: `apps/companion/src/infrastructure/parseContract.ts`, `release-please-config.json`, `.release-please-manifest.json`
  - Status: resolved — **2단계 제거**. 이번 slice는 schema v1 wire field를 유지하고 Companion semantic 의존만 제거한다. 실제 wire 제거는 schema v2 후속 slice로 분리한다.
- [x] `done` task 표시 범위
  - Impact: Main 정보 밀도와 완료 task의 IDE/Terminal/Finder 재접근성
  - Evidence: D2는 `done`을 board에서 제외하고 D4는 project별 TaskMetaRow를 별도 운영 surface로 둔다.
  - Status: resolved by existing plan evidence — StageBoard에서는 숨기고 TaskMetaRow에는 유지한다.
- [x] notification 배지 위치
  - Impact: StageBoard의 즉시 인지성과 460px 카드 정보 밀도
  - Evidence: 기존 `TaskRow` summary의 `+N`은 task 상태 신호이며 새 layout에서 명시적 owner가 필요하다.
  - Status: resolved — `notiCount > 0`일 때 StageCard에만 `+N`을 표시하고 TaskMetaRow에는 중복하지 않는다.
- [x] StageBoard 신규 파일 배치
  - Impact: component/style ownership과 이후 유지보수 경계
  - Evidence: UI component는 `src/ui/*.tsx` flat 구조이고 CSS는 `src/styles/*.css`를 `style.css`에서 import한다.
  - Status: resolved — `apps/companion/src/ui/StageBoard.tsx`와 `apps/companion/src/styles/stage-board.css`를 만들고 `style.css`에서 import한다.
- [x] StageCard의 긴 task/worktree 이름 표시
  - Impact: 460px 3컬럼에서 worktree 식별 정확성과 카드 높이/밀도
  - Evidence: single-line ellipsis는 공통 prefix 뒤의 구분 suffix를 숨기며, native 화면에서는 hover tooltip에 의존하지 않고 이름을 직접 읽을 수 있어야 한다.
  - Status: resolved — 사용자 선택 A. 카드 높이 가변을 허용하고 전체 이름을 줄바꿈해 표시한다.
- [x] `blocked`의 이전 stage 손실
  - Impact: status lifecycle, StageBoard 배치, agent 재개 동작
  - Evidence: status-only 한 줄은 `blocked` 진입 전의 `planning`/`review`를 보존할 수 없으며, 기존 StageBoard는 모든 blocked task를 Execution에 배치한다.
  - Status: resolved — 사용자 선택 A. `blocked`를 `in-progress`에서만 진입 가능한 Execution pause 상태로 제한하고, 해제 시 `in-progress`로 복원한다.

## Global Constraints

- CLI: portable Bash, 명시적 quoting, snake_case. `bin/workbranch` 직접 수정 금지 — `src/workbranch/**` 수정 후 재생성. 테스트는 `tests/cases/*.sh`의 `run_test` harness 사용.
- 생성 guidance는 ko/en 두 벌을 항상 동기화한다 (`PREFERRED_LANGUAGE`). `status:` 값 어휘 `todo | planning | in-progress | review | blocked | done`은 기계가독 그대로 유지.
- Companion: TS/TSX 탭 들여쓰기 + biome, readonly type/순수 함수/의존성 주입 idiom. 테스트는 DOM 없이 순수 함수 + `renderToStaticMarkup`. 새 테스트 의존성 금지.
- Tauri 쪽(Rust command, watch, activity store)은 변경하지 않는다.
- 커밋은 Conventional Commits, 이모지 prefix 금지.

## public contract (변경 / 비변경)

### 변경하는 것
- 생성 `AGENTS.md` 진행 프로토콜 본문(ko/en)과 기본 `TASK-WORKBRANCH.md` 템플릿.
- Companion domain `Task`/ACL/UI에서 `memoTitle` semantic 의존 제거.
- Companion main 뷰 구조: ProjectGroup>TaskRow(details/steps) → StageBoard + project별 TaskMetaRow.

### 변경하지 않는 것
- brief 파일 포맷 파싱 규칙 전체 (H1 Plan, `status:`, checklist Step, H2 이하 무시, status 도출 규칙).
- schema v1 JSON 전체(`memoTitle` 포함)와 `@workbranch/contract` DTO/JSON Schema/fixture/파서 필수 검증.
- Tauri command 계약(`workbranch_list_global`, `workbranch_run`, watch, activity), 액션 3종(IDE/Terminal/Finder).
- activity calendar 도메인·이벤트 스키마 (status-only brief에서는 status 전환 시점에 이벤트가 발생하게 된다 — granularity 축소는 의도된 트레이드오프).
- `workbranch memo`/`noti` 명령 동작.

## 파일 구조 (touched)

```text
apps/cli/src/workbranch/lib/task-state.sh      # write_default_task_brief, write_task_agent_guidance (ko/en)
apps/cli/tests/cases/memo.sh                   # 템플릿/guidance 문구 기대 갱신
apps/cli/bin/workbranch                        # 재생성

apps/companion/src/domain/model.ts             # Task.memoTitle 제거, taskStage/isBlocked 추가
apps/companion/src/infrastructure/acl.ts       # memoTitle 매핑 제거
apps/companion/src/application/state.ts        # buildBoardModel (컬럼 매핑, done 제외)
apps/companion/src/ui/StageBoard.tsx           # 신규: 3컬럼 스트립 + 컴팩트 카드
apps/companion/src/ui/TaskRow.tsx              # TaskMetaRow로 축소 (steps/CurrentStep 제거)
apps/companion/src/ui/ProjectGroup.tsx         # TaskMetaRow 배선
apps/companion/src/App.tsx                     # main 뷰 = StageBoard + 그룹 행
apps/companion/src/styles/stage-board.css       # 신규: 보드/컬럼/카드/배지/460px 규칙
apps/companion/src/style.css                    # stage-board.css import manifest 등록
apps/companion/tests/*.test.ts(x)              # domain fixture memoTitle 제거, DTO fixture 유지, board/행 테스트

docs/usage.md, docs/usage.ko.md                # brief 프로토콜 문단(96행 부근) 갱신
docs/specs/0001-workbranch-mvp.md              # v1 memoTitle 호환 필드 유지·brief 규칙(174행) 갱신
DESIGN.md                                      # stage-first Main 정보 구조와 검증 계약 갱신
AGENTS.md                                      # Agent-Specific Instructions의 brief 문단 갱신
```

---

### Task 1: CLI 템플릿 다이어트 (D1)

**Red:** `tests/cases/memo.sh`의 템플릿 기대를 갱신한다 — 새 brief는 `# <task>` + `status: todo`만 포함(`- [ ] Major: Start work` 부재 확인), 새 guidance는 "stage 전환 시 status 한 줄"(en: `Update only the status: line`, ko 대응 문구), 6-시점 나열·step 의무 문구 부재 확인. ko 테스트(`test_preferred_language_generates_korean_task_guidance`)도 동일하게. 기존 워크스페이스 오리엔테이션 bullet(task root 비-git, repo-local 지침, `workbranch done` 아카이브, `PREFERRED_LANGUAGE`)은 유지 기대.

**Green:** `task-state.sh`의 `write_default_task_brief`/`write_task_agent_guidance` ko/en 재작성 → `pnpm run cli:build` → 대상 테스트 GREEN.

- [x] red 확인 (memo.sh 갱신 후 3건 실패)
- [x] green: 템플릿 재작성 + 재생성 + 대상 테스트 3건 통과

### Task 2: Companion semantic model에서 memoTitle 제거 (D3)

**Red:** ACL 테스트에 schema v1 DTO(`memoTitle` 포함)를 넣어도 mapped domain `Task`에는 `memoTitle` property가 없음을 고정한다. 기존 parser/contract fixture는 v1 필드를 계속 요구·수용해야 한다.

**Green:** `domain/model.ts`의 `Task.memoTitle`과 `acl.ts` 매핑만 제거한다. DTO fixture(`acl`, parser/contract)는 `memoTitle`을 유지하고, domain-only fixture(`model`, task-row, activity-refresh/workspace-monitor 내부 Task)는 제거한다. `packages/contract/src/index.ts`, JSON Schema, CLI 방출, `parseContract.ts`는 변경하지 않는다.

- [x] red 확인 (`memoTitle` semantic 누출 테스트 1건 실패)
- [x] domain/ACL/domain fixture 정리 + typecheck 및 Companion 124 tests 통과
- [x] `pnpm --filter @workbranch/contract test`로 v1 wire 호환 3 tests 유지 확인

### Task 3: board model (D2)

**Red:** `state.ts`에 `buildBoardModel(state)` 테스트 — 매핑(todo/planning→plan, in-progress→execution, review→review), blocked→execution + `blocked: true`, done 카드 제외, 카드 `updatedAt` 내림차순, 다중 project 시 카드에 project 라벨, `notiCount` 보존.

**Green:** `taskStage(task)`(domain) + `buildBoardModel`(application) 구현. 기존 `buildMenuModel` 요약 카운트는 유지.

- [x] red 확인 (`taskStage`/`buildBoardModel` 7건 실패)
- [x] green (typecheck + Companion 131 tests 통과)

### Task 4: UI 재구성 (D4)

`apps/companion/src/ui/StageBoard.tsx`(3컬럼 헤더 + 컴팩트 카드: 이름/blocked 배지/progress/조건부 `+N`), `TaskRow.tsx` → steps/CurrentStep/`<details>` 제거한 meta 행(이름 + StatusToken + RepoChips + 액션 버튼, notification 중복 없음), `App.tsx` 배선. 보드 전용 CSS는 `apps/companion/src/styles/stage-board.css`에 두고 `style.css` import manifest에 등록한다. 테스트는 `renderToStaticMarkup`으로 컬럼 배치·blocked 배지·조건부 `+N`·TaskMetaRow 비중복·StageBoard의 done 부재·TaskMetaRow의 done 유지·액션 버튼 렌더를 고정한다. 미사용이 된 `StepItems` 등은 제거한다 (`domain/steps.ts`는 activity가 쓰므로 유지).

- [x] StageBoard + 카드 테스트 (3컬럼, done 제외, blocked/progress/project/`+N`, full-name wrapping)
- [x] TaskMetaRow/ProjectGroup/App 배선 + 테스트 갱신 (done meta 유지, 액션 계약 유지)
- [x] 스타일 적용, `pnpm lint` + typecheck + Companion 128 tests 통과

### Task 5: 문서·design 동기화

`docs/usage.md`·`docs/usage.ko.md`의 brief 프로토콜 문단(96행 부근: H1을 current Plan title로 설명, 6-시점 안내 축소)과 `docs/specs/0001-workbranch-mvp.md`(schema v1 `memoTitle`은 legacy compatibility field로 유지, 174행 brief 규칙 문구), repo `AGENTS.md`의 Agent-Specific Instructions 문단을 새 프로토콜로 갱신한다. `DESIGN.md`는 current-step cockpit 계약을 stage-first board + repo meta 정보 구조로 교체하고 460px/양 theme 검증 기준을 유지한다. ko/en 동기화 확인.

- [x] docs/spec/DESIGN.md/AGENTS.md 갱신 (en/ko status-only, v1 wire alias, stage-first Main)

### Task 6: 전체 검증

- [x] `pnpm run cli:build` + `/bin/bash -n apps/cli/bin/workbranch`
- [x] `apps/cli/tests/run.sh` 전체 통과
- [x] `pnpm --filter @workbranch/contract test` 통과(schema v1 `memoTitle` 유지)
- [x] `apps/companion`: `pnpm typecheck` + `pnpm lint` + `pnpm test` 통과
- [x] `pnpm --filter @workbranch/companion build` + `pnpm --filter @workbranch/companion tauri build` 통과
- [x] `git diff --check`
- [x] 실제 smoke: 임시 project에서 `workbranch add` → 새 brief/AGENTS.md 확인, `list --global --json`의 schema v1 `memoTitle` 유지 + 새 Companion domain mapping에서 미보존 확인
- [x] 실제 UI QA: native 460px에서 Claude/Codex 양 theme의 Main을 직접 확인 — 3컬럼 overflow 없음, 긴 task명 full-name wrapping/title, blocked·progress·`+N` 표시, done board 부재 + meta row 유지, IDE/Terminal/Finder 동작
- [x] Activity/Settings 양 theme 회귀 확인 — shared header/tab footprint와 기존 기능 유지
