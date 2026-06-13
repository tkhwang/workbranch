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

registry_normalize_root() {
  local root
  root=$1
  [ -d "$root" ] || die "registry root is not a directory: $root"
  (cd "$root" && pwd -P) || die "failed to normalize registry root: $root"
}

registry_add_root() {
  local root file tmp
  root=$(registry_normalize_root "$1")
  registry_ensure_file
  file=$(registry_path)
  if registry_list_roots | grep -Fx -- "$root" >/dev/null 2>&1; then
    return 0
  fi
  if ! grep -Eq '^[[:space:]]*##[[:space:]]+projects[[:space:]]*$' "$file"; then
    printf '\n## projects\n' >> "$file" || die "failed to update companion registry: $file"
  fi
  tmp=$(mktemp "${TMPDIR:-/tmp}/workbranch-registry.XXXXXX") || die "failed to create registry temp file"
  awk -v root="$root" '
    { print }
    /^[[:space:]]*##[[:space:]]+projects[[:space:]]*$/ { seen = 1 }
    END {
      if (seen) print "- " root
    }
  ' "$file" > "$tmp" || { rm -f "$tmp"; die "failed to update companion registry: $file"; }
  mv "$tmp" "$file" || { rm -f "$tmp"; die "failed to update companion registry: $file"; }
}

registry_remove_root() {
  local root file tmp
  root=$1
  case "$root" in /*) ;; *) root=$(registry_normalize_root "$root") ;; esac
  file=$(registry_path)
  [ -f "$file" ] || return 0
  tmp=$(mktemp "${TMPDIR:-/tmp}/workbranch-registry.XXXXXX") || die "failed to create registry temp file"
  awk -v root="$root" '
    /^[[:space:]]*-[[:space:]]*\// {
      value = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      if (value == root) next
    }
    { print }
  ' "$file" > "$tmp" || { rm -f "$tmp"; die "failed to update companion registry: $file"; }
  mv "$tmp" "$file" || { rm -f "$tmp"; die "failed to update companion registry: $file"; }
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
