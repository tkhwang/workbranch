use std::fs;
use std::path::{Path, PathBuf};

use crate::CompanionError;

pub(crate) fn resolve_workbranch_bin(
    config_home: Option<&Path>,
) -> Result<PathBuf, CompanionError> {
    let configured = configured_workbranch_bin(config_home)?;
    locate_workbranch(configured.as_deref())
}

fn configured_workbranch_bin(config_home: Option<&Path>) -> Result<Option<String>, CompanionError> {
    let Some(registry_path) = registry_path(config_home) else {
        return Ok(None);
    };
    if !registry_path.is_file() {
        return Ok(None);
    }
    let contents = fs::read_to_string(registry_path)?;
    Ok(parse_workbranch_bin(&contents))
}

fn registry_path(config_home: Option<&Path>) -> Option<PathBuf> {
    let base = match config_home {
        Some(path) => Some(path.to_path_buf()),
        None => std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".config"))),
    }?;
    Some(base.join("workbranch-companion/projects.md"))
}

fn parse_workbranch_bin(contents: &str) -> Option<String> {
    contents.lines().find_map(|line| {
        let value = line.trim_start().strip_prefix("workbranchBin:")?.trim();
        if value.is_empty() {
            None
        } else {
            Some(value.to_string())
        }
    })
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

#[cfg(test)]
mod tests {
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::*;

    #[test]
    fn locate_workbranch_finds_local_cli_when_available() {
        let found = locate_workbranch(None);
        assert!(found.is_ok(), "expected local workbranch binary: {found:?}");
    }

    #[test]
    fn resolve_workbranch_bin_prefers_registry_override() -> Result<(), Box<dyn std::error::Error>>
    {
        let stamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
        let config_home = std::env::temp_dir().join(format!("workbranch-companion-bin-{stamp}"));
        let registry_dir = config_home.join("workbranch-companion");
        let configured_bin = config_home.join("custom-workbranch");
        fs::create_dir_all(&registry_dir)?;
        fs::write(&configured_bin, "")?;
        fs::write(
            registry_dir.join("projects.md"),
            format!(
                "# workbranch companion projects\n\nworkbranchBin: {}\n\n## projects\n",
                configured_bin.display()
            ),
        )?;

        let resolved = resolve_workbranch_bin(Some(&config_home))?;

        assert_eq!(resolved, configured_bin);
        Ok(())
    }
}
