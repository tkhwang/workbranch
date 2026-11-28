use crate::{Result, tool::TodoItem};
use rusqlite::{Connection, OptionalExtension, params};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, path::Path, time::Duration};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Session {
    pub workspace: String,
    #[serde(default, skip_serializing_if = "is_false")]
    pub closed: bool,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub workspace_stamp: String,
    pub provider: String,
    pub session_id: String,
    pub agent_id: String,
    pub turn_id: String,
    pub state: String,
    pub observation: String,
    pub reason: String,
    pub prompt: String,
    pub activity: String,
    pub response: String,
    pub updated_at: u64,
    pub state_changed_at: u64,
    pub outcome: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub retired_turns: Vec<String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub active_tools: BTreeMap<String, String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub waits: BTreeMap<String, String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub completed_tools: Vec<String>,
    /// The last few requests and replies, newest last, for the dashboard.
    /// Kept in the session row, so they age out with it.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub messages: Vec<Message>,
    /// When recent turns began, newest last. Kept in the session row (at most
    /// `TURN_LIMIT`); the snapshot carries the last few hours.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub turns: Vec<Turn>,
    /// Snapshot only: the last few hours of tool calls, oldest first. Never
    /// stored in `data`; the call log is the record.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub calls: Vec<Call>,
    /// The agent's todo list as its todo tools last left it. Kept in the
    /// session row; the snapshot carries only `todos`, a summary.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub todo_items: Vec<TodoItem>,
    /// Snapshot only: how far the todo list has come.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub todos: Option<TodoSummary>,
    /// What the last request turn left, summed when it ended and kept in the
    /// session row, so it outlives the call log it was read from. The
    /// snapshot carries it only while the session is still finished.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_turn: Option<TurnSummary>,
    /// The highest call-log rowid when the current request turn began: the
    /// turn's calls are the ones logged after it, however fast turns follow
    /// each other. Never in the snapshot.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub turn_calls_after: i64,
    /// Snapshot only: the last day of state changes. Never stored in `data`;
    /// the transition log is the record.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub transitions: Vec<Transition>,
    /// Snapshot only: seconds spent per state over the retained log, absent
    /// when the session has no logged change (e.g. it predates the log).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub totals: Option<Totals>,
}

/// One logged state change: the state entered and when. `outcome` says how a
/// turn ended (`turn-ended`, `interrupted`, `error`, `tool-error`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Transition {
    pub state: String,
    pub at: u64,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub outcome: String,
}

/// A request (`prompt`) or the reply that ended a turn (`response`), clipped
/// and scrubbed like the latest ones.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Message {
    pub kind: String,
    pub text: String,
    pub at: u64,
}

/// Where a turn began: `prompt` for a request the user sent.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Turn {
    pub kind: String,
    pub at: u64,
}

/// A tool call as the dashboard draws it: the tool's own name, the names of
/// the files it touched, whether it failed, and when it started.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Call {
    pub tool: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub files: Vec<String>,
    #[serde(default, skip_serializing_if = "is_false")]
    pub failed: bool,
    pub at: u64,
}

/// How far a todo list has come: its size, how many are done, and the text of
/// the one in progress (empty when none is).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TodoSummary {
    pub total: usize,
    pub done: usize,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub active: String,
}

/// What an ended turn left: the files its edits changed, the lines they
/// added and removed, how its last test command went (`passed`, `failed`,
/// `unknown` when the provider did not say, `none` without one), and the
/// commits it made.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TurnSummary {
    pub started_at: u64,
    pub files_changed: usize,
    pub lines_added: u64,
    pub lines_removed: u64,
    pub tests: String,
    pub commits: usize,
}

/// The summary of `items`; none for an empty list.
pub fn todo_summary(items: &[TodoItem]) -> Option<TodoSummary> {
    if items.is_empty() {
        return None;
    }
    Some(TodoSummary {
        total: items.len(),
        done: items.iter().filter(|todo| todo.status == "done").count(),
        active: items
            .iter()
            .find(|todo| todo.status == "active")
            .map(|todo| todo.text.clone())
            .unwrap_or_default(),
    })
}

