main() {
  cmd=${1:-help}
  if [ $# -gt 0 ]; then shift; fi
  case "$cmd" in
    help|-h|--help|version|-v|--version|config|ide|finder|terminal|completion|__complete-tasks|__complete-repos|__complete-commands) ;;
    *) require_core_supported_platform ;;
  esac
  case "$cmd" in
    config) cmd_config "$@" ;;
    init) cmd_init "$@" ;;
    add) cmd_add "$@" ;;
    memo) cmd_memo "$@" ;;
    noti) cmd_noti "$@" ;;
    list) cmd_list "$@" ;;
    path) cmd_path "$@" ;;
    ide) cmd_ide "$@" ;;
    finder) cmd_finder "$@" ;;
    terminal) cmd_terminal "$@" ;;
    status) cmd_status "$@" ;;
    doctor) cmd_doctor "$@" ;;
    pull) cmd_pull "$@" ;;
    update) cmd_update "$@" ;;
    refresh) cmd_refresh "$@" ;;
    finalize) cmd_finalize "$@" ;;
    push) cmd_push "$@" ;;
    land) cmd_land "$@" ;;
    remove) cmd_remove "$@" ;;
    destroy) cmd_destroy "$@" ;;
    prune) cmd_prune "$@" ;;
    completion) cmd_completion "$@" ;;
    __complete-tasks) cmd_complete_tasks ;;
    __complete-repos) cmd_complete_repos ;;
    __complete-commands) cmd_complete_commands ;;
    version|-v|--version) cmd_version "$@" ;;
    help|-h|--help) usage ;;
    *) usage_plain >&2; die "unknown command: $cmd" ;;
  esac
}

main "$@"
