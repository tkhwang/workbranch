main() {
  cmd=${1:-help}
  if [ $# -gt 0 ]; then shift; fi
  case "$cmd" in
    config) cmd_config "$@" ;;
    init) cmd_init "$@" ;;
    add) cmd_add "$@" ;;
    list) cmd_list "$@" ;;
    status) cmd_status "$@" ;;
    pull) cmd_pull "$@" ;;
    update) cmd_update "$@" ;;
    push) cmd_push "$@" ;;
    land) cmd_land "$@" ;;
    remove) cmd_remove "$@" ;;
    version|-v|--version) cmd_version "$@" ;;
    help|-h|--help) usage ;;
    *) usage >&2; die "unknown command: $cmd" ;;
  esac
}

main "$@"