/// Messages kept per session, newest kept.
pub const MESSAGE_LIMIT: usize = 3;

/// Adds a message, skipping an empty one or a repeat of the newest.
pub fn remember(messages: &mut Vec<Message>, kind: &str, text: &str, at: u64) {
    if text.is_empty()
        || messages
            .last()
            .is_some_and(|m| m.kind == kind && m.text == text)
    {
        return;
    }
    messages.push(Message {
        kind: kind.into(),
        text: text.into(),
        at,
    });
    if messages.len() > MESSAGE_LIMIT {
        messages.drain(..messages.len() - MESSAGE_LIMIT);
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Totals {
    pub running: u64,
    pub waiting: u64,
    pub finished: u64,
}

/// Sessions and the transition log are kept for this long.
const RETENTION_SECS: u64 = 7 * 86400;
/// The snapshot carries this much recent history per session; older changes
/// only count toward `totals`.
const RECENT_SECS: u64 = 86400;
/// Upper bound on recent transitions per session, newest kept.
const RECENT_LIMIT: usize = 500;
/// Matches the snapshot's stale rule: no event for this long.
const STALE_SECS: u64 = 900;
/// Tool calls are kept for this long: a few hours drawn on the dashboard, and
/// a whole turn, however long, for its summary.
const CALL_RETENTION_SECS: u64 = 86400;
/// The snapshot carries the last few hours of calls and turns per session.
const RING_SECS: u64 = 3 * 3600;
/// Upper bound on calls per session in a snapshot, newest kept.
const CALL_LIMIT: usize = 300;
/// Upper bound on turn starts kept per session, newest kept.
pub const TURN_LIMIT: usize = 50;
const SCHEMA_VERSION: u32 = 3;
const SESSIONS_TABLE: &str = "CREATE TABLE IF NOT EXISTS sessions (workspace TEXT NOT NULL, provider TEXT NOT NULL, session TEXT NOT NULL, agent TEXT NOT NULL, data TEXT NOT NULL, updated INTEGER NOT NULL, PRIMARY KEY(workspace,provider,session,agent));";
const TRANSITIONS_TABLE: &str = "CREATE TABLE IF NOT EXISTS transitions (workspace TEXT NOT NULL, provider TEXT NOT NULL, session TEXT NOT NULL, agent TEXT NOT NULL, state TEXT NOT NULL, outcome TEXT NOT NULL, at INTEGER NOT NULL); CREATE INDEX IF NOT EXISTS transitions_by_session ON transitions(workspace,provider,session,agent,at); CREATE INDEX IF NOT EXISTS transitions_by_time ON transitions(at);";
/// One row per tool call: names and numbers only, never paths, contents or
/// command text. `files` is a JSON array of file names; `added`, `removed`
/// and `kind` (`test`, `commit`) describe what an edit or command did.
const TOOL_CALLS_TABLE: &str = "CREATE TABLE IF NOT EXISTS tool_calls (workspace TEXT NOT NULL, provider TEXT NOT NULL, session TEXT NOT NULL, agent TEXT NOT NULL, tool_use_id TEXT NOT NULL, tool TEXT NOT NULL, files TEXT NOT NULL, edit INTEGER NOT NULL, failed INTEGER NOT NULL DEFAULT 0, added INTEGER NOT NULL DEFAULT 0, removed INTEGER NOT NULL DEFAULT 0, kind TEXT NOT NULL DEFAULT '', at INTEGER NOT NULL); CREATE INDEX IF NOT EXISTS tool_calls_by_session ON tool_calls(workspace,provider,session,agent,at); CREATE INDEX IF NOT EXISTS tool_calls_by_time ON tool_calls(at); CREATE UNIQUE INDEX IF NOT EXISTS tool_calls_by_id ON tool_calls(workspace,provider,session,agent,tool_use_id) WHERE tool_use_id <> '';";
/// How long a hook writer waits for another writer's commit. Hooks from
/// several sessions serialize on one database, and each commit fsyncs, so on
/// a busy disk the queue outlasts a short timeout and the event is lost.
/// Snapshot readers keep the short timeout in `open_read` and retry on the
/// next poll instead.
const WRITE_BUSY_TIMEOUT: Duration = Duration::from_secs(5);

fn initialize(db: &Connection) -> Result<()> {
    db.busy_timeout(WRITE_BUSY_TIMEOUT)?;
    let version: u32 = db.query_row("PRAGMA user_version", [], |r| r.get(0))?;
    if version > SCHEMA_VERSION {
        return Err("Runtime database is newer; update workbranch".into());
    }
    // Opening an initialized store must not compete with hook event writers.
    if version == SCHEMA_VERSION {
        return Ok(());
    }
    // A new store gets every table; an older one gains what it lacks: version
    // 1 (sessions only) the transition log, versions 1 and 2 the call log.
    // IMMEDIATE serializes hooks that upgrade at once, and IF NOT EXISTS makes
    // the later one a no-op.
    db.execute_batch(&format!(
        "BEGIN IMMEDIATE; {SESSIONS_TABLE} {TRANSITIONS_TABLE} {TOOL_CALLS_TABLE} PRAGMA user_version={SCHEMA_VERSION}; COMMIT;"
    ))?;
    Ok(())
}
pub fn open_memory() -> Result<Connection> {
    let db = Connection::open_in_memory()?;
    initialize(&db)?;
    Ok(db)
}
pub fn open(path: &Path) -> Result<Connection> {
    if let Some(dir) = path.parent() {
        if dir.is_symlink() {
            return Err("Runtime directory must not be a symbolic link".into());
        }
        std::fs::create_dir_all(dir)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700))?;
        }
    }
    if path.is_symlink() {
        return Err("Runtime DB must not be a symbolic link".into());
    }
    let db = Connection::open(path)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    }
    initialize(&db)?;
    Ok(db)
}
pub fn load(
    db: &Connection,
    workspace: &str,
    provider: &str,
    session: &str,
    agent: &str,
) -> Result<Option<Session>> {
    let data: Option<String> = db
        .query_row(
            "SELECT data FROM sessions WHERE workspace=? AND provider=? AND session=? AND agent=?",
            params![workspace, provider, session, agent],
            |r| r.get(0),
        )
        .optional()?;
    data.map(|v| serde_json::from_str(&v).map_err(Into::into))
        .transpose()
}
pub fn save(db: &Connection, s: &Session) -> Result<()> {
    db.execute("INSERT INTO sessions VALUES (?,?,?,?,?,?) ON CONFLICT(workspace,provider,session,agent) DO UPDATE SET data=excluded.data,updated=excluded.updated", params![s.workspace,s.provider,s.session_id,s.agent_id,serde_json::to_string(s)?,i64::try_from(s.updated_at)?])?;
    // Purging is bounded by age and never creates a second history of content:
    // the transition log holds states and times only, and the few recent
    // messages live in the session row itself.
    let cutoff = i64::try_from(s.updated_at.saturating_sub(RETENTION_SECS))?;
    db.execute("DELETE FROM sessions WHERE updated < ?", [cutoff])?;
    // A purged session's changes all predate the cutoff; they go with it.
    db.execute(
        "DELETE FROM transitions WHERE at < ?1 AND NOT EXISTS (SELECT 1 FROM sessions s WHERE s.workspace=transitions.workspace AND s.provider=transitions.provider AND s.session=transitions.session AND s.agent=transitions.agent)",
        [cutoff],
    )?;
    // A live session keeps the state in force at the cutoff: its last change
    // before the cutoff moves up to it, so a long-held state still counts
    // from there instead of vanishing with its row.
    db.execute(
        "UPDATE transitions SET at = ?1 WHERE rowid IN (SELECT max(rowid) FROM transitions WHERE at < ?1 GROUP BY workspace, provider, session, agent)",
        [cutoff],
    )?;
    db.execute("DELETE FROM transitions WHERE at < ?", [cutoff])?;
    let call_cutoff = i64::try_from(s.updated_at.saturating_sub(CALL_RETENTION_SECS))?;
    db.execute("DELETE FROM tool_calls WHERE at < ?", [call_cutoff])?;
    Ok(())
}

