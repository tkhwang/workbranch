#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
SRC="$SCRIPT_DIR/bin/workbranch"
WORKBRANCH_DEFAULT_RAW_BASE_URL="https://raw.githubusercontent.com/tkhwang/workbranch/main"
WORKBRANCH_RAW_BASE_URL="${WORKBRANCH_RAW_BASE_URL:-$WORKBRANCH_DEFAULT_RAW_BASE_URL}"
DEFAULT_DEST_DIR="${HOME}/.local/bin"

expand_target_dir() {
  value=$1
  case "$value" in
    \~) printf '%s' "$HOME" ;;
    \~/*) printf '%s/%s' "$HOME" "${value#~/}" ;;
    *) printf '%s' "$value" ;;
  esac
}

prompt_read() {
  prompt=$1
  value=""
  if [ -t 0 ]; then
    IFS= read -r -e -p "$prompt" value || :
  else
    printf '%s' "$prompt" >&2
    IFS= read -r value || :
  fi
  printf '%s' "$value"
}

profile_for_shell() {
  shell_name=${SHELL##*/}
  case "$shell_name" in
    zsh) printf '%s' "$HOME/.zshrc" ;;
    bash) printf '%s' "$HOME/.bash_profile" ;;
    *) return 1 ;;
  esac
}

append_path_entry() {
  profile=$1
  dest_dir=$2
  line="export PATH=\"$dest_dir:\$PATH\""
  mkdir -p "$(dirname "$profile")" || { printf '[-] Error: failed to create profile directory for %s\n' "$profile" >&2; exit 1; }
  touch "$profile" || { printf '[-] Error: failed to write %s\n' "$profile" >&2; exit 1; }
  if grep -Fqx "$line" "$profile" 2>/dev/null; then
    printf '[*] PATH entry already exists in %s\n' "$profile"
  else
    {
      printf '\n# Added by workbranch installer\n'
      printf '%s\n' "$line"
    } >> "$profile" || { printf '[-] Error: failed to update %s\n' "$profile" >&2; exit 1; }
    printf '[+] Added PATH entry to %s\n' "$profile"
  fi
  printf '[*] Restart your shell or run: source %s\n' "$profile"
}

print_direct_usage() {
  printf '[*] Run directly:\n\n'
  printf '  %s help\n\n' "$DEST"
  printf '[*] Or add this manually to your shell config:\n\n'
  printf '  export PATH="%s:$%s"\n' "$DEST_DIR" PATH
}

download_file() {
  url=$1
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$url"
  else
    printf '[-] Error: curl or wget is required for standalone install\n' >&2
    exit 1
  fi
}

printf '[*] Install workbranch\n'
input_dir=$(prompt_read "[*] Target directory [$DEFAULT_DEST_DIR]: ")
if [ -z "$input_dir" ]; then
  DEST_DIR="$DEFAULT_DEST_DIR"
else
  DEST_DIR=$(expand_target_dir "$input_dir")
fi
DEST="$DEST_DIR/workbranch"

mkdir -p "$DEST_DIR" || { printf '[-] Error: failed to create %s\n' "$DEST_DIR" >&2; exit 1; }
if [ -f "$SRC" ]; then
  cp "$SRC" "$DEST" || { printf '[-] Error: failed to install workbranch\n' >&2; exit 1; }
else
  download_file "$WORKBRANCH_RAW_BASE_URL/apps/cli/bin/workbranch" > "$DEST" \
    || download_file "$WORKBRANCH_RAW_BASE_URL/bin/workbranch" > "$DEST" \
    || { rm -f "$DEST"; printf '[-] Error: failed to download workbranch\n' >&2; exit 1; }
  printf '[+] Downloaded workbranch from %s\n' "$WORKBRANCH_RAW_BASE_URL"
fi

chmod +x "$DEST" || { printf '[-] Error: failed to mark executable: %s\n' "$DEST" >&2; exit 1; }
printf '[+] Installed workbranch to %s\n' "$DEST"

cat <<USAGE

[*] Try it now:

  workbranch help     show all commands
  workbranch init     create your first workbranch project

USAGE
case ":${PATH}:" in
  *":${DEST_DIR}:"*) ;;
  *)
    printf '[-] Warning: %s is not on your PATH.\n' "$DEST_DIR"
    if profile=$(profile_for_shell); then
      answer=$(prompt_read "[*] Add it to your PATH now? [y/N]: ")
      case "$answer" in
        y|Y|yes|YES) append_path_entry "$profile" "$DEST_DIR" ;;
        *) print_direct_usage ;;
      esac
    else
      printf '[*] Automatic shell profile update is only supported for zsh and bash.\n'
      print_direct_usage
    fi
    ;;
esac
