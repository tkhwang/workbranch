//! The macOS side of the screensaver, through typed objc2 bindings.

use std::ffi::{CStr, c_void};
use std::ptr::NonNull;
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use block2::RcBlock;
use objc2::rc::Retained;
use objc2::runtime::ProtocolObject;
use objc2_app_kit::{
    NSApplicationDidChangeScreenParametersNotification, NSWindow, NSWindowCollectionBehavior,
};
use objc2_core_foundation::{
    CFArray, CFBoolean, CFDictionary, CFNumber, CFRetained, CFString, CFType,
};
use objc2_core_graphics::{
    CGEventSource, CGEventSourceStateID, CGEventType, CGSessionCopyCurrentDictionary,
};
use objc2_foundation::{
    NSActivityOptions, NSDistributedNotificationCenter, NSNotification, NSNotificationCenter,
    NSObjectProtocol, NSProcessInfo, NSString,
};
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

const SKYLIGHT_FRAMEWORK: &CStr =
    c"/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight";
/// The absolute space level macOS shows notifications at over its lock
/// screen, which sits at 300 (`LUIUnmanagedSpace: level=300` in the
/// loginwindow log). Windows in a space at this level draw above the lock
/// screen and the screen saver.
const OVERLAY_SPACE_LEVEL: i32 = 400;
/// The flags `SLSSpaceCreate` takes for an ordinary user space.
const OVERLAY_SPACE_FLAGS: i32 = 1;
/// The flags other lock-screen overlays pass to
/// `SLSSpaceAddWindowsAndRemoveFromSpaces`: move the windows out of every
/// other space.
const OVERLAY_MOVE_FLAGS: i32 = 7;

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
        // SAFETY: a valid C path and symbol name; the handle stays open for
        // the process's life because the function pointer must stay valid.
        let symbol = unsafe { private_symbol(LOGIN_FRAMEWORK, LOCK_SYMBOL) }?;
        // SAFETY: SACLockScreenImmediate takes no arguments and returns an
        // int status, matching this signature.
        let lock = unsafe { std::mem::transmute::<*mut c_void, extern "C" fn() -> i32>(symbol) };
        Some(Self(lock))
    }

    fn lock(self) {
        let _status = (self.0)();
    }
}

/// Looks up `symbol` in the private framework at `path`.
///
/// # Safety
/// Both strings must name a framework binary and a symbol in it; the
/// framework is never closed, so the returned pointer stays valid.
unsafe fn private_symbol(path: &CStr, symbol: &CStr) -> Option<*mut c_void> {
    // SAFETY: valid C strings, per the caller.
    let handle = unsafe { libc::dlopen(path.as_ptr(), libc::RTLD_LAZY) };
    if handle.is_null() {
        return None;
    }
    // SAFETY: a live handle and a valid C symbol name.
    let symbol = unsafe { libc::dlsym(handle, symbol.as_ptr()) };
    (!symbol.is_null()).then_some(symbol)
}

type MainConnectionId = unsafe extern "C" fn() -> i32;
type SpaceCreate = unsafe extern "C" fn(i32, i32, *const c_void) -> u64;
type SpaceSetAbsoluteLevel = unsafe extern "C" fn(i32, u64, i32) -> i32;
type ShowSpaces = unsafe extern "C" fn(i32, *const c_void) -> i32;
type SpaceAddWindows = unsafe extern "C" fn(i32, u64, *const c_void, i32) -> i32;

/// A SkyLight space above the lock screen that the dashboard windows move
/// into (COMP002 R1). Private SkyLight calls, probed like the lock, with the
/// signatures other lock-screen overlays use; the space lives as long as the
/// app.
struct Overlay {
    connection: i32,
    space: u64,
    add_windows: SpaceAddWindows,
}

