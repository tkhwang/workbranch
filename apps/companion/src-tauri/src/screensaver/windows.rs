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

/// Where one dashboard window goes, in logical points. `slot` names the
/// display it covers in this mode (`dashboard-0`, `dashboard-preview-1`);
/// each window's label adds a serial to it.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Frame {
    pub(crate) slot: String,
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
                slot: format!("{}{index}", mode.label_prefix()),
                x: f64::from(display.x) / scale,
                y: f64::from(display.y) / scale,
                width: f64::from(display.width) / scale,
                height: f64::from(display.height) / scale,
            }
        })
        .collect()
}

/// What to change so the dashboard windows cover each display once.
#[derive(Debug, Default, PartialEq)]
pub(crate) struct Plan {
    /// Slots no display wants: their display is gone, or they belong to the
    /// other mode.
    pub(crate) close: Vec<String>,
    /// Displays whose window is not where the display is.
    pub(crate) place: Vec<Frame>,
    /// Displays that have no window.
    pub(crate) open: Vec<Frame>,
}

/// Compares where the open dashboard windows are (`placed`) with one window
/// per display (`wanted`).
///
/// A window already where its display is stays untouched. macOS announces
/// new screen parameters for more than layout changes (on an XDR display,
/// every brightness ramp changes the EDR headroom and posts the notice many
/// times a second), and rebuilding the windows on each notice made the
/// dashboard flicker and, once a rebuild lost the race with the window it
/// replaced, vanish while the screen stayed locked. An empty `wanted` means
/// the displays could not be read, so nothing changes.
pub(crate) fn plan(placed: &[Frame], wanted: &[Frame]) -> Plan {
    if wanted.is_empty() {
        return Plan::default();
    }
    let mut plan = Plan {
        close: placed
            .iter()
            .filter(|frame| !wanted.iter().any(|want| want.slot == frame.slot))
            .map(|frame| frame.slot.clone())
            .collect(),
        ..Plan::default()
    };
    for frame in wanted {
        match placed.iter().find(|open| open.slot == frame.slot) {
            None => plan.open.push(frame.clone()),
            Some(open) if open != frame => plan.place.push(frame.clone()),
            Some(_) => {}
        }
    }
    plan
}

/// What the dashboard needs from the window system: Tauri in the app, a fake
/// in tests.
pub(crate) trait Screens {
    type Window;
    /// The displays now; empty when they cannot be read.
    fn displays(&self) -> Vec<Display>;
    /// The window with this label while it exists, including while it is
    /// still being destroyed.
    fn window(&self, label: &str) -> Option<Self::Window>;
    fn open(&self, label: &str, frame: &Frame) -> Result<Self::Window, String>;
    /// Moves and resizes the window; `false` when either fails.
    fn place(&self, window: &Self::Window, frame: &Frame) -> bool;
    /// Takes the windows off screen, then destroys them. Destroying finishes
    /// later, so their labels stay taken for a moment.
    fn close(&self, windows: Vec<Self::Window>);
    /// Every dashboard window that exists, whoever opened it.
    fn dashboard_windows(&self) -> Vec<Self::Window>;
}

/// A dashboard window this app opened and has not closed.
#[derive(Debug)]
struct Opened {
    label: String,
    /// Where the window last got to; a move that failed leaves the old frame
    /// here, so the next call moves it again.
    frame: Frame,
}

/// The dashboard windows on screen.
#[derive(Debug, Default)]
pub(crate) struct Dashboard {
    windows: Vec<Opened>,
    /// Numbers each new window's label, so a new window never shares a label
    /// with one that is still being destroyed (Tauri frees a label only once
    /// the window is gone).
    serial: u64,
}

