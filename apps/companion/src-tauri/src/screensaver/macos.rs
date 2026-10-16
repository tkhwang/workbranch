//! The macOS side of the screensaver, through typed objc2 bindings.

use std::ffi::{CStr, c_void};
use std::ptr::NonNull;
use std::sync::Arc;
use std::time::Duration;

use block2::RcBlock;
use objc2::rc::Retained;
use objc2::runtime::ProtocolObject;
use objc2_app_kit::{
    NSApplicationDidChangeScreenParametersNotification, NSScreenSaverWindowLevel, NSWindow,
    NSWindowCollectionBehavior,
};
use objc2_core_foundation::{CFBoolean, CFDictionary, CFRetained, CFString, CFType};
use objc2_core_graphics::{
    CGEventSource, CGEventSourceStateID, CGEventType, CGSessionCopyCurrentDictionary,
};
use objc2_foundation::{
    NSActivityOptions, NSDistributedNotificationCenter, NSNotification, NSNotificationCenter,
    NSObjectProtocol, NSProcessInfo, NSString,
};
use tauri::menu::Menu;
use tauri::{AppHandle, Runtime, WebviewWindow};

use super::platform::Platform;
use super::windows::{self, Mode};

const AWAKE_REASON: &str = "Workbranch agents are working";
/// `kCGAnyInputEventType` (~0); the bindings have no name for it.
const ANY_INPUT_EVENT: CGEventType = CGEventType(u32::MAX);

const LOGIN_FRAMEWORK: &CStr =
    c"/System/Library/PrivateFrameworks/login.framework/Versions/Current/login";
const LOCK_SYMBOL: &CStr = c"SACLockScreenImmediate";
/// Set to any value to make the lock probe fail, which exercises the
/// no-lock path (COMP001 R7) on a Mac that has the lock.
const NO_LOCK_ENV: &str = "WORKBRANCH_SCREENSAVER_NO_LOCK";

/// `SACLockScreenImmediate` from the private login framework: the lock that
/// Ctrl-Cmd-Q triggers, without the Accessibility permission a synthetic
/// key press would need. Private, so it is probed rather than linked.
#[derive(Clone, Copy)]
pub(crate) struct ScreenLock(extern "C" fn() -> i32);

impl ScreenLock {
    pub(crate) fn probe() -> Option<Self> {
        if std::env::var_os(NO_LOCK_ENV).is_some() {
            return None;
        }
        // SAFETY: a valid C path; the handle stays open for the process's life
        // because the function pointer below must stay valid.
        let handle = unsafe { libc::dlopen(LOGIN_FRAMEWORK.as_ptr(), libc::RTLD_LAZY) };
        if handle.is_null() {
            return None;
        }
        // SAFETY: a live handle and a valid C symbol name.
        let symbol = unsafe { libc::dlsym(handle, LOCK_SYMBOL.as_ptr()) };
        if symbol.is_null() {
            return None;
        }
        // SAFETY: SACLockScreenImmediate takes no arguments and returns an
        // int status, matching this signature.
        let lock = unsafe { std::mem::transmute::<*mut c_void, extern "C" fn() -> i32>(symbol) };
        Some(Self(lock))
    }

    fn lock(self) {
        let _status = (self.0)();
    }
}

pub(crate) struct MacPlatform<R: Runtime> {
    app: AppHandle<R>,
    activity: Option<Retained<ProtocolObject<dyn NSObjectProtocol>>>,
    lock: Option<ScreenLock>,
    /// The app menu, set aside while a dashboard covers the screen.
    menu: Option<Menu<R>>,
}

impl<R: Runtime> MacPlatform<R> {
    pub(crate) fn new(app: AppHandle<R>, lock: Option<ScreenLock>) -> Self {
        Self {
            app,
            activity: None,
            lock,
            menu: None,
        }
    }
}

impl<R: Runtime> Platform for MacPlatform<R> {
    fn set_awake(&mut self, awake: bool) {
        match (awake, self.activity.take()) {
            (true, None) => {
                // UserInitiated keeps the system awake and the app out of App
                // Nap; IdleDisplaySleepDisabled keeps the display on, which
                // also holds off the macOS screen saver.
                let options =
                    NSActivityOptions::UserInitiated | NSActivityOptions::IdleDisplaySleepDisabled;
                let reason = NSString::from_str(AWAKE_REASON);
                self.activity = Some(
                    NSProcessInfo::processInfo().beginActivityWithOptions_reason(options, &reason),
                );
            }
            (false, Some(activity)) => end_activity(&activity),
            (_, held) => self.activity = held,
        }
    }

    fn idle_time(&self) -> Duration {
        // The HID state counts hardware input only, so windows this app
        // opens never look like the user coming back.
        let seconds = CGEventSource::seconds_since_last_event_type(
            CGEventSourceStateID::HIDSystemState,
            ANY_INPUT_EVENT,
        );
        Duration::try_from_secs_f64(seconds).unwrap_or(Duration::ZERO)
    }

