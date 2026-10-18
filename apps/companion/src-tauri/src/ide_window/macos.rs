//! The macOS side of `ide_window`. CoreGraphics lists the window numbers on
//! every Space without any permission; the Accessibility API, which needs
//! the user's permission, reads and moves the IDE windows.

use std::collections::HashSet;
use std::ffi::{CStr, c_void};
use std::ptr::NonNull;
use std::sync::OnceLock;
use std::sync::mpsc::{self, Sender};

use objc2::rc::autoreleasepool;
use objc2_app_kit::NSRunningApplication;
use objc2_core_foundation::{
    CFArray, CFBoolean, CFDictionary, CFNumber, CFRetained, CFString, CFType, CGPoint, CGSize,
};
use objc2_core_graphics::{CGWindowListCopyWindowInfo, CGWindowListOption, kCGWindowNumber};
use objc2_foundation::NSString;

use super::{Desktop, Follower, Frame, IDE_BUNDLE_IDS, OpenWindow};

type AXError = i32;
const AX_SUCCESS: AXError = 0;
/// Seconds an Accessibility call waits for a busy app, instead of six.
const AX_TIMEOUT_SECONDS: f32 = 1.0;

const APPLICATION_SERVICES: &CStr =
    c"/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices";
/// `_AXUIElementGetWindow`: the CoreGraphics window number of an
/// Accessibility window. Private, so it is probed rather than linked;
/// macOS window managers have relied on it for years.
const GET_WINDOW_SYMBOL: &CStr = c"_AXUIElementGetWindow";
type GetWindow = unsafe extern "C" fn(*const CFType, *mut u32) -> AXError;

#[link(name = "ApplicationServices", kind = "framework")]
unsafe extern "C" {
    safe fn AXIsProcessTrusted() -> u8;
    fn AXIsProcessTrustedWithOptions(options: *const c_void) -> u8;
    safe fn AXUIElementCreateSystemWide() -> *mut CFType;
    safe fn AXUIElementCreateApplication(pid: libc::pid_t) -> *mut CFType;
    fn AXUIElementCopyAttributeValue(
        element: &CFType,
        attribute: &CFString,
        value: *mut *mut CFType,
    ) -> AXError;
    fn AXUIElementSetAttributeValue(
        element: &CFType,
        attribute: &CFString,
        value: &CFType,
    ) -> AXError;
    fn AXUIElementSetMessagingTimeout(element: &CFType, timeout_seconds: f32) -> AXError;
    fn AXValueCreate(value_type: u32, value: *const c_void) -> *mut CFType;
    fn AXValueGetValue(value: &CFType, value_type: u32, value_out: *mut c_void) -> u8;
    static kAXTrustedCheckOptionPrompt: &'static CFString;
}

pub(super) fn access_granted() -> bool {
    AXIsProcessTrusted() != 0
}

/// Shows macOS's prompt that leads to the Accessibility list in System
/// Settings, unless the permission is granted already; returns whether it
/// is.
pub(super) fn request_access() -> bool {
    // SAFETY: a constant string HIServices exports.
    let prompt_key = unsafe { kAXTrustedCheckOptionPrompt };
    let options =
        CFDictionary::<CFString, CFBoolean>::from_slices(&[prompt_key], &[CFBoolean::new(true)]);
    let options_pointer = CFRetained::as_ptr(&options).as_ptr().cast_const().cast();
    // SAFETY: a live dictionary that holds the prompt option.
    unsafe { AXIsProcessTrustedWithOptions(options_pointer) != 0 }
}

/// Notes every window that exists now, before the command opens any, then
/// follows from a background thread until the returned sender is dropped
/// and late windows had their time.
pub(super) fn follow(screen: Frame) -> Sender<()> {
    let (command_running, receiver) = mpsc::channel();
    let existing = window_numbers();
    // A thread that fails to start leaves the windows where the IDE puts them.
    let _thread = std::thread::Builder::new()
        .name("ide-window".into())
        .spawn(move || {
            if let Some(desktop) = MacDesktop::new() {
                super::run(&desktop, Follower::new(screen, existing), &receiver);
            }
        });
    command_running
}

