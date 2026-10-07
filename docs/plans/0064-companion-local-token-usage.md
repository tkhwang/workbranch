# 0064 Companion Local Token Usage

**Goal:** `TASK-WORKBRANCH.md` 폐기(0060) 뒤로 데이터가 끊긴 Activity 탭과, reset 시각을 손으로 입력하던 Main의 `WEEKLY LIMITS` gauge(0059)를 실제 사용량 표시로 바꾼다. Main 상단에는 Claude | Codex 요약(플랜 한도 + 14일 token 막대)을, 세 번째 탭 Usage에는 agent별 상세를 보여준다.

**Architecture:** Rust `usage_snapshot(days)` command(`src-tauri/src/usage.rs`)가 agent가 이미 남긴 로컬 파일만 읽어 15분 단위 token bucket과 한도 관측값을 돌려준다. 인증, Keychain, 네트워크를 쓰지 않는다. 파일은 크기·mtime 기준 in-memory cache로 다시 읽지 않는다. frontend는 `domain/usage.ts`에서 bucket을 로컬 날짜로 접고 한도 상태(미시작/reset/stale)를 계산하며, `UsageSummary`(Main)와 `UsageView`(탭)가 그린다. `useUsage`는 60초마다, 그리고 창이 열릴 때 다시 읽는다. CLI와 runtime collector는 바꾸지 않는다.

**Mockups:** https://claude.ai/artifact/VGKG3dmiCigRLB5qrUNUSt (2026-10-07. 860px 줄의 `Usage B · 860px`과 `Main · 860px 한도 아래 그래프`가 확정안)

---

## 사용자 문제와 흐름

1. Activity 탭은 `TASK-WORKBRANCH.md` checklist 변화를 기록해 timeline을 만들었다. 0060에서 brief를 폐기하면서 `activityEventsForRefresh`가 빈 배열을 돌려주게 되어 새 기록이 없었다.
2. `WEEKLY LIMITS` gauge는 `/usage`의 reset 시각을 사용자가 옮겨 적어야 했고 실제 사용률은 알 수 없었다.
3. 사용자는 OAuth 연동을 꺼리는 사용자가 많다고 보고, 먼저 로컬 파일만으로 구현한 뒤 부족하면 OAuth를 검토하기로 했다.

## 결정

- [x] **데이터 소스: 로컬 파일만.** OAuth `/api/oauth/usage`는 Anthropic 정책상 Claude Code 밖에서 쓸 수 없고 Keychain 권한 요청도 생긴다(claude-hud가 같은 이유로 철회). 참고 구현: senna-lang/herdr-agent-usage(MIT, `cachedUsageUtilization`), aqua5230/usage(AGPL, 설계만 참고), steipete/CodexBar(MIT, 중복 제거 규칙), ccusage(검증 기준).
- [x] **Claude token:** `~/.claude/projects/**/*.jsonl`의 assistant `message.usage`. 한 응답이 content block마다 여러 줄로 기록되므로 `message.id + requestId`로 한 번만 센다. 날짜는 첫 줄 시각, usage는 마지막 줄(streaming 최종 output). cache write는 `cache_creation_input_tokens`와 `cache_creation.ephemeral_*` 합 중 큰 값. 9/30~10/6 일별 합계가 ccusage와 일치.
- [x] **Claude 한도:** `~/.claude.json`의 `cachedUsageUtilization`(`five_hour`, `seven_day`, `fetchedAtMs`). Claude Code가 `/usage`를 갱신할 때만 바뀌어 하루 가까이 늦을 수 있다. 관측 시각을 함께 보여주고 5h는 1시간, weekly는 6시간이 지나면 흐리게 표시한다. statusline `rate_limits`를 받는 래퍼는 후속 옵션으로 남긴다.
- [x] **Codex token·한도:** `~/.codex/sessions`, `archived_sessions` rollout의 `token_count`. token은 `total_token_usage` 차이로 계산해 반복 이벤트를 무시하고, 합계가 줄면(재개 세션) 새 합계를 그대로 센다. 한도는 `rate_limits`를 `window_minutes`로 구분하고(`primary`가 weekly일 수 있다), 계정 전체 bucket(`codex`)을 우선한다. 일별 합계가 ccusage와 일치.
- [x] **Grok 제외:** 로그에 weekly 기간은 있으나 사용률이 없어 이번 범위에서 뺐다.
- [x] **화면:** Main 요약은 한도를 항상 Claude | Codex 2열로 두고, 그 아래 오늘 기준 최근 7일을 두 agent를 날짜별로 나란히 놓은 차트와 일별 합계로 보여준다(첫 구현의 열별 14일 그래프는 날짜 구분이 어렵다는 피드백으로 교체). Usage 탭은 B안(나란히 비교) — provider 열, 같은 축의 일별 비교 차트, 최근 7일 표. 컨테이너 너비 720px 이상에서 2열, 그보다 좁으면 1열(runtime 보드와 같은 기준).
- [x] **5h 줄:** agent가 5h 창을 보고할 때만 그린다. 현재 Codex Pro는 weekly만 있어 Claude에만 보인다.
- [x] **token 기준:** cache read를 포함한 합계(ccusage와 같음). 상세 화면에서 input/output/cache read/cache write를 나눠 보여준다.
- [x] **정리:** Activity 코드(`src/activity`, `application/activity.ts`, `activity_store.rs`, 관련 command·CSS·`--cal-*` token)와 수동 limits(`domain/limits.ts`, `application/limits.ts`, `useLimitAccounts`, `WeeklyLimitGauge`, Settings 섹션)를 삭제했다. 사용자 디스크의 `activity.jsonl`과 `companion-limits.json`은 지우지 않는다.

## 성능

이 Mac 기준 15일, 545개 파일(Claude 1.1GB, Codex 3.2GB 중 해당 기간)에서 release 빌드 첫 스캔 약 1.3초, 이후 변경 파일만 다시 읽어 약 40ms. 줄 단위 `memchr` 사전 필터로 대부분의 줄은 JSON 파싱을 건너뛴다.

## 검증

- [x] `cargo test`(usage 파서·병합·cache 8개 포함), `cargo clippy --all-targets`
- [x] `pnpm --filter @workbranch/companion typecheck|lint|test|build`
- [x] 실제 파일 대상 수동 스냅샷과 ccusage 일별 비교(`usage_tests.rs`의 ignored `manual_real_home_snapshot`)
- [ ] Tauri 앱에서 860px·460px, Claude/Codex 테마 시각 확인
