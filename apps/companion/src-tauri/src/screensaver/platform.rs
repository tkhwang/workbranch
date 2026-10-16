//! What the screensaver asks of the OS. The macOS implementation lives in
//! `macos.rs`; tests use the recording fake below.

use std::time::Duration;

use super::machine::Action;
use super::windows::Mode;

pub(crate) trait Platform {
    /// Keeps the display and the system from idle sleep, and the app out of
    /// App Nap, while held.
    fn set_awake(&mut self, awake: bool);
    /// Time since the last keyboard or mouse input, from any app.
    fn idle_time(&self) -> Duration;
    /// Covers every display with the dashboard.
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
    fn idle_time(&self) -> Duration {
        Duration::ZERO
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
        fn idle_time(&self) -> Duration {
            Duration::ZERO
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
                Action::ShowDashboard,
                Action::ShowPreview,
                Action::LockScreen,
                Action::HideDashboard,
                Action::ReleaseAwake,
            ],
        );
        assert_eq!(
            platform.0,
            vec![
                "awake=true",
                "show=Live",
                "show=Preview",
                "lock",
                "hide",
                "awake=false"
            ]
        );
    }
}