/// The numbers of every window, on every Space and of every app. A window
/// keeps its number for life, so one missing here opened later.
fn window_numbers() -> HashSet<u32> {
    let Some(windows) = CGWindowListCopyWindowInfo(CGWindowListOption::OptionAll, 0) else {
        return HashSet::new();
    };
    // SAFETY: the window list is an array of dictionaries from CFString
    // keys to CF values.
    let windows: CFRetained<CFArray<CFDictionary<CFString, CFType>>> =
        unsafe { CFRetained::cast_unchecked(windows) };
    // SAFETY: a constant string CoreGraphics exports.
    let number_key = unsafe { kCGWindowNumber };
    windows
        .iter()
        .filter_map(|window| {
            let number = window.get(number_key)?.downcast::<CFNumber>().ok()?;
            u32::try_from(number.as_i64()?).ok()
        })
        .collect()
}

struct MacDesktop {
    get_window: GetWindow,
}

impl MacDesktop {
    fn new() -> Option<Self> {
        if let Some(system) = NonNull::new(AXUIElementCreateSystemWide()) {
            // SAFETY: AXUIElementCreateSystemWide returns a new reference.
            let system = unsafe { CFRetained::from_raw(system) };
            // SAFETY: a live element; on the system-wide element the timeout
            // applies to every Accessibility call of this process.
            let _error = unsafe { AXUIElementSetMessagingTimeout(&system, AX_TIMEOUT_SECONDS) };
        }
        Some(Self {
            get_window: get_window()?,
        })
    }

    fn window_number(&self, window: &CFType) -> Option<u32> {
        let mut number = 0;
        // SAFETY: `get_window` is _AXUIElementGetWindow, which reads an
        // Accessibility element and writes a CGWindowID.
        let error = unsafe { (self.get_window)(std::ptr::from_ref(window), &raw mut number) };
        (error == AX_SUCCESS && number != 0).then_some(number)
    }
}

impl Desktop for MacDesktop {
    type Handle = CFRetained<CFType>;

    fn ide_windows(&self) -> Vec<OpenWindow<Self::Handle>> {
        ide_pids()
            .into_iter()
            .flat_map(application_windows)
            .filter(|window| is_movable(window))
            .filter_map(|window| {
                Some(OpenWindow {
                    id: self.window_number(&window)?,
                    frame: frame(&window)?,
                    handle: window,
                })
            })
            .collect()
    }

    fn move_window(&self, window: &Self::Handle, frame: Frame) -> bool {
        let origin = CGPoint {
            x: frame.x,
            y: frame.y,
        };
        let size = CGSize {
            width: frame.width,
            height: frame.height,
        };
        // Moving first lets the window take a size that only fits on the
        // new screen; moving again settles an origin macOS adjusted for the
        // old size. A window that cannot be resized keeps its size, so only
        // the moves decide whether it got there.
        let moved = write_value(window, "AXPosition", origin);
        let _resized = write_value(window, "AXSize", size);
        moved && write_value(window, "AXPosition", origin)
    }
}

fn get_window() -> Option<GetWindow> {
    static GET_WINDOW: OnceLock<Option<GetWindow>> = OnceLock::new();
    *GET_WINDOW.get_or_init(|| {
        // SAFETY: a valid framework path; the handle is never closed, so the
        // symbol stays valid for the process's life.
        let handle = unsafe { libc::dlopen(APPLICATION_SERVICES.as_ptr(), libc::RTLD_LAZY) };
        if handle.is_null() {
            return None;
        }
        // SAFETY: a live handle and a valid C symbol name.
        let symbol = unsafe { libc::dlsym(handle, GET_WINDOW_SYMBOL.as_ptr()) };
        if symbol.is_null() {
            return None;
        }
        // SAFETY: _AXUIElementGetWindow has the C signature `GetWindow`
        // spells out.
        Some(unsafe { std::mem::transmute::<*mut c_void, GetWindow>(symbol) })
    })
}

fn ide_pids() -> Vec<libc::pid_t> {
    // This runs on a background thread, which has no autorelease pool of
    // its own.
    autoreleasepool(|_| {
        IDE_BUNDLE_IDS
            .iter()
            .flat_map(|bundle_id| {
                NSRunningApplication::runningApplicationsWithBundleIdentifier(&NSString::from_str(
                    bundle_id,
                ))
                .to_vec()
            })
            .map(|application| application.processIdentifier())
            .filter(|pid| *pid > 0)
            .collect()
    })
}

