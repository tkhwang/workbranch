//! The screensaver's decisions, free of the OS: events in, actions out.

use std::time::Duration;

use serde::Deserialize;

const DEFAULT_IDLE_MINUTES: u32 = 5;
const MIN_IDLE_MINUTES: u32 = 1;
const MAX_IDLE_MINUTES: u32 = 60;

/// Mirrors `ScreensaverConfig` in application/screensaver.ts, stored under
/// the `screensaver` preference key.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
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

    /// Reads each field on its own and falls back to that field's default,
    /// as `sanitizeScreensaverConfig()` does, so Settings and this service
    /// always read a damaged value the same way.
    pub(crate) fn from_store_value(value: Option<serde_json::Value>) -> Self {
        let defaults = Self::default();
        let field = |name: &str| value.as_ref().and_then(|value| value.get(name));
        Self {
            enabled: field("enabled")
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(defaults.enabled),
            // Rounded, then held to the bounds, like Math.round there.
            idle_minutes: field("idleMinutes")
                .and_then(serde_json::Value::as_f64)
                .map_or(defaults.idle_minutes, |minutes| {
                    minutes
                        .round()
                        .clamp(f64::from(MIN_IDLE_MINUTES), f64::from(MAX_IDLE_MINUTES))
                        as u32
                }),
        }
    }
}

const RUNTIME_SCHEMA_VERSION: u64 = 1;

/// The runtime v1 document (`WorkbranchRuntimeDocument` in packages/contract),
/// held to the contract as strictly as `parseRuntimeDocument()` holds it for
/// the board, so a document the board rejects keeps nothing awake.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RuntimeDocument {
    schema_version: u64,
    sessions: Vec<RuntimeSession>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
#[expect(
    dead_code,
    reason = "every field is checked against the contract; only state and observation are read"
)]
struct RuntimeSession {
    workspace: String,
    provider: Provider,
    session_id: String,
    agent_id: String,
    turn_id: String,
    state: SessionState,
    observation: Observation,
    reason: String,
    prompt: String,
    activity: String,
    response: String,
    outcome: String,
    updated_at: u64,
    state_changed_at: u64,
}

#[derive(Deserialize)]
#[serde(rename_all = "lowercase")]
enum Provider {
    Claude,
    Codex,
    Grok,
}

#[derive(Deserialize)]
#[serde(rename_all = "lowercase")]
enum SessionState {
    Running,
    Waiting,
    Finished,
    Idle,
}

#[derive(Deserialize)]
#[serde(rename_all = "lowercase")]
enum Observation {
    Observed,
    Uncertain,
    Stale,
}

