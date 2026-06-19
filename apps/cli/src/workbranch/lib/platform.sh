detect_platform() {
  if [ -n "${WORKBRANCH_TEST_PLATFORM:-}" ]; then
    case "$WORKBRANCH_TEST_PLATFORM" in
      macos|linux|wsl|other) printf '%s' "$WORKBRANCH_TEST_PLATFORM" ;;
      *) die "invalid WORKBRANCH_TEST_PLATFORM: $WORKBRANCH_TEST_PLATFORM" ;;
    esac
    return 0
  fi

  case "$(uname -s 2>/dev/null || printf unknown)" in
    Darwin) printf '%s' macos ;;
    Linux)
      if [ -n "${WSL_INTEROP:-}" ] || grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
        printf '%s' wsl
      else
        printf '%s' linux
      fi
      ;;
    *) printf '%s' other ;;
  esac
}

is_core_supported_platform() {
  case "$(detect_platform)" in
    macos|linux|wsl) return 0 ;;
    *) return 1 ;;
  esac
}

is_macos_platform() {
  [ "$(detect_platform)" = "macos" ]
}

require_core_supported_platform() {
  platform=$(detect_platform)
  case "$platform" in
    macos|linux|wsl) return 0 ;;
    *) die "unsupported platform: $platform; workbranch supports macOS, Linux, and WSL" ;;
  esac
}

require_macos_tool_platform() {
  label=$1
  is_macos_platform || die "workbranch $label is only supported on macOS; core workbranch commands support macOS, Linux, and WSL"
}

info_skip_tool_prompts_for_platform() {
  info "Tool app launchers are macOS-only; skipping IDE/Terminal prompts."
}
