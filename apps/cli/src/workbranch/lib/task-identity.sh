conventional_task_type_is_known() {
  case "$1" in
    feat|fix|chore|docs|refactor|test|perf|ci|build|revert) return 0 ;;
    *) return 1 ;;
  esac
}

task_identity_has_delimiter() {
  local type
  case "$1" in
    *-*)
      type=${1%%-*}
      conventional_task_type_is_known "$type"
      ;;
    *) return 1 ;;
  esac
}

task_identity_type_from_folder() {
  printf '%s' "${1%%-*}"
}

task_identity_detail_from_folder() {
  printf '%s' "${1#*-}"
}

normalize_task_argument() {
  local value
  value=$1
  while [ -n "$value" ]; do
    case "$value" in
      */) value=${value%/} ;;
      *) break ;;
    esac
  done
  printf '%s' "$value"
}

validate_task_type() {
  local value
  value=$1
  validate_safe_name "task type" "$value"
  conventional_task_type_is_known "$value" || die "invalid task type '$value' (expected feat, fix, chore, docs, refactor, test, perf, ci, build, or revert)"
}

validate_task_detail_name() {
  local value type branch_ref
  value=$1
  type=${2:-feat}
  validate_safe_name "task detail name" "$value"
  branch_ref="$type/$value"
  git check-ref-format --branch "$branch_ref" >/dev/null 2>&1 || die "invalid task detail name '$value': produces invalid branch '$branch_ref'"
}

validate_task_folder_name() {
  local value type detail
  value=$(normalize_task_argument "$1")
  [ -n "$value" ] || die "invalid task '$1' (expected task key)"
  case "$value" in
    */*) die "invalid task '$value'" ;;
  esac
  if task_identity_has_delimiter "$value"; then
    type=$(task_identity_type_from_folder "$value")
    detail=$(task_identity_detail_from_folder "$value")
    validate_task_type "$type"
    validate_task_detail_name "$detail" "$type"
    return 0
  fi
  validate_safe_name "task" "$value"
}

task_folder_from_identity() {
  local type detail
  type=$1
  detail=$2
  validate_task_type "$type"
  validate_task_detail_name "$detail" "$type"
  printf '%s-%s' "$type" "$detail"
}

task_branch_from_identity() {
  local type detail
  type=$1
  detail=$2
  validate_task_type "$type"
  validate_task_detail_name "$detail" "$type"
  printf '%s/%s' "$type" "$detail"
}

task_branch_from_folder_identity() {
  local task type detail
  task=$(normalize_task_argument "$1")
  task_identity_has_delimiter "$task" || return 1
  type=$(task_identity_type_from_folder "$task")
  detail=$(task_identity_detail_from_folder "$task")
  conventional_task_type_is_known "$type" || return 1
  task_branch_from_identity "$type" "$detail"
}
