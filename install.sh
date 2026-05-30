#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
SRC="$SCRIPT_DIR/bin/monotree"
DEST_DIR="${HOME}/.local/bin"
DEST="$DEST_DIR/monotree"

[ -f "$SRC" ] || { printf 'Error: source executable not found: %s\n' "$SRC" >&2; exit 1; }
mkdir -p "$DEST_DIR" || { printf 'Error: failed to create %s\n' "$DEST_DIR" >&2; exit 1; }
cp "$SRC" "$DEST" || { printf 'Error: failed to install monotree\n' >&2; exit 1; }
chmod +x "$DEST" || { printf 'Error: failed to mark executable: %s\n' "$DEST" >&2; exit 1; }
printf 'Installed monotree to %s\n' "$DEST"

case ":${PATH}:" in
  *":${DEST_DIR}:"*) ;;
  *)
    cat <<PATH_WARNING

Warning: ${DEST_DIR} is not on your PATH.
Add this to your shell config:

  export PATH="\$HOME/.local/bin:\$PATH"

For zsh, append it to ~/.zshrc:

  echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> ~/.zshrc

For bash, append it to ~/.bashrc or ~/.bash_profile.
Then restart your shell or source the updated file.
PATH_WARNING
    ;;
esac