/// Drops a session key's logs, for a session that starts over under a key a
/// previous one used (a recreated workspace).
pub fn forget_history(
    db: &Connection,
    workspace: &str,
    provider: &str,
    session: &str,
    agent: &str,
) -> Result<()> {
    for table in ["transitions", "tool_calls"] {
        db.execute(
            &format!("DELETE FROM {table} WHERE workspace=? AND provider=? AND session=? AND agent=?"),
            params![workspace, provider, session, agent],
        )?;
    }
    Ok(())
}

/// What the log keeps of one call: names and numbers, no content.
pub struct CallRecord<'a> {
    pub tool_use_id: &'a str,
    pub tool: &'a str,
    pub files: &'a [String],
    pub edit: bool,
    pub added: u32,
    pub removed: u32,
    /// `test` and/or `commit`, space separated; empty for anything else.
    pub kind: String,
}

/// Logs a tool call `s` started at `at`. A repeated call id is logged once.
pub fn record_call(db: &Connection, s: &Session, call: &CallRecord, at: u64) -> Result<()> {
    db.execute(
        "INSERT OR IGNORE INTO tool_calls (workspace, provider, session, agent, tool_use_id, tool, files, edit, added, removed, kind, at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        params![
            s.workspace,
            s.provider,
            s.session_id,
            s.agent_id,
            call.tool_use_id,
            call.tool,
            serde_json::to_string(call.files)?,
            call.edit,
            call.added,
            call.removed,
            call.kind,
            i64::try_from(at)?
        ],
    )?;
    Ok(())
}

