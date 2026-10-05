# 0062 Companion Update Check

**Goal:** Companion header의 업데이트 아이콘을 누르면 Homebrew로 설치한 `workbranch` CLI와 `workbranch-companion`의 최신 버전을 확인하고, 버튼 하나로 둘 다 업데이트한다. Companion을 업데이트하면 새 버전으로 다시 시작한다.

**Architecture:** Tauri backend에 `update` 모듈을 추가한다. `update_check`는 `brew update` 뒤 `brew info --json=v2`로 formula와 cask의 설치·최신 버전을 읽는다. `update_apply`는 allowlist에 있는 두 package만 `brew upgrade`한다. `relaunch_companion`은 `AppHandle::restart()`를 호출한다. frontend는 `createUpdateController`(application), `UpdatePanel`(ui), header의 원형 화살표 버튼으로 구성한다. header 아이콘은 업데이트와 종료 두 개만 남기고, 수동 새로고침은 창을 열 때의 자동 새로고침으로 바꾼다. CLI JSON contract, `workbranch` CLI, release workflow는 바꾸지 않는다.

---

## 사용자 문제와 흐름

1. 지금은 `brew upgrade tkhwang/tap/workbranch`와 `brew upgrade --cask tkhwang/tap/workbranch-companion`을 터미널에서 따로 실행한다. 두 release가 독립적이라 어느 쪽이 밀렸는지 바로 알기 어렵다.
2. header의 원 안 아래 화살표(`arrow.down.circle`)를 누르면 header 아래에 업데이트 패널이 열리고 확인을 시작한다.
3. 패널은 CLI와 Companion마다 설치 버전과 최신 버전을 보여 준다. Companion은 실행 중인 버전도 함께 보여 준다.
4. 업데이트가 있으면 버튼 하나가 나온다. 버튼 이름에 재시작 여부가 드러난다: `CLI 업데이트` / `Companion 업데이트 후 재시작` / `모두 업데이트 후 재시작`.
5. CLI만 업데이트하면 버전을 다시 읽고 Main 상태와 Settings 연결 상태를 새로 고친다. Companion까지 업데이트했으면 바로 다시 시작한다.

## 결정

- D1. 버전 출처는 Homebrew다. 실제 설치 채널이 Homebrew이기 때문이다. GitHub release는 cask bump(빌드·공증 후)보다 먼저 publish되므로, release API를 기준으로 하면 `brew upgrade`가 아직 설치하지 못하는 버전을 "업데이트 있음"으로 보여 준다. `outdated` 판정도 직접 semver를 비교하지 않고 brew의 `outdated` 값을 쓴다.
- D2. 확인은 클릭할 때만 한다. `brew update`는 모든 tap을 갱신하는 무거운 작업이라 background polling을 하지 않는다. header 점(`data-update-available`)은 마지막 확인 결과로만 켠다.
- D3. 업그레이드는 설치되어 있고 outdated인 package만 대상으로 한다. 설치되지 않은 CLI는 기존 Settings의 설치 흐름으로 안내한다. backend는 `cli | companion` enum만 받는다. 인자는 `upgrade --formula tkhwang/tap/workbranch`와 `upgrade --cask tkhwang/tap/workbranch-companion`으로 고정한다.
- D4. 순서는 CLI → Companion이다. Companion 업그레이드는 재시작으로 끝나기 때문이다. 앞 단계가 실패하면 그 자리에서 멈추고 로그를 보여 준다.
- D5. Companion이 brew를 자식 프로세스로 실행한다. Homebrew 6.0.22(2026-08-29)부터 brew를 실행하는 앱은 cask의 `uninstall quit`을 건너뛴다(`hosting_brew?`). 그래서 brew는 실행 중인 번들을 그 자리에서 교체하고 다시 열지 않는다. 업그레이드가 성공하면 Companion이 `AppHandle::restart()`로 같은 경로의 새 binary를 실행한다.
- D6. 업그레이드 출력은 pipe 대신 임시 log 파일로 받아 100ms마다 tail해 `update-progress` event로 보낸다. 오래된 brew가 Companion을 quit하거나 사용자가 업데이트 도중 종료해도 brew가 SIGPIPE/EPIPE로 중간에 멈추지 않는다.
- D7. 업그레이드에는 `HOMEBREW_NO_AUTO_UPDATE=1`을 준다. 직전 확인에서 이미 `brew update`를 했으므로, 화면에 보여 준 버전과 실제로 설치되는 버전이 같다. 업그레이드 뒤에는 `brew update` 없이 버전만 다시 읽는다.
- D8. `brew update`(fetch 확인)와 업그레이드는 Settings 설치/연결 작업과 같은 `begin_action` lock을 쓴다. Homebrew 작업이 동시에 실행되지 않는다.
- D9. debug build(`tauri dev`)는 Companion 자체 업데이트를 막는다. 실행 중인 앱이 cask 번들이 아니기 때문이다. CLI 업데이트는 허용한다.
- D10. cask는 설치됐지만 실행 중인 버전과 다르면(터미널에서 업그레이드한 뒤 재시작하지 않은 경우) "다시 시작하면 적용됩니다"라고 안내만 한다.
- D11. header 아이콘은 `업데이트 | 종료` 두 개만 둔다. `↻` 새로고침은 대부분 자동 갱신과 겹친다(project root·git metadata fs watch, agent 세션 1초 polling, 5분 heartbeat). 수동 새로고침이 필요했던 경우는 두 가지였다. registry(`projects.md`)는 watch하지 않아 새로 등록한 project가 늦게 보였고, 에러 뒤에는 직접 재시도해야 했다. 이제 창이 focus를 얻을 때(`tauri://focus`) 전체 refresh를 한 번 실행해 두 경우를 모두 처리한다. 창은 blur 때 숨으므로 focus는 곧 tray로 창을 연 순간이다. 이미 실행 중인 refresh가 있으면 건너뛴다.
- D12. 업데이트 아이콘은 text `↓`에 1.5px 원형 border를 둘러 그린다(`arrow.down.circle`). `⏻`처럼 외곽선 원이라 두 아이콘이 한 세트로 보인다. `↓`는 새 버전을 내려받는다는 뜻이고, git fact의 `↓N`(upstream에 더 새 것이 있음)과도 뜻이 같다. `↻`는 지금까지 task 새로고침이라는 뜻이었는데, 이 버튼은 네트워크를 쓰는 느린 `brew update`를 실행하므로 쓰지 않았다. `↑`는 upgrade로도 읽히지만 다운로드 관례보다 덜 익숙하다. 후보였던 `↥`(Menlo)·`⤒`는 너무 작고 가늘었다. `⬆︎`는 채워진 모양이라 `⏻`보다 무거웠고, `⭱`·`⮉`는 일반 Mac에 없는 글꼴(Iosevka NF)이나 LastResort로 fallback됐다. text-only header(SVG 없음) 원칙은 유지한다.

