runtime_binary() {
  local candidate self
  if [ -n "${WORKBRANCH_RUNTIME_BIN:-}" ]; then
    [ -x "$WORKBRANCH_RUNTIME_BIN" ] || die "runtime binary is not executable: $WORKBRANCH_RUNTIME_BIN"
    printf '%s' "$WORKBRANCH_RUNTIME_BIN"
    return
  fi
  self=$(workbranch_self_path)
  candidate="${self%/*}/workbranch-agent-runtime"
  if [ -x "$candidate" ]; then printf '%s' "$candidate"; return; fi
  # A source checkout must not accidentally use an older installed collector.
  if [ -f "${self%/*}/../src/workbranch/main.sh" ] && [ -f "${self%/*}/../../agent-runtime/Cargo.toml" ]; then
    for candidate in "${self%/*}/../../agent-runtime/target/debug/workbranch-agent-runtime" "${self%/*}/../../agent-runtime/target/release/workbranch-agent-runtime"; do
      if [ -x "$candidate" ]; then printf '%s' "$candidate"; return; fi
    done
    die "Build the runtime collector: cargo build --manifest-path apps/agent-runtime/Cargo.toml"
  fi
  candidate="$HOME/.local/bin/workbranch-agent-runtime"
  if [ -x "$candidate" ]; then printf '%s' "$candidate"; return; fi
  command -v workbranch-agent-runtime 2>/dev/null || die "Install/update the workbranch runtime collector with workbranch (workbranch-agent-runtime missing)"
}

cmd_runtime() {
  [ "$#" -eq 1 ] && [ "$1" = "--json" ] || die "usage: workbranch runtime --json"
  "$(runtime_binary)" snapshot
}

