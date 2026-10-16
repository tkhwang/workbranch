//! The one place companion reads agent runtime state.
//!
//! Hook collectors write `state.sqlite3` in the runtime directory. This
//! service watches that directory, reads `workbranch runtime --json` once the
//! store settles, and fans the result out: every window gets the
//! `runtime-snapshot` event, in-process consumers subscribe. A slow fallback
//! read catches sessions that turn stale without any write, and any change
//! the watcher missed. The SQLite file itself stays the collector's private
//! storage; the schema'd CLI document is the contract.

use std::ffi::OsString;
use std::path::PathBuf;
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use serde::Serialize;
use tauri::{AppHandle, Emitter, Runtime, State};

use crate::workbranch_bin::resolve_workbranch_bin;

pub(crate) const SNAPSHOT_EVENT: &str = "runtime-snapshot";
/// Quiet time after the last write before reading: one hook event touches the
/// store several times in a row.
const DEBOUNCE: Duration = Duration::from_millis(200);
/// How long a steady stream of writes may postpone a read.
const MAX_DELAY: Duration = Duration::from_secs(1);
/// Sessions turn stale with no write at all, and a watcher can miss events.
const FALLBACK_INTERVAL: Duration = Duration::from_secs(60);

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct RuntimeSnapshot {
    pub(crate) sequence: u64,
    pub(crate) read_at_ms: u64,
    /// The `workbranch runtime --json` document. The webview validates it
    /// against the contract, as it validates every CLI document.
    pub(crate) document: Option<String>,
    pub(crate) error: Option<String>,
}

fn snapshot_from(
    sequence: u64,
    read_at_ms: u64,
    result: Result<String, String>,
) -> RuntimeSnapshot {
    let (document, error) = match result {
        Ok(document) => (Some(document), None),
        Err(error) => (None, Some(error)),
    };
    RuntimeSnapshot {
        sequence,
        read_at_ms,
        document,
        error,
    }
}

/// When the next read is due, given the last read and pending changes.
#[derive(Clone, Copy, Debug, Default)]
struct Schedule {
    last_read: Option<Instant>,
    first_change: Option<Instant>,
    last_change: Option<Instant>,
}

impl Schedule {
    fn change(&mut self, now: Instant) {
        self.first_change.get_or_insert(now);
        self.last_change = Some(now);
    }

    fn read_done(&mut self, now: Instant) {
        *self = Self {
            last_read: Some(now),
            first_change: None,
            last_change: None,
        };
    }

    fn due(&self, now: Instant) -> Instant {
        let Some(last_read) = self.last_read else {
            return now;
        };
        let fallback = last_read + FALLBACK_INTERVAL;
        match (self.first_change, self.last_change) {
            (Some(first), Some(last)) => (last + DEBOUNCE).min(first + MAX_DELAY).min(fallback),
            _ => fallback,
        }
    }
}

/// Keeps the latest snapshot and fans each new one out to subscribers.
#[derive(Default)]
struct Hub {
    latest: Mutex<Option<RuntimeSnapshot>>,
    subscribers: Mutex<Vec<Sender<RuntimeSnapshot>>>,
}

impl Hub {
    fn latest(&self) -> Option<RuntimeSnapshot> {
        self.latest.lock().ok().and_then(|latest| latest.clone())
    }

    /// The receiver starts with the latest snapshot, if any. Holding the
    /// subscriber lock across both steps means no publish slips between them.
    fn subscribe(&self) -> Receiver<RuntimeSnapshot> {
        let (sender, receiver) = mpsc::channel();
        if let Ok(mut subscribers) = self.subscribers.lock() {
            if let Some(latest) = self.latest() {
                let _ = sender.send(latest);
            }
            subscribers.push(sender);
        }
        receiver
    }

    fn publish(&self, snapshot: &RuntimeSnapshot) {
        if let Ok(mut latest) = self.latest.lock() {
            *latest = Some(snapshot.clone());
        }
        if let Ok(mut subscribers) = self.subscribers.lock() {
            subscribers.retain(|subscriber| subscriber.send(snapshot.clone()).is_ok());
        }
    }