## 범위 밖

- 주기적 자동 확인, macOS 알림, Sparkle·`tauri-plugin-updater` 같은 in-app 업데이터. 배포 채널은 계속 Homebrew 하나다.
- Homebrew가 아닌 경로(`install.sh`, checkout)로 설치한 CLI의 업데이트.
- tray menu의 "업데이트 확인" 항목.

## 변경 파일

- `apps/companion/src-tauri/src/update.rs`: `update_check`, `update_apply`, `relaunch_companion`, brew JSON parsing, file-backed runner.
- `apps/companion/src-tauri/src/setup.rs`: `FORMULA`, `path_env`, `find_program`, `execute`를 crate 안에 공개하고, action lock을 `begin_action()`으로 추출했다.
- `apps/companion/src-tauri/src/lib.rs`: module과 command 등록.
- `apps/companion/src/application/updates.ts`, `useUpdates.ts`: update state·controller·hook.
- `apps/companion/src/infrastructure/tauriClient.ts`: `checkUpdates`, `applyUpdates`, `onUpdateProgress`, `relaunchCompanion`, `onWindowFocused`.
- `apps/companion/src/ui/UpdatePanel.tsx`, `AgentHeader.tsx`, `App.tsx`, `styles/agent-shell.css`.
- `apps/companion/tests/updates.test.tsx`, `agent-primitives.test.tsx`, `app-shell.test.tsx`, `tauri-client.test.ts`.
- `DESIGN.md`.

## 검증 (2026-10-05)

- `cargo test` (src-tauri): 53 tests passed. `cargo clippy --all-targets -- -D warnings`: 경고 없음. 새로 생긴 `cargo fmt --check` diff는 없다. 기존 diff 2건(`setup.rs` grok tests, `watch_scope_tests.rs`)은 손대지 않았다.
- `pnpm --filter @workbranch/companion test`: 20 files, 246 tests passed. `typecheck`: error 없음. `lint`: error 없음. 기존 info 85개는 그대로다.
- 임시 ignored test로 이 Mac의 실제 Homebrew에 `inspect(false)`를 한 번 실행했다(`brew info`만 실행, 검증 후 삭제). CLI 2.26.0/2.26.0, Companion 2.23.0/2.23.0, 둘 다 `outdated: false`로 읽혔다.
- 임시 preview HTML(fixture 데이터, 앱 CSS)을 headless Chrome으로 확인했다. 860px과 460px, Claude·Codex 테마 모두 header 버튼과 패널이 가로 overflow 없이 들어간다. 원형 화살표는 small·medium·large 글자 크기에서 `⏻`와 지름·선 굵기가 맞는다.
- 직접 확인하지 못한 것: 실제 outdated 상태에서 `brew upgrade --cask`로 실행 중인 번들을 교체하고 재시작하는 흐름. 다음 companion release 뒤 이전 버전에서 한 번 확인해야 한다.
