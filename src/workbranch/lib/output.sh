info() { printf '[*] %s\n' "$*"; }

success() { printf '[+] %s\n' "$*"; }

die() { printf '[-] Error: %s\n' "$*" >&2; exit 1; }
