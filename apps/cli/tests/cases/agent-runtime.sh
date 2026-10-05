test_runtime_replaces_brief_and_migrates() {
  set -e
  new_fixture
  cd "$FIXTURE_PROJECT" || return 1
  run_expect_success "$WORKBRANCH" init >/dev/null
  run_expect_success "$WORKBRANCH" add runtime-test >/dev/null
  [ ! -f runtime-test/TASK-WORKBRANCH.md ] || fail "add still creates brief"
  assert_not_contains "$(cat runtime-test/AGENTS.md)" "status:"
  run_expect_fail "$WORKBRANCH" memo runtime-test >/dev/null
  run_expect_fail "$WORKBRANCH" done runtime-test >/dev/null
  export WORKBRANCH_RUNTIME_BIN="$REPO_ROOT/apps/agent-runtime/target/debug/workbranch-agent-runtime"
  export WORKBRANCH_RUNTIME_DIR="$FIXTURE_PROJECT/.runtime-test"
  [ -x "$WORKBRANCH_RUNTIME_BIN" ] || fail "build runtime collector before CLI tests"
  printf '# Legacy\nstatus: planning\n' > runtime-test/TASK-WORKBRANCH.md
  out=$(run_expect_success "$WORKBRANCH" migrate agent-runtime --dry-run)
  assert_contains "$out" 'TASK-WORKBRANCH.md'
  [ -f runtime-test/TASK-WORKBRANCH.md ] || fail "dry-run deleted data"
  run_expect_success "$WORKBRANCH" migrate agent-runtime --apply >/dev/null
  [ ! -f runtime-test/TASK-WORKBRANCH.md ] || fail "migration retained brief"
  out=$(run_expect_success "$WORKBRANCH" list --json)
  assert_contains "$out" '"schemaVersion":2'
  assert_not_contains "$out" '"planTitle"'
  printf '{"hook_event_name":"UserPromptSubmit","session_id":"test","cwd":"%s/runtime-test","prompt":"run tests"}' "$PWD" | "$WORKBRANCH_RUNTIME_BIN" ingest claude
  out=$(run_expect_success "$WORKBRANCH" runtime --json)
  assert_contains "$out" 'run tests'
}

test_hooks_delegate_without_modifying_user_configuration() {
  set -e
  new_fixture
  mkdir -p "$TMP_ROOT/hooks-bin"
  export WORKBRANCH_HOOK_TEST_LOG="$TMP_ROOT/hook-calls"
  export WORKBRANCH_RUNTIME_DIR="$TMP_ROOT/runtime"
  for provider in claude codex; do
    cat > "$TMP_ROOT/hooks-bin/$provider" <<'EOF_PROVIDER'
#!/bin/sh
printf '%s\n' "$*" >> "$WORKBRANCH_HOOK_TEST_LOG"
EOF_PROVIDER
    chmod +x "$TMP_ROOT/hooks-bin/$provider"
  done
  export WORKBRANCH_RUNTIME_BIN="$REPO_ROOT/apps/agent-runtime/target/debug/workbranch-agent-runtime"
  out=$(PATH="$TMP_ROOT/hooks-bin:$PATH" "$WORKBRANCH" hooks install --provider claude)
  assert_contains "$out" 'hook trust'
  PATH="$TMP_ROOT/hooks-bin:$PATH" "$WORKBRANCH" hooks install --provider codex >/dev/null
  PATH="$TMP_ROOT/hooks-bin:$PATH" "$WORKBRANCH" hooks uninstall --provider codex
  calls=$(cat "$WORKBRANCH_HOOK_TEST_LOG")
  assert_contains "$calls" "marketplace add $REPO_ROOT"
  assert_contains "$calls" "marketplace add $REPO_ROOT"
  assert_contains "$calls" 'plugin add workbranch-agent-events@workbranch-runtime'
  assert_contains "$calls" 'plugin remove workbranch-agent-events@workbranch-runtime'
}

