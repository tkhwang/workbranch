//! One borderless dashboard window per display (COMP001 R10).

use tauri::window::Color;
use tauri::{AppHandle, Manager, Runtime, WebviewUrl, WebviewWindow, WebviewWindowBuilder};

/// Every dashboard window's label starts with this; the `dashboard`
/// capability grants `dashboard-*`.
const LABEL_PREFIX: &str = "dashboard-";
const PREVIEW_PREFIX: &str = "dashboard-preview-";
const ENTRY: &str = "dashboard.html";
/// The Claude theme's `--surface-0`, so a window never flashes white while
/// its page loads.
const BACKGROUND: Color = Color(0x13, 0x13, 0x13, 0xff);

/// A live dashboard locks on input; a preview from Settings only closes
/// (COMP001 R12). The page reads which one it is from its window label.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Mode {
    Live,
    Preview,
}

impl Mode {
    fn label_prefix(self) -> &'static str {
        match self {
            Self::Live => LABEL_PREFIX,
            Self::Preview => PREVIEW_PREFIX,
        }
    }
}

/// Where one dashboard window goes, in logical points.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Frame {
    pub(crate) label: String,
    pub(crate) x: f64,
    pub(crate) y: f64,
    pub(crate) width: f64,
    pub(crate) height: f64,
    /// The primary display's window takes keyboard focus, so keys pressed
    /// before the lock land on the dashboard instead of the app underneath.
    pub(crate) focus: bool,
}

/// A display as Tauri reports it: physical pixels plus its scale factor.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Display {
    pub(crate) x: i32,
    pub(crate) y: i32,
    pub(crate) width: u32,
    pub(crate) height: u32,
    pub(crate) scale: f64,
    pub(crate) primary: bool,
}

pub(crate) fn frames(displays: &[Display], mode: Mode) -> Vec<Frame> {
    let focus_index = displays
        .iter()
        .position(|display| display.primary)
        .unwrap_or(0);
    displays
        .iter()
        .enumerate()
        .map(|(index, display)| {
            let scale = if display.scale > 0.0 {
                display.scale
            } else {
                1.0
            };
            Frame {
                label: format!("{}{index}", mode.label_prefix()),
                x: f64::from(display.x) / scale,
                y: f64::from(display.y) / scale,
                width: f64::from(display.width) / scale,
                height: f64::from(display.height) / scale,
                focus: index == focus_index,
            }
        })
        .collect()
}

fn displays<R: Runtime>(app: &AppHandle<R>) -> Vec<Display> {
    let primary = app.primary_monitor().ok().flatten();
    app.available_monitors()
        .unwrap_or_default()
        .iter()
        .map(|monitor| Display {
            x: monitor.position().x,
            y: monitor.position().y,
            width: monitor.size().width,
            height: monitor.size().height,
            scale: monitor.scale_factor(),
            primary: primary
                .as_ref()
                .is_some_and(|primary| primary.position() == monitor.position()),
        })
        .collect()
}

/// Covers every display, replacing any dashboard windows already open so the
/// set always matches the current displays.
pub(crate) fn show<R: Runtime>(
    app: &AppHandle<R>,
    mode: Mode,
    raise: impl Fn(WebviewWindow<R>, bool),
) {
    hide(app);
    for frame in frames(&displays(app), mode) {
        let built = WebviewWindowBuilder::new(app, &frame.label, WebviewUrl::App(ENTRY.into()))
            .title("Workbranch Dashboard")
            .decorations(false)
            .resizable(false)
            // Nothing but the lock (or, in a preview, input) takes it down.
            .minimizable(false)
            .closable(false)
            .shadow(false)
            .skip_taskbar(true)
            .always_on_top(true)
            .visible_on_all_workspaces(true)
            .background_color(BACKGROUND)
            .position(frame.x, frame.y)
            .inner_size(frame.width, frame.height)
            .focused(frame.focus)
            .build();
        if let Ok(window) = built {
            raise(window, frame.focus);
        }
    }
}

/// Takes every dashboard window off screen before tearing any of them down,
/// so the screen goes straight from the dashboard to what lies beneath and no
/// window is still visible while its webview is being released.
pub(crate) fn hide<R: Runtime>(app: &AppHandle<R>) {
    let windows: Vec<WebviewWindow<R>> = app
        .webview_windows()
        .into_iter()
        .filter(|(label, _)| label.starts_with(LABEL_PREFIX))
        .map(|(_, window)| window)
        .collect();
    for window in &windows {
        let _ = window.hide();
    }
    for window in windows {
        let _ = window.destroy();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn display(x: i32, width: u32, scale: f64, primary: bool) -> Display {
        Display {
            x,
            y: 0,
            width,
            height: 1800,
            scale,
            primary,
        }
    }

    #[test]
    fn each_display_gets_a_window_sized_in_points() {
        let frames = frames(
            &[display(0, 2880, 2.0, true), display(2880, 1920, 1.0, false)],
            Mode::Live,
        );
        assert_eq!(frames.len(), 2);
        assert_eq!(frames[0].label, "dashboard-0");
        assert_eq!(
            (frames[0].x, frames[0].width, frames[0].height),
            (0.0, 1440.0, 900.0)
        );
        assert_eq!((frames[1].x, frames[1].width), (2880.0, 1920.0));
    }

    #[test]
    fn the_primary_display_takes_focus() {
        let frames = frames(
            &[
                display(-1920, 1920, 1.0, false),
                display(0, 2880, 2.0, true),
            ],
            Mode::Live,
        );
        assert_eq!(
            frames.iter().map(|frame| frame.focus).collect::<Vec<_>>(),
            vec![false, true]
        );
    }

    #[test]
    fn the_first_display_takes_focus_when_none_is_primary() {
        let frames = frames(
            &[
                display(0, 1920, 1.0, false),
                display(1920, 1920, 1.0, false),
            ],
            Mode::Live,
        );
        assert!(frames[0].focus);
        assert!(!frames[1].focus);
    }

    #[test]
    fn a_preview_labels_its_windows_apart() {
        let frames = frames(&[display(0, 1920, 1.0, true)], Mode::Preview);
        assert_eq!(frames[0].label, "dashboard-preview-0");
        assert!(frames[0].label.starts_with(LABEL_PREFIX));
    }
}
