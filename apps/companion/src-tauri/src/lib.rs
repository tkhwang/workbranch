use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use tauri::{AppHandle, Emitter, Manager, State};
use thiserror::Error;

mod menu_bar;
mod process_env;
mod setup;
mod tray;
mod update;
mod usage;
mod watch_filter;
mod watch_roots;
mod watch_scope;
mod workbranch_bin;
#[cfg(test)]
mod workbranch_command_tests;

use process_env::gui_safe_path;
use watch_roots::{WatcherSet, reconcile_watchers};
use workbranch_bin::resolve_workbranch_bin;

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
    watchers: Arc<Mutex<WatcherSet>>,
}

#[derive(Default)]
struct UsageStore {
    cache: Arc<Mutex<usage::UsageCache>>,
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

fn workbranch_args_for(action: &CompanionCommand) -> Option<Vec<&str>> {
    match action {
        CompanionCommand::NotiClear { task } => Some(vec!["noti", "clear", task.as_str()]),
        CompanionCommand::Finder { task } => Some(vec!["finder", task.as_str()]),
        CompanionCommand::Ide { task } => Some(vec!["ide", task.as_str()]),
        CompanionCommand::Terminal { task } => Some(vec!["terminal", task.as_str()]),
        CompanionCommand::CopyPath { .. } => None,
    }
}

#[tauri::command]
async fn workbranch_list(root: String) -> Result<String, CompanionError> {
    tauri::async_runtime::spawn_blocking(move || {
        let bin = resolve_workbranch_bin(None)?;
        run_workbranch_stdout(&bin, &["list", "--json"], Path::new(&root))
    })
    .await
    .map_err(|error| std::io::Error::other(error.to_string()))?
}

#[tauri::command]
async fn workbranch_list_global() -> Result<String, CompanionError> {
    tauri::async_runtime::spawn_blocking(|| workbranch_list_global_with_config_home(None))
        .await
        .map_err(|error| std::io::Error::other(error.to_string()))?
}

fn workbranch_list_global_with_config_home(
    config_home: Option<&Path>,
) -> Result<String, CompanionError> {
    let bin = resolve_workbranch_bin(config_home)?;
    let cwd = std::env::var_os("HOME").map_or_else(|| PathBuf::from("/"), PathBuf::from);
    run_workbranch_global_json_stdout(&bin, &["list", "--global", "--json"], &cwd)
}

#[tauri::command]
async fn workbranch_runtime() -> Result<String, CompanionError> {
    tauri::async_runtime::spawn_blocking(|| {
        let bin = resolve_workbranch_bin(None)?;
        let cwd = std::env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/"));
        run_workbranch_stdout(&bin, &["runtime", "--json"], &cwd)
    })
    .await
    .map_err(|e| std::io::Error::other(e.to_string()))?
}

#[tauri::command]
async fn workbranch_migrate(apply: bool) -> Result<RunResult, CompanionError> {
    tauri::async_runtime::spawn_blocking(move || {
        let bin = resolve_workbranch_bin(None)?;
        let cwd = std::env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/"));
        run_workbranch(
            &bin,
            &[
                "migrate",
                "agent-runtime",
                if apply { "--apply" } else { "--dry-run" },
                "--global",
            ],
            &cwd,
        )
    })
    .await
    .map_err(|e| std::io::Error::other(e.to_string()))?
}

/// Reads Claude Code and Codex usage from their local files only.
#[tauri::command]
async fn usage_snapshot(
    days: u32,
    store: State<'_, UsageStore>,
) -> Result<usage::UsageSnapshot, CompanionError> {
    let cache = Arc::clone(&store.cache);
    tauri::async_runtime::spawn_blocking(move || {
        let paths = usage::UsagePaths::from_env().ok_or_else(|| {
            std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "HOME is required to read agent usage",
            )
        })?;
        let mut guard = cache
            .lock()
            .map_err(|_| std::io::Error::other("usage cache lock poisoned"))?;
        let now = usage::now_epoch();
        let since = usage::since_for_days(now, days);
        Ok(usage::snapshot(&mut guard, &paths, now, since))
    })
    .await
    .map_err(|error| std::io::Error::other(error.to_string()))?
}