fn application_windows(pid: libc::pid_t) -> Vec<CFRetained<CFType>> {
    let Some(application) = NonNull::new(AXUIElementCreateApplication(pid)) else {
        return Vec::new();
    };
    // SAFETY: AXUIElementCreateApplication returns a new reference.
    let application = unsafe { CFRetained::from_raw(application) };
    let Some(windows) =
        attribute(&application, "AXWindows").and_then(|value| value.downcast::<CFArray>().ok())
    else {
        return Vec::new();
    };
    // SAFETY: an app's AXWindows holds Accessibility elements, CF objects.
    let windows: CFRetained<CFArray<CFType>> = unsafe { CFRetained::cast_unchecked(windows) };
    windows.to_vec()
}

/// A document window the user could drag: not a dialog or panel, and not
/// minimized or in its own full-screen Space.
fn is_movable(window: &CFType) -> bool {
    let standard = attribute(window, "AXSubrole")
        .and_then(|subrole| subrole.downcast::<CFString>().ok())
        .is_some_and(|subrole| *subrole == *CFString::from_static_str("AXStandardWindow"));
    standard && !flag(window, "AXMinimized") && !flag(window, "AXFullScreen")
}

fn flag(element: &CFType, name: &'static str) -> bool {
    attribute(element, name)
        .and_then(|value| value.downcast::<CFBoolean>().ok())
        .is_some_and(|value| value.as_bool())
}

fn frame(window: &CFType) -> Option<Frame> {
    let origin = read_value(window, "AXPosition", CGPoint { x: 0.0, y: 0.0 })?;
    let size = read_value(
        window,
        "AXSize",
        CGSize {
            width: 0.0,
            height: 0.0,
        },
    )?;
    Some(Frame {
        x: origin.x,
        y: origin.y,
        width: size.width,
        height: size.height,
    })
}

fn attribute(element: &CFType, name: &'static str) -> Option<CFRetained<CFType>> {
    let mut value = std::ptr::null_mut();
    // SAFETY: a live element and attribute name; on success the call stores
    // a new reference in `value`.
    let error = unsafe {
        AXUIElementCopyAttributeValue(element, &CFString::from_static_str(name), &raw mut value)
    };
    if error != AX_SUCCESS {
        return None;
    }
    // SAFETY: the reference the call handed over, now owned here.
    NonNull::new(value).map(|value| unsafe { CFRetained::from_raw(value) })
}

/// A geometry an AXValue holds, with the `AXValueType` that names it.
trait AxGeometry: Copy {
    const KIND: u32;
}

impl AxGeometry for CGPoint {
    /// `kAXValueCGPointType`
    const KIND: u32 = 1;
}

impl AxGeometry for CGSize {
    /// `kAXValueCGSizeType`
    const KIND: u32 = 2;
}

fn read_value<T: AxGeometry>(element: &CFType, name: &'static str, mut out: T) -> Option<T> {
    let value = attribute(element, name)?;
    // SAFETY: `T::KIND` names the C type of `T`, so the call writes a whole
    // `T`; it returns false and writes nothing when the value holds another
    // type.
    let read = unsafe { AXValueGetValue(&value, T::KIND, (&raw mut out).cast()) };
    (read != 0).then_some(out)
}

/// Returns whether the app took the value.
fn write_value<T: AxGeometry>(element: &CFType, name: &'static str, geometry: T) -> bool {
    // SAFETY: `T::KIND` names the C type of `T`, which the call copies.
    let value = unsafe { AXValueCreate(T::KIND, (&raw const geometry).cast()) };
    let Some(value) = NonNull::new(value) else {
        return false;
    };
    // SAFETY: AXValueCreate returns a new reference.
    let value = unsafe { CFRetained::from_raw(value) };
    // SAFETY: a live element, an attribute name and an AXValue of the type
    // the attribute takes.
    let error =
        unsafe { AXUIElementSetAttributeValue(element, &CFString::from_static_str(name), &value) };
    error == AX_SUCCESS
}
