use super::*;

#[test]
fn memo_clear_uses_task_before_clear_flag() {
    let command = CompanionCommand::MemoClear {
        task: "login".to_string(),
    };
    let args = workbranch_args_for(&command);

    assert_eq!(args, Some(vec!["memo", "login", "--clear"]));
}

#[test]
#[cfg(unix)]
fn workbranch_runner_passes_gui_safe_path() -> Result<(), Box<dyn std::error::Error>> {
    use std::ffi::OsStr;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::time::{SystemTime, UNIX_EPOCH};

    let stamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
    let temp_dir = std::env::temp_dir().join(format!("workbranch-path-runner-{stamp}"));
    let fake_bin = temp_dir.join("workbranch");
    fs::create_dir_all(&temp_dir)?;
    fs::write(
        &fake_bin,
        r#"#!/bin/sh
printf '%s' "$PATH"
"#,
    )?;
    let mut permissions = fs::metadata(&fake_bin)?.permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(&fake_bin, permissions)?;

    let result = run_workbranch(&fake_bin, &["ide", "login"], &temp_dir)?;
    let parts = std::env::split_paths(OsStr::new(&result.stdout)).collect::<Vec<PathBuf>>();

    assert_eq!(result.exit_code, 0);
    assert_eq!(parts.first(), Some(&PathBuf::from("/opt/homebrew/bin")));
    assert_eq!(parts.get(1), Some(&PathBuf::from("/usr/local/bin")));
    if let Some(home) = std::env::var_os("HOME").map(PathBuf::from) {
        assert_eq!(parts.get(2), Some(&home.join(".local/bin")));
    }
    Ok(())
}

#[test]
#[cfg(unix)]
fn global_list_runs_configured_workbranch_bin() -> Result<(), Box<dyn std::error::Error>> {
    let config_home = configured_workbranch_script(
        r#"[ "$1 $2 $3" = "list --global --json" ] || exit 42
printf '%s' '{"schemaVersion":1,"projects":[],"errors":[]}'
"#,
    )?;

    let raw = workbranch_list_global_with_config_home(Some(&config_home))?;

    assert_eq!(raw, r#"{"schemaVersion":1,"projects":[],"errors":[]}"#);
    Ok(())
}

#[test]
#[cfg(unix)]
fn global_list_preserves_structured_stdout_on_nonzero_exit()
-> Result<(), Box<dyn std::error::Error>> {
    let structured =
        r#"{"schemaVersion":1,"projects":[],"errors":[{"root":"/missing","message":"missing"}]}"#;
    let config_home = configured_workbranch_script(&format!(
        "printf '%s' '{}'
printf '%s' 'root failed' >&2
exit 1
",
        structured
    ))?;

    let raw = workbranch_list_global_with_config_home(Some(&config_home))?;

    assert_eq!(raw, structured);
    Ok(())
}

#[cfg(unix)]
fn configured_workbranch_script(script: &str) -> Result<PathBuf, Box<dyn std::error::Error>> {
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::time::{SystemTime, UNIX_EPOCH};

    let stamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
    let config_home = std::env::temp_dir().join(format!("workbranch-global-list-{stamp}"));
    let registry_dir = config_home.join("workbranch-companion");
    let configured_bin = config_home.join("custom-workbranch");
    fs::create_dir_all(&registry_dir)?;
    fs::write(
        &configured_bin,
        format!(
            "#!/bin/sh
{script}"
        ),
    )?;
    let mut permissions = fs::metadata(&configured_bin)?.permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(&configured_bin, permissions)?;
    fs::write(
        registry_dir.join("projects.md"),
        format!(
            "# workbranch companion projects

workbranchBin: {}

## projects
",
            configured_bin.display()
        ),
    )?;
    Ok(config_home)
}

#[test]
fn activity_store_appends_jsonl_lines() -> Result<(), Box<dyn std::error::Error>> {
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    let stamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
    let temp_dir = std::env::temp_dir().join(format!("workbranch-activity-store-{stamp}"));
    let log_path = temp_dir.join("workbranch/activity.jsonl");
    let event = activity_store::ActivityEvent {
        v: 1,
        edited_at: 20,
        observed_at: 100,
        root: "/tmp/workbranch".to_string(),
        project: "workbranch".to_string(),
        task: "feat-login".to_string(),
        plan: "Backend".to_string(),
        plan_index: 0,
        plan_title: "Backend".to_string(),
        plan_status: "in-progress".to_string(),
        status: "in-progress".to_string(),
        task_progress_done: 1,
        task_progress_total: 2,
        progress_done: 1,
        progress_total: 2,
        items: Some(vec![activity_store::ChecklistItem {
            text: "Run verification".to_string(),
            checked: false,
            depth: 1,
        }]),
    };

    activity_store::append_activity_events_to_path(&log_path, &[event])?;

    let raw = fs::read_to_string(log_path)?;
    assert_eq!(raw.lines().count(), 1);
    assert!(raw.contains(r#""editedAt":20"#));
    assert!(raw.contains(r#""items":[{"text":"Run verification""#));
    Ok(())
}
