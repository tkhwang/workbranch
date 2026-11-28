# Hook payload fixtures

One hook event per file, as the provider sends it on stdin. Fields follow the
providers' hook references; `session_id`, `cwd` and paths are made up.

| file | provider | event | source |
|---|---|---|---|
| `claude-read.json` | Claude Code | `PreToolUse` · `Read` | built from https://code.claude.com/docs/en/hooks (common fields, `tool_name`, `tool_input`, `tool_use_id`) |
| `claude-edit.json` | Claude Code | `PreToolUse` · `Edit` | same; `Edit` input fields from https://code.claude.com/docs/en/tools-reference |
| `claude-write.json` | Claude Code | `PreToolUse` · `Write` | same |
| `claude-notebook-edit.json` | Claude Code | `PreToolUse` · `NotebookEdit` | same |
| `claude-bash.json` | Claude Code | `PreToolUse` · `Bash` | same |
| `claude-bash-failure.json` | Claude Code | `PostToolUseFailure` · `Bash` | same (`error`, `is_interrupt`, `duration_ms`) |
| `codex-apply-patch.json` | Codex | `PreToolUse` · `apply_patch` | built from https://learn.chatgpt.com/docs/hooks (`tool_input.command` holds the patch) |
| `claude-todo-write.json` | Claude Code | `PostToolUse` · `TodoWrite` | **constructed, not captured**: TodoWrite appears only with `CLAUDE_CODE_ENABLE_TASKS=0` on models that have task tools. `todos[{content, status, activeForm}]` |
| `claude-task-create.json` | Claude Code | `PostToolUse` · `TaskCreate` | **captured shape**: Claude Code 2.1.332 with `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` (2026-11-28); input `{subject, description}`, reply `{task: {id, subject, description}}`; texts replaced |
| `claude-task-update.json` | Claude Code | `PostToolUse` · `TaskUpdate` | **captured shape**: same session; input `{taskId, status}`, reply `{success, taskId, updatedFields, statusChange}` |
| `codex-update-plan.json` | Codex | `PostToolUse` · `update_plan` | `tool_input.plan[{step, status}]` as Codex session logs record the tool's arguments; whether Codex sends hooks for it is unconfirmed |
