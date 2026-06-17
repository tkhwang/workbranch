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
    {'type': 'generic', 'path': 'src-tauri/Cargo.lock'},
]
if companion_extra_files != expected_companion_extra_files:
    raise SystemExit(f'companion extra-files mismatch: {companion_extra_files}')

sample_companion_only_files = [
    'apps/workbranch-companion/src/App.tsx',
    'packages/contract/src/index.ts',
    'docs/plans/0027-companion-launch-at-login.md',
    'DESIGN.md',
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

test_homebrew_formula_template_tracks_cli_layout() {
  python3 - <<'PY'
from pathlib import Path

formula = Path('packaging/homebrew/workbranch.rb').read_text()
workflow = Path('.github/workflows/homebrew-bump.yml').read_text()

expected_formula_lines = [
    'system "apps/workbranch-cli/scripts/build-workbranch.sh"',
    'bin.install "apps/workbranch-cli/bin/workbranch"',
]
missing_formula_lines = [line for line in expected_formula_lines if line not in formula]
if missing_formula_lines:
    raise SystemExit(f'Homebrew formula template must build moved CLI layout: {missing_formula_lines}')

expected_workflow_lines = [
    'FORMULA_TEMPLATE="workbranch/packaging/homebrew/workbranch.rb"',
    'cp "$FORMULA_TEMPLATE" "$FORMULA_PATH"',
]
missing_workflow_lines = [line for line in expected_workflow_lines if line not in workflow]
if missing_workflow_lines:
    raise SystemExit(f'Homebrew bump workflow must copy the formula template before stamping URL/SHA: {missing_workflow_lines}')
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
    r'(?m)^name = "workbranch-companion"\nversion = "([^"]+)"(?:\s+# x-release-please-version)?$',
    cargo_lock,
)
if cargo_lock_match is None:
    raise SystemExit('Cargo.lock must include the workbranch-companion package entry')
if 'name = "workbranch-companion"\nversion = "' + cargo_lock_match.group(1) + '" # x-release-please-version' not in cargo_lock:
    raise SystemExit('[-] Error: Cargo.lock workbranch-companion version must carry x-release-please-version marker')
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
