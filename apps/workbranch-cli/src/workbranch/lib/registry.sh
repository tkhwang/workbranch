registry_path() {
  printf '%s/workbranch-companion/projects.md' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

registry_ensure_file() {
  local file dir
  file=$(registry_path)
  dir=$(dirname "$file")
  mkdir -p "$dir" || die "failed to create companion registry directory: $dir"
  if [ ! -f "$file" ]; then
    cat > "$file" <<'REGISTRY'
# workbranch companion projects

## projects
REGISTRY
  fi
}

registry_lock_path() {
  printf '%s.lock' "$(registry_path)"
}

registry_lock_wait() {
  sleep 0.1 2>/dev/null || sleep 1
}

registry_lock_acquire() {
  local lock dir attempts
  lock=$(registry_lock_path)
  dir=$(dirname "$lock")
  mkdir -p "$dir" || die "failed to create companion registry directory: $dir"
  attempts=${WORKBRANCH_REGISTRY_LOCK_RETRIES:-100}
  while ! mkdir "$lock" 2>/dev/null; do
    attempts=$((attempts - 1))
    [ "$attempts" -gt 0 ] || die "failed to acquire companion registry lock: $lock"
    registry_lock_wait
  done
  printf '%s' "$lock"
}

registry_lock_release() {
  local lock
  lock=$1
  [ -z "$lock" ] || rmdir "$lock" 2>/dev/null || true
}

registry_abort_locked() {
  local lock tmp message
  lock=$1
  tmp=$2
  message=$3
  [ -z "$tmp" ] || rm -f "$tmp"
  registry_lock_release "$lock"
  die "$message"
}

registry_normalize_root() {
  local root
  root=$1
  [ -d "$root" ] || die "registry root is not a directory: $root"
  (cd "$root" && pwd -P) || die "failed to normalize registry root: $root"
}

# Returns success when the given absolute, symlink-resolved path lives under a
# temporary directory (TMPDIR, /tmp, or macOS /var/folders). Used to keep
# throwaway test/demo projects out of the persistent companion registry.
registry_path_is_temp() {
  local path tmpdir
  path=$1
  case "$path" in
    /tmp|/tmp/*|/private/tmp|/private/tmp/*|/var/folders/*|/private/var/folders/*)
      return 0 ;;
  esac
  if [ -n "${TMPDIR:-}" ]; then
    tmpdir=${TMPDIR%/}
    case "$path" in
      "$tmpdir"|"$tmpdir"/*) return 0 ;;
    esac
  fi
  return 1
}

registry_add_root() {
  local root file dir tmp lock
  root=$(registry_normalize_root "$1")
  # Skip transient project roots so test/demo runs under TMPDIR do not pollute
  # the companion project list. Set WORKBRANCH_ALLOW_TEMP_REGISTRY=1 to opt in
  # (used by the test harness, which isolates the registry under TMPDIR).
  if [ "${WORKBRANCH_ALLOW_TEMP_REGISTRY:-0}" != "1" ] && registry_path_is_temp "$root"; then
    printf 'Skipping companion registry for temporary path: %s\n' "$root" >&2
    return 0
  fi
  file=$(registry_path)
  tmp=""
  lock=$(registry_lock_acquire)
  dir=$(dirname "$file")
  mkdir -p "$dir" || registry_abort_locked "$lock" "$tmp" "failed to create companion registry directory: $dir"
  if [ ! -f "$file" ]; then
    cat > "$file" <<'REGISTRY' || registry_abort_locked "$lock" "$tmp" "failed to update companion registry: $file"
# workbranch companion projects

## projects
REGISTRY
  fi
  if registry_list_roots | grep -Fx -- "$root" >/dev/null 2>&1; then
    registry_lock_release "$lock"
    return 0
  fi
  if ! grep -Eq '^[[:space:]]*##[[:space:]]+projects[[:space:]]*$' "$file"; then
    printf '\n## projects\n' >> "$file" || registry_abort_locked "$lock" "$tmp" "failed to update companion registry: $file"
  fi
  tmp=$(mktemp "${TMPDIR:-/tmp}/workbranch-registry.XXXXXX") || registry_abort_locked "$lock" "$tmp" "failed to create registry temp file"
  awk -v root="$root" '
    { print }
    /^[[:space:]]*##[[:space:]]+projects[[:space:]]*$/ { seen = 1 }
    END {
      if (seen) print "- " root
    }
  ' "$file" > "$tmp" || registry_abort_locked "$lock" "$tmp" "failed to update companion registry: $file"
  mv "$tmp" "$file" || registry_abort_locked "$lock" "$tmp" "failed to update companion registry: $file"
  tmp=""
  registry_lock_release "$lock"
}

registry_remove_root() {
  local root file tmp lock
  root=$1
  case "$root" in /*) ;; *) root=$(registry_normalize_root "$root") ;; esac
  file=$(registry_path)
  tmp=""
  lock=$(registry_lock_acquire)
  [ -f "$file" ] || { registry_lock_release "$lock"; return 0; }
  tmp=$(mktemp "${TMPDIR:-/tmp}/workbranch-registry.XXXXXX") || registry_abort_locked "$lock" "$tmp" "failed to create registry temp file"
  awk -v root="$root" '
    /^[[:space:]]*-[[:space:]]*\// {
      value = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      if (value == root) next
    }
    { print }
  ' "$file" > "$tmp" || registry_abort_locked "$lock" "$tmp" "failed to update companion registry: $file"
  mv "$tmp" "$file" || registry_abort_locked "$lock" "$tmp" "failed to update companion registry: $file"
  tmp=""
  registry_lock_release "$lock"
}

registry_list_roots() {
  local file
  file=$(registry_path)
  [ -f "$file" ] || return 0
  awk '
    /^[[:space:]]*-[[:space:]]*\// {
      value = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      print value
    }
  ' "$file"
}

registry_workbranch_bin() {
  local file
  file=$(registry_path)
  [ -f "$file" ] || return 0
  awk '
    /^[[:space:]]*workbranchBin:[[:space:]]*/ {
      value = $0
      sub(/^[[:space:]]*workbranchBin:[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      print value
      exit
    }
  ' "$file"
}
