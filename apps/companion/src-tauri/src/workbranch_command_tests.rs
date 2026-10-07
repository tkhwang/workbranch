use super::*;

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
printf '%s' '{"schemaVersion":2,"projects":[],"errors":[]}'
"#,
    )?;

    let raw = workbranch_list_global_with_config_home(Some(&config_home))?;

    assert_eq!(raw, r#"{"schemaVersion":2,"projects":[],"errors":[]}"#);
    Ok(())
}

#[test]
#[cfg(unix)]
fn global_list_preserves_structured_stdout_on_nonzero_exit()
-> Result<(), Box<dyn std::error::Error>> {
    let structured =
        r#"{"schemaVersion":2,"projects":[],"errors":[{"root":"/missing","message":"missing"}]}"#;
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
