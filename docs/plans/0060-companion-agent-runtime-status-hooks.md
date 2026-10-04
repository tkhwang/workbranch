# 0060 Companion — brief 기반 상태 공유 폐기와 hook 기반 자동 관측 전환

## 문제 / 배경

`TASK-WORKBRANCH.md`를 agent가 직접 갱신해 작업 상태·요약을 공유하는 방식은 기록 비용이 들고, 누락·지연된 기록이 실제 실행 상태와 어긋난다. 사용자 결정에 따라 기존 파일 기반 동작을 전면 폐기하고 provider hook으로 상태와 작업 내용을 자동 수집하는 방식으로 교체한다.

이 계획은 0052의 미구현 Slice C를 대체한다. 초기 0060의 additive agent badge, brief parser 유지, 요약 지침만 제거, prompt-only 표시, tool activity 제외 방침은 폐기한다. 기존 0052의 brief/stage 의존 계약도 이 결정과 충돌하는 범위에서 재정의한다. 2026-10-05 사용자가 `$kickoff 구현하자`로 구현을 요청했다.

## 목표 / 범위

### 확정된 방향

- **`TASK-WORKBRANCH.md` 기반 동작 전면 폐기.** 신규 생성, 상태·요약 쓰기, 읽기·파싱, mtime 정렬, checklist 진행률, 현재 Plan 추출, 표시 fallback, agent 갱신 지침을 제거한다. 같은 내용을 다른 수동 상태 파일에 옮기는 방식으로 대체하지 않는다.
- **상태와 내용 자동 수집.** provider lifecycle/waiting/tool hook에서 실행·대기·턴 종료, 사용자 요청, 현재 도구 활동, 마지막 응답을 얻는다. `Bash: pnpm test`, 파일 읽기/수정 등 관측 가능한 내용이 기본 표시다.
- **runtime과 Git 관측 분리.** 빈번한 tool 이벤트마다 root 전체 Git 조회를 실행하지 않는다. 상태 전이와 최신 activity를 수집·집계하고 UI 업데이트를 병합하는 경로를 설계한다.
- **agent에게 상태 보고용 문서 작성을 요구하지 않는다.** 실제 기능 설계/구현 Plan 문서는 사람이 요청하는 작업 산출물이며 runtime 상태의 source of truth가 아니다.
- **brief 전용 명령/보관 기능 폐기(R2 확정).** `workbranch memo`, 현재의 `workbranch done`, land/finalize/pull의 Plan 보관 질문과 brief 기반 archive 경로를 제거한다. 별도 Plan 등록·완료·보관 체계를 신설하지 않는다. 저장소의 일반 Plan 문서는 그대로 유지한다.
- 기존 Git worktree 생성·조회·land/pull/remove 안전성은 보존한다. hook 턴 종료만으로 작업 완료, merge, archive, 삭제를 실행하지 않는다.
- **구 자료 삭제와 migration 기능 추가(R7-A 확정).** 기존 brief 기반 데이터와 이를 쓰도록 요구하는 생성 지침을 정리하고 새 runtime 방식으로 전환하는 기능을 제공한다. 단순히 구 파일을 남긴 채 무시하는 초기 보존안은 폐기한다. migration 기능을 구현하며 실제 사용자 데이터 정리는 명시적인 apply 경로로만 수행한다.

### 구현 기본값과 남은 검증 경계

- 관측 신선도 기준/집계, provider별 지원 범위와 지연 보장. 실행 상태 4값과 관측 신뢰도 분리는 R3-A로 확정했다.
- 새 전송/저장 구조와 파일 경로, 이벤트 일관성, 구체적인 보존/필드 제한. 최신 내용만 로컬에 보관하는 방향은 R5-A로 확정했다.
- stage 중심 Companion을 대체할 runtime 중심 표시/정렬, 공개 JSON 계약과 버전 전환.

## 현재 근거 / 구현 방향

### 저장소 의존성

- `apps/cli/src/workbranch/lib/task-state.sh`: brief 경로, parser, 상태·체크리스트·요약 추출, mtime, 기본 brief 생성, KO/EN agent 지침을 소유한다.
- `commands/memo.sh`: brief 원문 읽기/덮어쓰기/삭제 명령이다.
- `commands/done.sh`와 `lib/archive.sh`: 현재 `done`은 brief에서 현재 Plan 블록을 추출해 `.workbranch/plans/done/`에 보관하고 원본에서 제거한다. 독립적인 작업 완료 상태 저장 명령이 아니다.
- `commands/land.sh`, `commands/pull.sh`: 위 archive prompt를 호출한다.
- `commands/list.sh`, `commands/doctor.sh`, public schema/DTO, Companion ACL/domain/UI, 문서·테스트에 brief 기반 계약이 연결되어 있다. 구현 전 전체 reference inventory를 만들어 제거 대상을 추적한다.
- `apps/companion/src/domain/model.ts`의 `matrixPlacement`는 기존 stage와 Git 활동으로 행을 분류한다. `StageBoard.tsx`의 idle 행까지 포함해 runtime 표시로 재설계한다.

### hook 기반 자동 수집 범위

provider hook payload에서 사용자 요청, 도구명과 허용된 입력, 도구 실패, 마지막 응답을 수집한다. 명령·파일 경로·검색어 등 관측 가능한 입력의 제한된 발췌를 현재 활동으로 표시한다. 전체 도구 출력과 대화 로그는 저장하지 않는다.

agent가 별도의 상태 문서를 작성할 필요는 없다. 작업 제목은 마지막 사용자 요청을 사용하며 transcript 제목 조회는 범위에서 제외한다. 관측된 도구 활동·턴 종료와 업무 단계·전체 작업 완료는 구별한다.

### 리뷰에서 확인한 필수 보완

1. **waiting 해제:** `PostToolUse`는 승인 직후가 아니라 성공 완료 후 발생한다. 긴 명령·실패·거절·질문 취소·elicitation 응답을 provider별로 확인하고, 실제 관측 가능한 신호에 맞춰 계약을 정한다. https://code.claude.com/docs/en/hooks#hook-events
2. **이벤트 상관관계:** A 도구의 늦은 async 완료가 B 도구의 대기를 해제하면 안 된다. session 단위 빈 marker와 직전 waiting 가드만으로 충분하지 않다. 식별자/세대/중복/역순/캐시 복구 규칙이 필요하다.
3. **마지막 변경 전달:** 현재 `watch_roots.rs:94-106`은 500ms 안의 후속 알림을 재예약하지 않고 버린다. 파일 기반 수집 경로를 선택한다면 trailing 전달 보완이 필수다. 새 전송 경로도 마지막 상태의 전달을 보장해야 한다.
4. **전체 task 노출:** brief 미갱신, clean repo, repo 없는 task, 여러 session/provider 동시 실행도 상태와 작업 내용을 보여야 한다.

## Decision Gates

- [x] **R1. brief 의존 전면 폐기 + hook 기반 자동 관측으로 교체**
  - 사용자 결정: 기존 `TASK-WORKBRANCH.md` 파일 기반 동작은 모두 폐기하고 hook 기반 자동 관측으로 전면 교체.
  - 결과: 기존 D5/D6/D7 및 G5/G6의 prompt-only/brief 유지 전제 폐기. brief를 fallback/source of truth로 사용하지 않는다.