/// "작업 중": an observed session that is running or waiting for the user,
/// the same reading as `runtimeRole()` in application/state.ts. A document
/// that breaks the contract counts as idle, so a broken or mismatched CLI
/// never pins the Mac awake.
pub(crate) fn is_working(document: &str) -> bool {
    serde_json::from_str::<RuntimeDocument>(document).is_ok_and(|document| {
        document.schema_version == RUNTIME_SCHEMA_VERSION
            && document.sessions.iter().any(|session| {
                matches!(session.observation, Observation::Observed)
                    && matches!(session.state, SessionState::Running | SessionState::Waiting)
            })
    })
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Event {
    Config(Config),
    /// Whether agents work, from a runtime document that was read.
    Working(bool),
    /// A runtime read failed, at this time since the Unix epoch.
    Unreadable(Duration),
    Locked(bool),
    /// The session's lock state, read on each sample while a requested lock
    /// is awaited, so the lock is confirmed even when its notification is late.
    LockSample(bool),
    /// How long since the last keyboard or mouse input, sampled while armed.
    Idle(Duration),
    /// Settings asked to show the dashboard now (COMP001 R12).
    Preview,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Action {
    /// Keeps the system from idle sleep, so agents go on working, with the
    /// screen locked or not (COMP001 R2).
    HoldAwake,
    ReleaseAwake,
    /// Keeps the display on, which also holds off the macOS screen saver and
    /// its lock, while the dashboard may show (R3, R4).
    HoldDisplay,
    ReleaseDisplay,
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
/// How long failed runtime reads keep the last reading of whether agents
/// work. A read can fail for a moment (a timeout, the CLI mid-upgrade) while
/// agents go on working; reads that keep failing must not pin the Mac awake.
pub(crate) const UNREADABLE_GRACE: Duration = Duration::from_secs(180);
/// Samples to wait for each lock request to land (~2 s).
pub(crate) const LOCK_WAIT_SAMPLES: u8 = 8;
/// Times the lock is asked for before this Mac counts as having none (~6 s).
pub(crate) const LOCK_ATTEMPTS: u8 = 3;
/// Samples a preview ignores input for, so the click that opened it and the
/// hand still on the mouse do not close it at once (~2 s).
pub(crate) const PREVIEW_GRACE_SAMPLES: u8 = 8;

#[derive(Clone, Copy, Debug)]
struct LockWait {
    /// Lock requests made so far.
    attempts: u8,
    /// Samples taken since the latest request.
    samples: u8,
}

#[derive(Debug, Default)]
pub(crate) struct Machine {
    config: Config,
    working: bool,
    /// When runtime reads started failing, while they keep failing.
    unreadable_since: Option<Duration>,
    locked: bool,
    /// Whether the system is held awake.
    awake: bool,
    /// Whether the display is held on.
    display: bool,
    dashboard: bool,
    /// The latest idle sample; dropped whenever the machine disarms, since
    /// nothing is sampled meanwhile and an old reading would misfire.
    idle: Option<Duration>,
    /// Whether macOS offers an immediate lock here (COMP001 R7).
    lock_available: bool,
    /// A lock asked for and not confirmed yet.
    lock_wait: Option<LockWait>,
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

    /// The feature is on and agents work: the system stays awake, even with
    /// the screen locked, since a lock stops no agent but sleep does (R2).
    fn keeps_awake(&self) -> bool {
        self.config.enabled && self.working
    }

    /// Armed: awake and the screen unlocked, so the display stays on and the
    /// dashboard may show. The display, screen saver and lock screen are
    /// otherwise left to the OS (R3, R5).
    fn armed(&self) -> bool {
        self.keeps_awake() && !self.locked
    }

    pub(crate) fn step(&mut self, event: Event) -> Vec<Action> {
        let mut input = false;
        match event {
            Event::Config(config) => self.config = config,
            Event::Working(working) => {
                self.working = working;
                self.unreadable_since = None;
            }
            Event::Unreadable(at) => {
                let since = *self.unreadable_since.get_or_insert(at);
                if at.saturating_sub(since) >= UNREADABLE_GRACE {
                    self.working = false;
                }
            }
            Event::Locked(locked) | Event::LockSample(locked) => self.locked = locked,
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
                Event::Locked(true) | Event::LockSample(true) => true,
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
            // The dashboard stays up until the session reads as locked, so the
            // desktop never shows and no key reaches the app underneath (R6).
            // A lock that has not landed is asked for again. One that never
            // lands means this Mac offers no lock after all: the dashboard
            // closes as it does without one (R7), rather than cover the
            // screen with no way back.
            if let (Event::LockSample(_), Some(wait)) = (event, self.lock_wait) {
                let samples = wait.samples.saturating_add(1);
                if samples < LOCK_WAIT_SAMPLES {
                    self.lock_wait = Some(LockWait { samples, ..wait });
                } else if wait.attempts < LOCK_ATTEMPTS {
                    self.lock_wait = Some(LockWait {
                        attempts: wait.attempts + 1,
                        samples: 0,
                    });
                    actions.push(Action::LockScreen);
                } else {
                    self.lock_wait = None;
                    self.dashboard = false;
                    actions.push(Action::HideDashboard);
                }
            }
        } else if self.dashboard && armed && input && self.lock_available {
            self.lock_wait = Some(LockWait {
                attempts: 1,
                samples: 0,
            });
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
        let awake = self.keeps_awake();
        if awake != self.awake {
            self.awake = awake;
            actions.push(if awake {
                Action::HoldAwake
            } else {
                Action::ReleaseAwake
            });
        }
        if armed != self.display {
            self.display = armed;
            actions.push(if armed {
                Action::HoldDisplay
            } else {
                Action::ReleaseDisplay
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

    /// A lock was asked for and has not landed: the service then samples the
    /// session's lock state instead of idle time.
    pub(crate) fn awaiting_lock(&self) -> bool {
        self.lock_wait.is_some()
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
