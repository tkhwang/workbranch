//! What a tool call's hook input says about the work: which files it touched
//! and whether it changed them. Only file names leave this module, never
//! paths, file contents or command text, so the call log holds no second
//! history of what the agent read or wrote.
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::path::Path;

/// File names kept per call; a patch touching more is cut here.
pub const MAX_FILES: usize = 8;

/// Tools that change the files they name: Claude Code's editors and Codex's
/// patch tool.
pub fn is_edit(tool: &str) -> bool {
    matches!(
        tool,
        "Edit" | "MultiEdit" | "Write" | "NotebookEdit" | "apply_patch"
    )
}

/// The names of the files the call touches, in the order it names them,
/// each once, at most `MAX_FILES`. Directories a search runs in are not
/// files it touched, so search tools give none.
pub fn files(tool: &str, input: &Value) -> Vec<String> {
    let paths: Vec<&str> = if tool == "apply_patch" {
        input
            .get("command")
            .and_then(Value::as_str)
            .map(patch_paths)
            .unwrap_or_default()
    } else {
        ["file_path", "notebook_path"]
            .iter()
            .filter_map(|key| input.get(key).and_then(Value::as_str))
            .collect()
    };
    let mut names: Vec<String> = Vec::new();
    for name in paths.into_iter().filter_map(basename) {
        if !names.contains(&name) {
            names.push(name);
        }
        if names.len() == MAX_FILES {
            break;
        }
    }
    names
}

// Codex patches name each file on a header line.
fn patch_paths(patch: &str) -> Vec<&str> {
    patch
        .lines()
        .filter_map(|line| {
            [
                "*** Add File: ",
                "*** Update File: ",
                "*** Delete File: ",
                "*** Move to: ",
            ]
            .iter()
            .find_map(|header| line.strip_prefix(header))
        })
        .map(str::trim)
        .collect()
}

fn basename(path: &str) -> Option<String> {
    Path::new(path.trim())
        .file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .map(str::to_owned)
}

/// A todo as the collector keeps it: the agent's own id (or its place in a
/// full list), its text, and `done`, `active` or `todo`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TodoItem {
    pub id: String,
    pub text: String,
    pub status: String,
}

/// How a successful call changed the session's todo list.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TodoChange {
    /// A full list: Claude Code `TodoWrite`, Codex `update_plan`.
    Replace(Vec<TodoItem>),
    /// One new todo: Claude Code `TaskCreate`. An empty id means the
    /// provider's reply named none, so the list numbers it.
    Create(TodoItem),
    /// One todo's new status or text: Claude Code `TaskUpdate`. A `None`
    /// status leaves it; `Some("deleted")` removes it.
    Update {
        id: String,
        status: Option<String>,
        text: Option<String>,
    },
}

/// Todos kept per session.
pub const MAX_TODOS: usize = 50;

fn todo_status(status: &str) -> Option<&'static str> {
    match status {
        "completed" => Some("done"),
        "in_progress" => Some("active"),
        "pending" => Some("todo"),
        "deleted" => Some("deleted"),
        _ => None,
    }
}

fn id_of(value: &Value) -> Option<String> {
    match value {
        Value::String(id) if !id.is_empty() => Some(id.clone()),
        Value::Number(id) => Some(id.to_string()),
        _ => None,
    }
}

// A full list whose every entry has text and a known status; anything else
// is not understood, and the previous list stands.
fn full_list(entries: &Value, text_key: &str) -> Option<Vec<TodoItem>> {
    let entries = entries.as_array()?;
    entries
        .iter()
        .take(MAX_TODOS)
        .enumerate()
        .map(|(index, entry)| {
            let status = todo_status(entry.get("status")?.as_str()?)?;
            if status == "deleted" {
                return None;
            }
            Some(TodoItem {
                id: (index + 1).to_string(),
                text: entry.get(text_key)?.as_str()?.to_owned(),
                status: status.into(),
            })
        })
        .collect()
}