test_hooks_replace_stale_provider_registrations() {
  set -e
  new_fixture
  local provider grok_source
  mkdir -p "$TMP_ROOT/hooks-bin"
  export WORKBRANCH_RUNTIME_DIR="$TMP_ROOT/runtime"
  export WORKBRANCH_RUNTIME_BIN="$REPO_ROOT/apps/agent-runtime/target/debug/workbranch-agent-runtime"
  for provider in claude codex; do
    export WORKBRANCH_HOOK_TEST_LOG="$TMP_ROOT/$provider-calls"
    cat > "$TMP_ROOT/hooks-bin/$provider" <<'EOF_PROVIDER'
#!/bin/sh
printf '%s\n' "$*" >> "$WORKBRANCH_HOOK_TEST_LOG"
case "$*" in 'plugin marketplace remove '*) echo 'not configured' >&2; exit 1 ;; esac
EOF_PROVIDER
    chmod +x "$TMP_ROOT/hooks-bin/$provider"
    PATH="$TMP_ROOT/hooks-bin:$PATH" "$WORKBRANCH" hooks install --provider "$provider" >/dev/null
    assert_contains "$(cat "$WORKBRANCH_HOOK_TEST_LOG")" 'plugin marketplace remove workbranch-runtime'
    [ "$(grep -n 'marketplace remove' "$WORKBRANCH_HOOK_TEST_LOG" | cut -d: -f1)" -lt "$(grep -n 'marketplace add' "$WORKBRANCH_HOOK_TEST_LOG" | cut -d: -f1)" ] || fail "$provider stale marketplace must be removed before add"
  done

  # Grok keeps one install per source: after installing, two copies remain until cleared.
  export WORKBRANCH_HOOK_TEST_LOG="$TMP_ROOT/grok-calls"
  export WORKBRANCH_GROK_COPIES="$TMP_ROOT/grok-copies"
  printf '2\n' > "$WORKBRANCH_GROK_COPIES"
  cat > "$TMP_ROOT/hooks-bin/grok" <<'EOF_PROVIDER'
#!/bin/sh
printf '%s\n' "$*" >> "$WORKBRANCH_HOOK_TEST_LOG"
copies=$(cat "$WORKBRANCH_GROK_COPIES")
case "$*" in
  'plugin list --json') i=0; while [ "$i" -lt "$copies" ]; do printf '{"name": "workbranch-agent-events-grok"}\n'; i=$((i + 1)); done ;;
  'plugin uninstall '*) [ "$copies" -gt 0 ] || exit 1; echo $((copies - 1)) > "$WORKBRANCH_GROK_COPIES" ;;
  'plugin install '*) [ "$copies" -gt 0 ] || echo 1 > "$WORKBRANCH_GROK_COPIES" ;;
esac
EOF_PROVIDER
  chmod +x "$TMP_ROOT/hooks-bin/grok"
  grok_source="$REPO_ROOT/integrations/agent-events/grok/plugins/workbranch-agent-events-grok"
  PATH="$TMP_ROOT/hooks-bin:$PATH" "$WORKBRANCH" hooks install --provider grok --trust --expected-source "$grok_source" >/dev/null
  [ "$(grep -c "^plugin install $grok_source --trust$" "$WORKBRANCH_HOOK_TEST_LOG")" -eq 2 ] || fail 'grok must reinstall after clearing stale copies'
  assert_contains "$(cat "$WORKBRANCH_HOOK_TEST_LOG")" 'plugin uninstall workbranch-agent-events-grok'
  [ "$(cat "$WORKBRANCH_GROK_COPIES")" = 1 ] || fail 'grok should end with exactly one install'

  # A single, current install is left alone.
  : > "$WORKBRANCH_HOOK_TEST_LOG"
  PATH="$TMP_ROOT/hooks-bin:$PATH" "$WORKBRANCH" hooks install --provider grok --trust --expected-source "$grok_source" >/dev/null
  assert_not_contains "$(cat "$WORKBRANCH_HOOK_TEST_LOG")" 'plugin uninstall'
}