/// Marks the call `tool_use_id` of `s` as known to have succeeded: a test or
/// commit it ran then counts as passed or made.
pub fn confirm_call(db: &Connection, s: &Session, tool_use_id: &str) -> Result<()> {
    db.execute(
        "UPDATE tool_calls SET kind = kind || ' ok' WHERE workspace=? AND provider=? AND session=? AND agent=? AND tool_use_id=? AND kind <> '' AND failed = 0 AND kind NOT LIKE '% ok'",
        params![s.workspace, s.provider, s.session_id, s.agent_id, tool_use_id],
    )?;
    Ok(())
}

/// Marks the call `tool_use_id` of `s` as failed.
pub fn fail_call(db: &Connection, s: &Session, tool_use_id: &str) -> Result<()> {
    db.execute(
        "UPDATE tool_calls SET failed=1 WHERE workspace=? AND provider=? AND session=? AND agent=? AND tool_use_id=?",
        params![s.workspace, s.provider, s.session_id, s.agent_id, tool_use_id],
    )?;
    Ok(())
}

/// Adds a turn start, keeping the newest `TURN_LIMIT`.
pub fn remember_turn(turns: &mut Vec<Turn>, kind: &str, at: u64) {
    turns.push(Turn {
        kind: kind.into(),
        at,
    });
    if turns.len() > TURN_LIMIT {
        turns.drain(..turns.len() - TURN_LIMIT);
    }
}

/// Logs that `s` entered its current state at `at`.
pub fn record_transition(db: &Connection, s: &Session, at: u64) -> Result<()> {
    db.execute(
        "INSERT INTO transitions VALUES (?,?,?,?,?,?,?)",
        params![
            s.workspace,
            s.provider,
            s.session_id,
            s.agent_id,
            s.state,
            if s.state == "finished" { s.outcome.as_str() } else { "" },
            i64::try_from(at)?
        ],
    )?;
    Ok(())
}

fn transitions_of(db: &Connection, s: &Session) -> Result<Vec<Transition>> {
    let mut stmt = db.prepare(
        "SELECT state, outcome, at FROM transitions WHERE workspace=? AND provider=? AND session=? AND agent=? ORDER BY at, rowid",
    )?;
    let rows = stmt.query_map(
        params![s.workspace, s.provider, s.session_id, s.agent_id],
        |r| {
            Ok(Transition {
                state: r.get(0)?,
                outcome: r.get(1)?,
                at: u64::try_from(r.get::<_, i64>(2)?).unwrap_or(0),
            })
        },
    )?;
    Ok(rows.collect::<std::result::Result<_, _>>()?)
}