/// What a successful call did to the todo list, when the call is a todo tool
/// whose input (and, for a new task, reply) the collector understands.
pub fn todo_change(tool: &str, input: &Value, response: &Value) -> Option<TodoChange> {
    match tool {
        "TodoWrite" => full_list(input.get("todos")?, "content").map(TodoChange::Replace),
        "update_plan" => full_list(input.get("plan")?, "step").map(TodoChange::Replace),
        "TaskCreate" => {
            let text = input.get("subject")?.as_str()?.to_owned();
            let id = [
                response.get("task").and_then(|task| task.get("id")),
                response.get("taskId"),
                response.get("id"),
            ]
            .into_iter()
            .flatten()
            .find_map(id_of)
            .unwrap_or_default();
            Some(TodoChange::Create(TodoItem {
                id,
                text,
                status: "todo".into(),
            }))
        }
        "TaskUpdate" => {
            let id = id_of(input.get("taskId")?)?;
            let status = match input.get("status").and_then(Value::as_str) {
                Some(status) => Some(todo_status(status)?.to_owned()),
                None => None,
            };
            let text = input
                .get("subject")
                .and_then(Value::as_str)
                .map(str::to_owned);
            Some(TodoChange::Update { id, status, text })
        }
        _ => None,
    }
}

/// Applies `change` to `items`, keeping at most `MAX_TODOS`. An update of a
/// todo the list does not hold changes nothing.
pub fn apply_todo(items: &mut Vec<TodoItem>, change: TodoChange) {
    match change {
        TodoChange::Replace(list) => *items = list,
        TodoChange::Create(mut item) => {
            if item.id.is_empty() {
                let next = items
                    .iter()
                    .filter_map(|todo| todo.id.parse::<u64>().ok())
                    .max()
                    .unwrap_or(0)
                    + 1;
                item.id = next.to_string();
            }
            items.retain(|todo| todo.id != item.id);
            items.push(item);
            if items.len() > MAX_TODOS {
                items.drain(..items.len() - MAX_TODOS);
            }
        }
        TodoChange::Update { id, status, text } => {
            if status.as_deref() == Some("deleted") {
                items.retain(|todo| todo.id != id);
                return;
            }
            if let Some(todo) = items.iter_mut().find(|todo| todo.id == id) {
                if let Some(status) = status {
                    todo.status = status;
                }
                if let Some(text) = text {
                    todo.text = text;
                }
            }
        }
    }
}

/// Lines an edit adds and removes, from its input alone (COMP004 R4): a Codex
/// patch counts its `+` and `-` lines exactly; a Claude Code edit compares
/// the old and new text line by line in order, so a moved line counts once
/// each way;
/// a write counts the new file's lines as added.
pub fn line_changes(tool: &str, input: &Value) -> (u32, u32) {
    let text = |key: &str| input.get(key).and_then(Value::as_str).unwrap_or("");
    match tool {
        "apply_patch" => patch_lines(text("command")),
        "Edit" => edit_lines(text("old_string"), text("new_string")),
        "MultiEdit" => input
            .get("edits")
            .and_then(Value::as_array)
            .map(|edits| {
                edits.iter().fold((0, 0), |(added, removed), edit| {
                    let old = edit.get("old_string").and_then(Value::as_str).unwrap_or("");
                    let new = edit.get("new_string").and_then(Value::as_str).unwrap_or("");
                    let (a, r) = edit_lines(old, new);
                    (added + a, removed + r)
                })
            })
            .unwrap_or((0, 0)),
        "Write" => (count(text("content").lines().count()), 0),
        "NotebookEdit" => (count(text("new_source").lines().count()), 0),
        _ => (0, 0),
    }
}

fn count(n: usize) -> u32 {
    u32::try_from(n).unwrap_or(u32::MAX)
}

fn patch_lines(patch: &str) -> (u32, u32) {
    let (mut added, mut removed) = (0, 0);
    for line in patch.lines().filter(|line| !line.starts_with("***")) {
        if line.starts_with('+') {
            added += 1;
        } else if line.starts_with('-') {
            removed += 1;
        }
    }
    (added, removed)
}

