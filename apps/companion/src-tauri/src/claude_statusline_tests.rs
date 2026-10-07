use super::*;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_TEMP_DIR: AtomicU64 = AtomicU64::new(0);

/// The data directory has a space, like `Application Support` on macOS.
fn temp_paths() -> Result<RelayPaths, Box<dyn std::error::Error>> {
    let suffix = NEXT_TEMP_DIR.fetch_add(1, Ordering::Relaxed);
    let root = std::env::temp_dir().join(format!(
        "wb-statusline-test-{}-{suffix}",
        std::process::id()
    ));
    let _ = fs::remove_dir_all(&root);
    fs::create_dir_all(root.join(".claude"))?;
    Ok(RelayPaths {
        settings: root.join(".claude/settings.json"),
        data_dir: root.join("App Support/companion"),
    })
}

fn settings(paths: &RelayPaths) -> Result<Value, Box<dyn std::error::Error>> {
    Ok(serde_json::from_slice(&fs::read(&paths.settings)?)?)
}

fn run_command(command: &str, input: &str) -> Result<String, Box<dyn std::error::Error>> {
    let mut child = Command::new("/bin/sh")
        .args(["-c", command])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()?;
    child
        .stdin
        .take()
        .ok_or("stdin")?
        .write_all(input.as_bytes())?;
    let output = child.wait_with_output()?;
    assert!(output.status.success());
    Ok(String::from_utf8(output.stdout)?)
}

#[test]
fn relay_wraps_the_previous_status_line_and_restores_it() -> Result<(), Box<dyn std::error::Error>>
{
    let paths = temp_paths()?;
    fs::write(
        &paths.settings,
        r#"{"model":"opus","statusLine":{"type":"command","command":"cat >/dev/null; printf 'mine'","padding":1},"hooks":{}}"#,
    )?;

    let status = enable(&paths)?;
    assert!(status.enabled);
    assert_eq!(
        status.previous_command.as_deref(),
        Some("cat >/dev/null; printf 'mine'")
    );
    let wrapped = settings(&paths)?;
    let command = wrapped["statusLine"]["command"].as_str().ok_or("command")?;
    assert_eq!(wrapped["statusLine"]["padding"], 1);
    let keys: Vec<&String> = wrapped.as_object().ok_or("object")?.keys().collect();
    assert_eq!(keys, ["model", "statusLine", "hooks"]);

    // Input without rate_limits still renders but is not captured.
    assert_eq!(run_command(command, r#"{"model":{}}"#)?, "mine");
    assert!(!paths.data_dir.join(CAPTURE_NAME).exists());
    let input = r#"{"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1791400000}}}"#;
    assert_eq!(run_command(command, input)?, "mine");
    assert_eq!(
        fs::read_to_string(paths.data_dir.join(CAPTURE_NAME))?,
        input
    );

    // Enabling twice keeps the original command, not the wrapper.
    enable(&paths)?;
    let status = disable(&paths)?;
    assert!(!status.enabled);
    assert_eq!(
        settings(&paths)?["statusLine"],
        serde_json::json!({"type":"command","command":"cat >/dev/null; printf 'mine'","padding":1})
    );
    assert!(!paths.data_dir.join(CAPTURE_NAME).exists());
    assert!(!paths.data_dir.join(WRAPPER_NAME).exists());
    Ok(())
}

#[test]
fn relay_without_a_status_line_prints_nothing_and_removes_its_entry()
-> Result<(), Box<dyn std::error::Error>> {
    let paths = temp_paths()?;

    let status = enable(&paths)?;
    assert_eq!(
        status,
        RelayStatus {
            enabled: true,
            previous_command: None
        }
    );
    let command = settings(&paths)?["statusLine"]["command"]
        .as_str()
        .ok_or("command")?
        .to_owned();
    assert_eq!(run_command(&command, r#"{"rate_limits":{}}"#)?, "");
    assert!(paths.data_dir.join(CAPTURE_NAME).exists());

    disable(&paths)?;
    assert_eq!(settings(&paths)?, serde_json::json!({}));
    Ok(())
}

#[test]
fn disabling_leaves_a_status_line_the_user_replaced() -> Result<(), Box<dyn std::error::Error>> {
    let paths = temp_paths()?;
    fs::write(
        &paths.settings,
        r#"{"statusLine":{"type":"command","command":"old"}}"#,
    )?;
    enable(&paths)?;
    fs::write(
        &paths.settings,
        r#"{"statusLine":{"type":"command","command":"new"}}"#,
    )?;

    let status = disable(&paths)?;
    assert_eq!(
        status,
        RelayStatus {
            enabled: false,
            previous_command: Some("new".to_string())
        }
    );
    assert_eq!(settings(&paths)?["statusLine"]["command"], "new");
    Ok(())
}

#[test]
fn invalid_settings_are_never_overwritten() -> Result<(), Box<dyn std::error::Error>> {
    let paths = temp_paths()?;
    fs::write(&paths.settings, "{ not json")?;
    assert!(enable(&paths).is_err());
    assert_eq!(fs::read_to_string(&paths.settings)?, "{ not json");
    Ok(())
}

#[test]
fn shell_quote_survives_single_quotes() {
    assert_eq!(shell_quote("/a b/it's"), r"'/a b/it'\''s'");
}