- [x] **R2. 기존 memo/done/archive 기능 폐기 — A 확정**
  - 사용자 결정: A. brief 전용 `memo`, 현재의 `done`, land/finalize/pull archive prompt를 폐기한다.
  - 구현 범위: command dispatch, usage/help, completion, command 구현, archive helper/call sites, 문서·테스트에서 해당 기능을 제거한다. 호출 인자가 조용히 성공하는 호환 no-op은 두지 않는다. 버전 전환 안내는 R6-A에 따른다.
  - 일반 repo Plan 문서는 유지한다. 별도 Plan 등록·완료·보관 기능을 신설하지 않는다. Git lifecycle 명령과 안전성 검사는 유지한다.
  - 기존 brief/archive는 R7의 migration 삭제 대상이다. 기능 제거 코드 변경과 실제 사용자 데이터 migration 실행은 구분한다.
- [x] **R3-A. 실행 상태와 관측 신뢰도 분리 — A 확정**
  - 사용자 결정: 실행 상태는 `running / waiting / finished / idle`로 표현하고, 관측 신뢰도/신선도를 별도 축으로 둔다.
  - `finished`는 턴 종료이며 전체 작업 완료가 아니다. hook 미설치, 수집 실패 또는 오래된 신호를 정상 idle이나 작업 완료로 바꾸지 않는다.
  - 관측을 신뢰할 수 없으면 “상태 확인 불가 · 마지막 관측 N분 전”처럼 표시한다. 마지막 실행 상태는 과거 관측값으로 보존하되 현재 확정 상태처럼 표시하지 않는다.
  - 이벤트가 없는 긴 작업만으로 수집 장애를 단정하지 않는다. 신선도 기준, health 신호의 의미, session 종료/강제 종료 증거는 아래 후속 gate에서 확정한다.
- [x] **R3-B. task 요약 + 펼쳐 보는 session 상세 — A 확정**
  - 사용자 결정: 기본 화면은 task 단위 요약이며 `승인 대기 1 · 실행 중 1`처럼 상태별 session 수를 표시한다. 펼치면 각 agent/session의 상태와 작업 내용을 확인한다.
  - 대표 상태 우선순위는 `waiting > running > finished > idle`이다. 관측 불명 session은 별도로 표시하고 확정 running/waiting 수에 합산하지 않는다.
  - waiting reason/activity는 선택된 session에 귀속한다. 서로 다른 session의 상태와 내용을 결합해 한 agent의 행동처럼 표시하지 않는다. 동률 선택/안정적인 정렬은 구현 규칙으로 문서화한다.
- [x] **R3-C. 신선도·오류 구현 기준 반영**
  - 구현 요청 이후 적용한 기본값: running/waiting은 마지막 관측 후 15분부터 stale, 내용은 7일 보관, 오류/중단 outcome 분리. provider의 관측 공백을 실제 idle/완료로 변환하지 않는다.
  - tool ID가 없는 permission은 활성 tool signature가 유일할 때만 연결하고 모호하면 uncertain이다. 종료된 turn/session과 완료 tool의 지연 이벤트는 되살리지 않는다. 실제 승인 직후 복귀 지연 acceptance는 남아 있다.
- [x] **R4-A. Companion과 독립적인 수집 — A 확정**
  - 사용자 결정: Companion이 종료된 동안에도 hook 수집은 동작한다. 앱을 다시 열면 마지막 상태·내용과 관측 시각을 읽는다.
  - 앱 재시작을 새 agent 활동으로 취급하지 않는다. 오래된 관측은 R3-A의 신뢰도 정책에 따라 표시한다.
  - runtime 저장은 수집기가 자동 관리하는 내부 데이터다. agent의 상태 문서 작성이나 brief fallback을 도입하지 않는다.
  - 이 결정 자체가 상시 daemon 도입을 뜻하지 않는다. hook 직접 기록과 독립 수집 프로세스 중 구체적인 구조는 R4-B2에서 확정한다.
- [x] **R4-B1. runtime 저장 루트 — 중앙 보관 확정 (2026-10-05)**
  - 사용자 결정: `~/.workbranch/runtime/` 아래에 중앙 보관한다.
  - canonical runtime 루트는 `~/.workbranch/runtime/`다. task-local `<task>/.workbranch/runtime/` 및 `<task>/.workbranch/agent.jsonl`은 이번 runtime 저장 경로로 사용하지 않는다.
  - 장점: 작업 공간마다 runtime 파일을 만들지 않고 Companion이 runtime 저장소를 별도로 관측할 수 있다. workspace Git watcher와의 불필요한 결합을 줄인다.
  - 계약상 필요: project/task 이름만으로 식별하지 않고 정규화한 전체 경로 등 충돌 없는 workspace 식별 근거와 provider/session 식별을 저장한다. workspace 삭제/이동/동일 경로 재생성 시 stale 연결과 고아 데이터 정리 규칙이 필요하다. 구체적 하위 파일 배치는 아직 미확정이다.
  - 현재 project registry는 `${XDG_CONFIG_HOME:-$HOME/.config}/workbranch-companion/projects.md`에 있고 기존 activity log도 별도 XDG state 경로를 쓴다. 이번 runtime 위치 결정만으로 기존 설정/로그 전체를 이동하지 않는다.
  - Status: resolved. 하위 파일명/배치와 저장 원자성·복구 방식은 R4-C2에서 확정한다.
- [x] **R4-B2. hook의 경량 수집기가 직접 저장 — A 확정**
  - 사용자 결정: 이벤트가 발생할 때 실행되는 경량 수집기가 `~/.workbranch/runtime/`를 직접 갱신한다. 상시 백그라운드 수집 서버를 도입하지 않는다.
  - Companion 실행 여부에 의존하지 않는다. runtime 갱신은 workspace Git 전체 조회를 유발하지 않는 별도 관측 경로로 처리한다.
  - 동시 기록, 이벤트 식별/순서/중복, 중간 종료, 원자적 갱신과 복구 규칙을 저장 계약에 포함한다. 파일 직접 기록만으로 이벤트 순서나 원자성이 저절로 보장된다고 가정하지 않는다.
  - hook마다 실행되는 비용은 실제 provider payload로 p50/p95와 연속 tool call 부하를 측정한다. 전체 CLI 기동/전체 로그 재파싱을 기본 fast path로 삼지 않는다.
- [x] **R4-C1. 별도 Rust 수집기와 소스 위치 — A 확정**
  - 사용자 결정: 경량 수집기는 별도 Rust 실행 파일로 배포하고 소스 루트는 `apps/agent-runtime/`에 둔다. Node 기반 `packages/agent-runtime/` 대안은 채택하지 않는다.
  - provider hook이 호출할 독립 실행 파일이며 Companion을 실행하거나 상시 서버를 띄우지 않는다. 배포 바이너리 사용자가 Node나 Rust toolchain을 설치하도록 요구하지 않는다.
  - 플랫폼/CPU별 build·release artifact, 설치/업데이트, hook에서 실행 파일을 찾는 규칙과 CLI/Companion/collector 호환성 검사를 구현 범위에 포함한다. 지원 플랫폼 범위는 기존 배포 계약을 확인해 문서화한다.
  - JSON 처리, 제한된 최신 내용 저장, 이벤트 상관관계/동시성/복구는 수집기가 소유한다. 기존 dependency-free Bash extractor 제약을 수집기에 적용하지 않는다.
  - 실제 hook payload로 기동/처리 p50/p95와 연속 tool call 부하를 검증한다. Rust 선택 자체를 성능 통과 증거로 삼지 않는다.
