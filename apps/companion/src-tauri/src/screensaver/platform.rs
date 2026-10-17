//! What the screensaver asks of the OS. The macOS implementation lives in
//! `macos.rs`; tests use the recording fake below.

use std::time::Duration;

use super::machine::Action;
use super::windows::Mode;

pub(crate) trait Platform {
    /// Keeps the system from idle sleep, and the app out of App Nap, while
    /// held.
    fn set_awake(&mut self, awake: bool);
    /// Keeps the display from idle sleep while held, so the dashboard stays
    /// in view over the screen saver or the lock screen.
    fn set_display_on(&mut self, on: bool);
    /// Time since the last keyboard or mouse input, from any app.
    fn idle_time(&self) -> Duration;
    /// Whether the login session's screen is locked right now.
    fn screen_locked(&self) -> bool;
    /// Whether the macOS screen saver runs right now; `None` where macOS
    /// cannot be asked, and its notifications alone tell.
    fn screen_saver_running(&self) -> Option<bool>;
    /// Covers every display with the dashboard, above the lock screen.
    fn show_dashboard(&mut self, mode: Mode);
    fn hide_dashboard(&mut self);
    /// Locks the login session at once, as Ctrl-Cmd-Q would.
    fn lock_screen(&mut self);
}

pub(crate) fn apply(platform: &mut impl Platform, actions: &[Action]) {
    for action in actions {
        match action {
            Action::HoldAwake => platform.set_awake(true),
            Action::ReleaseAwake => platform.set_awake(false),
            Action::HoldDisplay => platform.set_display_on(true),
            Action::ReleaseDisplay => platform.set_display_on(false),
            Action::ShowDashboard => platform.show_dashboard(Mode::Live),
            Action::ShowPreview => platform.show_dashboard(Mode::Preview),
            Action::HideDashboard => platform.hide_dashboard(),
            Action::LockScreen => platform.lock_screen(),
        }
    }
}

/// Stands in on systems without an integration; companion ships for macOS.
#[cfg(not(target_os = "macos"))]
#[derive(Default)]
pub(crate) struct NoopPlatform;

#[cfg(not(target_os = "macos"))]
impl Platform for NoopPlatform {
    fn set_awake(&mut self, _awake: bool) {}
    fn set_display_on(&mut self, _on: bool) {}
    fn idle_time(&self) -> Duration {
        Duration::ZERO
    }
    fn screen_locked(&self) -> bool {
        false
    }
    fn screen_saver_running(&self) -> Option<bool> {
        None
    }
    fn show_dashboard(&mut self, _mode: Mode) {}
    fn hide_dashboard(&mut self) {}
    fn lock_screen(&mut self) {}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Default)]
    struct Recording(Vec<String>);

    impl Platform for Recording {
        fn set_awake(&mut self, awake: bool) {
            self.0.push(format!("awake={awake}"));
        }
        fn set_display_on(&mut self, on: bool) {
            self.0.push(format!("display={on}"));
        }
        fn idle_time(&self) -> Duration {
            Duration::ZERO
        }
        fn screen_locked(&self) -> bool {
            false
        }
        fn screen_saver_running(&self) -> Option<bool> {
            None
        }
        fn show_dashboard(&mut self, mode: Mode) {
            self.0.push(format!("show={mode:?}"));
        }
        fn hide_dashboard(&mut self) {
            self.0.push("hide".into());
        }
        fn lock_screen(&mut self) {
            self.0.push("lock".into());
        }
    }

    #[test]
    fn actions_drive_the_platform_in_order() {
        let mut platform = Recording::default();
        apply(
            &mut platform,
            &[
                Action::HoldAwake,
                Action::HoldDisplay,
                Action::ShowDashboard,
                Action::ShowPreview,
                Action::LockScreen,
                Action::HideDashboard,
                Action::ReleaseDisplay,
                Action::ReleaseAwake,
            ],
        );
        assert_eq!(
            platform.0,
            vec![
                "awake=true",
                "display=true",
                "show=Live",
                "show=Preview",
                "lock",
                "hide",
                "display=false",
                "awake=false"
            ]
        );
    }
}
