//! Opt-in relay of Claude Code's live rate limits.
//!
//! Claude Code passes `rate_limits` (5h and weekly) to the status-line command
//! on every refresh, while `.claude.json` only changes when `/usage` is opened.
//! Turning the relay on points `statusLine.command` in Claude's settings at a
//! small wrapper that saves that input into the companion's data directory and
//! then runs the user's previous command with the same input, so their status
//! line keeps rendering. Turning it off restores the previous command.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::CompanionError;

/// Matches `identifier` in tauri.conf.json, so files sit next to the store.
const APP_IDENTIFIER: &str = "dev.tkhwang.workbranch.companion";
const WRAPPER_NAME: &str = "claude-statusline.sh";
/// Plain text so the wrapper can read it without a JSON parser.
const PREVIOUS_COMMAND_NAME: &str = "claude-statusline-command";
const STATE_NAME: &str = "claude-statusline-state.json";
const CAPTURE_NAME: &str = "claude-rate-limits.json";

const WRAPPER_SCRIPT: &str = r#"#!/bin/sh
# Installed by Workbranch Companion (Settings > Claude Limits).
# Saves Claude Code's rate limits, then runs your previous status line.
dir=$(dirname "$0")
input=$(cat)
case $input in
*'"rate_limits"'*)
	tmp="$dir/claude-rate-limits.json.$$"
	if printf '%s' "$input" >"$tmp"; then
		mv -f "$tmp" "$dir/claude-rate-limits.json"
	else
		rm -f "$tmp"
	fi
	;;
esac
previous=$(cat "$dir/claude-statusline-command" 2>/dev/null)
[ -n "$previous" ] || exit 0
printf '%s' "$input" | /bin/sh -c "$previous"
"#;

/// The companion's data directory, the same one Tauri resolves for the app.
pub(crate) fn data_dir(home: &Path) -> PathBuf {
    if cfg!(target_os = "macos") {
        return home
            .join("Library/Application Support")
            .join(APP_IDENTIFIER);
    }
    std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .filter(|dir| dir.is_absolute())
        .unwrap_or_else(|| home.join(".local/share"))
        .join(APP_IDENTIFIER)
}

pub(crate) fn capture_path(home: &Path) -> PathBuf {
    data_dir(home).join(CAPTURE_NAME)
}

pub(crate) struct RelayPaths {
    /// Claude Code's user settings, where `statusLine` lives.
    pub(crate) settings: PathBuf,
    pub(crate) data_dir: PathBuf,
}

impl RelayPaths {
    pub(crate) fn from_env() -> Option<Self> {
        let home = std::env::var_os("HOME").map(PathBuf::from)?;
        let claude_dir = std::env::var_os("CLAUDE_CONFIG_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".claude"));
        Some(Self {
            settings: claude_dir.join("settings.json"),
            data_dir: data_dir(&home),
        })
    }

    fn wrapper(&self) -> PathBuf {
        self.data_dir.join(WRAPPER_NAME)
    }

    fn wrapper_command(&self) -> String {
        shell_quote(&self.wrapper().to_string_lossy())
    }
}

#[derive(Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) struct RelayStatus {
    pub(crate) enabled: bool,
    /// The status line Claude Code runs besides the relay, if any.
    pub(crate) previous_command: Option<String>,
}

/// What the settings held before the relay; `None` means no status line.
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RelayState {
    previous: Option<Value>,
}

pub(crate) fn status(paths: &RelayPaths) -> std::io::Result<RelayStatus> {
    let settings = read_settings(&paths.settings)?;
    let enabled = current_command(&settings).as_deref() == Some(&paths.wrapper_command());
    let previous_command = if enabled {
        fs::read_to_string(paths.data_dir.join(PREVIOUS_COMMAND_NAME))
            .ok()
            .filter(|command| !command.trim().is_empty())
    } else {
        current_command(&settings)
    };
    Ok(RelayStatus {
        enabled,
        previous_command,
    })
}

pub(crate) fn enable(paths: &RelayPaths) -> std::io::Result<RelayStatus> {
    fs::create_dir_all(&paths.data_dir)?;
    write_atomic(&paths.wrapper(), WRAPPER_SCRIPT.as_bytes())?;
    set_executable(&paths.wrapper())?;
    let mut settings = read_settings(&paths.settings)?;
    let wrapper_command = paths.wrapper_command();
    if current_command(&settings).as_deref() != Some(&wrapper_command) {
        let previous = settings.get("statusLine").cloned();
        let previous_command = current_command(&settings).unwrap_or_default();
        write_atomic(
            &paths.data_dir.join(STATE_NAME),
            &serde_json::to_vec_pretty(&RelayState {
                previous: previous.clone(),
            })?,
        )?;
        write_atomic(
            &paths.data_dir.join(PREVIOUS_COMMAND_NAME),
            previous_command.as_bytes(),
        )?;
        let mut status_line = match previous {
            Some(Value::Object(fields)) => fields,
            _ => Map::new(),
        };
        status_line.insert("type".to_string(), Value::from("command"));
        status_line.insert("command".to_string(), Value::from(wrapper_command));
        settings.insert("statusLine".to_string(), Value::Object(status_line));
        write_settings(&paths.settings, &settings)?;
    }
    status(paths)
}