test_installer_copies_runtime_collector_from_verified_local_build() {
  set -e
  new_fixture
  local destination source_installer
  destination="$TMP_ROOT/installed"
  for source_installer in "$REPO_ROOT/install.sh" "$REPO_ROOT/apps/cli/install.sh"; do
    printf '%s\nn\n' "$destination" | WORKBRANCH_SKIP_RUNTIME_INSTALL=0 WORKBRANCH_RUNTIME_SOURCE="$REPO_ROOT/apps/agent-runtime/target/debug/workbranch-agent-runtime" bash "$source_installer" >/dev/null
    [ -x "$destination/workbranch-agent-runtime" ] || fail "runtime binary missing"
    "$destination/workbranch-agent-runtime" version | grep -q 'schema 1' || fail "wrong runtime binary"
    "$destination/workbranch" version >/dev/null
  done
}

test_grok_hooks_use_own_plugin_without_trust_bypass() {
  set -e
  new_fixture
  mkdir -p "$TMP_ROOT/provider-bin"
  export WORKBRANCH_HOOK_TEST_LOG="$TMP_ROOT/grok-calls"
  export WORKBRANCH_RUNTIME_DIR="$TMP_ROOT/runtime"
  export WORKBRANCH_RUNTIME_BIN="$REPO_ROOT/apps/agent-runtime/target/debug/workbranch-agent-runtime"
  cat > "$TMP_ROOT/provider-bin/grok" <<'EOF_PROVIDER'
#!/bin/sh
printf '%s\n' "$*" >> "$WORKBRANCH_HOOK_TEST_LOG"
EOF_PROVIDER
  chmod +x "$TMP_ROOT/provider-bin/grok"
  PATH="$TMP_ROOT/provider-bin:$PATH" "$WORKBRANCH" hooks install --provider grok >/dev/null
  PATH="$TMP_ROOT/provider-bin:$PATH" "$WORKBRANCH" hooks uninstall --provider grok >/dev/null
  calls=$(cat "$WORKBRANCH_HOOK_TEST_LOG")
  assert_contains "$calls" "plugin install $REPO_ROOT/integrations/agent-events/grok/plugins/workbranch-agent-events-grok"
  assert_contains "$calls" 'plugin uninstall workbranch-agent-events-grok'
  assert_not_contains "$calls" '--trust'
  [ -x "$WORKBRANCH_RUNTIME_DIR/hook-collector" ] || fail 'collector locator missing'
}

test_grok_trust_requires_explicit_flag_and_matching_source() {
  set -e
  new_fixture
  mkdir -p "$TMP_ROOT/provider-bin"
  export WORKBRANCH_HOOK_TEST_LOG="$TMP_ROOT/grok-calls"
  export WORKBRANCH_RUNTIME_DIR="$TMP_ROOT/runtime"
  export WORKBRANCH_RUNTIME_BIN="$REPO_ROOT/apps/agent-runtime/target/debug/workbranch-agent-runtime"
  cat > "$TMP_ROOT/provider-bin/grok" <<'EOF_PROVIDER'
#!/bin/sh
printf '%s\n' "$*" >> "$WORKBRANCH_HOOK_TEST_LOG"
case "$*" in 'plugin install '*--trust) exit 0 ;; 'plugin install '*) echo 'requires confirmation; re-run with --trust' >&2; exit 1 ;; *) exit 0 ;; esac
EOF_PROVIDER
  chmod +x "$TMP_ROOT/provider-bin/grok"
  source_path="$REPO_ROOT/integrations/agent-events/grok/plugins/workbranch-agent-events-grok"
  out=$("$WORKBRANCH" hooks describe --provider grok)
  assert_contains "$out" "$source_path"
  PATH="$TMP_ROOT/provider-bin:$PATH" run_expect_fail "$WORKBRANCH" hooks install --provider grok >/dev/null
  PATH="$TMP_ROOT/provider-bin:$PATH" run_expect_success "$WORKBRANCH" hooks install --provider grok --trust --expected-source "$source_path" >/dev/null
  calls_before=$(cat "$WORKBRANCH_HOOK_TEST_LOG")
  assert_contains "$calls_before" "plugin install $source_path --trust"
  PATH="$TMP_ROOT/provider-bin:$PATH" run_expect_fail "$WORKBRANCH" hooks install --provider grok --trust --expected-source /wrong-source >/dev/null
  [ "$(cat "$WORKBRANCH_HOOK_TEST_LOG")" = "$calls_before" ] || fail 'mismatched trust target executed a provider command'
  run_expect_fail "$WORKBRANCH" hooks install --provider claude --trust >/dev/null
}
