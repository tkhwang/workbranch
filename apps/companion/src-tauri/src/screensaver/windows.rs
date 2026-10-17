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

/// A live dashboard covers the screen saver and the lock screen and steps
/// aside on input; a preview from Settings only closes on input (COMP001
/// R12). The page reads which one it is from its window label.
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
}

/// A display as Tauri reports it: physical pixels plus its scale factor.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Display {
    pub(crate) x: i32,
    pub(crate) y: i32,
    pub(crate) width: u32,
    pub(crate) height: u32,
    pub(crate) scale: f64,
}

pub(crate) fn frames(displays: &[Display], mode: Mode) -> Vec<Frame> {
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
            }
        })
        .collect()
}

fn displays<R: Runtime>(app: &AppHandle<R>) -> Vec<Display> {
    app.available_monitors()
        .unwrap_or_default()
        .iter()
        .map(|monitor| Display {
            x: monitor.position().x,
            y: monitor.position().y,
            width: monitor.size().width,
            height: monitor.size().height,
            scale: monitor.scale_factor(),
        })
        .collect()
}

/// Covers every display, replacing any dashboard windows already open so the
/// set always matches the current displays. `raise` lifts each new window
/// above the lock screen.
pub(crate) fn show<R: Runtime>(
    app: &AppHandle<R>,
    mode: Mode,
    raise: impl Fn(WebviewWindow<R>, Mode),
) {
    hide(app);
    for frame in frames(&displays(app), mode) {
        let built = WebviewWindowBuilder::new(app, &frame.label, WebviewUrl::App(ENTRY.into()))
            .title("Workbranch Dashboard")
            .decorations(false)
            .resizable(false)
            // Nothing but input, signing in or work ending takes it down.
            .minimizable(false)
            .closable(false)
            .shadow(false)
            .skip_taskbar(true)
            .always_on_top(true)
            .visible_on_all_workspaces(true)
            .background_color(BACKGROUND)
            .position(frame.x, frame.y)
            .inner_size(frame.width, frame.height)
            // The keyboard stays with the lock screen's password field.
            .focused(false)
            .build();
        if let Ok(window) = built {
            raise(window, mode);
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

    fn display(x: i32, width: u32, scale: f64) -> Display {
        Display {
            x,
            y: 0,
            width,
            height: 1800,
            scale,
        }
    }

    #[test]
    fn each_display_gets_a_window_sized_in_points() {
        let frames = frames(
            &[display(0, 2880, 2.0), display(2880, 1920, 1.0)],
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
    fn a_display_without_a_scale_counts_as_one_to_one() {
        let frames = frames(&[display(-1920, 1920, 0.0)], Mode::Live);
        assert_eq!((frames[0].x, frames[0].width), (-1920.0, 1920.0));
    }

    #[test]
    fn a_preview_labels_its_windows_apart() {
        let frames = frames(&[display(0, 1920, 1.0)], Mode::Preview);
        assert_eq!(frames[0].label, "dashboard-preview-0");
        assert!(frames[0].label.starts_with(LABEL_PREFIX));
    }
}