/// Restores the previous status line only while the relay is still the one
/// configured; a status line the user changed since then is left alone.
pub(crate) fn disable(paths: &RelayPaths) -> std::io::Result<RelayStatus> {
    let mut settings = read_settings(&paths.settings)?;
    if current_command(&settings).as_deref() == Some(&paths.wrapper_command()) {
        let state: Option<RelayState> = fs::read(paths.data_dir.join(STATE_NAME))
            .ok()
            .and_then(|raw| serde_json::from_slice(&raw).ok());
        match state.and_then(|state| state.previous) {
            Some(previous) => {
                settings.insert("statusLine".to_string(), previous);
            }
            None => {
                settings.remove("statusLine");
            }
        }
        write_settings(&paths.settings, &settings)?;
    }
    for name in [
        STATE_NAME,
        PREVIOUS_COMMAND_NAME,
        CAPTURE_NAME,
        WRAPPER_NAME,
    ] {
        remove_if_present(&paths.data_dir.join(name))?;
    }
    status(paths)
}

fn current_command(settings: &Map<String, Value>) -> Option<String> {
    settings
        .get("statusLine")?
        .get("command")?
        .as_str()
        .map(str::to_owned)
}

fn read_settings(path: &Path) -> std::io::Result<Map<String, Value>> {
    let raw = match fs::read(path) {
        Ok(raw) => raw,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Map::new()),
        Err(error) => return Err(error),
    };
    match serde_json::from_slice(&raw) {
        Ok(Value::Object(settings)) => Ok(settings),
        Ok(_) => Err(std::io::Error::other(format!(
            "{} is not a JSON object",
            path.display()
        ))),
        Err(error) => Err(std::io::Error::other(format!(
            "{} is not valid JSON: {error}",
            path.display()
        ))),
    }
}

fn write_settings(path: &Path, settings: &Map<String, Value>) -> std::io::Result<()> {
    let mut raw = serde_json::to_vec_pretty(settings)?;
    raw.push(b'\n');
    // Write through a symlinked settings.json (dotfile setups) to its target.
    let target = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent)?;
    }
    write_atomic(&target, &raw)
}

fn write_atomic(path: &Path, contents: &[u8]) -> std::io::Result<()> {
    let file_name = path
        .file_name()
        .ok_or_else(|| std::io::Error::other(format!("{} has no file name", path.display())))?;
    let mut temp_name = file_name.to_os_string();
    temp_name.push(format!(".wb-{}.tmp", std::process::id()));
    let temp = path.with_file_name(temp_name);
    let result = (|| {
        let mut file = fs::File::create(&temp)?;
        file.write_all(contents)?;
        file.sync_all()?;
        if let Ok(metadata) = fs::metadata(path) {
            fs::set_permissions(&temp, metadata.permissions())?;
        }
        fs::rename(&temp, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
}

#[cfg(unix)]
fn set_executable(path: &Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o755))
}

#[cfg(not(unix))]
fn set_executable(_path: &Path) -> std::io::Result<()> {
    Ok(())
}

fn remove_if_present(path: &Path) -> std::io::Result<()> {
    match fs::remove_file(path) {
        Err(error) if error.kind() != std::io::ErrorKind::NotFound => Err(error),
        _ => Ok(()),
    }
}

/// Single-quotes a path for the shell Claude Code runs the command with.
fn shell_quote(text: &str) -> String {
    format!("'{}'", text.replace('\'', r"'\''"))
}

fn relay_paths() -> Result<RelayPaths, CompanionError> {
    RelayPaths::from_env().ok_or_else(|| {
        std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "HOME is required to configure the Claude status line",
        )
        .into()
    })
}

#[tauri::command]
pub(crate) async fn claude_limit_relay_status() -> Result<RelayStatus, CompanionError> {
    tauri::async_runtime::spawn_blocking(|| Ok(status(&relay_paths()?)?))
        .await
        .map_err(|error| std::io::Error::other(error.to_string()))?
}

#[tauri::command]
pub(crate) async fn claude_limit_relay_set(enabled: bool) -> Result<RelayStatus, CompanionError> {
    tauri::async_runtime::spawn_blocking(move || {
        let paths = relay_paths()?;
        Ok(if enabled {
            enable(&paths)?
        } else {
            disable(&paths)?
        })
    })
    .await
    .map_err(|error| std::io::Error::other(error.to_string()))?
}

#[cfg(test)]
#[path = "claude_statusline_tests.rs"]
mod tests;