- [x] **R4-C2a. 내장 SQLite 저장 — 확정**
  - 사용자 결정: `~/.workbranch/runtime/state.sqlite3`에 runtime 상태와 제한된 최신 내용을 저장한다. session별 JSON 파일 대안은 채택하지 않는다.
  - SQLite 라이브러리는 Rust 수집기 배포에 포함한다. 사용자에게 별도 DB 서버, sqlite3 CLI, 시스템 SQLite 개발 패키지 설치를 요구하지 않는다.
  - DB 생성·스키마 버전 관리·업그레이드·보존 한도 정리는 workbranch가 소유한다. Companion 없이도 수집기가 필요한 초기화를 수행할 수 있어야 한다.
  - workspace/provider/session별 상태와 최신 내용을 트랜잭션으로 갱신한다. SQLite의 동시성 제어와 별개로 이벤트 식별자·세대·역순/중복 처리 규칙을 명시한다.
  - 쓰기 경합/잠금 대기는 hook 시간 예산 안에서 제한하고 실패가 agent를 방해하지 않게 한다. 중간 종료 후 복구, 동시 writer, DB schema 비호환과 정리 중 쓰기를 테스트한다.
  - DB와 SQLite sidecar 파일을 포함한 runtime 디렉터리는 사용자 전용 접근권한으로 관리한다. Companion의 갱신 감지는 실제 선택한 journal 모드에 맞춰 설계하고 마지막 변경 누락을 검증한다.
- [x] **R4-C2. 파일 배치·provider 설치 코드 반영**
  - 확정된 `apps/agent-runtime/` 아래 manifest/source/test/fixture, provider adapter의 정확한 이름과 배치를 제안한다. runtime DB 경로는 R4-C2a로 확정했으며 추가 영속 파일 도입 시 용도와 경로를 명시한다. CLI migration 소스/fixture도 포함한다.
  - provider-native plugin을 우선 검토하되 최신 provider 기능/버전과 실 설치·trust 동작을 검증한다. 사용자 설정 직접 수정이나 trust 자동 우회는 기본 경로로 삼지 않는다.
  - source of truth와 일관성·복구 계약 없이 별도 marker를 도입하지 않는다.
- [x] **R5-A. 최신 내용만 제한적으로 로컬 보관 — A 확정**
  - 사용자 결정: session별 마지막 요청, 최신 도구 활동, 마지막 응답을 길이 제한하여 로컬에 보관한다. 전체 대화·도구 출력과 과거 내용 탐색 기능은 이번 범위에 포함하지 않는다.
  - 상태 복구용 이벤트 기록은 내용 이력과 분리하고 별도 보존 한도를 둔다. 과거 prompt/응답이 이벤트 log에 무제한 누적되는 우회 이력을 만들지 않는다.
  - 최신 내용은 원문에서 추출한 제한된 발췌이며 별도 LLM 요약 생성을 요구하지 않는다. 저장·표시에는 동일한 길이 제한을 적용하고 잘린 내용임을 표시한다.
  - 이 결정은 임의의 tool input 전체 수집을 허용하지 않는다. provider별 필드 허용 목록, 민감 정보 제외, 정확한 길이·보존 한도와 로컬 파일 접근권한은 구현 전 계약으로 구체화한다.
- [x] **R5-B. hook-only 수집 구현 기준 반영**
  - 구현 기본값으로 transcript 조회/enrichment는 제외했다. 마지막 요청을 제목으로 사용하며 prompt/activity/response는 각각 500/240/2000자로 제한한다. 인증정보 패턴이 포함된 발췌는 전체 생략한다. 필터는 임의의 자연어 비밀을 모두 판별하는 보안 경계가 아니다.
  - 임의의 tool output/전체 대화는 저장하지 않는다. 명령 배열과 첫 질문 텍스트처럼 명시적으로 허용한 필드만 activity로 만든다.
- [x] **R6-A. 호환 버전 업데이트 안내 — A 확정**
  - 사용자 결정: 새 공개 계약과 호환되지 않는 CLI/Companion 조합에서는 호환 버전으로의 업데이트를 안내한다. brief fallback이나 Git 정보만 가져오는 제한 호환 경로를 유지하지 않는다.
  - public schema version은 새 계약을 명확히 구분하도록 변경한다. 정확한 새 DTO/schema와 지원 버전 범위를 문서·fixture·parser에서 함께 정의한다.
  - 새 Companion은 알 수 없는/구 계약을 일반 parse 오류와 구별해 필요한 업데이트를 안내한다. 구 Companion의 동작은 소급 변경할 수 없으므로 배포/설치 안내에 호환 조합과 함께 업데이트할 필요를 명시한다.
  - 구 계약을 흉내 내기 위해 삭제된 brief 필드에 가짜 status/progress 값을 채우지 않는다. 제거 명령에 대해서도 호환 no-op을 만들지 않는다.
- [x] **R6-B1. runtime 중심 Companion UI 재설계 범위 — 사용자 요청 반영 (2026-10-05)**
  - 사용자 요청: 실행 상태와 작업 내용을 중심으로 Companion UI를 함께 재설계한다. 기존 stage 보드 위에 badge만 추가하는 범위가 아니다.
  - Companion의 정보 구조와 표시 계약을 아래 UI 절에 구체화했다. task 요약/session 상세, 관측 신뢰도 분리, 최신 내용만 보관한다는 기존 결정은 유지한다.
  - 구체적인 시각 토큰과 컴포넌트 배치는 구현 전 화면 시안에서 검증한다. 새 source 파일명/배치는 R4-C2에서 묶어 확정한다.
- [x] **R6-B2. wire 형식과 UI fixture 검증 반영**
  - 새로운 schema 버전, runtime 객체 및 관측 신뢰도 필드, provider별 capability와 호환 오류 계약을 구현 전 문서화한다.
  - 아래 UI 적용안을 기존 DESIGN.md와 대조해 최종 디자인 토큰/레이아웃 계약으로 반영하고 실제 창에서 검증한다.
- [x] **R7-A. 기존 데이터·작성 지침 삭제 및 migration 기능 추가 — 사용자 요청 확정 (2026-10-05)**
  - 사용자 결정: 기존 `TASK-WORKBRANCH.md`, 구 저장 데이터, 이를 작성하도록 요구하는 AGENTS.md 설정 등을 제거하고 새 기능으로 전환하는 migration 기능을 이번 범위에 포함한다. 원위치 보존/무시만 하는 이전 추천은 폐기한다.
  - 삭제 inventory: 관리 대상 workspace의 `TASK-WORKBRANCH.md`, 기존 brief archive인 `<task>/.workbranch/plans/done/`, 식별 가능한 구 상태 데이터, `~/.workbranch`에 존재하는 구 기능 데이터. 새 `~/.workbranch/runtime/` 데이터와 무관한 설정/알림까지 재귀 삭제하는 것으로 구현하지 않는다.
  - 현재 환경 확인: `~/.workbranch`는 존재하지 않는다. 현행 코드의 brief/archive는 task root와 `<task>/.workbranch/`에 있고 project registry는 XDG config 경로에 있다. migration은 실제 경로 inventory와 구 형식 판별을 사용하고 홈 디렉터리에 구 자료가 없으면 정상적으로 건너뛴다.
  - 생성 AGENTS.md의 brief 기록·status 전환·요약 갱신·done/archive 안내를 제거한다. repo-local 규칙 준수와 Git root 안내 등 현재도 유효한 지침, nodeterm 등 타 도구 블록, 사용자 작성 내용은 보존한다. 파일 전체가 폐기 대상 안내뿐이면 제거할 수 있으나 비관련 안내가 섞인 파일을 통째로 삭제하지 않는다.
  - 새 task의 generator, CLI help/completion, repo 문서·테스트도 함께 변경해 폐기한 지침이 재생성되지 않게 한다. 이미 열린 agent session이 읽은 지침은 디스크 수정만으로 취소되지 않으므로 재시작/재로드 필요성을 결과에 안내한다.
  - migration은 삭제/지침 수정/새 수집 준비/검증 결과를 보고한다. 기존 brief 내용을 가짜 hook 이력이나 현재 실행 상태로 변환하지 않는다. 실제 hook 관측 전에는 미관측으로 표시한다.
  - 검증: 실제 구 KO/EN 지침과 사용자/타 도구 내용이 섞인 fixture, 구 파일 부재, 경로 충돌, 부분 실패 후 재실행, 새 runtime 데이터 보존, 삭제 완료 후 구 지침 재생성 없음. 재실행은 완료한 정리를 중복 수행해 손상을 만들지 않아야 한다.
