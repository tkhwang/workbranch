use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::CompanionError;

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ChecklistItem {
    pub(crate) text: String,
    pub(crate) checked: bool,
    pub(crate) depth: u64,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ActivityEvent {
    pub(crate) v: u8,
    pub(crate) edited_at: u64,
    pub(crate) observed_at: u64,
    pub(crate) root: String,
    pub(crate) project: String,
    pub(crate) task: String,
    pub(crate) plan: String,
    pub(crate) plan_index: u64,
    pub(crate) plan_title: String,
    pub(crate) plan_status: String,
    pub(crate) status: String,
    pub(crate) task_progress_done: u64,
    pub(crate) task_progress_total: u64,
    pub(crate) progress_done: u64,
    pub(crate) progress_total: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) items: Option<Vec<ChecklistItem>>,
}

pub(crate) fn append_activity_events_default(
    events: &[ActivityEvent],
) -> Result<(), CompanionError> {
    let path = activity_log_path(None)?;
    append_activity_events_to_path(&path, events)
}

fn activity_log_path(state_home: Option<&Path>) -> Result<PathBuf, CompanionError> {
    let base = match state_home {
        Some(path) => path.to_path_buf(),
        None => default_state_home()?,
    };
    Ok(base.join("workbranch/activity.jsonl"))
}

fn default_state_home() -> Result<PathBuf, CompanionError> {
    if let Some(path) = std::env::var_os("XDG_STATE_HOME").map(PathBuf::from) {
        return Ok(path);
    }
    if let Some(home) = std::env::var_os("HOME") {
        return Ok(PathBuf::from(home).join(".local/state"));
    }
    Err(std::io::Error::new(
        std::io::ErrorKind::NotFound,
        "HOME or XDG_STATE_HOME is required for activity log storage",
    )
    .into())
}

pub(crate) fn append_activity_events_to_path(
    path: &Path,
    events: &[ActivityEvent],
) -> Result<(), CompanionError> {
    if events.is_empty() {
        return Ok(());
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut file = OpenOptions::new().create(true).append(true).open(path)?;
    for event in events {
        serde_json::to_writer(&mut file, event).map_err(std::io::Error::other)?;
        file.write_all(b"\n")?;
    }
    Ok(())
}
