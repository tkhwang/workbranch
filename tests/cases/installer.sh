# shellcheck shell=bash
# Sourced by tests/run.sh; uses helpers from tests/lib/helpers.sh.
test_installer_supports_pipe_to_bash() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/standalone" "$TMP_ROOT/server/bin"
  cp "$REPO_ROOT/install.sh" "$TMP_ROOT/standalone/install.sh"
  cp "$WORKBRANCH" "$TMP_ROOT/server/bin/workbranch"
  cd "$TMP_ROOT/server" || return 1
  python3 -m http.server 8765 >/tmp/workbranch-test-http.log 2>&1 &
  server_pid=$!
  cd "$TMP_ROOT/standalone" || return 1
  sleep 1
  out=$(HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" WORKBRANCH_RAW_BASE_URL="http://127.0.0.1:8765" bash < "$TMP_ROOT/standalone/install.sh" 2>&1)
  kill "$server_pid" 2>/dev/null || true
  assert_contains "$out" "Downloaded workbranch"
  assert_contains "$out" "Installed workbranch"
  assert_file "$TMP_ROOT/home/.local/bin/workbranch"
  [ -x "$TMP_ROOT/home/.local/bin/workbranch" ] || fail "pipe-to-bash installed workbranch is not executable"
  out=$(HOME="$TMP_ROOT/home" "$TMP_ROOT/home/.local/bin/workbranch" help 2>&1)
  assert_contains "$out" "Usage:"
  assert_contains "$out" "workbranch <command> [args]"
}

test_installer_pipe_to_bash_ignores_cwd_bin_workbranch() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/standalone/bin" "$TMP_ROOT/server/bin"
  cp "$REPO_ROOT/install.sh" "$TMP_ROOT/standalone/install.sh"
  cat > "$TMP_ROOT/standalone/bin/workbranch" <<'STALE'
#!/usr/bin/env sh
printf '%s\n' STALE
STALE
  chmod +x "$TMP_ROOT/standalone/bin/workbranch"
  mkdir -p "$TMP_ROOT/standalone/.git"
  : > "$TMP_ROOT/standalone/bash"
  cat > "$TMP_ROOT/server/bin/workbranch" <<'REMOTE'
#!/usr/bin/env sh
printf '%s\n' REMOTE
REMOTE
  chmod +x "$TMP_ROOT/server/bin/workbranch"

  cd "$TMP_ROOT/standalone" || return 1
  out=$(HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" WORKBRANCH_RAW_BASE_URL="file://$TMP_ROOT/server" bash < "$TMP_ROOT/standalone/install.sh" 2>&1)
  assert_contains "$out" "Downloaded workbranch"
  installed_out=$("$TMP_ROOT/home/.local/bin/workbranch")
  [ "$installed_out" = "REMOTE" ] || fail "expected pipe install to download REMOTE, got: $installed_out"
}

test_installer_downloads_cli_when_run_standalone() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/standalone/bin" "$TMP_ROOT/server/bin"
  cp "$REPO_ROOT/install.sh" "$TMP_ROOT/standalone/install.sh"
  cp "$WORKBRANCH" "$TMP_ROOT/server/bin/workbranch"
  cd "$TMP_ROOT/server" || return 1
  python3 -m http.server 8765 >/tmp/workbranch-test-http.log 2>&1 &
  server_pid=$!
  cd "$REPO_ROOT" || return 1
  sleep 1
  out=$(printf '\nn\n' | HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" WORKBRANCH_RAW_BASE_URL="http://127.0.0.1:8765" "$TMP_ROOT/standalone/install.sh" 2>&1)
  kill "$server_pid" 2>/dev/null || true
  assert_contains "$out" "Downloaded workbranch"
  assert_file "$TMP_ROOT/home/.local/bin/workbranch"
  [ -x "$TMP_ROOT/home/.local/bin/workbranch" ] || fail "standalone installed workbranch is not executable"
  out=$(HOME="$TMP_ROOT/home" "$TMP_ROOT/home/.local/bin/workbranch" help 2>&1)
  assert_contains "$out" "Usage:"
  assert_contains "$out" "workbranch <command> [args]"
}

test_installer_standalone_uses_embedded_raw_base_url() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  mkdir -p "$TMP_ROOT/standalone" "$TMP_ROOT/server/bin"
  sed "s#https://raw.githubusercontent.com/tkhwang/workbranch/main#file://$TMP_ROOT/server#g" "$REPO_ROOT/install.sh" > "$TMP_ROOT/standalone/install.sh"
  chmod +x "$TMP_ROOT/standalone/install.sh"
  cat > "$TMP_ROOT/server/bin/workbranch" <<'REMOTE'
#!/usr/bin/env sh
printf '%s\n' EMBEDDED
REMOTE
  chmod +x "$TMP_ROOT/server/bin/workbranch"

  out=$(printf '\nn\n' | HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" "$TMP_ROOT/standalone/install.sh" 2>&1)
  assert_contains "$out" "Downloaded workbranch from file://$TMP_ROOT/server"
  assert_contains "$out" "Installed workbranch"
  installed_out=$("$TMP_ROOT/home/.local/bin/workbranch")
  [ "$installed_out" = "EMBEDDED" ] || fail "expected embedded default install to download EMBEDDED, got: $installed_out"
}

test_installer_installs_executable() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  out=$(printf '\nn\n' | HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" "$REPO_ROOT/install.sh" 2>&1)
  assert_contains "$out" "[*] Target directory"
  assert_contains "$out" "Installed workbranch"
  assert_contains "$out" "[*] Try it now:"
  assert_contains "$out" "workbranch help     show all commands"
  assert_contains "$out" "workbranch init     create your first workbranch project"
  assert_contains "$out" "not on your PATH"
  assert_contains "$out" "Add it to your PATH now? [y/N]"
  assert_contains "$out" "Run directly:"
  assert_file "$TMP_ROOT/home/.local/bin/workbranch"
  [ -x "$TMP_ROOT/home/.local/bin/workbranch" ] || fail "installed workbranch is not executable"
  out=$(HOME="$TMP_ROOT/home" "$TMP_ROOT/home/.local/bin/workbranch" help 2>&1)
  assert_contains "$out" "Usage:"
  assert_contains "$out" "workbranch <command> [args]"
}

test_installer_uses_custom_target_directory() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  custom_dir="$TMP_ROOT/custom-bin"
  out=$(printf '%s\nn\n' "$custom_dir" | HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" "$REPO_ROOT/install.sh" 2>&1)
  assert_contains "$out" "Installed workbranch to $custom_dir/workbranch"
  assert_contains "$out" "[*] Try it now:"
  assert_contains "$out" "$custom_dir is not on your PATH"
  assert_file "$custom_dir/workbranch"
  [ -x "$custom_dir/workbranch" ] || fail "custom installed workbranch is not executable"
  out=$("$custom_dir/workbranch" help 2>&1)
  assert_contains "$out" "Usage:"
}

test_installer_can_add_target_directory_to_zshrc() {
  TMP_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t workbranch-test)
  custom_dir="$TMP_ROOT/custom-bin"
  out=$(printf '%s\ny\n' "$custom_dir" | HOME="$TMP_ROOT/home" PATH="/usr/bin:/bin" SHELL="/bin/zsh" "$REPO_ROOT/install.sh" 2>&1)
  assert_contains "$out" "Added PATH entry to $TMP_ROOT/home/.zshrc"
  assert_file "$TMP_ROOT/home/.zshrc"
  assert_contains "$(cat "$TMP_ROOT/home/.zshrc")" "export PATH=\"$custom_dir:\$PATH\""
}