/// What the session's last request turn left, once that turn has ended.
pub fn turn_summary(db: &Connection, s: &Session) -> Result<Option<TurnSummary>> {
    let Some(start) = s.turns.iter().rev().find(|turn| turn.kind == "prompt").map(|turn| turn.at) else {
        return Ok(None);
    };
    if s.state != "finished" {
        return Ok(None);
    }
    let mut stmt = db.prepare(
        "SELECT files, edit, added, removed, kind, failed FROM tool_calls WHERE workspace=? AND provider=? AND session=? AND agent=? AND rowid > ? ORDER BY rowid",
    )?;
    let rows = stmt.query_map(
        params![s.workspace, s.provider, s.session_id, s.agent_id, s.turn_calls_after],
        |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, bool>(1)?,
                r.get::<_, i64>(2)?,
                r.get::<_, i64>(3)?,
                r.get::<_, String>(4)?,
                r.get::<_, bool>(5)?,
            ))
        },
    )?;
    let mut summary = TurnSummary {
        started_at: start,
        tests: "none".into(),
        ..TurnSummary::default()
    };
    let mut files: Vec<String> = Vec::new();
    for row in rows {
        let (names, edit, added, removed, kind, failed) = row?;
        let kinds: Vec<&str> = kind.split(' ').collect();
        // An edit the provider rejected changed nothing.
        if edit && !failed {
            for name in serde_json::from_str::<Vec<String>>(&names).unwrap_or_default() {
                if !files.contains(&name) {
                    files.push(name);
                }
            }
            summary.lines_added += u64::try_from(added).unwrap_or(0);
            summary.lines_removed += u64::try_from(removed).unwrap_or(0);
        }
        if kinds.contains(&"test") {
            summary.tests = if failed {
                "failed"
            } else if kinds.contains(&"ok") {
                "passed"
            } else {
                "unknown"
            }
            .into();
        }
        if !failed {
            summary.commits += kinds.iter().filter(|kind| **kind == "commit").count();
        }
    }
    summary.files_changed = files.len();
    Ok(Some(summary))
}

/// The session's calls since `since`, oldest first; at most `CALL_LIMIT`,
/// newest kept.
fn calls_of(db: &Connection, s: &Session, since: u64) -> Result<Vec<Call>> {
    let mut stmt = db.prepare(
        "SELECT tool, files, failed, at FROM tool_calls WHERE workspace=? AND provider=? AND session=? AND agent=? AND at >= ? ORDER BY at DESC, rowid DESC LIMIT ?",
    )?;
    let rows = stmt.query_map(
        params![
            s.workspace,
            s.provider,
            s.session_id,
            s.agent_id,
            i64::try_from(since)?,
            i64::try_from(CALL_LIMIT)?
        ],
        |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, bool>(2)?,
                r.get::<_, i64>(3)?,
            ))
        },
    )?;
    let mut calls = Vec::new();
    for row in rows {
        let (tool, files, failed, at) = row?;
        calls.push(Call {
            tool,
            // A row the collector wrote always parses; anything else has no names.
            files: serde_json::from_str(&files).unwrap_or_default(),
            failed,
            at: u64::try_from(at).unwrap_or(0),
        });
    }
    calls.reverse();
    Ok(calls)
}

/// Seconds per state across the whole log. Each change lasts until the next
/// one; the last lasts until `end`.
pub fn totals(log: &[Transition], end: u64) -> Totals {
    let mut totals = Totals::default();
    for (i, t) in log.iter().enumerate() {
        let until = log.get(i + 1).map_or(end, |next| next.at);
        let spent = until.saturating_sub(t.at);
        match t.state.as_str() {
            "running" => totals.running += spent,
            "waiting" => totals.waiting += spent,
            "finished" => totals.finished += spent,
            _ => {}
        }
    }
    totals
}

