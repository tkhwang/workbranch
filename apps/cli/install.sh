#!/usr/bin/env bash
# Keep the historical entrypoint on the same installer as the repository root.
set -eu
script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_root=$(cd "$script_dir/../.." && pwd -P)
if [ -f "$repo_root/apps/cli/src/workbranch/main.sh" ] && [ -f "$repo_root/install.sh" ]; then
  exec bash "$repo_root/install.sh" "$@"
fi
installer=$(mktemp "${TMPDIR:-/tmp}/workbranch-installer.XXXXXX")
trap 'rm -f "$installer"' EXIT INT TERM
url="${WORKBRANCH_RAW_BASE_URL:-https://raw.githubusercontent.com/tkhwang/workbranch/main}/install.sh"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$url" > "$installer"
elif command -v wget >/dev/null 2>&1; then
  wget -qO- "$url" > "$installer"
else
  printf '%s\n' '[-] Error: curl or wget is required' >&2
  exit 1
fi
bash "$installer" "$@"
