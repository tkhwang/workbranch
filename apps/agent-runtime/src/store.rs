use crate::Result;
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
const SCHEMA_VERSION: u32 = 2;
const SESSIONS_TABLE: &str = "CREATE TABLE IF NOT EXISTS sessions (workspace TEXT NOT NULL, provider TEXT NOT NULL, session TEXT NOT NULL, agent TEXT NOT NULL, data TEXT NOT NULL, updated INTEGER NOT NULL, PRIMARY KEY(workspace,provider,session,agent));";
const TRANSITIONS_TABLE: &str = "CREATE TABLE IF NOT EXISTS transitions (workspace TEXT NOT NULL, provider TEXT NOT NULL, session TEXT NOT NULL, agent TEXT NOT NULL, state TEXT NOT NULL, outcome TEXT NOT NULL, at INTEGER NOT NULL); CREATE INDEX IF NOT EXISTS transitions_by_session ON transitions(workspace,provider,session,agent,at); CREATE INDEX IF NOT EXISTS transitions_by_time ON transitions(at);";
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
    // A new store gets both tables; a version 1 store (sessions only) gains the
    // transition log. IMMEDIATE serializes hooks that upgrade at once, and
    // IF NOT EXISTS makes the later one a no-op.
    db.execute_batch(&format!(
        "BEGIN IMMEDIATE; {SESSIONS_TABLE} {TRANSITIONS_TABLE} PRAGMA user_version={SCHEMA_VERSION}; COMMIT;"
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
    // the transition log holds states and times only.
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
    Ok(())
}

/// Drops a session key's log, for a session that starts over under a key a
/// previous one used (a recreated workspace).
pub fn forget_transitions(
    db: &Connection,
    workspace: &str,
    provider: &str,
    session: &str,
    agent: &str,
) -> Result<()> {
    db.execute(
        "DELETE FROM transitions WHERE workspace=? AND provider=? AND session=? AND agent=?",
        params![workspace, provider, session, agent],
    )?;
    Ok(())
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
