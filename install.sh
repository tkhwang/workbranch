#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
SRC="$SCRIPT_DIR/bin/monotree"
DEFAULT_DEST_DIR="${HOME}/.local/bin"

expand_target_dir() {
  value=$1
  case "$value" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${value#~/}" ;;
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
      printf '\n# Added by monotree installer\n'
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
  printf '  export PATH="%s:$PATH"\n' "$DEST_DIR"
}

[ -f "$SRC" ] || { printf '[-] Error: source executable not found: %s\n' "$SRC" >&2; exit 1; }

printf '[*] Install monotree\n'
input_dir=$(prompt_read "[*] Target directory [$DEFAULT_DEST_DIR]: ")
if [ -z "$input_dir" ]; then
  DEST_DIR="$DEFAULT_DEST_DIR"
else
  DEST_DIR=$(expand_target_dir "$input_dir")
fi
DEST="$DEST_DIR/monotree"

mkdir -p "$DEST_DIR" || { printf '[-] Error: failed to create %s\n' "$DEST_DIR" >&2; exit 1; }
cp "$SRC" "$DEST" || { printf '[-] Error: failed to install monotree\n' >&2; exit 1; }
chmod +x "$DEST" || { printf '[-] Error: failed to mark executable: %s\n' "$DEST" >&2; exit 1; }
printf '[+] Installed monotree to %s\n' "$DEST"

cat <<USAGE

[*] Try it now:

  monotree help     show all commands
  monotree init     create your first monotree project

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
