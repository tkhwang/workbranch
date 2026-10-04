#!/bin/sh
# Observer only: never return permission decisions or model context.
collector=${WORKBRANCH_RUNTIME_BIN:-}
runtime_dir=${WORKBRANCH_RUNTIME_DIR:-"$HOME/.workbranch/runtime"}
if [ -z "$collector" ] && [ -x "$runtime_dir/hook-collector" ]; then collector="$runtime_dir/hook-collector"; fi
if [ -z "$collector" ]; then collector=$(command -v workbranch-agent-runtime 2>/dev/null || true); fi
if [ -z "$collector" ] && [ -x "$HOME/.local/bin/workbranch-agent-runtime" ]; then collector="$HOME/.local/bin/workbranch-agent-runtime"; fi
if [ -n "$collector" ]; then "$collector" ingest grok >/dev/null 2>&1 || true; fi
exit 0