#[tauri::command]
async fn workbranch_run(
    action: CompanionCommand,
    cwd: String,
) -> Result<RunResult, CompanionError> {
    tauri::async_runtime::spawn_blocking(move || {
        let cwd_path = PathBuf::from(cwd);
        match action {
            CompanionCommand::CopyPath { path } => run_pbcopy(&path),
            command => {
                let args = workbranch_args_for(&command).ok_or_else(|| {
                    std::io::Error::other("companion command has no workbranch argv")
                })?;
                run_workbranch(&resolve_workbranch_bin(None)?, &args, &cwd_path)
            }
        }
    })
    .await
    .map_err(|error| std::io::Error::other(error.to_string()))?
}

#[tauri::command]
fn quit_app(app: AppHandle) {
    app.exit(0);
}

#[tauri::command]
async fn watch_roots(
    app: AppHandle,
    roots: Vec<String>,
    watchers: State<'_, WatcherStore>,
) -> Result<WatchResult, CompanionError> {
    let app_for_watchers = app.clone();
    let roots_for_watchers = roots.clone();
    let watcher_store = Arc::clone(&watchers.watchers);
    let changed_roots = tauri::async_runtime::spawn_blocking(move || {
        let mut guard = watcher_store
            .lock()
            .map_err(|_| std::io::Error::other("watcher store lock poisoned"))?;
        reconcile_watchers(app_for_watchers, &roots_for_watchers, &mut guard)
    })
    .await
    .map_err(|error| std::io::Error::other(error.to_string()))??;

    for root in changed_roots {
        app.emit("roots-changed", root)
            .map_err(std::io::Error::other)?;
    }
    Ok(WatchResult { roots })
}

fn run_workbranch_global_json_stdout(
    bin: &Path,
    args: &[&str],
    cwd: &Path,
) -> Result<String, CompanionError> {
    let result = run_workbranch(bin, args, cwd)?;
    if result.exit_code == 0 || is_global_list_document(&result.stdout) {
        Ok(result.stdout)
    } else {
        Err(CompanionError::CommandFailed {
            exit_code: result.exit_code,
            stderr: result.stderr,
        })
    }
}

fn is_global_list_document(stdout: &str) -> bool {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(stdout) else {
        return false;
    };
    value
        .get("schemaVersion")
        .and_then(serde_json::Value::as_u64)
        == Some(2)
        && value
            .get("projects")
            .is_some_and(serde_json::Value::is_array)
        && value.get("errors").is_some_and(serde_json::Value::is_array)
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
    let home = std::env::var_os("HOME").map(PathBuf::from);
    let path = gui_safe_path(std::env::var_os("PATH").as_deref(), home.as_deref())
        .map_err(std::io::Error::other)?;
    let output = Command::new(bin)
        .args(args)
        .current_dir(cwd)
        .env("PATH", path)
        .output()?;
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
    let usage_store = UsageStore::default();
    // The menu bar title shares the Usage view's parse cache.
    let usage_cache = Arc::clone(&usage_store.cache);
    let builder = tauri::Builder::default().plugin(tauri_plugin_store::Builder::new().build());
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let builder = builder.plugin(tauri_plugin_autostart::init(
        tauri_plugin_autostart::MacosLauncher::LaunchAgent,
        None,
    ));
    let builder = builder
        .plugin(tauri_plugin_positioner::init())
        .manage(WatcherStore::default())
        .manage(usage_store)
        .setup(move |app| {
            tray::install(app)?;
            let refresher = menu_bar::start(app.handle(), usage_cache);
            app.manage(refresher);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            setup::setup_status,
            setup::setup_action,
            update::update_check,
            update::update_apply,
            update::relaunch_companion,
            workbranch_list,
            workbranch_list_global,
            workbranch_runtime,
            workbranch_migrate,
            workbranch_run,
            usage_snapshot,
            menu_bar::menu_bar_refresh,
            watch_roots,
            quit_app,
        ]);
    if let Err(error) = builder.run(tauri::generate_context!()) {
        eprintln!("error while running tauri application: {error}");
    }
}
