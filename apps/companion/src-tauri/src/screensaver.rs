//! Keeps the Mac awake while agents work (COMP001). `machine` decides,
//! `platform` acts; this module feeds the machine from the runtime service,
//! the preference store and screen-lock notifications, on one thread.

mod machine;
#[cfg(target_os = "macos")]
mod macos;
mod platform;
mod windows;

use std::sync::Mutex;
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::time::Duration;

use tauri::{AppHandle, Runtime, State};
use tauri_plugin_store::StoreExt;

use crate::menu_bar::PREFERENCES_STORE_FILE;
use crate::runtime_service::{RuntimeService, RuntimeSnapshot};
use machine::{Config, Event, Machine, is_working};
use platform::{Platform, apply};
use windows::Mode;

const CONFIG_KEY: &str = "screensaver";

enum Message {
    Runtime(RuntimeSnapshot),
    ConfigChanged,
    Locked(bool),
    DisplaysChanged,
    Preview,
}

pub(crate) struct Screensaver {
    /// Wakes the screensaver thread, e.g. right after Settings changes.
    wake: Mutex<Sender<Message>>,
    /// Whether input on the dashboard can lock the Mac (COMP001 R7).
    lock_available: bool,
}

pub(crate) fn start<R: Runtime>(app: &AppHandle<R>, runtime: &RuntimeService) -> Screensaver {
    let (sender, receiver) = mpsc::channel();
    #[cfg(target_os = "macos")]
    let lock = macos::ScreenLock::probe();
    #[cfg(target_os = "macos")]
    let lock_available = lock.is_some();
    #[cfg(not(target_os = "macos"))]
    let lock_available = false;

    let snapshots = runtime.subscribe();
    let forward = sender.clone();
    std::thread::spawn(move || {
        for snapshot in snapshots {
            if forward.send(Message::Runtime(snapshot)).is_err() {
                return;
            }
        }
    });

    #[cfg(target_os = "macos")]
    {
        let on_lock = Mutex::new(sender.clone());
        macos::watch_screen_lock(app, move |locked| {
            if let Ok(sender) = on_lock.lock() {
                let _ = sender.send(Message::Locked(locked));
            }
        });
        let on_displays = Mutex::new(sender.clone());
        macos::watch_displays(app, move || {
            if let Ok(sender) = on_displays.lock() {
                let _ = sender.send(Message::DisplaysChanged);
            }
        });
    }

    let app = app.clone();
    std::thread::spawn(move || {
        // The platform holds an activity token that must stay on this thread.
        #[cfg(target_os = "macos")]
        let platform = macos::MacPlatform::new(app.clone(), lock);
        #[cfg(not(target_os = "macos"))]
        let platform = platform::NoopPlatform;
        run(&app, &receiver, platform, lock_available);
    });
    Screensaver {
        wake: Mutex::new(sender),
        lock_available,
    }
}

fn run<R: Runtime>(
    app: &AppHandle<R>,
    messages: &Receiver<Message>,
    mut platform: impl Platform,
    lock_available: bool,
) {
    let mut machine = Machine::new(lock_available);

    let locked = platform.screen_locked();
    apply(&mut platform, &machine.step(Event::Locked(locked)));
    apply(
        &mut platform,
        &machine.step(Event::Config(read_config(app))),
    );

    loop {
        // Idle time has no notification, so it is sampled, and only while
        // the machine could act on it. While a lock is awaited, the lock
        // state is sampled instead, since its notification can come late.
        let message = match machine.poll_interval() {
            Some(interval) => match messages.recv_timeout(interval) {
                Ok(message) => Some(message),
                Err(RecvTimeoutError::Timeout) => None,
                Err(RecvTimeoutError::Disconnected) => return,
            },
            None => match messages.recv() {
                Ok(message) => Some(message),
                Err(_) => return,
            },
        };
        let event = match message {
            Some(Message::Runtime(snapshot)) => match snapshot.document.as_deref() {
                Some(document) => Event::Working(is_working(document)),
                // A failed read says nothing new about the agents.
                None => Event::Unreadable(Duration::from_millis(snapshot.read_at_ms)),
            },
            Some(Message::ConfigChanged) => Event::Config(read_config(app)),
            Some(Message::Locked(locked)) => Event::Locked(locked),
            Some(Message::Preview) => Event::Preview,
            Some(Message::DisplaysChanged) => {
                // A display came or went: rebuild the windows to match.
                if machine.previewing() {
                    platform.show_dashboard(Mode::Preview);
                } else if machine.showing() {
                    platform.show_dashboard(Mode::Live);
                }
                continue;
            }
            None if machine.awaiting_lock() => Event::LockSample(platform.screen_locked()),
            None => Event::Idle(platform.idle_time()),
        };
        apply(&mut platform, &machine.step(event));
    }
}

fn read_config<R: Runtime>(app: &AppHandle<R>) -> Config {
    app.store(PREFERENCES_STORE_FILE).map_or_else(
        |_| Config::default(),
        |store| Config::from_store_value(store.get(CONFIG_KEY)),
    )
}

/// Re-reads the `screensaver` preference after Settings saved it.
#[tauri::command]
pub(crate) fn screensaver_refresh(screensaver: State<'_, Screensaver>) {
    if let Ok(sender) = screensaver.wake.lock() {
        let _ = sender.send(Message::ConfigChanged);
    }
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ScreensaverStatus {
    lock_available: bool,
}

/// Lets the dashboard tell whether input will lock the Mac (COMP001 R7).
#[tauri::command]
pub(crate) fn screensaver_status(screensaver: State<'_, Screensaver>) -> ScreensaverStatus {
    ScreensaverStatus {
        lock_available: screensaver.lock_available,
    }
}

/// Shows the dashboard now, as a preview that input only closes (COMP001 R12).
#[tauri::command]
pub(crate) fn screensaver_preview(screensaver: State<'_, Screensaver>) {
    if let Ok(sender) = screensaver.wake.lock() {
        let _ = sender.send(Message::Preview);
    }
}