- [x] **R7-B. CLI migration + Companion 감지/실행 연동 — A+B 확정**
  - 사용자 결정: A의 CLI 기능을 만들고, 업데이트 후 B의 Companion 감지가 같은 A를 실행하도록 연결한다. 두 경로에서 migration 정리 로직을 중복 구현하지 않는다.
  - 확정 CLI: `workbranch migrate agent-runtime --dry-run` / `workbranch migrate agent-runtime --apply`. 직접 CLI로도 실행할 수 있다.
  - Companion은 호환 CLI 확인 후 read-only dry-run으로 migration 필요 여부와 대상/예외를 감지한다. 업데이트 후 첫 실행을 포함하며 이전 부분 실패나 새로 등록된 구 workspace도 다시 감지할 수 있어야 한다.
  - 기존 B의 사용자 실행 선택 흐름을 유지한다: 감지 결과를 안내하고 전환 실행을 선택하면 동일 CLI의 `--apply`를 호출한다. 앱의 일반 list 조회가 암묵적으로 삭제를 수행하지 않는다.
  - dry-run/apply의 대상 범위와 결과 형식을 공유한다. 앱은 CLI 결과를 표시하고, 실제 정리와 검증은 CLI가 소유한다. apply 직전 대상을 재검증하고 변경/실패는 결과에 보고한다.
  - CLI/App 동시 실행의 중복 적용을 막고, 부분 실패 후 재시도할 수 있게 한다. migration 완료와 provider hook 설치/trust/첫 관측 상태를 구별해 표시하며, provider trust를 자동 우회하지 않는다.
  - 앱 업데이트 여부만으로 완료를 판정하지 않는다. apply 후 dry-run으로 잔여 구 데이터를 재확인하고 완료/부분 실패를 표시한다. 새 runtime 데이터 및 무관한 설정 보존을 검증한다.
  - 명령명은 확정했다. 구현 파일/fixture 경로 및 앱 연동의 structured result 계약은 R4-C2/R6-B2에서 구체화한다.

## Companion UI 재설계 — runtime 현황과 session 상세

### 설계 범위

- 개입 대기, 실행 중, 턴 종료 순으로 상태를 묶고 provider·repo/branch·요청 제목·도구 활동·마지막 관측 시각을 함께 표시한다.
- 일관된 작은 둥근 모서리, 중성 표면의 명도 차와 얇은 경계, 상태별 강조색으로 정보 위계를 표현한다. 구체적인 토큰은 기존 Companion 테마와 맞춘다.
- 브라우저 fixture 검증과 설치된 앱의 실제 provider 연동 검증은 구분한다. 검증 결과와 남은 acceptance는 구현 결과 절에 기록한다.
- 범위는 로컬 agent 현황을 읽는 제품 화면이다. 마케팅 페이지, 클라우드 로그인, 모바일 push, 원격 allow/deny 기능은 포함하지 않는다.

### 시각·정보 방향

- **시각 방향:** 작은 창에서 읽는 조밀한 작업 관제 화면. 중성 바탕 위에서 개입 대기와 현재 활동이 먼저 읽힌다. provider 테마는 정체성, 상태 색은 의미를 담당해 분리한다.
- **정보 순서:** 전역 상태 요약 → 상태별 task 목록 → 펼쳐 보는 session 상세 → Git 사실과 기존 실행 도구.
- **상호작용:** 상태와 activity 텍스트가 갱신되어도 펼침/선택/focus를 유지한다. 갱신에는 짧은 opacity 피드백만 사용하고 reduced-motion에서는 정적으로 표시한다. 이벤트마다 행 전체가 튀거나 도구 activity만 바뀌어도 목록 순서가 흔들리지 않게 한다.
- **CSS 전략:** 기존 CSS 파일과 theme custom property 구조를 사용한다. 새 CSS 프레임워크를 추가하지 않는다. 작은 고정 반경과 명도 단계로 표면을 구분하며 장식적 gradient/과도한 shadow를 도입하지 않는다. 정확한 radius/color/font 값은 시안 검증 후 DESIGN.md에 기록한다.

### Main 화면

1. 상단에는 project/task 수와 `대기 N · 실행 N · 턴 종료 N · 관측 불명 N` session 요약을 표시한다. task 수와 session 수를 혼동하지 않도록 단위를 구분한다.
2. 기존 `PLAN / EXECUTION / REVIEW` lifecycle 그룹을 runtime 그룹으로 교체한다. 제안 순서는 **내 응답 대기 → 실행 중 → 턴 종료 → 관측 불명/미관측 → 비활성**이다. 대표 상태는 R3-B를 따른다. 정상 관측 session과 관측 불명 session이 섞인 task는 한 번만 표시하고 불명 수를 함께 노출한다.
3. task 행은 프로젝트/작업 공간, 요청 제목, provider 표식, session 상태별 수, 대표 session의 대기 사유 또는 최신 activity와 상대 시각을 표시한다. 예: `승인 대기 1 · 실행 중 1`, `Claude · Bash: pnpm test`.
4. task를 펼치면 session마다 provider, 상태, 마지막 관측 시각, 요청, 최신 도구 활동, 제한된 마지막 응답을 읽는다. 상태/내용의 session 귀속을 유지하고 전체 대화 이력 UI를 만들지 않는다.
5. `finished`의 표시명은 **턴 종료**로 두어 전체 작업 완료나 품질 검증 통과를 암시하지 않는다. 테스트 결과 같은 내용은 실제 수집된 응답의 발췌로만 표시하고 별도 검증한 성공 badge로 승격하지 않는다.
6. 대기에는 사유와 관측 시각을 표시한다. 복귀 신호가 없거나 관측이 오래되면 현재 대기를 확정하지 않고 R3-A의 신뢰도 표기를 사용한다. 수집 미설치/미관측을 idle로 숨기지 않는다.
7. repo/branch, dirty/ahead/behind, 최근 commit은 보조 정보로 배치한다. 기존 IDE/Terminal/Finder 실행과 repo note 기능은 유지하되 runtime 읽기를 가리지 않도록 상세 영역에 배치한다. 기존 weekly limits 및 base repo 기능도 삭제하지 않으며 보조 영역 배치를 함께 검증한다.
8. 제목 추출은 마지막 요청을 사용할 수 있어야 한다. transcript 제목 enrichment는 R5-B의 구현 기본값에 따라 제외한다.

### 연결·migration·오류 상태

- 업데이트 후에는 호환 CLI 확인 → 공통 migration dry-run → 대상/결과 안내 → 같은 CLI apply 실행 → 잔여 항목 재확인의 R7-B 흐름을 UI에 연결한다.
- provider별 미설치, trust 대기, 수집 오류, 첫 이벤트 대기를 구분한다. migration 성공을 hook 수집 성공과 동일시하지 않는다.
- 비호환 버전은 업데이트 안내를 제공한다. 일부 root/DB 조회 실패가 건강한 다른 task를 숨기지 않도록 실패 범위를 명시한다.
- 수집된 명령/응답은 표시 데이터이며 실행 버튼이나 HTML로 해석하지 않는다. 원격 승인 버튼은 이번 UI 범위에 없다.