impl Overlay {
    /// Builds the space once, on the main thread. `None` when SkyLight lacks
    /// a call, and the dashboard then shows at the screen saver level only,
    /// so it stays under the lock screen.
    fn shared() -> Option<&'static Self> {
        static OVERLAY: OnceLock<Option<Overlay>> = OnceLock::new();
        OVERLAY.get_or_init(Self::create).as_ref()
    }

    fn create() -> Option<Self> {
        // SAFETY: valid C strings naming SkyLight and its exported symbols.
        let symbol = |name: &CStr| unsafe { private_symbol(SKYLIGHT_FRAMEWORK, name) };
        let main_connection = symbol(c"SLSMainConnectionID")?;
        let space_create = symbol(c"SLSSpaceCreate")?;
        let set_level = symbol(c"SLSSpaceSetAbsoluteLevel")?;
        let show_spaces = symbol(c"SLSShowSpaces")?;
        let add_windows = symbol(c"SLSSpaceAddWindowsAndRemoveFromSpaces")?;
        // SAFETY: each symbol is the SkyLight function of that name, whose
        // C signature the matching type above spells out.
        let (main_connection, space_create, set_level, show_spaces, add_windows) = unsafe {
            (
                std::mem::transmute::<*mut c_void, MainConnectionId>(main_connection),
                std::mem::transmute::<*mut c_void, SpaceCreate>(space_create),
                std::mem::transmute::<*mut c_void, SpaceSetAbsoluteLevel>(set_level),
                std::mem::transmute::<*mut c_void, ShowSpaces>(show_spaces),
                std::mem::transmute::<*mut c_void, SpaceAddWindows>(add_windows),
            )
        };
        // SAFETY: no arguments; returns this process's WindowServer connection.
        let connection = unsafe { main_connection() };
        // SAFETY: a live connection, the user-space flags and no options.
        let space = unsafe { space_create(connection, OVERLAY_SPACE_FLAGS, std::ptr::null()) };
        if space == 0 {
            return None;
        }
        let spaces = number_array(&CFNumber::new_i64(i64::try_from(space).ok()?));
        // SAFETY: the space was just created on this connection, and the
        // array holds its id as a CFNumber, as SkyLight expects.
        unsafe {
            set_level(connection, space, OVERLAY_SPACE_LEVEL);
            show_spaces(connection, array_pointer(&spaces));
        }
        Some(Self {
            connection,
            space,
            add_windows,
        })
    }

    fn add(&self, window_number: isize) {
        let windows = number_array(&CFNumber::new_isize(window_number));
        // SAFETY: the overlay space belongs to this connection, and the
        // array holds one window number of this process as a CFNumber.
        let _status = unsafe {
            (self.add_windows)(
                self.connection,
                self.space,
                array_pointer(&windows),
                OVERLAY_MOVE_FLAGS,
            )
        };
    }
}

fn number_array(number: &CFNumber) -> CFRetained<CFArray<CFNumber>> {
    CFArray::from_objects(&[number])
}

fn array_pointer(array: &CFRetained<CFArray<CFNumber>>) -> *const c_void {
    CFRetained::as_ptr(array)
        .as_ptr()
        .cast::<c_void>()
        .cast_const()
}

#[link(name = "CoreGraphics", kind = "framework")]
unsafe extern "C" {
    /// The level of the shield macOS raises over every display; the
    /// bindings only have it behind a feature this crate does not enable.
    fn CGShieldingWindowLevel() -> i32;
}

/// A held `NSProcessInfo` activity, ended when let go.
type Activity = Retained<ProtocolObject<dyn NSObjectProtocol>>;

pub(crate) struct MacPlatform<R: Runtime> {
    app: AppHandle<R>,
    /// `PreventUserIdleSystemSleep`, held while agents work, locked or not.
    system: Option<Activity>,
    /// `PreventUserIdleDisplaySleep`, held while the screen saver or the
    /// lock screen is up and agents work.
    display: Option<Activity>,
    lock: Option<ScreenLock>,
}

impl<R: Runtime> MacPlatform<R> {
    pub(crate) fn new(app: AppHandle<R>, lock: Option<ScreenLock>) -> Self {
        Self {
            app,
            system: None,
            display: None,
            lock,
        }
    }
}

impl<R: Runtime> Platform for MacPlatform<R> {
    fn set_awake(&mut self, awake: bool) {
        // UserInitiated keeps the system awake and the app out of App Nap.
        hold(&mut self.system, awake, NSActivityOptions::UserInitiated);
    }

    fn set_display_on(&mut self, on: bool) {
        hold(
            &mut self.display,
            on,
            NSActivityOptions::IdleDisplaySleepDisabled,
        );
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
        windows::show(&self.app, mode, raise);
    }

