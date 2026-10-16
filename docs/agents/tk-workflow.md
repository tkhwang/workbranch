# tk-workflow config

## Layout
- kind: multi-package
- docs home: .
- packages:
  - cli → apps/cli
  - companion → apps/companion
  - agent-runtime → apps/agent-runtime
  - contract → packages/contract

## Docs
- intents: docs/intents/
- specs:   docs/specs/{module}/
- tasks:   docs/tasks/

## Modules
| code | name | code locations |
|------|------|----------------|
| CLI  | workbranch CLI (Bash) | apps/cli/src/workbranch, apps/cli/scripts, apps/cli/tests |
| COMP | Companion menubar app (Tauri + React) | apps/companion/src, apps/companion/src-tauri, apps/companion/tests |

## Verify
| package | typecheck | lint | format | test |
|---------|-----------|------|--------|------|
| cli | /bin/bash -n bin/workbranch install.sh apps/cli/install.sh apps/cli/bin/workbranch apps/cli/tests/run.sh apps/cli/scripts/build-workbranch.sh | find apps/cli/src/workbranch apps/cli/scripts -type f -name '*.sh' -print0 \| xargs -0 shellcheck -s bash -S warning -e SC2034 install.sh apps/cli/install.sh | — | apps/cli/tests/run.sh |
| companion | pnpm --filter @workbranch/companion typecheck | pnpm --filter @workbranch/companion lint | (included in lint: biome check) | pnpm --filter @workbranch/companion test && cargo test --manifest-path apps/companion/src-tauri/Cargo.toml |
| agent-runtime | cargo +1.95.0 build --locked --manifest-path apps/agent-runtime/Cargo.toml | — | — | cargo +1.95.0 test --locked --manifest-path apps/agent-runtime/Cargo.toml |
| contract | pnpm --filter @workbranch/contract typecheck | pnpm --filter @workbranch/contract lint | (included in lint: biome check) | pnpm --filter @workbranch/contract test |

- cli: rebuild `bin/workbranch` with `apps/cli/scripts/build-workbranch.sh` before testing; `apps/cli/tests/run.sh` fails if the generated file is stale.
- `biome check` exits 0 on warnings; check its output for warnings.

## Language
- conversation: ko
- documents: ko

## Peers
| name   | kind   | role   | command |
|--------|--------|--------|---------|
| codex  | codex  | any    |         |
| grok   | grok   | any    |         |
| claude | claude | debate |         |