### 반응형·접근성·검증

- 기존 native 창 기본 520×760, 최소 너비 460px를 기준으로 단일 열을 유지한다. 좁은 창에서는 여러 상태를 가로 3열로 나누지 않는다.
- 긴 요청은 행에서 제한해 표시하되 상세에서는 저장한 발췌 전체를 읽을 수 있다. 명령/경로는 monospace, 숫자/상대 시각은 tabular numbers를 사용한다. theme별 대비와 가장 큰 폰트 설정도 확인한다.
- session 펼침은 native button 및 aria-expanded를 사용하고 키보드 focus를 보존한다. 색상 외에 상태명/사유로 의미를 전달하고 모든 tool 이벤트를 live region으로 읽어주지 않는다.
- 테스트에는 혼합 session, 대기 사유, stale/unknown, 긴 명령, 빈 요청/응답, 실패/취소, clean/repo-less task, 업데이트 중 열린 상세 유지, migration 부분 실패를 포함한다.
- 구현 시 실제 UI에서 두 테마, 460px/520px, overflow/행 내부 잘림/선택 및 펼침 상태 유지/키보드 조작을 확인한다. DOM/정적 렌더 테스트와 실제 visual QA 증거는 구분한다.

## Status

Verification Pending — 구현과 로컬 최종 회귀 검증을 완료했다. provider 실설치/trust, 실제 Companion live 데이터, cross-platform release, 사용자 자료 migration apply는 별도 acceptance로 남는다. CPQ 전용 경로는 해당 없음; [backend]는 CLI/Rust/contract, [frontend]는 Companion이다.

## Progress

- [x] 초기 0060 및 현행 코드 리뷰
- [x] hook 기반 activity/응답 수집 범위 확인
- [x] 전면 교체 결정 반영 및 상충하는 초기 범위 폐기
- [x] R2: memo/done/brief archive 기능 폐기 확정
- [x] R3-A: 실행 상태 4값과 관측 신뢰도 분리 확정
- [x] R3-B: task 요약과 펼쳐 보는 session 상세 확정
- [x] R5-A: 최신 내용의 제한적 로컬 보관 확정
- [x] R4-A: Companion 종료 중에도 독립 수집 확정
- [x] R4-B1: `~/.workbranch/runtime/` 중앙 보관 확정
- [x] R4-B2: hook 경량 수집기의 직접 저장 확정
- [x] R6-A: 비호환 버전 업데이트 안내, legacy fallback 없음 확정
- [x] R7-A: 구 데이터/작성 지침 삭제와 migration 기능 추가 확정
- [x] R7-B: CLI migration과 Companion 감지/실행 공유 확정
- [x] R4-C1: `apps/agent-runtime/`의 독립 Rust 수집기 확정
- [x] R4-C2a: 내장 SQLite와 `~/.workbranch/runtime/state.sqlite3` 확정
- [x] R6-B1: runtime 중심 UI 재설계 적용안 반영
- [x] R3-C/R4-C2/R5-B/R6-B2 구현 기준과 로컬 검증 반영
- [x] 결정에 맞춘 slice/파일 inventory 반영
- [x] 사용자 kickoff 구현 요청 후 backend → frontend 순서로 구현 진행

## 구현 기준 및 리뷰 (2026-10-05)

- 사용자 확정 방향과 실제 코드/공식 hook 계약을 재검토했다. 아래는 구현 범위 안의 세부 기본값이며 새로운 사용자 승인으로 표기하지 않는다.
- 제목/응답은 hook payload만 사용한다. transcript enrichment는 제외하여 별도 대화 로그 접근을 만들지 않는다.
- public list schema는 2로 변경한다. task는 identity/path/repos/notiCount만 담고 brief 필드를 제거한다. 별도 runtime snapshot(schemaVersion 1)으로 session 상태를 읽어 Git 조회와 분리한다.
- 경량 수집기는 `apps/agent-runtime/{Cargo.toml,Cargo.lock,src/{main,lib,store,event,migration}.rs,tests/runtime.rs}`에 구현한다. 기존 Rust/TS 파일을 가능한 한 재사용한다. CLI 연결은 `apps/cli/src/workbranch/commands/runtime.sh`, 테스트는 `apps/cli/tests/cases/agent-runtime.sh`; plugin은 기존 제안 경로인 `integrations/agent-events/{claude-code,codex}/`를 사용한다.
- hook은 짧은 동기 기록을 기본값으로 하여 같은 session의 순차 hook 기록 순서를 보존한다. 관측기는 permission 결정/추가 모델 context를 반환하지 않으며 실패는 agent 진행을 막지 않는다. 다른 session의 동시 쓰기는 SQLite transaction과 bounded busy timeout으로 처리한다.
- provider/session/agent 및 canonical workspace 경로로 구분한다. tool ID가 있는 완료만 해당 tool 대기를 해제하며 PermissionRequest에 ID가 없으면 일치하는 활성 tool을 유일하게 식별할 때만 연결한다. 모호하면 관측 신뢰도를 낮춘다. Codex의 turn_id와 종료된 turn 기록을 이용해 늦은 이벤트가 다음 turn을 덮지 않도록 한다.
- 기본 최신 내용 한도: prompt 500자, activity 240자, response 2000자. 전체 tool output/transcript는 보관하지 않는다. 민감 키/password/token 및 인증 헤더는 제외하고 제한된 도구 입력만 발췌한다.
- running/waiting이 15분 이상 관측되지 않으면 현재 실행 상태를 확정하지 않고 stale로 표시한다(죽었다고 단정하지 않음). 종료된 session 최신 내용은 7일 보관 후 정리한다. 정확한 벤치마크/실 provider acceptance 전에는 freshness/latency를 실측 완료로 주장하지 않는다.
- [backend] 수집/저장/정규화 및 migration의 실패·동시성·경계를 먼저 검증한 뒤 [frontend]를 연결한다. smoke/fixture와 실제 provider/native UI acceptance는 분리한다.

## 구현 순서 초안

1. **계약 및 한 provider end-to-end 경로:** 실제 fixture → 정규화 → 일관성 있는 session 상태/activity → CLI/API → Companion 표시. 실제 세션의 도구 실행·대기·실패·턴 종료를 확인한다.
2. **수집기 배포·provider 확장과 설치:** Rust 수집기의 플랫폼/CPU별 배포와 설치·업데이트·실행 파일 해석 및 버전 호환을 구현한다. 지원 이벤트/식별자 capability를 비교하고, 설치·해제·trust·재시작·복구를 검증한다. provider별 지원 차이를 숨기지 않는다.
3. **runtime UI 재설계와 brief 전면 제거:** runtime 중심 UI 계약에 따라 기존 stage 그룹을 runtime task 목록/session 상세로 교체하고 DESIGN.md를 동기화한다. reader/writer/generator, memo/done/archive 제거(R2 확정), list/doctor, contract/ACL/UI, 문서와 테스트를 함께 전환한다. clean task와 idle 행도 포함한다.
4. **기존 workspace migration:** R7에 따라 구 데이터 삭제·혼합 AGENTS.md에서 폐기 지침 제거·새 수집 준비·검증/결과 보고를 구현한다. CLI dry-run/apply와 Companion 감지/실행을 연결한다. inventory와 미리보기, CLI/App 동시 실행, 부분 실패 후 재실행, 새 runtime 보존을 검증한다. agent에게 별도 상태 문서 작성을 요청하지 않는지 확인한다.
5. **통합 검증:** 이벤트 폭주·역순·중복·다중 session·수집 실패·재시작·마지막 이벤트 전달과 mixed-version 동작을 검증한다.

