cmd_version() {
  [ $# -eq 0 ] || die "usage: workbranch version"
  printf 'workbranch %s\n' "$WORKBRANCH_VERSION"
}
