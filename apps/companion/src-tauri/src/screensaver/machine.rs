//! The screensaver's decisions, free of the OS: events in, actions out.

use std::time::Duration;

use serde::Deserialize;

const DEFAULT_IDLE_MINUTES: u32 = 5;
const MIN_IDLE_MINUTES: u32 = 1;
const MAX_IDLE_MINUTES: u32 = 60;

/// Mirrors `ScreensaverConfig` in application/screensaver.ts, stored under
/// the `screensaver` preference key.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase", default)]
pub(crate) struct Config {
    pub(crate) enabled: bool,
    pub(crate) idle_minutes: u32,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            enabled: false,
            idle_minutes: DEFAULT_IDLE_MINUTES,
        }
    }
}

impl Config {
    fn idle_after(self) -> Duration {
        Duration::from_secs(u64::from(self.idle_minutes) * 60)
    }

    pub(crate) fn from_store_value(value: Option<serde_json::Value>) -> Self {
        let config: Self = value
            .and_then(|value| serde_json::from_value(value).ok())
            .unwrap_or_default();
        Self {
            idle_minutes: config
                .idle_minutes
                .clamp(MIN_IDLE_MINUTES, MAX_IDLE_MINUTES),
            ..config
        }
    }
}

/// "작업 중": an observed session that is running or waiting for the user,
/// the same reading as `runtimeRole()` in application/state.ts. A document
/// that cannot be read counts as idle, so a broken CLI never pins the Mac awake.
pub(crate) fn is_working(document: &str) -> bool {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(document) else {
        return false;
    };
    value
        .get("sessions")
        .and_then(serde_json::Value::as_array)
        .is_some_and(|sessions| {
            sessions.iter().any(|session| {
                session
                    .get("observation")
                    .and_then(serde_json::Value::as_str)
                    == Some("observed")
                    && matches!(
                        session.get("state").and_then(serde_json::Value::as_str),
                        Some("running" | "waiting")
                    )
            })
        })
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Event {
    Config(Config),
    Working(bool),
    Locked(bool),
    /// How long since the last keyboard or mouse input, sampled while armed.
    Idle(Duration),
    /// Settings asked to show the dashboard now (COMP001 R12).
    Preview,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Action {
    HoldAwake,
    ReleaseAwake,
    ShowDashboard,
    HideDashboard,
    /// Hands the screen to the macOS lock (COMP001 R6).
    LockScreen,
    /// Shows the dashboard as a preview: input closes it, nothing locks.
    ShowPreview,
}

/// How often idle time is sampled while waiting to show the dashboard.
pub(crate) const IDLE_POLL: Duration = Duration::from_secs(1);
/// How often it is sampled while the dashboard shows, to catch input quickly.
pub(crate) const INPUT_POLL: Duration = Duration::from_millis(250);
/// Samples to wait for the lock screen before giving up on it (~2 s).
pub(crate) const LOCK_WAIT_SAMPLES: u8 = 8;
/// Samples a preview ignores input for, so the click that opened it and the
/// hand still on the mouse do not close it at once (~2 s).
pub(crate) const PREVIEW_GRACE_SAMPLES: u8 = 8;

#[derive(Debug, Default)]
pub(crate) struct Machine {
    config: Config,
    working: bool,
    locked: bool,
    awake: bool,
    dashboard: bool,
    /// The latest idle sample; dropped whenever the machine disarms, since
    /// nothing is sampled meanwhile and an old reading would misfire.
    idle: Option<Duration>,
    /// Whether macOS offers an immediate lock here (COMP001 R7).
    lock_available: bool,
    /// Samples taken since the lock was asked for, while waiting for it.
    lock_wait: Option<u8>,
    /// Samples taken since a preview opened, while it shows.
    preview: Option<u8>,
}

impl Machine {
    pub(crate) fn new(lock_available: bool) -> Self {
        Self {
            lock_available,
            ..Self::default()
        }
    }

    /// Armed: the feature is on, agents work and the screen is unlocked.
    /// Anything else is left to the OS (COMP001 R2, R5).
    fn armed(&self) -> bool {
        self.config.enabled && self.working && !self.locked
    }

    pub(crate) fn step(&mut self, event: Event) -> Vec<Action> {
        let mut input = false;
        match event {
            Event::Config(config) => self.config = config,
            Event::Working(working) => self.working = working,
            Event::Locked(locked) => self.locked = locked,
            Event::Idle(idle) => {
                input = self.idle.is_some_and(|previous| idle < previous);
                self.idle = Some(idle);
            }
            Event::Preview => {}
        }
        let armed = self.armed();
        if !armed && self.preview.is_none() {
            self.idle = None;
        }

        let mut actions = Vec::new();
        if let Some(samples) = self.preview {
            // A preview answers only to input after its grace, and to a lock.
            let closes = match event {
                Event::Idle(_) => {
                    let samples = samples.saturating_add(1);
                    self.preview = Some(samples);
                    input && samples > PREVIEW_GRACE_SAMPLES
                }
                Event::Locked(true) => true,
                _ => false,
            };
            if closes {
                self.preview = None;
                self.dashboard = false;
                actions.push(Action::HideDashboard);
            }
        } else if matches!(event, Event::Preview) && !self.dashboard {
            self.preview = Some(0);
            self.dashboard = true;
            // The first sample sets the baseline that input is measured from.
            self.idle = None;
            actions.push(Action::ShowPreview);
        } else if self.dashboard && armed && self.lock_wait.is_some() {
            // The dashboard stays up until the lock screen covers it, so the
            // desktop never shows and no key reaches the app underneath. If
            // the lock never lands, the dashboard closes anyway.
            if matches!(event, Event::Idle(_)) {
                let waited = self.lock_wait.map_or(1, |waited| waited.saturating_add(1));
                self.lock_wait = Some(waited);
                if waited >= LOCK_WAIT_SAMPLES {
                    self.lock_wait = None;
                    self.dashboard = false;
                    actions.push(Action::HideDashboard);
                }
            }
        } else if self.dashboard && armed && input && self.lock_available {
            self.lock_wait = Some(0);
            actions.push(Action::LockScreen);
        } else if self.dashboard && (!armed || input) {
            self.lock_wait = None;
            self.dashboard = false;
            actions.push(Action::HideDashboard);
        } else if !self.dashboard
            && armed
            && self
                .idle
                .is_some_and(|idle| idle >= self.config.idle_after())
        {
            self.dashboard = true;
            actions.push(Action::ShowDashboard);
        }
        if armed != self.awake {
            self.awake = armed;
            actions.push(if armed {
                Action::HoldAwake
            } else {
                Action::ReleaseAwake
            });
        }
        actions
    }

    pub(crate) fn showing(&self) -> bool {
        self.dashboard
    }

    pub(crate) fn previewing(&self) -> bool {
        self.preview.is_some()
    }

    /// When to sample idle time next; `None` while there is nothing to show.
    pub(crate) fn poll_interval(&self) -> Option<Duration> {
        if self.preview.is_some() {
            Some(INPUT_POLL)
        } else if !self.armed() {
            None
        } else if self.dashboard {
            Some(INPUT_POLL)
        } else {
            Some(IDLE_POLL)
        }
    }
}

#[cfg(test)]
#[path = "machine_tests.rs"]
mod tests;
