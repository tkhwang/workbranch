#!/usr/bin/env bash
set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
svg="$repo_root/docs/figs/workbranch-git-flow.svg"
png="$repo_root/docs/figs/workbranch-git-flow.png"

tmp_png=$(mktemp "${TMPDIR:-/tmp}/workbranch-flow.XXXXXX.png")
sips -s format png "$svg" --out "$tmp_png" >/dev/null
mv "$tmp_png" "$png"
