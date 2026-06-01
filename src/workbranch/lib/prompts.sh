prompt_read() {
  prompt=$1
  value=""
  if [ -t 0 ]; then
    # Use readline for interactive editing when a real terminal is attached.
    if ! IFS= read -r -e -p "$prompt" value; then
      [ -n "$value" ] || return 1
    fi
  else
    printf '%s' "$prompt" >&2
    if ! IFS= read -r value; then
      [ -n "$value" ] || return 1
    fi
  fi
  printf '%s' "$value"
}

prompt_with_default() {
  prompt=$1
  default=$2
  value=$(prompt_read "[*] $prompt [$default]: ")
  if [ -z "$value" ]; then
    printf '%s' "$default"
  else
    printf '%s' "$value"
  fi
}

prompt_required() {
  prompt=$1
  value=""
  while [ -z "$value" ]; do
    value=$(prompt_read "[*] $prompt: ") || die "input aborted"
    [ -n "$value" ] || printf '[-] %s is required.
' "$prompt" >&2
  done
  printf '%s' "$value"
}

expand_path() {
  value=$1
  case "$value" in
    ".") pwd -P ;;
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${value#~/}" ;;
    /*) printf '%s' "$value" ;;
    *) printf '%s/%s' "$(pwd -P)" "$value" ;;
  esac
}
