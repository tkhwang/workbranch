use crate::{RunResult, process_env::gui_safe_path, workbranch_bin::resolve_workbranch_bin};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    collections::HashSet,
    ffi::{OsStr, OsString},
    io::Read,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{
        Arc, OnceLock,
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
    time::{Duration, Instant},
};
use tauri::{AppHandle, Emitter};

pub(crate) const FORMULA: &str = "tkhwang/tap/workbranch";
const OUTPUT_LIMIT: usize = 1_048_576;
const SHELL_PATH_MARKER: &str = "__WORKBRANCH_PATH__";
const SHELL_PATH_TIMEOUT: Duration = Duration::from_secs(10);
static ACTION_RUNNING: AtomicBool = AtomicBool::new(false);
pub(crate) type Log = Arc<dyn Fn(&str) + Send + Sync>;
#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum Provider {
    Claude,
    Codex,
    Grok,
}
impl Provider {
    fn name(self) -> &'static str {
        match self {
            Self::Claude => "claude",
            Self::Codex => "codex",
            Self::Grok => "grok",
        }
    }
    fn plugin(self) -> &'static str {
        match self {
            Self::Grok => "workbranch-agent-events-grok",
            _ => "workbranch-agent-events",
        }
    }
}
#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub(crate) enum SetupAction {
    InstallCli,
    UpdateCli,
    RepairCli,
    ConnectAgent {
        provider: Provider,
        #[serde(default, rename = "approvedSource")]
        approved_source: Option<String>,
    },
    DisconnectAgent {
        provider: Provider,
    },
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct CliStatus {
    state: String,
    path: Option<String>,
    version: String,
    message: String,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AgentStatus {
    provider: Provider,
    executable_path: Option<String>,
    install_source: Option<String>,
    state: String,
    last_observed_at: Option<u64>,
    message: String,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SetupStatus {
    brew_path: Option<String>,
    formula_installed: Option<bool>,
    cli: CliStatus,
    agents: Vec<AgentStatus>,
}
pub(crate) fn path_env() -> Result<OsString, String> {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    let base = gui_safe_path(std::env::var_os("PATH").as_deref(), home.as_deref())
        .map_err(|e| e.to_string())?;
    let mut paths = std::env::split_paths(&base).collect::<Vec<_>>();
    // Agents installed through version managers (nvm, bun, pnpm, ...) are only
    // on the shell profile's PATH, which a Finder or login-item launch never
    // inherits. Appended so existing brew/CLI lookups keep their order.
    if let Some(profile) = login_shell_path() {
        paths.extend(std::env::split_paths(profile));
    }
    if let Some(home) = home {
        paths.push(home.join(".grok/bin"));
    }
    let mut seen = HashSet::new();
    paths.retain(|path| seen.insert(path.clone()));
    std::env::join_paths(paths).map_err(|e| e.to_string())
}
/// The interactive login shell's PATH, resolved once per launch. A slow or
/// broken profile falls back to the GUI-safe PATH.
fn login_shell_path() -> Option<&'static OsStr> {
    static PROFILE_PATH: OnceLock<Option<OsString>> = OnceLock::new();
    PROFILE_PATH
        .get_or_init(|| {
            // Tests must not depend on the developer's shell profile.
            if cfg!(test) {
                return None;
            }
            let shell = PathBuf::from(std::env::var_os("SHELL")?);
            shell_profile_path(&shell, SHELL_PATH_TIMEOUT)
        })
        .as_deref()
}
fn shell_profile_path(shell: &Path, timeout: Duration) -> Option<OsString> {
    if !shell.is_absolute() || !executable(shell) {
        return None;
    }
    // printenv reports PATH as child processes see it, whatever list syntax
    // the shell uses; the markers skip anything the profile prints.
    let script =
        format!("echo {SHELL_PATH_MARKER}; /usr/bin/printenv PATH; echo {SHELL_PATH_MARKER}");
    let mut command = Command::new(shell);
    command
        .args(["-ilc", &script])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    if let Some(home) = std::env::var_os("HOME") {
        command.current_dir(home);
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        // SAFETY: setsid is async-signal-safe. The new session keeps an
        // interactive profile off any controlling terminal, as on a Finder
        // launch, and leads the process group the deadline kills.
        unsafe {
            command.pre_exec(|| {
                if libc::setsid() == -1 {
                    return Err(std::io::Error::last_os_error());
                }
                Ok(())
            });
        }
    }
    let deadline = Instant::now() + timeout;
    let mut child = command.spawn().ok()?;
    let mut stdout = child.stdout.take()?;
    let (sender, receiver) = mpsc::channel();
    // A daemon started by the profile can hold the pipe open forever, so the
    // reader stops at the closing marker and the deadline never waits on it.
    std::thread::spawn(move || {
        let mut output = Vec::new();
        let mut buf = [0u8; 4096];
        loop {
            match stdout.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    output.extend_from_slice(&buf[..n]);
                    let markers = String::from_utf8_lossy(&output)
                        .matches(SHELL_PATH_MARKER)
                        .count();
                    if markers >= 2 || output.len() > OUTPUT_LIMIT {
                        break;
                    }
                }
            }
        }
        let _ = sender.send(output);
    });
    let output = receiver.recv_timeout(timeout).ok();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(25)),
            _ => {
                #[cfg(unix)]
                {
                    // SAFETY: setsid above made the child lead its own process group.
                    unsafe {
                        libc::kill(-(child.id() as i32), libc::SIGKILL);
                    }
                }
                let _ = child.kill();
                let _ = child.wait();
                break;
            }
        }
    }
    marked_path(&String::from_utf8_lossy(&output?))
}
fn marked_path(output: &str) -> Option<OsString> {
    let mut sections = output.split(SHELL_PATH_MARKER);
    sections.next()?;
    let value = sections.next()?;
    sections.next()?;
    let paths = std::env::split_paths(value.trim())
        .filter(|path| path.is_absolute())
        .collect::<Vec<_>>();
    if paths.is_empty() {
        return None;
    }
    std::env::join_paths(paths).ok()
}
fn executable(path: &Path) -> bool {
    if !path.is_file() {
        return false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::metadata(path)
            .map(|m| m.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
    }
    #[cfg(not(unix))]
    {
        true
    }
}
pub(crate) fn find_program(name: &str) -> Option<PathBuf> {
    std::env::split_paths(&path_env().ok()?)
        .map(|p| p.join(name))
        .find(|p| executable(p))
}
fn reader(mut pipe: impl Read + Send + 'static, log: Log) -> std::thread::JoinHandle<String> {
    std::thread::spawn(move || {
        let mut result = String::new();
        let mut buf = [0u8; 4096];
        loop {
            match pipe.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    let text = String::from_utf8_lossy(&buf[..n]);
                    log(&text);
                    result.push_str(&text);
                    if result.len() > OUTPUT_LIMIT {
                        let mut boundary = result.len() - OUTPUT_LIMIT;
                        while !result.is_char_boundary(boundary) {
                            boundary += 1;
                        }
                        result.drain(..boundary);
                    }
                }
            }
        }
        result
    })
}
pub(crate) fn execute(
    bin: &Path,
    args: &[&str],
    timeout: Duration,
    log: Log,
) -> Result<RunResult, String> {
    let mut command = Command::new(bin);
    command
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .env("PATH", path_env()?);
    if let Some(home) = std::env::var_os("HOME") {
        command.current_dir(home);
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        command.process_group(0);
    }
    let mut child = command.spawn().map_err(|e| e.to_string())?;
    let stdout = reader(
        child.stdout.take().ok_or("Missing stdout pipe")?,
        Arc::clone(&log),
    );
    let stderr = reader(child.stderr.take().ok_or("Missing stderr pipe")?, log);
    let start = Instant::now();
    let mut timed_out = false;
    let status = loop {
        if let Some(status) = child.try_wait().map_err(|e| e.to_string())?
            && stdout.is_finished()
            && stderr.is_finished()
        {
            break status;
        }
        if start.elapsed() > timeout {
            timed_out = true;
            #[cfg(unix)]
            {
                // SAFETY: this is the process group created above for our own child command.
                unsafe {
                    libc::kill(-(child.id() as i32), libc::SIGKILL);
                }
            }
            let _ = child.kill();
            break child.wait().map_err(|e| e.to_string())?;
        }
        std::thread::sleep(Duration::from_millis(25));
    };
    let out = stdout.join().map_err(|_| "stdout reader failed")?;
    let mut err = stderr.join().map_err(|_| "stderr reader failed")?;
    if timed_out {
        err.push_str("\nOperation timed out. Check installation status before retrying.");
    }
    Ok(RunResult {
        exit_code: if timed_out {
            124
        } else {
            status.code().unwrap_or(1)
        },
        stdout: out,
        stderr: err,
    })
}
fn query(bin: &Path, args: &[&str]) -> Result<RunResult, String> {
    execute(bin, args, Duration::from_secs(15), Arc::new(|_| {}))
}
fn json_query(bin: &Path, args: &[&str]) -> Result<Value, String> {
    let output = query(bin, args)?;
    if output.exit_code != 0 {
        return Err("Command unavailable or failed".into());
    }
    serde_json::from_str(&output.stdout).map_err(|_| "Invalid command response".into())
}
fn compatible(caps: &Value, snapshot: &Value) -> bool {
    caps["listSchemaVersion"] == 2
        && caps["runtimeSchemaVersion"] == 1
        && snapshot["schemaVersion"] == 1
        && snapshot["sessions"].is_array()
}
fn plugin_state(provider: Provider, value: &Value) -> &'static str {
    let rows = value
        .as_array()
        .or_else(|| value.get("installed").and_then(Value::as_array));
    let Some(rows) = rows else {
        return "unknown";
    };
    for row in rows {
        let name = row
            .get("id")
            .or_else(|| row.get("pluginId"))
            .or_else(|| row.get("name"))
            .and_then(Value::as_str)
            .unwrap_or("");
        if name.split('@').next() != Some(provider.plugin()) {
            continue;
        }
        if row.get("installed") == Some(&Value::Bool(false)) {
            continue;
        }
        if row.get("enabled") == Some(&Value::Bool(false)) || row["status"] == "disabled" {
            return "disabled";
        }
        if row.get("trusted") == Some(&Value::Bool(false)) || row["status"] == "untrusted" {
            return "trustRequired";
        }
        return "configured";
    }
    "disconnected"
}
fn probe() -> SetupStatus {
    let brew = find_program("brew");
    let formula_installed = brew
        .as_ref()
        .and_then(|bin| query(bin, &["list", "--formula", "--versions", FORMULA]).ok())
        .and_then(|r| match r.exit_code {
            0 => Some(!r.stdout.trim().is_empty()),
            1 => Some(false),
            _ => None,
        });
    let cli = resolve_workbranch_bin(None).ok();
    let mut status = CliStatus {
        state: "missing".into(),
        path: cli.as_ref().map(|p| p.display().to_string()),
        version: String::new(),
        message: "Workbranch CLI를 설치하세요.".into(),
    };
    let mut snapshot = Value::Null;
    let mut supports_grok_trust = false;
    if let Some(bin) = &cli {
        status.version = query(bin, &["version"])
            .ok()
            .filter(|r| r.exit_code == 0)
            .map(|r| r.stdout.trim().to_string())
            .unwrap_or_default();
        let caps = json_query(bin, &["capabilities", "--json"]).unwrap_or(Value::Null);
        supports_grok_trust = caps["grokTrustConfirmation"] == true;
        if caps["listSchemaVersion"] == 2 && caps["runtimeSchemaVersion"] == 1 {
            snapshot = json_query(bin, &["runtime", "--json"]).unwrap_or(Value::Null);
            if compatible(&caps, &snapshot) {
                status.state = "ready".into();
                status.message = "CLI와 수집기를 사용할 수 있습니다.".into();
            } else {
                status.state = "runtimeUnavailable".into();
                status.message =
                    "수집기를 확인하지 못했습니다. 설치 복구 후 다시 확인하세요.".into();
            }
        } else {
            status.state = "incompatible".into();
            status.message = "이 Companion과 호환되는 CLI로 업데이트하세요.".into();
        }
    }
    let agents = [Provider::Claude, Provider::Codex, Provider::Grok]
        .into_iter()
        .map(|provider| {
            let bin = find_program(provider.name());
            let state = match &bin {
                None => "notInstalled",
                Some(bin) => json_query(bin, &["plugin", "list", "--json"])
                    .map(|v| plugin_state(provider, &v))
                    .unwrap_or("unknown"),
            };
            let last = snapshot
                .get("sessions")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
                .filter(|s| s["provider"] == provider.name())
                .filter_map(|s| s["updatedAt"].as_u64())
                .max();
            let message = match state {
                "notInstalled" => "Agent 프로그램을 먼저 설치하세요.",
                "disconnected" => "Workbranch hook을 연결하세요.",
                "disabled" => "Plugin이 비활성화되어 있습니다.",
                "trustRequired" => "Agent에서 hook 신뢰 승인이 필요합니다.",
                "configured" => "설정됨. Agent를 재시작하고 native hook 신뢰 상태를 확인하세요.",
                _ => "연결 상태를 확인하지 못했습니다. Agent의 plugin 목록을 확인하세요.",
            };
            let install_source = if matches!(provider, Provider::Grok) && supports_grok_trust {
                cli.as_ref()
                    .and_then(|bin| {
                        json_query(bin, &["hooks", "describe", "--provider", "grok"]).ok()
                    })
                    .and_then(|v| v.get("source").and_then(Value::as_str).map(str::to_owned))
            } else {
                None
            };
            AgentStatus {
                provider,
                install_source,
                executable_path: bin.map(|p| p.display().to_string()),
                state: state.into(),
                last_observed_at: last,
                message: message.into(),
            }
        })
        .collect();
    SetupStatus {
        brew_path: brew.map(|p| p.display().to_string()),
        formula_installed,
        cli: status,
        agents,
    }
}
fn brew_args(action: &SetupAction) -> Option<Vec<&'static str>> {
    match action {
        SetupAction::InstallCli => Some(vec!["install", FORMULA]),
        SetupAction::UpdateCli => Some(vec!["upgrade", FORMULA]),
        SetupAction::RepairCli => Some(vec!["reinstall", FORMULA]),
        _ => None,
    }
}
fn hook_arguments(
    verb: &str,
    provider: Provider,
    approved: Option<&str>,
    source: Option<&str>,
) -> Result<Vec<String>, String> {
    let mut args = vec![
        "hooks".into(),
        verb.into(),
        "--provider".into(),
        provider.name().into(),
    ];
    if let Some(approved) = approved {
        if !matches!(provider, Provider::Grok)
            || verb != "install"
            || approved.is_empty()
            || source != Some(approved)
        {
            return Err("승인한 plugin 대상이 변경됐습니다. 다시 확인하세요.".into());
        }
        args.extend([
            "--trust".into(),
            "--expected-source".into(),
            approved.into(),
        ]);
    }
    Ok(args)
}
pub(crate) struct ActionGuard(());
impl Drop for ActionGuard {
    fn drop(&mut self) {
        ACTION_RUNNING.store(false, Ordering::Release);
    }
}
/// Serializes every Homebrew or hook mutation the Companion starts.
pub(crate) fn begin_action() -> Result<ActionGuard, String> {
    ACTION_RUNNING
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .map(|_| ActionGuard(()))
        .map_err(|_| "다른 설치 또는 연결 작업이 진행 중입니다.".into())
}
#[tauri::command]
pub(crate) async fn setup_status() -> Result<SetupStatus, String> {
    tauri::async_runtime::spawn_blocking(probe)
        .await
        .map_err(|e| e.to_string())
}
#[tauri::command]
pub(crate) async fn setup_action(
    app: AppHandle,
    action: SetupAction,
    operation_id: String,
) -> Result<RunResult, String> {
    if operation_id.len() > 80 {
        return Err("Invalid operation id".into());
    }
    let guard = begin_action()?;
    tauri::async_runtime::spawn_blocking(move || {
        let _guard = guard;
        let log: Log = Arc::new(move |text| {
            let _ = app.emit(
                "setup-progress",
                serde_json::json!({"operationId":operation_id,"text":text}),
            );
        });
        if let Some(args) = brew_args(&action) {
            let brew = find_program("brew")
                .ok_or("Homebrew를 찾지 못했습니다. 설치 경로를 확인하세요.")?;
            let installed = query(&brew, &["list", "--formula", "--versions", FORMULA])
                .map(|r| r.exit_code == 0 && !r.stdout.trim().is_empty())
                .unwrap_or(false);
            let args = if installed {
                args
            } else {
                vec!["install", FORMULA]
            };
            return execute(&brew, &args, Duration::from_secs(1800), log);
        }
        let (verb, provider, approved_source) = match action {
            SetupAction::ConnectAgent {
                provider,
                approved_source,
            } => ("install", provider, approved_source),
            SetupAction::DisconnectAgent { provider } => ("uninstall", provider, None),
            _ => return Err("Unsupported action".into()),
        };
        if find_program(provider.name()).is_none() {
            return Err("Agent 프로그램을 먼저 설치하세요.".into());
        }
        let cli = resolve_workbranch_bin(None).map_err(|e| e.to_string())?;
        let caps = json_query(&cli, &["capabilities", "--json"])?;
        if caps["listSchemaVersion"] != 2
            || !caps["providers"]
                .as_array()
                .is_some_and(|p| p.iter().any(|p| p == provider.name()))
        {
            return Err("CLI를 먼저 업데이트하세요.".into());
        }
        let source = if approved_source.is_some() {
            if caps["grokTrustConfirmation"] != true {
                return Err("CLI를 업데이트한 뒤 Grok 설치를 승인하세요.".into());
            }
            json_query(&cli, &["hooks", "describe", "--provider", "grok"])?
                .get("source")
                .and_then(Value::as_str)
                .map(str::to_owned)
        } else {
            None
        };
        let args = hook_arguments(
            verb,
            provider,
            approved_source.as_deref(),
            source.as_deref(),
        )?;
        let borrowed = args.iter().map(String::as_str).collect::<Vec<_>>();
        execute(&cli, &borrowed, Duration::from_secs(300), log)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn brew_actions_only_target_the_workbranch_formula() {
        assert_eq!(
            brew_args(&SetupAction::InstallCli),
            Some(vec!["install", "tkhwang/tap/workbranch"])
        );
        assert_eq!(
            brew_args(&SetupAction::UpdateCli),
            Some(vec!["upgrade", "tkhwang/tap/workbranch"])
        );
        assert!(
            serde_json::from_value::<SetupAction>(
                json!({"kind":"connectAgent","provider":"shell; rm"})
            )
            .is_err()
        );
    }
    #[test]
    fn compatibility_requires_both_cli_and_runtime_contracts() {
        assert!(!compatible(
            &json!({"listSchemaVersion":1,"runtimeSchemaVersion":1}),
            &json!({"schemaVersion":1,"sessions":[]})
        ));
        assert!(compatible(
            &json!({"listSchemaVersion":2,"runtimeSchemaVersion":1}),
            &json!({"schemaVersion":1,"sessions":[]})
        ));
    }
    #[test]
    fn plugin_inspection_does_not_confuse_available_with_installed() {
        assert_eq!(
            plugin_state(
                Provider::Codex,
                &json!({"installed":[],"available":[{"name":"workbranch-agent-events","installed":false}]})
            ),
            "disconnected"
        );
        assert_eq!(
            plugin_state(
                Provider::Claude,
                &json!([{"id":"workbranch-agent-events@workbranch-runtime","enabled":false}])
            ),
            "disabled"
        );
        assert_eq!(
            plugin_state(
                Provider::Grok,
                &json!([{"name":"workbranch-agent-events-grok","status":"enabled"}])
            ),
            "configured"
        );
    }
}

#[cfg(test)]
mod process_tests {
    use super::*;
    #[test]
    #[cfg(unix)]
    fn bounded_process_runner_times_out_without_waiting_for_children()
    -> Result<(), Box<dyn std::error::Error>> {
        let started = Instant::now();
        let result = execute(
            Path::new("/bin/sh"),
            &["-c", "sleep 30"],
            Duration::from_millis(100),
            Arc::new(|_| {}),
        )?;
        assert_eq!(result.exit_code, 124);
        assert!(started.elapsed() < Duration::from_secs(3));
        Ok(())
    }
}

#[cfg(test)]
mod pipe_deadline_tests {
    use super::*;
    #[test]
    #[cfg(unix)]
    fn exited_parent_does_not_bypass_pipe_deadline() -> Result<(), Box<dyn std::error::Error>> {
        let started = Instant::now();
        let result = execute(
            Path::new("/bin/sh"),
            &["-c", "sleep 2 & exit 0"],
            Duration::from_millis(100),
            Arc::new(|_| {}),
        )?;
        assert_eq!(result.exit_code, 124);
        assert!(started.elapsed() < Duration::from_secs(1));
        Ok(())
    }
}

#[cfg(test)]
mod login_shell_path_tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[cfg(unix)]
    fn fake_shell(body: &str) -> Result<PathBuf, Box<dyn std::error::Error>> {
        use std::os::unix::fs::PermissionsExt;
        let stamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
        let dir = std::env::temp_dir().join(format!("workbranch-login-shell-{stamp}"));
        std::fs::create_dir_all(&dir)?;
        let shell = dir.join("shell");
        std::fs::write(&shell, format!("#!/bin/sh\n{body}\n"))?;
        let mut permissions = std::fs::metadata(&shell)?.permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(&shell, permissions)?;
        Ok(shell)
    }

    #[test]
    fn marked_path_ignores_profile_output_and_relative_entries() {
        let marker = SHELL_PATH_MARKER;
        assert_eq!(
            marked_path(&format!(
                "motd\n{marker}\n/a/bin:relative:/b/bin\n{marker}\nbye\n"
            )),
            Some(OsString::from("/a/bin:/b/bin"))
        );
        assert_eq!(marked_path(&format!("{marker}\n/a/bin\n")), None);
        assert_eq!(marked_path(&format!("{marker}\n\n{marker}\n")), None);
        assert_eq!(marked_path("/a/bin"), None);
    }

    #[test]
    #[cfg(unix)]
    fn profile_path_comes_from_the_shell_script() -> Result<(), Box<dyn std::error::Error>> {
        // Stands in for `$SHELL -ilc <script>`: profile noise, then the script.
        let shell = fake_shell(
            r#"echo "profile noise"; PATH=/profile/bin:/usr/bin:/bin exec /bin/sh -c "$2""#,
        )?;
        assert_eq!(
            shell_profile_path(&shell, Duration::from_secs(5)),
            Some(OsString::from("/profile/bin:/usr/bin:/bin"))
        );
        Ok(())
    }

    #[test]
    #[cfg(unix)]
    fn hanging_profile_falls_back_at_the_deadline() -> Result<(), Box<dyn std::error::Error>> {
        let shell = fake_shell("sleep 30")?;
        let started = Instant::now();
        assert_eq!(shell_profile_path(&shell, Duration::from_millis(200)), None);
        assert!(started.elapsed() < Duration::from_secs(3));
        Ok(())
    }

    #[test]
    #[cfg(unix)]
    fn daemon_holding_the_pipe_does_not_hide_the_path() -> Result<(), Box<dyn std::error::Error>> {
        // The profile leaves a process in another session with stdout open.
        let shell = fake_shell(&format!(
            "perl -e 'use POSIX; POSIX::setsid(); sleep 10' &\n\
             echo {SHELL_PATH_MARKER}; echo /profile/bin; echo {SHELL_PATH_MARKER}"
        ))?;
        let started = Instant::now();
        assert_eq!(
            shell_profile_path(&shell, Duration::from_secs(5)),
            Some(OsString::from("/profile/bin"))
        );
        assert!(started.elapsed() < Duration::from_secs(3));
        Ok(())
    }
}

#[cfg(test)]
mod grok_trust_tests {
 use super::*;
 #[test]
 fn default_connection_has_no_trust_flag() {
  let args=hook_arguments("install",Provider::Grok,None,None).unwrap_or_default();
  assert_eq!(args,vec!["hooks","install","--provider","grok"]);
 }
 #[test]
 fn trusted_install_is_bound_to_the_reviewed_source() -> Result<(),String> {
  let args=hook_arguments("install",Provider::Grok,Some("/reviewed/plugin"),Some("/reviewed/plugin"))?;
  assert_eq!(args,vec!["hooks","install","--provider","grok","--trust","--expected-source","/reviewed/plugin"]);
  assert!(hook_arguments("install",Provider::Grok,Some("/old"),Some("/new")).is_err());
  assert!(hook_arguments("install",Provider::Claude,Some("/reviewed/plugin"),Some("/reviewed/plugin")).is_err());
  Ok(())
 }
}
