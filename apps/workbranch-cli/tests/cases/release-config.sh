# shellcheck shell=bash

test_release_please_root_excludes_companion_only_paths() {
  python3 - <<'PY'
import json
from pathlib import Path

cfg = json.loads(Path('release-please-config.json').read_text())
manifest = json.loads(Path('.release-please-manifest.json').read_text())
root = cfg['packages']['.']
companion = cfg['packages']['apps/workbranch-companion']
exclude_paths = set(root.get('exclude-paths', []))
required_recursive_excludes = {
    'apps/workbranch-companion/**',
    'packages/contract/**',
    'docs/**',
    '.github/**',
}
missing = sorted(required_recursive_excludes - exclude_paths)
if missing:
    raise SystemExit(f"root package must recursively exclude non-CLI release paths: {missing}")

extra_files = {item['path'] for item in root.get('extra-files', [])}
if 'apps/workbranch-cli/bin/workbranch' not in extra_files:
    raise SystemExit('root package must update moved CLI artifact')
if 'bin/workbranch' not in extra_files:
    raise SystemExit('root package must update raw-install compatibility artifact')

if cfg.get('separate-pull-requests') is not True:
    raise SystemExit('release-please must preserve independent package PRs')
if 'companion' in cfg['packages'] or 'companion' in manifest:
    raise SystemExit('legacy companion release package key must be migrated')
if 'apps/workbranch-companion' not in manifest:
    raise SystemExit('manifest must carry companion version under moved app path')
companion_extra_files = companion.get('extra-files', [])
expected_companion_extra_files = [
    {'type': 'json', 'path': 'src-tauri/tauri.conf.json', 'jsonpath': '$.version'},
    {'type': 'json', 'path': 'package.json', 'jsonpath': '$.version'},
    {'type': 'toml', 'path': 'src-tauri/Cargo.toml', 'jsonpath': '$.package.version'},
    {
        'type': 'toml',
        'path': 'src-tauri/Cargo.lock',
        'jsonpath': '$.package[?(@.name=="workbranch-companion")].version',
    },
]
if companion_extra_files != expected_companion_extra_files:
    raise SystemExit(f'companion extra-files mismatch: {companion_extra_files}')

sample_companion_only_files = [
    'apps/workbranch-companion/src/App.tsx',
    'packages/contract/src/index.ts',
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

test_companion_release_cask_quits_running_app_on_upgrade() {
  python3 - <<'PY'
from pathlib import Path

workflow = Path('.github/workflows/companion-release.yml').read_text()
expected = 'uninstall quit: "dev.tkhwang.workbranch.companion"'
if expected not in workflow:
    raise SystemExit('companion cask generation must quit the running menu-bar app during upgrades')

if workflow.count(expected) != 2:
    raise SystemExit('companion cask quit stanza must be maintained for both existing and newly-created casks')
PY
}

test_companion_release_versions_stay_in_sync() {
  python3 - <<'PY'
import json
import re
from pathlib import Path

manifest_version = json.loads(Path('.release-please-manifest.json').read_text())['apps/workbranch-companion']
package_version = json.loads(Path('apps/workbranch-companion/package.json').read_text())['version']
tauri_version = json.loads(Path('apps/workbranch-companion/src-tauri/tauri.conf.json').read_text())['version']
cargo_toml = Path('apps/workbranch-companion/src-tauri/Cargo.toml').read_text()
cargo_toml_version = re.search(r'^version = "([^"]+)"$', cargo_toml, flags=re.MULTILINE).group(1)
cargo_lock = Path('apps/workbranch-companion/src-tauri/Cargo.lock').read_text()
cargo_lock_match = re.search(
    r'(?ms)^\[\[package\]\]\nname = "workbranch-companion"\nversion = "([^"]+)"$',
    cargo_lock,
)
if cargo_lock_match is None:
    raise SystemExit('Cargo.lock must include the workbranch-companion package entry')
cargo_lock_version = cargo_lock_match.group(1)

versions = {
    'release manifest': manifest_version,
    'package.json': package_version,
    'tauri.conf.json': tauri_version,
    'Cargo.toml': cargo_toml_version,
    'Cargo.lock': cargo_lock_version,
}
if len(set(versions.values())) != 1:
    raise SystemExit(f'companion release versions are out of sync: {versions}')
PY
}