## 검증 및 성공 기준

- brief가 없는 신규 task와 기존 brief가 남은 task 모두, brief 내용/mtime 변경에 영향받지 않고 runtime 상태·요청·activity·마지막 응답을 표시한다.
- agent가 상태 보고용 파일을 작성하지 않아도 기능이 성립한다. 생성 지침에 brief 갱신 의무가 없다.
- 파일 편집 없는 조사·질문 세션, clean/repo-less task, 다중 provider/session을 표시한다.
- 승인 후 긴 실행·실패·거절·취소와 async 교차 순서에서 거짓 대기 해제 또는 확정되지 않은 작업 완료를 표시하지 않는다. 관측 한계와 신선도는 R3에 따른다.
- 빈번한 tool 이벤트가 Git/root 전체 refresh를 반복 유발하지 않는다. fast path p50/p95, 이벤트→UI 지연, refresh 횟수와 CPU를 실측하고 R3/R4에서 확정한 예산과 비교한다.
- 수집 실패가 agent를 방해하지 않는다. stdout/stderr·timeout·실패 처리는 provider별 실 실행으로 확인한다.
- CLI source 수정 후 `apps/cli/scripts/build-workbranch.sh`로 generated CLI 재생성, `./apps/cli/tests/run.sh` 실행.
- contract test, Companion test/typecheck/lint/build, collector 및 변경한 Companion Rust의 cargo test/clippy, git diff --check. 수집기 배포 artifact와 CLI 단독 설치/Companion 종료 상태에서 실제 hook 실행도 검증한다.
- 실제 Companion 460×680에서 테마 양쪽, 긴 내용, overflow, idle/활성/session 전이와 접근성 확인.
- unit fixture 증명과 provider 설치·실세션·실 UI 증명을 구분해 기록한다.

## Specs 영향

`docs/specs/0001-workbranch-mvp.md`, CLI usage/completion, `docs/ai-agents{,.ko}.md`, `docs/usage{,.ko}.md`, README 관련 설명, DESIGN.md, public schema/DTO, 0052 Slice C를 최종 결정과 동기화한다. hook 기반 runtime 계약을 별도 spec으로 분리할 경우 R4에서 정확한 파일명/경로를 먼저 확정한다.


## 구현 결과 및 검증 증거 (2026-10-05)

### [backend] CLI / Rust / contract

- [x] 내장 SQLite Rust 수집기: 최신 내용, workspace incarnation, 대기 상관관계, 종료/중복 이벤트 가드, stale 관측 분리.
- [x] CLI `runtime --json`, `hooks install|status|uninstall`, `migrate agent-runtime --dry-run|--apply [--global]` 연결. memo/done/brief parser/archive prompt 제거 및 generated CLI/mirror 재생성.
- [x] migration은 exact 생성 지침만 제거하고 사용자 H2/코드 예시/다른 도구 블록·새 runtime을 보존한다. symlink 거부, partial error, 프로세스 잠금과 재실행 처리.
- [x] 공개 list schema 2, 독립 runtime schema 1 및 live collector contract 테스트. 수집기 snapshot 읽기는 read-only DB 연결이다.
- [x] root 및 기존 apps/cli installer 경로를 단일 설치 로직으로 연결. SQLite 포함 바이너리 복사/플랫폼별 release asset·checksum 검증·Homebrew build/CI 정의 추가.
- [x] Rust regression 16개, contract 8개, CLI 최종 전체 265개 통과.
- [x] Claude plugin manifest validator, provider CLI argv stub, shell syntax/ShellCheck 검증. 실제 provider 설정은 수정하지 않았다.

### [frontend] Companion

- [x] runtime 우선 그룹, task 요약/session 상세, 최신 활동/응답, 관측 불명 표시. repo notes/launcher/base repositories/weekly limits 유지.
- [x] Git 조회와 별개인 순차 1초 runtime polling. DB 파일 watcher의 마지막 이벤트 누락에 의존하지 않는다. 기존 Git watcher 주기는 이번 구현에서 변경하지 않는다.
- [x] migration CLI 감지·실행·부분 실패 결과 표시. workspace identity 변경 및 수동 refresh에서 재감지한다.
- [x] 전체 UI 210개, typecheck/build 통과. lint error/warning 없음(기존 computed-key 관련 info는 유지). Tauri Rust 36개와 clippy 통과.
- [x] native Chrome에서 460 CSS px fixture의 Claude/Codex 테마, 긴 제목·도구 내용, session 펼침, launcher 배치 확인. waiting→running 그룹 이동 시 열린 session 상세 유지 확인. 렌더 중 발견한 카드 전체 색 적용과 launcher 겹침 수정.

### 리뷰 / 실측 / 남은 acceptance

- [x] check 스킬의 보안·아키텍처 독립 리뷰. 인증정보 발췌, 사용자 지침 보존, 종료 이벤트 부활, workspace 재생성 귀속, UI remount, migration 재감지 지적을 수정하고 재검토했다. 마지막 리뷰에서 새 P1/P2 없음.
- [x] release 수집기 로컬 기동+prompt 저장 benchmark: warm-up 5회 제외 55개, p50 4.6ms / p95 5.17ms. 이는 로컬 fixture이며 provider end-to-end latency 보장은 아니다.
- [ ] 실제 Claude/Codex plugin 설치·trust·질문/permission/중단·동시 session 수신 acceptance. native provider 설정을 변경하거나 trust를 우회하지 않았다.
- [ ] 실제 설치된 Companion 창의 live 데이터 QA. 브라우저 fixture와 native Rust tests는 실제 앱/provider acceptance를 대체하지 않는다.
- [ ] macOS Intel/Linux release artifact 생성 및 다운로드 설치 검증, GitHub CI/release upload. workflow만 구현했으며 배포/업로드하지 않았다.
- [ ] 실제 사용자 workspace에 migration apply 실행. 지금까지 apply 검증은 격리 fixture에 한정했다.

이 저장소는 CPQ backend/frontend 구조가 아니므로 CPQ generated package mirror/DA-apis는 해당 없음. 이 작업의 wire 변경은 workbranch list/runtime JSON 계약이다. 공개 릴리스·commit·push·사용자 자료 migration은 실행하지 않았다.


### 최종 closeout

- CLI 전체 265 / collector 16 / contract 8 / Companion TS 210 / Tauri Rust 36 테스트 통과.
- Companion typecheck/build/lint, collector/Tauri clippy, ShellCheck, Bash syntax, generated CLI parity, git diff --check 통과. lint의 기존 info 80개는 오류/경고가 아니다.
- 디스크 부족으로 중단된 이전 실행은 통과 증거에서 제외하고 공간 확보 뒤 전체 검증을 재실행했다.
- Claude manifest는 기본 `hooks/hooks.json` 자동 탐색만 사용하여 같은 파일의 중복 선언을 제거했다. 실제 설치와 trust acceptance는 여전히 별도다.
- 임시 UI preview 소스는 검증 후 제거했다. commit/push/release 및 실제 사용자 데이터 apply는 실행하지 않았다.


### 후속 수정 — 구 CLI 선택과 runtime 오류 노출

