use std::fs::{self, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
#[cfg(test)]
use std::sync::atomic::{AtomicU64, Ordering};

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

pub(crate) fn read_activity_events_default(
    from_epoch: u64,
    to_epoch: u64,
) -> Result<Vec<serde_json::Value>, CompanionError> {
    let path = activity_log_path(None)?;
    read_activity_events_in_range(&path, from_epoch, to_epoch)
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

pub(crate) fn read_activity_events_in_range(
    path: &Path,
    from_epoch: u64,
    to_epoch: u64,
) -> Result<Vec<serde_json::Value>, CompanionError> {
    let file = match std::fs::File::open(path) {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(Vec::new());
        }
        Err(error) => return Err(error.into()),
    };

    let mut events = Vec::new();
    for line in BufReader::new(file).lines() {
        let Ok(line) = line else {
            continue;
        };
        let Ok(value) = serde_json::from_str::<serde_json::Value>(&line) else {
            continue;
        };
        let Some(observed_at) = value.get("observedAt").and_then(serde_json::Value::as_u64) else {
            continue;
        };
        if observed_at >= from_epoch && observed_at <= to_epoch {
            events.push(value);
        }
    }
    Ok(events)
}

#[cfg(test)]
mod tests {
    use super::*;

    static NEXT_TEMP_DIR: AtomicU64 = AtomicU64::new(0);

    fn tempdir_like() -> Result<PathBuf, Box<dyn std::error::Error>> {
        let suffix = NEXT_TEMP_DIR.fetch_add(1, Ordering::Relaxed);
        let path =
            std::env::temp_dir().join(format!("wb-activity-test-{}-{suffix}", std::process::id()));
        fs::create_dir_all(&path)?;
        Ok(path)
    }

    fn write_lines(dir: &Path, lines: &[&str]) -> Result<PathBuf, Box<dyn std::error::Error>> {
        let path = dir.join("activity.jsonl");
        let mut file = std::fs::File::create(&path)?;
        for line in lines {
            writeln!(file, "{line}")?;
        }
        Ok(path)
    }

    #[test]
    fn reads_events_within_range_inclusive() -> Result<(), Box<dyn std::error::Error>> {
        let dir = tempdir_like()?;
        let path = write_lines(
            &dir,
            &[
                r#"{"v":1,"observedAt":100,"project":"a","task":"t1"}"#,
                r#"{"v":1,"observedAt":200,"project":"a","task":"t1"}"#,
                r#"{"v":1,"observedAt":300,"project":"a","task":"t1"}"#,
            ],
        )?;

        let events = read_activity_events_in_range(&path, 150, 300)?;

        assert_eq!(events.len(), 2);
        assert_eq!(events[0]["observedAt"], 200);
        assert_eq!(events[1]["observedAt"], 300);
        Ok(())
    }

    #[test]
    fn skips_unparseable_and_legacy_lines_without_observed_at()
    -> Result<(), Box<dyn std::error::Error>> {
        let dir = tempdir_like()?;
        let path = write_lines(
            &dir,
            &[
                "not json at all",
                r#"{"v":1,"project":"a","task":"t"}"#,
                r#"{"v":1,"observedAt":100,"project":"a","task":"t","plan":"P","planIndex":0}"#,
            ],
        )?;

        let events = read_activity_events_in_range(&path, 0, 1_000)?;

        assert_eq!(events.len(), 1);
        assert_eq!(events[0]["observedAt"], 100);
        Ok(())
    }

    #[test]
    fn skips_invalid_utf8_lines_and_continues() -> Result<(), Box<dyn std::error::Error>> {
        let dir = tempdir_like()?;
        let path = dir.join("activity.jsonl");
        let mut file = std::fs::File::create(&path)?;
        file.write_all(br#"{"v":1,"observedAt":100,"project":"a","task":"t"}"#)?;
        file.write_all(b"\n\xff\xfe\n")?;
        file.write_all(br#"{"v":1,"observedAt":200,"project":"a","task":"t"}"#)?;
        file.write_all(b"\n")?;

        let events = read_activity_events_in_range(&path, 0, 1_000)?;

        assert_eq!(events.len(), 2);
        assert_eq!(events[0]["observedAt"], 100);
        assert_eq!(events[1]["observedAt"], 200);
        Ok(())
    }

    #[test]
    fn missing_file_returns_empty() -> Result<(), Box<dyn std::error::Error>> {
        let dir = tempdir_like()?;

        let events = read_activity_events_in_range(&dir.join("absent.jsonl"), 0, 10)?;

        assert!(events.is_empty());
        Ok(())
    }
}