    #[cfg(test)]
    fn subscriber_count(&self) -> usize {
        self.subscribers
            .lock()
            .map_or(0, |subscribers| subscribers.len())
    }
}

pub(crate) struct RuntimeService {
    hub: Arc<Hub>,
}

impl RuntimeService {
    /// Snapshots as they are read, starting with the latest one.
    pub(crate) fn subscribe(&self) -> Receiver<RuntimeSnapshot> {
        self.hub.subscribe()
    }
}

pub(crate) fn start<R: Runtime>(app: &AppHandle<R>) -> RuntimeService {
    let hub = Arc::new(Hub::default());

    // Webviews are one more subscriber of the same fan-out.
    let to_webviews = hub.subscribe();
    let app = app.clone();
    std::thread::spawn(move || {
        for snapshot in to_webviews {
            let _ = app.emit(SNAPSHOT_EVENT, &snapshot);
        }
    });

    let (wake, changes) = mpsc::channel();
    let reader_hub = Arc::clone(&hub);
    std::thread::spawn(move || {
        run(&wake, &changes, read_runtime, |snapshot| {
            reader_hub.publish(&snapshot);
        });
    });

    RuntimeService { hub }
}

fn run(
    wake: &Sender<()>,
    changes: &Receiver<()>,
    read: impl Fn() -> Result<String, String>,
    publish: impl Fn(RuntimeSnapshot),
) {
    let mut schedule = Schedule::default();
    let mut watcher: Option<RecommendedWatcher> = None;
    let mut sequence = 0;
    loop {
        let now = Instant::now();
        let due = schedule.due(now);
        if due <= now {
            // The runtime directory appears once the collector is installed,
            // so a failed watch is retried on every read.
            if watcher.is_none() {
                watcher = watch_runtime_dir(wake.clone());
            }
            sequence += 1;
            let snapshot = snapshot_from(sequence, epoch_ms(), read());
            schedule.read_done(Instant::now());
            publish(snapshot);
            continue;
        }
        match changes.recv_timeout(due - now) {
            Ok(()) => schedule.change(Instant::now()),
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => return,
        }
    }
}

/// Mirrors `runtime_dir()` in apps/agent-runtime/src/main.rs.
fn runtime_dir(override_dir: Option<OsString>, home: Option<OsString>) -> Option<PathBuf> {
    if let Some(dir) = override_dir.filter(|dir| !dir.is_empty()) {
        return Some(PathBuf::from(dir));
    }
    home.filter(|home| !home.is_empty())
        .map(|home| PathBuf::from(home).join(".workbranch/runtime"))
}

fn watch_runtime_dir(wake: Sender<()>) -> Option<RecommendedWatcher> {
    let dir = runtime_dir(
        std::env::var_os("WORKBRANCH_RUNTIME_DIR"),
        std::env::var_os("HOME"),
    )?;
    // FSEvents watches by path, so this watch outlives the directory being
    // removed and recreated (companion ships for macOS only). A port to a
    // backend that watches by inode, such as inotify, must re-add it.
    let mut watcher = notify::recommended_watcher(move |event: notify::Result<notify::Event>| {
        if event.is_ok() {
            let _ = wake.send(());
        }
    })
    .ok()?;
    watcher.watch(&dir, RecursiveMode::NonRecursive).ok()?;
    Some(watcher)
}

fn read_runtime() -> Result<String, String> {
    let bin = resolve_workbranch_bin(None).map_err(|error| error.to_string())?;
    let cwd = std::env::var_os("HOME").map_or_else(|| PathBuf::from("/"), PathBuf::from);
    crate::run_workbranch_stdout(&bin, &["runtime", "--json"], &cwd)
        .map_err(|error| error.to_string())
}

fn epoch_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| {
            u64::try_from(elapsed.as_millis()).unwrap_or(u64::MAX)
        })
}

/// The latest snapshot for a window that opens after it was pushed.
#[tauri::command]
pub(crate) fn runtime_snapshot(service: State<'_, RuntimeService>) -> Option<RuntimeSnapshot> {
    service.hub.latest()
}

#[cfg(test)]
#[path = "runtime_service_tests.rs"]
mod tests;