- 사용자 스크린샷에서 새 개발 Companion이 Homebrew의 구 CLI를 선택해 schema mismatch와 `unknown command: runtime`이 함께 발생했다. raw Usage 전체가 UI에 노출되는 것도 확인했다.
- debug build는 명시적인 registry override 다음으로 같은 checkout CLI를 우선한다. source checkout CLI는 같은 checkout의 debug/release 수집기를 찾는다. 설치된 release 앱의 명시적 버전 호환 요구는 유지하며 전역 Homebrew/registry 설정은 변경하지 않는다.
- list schema 호환 확인 후에만 runtime polling과 migration 감지를 시작한다. 비호환 시 polling을 멈추고 짧은 업데이트 안내를 표시한다. 일반 오류도 원시 전체 도움말 대신 제한된 메시지로 표시한다.
- RED: 기존 resolver가 `/opt/homebrew/bin/workbranch`를 반환하는 실패와 Usage 표시 회귀 재현. GREEN: UI 212개, resolver 관련 Rust 5개, typecheck/build/lint 통과. 실제 checkout CLI로 schema 2 / 3 projects / 7 tasks / errors 0 및 독립 runtime snapshot exit 0 확인.
- native 앱 UI 재확인은 CUA timeout으로 완료하지 못했다. 개발 서버의 새 debug process 재기동은 확인했다. 실제 사용자 migration apply/전역 CLI 교체는 수행하지 않았다.


## 확장 제안 — Companion onboarding / Settings 연결 관리 (2026-10-05)

사용자 제안: Companion의 첫 실행과 Settings에서 `Install CLI`, `Connect AI Agent: Claude / Codex / Grok`를 제공한다. 기존 구현에는 Settings의 설치/연결 관리가 없고 CLI `hooks` 명령만 있다. CLI installer 자동 hook 연결 대신 아래 Homebrew onboarding 흐름을 구현한다.

### 제안한 사용자 흐름

1. **Install CLI:** 미설치/비호환을 감지하고 CLI와 runtime 수집기를 함께 설치 또는 업데이트한다. 실제 선택할 실행 경로와 호환성을 다시 검사한다. CLI가 없어도 실행할 수 있도록 bootstrap은 Companion의 native port가 소유한다.
2. **Connect AI Agent:** Claude Code, Codex, Grok Build를 각각 표시하고 설치된 agent에 연결/다시 연결/연결 해제를 제공한다. agent 프로그램 자체의 설치와 계정 로그인은 이 연결 동작에 포함하지 않는다.
3. **Verify:** hook 설정 완료, provider trust 대기, 첫 이벤트 수신 대기, 수신 확인을 구별한다. 설치 명령 성공만으로 실행 상태 수집을 확인했다고 표시하지 않는다.
4. Settings에서도 같은 연결 관리와 상태를 재사용한다. onboarding 전용 설치 로직을 중복 작성하지 않는다. 미설치/비호환은 정상적인 설정 화면으로 처리하며 원시 Usage 오류를 표시하지 않는다.
5. workbranch는 로컬 기능이므로 별도 서비스 계정 로그인 단계를 추가하지 않는다. provider의 native trust를 자동 우회하지 않는다. 기존 사용자 hook은 보존하고 workbranch 소유 연결만 관리한다.

### Grok 근거와 경계

- 로컬 `grok --version`: `grok 1.0.46 (2765805b9442) [stable]`. 사용자 환경의 Grok Build를 지원 대상으로 해석한다.
- 공식 문서: https://docs.x.ai/build/features/skills-plugins-marketplaces 및 https://docs.x.ai/build/cli/reference . Grok은 lifecycle hook/plugin과 CLI plugin 관리 명령을 제공한다.
- Grok은 Claude 설정/plugin도 발견할 수 있으므로 기존 Claude wrapper 재사용만으로 Grok을 Claude로 오인하거나 중복 수집하지 않도록 별도 adapter와 귀속 검증이 필요하다. payload/이벤트/식별자 차이는 구현 전 fixtures로 고정한다.
- 현재 provider enum/DB ingest/parser/UI/manifest는 Claude·Codex만 지원한다. Grok 행만 추가하고 연결 기능이 완성됐다고 표시하지 않는다.

### 설치 공급 방식 — Homebrew로 전환 (사용자 제안 반영)

- 사용자는 `brew install --cask tkhwang/tap/workbranch-companion`으로 Companion을 설치한다.
- Companion의 onboarding/Settings에서 CLI 설치 버튼을 누르면 native port가 `brew install tkhwang/tap/workbranch`를 실행한다. 업데이트는 해당 formula만 대상으로 `brew upgrade tkhwang/tap/workbranch`를 실행한다.
- 현재 공개 formula 이름은 `workbranch`다. `workbranch-cli`는 역할 명칭으로 해석하며 이번 기능에서 package/명령을 임의로 rename하지 않는다.
- CLI formula는 `workbranch`와 `workbranch-agent-runtime`을 함께 제공한다. Companion에 CLI를 번들링하거나 raw installer를 자동 실행하는 이전 추천은 이 macOS 제품 경로에서 채택하지 않는다. 기존 독립 CLI 설치 채널은 유지한다.
- CLI 미설치 상태에서도 onboarding이 열려야 한다. 따라서 brew 탐색·설치·업데이트 bootstrap은 기존 CLI에 의존하지 않고 Tauri native port에서 수행한다.
- 앱은 GUI PATH만 믿지 않고 brew 실행 위치를 확인한다. 설치 완료 후 실제 Homebrew prefix의 CLI/수집기 경로 및 schema/capability를 검증하여 이전 screenshot의 구 CLI 선택 문제를 반복하지 않는다.
- 설치 중에는 진행/실패/재시도를 표시하고 상세 로그는 접어서 제공한다. 원시 Usage나 brew 로그 전체를 Main 오류 영역에 출력하지 않는다. 일반 앱 시작이 패키지 설치를 자동 실행하지는 않는다.
- Companion cask 설치와 CLI 설치 단계를 나누므로 cask가 formula를 강제 선설치하는 dependency는 추가하지 않는다. CLI가 이미 호환 버전이면 설치 단계를 완료로 표시한다.
- agent 연결은 다음 단계에서 Claude/Codex/Grok별로 수행한다. provider 프로그램 설치/계정 로그인과 workbranch hook 연결은 구별하며 trust와 첫 이벤트 확인은 별도 상태다.
- 배포 조건: 호환 CLI formula가 먼저 배포되어 있어야 새 Companion onboarding이 설치를 완료할 수 있다. 독립적인 버전 번호가 같다는 가정 대신 실제 계약을 검사한다. source-build Rust 의존성으로 설치가 길어지지 않도록 bottle 또는 검증된 prebuilt collector 배포를 준비한다.
- UI 공통 service, 설치 중 동시 실행 제어, 고정 argv, brew 미발견/잠금/네트워크/권한 실패 및 provider별 등록 방식은 이 흐름에 맞춰 구현한다. 아직 Homebrew 설치나 사용자 설정 변경은 실행하지 않았다.


## Onboarding / Settings 구현 slice

