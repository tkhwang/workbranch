use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, State};
use thiserror::Error;

mod tray;

#[derive(Debug, Error)]
enum CompanionError {
    #[error("workbranch binary not found. Checked: {0:?}")]
    WorkbranchNotFound(Vec<String>),
    #[error("command failed with exit {exit_code}: {stderr}")]
    CommandFailed { exit_code: i32, stderr: String },
    #[error("failed to run command: {0}")]
    Io(#[from] std::io::Error),
    #[error("failed to watch roots: {0}")]
    Watch(#[from] notify::Error),
}

#[derive(Default)]
struct WatcherStore {
    watchers: Mutex<Vec<RecommendedWatcher>>,
}

impl serde::Serialize for CompanionError {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&self.to_string())
    }
}

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
enum CompanionCommand {
    Memo { task: String, text: String },
    MemoClear { task: String },
    NotiClear { task: String },
    Finder { task: String },
    Ide { task: String },
    Terminal { task: String },
    CopyPath { path: String },
}

#[derive(Debug, Serialize)]
struct RunResult {
    exit_code: i32,
    stdout: String,
    stderr: String,
}

#[derive(Debug, Serialize)]
struct WatchResult {
    roots: Vec<String>,
}

#[tauri::command]
fn workbranch_list(root: String) -> Result<String, CompanionError> {
    let bin = locate_workbranch(None)?;
    run_workbranch_stdout(&bin, &["list", "--json"], Path::new(&root))
}

#[tauri::command]
fn workbranch_list_global() -> Result<String, CompanionError> {
    let bin = locate_workbranch(None)?;
    let cwd = std::env::var_os("HOME").map_or_else(|| PathBuf::from("/"), PathBuf::from);
    run_workbranch_stdout(&bin, &["list", "--global", "--json"], &cwd)
}

#[tauri::command]
fn workbranch_run(action: CompanionCommand, cwd: String) -> Result<RunResult, CompanionError> {
    let cwd_path = PathBuf::from(cwd);
    match action {
        CompanionCommand::Memo { task, text } => run_workbranch(
            &locate_workbranch(None)?,
            &["memo", &task, &text],
            &cwd_path,
        ),
        CompanionCommand::MemoClear { task } => run_workbranch(
            &locate_workbranch(None)?,
            &["memo", "--clear", &task],
            &cwd_path,
        ),
        CompanionCommand::NotiClear { task } => run_workbranch(
            &locate_workbranch(None)?,
            &["noti", "clear", &task],
            &cwd_path,
        ),
        CompanionCommand::Finder { task } => {
            run_workbranch(&locate_workbranch(None)?, &["finder", &task], &cwd_path)
        }
        CompanionCommand::Ide { task } => {
            run_workbranch(&locate_workbranch(None)?, &["ide", &task], &cwd_path)
        }
        CompanionCommand::Terminal { task } => {
            run_workbranch(&locate_workbranch(None)?, &["terminal", &task], &cwd_path)
        }
        CompanionCommand::CopyPath { path } => run_pbcopy(&path),
    }
}

#[tauri::command]
fn watch_roots(
    app: AppHandle,
    roots: Vec<String>,
    watchers: State<'_, WatcherStore>,
) -> Result<WatchResult, CompanionError> {
    let debounce = Arc::new(Mutex::new(HashMap::<String, Instant>::new()));
    let mut next_watchers = Vec::with_capacity(roots.len());

    for root in &roots {
        let root_path = PathBuf::from(root);
        let root_label = root.clone();
        let app_handle = app.clone();
        let debounce_state = Arc::clone(&debounce);
        let mut watcher =
            notify::recommended_watcher(move |event: notify::Result<notify::Event>| {
                if event.is_err() {
                    return;
                }
                if should_emit_root_change(&debounce_state, &root_label) {
                    let _ = app_handle.emit("roots-changed", root_label.clone());
                }
            })?;
        watcher.watch(&root_path, RecursiveMode::Recursive)?;
        next_watchers.push(watcher);
        app.emit("roots-changed", root)
            .map_err(std::io::Error::other)?;
    }

    let mut guard = watchers
        .watchers
        .lock()
        .map_err(|_| std::io::Error::other("watcher store lock poisoned"))?;
    *guard = next_watchers;
    Ok(WatchResult { roots })
}

fn should_emit_root_change(debounce: &Arc<Mutex<HashMap<String, Instant>>>, root: &str) -> bool {
    const DEBOUNCE_WINDOW: Duration = Duration::from_millis(500);
    let now = Instant::now();
    let Ok(mut last_by_root) = debounce.lock() else {
        return true;
    };
    if let Some(last) = last_by_root.get(root)
        && now.duration_since(*last) < DEBOUNCE_WINDOW
    {
        return false;
    }
    last_by_root.insert(root.to_string(), now);
    true
}

fn locate_workbranch(configured: Option<&str>) -> Result<PathBuf, CompanionError> {
    let mut candidates = Vec::new();
    if let Some(path) = configured {
        candidates.push(PathBuf::from(path));
    }
    candidates.push(PathBuf::from("/opt/homebrew/bin/workbranch"));
    candidates.push(PathBuf::from("/usr/local/bin/workbranch"));
    if let Some(home) = std::env::var_os("HOME") {
        candidates.push(PathBuf::from(home).join(".local/bin/workbranch"));
    }
    candidates.push(
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../workbranch-cli/bin/workbranch"),
    );

    for candidate in &candidates {
        if candidate.is_file() {
            return Ok(candidate.clone());
        }
    }
    Err(CompanionError::WorkbranchNotFound(
        candidates
            .iter()
            .map(|path| path.display().to_string())
            .collect(),
    ))
}

fn run_workbranch_stdout(bin: &Path, args: &[&str], cwd: &Path) -> Result<String, CompanionError> {
    let result = run_workbranch(bin, args, cwd)?;
    if result.exit_code == 0 {
        Ok(result.stdout)
    } else {
        Err(CompanionError::CommandFailed {
            exit_code: result.exit_code,
            stderr: result.stderr,
        })
    }
}

fn run_workbranch(bin: &Path, args: &[&str], cwd: &Path) -> Result<RunResult, CompanionError> {
    let output = Command::new(bin).args(args).current_dir(cwd).output()?;
    Ok(RunResult {
        exit_code: output.status.code().unwrap_or(1),
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
    })
}

fn run_pbcopy(path: &str) -> Result<RunResult, CompanionError> {
    let mut child = Command::new("/usr/bin/pbcopy")
        .stdin(Stdio::piped())
        .spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        use std::io::Write;
        stdin.write_all(path.as_bytes())?;
    }
    let output = child.wait_with_output()?;
    Ok(RunResult {
        exit_code: output.status.code().unwrap_or(1),
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
    })
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default()
        .plugin(tauri_plugin_positioner::init())
        .manage(WatcherStore::default())
        .setup(|app| {
            tray::install(app)?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            workbranch_list,
            workbranch_list_global,
            workbranch_run,
            watch_roots,
        ]);
    if let Err(error) = builder.run(tauri::generate_context!()) {
        eprintln!("error while running tauri application: {error}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn locate_workbranch_finds_local_cli_when_available() {
        let found = locate_workbranch(None);
        assert!(found.is_ok(), "expected local workbranch binary: {found:?}");
    }
}
