//! The screensaver's decisions, free of the OS: events in, actions out.

use std::time::Duration;

use serde::Deserialize;

/// Mirrors `ScreensaverConfig` in application/screensaver.ts, stored under
/// the `screensaver` preference key.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(crate) struct Config {
    pub(crate) enabled: bool,
}

impl Config {
    /// Reads the switch and falls back to off, as
    /// `sanitizeScreensaverConfig()` does, so Settings and this service
    /// always read a damaged value the same way. Fields the feature no longer
    /// uses (`idleMinutes`) are ignored.
    pub(crate) fn from_store_value(value: Option<serde_json::Value>) -> Self {
        Self {
            enabled: value
                .as_ref()
                .and_then(|value| value.get("enabled"))
                .and_then(serde_json::Value::as_bool)
                .unwrap_or_default(),
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
    /// The macOS screen saver started (`true`) or stopped (`false`), as its
    /// notifications tell, where the session cannot be asked.
    Saver(bool),
    /// A reading of the session, taken on every poll and whenever macOS says
    /// the screen locked or unlocked or the screen saver started or stopped:
    /// time since the last keyboard or mouse input, whether the session reads
    /// as locked, and whether its screen saver runs (`None` where macOS
    /// cannot be asked). The session, not a notification, is the truth, so a
    /// stray or missed notification never misleads the machine.
    Sample {
        idle: Duration,
        locked: bool,
        saver: Option<bool>,
    },
    /// Settings asked to show the dashboard now (COMP001 R12).
    Preview,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Action {
    /// Keeps the system from idle sleep, so agents go on working, with the
    /// screen locked or not (COMP001 R2).
    HoldAwake,
    ReleaseAwake,
    /// Keeps the display on while the screen saver or the lock screen is up,
    /// so the dashboard stays in view (COMP002 R2).
    HoldDisplay,
    ReleaseDisplay,
    /// Shows the dashboard above the screen saver and the lock screen.
    ShowDashboard,
    HideDashboard,
    /// Asks for the session lock, so the dashboard never covers a screen
    /// saver that would end without a password (COMP002 R3).
    LockScreen,
    /// Shows the dashboard as a preview: input closes it, nothing locks.
    ShowPreview,
}

/// How often the session is read while agents work.
pub(crate) const IDLE_POLL: Duration = Duration::from_secs(1);
/// How often it is read while the dashboard shows or a lock is awaited, to
/// catch input and the lock quickly.
pub(crate) const INPUT_POLL: Duration = Duration::from_millis(250);
/// How long input must pause, with the screen saver or the lock screen up,
/// before the dashboard shows. Someone typing the password keeps it away;
/// the screen saver itself starts after a far longer pause, so it is
/// covered at once.
pub(crate) const SHOW_AFTER: Duration = Duration::from_secs(15);
/// How long failed runtime reads keep the last reading of whether agents
/// work. A read can fail for a moment (a timeout, the CLI mid-upgrade) while
/// agents go on working; reads that keep failing must not pin the Mac awake.
pub(crate) const UNREADABLE_GRACE: Duration = Duration::from_secs(180);
/// Samples to wait for each lock request to land (~2 s).
pub(crate) const LOCK_WAIT_SAMPLES: u8 = 8;
/// Times the lock is asked for before giving up on it for this screen saver
/// (~6 s).
pub(crate) const LOCK_ATTEMPTS: u8 = 3;
/// Samples the dashboard ignores input for once it shows over the lock
/// screen (~1 s), so a stray reading while macOS raises the lock screen
/// never takes it straight down again.
pub(crate) const LIVE_GRACE_SAMPLES: u8 = 4;
/// Samples a preview ignores input for, so the click that opened it and the
/// hand still on the mouse do not close it at once (~2 s).
pub(crate) const PREVIEW_GRACE_SAMPLES: u8 = 8;

/// What covers the screen, with the samples taken since it showed.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
enum Shown {
    #[default]
    Nothing,
    Live(u8),
    Preview(u8),
}

/// Where the lock asked for under a running screen saver stands.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
enum LockRequest {
    /// Nothing asked for.
    #[default]
    None,
    /// Asked for `attempts` times, the latest `samples` readings ago.
    Awaiting { attempts: u8, samples: u8 },
    /// Never landed: left to macOS until this screen saver ends.
    GaveUp,
}

#[derive(Debug, Default)]
pub(crate) struct Machine {
    config: Config,
    working: bool,
    /// When runtime reads started failing, while they keep failing.
    unreadable_since: Option<Duration>,
    /// Whether the login session reads as locked.
    locked: bool,
    /// Whether the macOS screen saver runs.
    saver: bool,
    /// Set when someone signs in. A reading that the screen saver still runs
    /// is not believed again until one reads it stopped or a new one starts,
    /// so a late reading never locks the Mac just after it was unlocked
    /// (Touch ID leaves no keyboard or mouse input to hold the lock off).
    saver_stale: bool,
    /// Whether the system is held awake.
    awake: bool,
    /// Whether the display is held on.
    display: bool,
    shown: Shown,
    lock_request: LockRequest,
    /// The latest idle sample; dropped whenever nothing is sampled, since an
    /// old reading would look like input.
    idle: Option<Duration>,
    /// Whether macOS offers an immediate lock here (COMP001 R7).
    lock_available: bool,
}

impl Machine {
    pub(crate) fn new(lock_available: bool) -> Self {
        Self {
            lock_available,
            ..Self::default()
        }
    }

    /// The feature is on and agents work: the system stays awake, even with
    /// the screen locked, since a lock stops no agent but sleep does.
    fn keeps_awake(&self) -> bool {
        self.config.enabled && self.working
    }

    /// Covered: agents work and macOS has put up its screen saver or its
    /// lock screen. The display then stays on and the dashboard shows on
    /// top. Until then nothing here holds the display, so the screen saver,
    /// the lock and display sleep follow the macOS settings.
    fn covered(&self) -> bool {
        self.keeps_awake() && (self.locked || self.saver)
    }

    /// Whether the dashboard may show now. Where the Mac can lock, only over
    /// a session that reads as locked, so the dashboard never claims a lock
    /// that is not there and input never reveals the desktop without a
    /// password (COMP002 R3).
    fn may_show(&self) -> bool {
        self.covered() && (self.locked || !self.lock_available)
    }

    fn read_session(&mut self, idle: Duration, locked: bool, saver: Option<bool>) -> bool {
        let input = self.idle.is_some_and(|previous| idle < previous);
        self.idle = Some(idle);
        if self.locked && !locked {
            // Someone signed in: no screen saver runs behind the desktop.
            self.saver = false;
            self.saver_stale = true;
        }
        self.locked = locked;
        if let Some(saver) = saver {
            if !saver {
                self.saver_stale = false;
            }
            self.saver = saver && !self.saver_stale;
        }
        if input && !self.locked {
            // Input ends a screen saver that has no lock behind it, even if
            // its stop notification never comes.
            self.saver = false;
        }
        input
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
            Event::Saver(running) => {
                if running {
                    // A new screen saver, not a late reading of the old one.
                    self.saver_stale = false;
                }
                self.saver = running;
            }
            Event::Sample {
                idle,
                locked,
                saver,
            } => input = self.read_session(idle, locked, saver),
            Event::Preview => {}
        }
        let covered = self.covered();
        let sampled = matches!(event, Event::Sample { .. });
        if !covered || self.locked {
            // A lock request ends with the lock or with the screen saver.
            self.lock_request = LockRequest::None;
        }

        let mut actions = Vec::new();
        match self.shown {
            Shown::Preview(samples) if sampled => {
                // A preview answers only to input after its grace, and to a
                // lock.
                let samples = samples.saturating_add(1);
                self.shown = Shown::Preview(samples);
                if (input && samples > PREVIEW_GRACE_SAMPLES) || self.locked {
                    self.shown = Shown::Nothing;
                    actions.push(Action::HideDashboard);
                }
            }
            Shown::Preview(_) => {}
            Shown::Live(_) if !self.may_show() => {
                self.shown = Shown::Nothing;
                actions.push(Action::HideDashboard);
            }
            Shown::Live(samples) if sampled => {
                // Input uncovers the lock screen, so its owner can sign in.
                let samples = samples.saturating_add(1);
                self.shown = Shown::Live(samples);
                if input && samples > LIVE_GRACE_SAMPLES {
                    self.shown = Shown::Nothing;
                    actions.push(Action::HideDashboard);
                }
            }
            Shown::Live(_) => {}
            Shown::Nothing if matches!(event, Event::Preview) => {
                self.shown = Shown::Preview(0);
                // The first sample sets the baseline input is measured from.
                self.idle = None;
                actions.push(Action::ShowPreview);
            }
            Shown::Nothing => {
                let paused = self.idle.is_some_and(|idle| idle >= SHOW_AFTER);
                if paused && self.may_show() {
                    self.shown = Shown::Live(0);
                    actions.push(Action::ShowDashboard);
                } else if paused && covered && sampled {
                    // The screen saver runs and macOS has not locked yet:
                    // lock first, and show once the lock reads as landed.
                    self.ask_for_lock(&mut actions);
                }
            }
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
        if covered != self.display {
            self.display = covered;
            actions.push(if covered {
                Action::HoldDisplay
            } else {
                Action::ReleaseDisplay
            });
        }
        if self.poll_interval().is_none() {
            self.idle = None;
        }
        actions
    }

    /// Asks for the lock, again every `LOCK_WAIT_SAMPLES` readings that do
    /// not find it, up to `LOCK_ATTEMPTS` times. A lock that never lands is
    /// left to macOS, which locks on its own once its password delay ends;
    /// the dashboard waits for that, with the display kept on.
    fn ask_for_lock(&mut self, actions: &mut Vec<Action>) {
        self.lock_request = match self.lock_request {
            LockRequest::None => {
                actions.push(Action::LockScreen);
                LockRequest::Awaiting {
                    attempts: 1,
                    samples: 0,
                }
            }
            LockRequest::Awaiting { attempts, samples } => {
                let samples = samples.saturating_add(1);
                if samples < LOCK_WAIT_SAMPLES {
                    LockRequest::Awaiting { attempts, samples }
                } else if attempts < LOCK_ATTEMPTS {
                    actions.push(Action::LockScreen);
                    LockRequest::Awaiting {
                        attempts: attempts + 1,
                        samples: 0,
                    }
                } else {
                    LockRequest::GaveUp
                }
            }
            LockRequest::GaveUp => LockRequest::GaveUp,
        };
    }

    pub(crate) fn showing(&self) -> bool {
        self.shown != Shown::Nothing
    }

    pub(crate) fn previewing(&self) -> bool {
        matches!(self.shown, Shown::Preview(_))
    }

    /// When to read the session next; `None` while nothing could change.
    pub(crate) fn poll_interval(&self) -> Option<Duration> {
        if self.showing() || matches!(self.lock_request, LockRequest::Awaiting { .. }) {
            Some(INPUT_POLL)
        } else if self.keeps_awake() {
            Some(IDLE_POLL)
        } else {
            None
        }
    }
}

#[cfg(test)]
#[path = "machine_tests.rs"]
mod tests;
