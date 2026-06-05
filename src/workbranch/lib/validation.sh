is_safe_name() {
  [ -n "$1" ] || return 1
  [ "$1" = "." ] && return 1
  [ "$1" = ".." ] && return 1
  case "$1" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

has_whitespace() {
  case "$1" in
    *[[:space:]]*) return 0 ;;
    *) return 1 ;;
  esac
}

validate_safe_name() {
  label=$1
  value=$2
  is_safe_name "$value" || die "invalid $label '$value' (expected [A-Za-z0-9._-]+)"
}

validate_nonempty_no_space() {
  label=$1
  value=$2
  [ -n "$value" ] || die "invalid $label: empty value"
  if has_whitespace "$value"; then
    die "invalid $label '$value': whitespace is not supported"
  fi
}

validate_branch_name() {
  label=$1
  value=$2
  [ -n "$value" ] || die "invalid $label: empty value"
  if has_whitespace "$value"; then
    die "invalid $label '$value': whitespace is not supported"
  fi
  git check-ref-format --branch "$value" >/dev/null 2>&1 || die "invalid $label '$value'"
}
