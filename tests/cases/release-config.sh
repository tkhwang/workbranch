# shellcheck shell=bash

test_release_please_root_excludes_companion_only_paths() {
  python3 - <<'PY'
import json
from pathlib import Path

cfg = json.loads(Path('release-please-config.json').read_text())
root = cfg['packages']['.']
exclude_paths = set(root.get('exclude-paths', []))
required_recursive_excludes = {
    'companion/**',
    'docs/**',
    '.github/**',
}
missing = sorted(required_recursive_excludes - exclude_paths)
if missing:
    raise SystemExit(f"root package must recursively exclude companion-only release paths: {missing}")

sample_companion_only_files = [
    'companion/Sources/CompanionApp/LoginItemController.swift',
    'companion/scripts/build-app.sh',
    'docs/plans/0027-companion-launch-at-login.md',
    'README.md',
    'README.ko.md',
]

def is_excluded(path):
    return (
        path in exclude_paths
        or any(pattern.endswith('/**') and path.startswith(pattern[:-3] + '/') for pattern in exclude_paths)
    )

not_excluded = [path for path in sample_companion_only_files if not is_excluded(path)]
if not_excluded:
    raise SystemExit(f"root package would still see companion-only files: {not_excluded}")
PY
}
