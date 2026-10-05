# 0063 Companion Setup Progress and Agent PATH

**Goal:** Onboarding과 Settings의 설치·연결 버튼이 눌렸는지, 실행 중인지, 결과가 무엇인지 버튼 자리에서 바로 보이게 한다. Finder나 login item으로 실행한 Companion도 version manager로 설치한 agent(Codex 등)를 찾게 한다.

**Architecture:** frontend에 `ProgressButton`(ui)을 추가해 실행 중인 버튼에만 `aria-busy`, spinner, `… 중…` label을 보여 준다. `ConnectionState`에 `lastAction`을 두어 결과 메시지를 그 동작의 CLI 단계나 agent 카드 안에 그린다. 전역 `button:disabled` 스타일로 비활성 버튼을 흐리게 한다. Tauri backend의 `setup::path_env()`는 사용자의 interactive login shell PATH를 한 번 읽어 GUI-safe PATH 뒤에 붙인다. CLI, hook 설치 명령, `lib.rs`의 workbranch runner는 바꾸지 않는다.

---

## 사용자 문제와 흐름

1. 연결 버튼을 눌러도 버튼은 그대로이고, 진행 문구는 긴 패널 맨 아래에만 있어 스크롤 밖에 있었다. 완료·실패 문구도 패널 맨 위에만 나와 눌렀는지조차 알기 어려웠다.
2. Codex와 Grok의 `연결` 버튼은 `disabled`였지만 전역 버튼 스타일에 disabled 표시가 없어 눌리는 버튼처럼 보였다.
3. Codex가 `Agent 미설치`로 나온 원인: Finder·login item 실행은 launchd의 `PATH=/usr/bin:/bin:/usr/sbin:/sbin`만 물려받는다. GUI-safe PATH(`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.grok/bin`)에도 `~/.openclis/versions/nodejs/.../bin/codex` 같은 version manager 경로는 없다. Claude는 `~/.local/bin`에 있어 연결됐다. Grok은 실제로 설치되지 않은 상태였다.
4. 이제 버튼을 누르면 그 버튼이 `연결 중…`(spinner)으로 바뀌고 나머지 버튼은 흐리게 기다린다. 끝나면 결과가 그 카드 안에 나온다.

## 결정

- D1. 진행 표시는 누른 버튼 자체에 둔다. 버튼 identity는 action kind와 대상(CLI 또는 provider)이다. 승인한 Grok source(`approvedSource`)는 비교하지 않는다. 신뢰 승인 뒤 실행돼도 Grok `연결` 버튼에 표시된다.
- D2. 결과(`error`/`notice`)는 `lastAction`의 대상 위치에 그린다. 상태 확인(`refresh`) 실패는 `lastAction`을 비워 패널 맨 위에 둔다. 아래쪽 `role="status"` 진행 문구와 상세 로그 disclosure는 유지한다.
- D3. disabled는 모든 버튼에 적용한다(`--faint`, opacity 0.55, `not-allowed`). 기존 task action의 disabled 값과 같다. 실행 중인 버튼은 `button[aria-busy="true"]:disabled`로 본문 색과 opacity 1을 유지한다. 그래서 업데이트 확인·적용과 runtime 전환 버튼도 같은 `ProgressButton`으로 바꿨다. 바꾸지 않으면 진행 중에 흐려진다.
- D4. spinner는 CSS ring이다. 터미널식 braille spinner는 JS timer re-render나 브라우저마다 다른 `content` animation이 필요하다. reduced motion에서는 회전을 멈추고 label로만 진행을 알린다.
- D5. agent PATH는 `$SHELL -ilc 'echo M; /usr/bin/printenv PATH; echo M'`로 읽는다. `printenv`는 fish 같은 shell의 list 문법과 무관하게 자식 프로세스가 받는 PATH를 출력하고, marker는 profile이 출력한 내용을 건너뛴다. 상대 경로는 버린다.
- D6. shell은 `setsid`로 새 session에서 실행한다. terminal에서 띄운 dev build에서도 interactive zsh가 controlling terminal을 잡으려다 SIGTTOU로 멈추지 않는다. deadline(10초)이 지나면 process group을 kill한다. reader는 닫는 marker를 읽는 즉시 결과를 넘긴다. profile이 띄운 daemon이 pipe를 잡고 있어도 기다리지 않는다. 결과는 `OnceLock`으로 실행당 한 번만 계산한다. 실패하면 기존 GUI-safe PATH만 쓴다.
- D7. login shell PATH는 기존 경로 뒤에 붙이고 중복을 제거한다. brew와 workbranch CLI가 원래 찾던 경로가 그대로 앞에 남는다. 이 PATH는 `find_program`과 setup/update 자식 프로세스(`execute`, `run_logged`)에 같이 쓰인다. `codex.js`의 `#!/usr/bin/env node`도 같은 PATH에서 node를 찾는다.
- D8. test build에서는 login shell을 읽지 않는다. 개발자의 shell profile에 따라 결과가 달라지지 않게 하기 위해서다. 실행 계약은 가짜 shell script로 검증한다.

