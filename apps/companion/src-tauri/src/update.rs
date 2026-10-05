use crate::setup::{FORMULA, Log, begin_action, execute, find_program, path_env};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    fs::File,
    io::Read,
    path::Path,
    process::{Command, Stdio},
    sync::Arc,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use tauri::{AppHandle, Emitter};

const CASK: &str = "tkhwang/tap/workbranch-companion";
const FETCH_TIMEOUT: Duration = Duration::from_secs(300);
const UPGRADE_TIMEOUT: Duration = Duration::from_secs(1800);
const OUTPUT_LIMIT: usize = 1_048_576;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum UpdateTarget {
    Cli,
    Companion,
}

#[derive(Debug, Default, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PackageVersion {
    installed: Option<String>,
    latest: Option<String>,
    outdated: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct UpdateStatus {
    brew_path: Option<String>,
    fetch_error: Option<String>,
    running_version: String,
    self_update_supported: bool,
    cli: PackageVersion,
    companion: PackageVersion,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct UpdateRunResult {
    exit_code: i32,
    output: String,
    restart_required: bool,
}

fn formula_version(document: &Value) -> PackageVersion {
    let formula = &document["formulae"][0];
    let installed = formula["linked_keg"]
        .as_str()
        .map(str::to_owned)
        .or_else(|| {
            formula["installed"]
                .as_array()
                .and_then(|kegs| kegs.last())
                .and_then(|keg| keg["version"].as_str())
                .map(str::to_owned)
        });
    PackageVersion {
        outdated: installed.is_some() && formula["outdated"] == true,
        installed,
        latest: formula["versions"]["stable"].as_str().map(str::to_owned),
    }
}

fn cask_version(document: &Value) -> PackageVersion {
    let cask = &document["casks"][0];
    let installed = cask["installed"].as_str().map(str::to_owned);
    PackageVersion {
        outdated: installed.is_some() && cask["outdated"] == true,
        installed,
        latest: cask["version"].as_str().map(str::to_owned),
    }
}

fn brew_info(brew: &Path, kind: &str, name: &str) -> Option<Value> {
    let result = execute(
        brew,
        &["info", "--json=v2", kind, name],
        Duration::from_secs(60),
        Arc::new(|_| {}),
    )
    .ok()?;
    if result.exit_code != 0 {
        return None;
    }
    serde_json::from_str(&result.stdout).ok()
}

fn last_line(text: &str) -> String {
    text.lines()
        .rev()
        .find(|line| !line.trim().is_empty())
        .unwrap_or("Homebrew 정보를 갱신하지 못했습니다.")
        .trim()
        .to_string()
}

fn inspect(fetch: bool, running_version: String) -> Result<UpdateStatus, String> {
    let self_update_supported = !cfg!(debug_assertions);
    let Some(brew) = find_program("brew") else {
        return Ok(UpdateStatus {
            brew_path: None,
            fetch_error: None,
            running_version,
            self_update_supported,
            cli: PackageVersion::default(),
            companion: PackageVersion::default(),
        });
    };
    let fetch_error = if fetch {
        let _guard = begin_action()?;
        let result = execute(
            &brew,
            &["update", "--quiet"],
            FETCH_TIMEOUT,
            Arc::new(|_| {}),
        )?;
        (result.exit_code != 0).then(|| last_line(&format!("{}\n{}", result.stdout, result.stderr)))
    } else {
        None
    };
    Ok(UpdateStatus {
        brew_path: Some(brew.display().to_string()),
        fetch_error,
        running_version,
        self_update_supported,
        cli: brew_info(&brew, "--formula", FORMULA)
            .map(|v| formula_version(&v))
            .unwrap_or_default(),
        companion: brew_info(&brew, "--cask", CASK)
            .map(|v| cask_version(&v))
            .unwrap_or_default(),
    })
}

/// CLI first: a Companion upgrade ends with a restart.
fn ordered_targets(targets: &[UpdateTarget]) -> Vec<UpdateTarget> {
    [UpdateTarget::Cli, UpdateTarget::Companion]
        .into_iter()
        .filter(|target| targets.contains(target))
        .collect()
}

fn upgrade_args(target: UpdateTarget) -> Vec<&'static str> {
    match target {
        UpdateTarget::Cli => vec!["upgrade", "--formula", FORMULA],
        UpdateTarget::Companion => vec!["upgrade", "--cask", CASK],
    }
}

/// Moves the longest decodable prefix out of `pending`, keeping a split
/// multi-byte character for the next read.
fn take_utf8(pending: &mut Vec<u8>) -> String {
    let valid = match std::str::from_utf8(pending) {
        Ok(text) => text.len(),
        Err(error) if error.error_len().is_none() => error.valid_up_to(),
        Err(_) => pending.len(),
    };
    let text = String::from_utf8_lossy(&pending[..valid]).into_owned();
    pending.drain(..valid);
    text
}

