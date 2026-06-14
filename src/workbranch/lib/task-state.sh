task_state_dir_path() { printf '%s/%s/.workbranch' "$PROJECT_ROOT" "$1"; }

task_brief_path() { printf '%s/%s/TASK-WORKBRANCH.md' "$PROJECT_ROOT" "$1"; }

task_agents_path() { printf '%s/%s/AGENTS.md' "$PROJECT_ROOT" "$1"; }

task_noti_path() { printf '%s/notifications.jsonl' "$(task_state_dir_path "$1")"; }

task_brief_title() {
  local file line
  file=$(task_brief_path "$1")
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    printf '%s' "$line" | sed 's/^#\{1,\}[[:space:]]*//'
    return 0
  done < "$file"
}

task_brief_file() {
  file=$(task_brief_path "$1")
  [ -f "$file" ] && printf '%s' "$file"
}

task_updated_at() {
  local file
  file=$(task_brief_file "$1") || true
  [ -n "${file:-}" ] || { printf '0'; return 0; }
  if stat -f %m "$file" >/dev/null 2>&1; then
    stat -f %m "$file"
  elif stat -c %Y "$file" >/dev/null 2>&1; then
    stat -c %Y "$file"
  else
    printf '0'
  fi
}

task_checklist_counts() {
  local file
  file=$(task_brief_file "$1") || true
  [ -n "${file:-}" ] || { printf '0 0'; return 0; }
  awk '
    /^[[:space:]]*```/ { in_code = !in_code; next }
    in_code { next }
    /^[[:space:]]*-[[:space:]]*\[[xX]\][[:space:]]*/ { done++; total++; next }
    /^[[:space:]]*-[[:space:]]*\[[[:space:]]\][[:space:]]*/ { total++; next }
    END { printf "%d %d", done + 0, total + 0 }
  ' "$file"
}

task_explicit_status() {
  local file
  file=$(task_brief_file "$1") || true
  [ -n "${file:-}" ] || return 1
  awk '
    function lower(value) { return tolower(value) }
    /^[[:space:]]*```/ { in_code = !in_code; next }
    in_code { next }
    /^[[:space:]]*-[[:space:]]*\[[ xX]\][[:space:]]*/ { exit }
    /^[[:space:]]*status:[[:space:]]*/ {
      value = $0
      sub(/^[[:space:]]*status:[[:space:]]*/, "", value)
      sub(/[[:space:]]+.*/, "", value)
      value = lower(value)
      if (value == "todo" || value == "planning" || value == "in-progress" || value == "review" || value == "blocked" || value == "done") print value
      else print ""
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  ' "$file"
}

task_plan_title() {
  local file
  file=$(task_brief_file "$1") || true
  [ -n "${file:-}" ] || return 0
  awk '
    /^[[:space:]]*```/ { in_code = !in_code; next }
    in_code { next }
    /^[[:space:]]*-[[:space:]]*\[[ xX]\][[:space:]]*/ { exit }
    /^[[:space:]]*plan:[[:space:]]*/ {
      value = $0
      sub(/^[[:space:]]*plan:[[:space:]]*/, "", value)
      sub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$file"
}

task_status() {
  local task explicit status_counts done_count total_count
  task=$1
  if explicit=$(task_explicit_status "$task"); then
    printf '%s' "$explicit"
    return 0
  fi
  status_counts=$(task_checklist_counts "$task")
  done_count=${status_counts%% *}
  total_count=${status_counts##* }
  if [ "$done_count" -eq 0 ]; then
    printf 'todo'
  elif [ "$done_count" -eq "$total_count" ]; then
    printf 'done'
  else
    printf 'in-progress'
  fi
}

task_current_item() {
  local file
  file=$(task_brief_file "$1") || true
  [ -n "${file:-}" ] || return 0
  awk '
    /^[[:space:]]*```/ { in_code = !in_code; next }
    in_code { next }
    /^[[:space:]]*-[[:space:]]*\[[[:space:]]\][[:space:]]*/ {
      value = $0
      sub(/^[[:space:]]*-[[:space:]]*\[[[:space:]]\][[:space:]]*/, "", value)
      print value
      exit
    }
  ' "$file"
}


task_checklist_items_json() {
  local file line in_code first leading mark text depth
  file=$(task_brief_file "$1") || true
  printf '['
  [ -n "${file:-}" ] || { printf ']'; return 0; }
  in_code=0
  first=1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      [[:space:]]*\`\`\`*)
        if [ "$in_code" -eq 0 ]; then in_code=1; else in_code=0; fi
        continue
        ;;
    esac
    [ "$in_code" -eq 0 ] || continue
    if [[ $line =~ ^([[:space:]]*)-[[:space:]]*\[([xX[:space:]])\][[:space:]]*(.*)$ ]]; then
      leading=${BASH_REMATCH[1]}
      mark=${BASH_REMATCH[2]}
      text=${BASH_REMATCH[3]}
      depth=$((${#leading} / 2))
      if [ "$first" -eq 1 ]; then first=0; else printf ','; fi
      printf '{"text":'
      json_string "$text"
      if [ "$mark" = "x" ] || [ "$mark" = "X" ]; then
        printf ',"checked":true'
      else
        printf ',"checked":false'
      fi
      printf ',"depth":%d}' "$depth"
    fi
  done < "$file"
  printf ']'
}

write_default_task_brief() {
  local task file
  task=$1
  file=$(task_brief_path "$task")
  [ -e "$file" ] && return 0
  if [ "${PREFERRED_LANGUAGE:-en}" = "ko" ]; then
    cat > "$file" <<EOF_BRIEF
# $task

상태: todo
status: todo
plan: $task

- [ ] 주요: 작업 시작
  - [ ] 변경 구현
  - [ ] 검증 실행

## 메모
-
EOF_BRIEF
  else
    cat > "$file" <<EOF_BRIEF
# $task

status: todo
plan: $task

- [ ] Major: Start work
  - [ ] Implement change
  - [ ] Run verification

## Notes
-
EOF_BRIEF
  fi
}

write_task_agent_guidance() {
  local task file
  task=$1
  file=$(task_agents_path "$task")
  [ -e "$file" ] && return 0
  if [ "${PREFERRED_LANGUAGE:-en}" = "ko" ]; then
    cat > "$file" <<'EOF_GUIDANCE'
# Workbranch 작업 안내

이 파일은 workbranch가 이 task workspace에 생성한 안내입니다.

- AI agent session은 기본적으로 task root(`<task>`)에서 실행합니다.
- task root는 Git repository가 아닙니다. workbranch metadata/agent 작업 공간입니다.
- 실제 Git repo는 `<task>/<repo>` 아래에 있습니다.
- 코드 변경과 Git 명령은 repo folder 안에서 수행하고, 진행 상황은 task root의 `TASK-WORKBRANCH.md`에 기록합니다.
- 현재 작업 디렉터리가 task root이면 `TASK-WORKBRANCH.md`를 갱신합니다.
- 현재 작업 디렉터리가 이 task 아래의 repo folder이면 `../TASK-WORKBRANCH.md`를 갱신합니다.
- 현재 작업, blocker, 다음 action을 사람이 읽을 수 있게 task brief에 남깁니다.
- `plan:`은 Step들을 묶는 구체적인 Plan 이름으로 유지합니다.
- 사용자가 명시적으로 요청하지 않는 한 repo-local task-state file을 만들지 않습니다.

## 작업 진행 업데이트 규칙

다음 시점에 `TASK-WORKBRANCH.md`를 갱신합니다:
- 의미 있는 작업을 시작하거나 재개할 때
- active implementation step이 바뀔 때
- 검증을 실행하기 전
- 검증이 통과하거나 실패한 후
- blocked 상태가 되었을 때
- final response 직전

규칙:
- `status:`는 todo | planning | in-progress | review | blocked | done 중 하나로 유지합니다.
- `plan:`은 Step들을 묶는 구체적인 Plan 이름으로 유지합니다.
- 계획(planning)을 포함해 의미 있는 작업을 시작하면 즉시 `todo`에서 `planning`으로 status를 갱신합니다. 초기 planning 단계에서도 status와 Step을 갱신합니다.
- Step은 작고 실행 가능한 단위로 유지합니다.
- 완료한 Step은 즉시 `[x]`로 표시합니다.
- 첫 번째 미완료 Step이 현재 또는 다음 작업을 나타내야 합니다.
- 하위 Step은 Markdown checklist 항목을 두 칸 들여써 표현합니다.
EOF_GUIDANCE
  else
    cat > "$file" <<'EOF_GUIDANCE'
# Workbranch Task Guidance

This file is generated by workbranch for this task workspace.

- Run AI agent sessions from the task root (`<task>`) by default.
- The task root is not a Git repository; it is a workbranch metadata/agent workspace.
- The actual Git repositories live under `<task>/<repo>`.
- Make code changes and run Git commands inside the repo folders; keep progress in `TASK-WORKBRANCH.md` at the task root.
- Keep the task brief current as work progresses.
- If your current working directory is the task root, update `TASK-WORKBRANCH.md`.
- If your current working directory is a repo folder under this task, update `../TASK-WORKBRANCH.md`.
- Use the task brief for human-readable current work, blockers, and next actions.
- Keep `plan:` set to the concrete Plan name that groups the Steps.
- Do not create repo-local task-state files unless the user explicitly asks.

## Task progress update protocol

Update `TASK-WORKBRANCH.md` when:
- starting or resuming meaningful work
- changing the active implementation step
- before running verification
- after verification passes or fails
- when blocked
- before final response

Rules:
- keep `status:` current: todo | planning | in-progress | review | blocked | done
- keep `plan:` current as the concrete Plan name for the Steps
- when starting meaningful work, including planning, move status from todo to planning immediately; keep status and Steps current during the initial planning phase
- keep Steps small and actionable
- mark completed Steps immediately with `[x]`
- the first unchecked Step should represent the current or next work
- express substeps by indenting Markdown checklist items with two spaces per level
EOF_GUIDANCE
  fi
}

write_default_task_state() {
  local task noti state_dir
  task=$1
  write_default_task_brief "$task" || die "failed to write task brief: $task"
  write_task_agent_guidance "$task" || die "failed to write task agent guidance: $task"
  state_dir=$(task_state_dir_path "$task")
  noti=$(task_noti_path "$task")
  mkdir -p "$state_dir" && : > "$noti" || die "failed to initialize notification inbox: $task"
}

remove_task_state_files() {
  local task brief agents noti state_dir task_dir
  task=$1
  task_dir="$PROJECT_ROOT/$task"
  brief=$(task_brief_path "$task")
  agents=$(task_agents_path "$task")
  noti=$(task_noti_path "$task")
  state_dir=$(task_state_dir_path "$task")
  [ ! -f "$brief" ] || rm -f "$brief" || die "failed to remove task brief: $brief"
  [ ! -f "$agents" ] || rm -f "$agents" || die "failed to remove task agent guidance: $agents"
  [ ! -f "$noti" ] || rm -f "$noti" || die "failed to remove task notifications: $noti"
  rmdir "$state_dir" 2>/dev/null || true
}

resolve_current_task_from_cwd() {
  local dir parent task
  dir=$(pwd -P)
  while [ "$dir" != "$PROJECT_ROOT" ] && [ "$dir" != "/" ]; do
    parent=$(dirname "$dir")
    if [ "$parent" = "$PROJECT_ROOT" ]; then
      task=${dir##*/}
      is_task_workspace_path "$PROJECT_ROOT/$task" || return 1
      printf '%s' "$task"
      return 0
    fi
    dir=$parent
  done
  return 1
}

require_known_task_workspace() {
  local operation task task_dir
  operation=$1
  task=$2
  validate_task_folder_name "$task"
  task_dir="$PROJECT_ROOT/$task"
  if ! is_task_workspace_path "$task_dir"; then
    die "Cannot $operation: unknown task '$task'"
  fi
}

json_string() {
  printf '"'
  printf '%s' "$1" | json_escape
  printf '"'
}

json_escape() {
  awk 'BEGIN {
      ORS = ""
      for (i = 0; i < 32; i++) {
        c = sprintf("%c", i)
        control_escape[c] = sprintf("\\u%04x", i)
      }
      control_escape[sprintf("%c", 8)] = "\\b"
      control_escape[sprintf("%c", 9)] = "\\t"
      control_escape[sprintf("%c", 10)] = "\\n"
      control_escape[sprintf("%c", 12)] = "\\f"
      control_escape[sprintf("%c", 13)] = "\\r"
    }
    {
      if (NR > 1) printf "\\n"
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == "\\") printf "\\\\"
        else if (c == "\"") printf "\\\""
        else if (c in control_escape) printf "%s", control_escape[c]
        else printf "%s", c
      }
    }'
}

json_unescape() {
  awk '
  function hex_value(c) {
    if (c >= "0" && c <= "9") return c + 0
    c = tolower(c)
    if (c >= "a" && c <= "f") return index("abcdef", c) + 9
    return -1
  }
  function hex_byte(value, hi, lo) {
    hi = hex_value(substr(value, 1, 1))
    lo = hex_value(substr(value, 2, 1))
    if (hi < 0 || lo < 0) return -1
    return hi * 16 + lo
  }
  {
    out = ""
    for (i = 1; i <= length($0); i++) {
      c = substr($0, i, 1)
      if (c == "\\") {
        i++
        e = substr($0, i, 1)
        if (e == "n") out = out "\n"
        else if (e == "t") out = out "\t"
        else if (e == "r") out = out "\r"
        else if (e == "b") out = out sprintf("%c", 8)
        else if (e == "f") out = out sprintf("%c", 12)
        else if (e == "u" && substr($0, i + 1, 2) == "00") {
          code = hex_byte(substr($0, i + 3, 2))
          if (code >= 0 && code < 32) {
            out = out sprintf("%c", code)
            i += 4
          } else {
            out = out e
          }
        }
        else out = out e
      } else {
        out = out c
      }
    }
    print out
  }'
}

noti_count() {
  local file count
  file=$(task_noti_path "$1")
  [ -f "$file" ] || { printf '0'; return 0; }
  count=$(wc -l < "$file" | tr -d '[:space:]')
  printf '%s' "${count:-0}"
}