    fn screen_locked(&self) -> bool {
        screen_locked()
    }

    fn show_dashboard(&mut self, mode: Mode) {
        // The app has no main menu while the dashboard covers the screen.
        // Its key equivalents (Cmd-Q quit, Cmd-H hide, Cmd-M minimize, Cmd-W
        // close) act before the next input sample, so they could take the
        // cover down, or the whole app, without the Mac ever locking.
        if self.menu.is_none() {
            self.menu = self.app.remove_menu().ok().flatten();
        }
        windows::show(&self.app, mode, raise);
    }

    fn hide_dashboard(&mut self) {
        windows::hide(&self.app);
        if let Some(menu) = self.menu.take() {
            let _ = self.app.set_menu(menu);
        }
    }

    fn lock_screen(&mut self) {
        if let Some(lock) = self.lock {
            lock.lock();
        }
    }
}

impl<R: Runtime> Drop for MacPlatform<R> {
    fn drop(&mut self) {
        if let Some(activity) = self.activity.take() {
            end_activity(&activity);
        }
    }
}

fn end_activity(activity: &ProtocolObject<dyn NSObjectProtocol>) {
    // SAFETY: every activity this module holds came from
    // beginActivityWithOptions:reason: on the shared process info.
    unsafe { NSProcessInfo::processInfo().endActivity(activity) };
}

/// Whether the login session's screen is locked right now.
fn screen_locked() -> bool {
    let Some(session) = CGSessionCopyCurrentDictionary() else {
        return false;
    };
    // SAFETY: the session dictionary maps CFString keys to CF values.
    let session: CFRetained<CFDictionary<CFString, CFType>> =
        unsafe { CFRetained::cast_unchecked(session) };
    session
        .get(&CFString::from_static_str("CGSSessionScreenIsLocked"))
        .and_then(|value| value.downcast::<CFBoolean>().ok())
        .is_some_and(|locked| locked.as_bool())
}

/// Calls `on_change(locked)` whenever the screen locks or unlocks.
pub(crate) fn watch_screen_lock<R: Runtime>(
    app: &AppHandle<R>,
    on_change: impl Fn(bool) + Send + Sync + 'static,
) {
    let on_change = Arc::new(on_change);
    let _ = app.run_on_main_thread(move || {
        let center = NSDistributedNotificationCenter::defaultCenter();
        for (name, locked) in [
            ("com.apple.screenIsLocked", true),
            ("com.apple.screenIsUnlocked", false),
        ] {
            let on_change = Arc::clone(&on_change);
            let block = RcBlock::new(move |_: NonNull<NSNotification>| on_change(locked));
            let name = NSString::from_str(name);
            // SAFETY: no sender object is matched, and a nil queue runs the
            // block on the posting thread; the block only forwards a bool
            // through a thread-safe callback.
            let _observer = unsafe {
                center.addObserverForName_object_queue_usingBlock(Some(&name), None, None, &block)
            };
            // The center keeps the observer registered for the app's life;
            // nothing ever removes it, so the token is not stored.
        }
    });
}

/// Lifts a dashboard window above the menu bar, the Dock and full-screen
/// apps on every Space, and gives the focused one the keyboard.
fn raise<R: Runtime>(window: WebviewWindow<R>, focus: bool) {
    let target = window.clone();
    let _ = window.run_on_main_thread(move || {
        let Ok(pointer) = target.ns_window() else {
            return;
        };
        // SAFETY: Tauri hands out the live NSWindow behind this window, and
        // this closure runs on the main thread that owns it.
        let ns_window = unsafe { &*pointer.cast::<NSWindow>() };
        ns_window.setLevel(NSScreenSaverWindowLevel);
        ns_window.setCollectionBehavior(
            NSWindowCollectionBehavior::CanJoinAllSpaces
                | NSWindowCollectionBehavior::FullScreenAuxiliary
                | NSWindowCollectionBehavior::Stationary
                | NSWindowCollectionBehavior::IgnoresCycle,
        );
        if focus {
            // Activates the app and makes this the key window.
            let _ = target.set_focus();
        }
    });
}

/// Calls `on_change` whenever displays are added, removed or rearranged.
pub(crate) fn watch_displays<R: Runtime>(
    app: &AppHandle<R>,
    on_change: impl Fn() + Send + Sync + 'static,
) {
    let _ = app.run_on_main_thread(move || {
        let block = RcBlock::new(move |_: NonNull<NSNotification>| on_change());
        // SAFETY: AppKit posts this notification on the main thread with the
        // application as sender; no sender object is matched, and the block
        // only calls a thread-safe callback.
        let _observer = unsafe {
            NSNotificationCenter::defaultCenter().addObserverForName_object_queue_usingBlock(
                Some(NSApplicationDidChangeScreenParametersNotification),
                None,
                None,
                &block,
            )
        };
        // Registered for the app's life, like the lock observers above.
    });
}
