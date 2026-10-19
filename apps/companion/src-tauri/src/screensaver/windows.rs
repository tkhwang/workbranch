//! One borderless dashboard window per display (COMP001 R10).

use tauri::window::Color;
use tauri::{
    AppHandle, LogicalPosition, LogicalSize, Manager, Runtime, WebviewUrl, WebviewWindow,
    WebviewWindowBuilder,
};

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

/// What to change so the open dashboard windows cover each display once.
#[derive(Debug, Default, PartialEq)]
pub(crate) struct Plan {
    /// Open windows no display wants: their display is gone, or they belong
    /// to the other mode.
    pub(crate) close: Vec<String>,
    /// Open windows whose display moved or changed size.
    pub(crate) place: Vec<Frame>,
    /// Displays that have no window yet.
    pub(crate) open: Vec<Frame>,
}

/// Compares the dashboard windows that are open (`open`, by label) and where
/// they were last put (`placed`) with one window per display (`wanted`).
///
/// A window already where its display is stays untouched. macOS announces
/// new screen parameters for more than layout changes (on an XDR display,
/// every brightness ramp changes the EDR headroom and posts the notice many
/// times a second), and rebuilding the windows on each notice made the
/// dashboard flicker and, once a rebuild lost the race with the window it
/// replaced, vanish while the screen stayed locked. An empty `wanted` means
/// the displays could not be read, so nothing changes.
pub(crate) fn plan(open: &[String], placed: &[Frame], wanted: &[Frame]) -> Plan {
    if wanted.is_empty() {
        return Plan::default();
    }
    let close = open
        .iter()
        .filter(|label| !wanted.iter().any(|frame| &frame.label == *label))
        .cloned()
        .collect();
    let mut plan = Plan {
        close,
        ..Plan::default()
    };
    for frame in wanted {
        if !open.contains(&frame.label) {
            plan.open.push(frame.clone());
        } else if !placed.contains(frame) {
            plan.place.push(frame.clone());
        }
    }
    plan
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

fn dashboard_windows<R: Runtime>(app: &AppHandle<R>) -> Vec<(String, WebviewWindow<R>)> {
    app.webview_windows()
        .into_iter()
        .filter(|(label, _)| label.starts_with(LABEL_PREFIX))
        .collect()
}

/// The dashboard windows on screen, with where this module put each one.
#[derive(Debug, Default)]
pub(crate) struct Dashboard {
    placed: Vec<Frame>,
}

impl Dashboard {
    /// Covers every display, opening a window only where one is missing,
    /// moving only those whose display moved, and closing those no display
    /// wants, so calling it again with the same displays changes nothing.
    /// `raise` lifts each new or moved window above the lock screen.
    pub(crate) fn show<R: Runtime>(
        &mut self,
        app: &AppHandle<R>,
        mode: Mode,
        raise: impl Fn(WebviewWindow<R>, Mode),
    ) {
        let wanted = frames(&displays(app), mode);
        let open = dashboard_windows(app);
        let labels: Vec<String> = open.iter().map(|(label, _)| label.clone()).collect();
        let plan = plan(&labels, &self.placed, &wanted);
        if plan == Plan::default() {
            return;
        }

        close(
            open.into_iter()
                .filter(|(label, _)| plan.close.contains(label))
                .map(|(_, window)| window)
                .collect(),
        );
        for frame in &plan.place {
            if let Some(window) = app.get_webview_window(&frame.label) {
                let _ = window.set_position(LogicalPosition::new(frame.x, frame.y));
                let _ = window.set_size(LogicalSize::new(frame.width, frame.height));
                raise(window, mode);
            }
        }
        // Only windows that are open count as placed; one that failed to
        // open is still missing on the next call and is opened then.
        let mut placed: Vec<Frame> = wanted
            .into_iter()
            .filter(|frame| !plan.open.contains(frame))
            .collect();
        for frame in plan.open {
            match build(app, &frame) {
                Ok(window) => {
                    raise(window, mode);
                    placed.push(frame);
                }
                Err(error) => {
                    eprintln!(
                        "[screensaver] could not open dashboard window {}: {error}",
                        frame.label
                    );
                }
            }
        }
        self.placed = placed;
    }

    /// Takes every dashboard window down.
    pub(crate) fn hide<R: Runtime>(&mut self, app: &AppHandle<R>) {
        self.placed.clear();
        close(
            dashboard_windows(app)
                .into_iter()
                .map(|(_, window)| window)
                .collect(),
        );
    }
}

fn build<R: Runtime>(app: &AppHandle<R>, frame: &Frame) -> tauri::Result<WebviewWindow<R>> {
    WebviewWindowBuilder::new(app, &frame.label, WebviewUrl::App(ENTRY.into()))
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
        .build()
}

/// Takes the windows off screen before tearing any of them down, so the
/// screen goes straight from the dashboard to what lies beneath and no
/// window is still visible while its webview is being released.
fn close<R: Runtime>(windows: Vec<WebviewWindow<R>>) {
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

    fn labels(frames: &[Frame]) -> Vec<String> {
        frames.iter().map(|frame| frame.label.clone()).collect()
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

    #[test]
    fn the_first_show_opens_a_window_per_display() {
        let wanted = frames(&[display(0, 2880, 2.0)], Mode::Live);
        let plan = plan(&[], &[], &wanted);
        assert_eq!(plan.open, wanted);
        assert!(plan.close.is_empty() && plan.place.is_empty());
    }

    #[test]
    fn the_same_displays_change_nothing() {
        // What a brightness ramp announces: new screen parameters, the same
        // layout.
        let wanted = frames(
            &[display(0, 2880, 2.0), display(2880, 2560, 1.0)],
            Mode::Live,
        );
        assert_eq!(plan(&labels(&wanted), &wanted, &wanted), Plan::default());
    }

    #[test]
    fn a_new_display_opens_only_its_window() {
        let before = frames(&[display(0, 2880, 2.0)], Mode::Live);
        let after = frames(
            &[display(0, 2880, 2.0), display(2880, 2560, 1.0)],
            Mode::Live,
        );
        let plan = plan(&labels(&before), &before, &after);
        assert_eq!(labels(&plan.open), vec!["dashboard-1"]);
        assert!(plan.close.is_empty() && plan.place.is_empty());
    }

    #[test]
    fn a_display_that_left_closes_its_window() {
        let before = frames(
            &[display(0, 2880, 2.0), display(2880, 2560, 1.0)],
            Mode::Live,
        );
        let after = frames(&[display(0, 2880, 2.0)], Mode::Live);
        let plan = plan(&labels(&before), &before, &after);
        assert_eq!(plan.close, vec!["dashboard-1"]);
        assert!(plan.open.is_empty() && plan.place.is_empty());
    }

    #[test]
    fn a_moved_display_moves_its_window() {
        let before = frames(
            &[display(0, 2880, 2.0), display(2880, 2560, 1.0)],
            Mode::Live,
        );
        let after = frames(
            &[display(0, 2880, 2.0), display(-2560, 2560, 1.0)],
            Mode::Live,
        );
        let plan = plan(&labels(&before), &before, &after);
        assert_eq!(plan.place, vec![after[1].clone()]);
        assert!(plan.open.is_empty() && plan.close.is_empty());
    }

    #[test]
    fn a_window_open_at_an_unknown_place_is_moved() {
        let wanted = frames(&[display(0, 2880, 2.0)], Mode::Live);
        let plan = plan(&labels(&wanted), &[], &wanted);
        assert_eq!(plan.place, wanted);
    }

    #[test]
    fn switching_mode_replaces_every_window() {
        let preview = frames(&[display(0, 2880, 2.0)], Mode::Preview);
        let live = frames(&[display(0, 2880, 2.0)], Mode::Live);
        let plan = plan(&labels(&preview), &preview, &live);
        assert_eq!(plan.close, vec!["dashboard-preview-0"]);
        assert_eq!(plan.open, live);
    }

    #[test]
    fn unreadable_displays_keep_the_windows_up() {
        let open = frames(&[display(0, 2880, 2.0)], Mode::Live);
        assert_eq!(plan(&labels(&open), &open, &[]), Plan::default());
    }
}