cmd_migrate() {
  local mode global root path self
  local -a workspaces
  [ "${1:-}" = "agent-runtime" ] || die "usage: workbranch migrate agent-runtime --dry-run|--apply [--global]"
  shift
  mode=${1:-}
  case "$mode" in --dry-run|--apply) ;; *) die "migration requires --dry-run or --apply" ;; esac
  shift
  global=0
  if [ "${1:-}" = "--global" ]; then global=1; shift; fi
  [ $# -eq 0 ] || die "unexpected migration argument"
  workspaces=()
  if [ "$global" -eq 1 ]; then
    while IFS= read -r root; do
      [ -n "$root" ] || continue
      [ -d "$root" ] || continue
      for path in "$root"/*; do
        [ -f "$path/.workbranch.task" ] && [ ! -L "$path" ] && workspaces[${#workspaces[@]}]="$path"
      done
    done <<EOF_ROOTS
$(registry_list_roots)
EOF_ROOTS
  else
    require_project
    for path in "$PROJECT_ROOT"/*; do
      is_task_workspace_path "$path" || continue
      workspaces[${#workspaces[@]}]="$path"
    done
  fi
  if [ -d "$HOME/.workbranch" ] && [ ! -L "$HOME/.workbranch" ]; then workspaces[${#workspaces[@]}]="$HOME/.workbranch"; fi
  "$(runtime_binary)" migrate "$mode" "${workspaces[@]}"
}

cmd_capabilities() {
  [ "$#" -eq 1 ] && [ "$1" = "--json" ] || die "usage: workbranch capabilities --json"
  printf '%s\n' '{"schemaVersion":1,"listSchemaVersion":2,"runtimeSchemaVersion":1,"grokTrustConfirmation":true,"providers":["claude","codex","grok"]}'
}

# Claude and Codex refuse to re-add a marketplace name from a different source
# (e.g. an old dev checkout directory -> GitHub), so drop any previous
# registration first. A missing registration is not an error.
hooks_remove_marketplace() {
  "$1" plugin marketplace remove "$2" >/dev/null 2>&1 || true
}

# Grok keeps one copy per install source, so switching sources would run the
# hooks twice. Install first so a declined trust prompt leaves the existing copy
# untouched; if older copies remain, clear every copy and install once more.
hooks_grok_install() {
  local install_source=$1 plugin=$2 trust=$3 count
  local -a trust_args
  trust_args=()
  [ "$trust" -eq 1 ] && trust_args=(--trust)
  grok plugin install "$install_source" ${trust_args[@]+"${trust_args[@]}"} || return
  count=$(grok plugin list --json 2>/dev/null | grep -c "\"name\": *\"$plugin\"") || count=0
  [ "$count" -gt 1 ] || return 0
  info "Replacing $((count - 1)) Grok plugin install(s) from other sources: $plugin"
  while grok plugin uninstall "$plugin" >/dev/null 2>&1; do count=$((count - 1)); [ "$count" -ge 0 ] || break; done
  grok plugin install "$install_source" ${trust_args[@]+"${trust_args[@]}"} || return
}

cmd_hooks() {
  local action provider binary source self plugin trust expected_source install_source
  action=${1:-}; [ $# -gt 0 ] && shift
  [ "${1:-}" = "--provider" ] && [ $# -ge 2 ] || die "usage: workbranch hooks install|status|uninstall --provider claude|codex|grok [--source <path>]"
  provider=$2; shift 2
  source=""; trust=0; expected_source=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --source)
        [ $# -ge 2 ] && [ -d "$2" ] || die "plugin source directory not found"
        source=$(cd "$2" && pwd -P) || return
        shift 2 ;;
      --trust) trust=1; shift ;;
      --expected-source)
        [ $# -ge 2 ] && [ -n "$2" ] || die "approved plugin source is required"
        expected_source=$2; shift 2 ;;
      *) die "unexpected hooks argument: $1" ;;
    esac
  done
  case "$provider" in claude|codex|grok) ;; *) die "unsupported provider: $provider" ;; esac
  if [ "$trust" -eq 1 ]; then
    [ "$provider" = "grok" ] && [ "$action" = "install" ] || die "--trust is only valid for an explicitly approved Grok install"
  fi
  if [ -n "$expected_source" ]; then [ "$trust" -eq 1 ] || die "--expected-source requires --trust"; fi
  self=$(workbranch_self_path)
  if [ -z "$source" ] && [ -f "${self%/*}/../src/workbranch/main.sh" ]; then
    source=$(cd "${self%/*}/../../.." && pwd -P) || return
  fi
  install_source=${source:-tkhwang/workbranch}
  if [ "$provider" = "grok" ]; then
    if [ -n "$source" ]; then install_source="$source/integrations/agent-events/grok/plugins/workbranch-agent-events-grok"
    else install_source='tkhwang/workbranch#integrations/agent-events/grok/plugins/workbranch-agent-events-grok'; fi
  fi
  if [ -n "$expected_source" ] && [ "$expected_source" != "$install_source" ]; then
    die "Plugin source changed since approval. Review the new source before retrying."
  fi
  plugin=workbranch-agent-events@workbranch-runtime
  [ "$provider" != "grok" ] || plugin=workbranch-agent-events-grok
  case "$action" in
    describe)
      printf '{"provider":'; json_string "$provider"
      printf ',"plugin":'; json_string "$plugin"
      printf ',"source":'; json_string "$install_source"
      printf '}\n'
      ;;
    install)
      binary=$(runtime_binary) || return
      "$binary" version >/dev/null || die "runtime collector unavailable"
      "$binary" register "$binary" || die "failed to register hook collector"
      if [ "$provider" = "grok" ]; then
        hooks_grok_install "$install_source" "$plugin" "$trust" || return
        grok plugin enable "$plugin" || return
      elif [ "$provider" = "claude" ]; then
        hooks_remove_marketplace claude "${plugin#*@}"
        if [ -n "$source" ]; then claude plugin marketplace add "$source" || return
        else claude plugin marketplace add tkhwang/workbranch --sparse .claude-plugin integrations/agent-events/claude-code || return; fi
        claude plugin install "$plugin" || return
        claude plugin enable "$plugin" || return
      else
        hooks_remove_marketplace codex "${plugin#*@}"
        if [ -n "$source" ]; then codex plugin marketplace add "$source" || return
        else codex plugin marketplace add tkhwang/workbranch --sparse .agents/plugins --sparse integrations/agent-events/codex || return; fi
        codex plugin add "$plugin" || return
      fi
      info "Configured. Review provider-native hook trust and restart the agent. First event confirms collection."
      ;;
    status) "$provider" plugin list --json ;;
    uninstall)
      if [ "$provider" = "codex" ]; then codex plugin remove "$plugin"; else "$provider" plugin uninstall "$plugin"; fi
      ;;
    *) die "usage: workbranch hooks install|status|uninstall --provider claude|codex|grok" ;;
  esac
}