fn temp_log_path() -> Result<std::path::PathBuf, String> {
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_nanos();
    Ok(std::env::temp_dir().join(format!(
        "workbranch-companion-update-{}-{stamp}.log",
        std::process::id()
    )))
}

/// Runs Homebrew with output in a file instead of pipes so the upgrade
/// survives the Companion quitting before Homebrew finishes.
fn run_logged(
    bin: &Path,
    args: &[&str],
    timeout: Duration,
    log: Log,
) -> Result<(i32, String), String> {
    let log_path = temp_log_path()?;
    let file = File::create(&log_path).map_err(|e| e.to_string())?;
    let mut command = Command::new(bin);
    command
        .args(args)
        .stdin(Stdio::null())
        .stdout(file.try_clone().map_err(|e| e.to_string())?)
        .stderr(file)
        .env("PATH", path_env()?)
        // The check that offered this update already ran `brew update`.
        .env("HOMEBREW_NO_AUTO_UPDATE", "1")
        .env("HOMEBREW_NO_ENV_HINTS", "1");
    if let Some(home) = std::env::var_os("HOME") {
        command.current_dir(home);
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        command.process_group(0);
    }
    let mut child = command.spawn().map_err(|e| e.to_string())?;
    let mut reader = File::open(&log_path).map_err(|e| e.to_string())?;
    let mut pending = Vec::new();
    let mut output = String::new();
    let drain = |reader: &mut File, pending: &mut Vec<u8>, output: &mut String| {
        let _ = reader.read_to_end(pending);
        let text = take_utf8(pending);
        if !text.is_empty() {
            log(&text);
            output.push_str(&text);
            if output.len() > OUTPUT_LIMIT {
                let mut boundary = output.len() - OUTPUT_LIMIT;
                while !output.is_char_boundary(boundary) {
                    boundary += 1;
                }
                output.drain(..boundary);
            }
        }
    };
    let start = Instant::now();
    let exit_code = loop {
        drain(&mut reader, &mut pending, &mut output);
        if let Some(status) = child.try_wait().map_err(|e| e.to_string())? {
            drain(&mut reader, &mut pending, &mut output);
            break status.code().unwrap_or(1);
        }
        if start.elapsed() > timeout {
            #[cfg(unix)]
            {
                // SAFETY: this is the process group created above for our own child command.
                unsafe {
                    libc::kill(-(child.id() as i32), libc::SIGKILL);
                }
            }
            let _ = child.kill();
            let _ = child.wait();
            drain(&mut reader, &mut pending, &mut output);
            output.push_str("\nOperation timed out. Check `brew outdated` before retrying.");
            break 124;
        }
        std::thread::sleep(Duration::from_millis(100));
    };
    let _ = std::fs::remove_file(&log_path);
    Ok((exit_code, output))
}