impl Dashboard {
    /// Covers every display, opening a window only where one is missing,
    /// moving only those whose display moved, and closing those no display
    /// wants, so calling it again with the same displays changes nothing.
    /// A window that failed to open or move, or that vanished, is dealt with
    /// on the next call. `raise` lifts each new or moved window above the
    /// lock screen.
    pub(crate) fn show<S: Screens>(
        &mut self,
        screens: &S,
        mode: Mode,
        raise: impl Fn(S::Window, Mode),
    ) {
        let wanted = frames(&screens.displays(), mode);
        self.windows
            .retain(|opened| screens.window(&opened.label).is_some());
        let placed: Vec<Frame> = self
            .windows
            .iter()
            .map(|opened| opened.frame.clone())
            .collect();
        let plan = plan(&placed, &wanted);
        if plan == Plan::default() {
            return;
        }

        let (closing, kept): (Vec<Opened>, Vec<Opened>) = std::mem::take(&mut self.windows)
            .into_iter()
            .partition(|opened| plan.close.contains(&opened.frame.slot));
        self.windows = kept;
        screens.close(
            closing
                .iter()
                .filter_map(|opened| screens.window(&opened.label))
                .collect(),
        );

        for frame in plan.place {
            let Some(opened) = self
                .windows
                .iter_mut()
                .find(|opened| opened.frame.slot == frame.slot)
            else {
                continue;
            };
            let Some(window) = screens.window(&opened.label) else {
                continue;
            };
            let moved = screens.place(&window, &frame);
            raise(window, mode);
            if moved {
                opened.frame = frame;
            }
        }

        for frame in plan.open {
            self.serial += 1;
            let label = format!("{}-{}", frame.slot, self.serial);
            match screens.open(&label, &frame) {
                Ok(window) => {
                    raise(window, mode);
                    self.windows.push(Opened { label, frame });
                }
                Err(error) => {
                    eprintln!("[screensaver] could not open dashboard window {label}: {error}");
                }
            }
        }
    }

    /// Takes every dashboard window down.
    pub(crate) fn hide<S: Screens>(&mut self, screens: &S) {
        self.windows.clear();
        screens.close(screens.dashboard_windows());
    }
}

impl<R: Runtime> Screens for AppHandle<R> {
    type Window = WebviewWindow<R>;