- 사용자 진행 요청에 따라 Homebrew 설치와 agent 연결 UI를 구현한다. source files: `apps/companion/src-tauri/src/setup.rs`, `src/application/{connections,useConnections}.ts`, `src/ui/ConnectionsPanel.tsx`; 관련 테스트는 기존 Rust module tests와 `tests/connections.test.tsx`에 둔다.
- native bootstrap은 CLI 부재에서도 brew 탐색/설치/업데이트를 수행한다. 고정 formula `tkhwang/tap/workbranch`만 허용하며 shell 문자열 대신 argv를 사용한다. 진행 로그는 크기를 제한해 UI의 접힌 상세에 전달한다.
- onboarding과 Settings는 하나의 controller/status/action을 공유한다. 초기 연결 확인 전에는 installation 상태를 표시하고, 클릭 없이 package/provider 설정을 변경하지 않는다. 나중에 연결을 선택해 이번 실행에서 onboarding을 접을 수 있다.
- CLI `capabilities --json`으로 Git 조회 없이 계약과 provider 지원을 확인한다. 실제 snapshot도 읽어 수집기 사용 가능 여부를 검사한다. 설치 후에도 선택 경로/호환성을 재검증한다.
- Grok Build는 camelCase payload를 canonical envelope로 정규화한다. `StopCancelled`는 interrupted, notification의 permission_prompt는 대기 관측으로 처리한다. Claude 호환 hook을 통해 전달된 Grok payload는 Claude로 기록하지 않는다.
- Grok 전용 plugin은 `integrations/agent-events/grok/plugins/workbranch-agent-events-grok/`에 둔다. native provider manager로 연결하며 사용자 승인 없이 trust 옵션을 자동 적용하지 않는다. source checkout에서는 로컬 plugin source를 사용할 수 있다.
- 설치된 plugin 정보와 최근 관측 시각을 분리한다. native manager가 trust 상태를 제공하지 않으면 이를 추정하지 않고 provider에서 확인하도록 안내한다. agent 프로그램 자체 설치/로그인은 포함하지 않는다.
- 이전 raw installer 자동 연결 제안과 그 RED 테스트는 이 UI 흐름으로 대체한다. Homebrew로 설치하는 product 경로가 기본이며 CLI `hooks`는 공통 연결 실행 경로로 남긴다.
- [x] [backend] setup probe/action, Grok adapter, capabilities, 설치/실패/고정 argv 테스트
- [x] [frontend] 공통 ConnectionsPanel/controller, onboarding/Settings 연결 및 재시도/상태 테스트
- [x] 기존 회귀, 브라우저 fixture, 리뷰 및 문서 동기화


### Onboarding / Settings 구현 검증

- Onboarding과 Settings는 공통 controller와 ConnectionsPanel을 사용한다. CLI 미설치에서도 native bootstrap이 Homebrew를 찾고 install/update/repair를 수행한다. 실제 package/provider 설정 변경은 클릭 후에만 실행된다.
- formula 설치 여부와 CLI 존재 여부를 구분하여 이전 수동 설치 환경에서는 `brew install`로 진입한다. 연결/재연결 뒤에는 새 시각 기준 이후 수신만 검증된 것으로 표시하고 이전 기록은 historical로 남긴다.
- 명령은 고정 enum/argv로 제한한다. 작업 직렬화, 제한된 로그, parent 종료 후 pipe drain까지 적용되는 timeout, 설치 후 재검증을 구현했다. 보안/아키텍처 리뷰에서 나온 세 P2를 수정하고 재검토에서 새 P1/P2가 없음을 확인했다.
- Grok camelCase와 StopCancelled, 불확실한 Stop/idle 확인을 정규화한다. Claude 호환 경로의 Grok 이벤트는 Claude로 수집하지 않는다. 연결 시 고정 실행 locator `~/.workbranch/runtime/hook-collector`를 등록하며 별도 agent 상태 문서는 만들지 않는다.
- 로컬 검증: CLI 266개, collector 19개, contract 8개, Companion TS 218개, Tauri Rust 42개 통과. typecheck/build/lint, 두 Rust clippy, ShellCheck 및 generated mirror/diff 검증 통과. lint info는 오류/경고와 구별한다.
- 실제 Chrome 460 CSS px fixture에서 CLI 설치 전 연결 비활성화, 설치 후 연결 활성화, Grok 설정 후 trust/첫 이벤트 대기, Claude/Codex 테마를 확인했다. fixture 설치 action은 mock이며 실제 Homebrew를 실행하지 않았다.
- Claude native plugin manager는 격리된 설정 디렉터리에서 로컬 marketplace 추가/설치의 반복 실행을 확인했다. 실제 사용자 설정, provider login/trust, agent turn 실행은 변경하거나 우회하지 않았다.
- 실제 Homebrew 설치·업데이트, 사용자 계정의 Claude/Codex/Grok hook 수신, release/bottle 게시 acceptance는 여전히 별도다. 사용자가 준비한 Git staging은 그대로 유지했으며 이번 변경을 stage/commit/push하지 않았다.


### Grok 설치 신뢰 승인 누락 수정

- 원인: Grok의 비대화형 plugin 설치는 명시적인 `--trust` 승인이 필요하지만 기존 Connect 경로는 승인 단계 없이 일반 install만 호출했다.
- Grok 연결 버튼은 먼저 설치 대상과 plugin 실행 권한을 표시한다. 사용자가 `신뢰하고 설치`를 누른 경우에만 승인된 source를 native port에 전달하고 `--trust --expected-source`를 사용한다. 취소/일반 연결/다른 provider에는 trust가 추가되지 않는다.
- `hooks describe`는 설치 source를 변경 없이 반환한다. native port와 CLI가 각각 승인 source와 현재 source를 비교해 변경됐으면 재승인을 요구한다. 오래된 CLI는 업데이트를 요구하며 자동으로 신뢰 승인하지 않는다.
- stream 로그와 최종 결과를 중복 합치던 표시도 수정했다. 기존 사용자 환경에서 실제 trust/install은 실행하지 않고 stub/fixture로 승인 전달을 검증한다.

- 후속 검증: 승인 전달/대상 변경 차단 CLI 2개, native 승인 argv 2개, Companion 전체 220개 테스트 및 typecheck/build/lint/clippy 통과. 보안 리뷰에서 새 P1/P2 없음. 실제 Grok `--trust` 설치는 실행하지 않았다. 설치 source는 경로/원격 source 문자열에 바인딩하며 파일 내용 hash 승인을 의미하지 않는다.


### TASK-WORKBRANCH.md 운영 의존성 완전 제거

- 앞으로 task 생성·인식·상태 수집·표시에 기존 brief 파일을 사용하지 않는다. 기존 파일 삭제와 migration 검증에만 이름을 유지한다.
- Companion의 외부 Git metadata 감시 대상 탐색에서 brief 존재 조건을 제거하고, project 하위 workspace/repository의 실제 `.git` 구조로 탐색한다.
- 일반 파일 감시 테스트는 현재 metadata/config를 사용한다. brief가 없는 task의 외부 Git HEAD 변경 감지 회귀 테스트를 추가했다.
- 검증: 수정 전 회귀 테스트는 Timeout으로 실패하여 누락을 재현했다. 수정 후 Companion native `cargo test --lib` 45개 전부 통과. 운영 코드 검색 결과 남은 파일명 참조는 migration과 task 제거 시 기존 파일 정리뿐이다.

### PR #198 review corrections

- Migration replaces only exact generated EN/KO guidance lines, preserving user-added suffixes.
- A missing or unsupported Cargo toolchain no longer fails the already-installed Bash CLI; collector failure is reported with hook setup guidance.
- Excerpts containing URI authority userinfo are omitted for all schemes, including database DSNs and quoted userinfo. This is conservative pattern-based protection, not a guarantee against arbitrary unlabeled secrets.
- Empty runtime overrides use the home default; a nonempty override works without HOME.
- External Git watches include the configured base and task directories with `.workbranch.task`, excluding unrelated worktrees without reintroducing a task brief dependency.
- Validation: runtime 22 tests and Companion native 46 tests passed. Full CLI suite passed; Bash syntax, ShellCheck warning/error checks, runtime Clippy with warnings denied, and diff whitespace checks passed. Independent review found no remaining P1/P2 in this correction.
