use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use tauri::{AppHandle, Emitter};

use crate::CompanionError;
use crate::watch_filter::{IGNORED_COMPONENTS, event_has_relevant_change};

pub(crate) fn build_watchers(
    app: AppHandle,
    roots: &[String],
) -> Result<Vec<RecommendedWatcher>, CompanionError> {
    let debounce = Arc::new(Mutex::new(HashMap::<String, Instant>::new()));
    let mut next_watchers = Vec::with_capacity(roots.len());

    for root in roots {
        let root_path = PathBuf::from(root);
        let root_label = root.clone();
        let app_handle = app.clone();
        let debounce_state = Arc::clone(&debounce);
        let mut watcher =
            notify::recommended_watcher(move |event: notify::Result<notify::Event>| {
                let Ok(event) = event else {
                    return;
                };
                if !event_has_relevant_change(&event.paths, IGNORED_COMPONENTS) {
                    return;
                }
                if should_emit_root_change(&debounce_state, &root_label) {
                    let _ = app_handle.emit("roots-changed", root_label.clone());
                }
            })?;
        watcher.watch(&root_path, RecursiveMode::Recursive)?;
        next_watchers.push(watcher);
        app.emit("roots-changed", root)
            .map_err(std::io::Error::other)?;
    }

    Ok(next_watchers)
}

fn should_emit_root_change(debounce: &Arc<Mutex<HashMap<String, Instant>>>, root: &str) -> bool {
    const DEBOUNCE_WINDOW: Duration = Duration::from_millis(500);
    let now = Instant::now();
    let Ok(mut last_by_root) = debounce.lock() else {
        return true;
    };
    if let Some(last) = last_by_root.get(root)
        && now.duration_since(*last) < DEBOUNCE_WINDOW
    {
        return false;
    }
    last_by_root.insert(root.to_string(), now);
    true
}
