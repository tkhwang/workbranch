use std::env::JoinPathsError;
use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};

const GUI_PREPEND_BINS: &[&str] = &["/opt/homebrew/bin", "/usr/local/bin"];

pub(crate) fn gui_safe_path(
    inherited: Option<&OsStr>,
    home: Option<&Path>,
) -> Result<OsString, JoinPathsError> {
    let mut paths = Vec::new();
    paths.extend(GUI_PREPEND_BINS.iter().map(PathBuf::from));
    if let Some(home_path) = home {
        paths.push(home_path.join(".local/bin"));
    }
    if let Some(inherited_path) = inherited {
        paths.extend(std::env::split_paths(inherited_path));
    }
    std::env::join_paths(paths)
}

#[cfg(test)]
mod tests {
    use std::ffi::OsStr;
    use std::path::{Path, PathBuf};

    use super::*;

    #[test]
    fn gui_safe_path_prepends_common_bins_before_sparse_gui_path()
    -> Result<(), Box<dyn std::error::Error>> {
        let path = gui_safe_path(
            Some(OsStr::new("/usr/bin:/bin")),
            Some(Path::new("/Users/example")),
        )?;
        let parts = std::env::split_paths(&path).collect::<Vec<PathBuf>>();

        assert_eq!(
            parts,
            vec![
                PathBuf::from("/opt/homebrew/bin"),
                PathBuf::from("/usr/local/bin"),
                PathBuf::from("/Users/example/.local/bin"),
                PathBuf::from("/usr/bin"),
                PathBuf::from("/bin"),
            ],
        );
        Ok(())
    }
}
