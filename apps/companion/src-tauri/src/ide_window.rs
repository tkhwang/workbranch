//! Moves the window an IDE opens onto the screen the companion is on.
//!
//! Zed opens a window where that project's window last was, or else where
//! the last window was, often on another display, and none of the supported
//! IDEs can be told which screen to use. So while `workbranch ide` runs, the
//! companion notes every window that already exists, then moves each window
//! one of these IDEs opens afterwards onto the companion's screen through
//! the Accessibility API. A window the IDE only brings forward stays where
//! it is. The `ideWindow` switch in Settings turns this on, and Settings
//! asks for the Accessibility permission; until both are on, the IDEs place
//! their windows themselves.

#[cfg(target_os = "macos")]
mod macos;

use std::collections::HashSet;
use std::sync::mpsc::{Receiver, TryRecvError};
use std::time::{Duration, Instant};

use tauri::{Runtime, WebviewWindow};
use tauri_plugin_store::StoreExt;

use crate::menu_bar::PREFERENCES_STORE_FILE;

/// The preference key Settings saves the switch under
/// (`src/application/ideWindow.ts` holds the same shape).
const CONFIG_KEY: &str = "ideWindow";
/// The Accessibility list in System Settings.
#[cfg(target_os = "macos")]
const ACCESS_SETTINGS_URL: &str =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility";

/// Bundle identifiers of the IDEs whose new windows follow the companion's
/// screen: Zed, VS Code, Cursor and Antigravity IDE, with the preview
/// channels of Zed and VS Code.
pub(crate) const IDE_BUNDLE_IDS: [&str; 6] = [
    "dev.zed.Zed",
    "dev.zed.Zed-Preview",
    "com.microsoft.VSCode",
    "com.microsoft.VSCodeInsiders",
    // Cursor
    "com.todesktop.230313mzl4w4u92",
    "com.google.antigravity-ide",
];

/// How long after `workbranch ide` finishes a new window is still awaited:
/// long enough for an IDE that was not running to start.
const WAIT_FOR_FIRST: Duration = Duration::from_secs(10);
/// Once a new window arrived and the command finished, how long to wait for
/// the windows of a task's other repos.
const WAIT_FOR_MORE: Duration = Duration::from_secs(3);
/// Stops following even if the command never finishes.
const MAX_FOLLOW: Duration = Duration::from_secs(120);
const POLL: Duration = Duration::from_millis(100);

/// A rectangle in global screen points, with the origin at the top-left of
/// the main display: the space both CoreGraphics and the Accessibility API
/// use.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Frame {
    pub(crate) x: f64,
    pub(crate) y: f64,
    pub(crate) width: f64,
    pub(crate) height: f64,
}

impl Frame {
    fn contains(&self, x: f64, y: f64) -> bool {
        x >= self.x && x < self.x + self.width && y >= self.y && y < self.y + self.height
    }
}

/// The screen new IDE windows move to, or `None` while the Settings switch
/// is off or the Accessibility permission is missing.
pub(crate) fn screen_to_follow<R: Runtime>(window: &WebviewWindow<R>) -> Option<Frame> {
    let switched_on = window
        .store(PREFERENCES_STORE_FILE)
        .is_ok_and(|store| enabled_in_store_value(store.get(CONFIG_KEY).as_ref()));
    (switched_on && access_granted())
        .then(|| companion_screen(window))
        .flatten()
}

/// Reads the switch the way `sanitizeIdeWindowConfig()` does: anything but
/// `{ "enabled": true }` is off.
pub(crate) fn enabled_in_store_value(value: Option<&serde_json::Value>) -> bool {
    value
        .and_then(|value| value.get("enabled"))
        .and_then(serde_json::Value::as_bool)
        .unwrap_or_default()
}

/// The usable area, without the menu bar and the Dock, of the monitor the
/// companion window is on.
fn companion_screen<R: Runtime>(window: &WebviewWindow<R>) -> Option<Frame> {
    let monitor = window.current_monitor().ok().flatten()?;
    let area = monitor.work_area();
    screen_frame(
        area.position.x,
        area.position.y,
        area.size.width,
        area.size.height,
        monitor.scale_factor(),
    )
}

/// Tauri reports a monitor's area in points multiplied by that monitor's
/// scale factor, so dividing by the factor gives the points back.
pub(crate) fn screen_frame(x: i32, y: i32, width: u32, height: u32, scale: f64) -> Option<Frame> {
    (scale > 0.0 && width > 0 && height > 0).then(|| Frame {
        x: f64::from(x) / scale,
        y: f64::from(y) / scale,
        width: f64::from(width) / scale,
        height: f64::from(height) / scale,
    })
}

/// Where a window goes on `screen`: nowhere when its center is already on
/// that screen, else centered there at its own size, shrunk to fit.
pub(crate) fn placement(window: Frame, screen: Frame) -> Option<Frame> {
    if screen.contains(
        window.x + window.width / 2.0,
        window.y + window.height / 2.0,
    ) {
        return None;
    }
    let width = window.width.min(screen.width);
    let height = window.height.min(screen.height);
    Some(Frame {
        x: (screen.x + (screen.width - width) / 2.0).round(),
        y: (screen.y + (screen.height - height) / 2.0).round(),
        width,
        height,
    })
}