#[tauri::command]
pub(crate) async fn update_check(app: AppHandle, fetch: bool) -> Result<UpdateStatus, String> {
    let running_version = app.package_info().version.to_string();
    tauri::async_runtime::spawn_blocking(move || inspect(fetch, running_version))
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
pub(crate) async fn update_apply(
    app: AppHandle,
    targets: Vec<UpdateTarget>,
    operation_id: String,
) -> Result<UpdateRunResult, String> {
    if operation_id.len() > 80 {
        return Err("Invalid operation id".into());
    }
    let targets = ordered_targets(&targets);
    if targets.is_empty() {
        return Err("업데이트할 대상이 없습니다.".into());
    }
    if targets.contains(&UpdateTarget::Companion) && cfg!(debug_assertions) {
        return Err("개발 빌드에서는 Companion을 업데이트할 수 없습니다.".into());
    }
    let guard = begin_action()?;
    tauri::async_runtime::spawn_blocking(move || {
        let _guard = guard;
        let brew =
            find_program("brew").ok_or("Homebrew를 찾지 못했습니다. 설치 경로를 확인하세요.")?;
        let log: Log = Arc::new(move |text| {
            let _ = app.emit(
                "update-progress",
                serde_json::json!({"operationId":operation_id,"text":text}),
            );
        });
        let mut output = String::new();
        for target in targets {
            let (exit_code, text) = run_logged(
                &brew,
                &upgrade_args(target),
                UPGRADE_TIMEOUT,
                Arc::clone(&log),
            )?;
            output.push_str(&text);
            if exit_code != 0 {
                return Ok(UpdateRunResult {
                    exit_code,
                    output,
                    restart_required: false,
                });
            }
            if target == UpdateTarget::Companion {
                return Ok(UpdateRunResult {
                    exit_code,
                    output,
                    restart_required: true,
                });
            }
        }
        Ok(UpdateRunResult {
            exit_code: 0,
            output,
            restart_required: false,
        })
    })
    .await
    .map_err(|e| e.to_string())?
}

/// Homebrew does not quit the app it runs inside, so it replaces the bundle
/// under the running Companion; restart onto the new binary at the same path.
#[tauri::command]
pub(crate) fn relaunch_companion(app: AppHandle) {
    app.restart();
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn formula_version_reads_linked_keg_and_stable() {
        let info = json!({"formulae":[{
            "versions":{"stable":"2.26.0"},
            "installed":[{"version":"2.24.0"},{"version":"2.25.1"}],
            "linked_keg":"2.25.1",
            "outdated":true
        }],"casks":[]});
        assert_eq!(
            formula_version(&info),
            PackageVersion {
                installed: Some("2.25.1".into()),
                latest: Some("2.26.0".into()),
                outdated: true,
            }
        );
    }

    #[test]
    fn missing_packages_are_never_outdated() {
        let formula = json!({"formulae":[{
            "versions":{"stable":"2.26.0"},"installed":[],"linked_keg":null,"outdated":true
        }]});
        let cask = json!({"casks":[{"version":"2.24.0","installed":null,"outdated":true}]});
        assert!(!formula_version(&formula).outdated);
        assert_eq!(cask_version(&cask).latest.as_deref(), Some("2.24.0"));
        assert!(!cask_version(&cask).outdated);
        assert_eq!(formula_version(&json!({})), PackageVersion::default());
    }

    #[test]
    fn cask_version_reads_installed_and_latest() {
        let info = json!({"formulae":[],"casks":[{
            "version":"2.24.0","installed":"2.23.0","outdated":true
        }]});
        assert_eq!(
            cask_version(&info),
            PackageVersion {
                installed: Some("2.23.0".into()),
                latest: Some("2.24.0".into()),
                outdated: true,
            }
        );
    }

    #[test]
    fn upgrades_only_target_workbranch_packages_cli_first() {
        assert_eq!(
            ordered_targets(&[
                UpdateTarget::Companion,
                UpdateTarget::Cli,
                UpdateTarget::Companion
            ]),
            vec![UpdateTarget::Cli, UpdateTarget::Companion]
        );
        assert_eq!(
            upgrade_args(UpdateTarget::Cli),
            vec!["upgrade", "--formula", "tkhwang/tap/workbranch"]
        );
        assert_eq!(
            upgrade_args(UpdateTarget::Companion),
            vec!["upgrade", "--cask", "tkhwang/tap/workbranch-companion"]
        );
        assert!(serde_json::from_value::<UpdateTarget>(json!("brew; rm")).is_err());
    }

    #[test]
    fn take_utf8_keeps_split_characters_for_the_next_read() {
        let mut pending = "🍺 done".as_bytes()[..2].to_vec();
        assert_eq!(take_utf8(&mut pending), "");
        pending.extend_from_slice(&"🍺 done".as_bytes()[2..]);
        assert_eq!(take_utf8(&mut pending), "🍺 done");
        assert!(pending.is_empty());
    }

    #[test]
    #[cfg(unix)]
    fn logged_runner_streams_file_output_and_exit_code() -> Result<(), String> {
        let lines = Arc::new(std::sync::Mutex::new(String::new()));
        let sink = Arc::clone(&lines);
        let (exit_code, output) = run_logged(
            Path::new("/bin/sh"),
            &[
                "-c",
                "echo out; echo err >&2; [ \"$HOMEBREW_NO_AUTO_UPDATE\" = 1 ]",
            ],
            Duration::from_secs(10),
            Arc::new(move |text| {
                if let Ok(mut lines) = sink.lock() {
                    lines.push_str(text);
                }
            }),
        )?;
        assert_eq!(exit_code, 0);
        assert!(output.contains("out\n") && output.contains("err\n"));
        assert_eq!(*lines.lock().map_err(|e| e.to_string())?, output);
        Ok(())
    }

    #[test]
    #[cfg(unix)]
    fn logged_runner_times_out() -> Result<(), String> {
        let started = Instant::now();
        let (exit_code, _) = run_logged(
            Path::new("/bin/sh"),
            &["-c", "sleep 30"],
            Duration::from_millis(100),
            Arc::new(|_| {}),
        )?;
        assert_eq!(exit_code, 124);
        assert!(started.elapsed() < Duration::from_secs(3));
        Ok(())
    }
}
