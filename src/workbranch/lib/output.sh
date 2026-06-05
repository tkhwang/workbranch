color_enabled_startup() {
  _wb_fd=$1
  [ -z "${NO_COLOR:-}" ] || return 1
  case "${WORKBRANCH_COLOR:-auto}" in
    always) return 0 ;;
    never) return 1 ;;
    auto|'') [ -t "$_wb_fd" ] && [ "${TERM:-}" != "dumb" ] ;;
    *) [ -t "$_wb_fd" ] && [ "${TERM:-}" != "dumb" ] ;;
  esac
}

if color_enabled_startup 1; then
  WB_COLOR_ENABLED=1
  WB_ESC=$'\033'
  WB_GREEN="${WB_ESC}[0;32m"
  WB_BLUE="${WB_ESC}[0;34m"
  WB_CYAN="${WB_ESC}[0;36m"
  WB_YELLOW="${WB_ESC}[0;33m"
  WB_PURPLE="${WB_ESC}[0;35m"
  WB_PURPLE_BOLD="${WB_ESC}[1;35m"
  WB_RED="${WB_ESC}[0;31m"
  WB_GRAY="${WB_ESC}[0;90m"
  WB_BOLD="${WB_ESC}[1m"
  WB_RESET="${WB_ESC}[0m"
else
  WB_COLOR_ENABLED=0
  WB_ESC=""
  WB_GREEN=""
  WB_BLUE=""
  WB_CYAN=""
  WB_YELLOW=""
  WB_PURPLE=""
  WB_PURPLE_BOLD=""
  WB_RED=""
  WB_GRAY=""
  WB_BOLD=""
  WB_RESET=""
fi

if color_enabled_startup 2; then
  WB_COLOR_ERR_ENABLED=1
  WB_ERR_ESC=$'\033'
  WB_ERR_GREEN="${WB_ERR_ESC}[0;32m"
  WB_ERR_BLUE="${WB_ERR_ESC}[0;34m"
  WB_ERR_CYAN="${WB_ERR_ESC}[0;36m"
  WB_ERR_YELLOW="${WB_ERR_ESC}[0;33m"
  WB_ERR_PURPLE="${WB_ERR_ESC}[0;35m"
  WB_ERR_PURPLE_BOLD="${WB_ERR_ESC}[1;35m"
  WB_ERR_RED="${WB_ERR_ESC}[0;31m"
  WB_ERR_GRAY="${WB_ERR_ESC}[0;90m"
  WB_ERR_BOLD="${WB_ERR_ESC}[1m"
  WB_ERR_RESET="${WB_ERR_ESC}[0m"
else
  WB_COLOR_ERR_ENABLED=0
  WB_ERR_ESC=""
  WB_ERR_GREEN=""
  WB_ERR_BLUE=""
  WB_ERR_CYAN=""
  WB_ERR_YELLOW=""
  WB_ERR_PURPLE=""
  WB_ERR_PURPLE_BOLD=""
  WB_ERR_RED=""
  WB_ERR_GRAY=""
  WB_ERR_BOLD=""
  WB_ERR_RESET=""
fi

color_enabled() {
  [ "${WB_COLOR_ENABLED:-0}" -eq 1 ]
}

color_stderr_enabled() {
  [ "${WB_COLOR_ERR_ENABLED:-0}" -eq 1 ]
}

WB_ICON_CONFIRM="◎"
WB_ICON_SUCCESS="✓"
WB_ICON_WARNING="◎"
WB_ICON_LIST="•"
WB_ICON_SUBLIST="↳"
WB_ICON_ARROW="➤"
WB_ICON_REVIEW="☞"

color_text() {
  _wb_color=$1
  shift
  if color_enabled && [ -n "$_wb_color" ]; then
    printf '%s%s%s' "$_wb_color" "$*" "$WB_RESET"
  else
    printf '%s' "$*"
  fi
}

color_cell() {
  _wb_color=$1
  _wb_width=$2
  _wb_value=$3
  _wb_padded=$(printf "%-${_wb_width}s" "$_wb_value")
  color_text "$_wb_color" "$_wb_padded"
}

status_color() {
  case "$1" in
    clean) printf '%s' "$WB_GREEN" ;;
    modified*|untracked) printf '%s' "$WB_YELLOW" ;;
    missing|\?) printf '%s' "$WB_RED" ;;
    *) printf '%s' "$WB_GRAY" ;;
  esac
}

diff_color() {
  case "$1" in
    0) printf '%s' "$WB_GREEN" ;;
    +*) printf '%s' "$WB_GREEN" ;;
    -*|±*) printf '%s' "$WB_YELLOW" ;;
    *) printf '%s' "$WB_GRAY" ;;
  esac
}

next_action_color() {
  case "$1" in
    land) printf '%s' "$WB_GREEN" ;;
    update|check) printf '%s' "$WB_YELLOW" ;;
    -) printf '%s' "$WB_GRAY" ;;
    *) printf '%s' "$WB_GRAY" ;;
  esac
}

table_header() {
  color_cell "$WB_GRAY" "$1" "$2"
}

color_status() {
  status_color "$1"
}

color_diff() {
  diff_color "$1"
}

color_next_action() {
  next_action_color "$1"
}

section() {
  if color_enabled; then
    printf '\n%s%s %s%s\n' "$WB_PURPLE_BOLD" "$WB_ICON_ARROW" "$1" "$WB_RESET"
  else
    info "$1"
  fi
}

item_ok() {
  if color_enabled; then
    printf '  %s%s%s %s\n' "$WB_GREEN" "$WB_ICON_SUCCESS" "$WB_RESET" "$*"
  else
    success "$*"
  fi
}

item_warn() {
  if color_enabled; then
    printf '  %s%s%s %s\n' "$WB_YELLOW" "$WB_ICON_WARNING" "$WB_RESET" "$*"
  else
    info "$*"
  fi
}

item_info() {
  if color_enabled; then
    printf '  %s%s%s %s\n' "$WB_GREEN" "$WB_ICON_LIST" "$WB_RESET" "$*"
  else
    info "$*"
  fi
}

item_detail() {
  if color_enabled; then
    printf '  %s%s %s%s\n' "$WB_GRAY" "$WB_ICON_SUBLIST" "$*" "$WB_RESET"
  else
    printf '    %s\n' "$*"
  fi
}

item_review() {
  if color_enabled; then
    printf '  %s%s %s%s\n' "$WB_GRAY" "$WB_ICON_REVIEW" "$*" "$WB_RESET"
  else
    printf '    %s\n' "$*"
  fi
}

info() { printf '%s[*]%s %s\n' "$WB_BLUE" "$WB_RESET" "$*"; }

success() { printf '%s[+]%s %s\n' "$WB_GREEN" "$WB_RESET" "$*"; }

die() { printf '%s[-] Error:%s %s\n' "$WB_ERR_RED" "$WB_ERR_RESET" "$*" >&2; exit 1; }
