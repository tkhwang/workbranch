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
}
fn initialize(db: &Connection) -> Result<()> {
    db.busy_timeout(Duration::from_millis(150))?;
    let version: u32 = db.query_row("PRAGMA user_version", [], |r| r.get(0))?;
    if version > 1 {
        return Err("Runtime database is newer; update workbranch".into());
    }
    // Opening an initialized store must not compete with hook event writers.
    if version == 1 {
        return Ok(());
    }
    db.execute_batch("CREATE TABLE IF NOT EXISTS sessions (workspace TEXT NOT NULL, provider TEXT NOT NULL, session TEXT NOT NULL, agent TEXT NOT NULL, data TEXT NOT NULL, updated INTEGER NOT NULL, PRIMARY KEY(workspace,provider,session,agent)); PRAGMA user_version=1;")?;
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
    // Purging is bounded by age and never creates a second history of content.
    db.execute(
        "DELETE FROM sessions WHERE updated < ?",
        [i64::try_from(s.updated_at.saturating_sub(7 * 86400))?],
    )?;
    Ok(())
}
pub fn snapshot(db: &Connection, now: u64) -> Result<Vec<Session>> {
    let mut stmt = db.prepare(
        "SELECT data FROM sessions WHERE updated >= ? ORDER BY workspace,provider,session,agent",
    )?;
    let data = stmt.query_map([i64::try_from(now.saturating_sub(7 * 86400))?], |r| {
        r.get::<_, String>(0)
    })?;
    let mut result = Vec::new();
    for item in data {
        let mut s: Session = serde_json::from_str(&item?)?;
        if !s.workspace_stamp.is_empty()
            && workspace_stamp(Path::new(&s.workspace)) != s.workspace_stamp
        {
            continue;
        }
        if matches!(s.state.as_str(), "running" | "waiting")
            && now.saturating_sub(s.updated_at) >= 900
        {
            s.observation = "stale".into();
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
    if version != 1 {
        return Err("Update runtime collector: incompatible database schema".into());
    }
    Ok(db)
}

fn is_false(value: &bool) -> bool {
    !value
}