/// Line pairs an edit compares in order before it falls back to an unordered
/// match, which keeps a huge edit from costing the hook its time budget.
const ORDERED_DIFF_LIMIT: usize = 250_000;

// Lines kept in order are the longest common subsequence of the two texts;
// everything else was added or removed, so a moved line counts once each way.
fn edit_lines(old: &str, new: &str) -> (u32, u32) {
    let old: Vec<&str> = old.lines().collect();
    let new: Vec<&str> = new.lines().collect();
    let kept = if old.len().saturating_mul(new.len()) <= ORDERED_DIFF_LIMIT {
        common_lines(&old, &new)
    } else {
        unordered_common_lines(&old, &new)
    };
    (count(new.len() - kept), count(old.len() - kept))
}

fn common_lines(old: &[&str], new: &[&str]) -> usize {
    let mut row = vec![0usize; new.len() + 1];
    for old_line in old {
        let mut diagonal = 0;
        for (j, new_line) in new.iter().enumerate() {
            let above = row[j + 1];
            row[j + 1] = if old_line == new_line {
                diagonal + 1
            } else {
                above.max(row[j])
            };
            diagonal = above;
        }
    }
    row[new.len()]
}

fn unordered_common_lines(old: &[&str], new: &[&str]) -> usize {
    let mut unmatched = old.to_vec();
    new.iter()
        .filter(|line| {
            unmatched
                .iter()
                .position(|old_line| old_line == *line)
                .map(|index| unmatched.swap_remove(index))
                .is_some()
        })
        .count()
}

/// The providers' shell tools: Claude Code's and Codex's canonical `Bash`,
/// Codex's older names, and Grok's terminal tool.
const SHELL_TOOLS: [&str; 5] = [
    "Bash",
    "shell",
    "exec_command",
    "local_shell",
    "run_terminal_command",
];

/// What a shell command is, for the turn summary (COMP004 R4): `test` once
/// when any of its parts runs a test suite, and `commit` once for every part
/// that makes a git commit. The command itself is never kept.
pub fn command_kinds(tool: &str, input: &Value) -> Vec<&'static str> {
    if !SHELL_TOOLS.contains(&tool) {
        return Vec::new();
    }
    let command = match input.get("command") {
        Some(Value::String(command)) => command.clone(),
        Some(Value::Array(parts)) => parts
            .iter()
            .filter_map(Value::as_str)
            .collect::<Vec<_>>()
            .join(" "),
        _ => return Vec::new(),
    };
    let parts: Vec<Vec<&str>> = command
        .split(['&', '|', ';', '\n'])
        .map(|part| {
            part.split_whitespace()
                .skip_while(|word| word.contains('=') && !word.starts_with('-'))
                .collect()
        })
        .collect();
    let mut kinds = Vec::new();
    if parts.iter().any(|words| is_test(words)) {
        kinds.push("test");
    }
    kinds.extend(
        parts
            .iter()
            .filter(|words| is_commit(words))
            .map(|_| "commit"),
    );
    kinds
}

fn is_test(words: &[&str]) -> bool {
    let has = |word: &str| words.contains(&word);
    let Some(first) = words.first() else {
        return false;
    };
    let runner = first.rsplit('/').next().unwrap_or(first);
    match runner {
        "cargo" => has("test") || has("nextest"),
        "pnpm" | "npm" | "yarn" | "bun" | "npx" | "pnpx" | "bunx" => {
            has("test") || has("vitest") || has("jest")
        }
        "vitest" | "jest" | "pytest" => true,
        "python" | "python3" => has("pytest") || has("unittest"),
        "go" | "mvn" | "gradle" | "gradlew" | "make" | "swift" | "dotnet" => has("test"),
        _ => runner == "run.sh" && first.contains("tests/"),
    }
}

fn is_commit(words: &[&str]) -> bool {
    words.first() == Some(&"git") && words.contains(&"commit") && !words.contains(&"--dry-run")
}