/// An IDE window the OS can move right now.
pub(crate) struct OpenWindow<H> {
    /// The CoreGraphics window number, stable for the window's life.
    pub(crate) id: u32,
    pub(crate) frame: Frame,
    pub(crate) handle: H,
}

/// What following asks of the OS. The macOS implementation lives in
/// `macos.rs`; tests use a fake.
pub(crate) trait Desktop {
    type Handle;
    /// The supported IDEs' standard windows that can be moved now, so not
    /// minimized or full screen.
    fn ide_windows(&self) -> Vec<OpenWindow<Self::Handle>>;
    fn move_window(&self, handle: &Self::Handle, frame: Frame);
}

/// Moves each IDE window that did not exist when the command started onto
/// the companion's screen, once, so the user can move it away again.
pub(crate) struct Follower {
    screen: Frame,
    /// Window numbers that existed before the command, or were handled.
    seen: HashSet<u32>,
}

impl Follower {
    pub(crate) fn new(screen: Frame, existing: HashSet<u32>) -> Self {
        Self {
            screen,
            seen: existing,
        }
    }

    /// One look at the IDE windows; returns how many were new.
    pub(crate) fn step(&mut self, desktop: &impl Desktop) -> usize {
        let mut new_windows = 0;
        for window in desktop.ide_windows() {
            if !self.seen.insert(window.id) {
                continue;
            }
            new_windows += 1;
            if let Some(frame) = placement(window.frame, self.screen) {
                desktop.move_window(&window.handle, frame);
            }
        }
        new_windows
    }
}

/// Whether to keep looking for new windows, given the time since the
/// command finished (`None` while it runs) and since the last new window
/// (`None` before the first). A window can open before the command ends,
/// so the quiet time counts from whichever came later.
pub(crate) fn keep_following(
    since_finished: Option<Duration>,
    since_new_window: Option<Duration>,
) -> bool {
    let Some(since_finished) = since_finished else {
        return true;
    };
    since_finished < WAIT_FOR_FIRST
        && since_new_window.is_none_or(|since_new| since_new.min(since_finished) < WAIT_FOR_MORE)
}

/// Looks for new IDE windows until `keep_following` says to stop. The
/// command counts as finished once `command_running` disconnects.
pub(crate) fn run(desktop: &impl Desktop, mut follower: Follower, command_running: &Receiver<()>) {
    let started = Instant::now();
    let mut finished_at = None;
    let mut new_window_at = None;
    loop {
        if finished_at.is_none()
            && matches!(command_running.try_recv(), Err(TryRecvError::Disconnected))
        {
            finished_at = Some(Instant::now());
        }
        if follower.step(desktop) > 0 {
            new_window_at = Some(Instant::now());
        }
        let now = Instant::now();
        let since = |at: Instant| now.duration_since(at);
        if since(started) >= MAX_FOLLOW
            || !keep_following(finished_at.map(since), new_window_at.map(since))
        {
            return;
        }
        std::thread::sleep(POLL);
    }
}

/// Follows one `workbranch ide` run. Take it right before the command and
/// drop it once the command returns: dropping it starts the wait for
/// windows that open late.
pub(crate) struct Following {
    #[cfg(target_os = "macos")]
    _command_running: std::sync::mpsc::Sender<()>,
}

/// Notes the windows that exist now, then moves the new IDE windows onto
/// `screen` from a background thread.
#[cfg(target_os = "macos")]
pub(crate) fn follow(screen: Frame) -> Following {
    Following {
        _command_running: macos::follow(screen),
    }
}

#[cfg(not(target_os = "macos"))]
pub(crate) fn follow(_screen: Frame) -> Following {
    Following {}
}

/// Whether macOS lets the companion move other apps' windows.
#[cfg(target_os = "macos")]
fn access_granted() -> bool {
    macos::access_granted()
}

#[cfg(not(target_os = "macos"))]
fn access_granted() -> bool {
    false
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct IdeWindowAccess {
    granted: bool,
}

/// Lets Settings show whether the Accessibility permission is granted. It
/// can change in System Settings at any time, so Settings asks again each
/// time it opens.
#[tauri::command]
pub(crate) fn ide_window_access() -> IdeWindowAccess {
    IdeWindowAccess {
        granted: access_granted(),
    }
}

/// Shows macOS's prompt for the Accessibility permission, which also lists
/// the companion in System Settings, unless it is granted already.
#[tauri::command]
pub(crate) fn ide_window_request_access() -> IdeWindowAccess {
    #[cfg(target_os = "macos")]
    let granted = macos::request_access();
    #[cfg(not(target_os = "macos"))]
    let granted = false;
    IdeWindowAccess { granted }
}

/// Opens the Accessibility list in System Settings, where the permission is
/// turned on, or off again.
#[tauri::command]
pub(crate) fn ide_window_open_access_settings() -> Result<(), String> {
    #[cfg(target_os = "macos")]
    let opened = std::process::Command::new("/usr/bin/open")
        .arg(ACCESS_SETTINGS_URL)
        .spawn()
        .map(drop)
        .map_err(|error| format!("failed to open System Settings: {error}"));
    #[cfg(not(target_os = "macos"))]
    let opened = Err("the Accessibility permission exists on macOS only".to_owned());
    opened
}

#[cfg(test)]
#[path = "ide_window_tests.rs"]
mod tests;
