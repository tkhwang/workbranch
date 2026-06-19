use std::path::{Path, PathBuf};

pub(crate) const IGNORED_COMPONENTS: &[&str] = &[
    "node_modules",
    "target",
    "dist",
    "build",
    ".next",
    ".turbo",
    ".cache",
];

pub(crate) fn event_has_relevant_change(root: &Path, paths: &[PathBuf], ignored: &[&str]) -> bool {
    paths
        .iter()
        .any(|path| !path_is_ignored(root, path, ignored))
}

pub(crate) fn path_is_ignored(root: &Path, path: &Path, ignored: &[&str]) -> bool {
    let relative_path = match path.strip_prefix(root) {
        Ok(relative_path) => relative_path,
        Err(_) => path,
    };
    relative_path.components().any(|component| {
        let value = component.as_os_str();
        ignored
            .iter()
            .any(|ignored_component| value == *ignored_component)
    })
}

#[cfg(test)]
mod tests {
    use super::{IGNORED_COMPONENTS, event_has_relevant_change};
    use std::path::{Path, PathBuf};

    const ROOT: &str = "/project";

    fn root() -> &'static Path {
        Path::new(ROOT)
    }

    fn paths(values: &[&str]) -> Vec<PathBuf> {
        values.iter().map(PathBuf::from).collect()
    }

    #[test]
    fn ignores_empty_path_events() {
        assert!(!event_has_relevant_change(root(), &[], IGNORED_COMPONENTS));
    }

    #[test]
    fn ignores_noise_only_paths_when_all_components_are_ignored() {
        let event_paths = paths(&[
            "/project/node_modules/pkg/index.js",
            "/project/target/debug/app",
            "/project/.next/cache/file",
        ]);

        assert!(!event_has_relevant_change(
            root(),
            &event_paths,
            IGNORED_COMPONENTS
        ));
    }

    #[test]
    fn keeps_relevant_paths_when_watched_root_parent_is_ignored_name() {
        let root = Path::new("/tmp/target/demo");
        let event_paths = paths(&[
            "/tmp/target/demo/TASK-WORKBRANCH.md",
            "/tmp/target/demo/workbranch/src/lib.rs",
        ]);

        assert!(event_has_relevant_change(
            root,
            &event_paths,
            IGNORED_COMPONENTS
        ));
    }

    #[test]
    fn keeps_task_metadata_and_worktree_source_paths_relevant() {
        let event_paths = paths(&[
            "/project/feat-login/TASK-WORKBRANCH.md",
            "/project/feat-login/frontend/src/App.tsx",
        ]);

        assert!(event_has_relevant_change(
            root(),
            &event_paths,
            IGNORED_COMPONENTS
        ));
    }

    #[test]
    fn keeps_linked_worktree_git_metadata_relevant() {
        let event_paths = paths(&[
            "/project/_base/frontend/.git/worktrees/feat-login-frontend/index",
            "/project/_base/frontend/.git/worktrees/feat-login-frontend/HEAD",
            "/project/_base/frontend/.git/refs/heads/feat-login",
            "/project/_base/frontend/.git/packed-refs",
        ]);

        assert!(event_has_relevant_change(
            root(),
            &event_paths,
            IGNORED_COMPONENTS
        ));
    }

    #[test]
    fn keeps_mixed_noise_and_relevant_paths_relevant() {
        let event_paths = paths(&[
            "/project/node_modules/pkg/index.js",
            "/project/feat-login/TASK-WORKBRANCH.md",
        ]);

        assert!(event_has_relevant_change(
            root(),
            &event_paths,
            IGNORED_COMPONENTS
        ));
    }
}