/// The changes since `since`, led by the one in force at `since` so the state
/// at the window's start is known; at most `RECENT_LIMIT`, newest kept.
pub fn recent(log: &[Transition], since: u64) -> Vec<Transition> {
    let first = log.iter().rposition(|t| t.at <= since).unwrap_or(0);
    let tail = &log[first..];
    tail[tail.len().saturating_sub(RECENT_LIMIT)..].to_vec()
}
pub fn snapshot(db: &Connection, now: u64) -> Result<Vec<Session>> {
    let mut stmt = db.prepare(
        "SELECT data FROM sessions WHERE updated >= ? ORDER BY workspace,provider,session,agent",
    )?;
    let data = stmt.query_map([i64::try_from(now.saturating_sub(RETENTION_SECS))?], |r| {
        r.get::<_, String>(0)
    })?;
    // A version 1 store has no transition log yet; its sessions carry no history.
    let version: u32 = db.query_row("PRAGMA user_version", [], |r| r.get(0))?;
    let logged = version >= 2;
    // Calls are logged from version 3 on.
    let calls_logged = version >= 3;
    let ring_start = now.saturating_sub(RING_SECS);
    let mut result = Vec::new();
    for item in data {
        let mut s: Session = serde_json::from_str(&item?)?;
        if !s.workspace_stamp.is_empty()
            && workspace_stamp(Path::new(&s.workspace)) != s.workspace_stamp
        {
            continue;
        }
        let stale = matches!(s.state.as_str(), "running" | "waiting")
            && now.saturating_sub(s.updated_at) >= STALE_SECS;
        if stale {
            s.observation = "stale".into();
        }
        if logged {
            let log = transitions_of(db, &s)?;
            if !log.is_empty() {
                // A stale session's last state is unconfirmed after its last event.
                let end = if stale { s.updated_at } else { now };
                s.totals = Some(totals(&log, end));
                s.transitions = recent(&log, now.saturating_sub(RECENT_SECS));
            }
        }
        if calls_logged {
            s.calls = calls_of(db, &s, ring_start)?;
        }
        s.turns.retain(|turn| turn.at >= ring_start);
        if s.state != "finished" {
            s.last_turn = None;
        }
        s.turn_calls_after = 0;
        s.todos = todo_summary(&s.todo_items);
        s.todo_items.clear();
        s.closed = false;
        s.workspace_stamp.clear();
        s.retired_turns.clear();
        s.active_tools.clear();
        s.waits.clear();
        s.completed_tools.clear();
        result.push(s);
    }
    Ok(result)
}

pub fn workspace_stamp(path: &Path) -> String {
    let marker = path.join(".workbranch.task");
    if marker.is_symlink() {
        return String::new();
    }
    let Ok(meta) = std::fs::metadata(marker) else {
        return String::new();
    };
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        let created = meta
            .created()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|t| t.as_nanos())
            .unwrap_or(0);
        if created > 0 {
            format!("{}:{}:{}", meta.dev(), meta.ino(), created)
        } else {
            format!(
                "{}:{}:{}:{}",
                meta.dev(),
                meta.ino(),
                meta.ctime(),
                meta.ctime_nsec()
            )
        }
    }
    #[cfg(not(unix))]
    {
        format!("{:?}", meta.created().or_else(|_| meta.modified()).ok())
    }
}

pub fn open_read(path: &Path) -> Result<Connection> {
    if path.is_symlink() {
        return Err("Runtime DB must not be a symbolic link".into());
    }
    let db = Connection::open_with_flags(path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    db.busy_timeout(Duration::from_millis(150))?;
    let version: u32 = db.query_row("PRAGMA user_version", [], |r| r.get(0))?;
    // Version 1 is read as before (no history) until a hook upgrades it.
    if !(1..=SCHEMA_VERSION).contains(&version) {
        return Err("Update runtime collector: incompatible database schema".into());
    }
    Ok(db)
}

fn is_false(value: &bool) -> bool {
    !value
}

fn is_zero(value: &i64) -> bool {
    *value == 0
}

/// The highest rowid in the call log, 0 when it is empty.
pub fn last_call_rowid(db: &Connection) -> Result<i64> {
    Ok(db.query_row("SELECT coalesce(max(rowid), 0) FROM tool_calls", [], |r| r.get(0))?)
}