## 범위 밖

- 미설치 agent 자체를 설치하는 버튼. 미설치 agent는 지금처럼 연결을 막고 설치를 안내한다.
- `lib.rs`의 `run_workbranch`(list·runtime·IDE 실행)에 login shell PATH를 쓰는 것.
- shell 설정이 바뀌었을 때 Companion 재시작 없이 PATH를 다시 읽는 것.

## 변경 파일

- `apps/companion/src-tauri/src/setup.rs`: `path_env()`에 login shell PATH 추가, `login_shell_path`, `shell_profile_path`, `marked_path`와 test.
- `apps/companion/src/ui/ProgressButton.tsx`: 새 primitive.
- `apps/companion/src/application/connections.ts`: `lastAction`, `setupTarget`, `sameSetupAction`.
- `apps/companion/src/ui/ConnectionsPanel.tsx`, `UpdatePanel.tsx`, `App.tsx`: `ProgressButton` 적용과 결과 위치.
- `apps/companion/src/styles/chrome.css`, `motion.css`: disabled, busy, spinner, reduced motion.
- `apps/companion/tests/connections.test.tsx`, `updates.test.tsx`, `agent-primitives.test.tsx`.
- `DESIGN.md`.

## 검증 (2026-10-06)

- `cargo test` (src-tauri): 57 tests passed(새 test 4개). `cargo clippy --all-targets -- -D warnings`: 경고 없음. `cargo fmt --check`: 새 diff 없음. 기존 diff 2건(`setup.rs` grok tests, `watch_scope_tests.rs`)은 그대로 둔다.
- daemon test는 reader의 조기 반환을 끄면 실패한다(mutation으로 확인).
- `pnpm --filter @workbranch/companion test`: 20 files, 255 tests passed. `typecheck`: error 없음. `lint`: error 없음. 기존 info 85개는 그대로다.
- 이 Mac의 실제 zsh profile을 GUI와 같은 환경(`env -i`, `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, `SHELL=/bin/zsh`)에서 임시 ignored test로 읽었다(검증 후 삭제). 1.5초 안에 읽혔다. 기존 PATH로는 `codex`가 없었고, 새 PATH로는 `~/.openclis/versions/nodejs/24.14.1/.../bin/codex`를 찾았다. `grok`은 둘 다 없어 실제 미설치와 일치했다.
- fixture와 앱 CSS로 만든 preview HTML을 headless Chrome으로 확인했다. 실행 중인 버튼만 spinner와 `연결 중…`/`CLI 업데이트 중…`/`확인 중…`으로 또렷하고 나머지는 흐리다. 실패 문구는 Codex 카드 안에 나온다. headless Chrome의 최소 창 폭이 500px이라 `main`을 460px로 고정해 확인했고, Claude·Codex 테마 모두 overflow되는 요소가 없었다.
- 직접 확인하지 못한 것: Finder로 실행한 release 번들에서 실제로 Codex `연결`을 눌러 hook 설치까지 끝나는 흐름. 다음 companion release 뒤 확인해야 한다.
