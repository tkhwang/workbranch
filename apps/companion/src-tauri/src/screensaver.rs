//! Keeps the Mac awake while agents work and shows the dashboard over the
//! macOS screen saver and lock screen (COMP001, COMP002). `machine` decides,
//! `platform` acts; this module feeds the machine from the runtime service,
//! the preference store, screen-lock and screen-saver notifications and
//! readings of the session, on one thread.

mod machine;
#[cfg(target_os = "macos")]
mod macos;
mod platform;
mod windows;

use std::sync::Mutex;
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::time::{Duration, Instant};

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
    /// macOS said the screen locked or unlocked; the session is read for
    /// the state itself.
    LockChanged,
    /// The macOS screen saver started or stopped.
    Saver(bool),
    DisplaysChanged,
    Preview,
}

pub(crate) struct Screensaver {
    /// Wakes the screensaver thread, e.g. right after Settings changes.
    wake: Mutex<Sender<Message>>,
    /// Whether the dashboard can lock the Mac (COMP001 R7).
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
        macos::watch_screen_lock(app, move || {
            if let Ok(sender) = on_lock.lock() {
                let _ = sender.send(Message::LockChanged);
            }
        });
        let on_saver = Mutex::new(sender.clone());
        macos::watch_screen_saver(app, move |running| {
            if let Ok(sender) = on_saver.lock() {
                let _ = sender.send(Message::Saver(running));
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
    // Readings carry time on a monotonic clock, for how long a cover may
    // last with no agent at work.
    let started = Instant::now();

    let first = sample(&platform, started);
    apply(&mut platform, &machine.step(first));
    apply(
        &mut platform,
        &machine.step(Event::Config(read_config(app))),
    );

    // When the session is read next. Messages in between never push it back,
    // so runtime snapshots arriving faster than the poll (agents at work)
    // cannot starve the readings.
    let mut due: Option<Instant> = None;
    loop {
        // Idle time has no notification, and the lock notification can come
        // late or stray, so the session is read on a timer, only while the
        // machine could act on it.
        let message = match machine.poll_interval() {
            Some(interval) => {
                let now = Instant::now();
                let deadline = due.map_or(now + interval, |due| due.min(now + interval));
                due = Some(deadline);
                match messages.recv_timeout(deadline.saturating_duration_since(now)) {
                    Ok(message) => Some(message),
                    Err(RecvTimeoutError::Timeout) => None,
                    Err(RecvTimeoutError::Disconnected) => return,
                }
            }
            None => {
                due = None;
                match messages.recv() {
                    Ok(message) => Some(message),
                    Err(_) => return,
                }
            }
        };
        let event = match message {
            Some(Message::Runtime(snapshot)) => match snapshot.document.as_deref() {
                Some(document) => Event::Working(is_working(document)),
                // A failed read says nothing new about the agents.
                None => Event::Unreadable(Duration::from_millis(snapshot.read_at_ms)),
            },
            Some(Message::ConfigChanged) => Event::Config(read_config(app)),
            Some(Message::LockChanged) | None => sample(&platform, started),
            // Where the session can be asked, it is the truth.
            Some(Message::Saver(running)) => match platform.screen_saver_running() {
                Some(_) => sample(&platform, started),
                None => Event::Saver(running),
            },
            Some(Message::Preview) => Event::Preview,
            Some(Message::DisplaysChanged) => {
                // A display came, went or moved, or macOS re-announced the
                // screens (it does on every brightness ramp of an XDR
                // display): line the windows up with the displays, which
                // leaves them alone when the layout is the same.
                if machine.previewing() {
                    platform.show_dashboard(Mode::Preview);
                } else if machine.showing() {
                    platform.show_dashboard(Mode::Live);
                }
                continue;
            }
        };
        if matches!(event, Event::Sample { .. }) {
            // This turn read the session; the next reading is a full
            // interval away.
            due = None;
        }
        apply(&mut platform, &machine.step(event));
    }
}

fn sample(platform: &impl Platform, started: Instant) -> Event {
    Event::Sample {
        at: started.elapsed(),
        idle: platform.idle_time(),
        locked: platform.screen_locked(),
        saver: platform.screen_saver_running(),
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

/// Lets the dashboard tell whether it shows over a locked Mac (COMP001 R7).
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