    fn displays(&self) -> Vec<Display> {
        self.available_monitors()
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

    fn window(&self, label: &str) -> Option<Self::Window> {
        self.get_webview_window(label)
    }

    fn open(&self, label: &str, frame: &Frame) -> Result<Self::Window, String> {
        WebviewWindowBuilder::new(self, label, WebviewUrl::App(ENTRY.into()))
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
            .map_err(|error| error.to_string())
    }

    fn place(&self, window: &Self::Window, frame: &Frame) -> bool {
        let moved = window
            .set_position(LogicalPosition::new(frame.x, frame.y))
            .is_ok();
        let sized = window
            .set_size(LogicalSize::new(frame.width, frame.height))
            .is_ok();
        moved && sized
    }

    /// Hides every window before destroying any, so the screen goes straight
    /// from the dashboard to what lies beneath and no window is still visible
    /// while its webview is being released.
    fn close(&self, windows: Vec<Self::Window>) {
        for window in &windows {
            let _ = window.hide();
        }
        for window in windows {
            let _ = window.destroy();
        }
    }

    fn dashboard_windows(&self) -> Vec<Self::Window> {
        self.webview_windows()
            .into_iter()
            .filter(|(label, _)| label.starts_with(LABEL_PREFIX))
            .map(|(_, window)| window)
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use std::cell::{Cell, RefCell};

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

    const BUILT_IN: Display = Display {
        x: 0,
        y: 0,
        width: 3456,
        height: 2234,
        scale: 2.0,
    };
    const EXTERNAL: Display = Display {
        x: 3456,
        y: -412,
        width: 2560,
        height: 1440,
        scale: 1.0,
    };

    /// Windows as Tauri keeps them: a destroyed window holds its label until
    /// `finish_destroying()`, and opening a label that is still held fails.
    #[derive(Default)]
    struct Fake {
        displays: RefCell<Vec<Display>>,
        windows: RefCell<Vec<(String, Frame)>>,
        destroying: RefCell<Vec<String>>,
        fail_open: Cell<bool>,
        fail_place: Cell<bool>,
        raised: RefCell<Vec<String>>,
    }

    impl Fake {
        fn with(displays: &[Display]) -> Self {
            let fake = Self::default();
            fake.set_displays(displays);
            fake
        }

        fn set_displays(&self, displays: &[Display]) {
            *self.displays.borrow_mut() = displays.to_vec();
        }

        fn finish_destroying(&self) {
            self.destroying.borrow_mut().clear();
        }

        /// Frames covered by windows that are not being destroyed.
        fn covered(&self) -> Vec<Frame> {
            let mut frames: Vec<Frame> = self
                .windows
                .borrow()
                .iter()
                .map(|(_, frame)| frame.clone())
                .collect();
            frames.sort_by(|a, b| a.slot.cmp(&b.slot));
            frames
        }

        fn labels(&self) -> Vec<String> {
            let mut labels: Vec<String> = self
                .windows
                .borrow()
                .iter()
                .map(|(label, _)| label.clone())
                .collect();
            labels.sort();
            labels
        }
    }

    impl Screens for Fake {
        type Window = String;

        fn displays(&self) -> Vec<Display> {
            self.displays.borrow().clone()
        }

        fn window(&self, label: &str) -> Option<String> {
            let exists = self.windows.borrow().iter().any(|(open, _)| open == label)
                || self.destroying.borrow().iter().any(|dying| dying == label);
            exists.then(|| label.to_owned())
        }

        fn open(&self, label: &str, frame: &Frame) -> Result<String, String> {
            if self.fail_open.get() {
                return Err("failed".into());
            }
            if self.window(label).is_some() {
                return Err(format!("a window with label `{label}` already exists"));
            }
            self.windows
                .borrow_mut()
                .push((label.to_owned(), frame.clone()));
            Ok(label.to_owned())
        }

        fn place(&self, window: &String, frame: &Frame) -> bool {
            if self.fail_place.get() {
                return false;
            }
            for (label, at) in self.windows.borrow_mut().iter_mut() {
                if label == window {
                    *at = frame.clone();
                }
            }
            true
        }

        fn close(&self, windows: Vec<String>) {
            self.windows
                .borrow_mut()
                .retain(|(label, _)| !windows.contains(label));
            self.destroying.borrow_mut().extend(windows);
        }

        fn dashboard_windows(&self) -> Vec<String> {
            let mut all = self.labels();
            all.extend(self.destroying.borrow().iter().cloned());
            all
        }
    }

    fn show(dashboard: &mut Dashboard, fake: &Fake, mode: Mode) {
        dashboard.show(fake, mode, |window, _| {
            fake.raised.borrow_mut().push(window)
        });
    }

    #[test]
    fn each_display_gets_a_frame_sized_in_points() {
        let frames = frames(
            &[display(0, 2880, 2.0), display(2880, 1920, 1.0)],
            Mode::Live,
        );
        assert_eq!(frames.len(), 2);
        assert_eq!(frames[0].slot, "dashboard-0");
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
    fn the_plan_moves_closes_and_opens_by_slot() {
        let before = frames(&[BUILT_IN, EXTERNAL], Mode::Live);
        assert_eq!(plan(&before, &before), Plan::default());

        let moved = frames(&[BUILT_IN, display(-2560, 2560, 1.0)], Mode::Live);
        let plan_moved = plan(&before, &moved);
        assert_eq!(plan_moved.place, vec![moved[1].clone()]);
        assert!(plan_moved.open.is_empty() && plan_moved.close.is_empty());

        let fewer = frames(&[BUILT_IN], Mode::Live);
        assert_eq!(plan(&before, &fewer).close, vec!["dashboard-1"]);
        assert_eq!(plan(&fewer, &before).open, vec![before[1].clone()]);
        assert_eq!(plan(&before, &[]), Plan::default());
    }

    #[test]
    fn the_first_show_covers_every_display() {
        let fake = Fake::with(&[BUILT_IN, EXTERNAL]);
        let mut dashboard = Dashboard::default();
        show(&mut dashboard, &fake, Mode::Live);
        assert_eq!(fake.covered(), frames(&[BUILT_IN, EXTERNAL], Mode::Live));
        assert_eq!(fake.raised.borrow().len(), 2);
    }

    #[test]
    fn the_same_displays_leave_the_windows_alone() {
        // What a brightness ramp announces: new screen parameters, the same
        // layout, many times a second.
        let fake = Fake::with(&[BUILT_IN, EXTERNAL]);
        let mut dashboard = Dashboard::default();
        show(&mut dashboard, &fake, Mode::Live);
        let labels = fake.labels();
        for _ in 0..30 {
            show(&mut dashboard, &fake, Mode::Live);
        }
        assert_eq!(fake.labels(), labels);
        assert!(fake.destroying.borrow().is_empty());
        assert_eq!(fake.raised.borrow().len(), 2);
    }

    #[test]
    fn a_display_back_before_its_old_window_is_gone_gets_a_new_one() {
        let fake = Fake::with(&[BUILT_IN, EXTERNAL]);
        let mut dashboard = Dashboard::default();
        show(&mut dashboard, &fake, Mode::Live);

        fake.set_displays(&[BUILT_IN]);
        show(&mut dashboard, &fake, Mode::Live);
        // The external display returns while its old window is still being
        // destroyed, and no further notice comes to try again.
        fake.set_displays(&[BUILT_IN, EXTERNAL]);
        show(&mut dashboard, &fake, Mode::Live);
        assert_eq!(fake.covered(), frames(&[BUILT_IN, EXTERNAL], Mode::Live));

        fake.finish_destroying();
        show(&mut dashboard, &fake, Mode::Live);
        assert_eq!(fake.covered(), frames(&[BUILT_IN, EXTERNAL], Mode::Live));
    }

    #[test]
    fn a_move_that_failed_is_tried_again() {
        let fake = Fake::with(&[BUILT_IN, EXTERNAL]);
        let mut dashboard = Dashboard::default();
        show(&mut dashboard, &fake, Mode::Live);

        let moved = Display {
            x: -2560,
            ..EXTERNAL
        };
        fake.set_displays(&[BUILT_IN, moved]);
        fake.fail_place.set(true);
        show(&mut dashboard, &fake, Mode::Live);
        fake.fail_place.set(false);
        show(&mut dashboard, &fake, Mode::Live);

        assert_eq!(fake.covered(), frames(&[BUILT_IN, moved], Mode::Live));
    }

    #[test]
    fn a_window_that_failed_to_open_opens_on_the_next_call() {
        let fake = Fake::with(&[BUILT_IN]);
        let mut dashboard = Dashboard::default();
        fake.fail_open.set(true);
        show(&mut dashboard, &fake, Mode::Live);
        assert!(fake.covered().is_empty());

        fake.fail_open.set(false);
        show(&mut dashboard, &fake, Mode::Live);
        assert_eq!(fake.covered(), frames(&[BUILT_IN], Mode::Live));
    }

    #[test]
    fn a_window_that_vanished_opens_again() {
        let fake = Fake::with(&[BUILT_IN]);
        let mut dashboard = Dashboard::default();
        show(&mut dashboard, &fake, Mode::Live);
        fake.windows.borrow_mut().clear();

        show(&mut dashboard, &fake, Mode::Live);
        assert_eq!(fake.covered(), frames(&[BUILT_IN], Mode::Live));
    }

    #[test]
    fn unreadable_displays_keep_the_windows_up() {
        let fake = Fake::with(&[BUILT_IN]);
        let mut dashboard = Dashboard::default();
        show(&mut dashboard, &fake, Mode::Live);
        fake.set_displays(&[]);

        show(&mut dashboard, &fake, Mode::Live);
        assert_eq!(fake.covered(), frames(&[BUILT_IN], Mode::Live));
    }

    #[test]
    fn a_preview_gives_way_to_the_live_dashboard() {
        let fake = Fake::with(&[BUILT_IN]);
        let mut dashboard = Dashboard::default();
        show(&mut dashboard, &fake, Mode::Preview);
        let preview = fake.labels();
        assert!(preview[0].starts_with(PREVIEW_PREFIX));

        show(&mut dashboard, &fake, Mode::Live);
        let live = fake.labels();
        assert_eq!(fake.covered(), frames(&[BUILT_IN], Mode::Live));
        assert!(live[0].starts_with(LABEL_PREFIX) && !live[0].starts_with(PREVIEW_PREFIX));
        assert_eq!(*fake.destroying.borrow(), preview);
    }

    #[test]
    fn hiding_closes_every_dashboard_window_and_the_next_show_starts_over() {
        let fake = Fake::with(&[BUILT_IN, EXTERNAL]);
        let mut dashboard = Dashboard::default();
        show(&mut dashboard, &fake, Mode::Live);
        let first = fake.labels();

        dashboard.hide(&fake);
        assert!(fake.covered().is_empty());
        // Shown again before the old windows are gone.
        show(&mut dashboard, &fake, Mode::Live);
        assert_eq!(fake.covered(), frames(&[BUILT_IN, EXTERNAL], Mode::Live));
        assert!(fake.labels().iter().all(|label| !first.contains(label)));
    }
}
