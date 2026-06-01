repo_count() { printf '%s' "${#REPO_NAMES[@]}"; }

repo_name_at() { printf '%s' "${REPO_NAMES[$1]}"; }

repo_url_at() { printf '%s' "${REPO_URLS[$1]}"; }

repo_base_branch_at() { printf '%s' "${REPO_BASE_BRANCHES[$1]}"; }

repo_index_by_name() {
  needle=$1
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    if [ "$(repo_name_at "$i")" = "$needle" ]; then
      printf '%s' "$i"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

parse_repo_option() {
  FILTER_REPO=""
  ARGS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo)
        [ $# -ge 2 ] || die "missing value for --repo"
        FILTER_REPO=$2
        validate_safe_name "repo" "$FILTER_REPO"
        shift 2
        ;;
      --repo=*)
        FILTER_REPO=${1#--repo=}
        validate_safe_name "repo" "$FILTER_REPO"
        shift
        ;;
      *)
        ARGS[${#ARGS[@]}]=$1
        shift
        ;;
    esac
  done

  if [ -n "$FILTER_REPO" ]; then
    repo_index_by_name "$FILTER_REPO" >/dev/null || die "unknown repo: $FILTER_REPO"
  fi
}

repo_matches_filter() {
  [ -z "$FILTER_REPO" ] || [ "$1" = "$FILTER_REPO" ]
}

add_repo_config() {
  name=$1
  url=$2
  base_branch=${3:-}
  validate_safe_name "repo name" "$name"
  validate_nonempty_no_space "git-url" "$url"
  if [ -n "$base_branch" ]; then
    validate_nonempty_no_space "base-branch" "$base_branch"
  fi
  if repo_index_by_name "$name" >/dev/null; then
    die "duplicate repo '$name' in config"
  fi
  REPO_NAMES[${#REPO_NAMES[@]}]=$name
  REPO_URLS[${#REPO_URLS[@]}]=$url
  REPO_BASE_BRANCHES[${#REPO_BASE_BRANCHES[@]}]=$base_branch
}

set_repo_base_branch() {
  name=$1
  base_branch=$2
  validate_nonempty_no_space "base-branch" "$base_branch"
  idx=$(repo_index_by_name "$name") || die "base branch references unknown repo '$name'"
  current=$(repo_base_branch_at "$idx")
  if [ -n "$current" ]; then
    [ "$current" = "$base_branch" ] || die "conflicting base branch for repo '$name': $current vs $base_branch"
    return 0
  fi
  REPO_BASE_BRANCHES[$idx]=$base_branch
}

reset_config() {
  PROJECT_NAME=""
  BASE_DIR=""
  BRANCH_PREFIX=""
  TASK_SETUP=""
  REPO_NAMES=()
  REPO_URLS=()
  REPO_BASE_BRANCHES=()
}

task_setup_from_line() {
  line=$1
  command=$(printf '%s' "$line" | sed 's/^[^[:space:]]*[[:space:]]*//; s/[[:space:]]*$//')
  printf '%s' "$command"
}

config_line_split_tokens() {
  # shell word splitting is intentional: config values cannot contain whitespace.
  # Pathname expansion is not part of the config format, so keep glob characters literal.
  line=$1
  case $- in
    *f*) glob_was_disabled=1 ;;
    *) glob_was_disabled=0 ;;
  esac
  set -f
  CONFIG_FIELDS=($line)
  [ "$glob_was_disabled" -eq 1 ] || set +f
}

validate_config_complete() {
  [ -n "$PROJECT_NAME" ] || die "missing PROJECT_NAME directive in config"
  [ -n "$BASE_DIR" ] || die "missing MAIN_WORKTREES_DIR directive in config"
  [ -n "$BRANCH_PREFIX" ] || die "missing BRANCH_PREFIX directive in config"
  [ ${#REPO_NAMES[@]} -gt 0 ] || die "config must define at least one repo"
  i=0
  while [ $i -lt ${#REPO_NAMES[@]} ]; do
    name=$(repo_name_at "$i")
    [ -n "$(repo_base_branch_at "$i")" ] || die "missing base branch for repo '$name'"
    i=$((i + 1))
  done
}

parse_config() {
  file=$1
  [ -f "$file" ] || die "config not found: $file"
  reset_config
  line_no=0
  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    line_no=$((line_no + 1))
    # trim leading/trailing whitespace using awk-compatible shell expansion avoidance
    line=$(printf '%s' "$raw_line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac

    config_line_split_tokens "$line"
    set -- "${CONFIG_FIELDS[@]}"
    directive=$1
    case "$directive" in
      PROJECT_NAME)
        [ $# -eq 2 ] || die "invalid config line $line_no: PROJECT_NAME expects 1 value"
        [ -z "$PROJECT_NAME" ] || die "duplicate PROJECT_NAME directive in config"
        validate_safe_name "PROJECT_NAME" "$2"
        PROJECT_NAME=$2
        ;;
      MAIN_WORKTREES_DIR)
        [ $# -eq 2 ] || die "invalid config line $line_no: MAIN_WORKTREES_DIR expects 1 value"
        [ -z "$BASE_DIR" ] || die "duplicate MAIN_WORKTREES_DIR directive in config"
        validate_safe_name "MAIN_WORKTREES_DIR" "$2"
        BASE_DIR=$2
        ;;
      BRANCH_PREFIX)
        [ $# -eq 2 ] || die "invalid config line $line_no: BRANCH_PREFIX expects 1 value"
        [ -z "$BRANCH_PREFIX" ] || die "duplicate BRANCH_PREFIX directive in config"
        validate_nonempty_no_space "BRANCH_PREFIX" "$2"
        BRANCH_PREFIX=$2
        ;;
      TASK_SETUP)
        [ -z "$TASK_SETUP" ] || die "duplicate TASK_SETUP directive in config"
        TASK_SETUP=$(task_setup_from_line "$line")
        [ -n "$TASK_SETUP" ] || die "invalid config line $line_no: TASK_SETUP expects a command"
        ;;
      REPO)
        [ $# -eq 4 ] || die "invalid config line $line_no: REPO expects 3 values: <name> <git-url> <base-branch>; run 'workbranch config' to rewrite an older config format"
        add_repo_config "$2" "$3" "$4"
        ;;
      *)
        die "unknown directive '$directive' in config line $line_no"
        ;;
    esac
  done < "$file"

  validate_config_complete
}

parse_config_for_rewrite() {
  file=$1
  [ -f "$file" ] || die "config not found: $file"
  reset_config
  line_no=0
  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    line_no=$((line_no + 1))
    line=$(printf '%s' "$raw_line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac

    config_line_split_tokens "$line"
    set -- "${CONFIG_FIELDS[@]}"
    directive=$1
    case "$directive" in
      PROJECT_NAME|project)
        [ $# -eq 2 ] || die "invalid config line $line_no: PROJECT_NAME expects 1 value"
        [ -z "$PROJECT_NAME" ] || die "duplicate PROJECT_NAME directive in config"
        validate_safe_name "PROJECT_NAME" "$2"
        PROJECT_NAME=$2
        ;;
      MAIN_WORKTREES_DIR|BASE_DIR|base_dir)
        [ $# -eq 2 ] || die "invalid config line $line_no: MAIN_WORKTREES_DIR expects 1 value"
        [ -z "$BASE_DIR" ] || die "duplicate MAIN_WORKTREES_DIR directive in config"
        validate_safe_name "MAIN_WORKTREES_DIR" "$2"
        BASE_DIR=$2
        ;;
      BRANCH_PREFIX|branch_prefix)
        [ $# -eq 2 ] || die "invalid config line $line_no: BRANCH_PREFIX expects 1 value"
        [ -z "$BRANCH_PREFIX" ] || die "duplicate BRANCH_PREFIX directive in config"
        validate_nonempty_no_space "BRANCH_PREFIX" "$2"
        BRANCH_PREFIX=$2
        ;;
      TASK_SETUP|task_setup)
        [ -z "$TASK_SETUP" ] || die "duplicate TASK_SETUP directive in config"
        TASK_SETUP=$(task_setup_from_line "$line")
        [ -n "$TASK_SETUP" ] || die "invalid config line $line_no: TASK_SETUP expects a command"
        ;;
      REPO|repo)
        if [ $# -eq 4 ]; then
          add_repo_config "$2" "$3" "$4"
        elif [ $# -eq 3 ]; then
          add_repo_config "$2" "$3" ""
        else
          die "invalid config line $line_no: REPO expects <name> <git-url> [base-branch]"
        fi
        ;;
      BASE_BRANCH|base_branch|REPO_BASE_BRANCH|repo_base_branch)
        [ $# -eq 3 ] || die "invalid config line $line_no: BASE_BRANCH expects 2 values: <repo> <base-branch>"
        set_repo_base_branch "$2" "$3"
        ;;
      *)
        die "unknown directive '$directive' in config line $line_no"
        ;;
    esac
  done < "$file"

  validate_config_complete
}

write_config() {
  file=$1
  mkdir -p "$(dirname "$file")" || die "failed to create config directory"
  {
    printf '# Workbranch config
'
    printf '# You may edit this file manually.
'
    printf '# This file is read by workbranch. It is not a shell script.
'
    printf '#
'
    printf '# Be careful changing MAIN_WORKTREES_DIR, BRANCH_PREFIX, or REPO after worktrees exist.
'
    printf '\n'
    printf 'PROJECT_NAME %s\n' "$PROJECT_NAME"
    printf 'MAIN_WORKTREES_DIR %s\n' "$BASE_DIR"
    printf 'BRANCH_PREFIX %s\n' "$BRANCH_PREFIX"
    if [ -n "$TASK_SETUP" ]; then
      printf 'TASK_SETUP %s\n' "$TASK_SETUP"
    fi
    printf '\n'
    printf '# REPO <name> <git-url> <base-branch>\n'
    i=0
    while [ $i -lt ${#REPO_NAMES[@]} ]; do
      printf 'REPO %s %s %s\n' "$(repo_name_at "$i")" "$(repo_url_at "$i")" "$(repo_base_branch_at "$i")"
      i=$((i + 1))
    done
  } > "$file" || die "failed to write config: $file"
}