    fn hide_dashboard(&mut self) {
        windows::hide(&self.app);
    }

    fn lock_screen(&mut self) {
        if let Some(lock) = self.lock {
            lock.lock();
        }
    }
}

impl<R: Runtime> Drop for MacPlatform<R> {
    fn drop(&mut self) {
        for activity in [self.display.take(), self.system.take()]
            .into_iter()
            .flatten()
        {
            end_activity(&activity);
        }
    }
}

/// Begins or ends the activity in `slot` so it is held exactly when `held`.
fn hold(slot: &mut Option<Activity>, held: bool, options: NSActivityOptions) {
    match (held, slot.take()) {
        (true, None) => {
            let reason = NSString::from_str(AWAKE_REASON);
            *slot = Some(
                NSProcessInfo::processInfo().beginActivityWithOptions_reason(options, &reason),
            );
        }
        (false, Some(activity)) => end_activity(&activity),
        (_, current) => *slot = current,
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

/// Calls `on_signal()` whenever macOS says the screen locked or unlocked.
/// The caller reads the session for the state itself.
pub(crate) fn watch_screen_lock<R: Runtime>(
    app: &AppHandle<R>,
    on_signal: impl Fn() + Send + Sync + 'static,
) {
    let on_signal = Arc::new(move |_: bool| on_signal());
    observe_distributed(
        app,
        &[
            ("com.apple.screenIsLocked", true),
            ("com.apple.screenIsUnlocked", false),
        ],
        on_signal,
    );
}

/// Calls `on_change(running)` whenever the macOS screen saver starts or
/// stops.
pub(crate) fn watch_screen_saver<R: Runtime>(
    app: &AppHandle<R>,
    on_change: impl Fn(bool) + Send + Sync + 'static,
) {
    observe_distributed(
        app,
        &[
            ("com.apple.screensaver.didstart", true),
            ("com.apple.screensaver.didstop", false),
        ],
        Arc::new(on_change),
    );
}

/// Calls `on_post(value)` with the value paired to each distributed
/// notification name, whenever one is posted.
fn observe_distributed<R: Runtime>(
    app: &AppHandle<R>,
    names: &[(&'static str, bool)],
    on_post: Arc<dyn Fn(bool) + Send + Sync>,
) {
    let names = names.to_vec();
    let _ = app.run_on_main_thread(move || {
        let center = NSDistributedNotificationCenter::defaultCenter();
        for (name, value) in names {
            let on_post = Arc::clone(&on_post);
            let block = RcBlock::new(move |_: NonNull<NSNotification>| on_post(value));
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

/// Moves a dashboard window above the lock screen and the screen saver on
/// every display (COMP002 R1). The window never takes the keyboard: while
/// the screen is locked, keys belong to the lock screen's password field.
fn raise<R: Runtime>(window: WebviewWindow<R>, mode: Mode) {
    let target = window.clone();
    let _ = window.run_on_main_thread(move || {
        let Ok(pointer) = target.ns_window() else {
            return;
        };
        // SAFETY: Tauri hands out the live NSWindow behind this window, and
        // this closure runs on the main thread that owns it.
        let ns_window = unsafe { &*pointer.cast::<NSWindow>() };
        // SAFETY: a plain CoreGraphics query with no arguments.
        let shield = unsafe { CGShieldingWindowLevel() };
        ns_window.setLevel(isize::try_from(shield).map_or(isize::MAX, |level| level + 1));
        ns_window.setCollectionBehavior(
            NSWindowCollectionBehavior::CanJoinAllSpaces
                | NSWindowCollectionBehavior::FullScreenAuxiliary
                | NSWindowCollectionBehavior::Stationary
                | NSWindowCollectionBehavior::IgnoresCycle,
        );
        ns_window.setCanBecomeVisibleWithoutLogin(true);
        // Over the lock screen a click goes through to it; input takes the
        // dashboard down within a sample anyway. A preview keeps its clicks,
        // so they never land in an app underneath.
        ns_window.setIgnoresMouseEvents(mode == Mode::Live);
        ns_window.orderFrontRegardless();
        let number = ns_window.windowNumber();
        if number > 0
            && let Some(overlay) = Overlay::shared()
        {
            overlay.add(number);
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
