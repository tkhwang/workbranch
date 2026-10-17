use super::*;
use std::time::Duration;

/// A session that meets the runtime v1 contract.
fn session(state: &str, observation: &str) -> serde_json::Value {
    serde_json::json!({
        "workspace": "/work/feat-x",
        "provider": "claude",
        "sessionId": "s1",
        "agentId": "",
        "turnId": "t1",
        "state": state,
        "observation": observation,
        "reason": "",
        "prompt": "",
        "activity": "",
        "response": "",
        "outcome": "",
        "updatedAt": 1_760_000_000,
        "stateChangedAt": 1_760_000_000,
    })
}

fn document(sessions: &[serde_json::Value]) -> String {
    serde_json::json!({ "schemaVersion": 1, "sessions": sessions }).to_string()
}

fn enabled() -> Config {
    Config { enabled: true }
}

#[test]
fn config_defaults_to_off() {
    assert_eq!(Config::from_store_value(None), Config { enabled: false });
}

#[test]
fn config_falls_back_to_off_for_a_broken_value() {
    assert_eq!(
        Config::from_store_value(Some(serde_json::json!("on"))),
        Config::default()
    );
    assert_eq!(
        Config::from_store_value(Some(serde_json::json!({ "enabled": "yes" }))),
        Config::default()
    );
}

#[test]
fn config_reads_the_switch_and_ignores_the_old_idle_minutes() {
    assert_eq!(
        Config::from_store_value(Some(
            serde_json::json!({ "enabled": true, "idleMinutes": 12 })
        )),
        enabled()
    );
}

#[test]
fn only_observed_running_or_waiting_sessions_count_as_working() {
    assert!(is_working(&document(&[session("running", "observed")])));
    assert!(is_working(&document(&[session("waiting", "observed")])));
    for (state, observation) in [
        ("running", "stale"),
        ("waiting", "uncertain"),
        ("finished", "observed"),
        ("idle", "observed"),
    ] {
        assert!(
            !is_working(&document(&[session(state, observation)])),
            "{state}/{observation}"
        );
    }
}

#[test]
fn one_working_session_among_others_is_enough() {
    assert!(is_working(&document(&[
        session("finished", "observed"),
        session("running", "observed"),
    ])));
}

#[test]
fn an_unreadable_document_is_not_working() {
    assert!(!is_working("not json"));
    assert!(!is_working(r#"{"schemaVersion":1}"#));
}

#[test]
fn a_document_from_another_schema_version_is_not_working() {
    let sessions = [session("running", "observed")];
    let document = serde_json::json!({ "schemaVersion": 2, "sessions": sessions });
    assert!(!is_working(&document.to_string()));
}

#[test]
fn a_document_the_board_would_reject_is_not_working() {
    // One session off the contract fails the whole document on the board,
    // so it keeps nothing awake here either.
    let mut broken = session("waiting", "observed");
    broken["provider"] = serde_json::json!("other");
    assert!(!is_working(&document(&[
        session("running", "observed"),
        broken
    ])));

    let mut missing = session("running", "observed");
    missing
        .as_object_mut()
        .map(|fields| fields.remove("turnId"));
    assert!(!is_working(&document(&[missing])));

    let mut negative = session("running", "observed");
    negative["updatedAt"] = serde_json::json!(-1);
    assert!(!is_working(&document(&[negative])));
}

fn secs(n: u64) -> Duration {
    Duration::from_secs(n)
}

fn ms(n: u64) -> Duration {
    Duration::from_millis(n)
}

fn minutes(n: u64) -> Duration {
    Duration::from_secs(n * 60)
}

fn unlocked(idle: Duration) -> Event {
    Event::Sample {
        idle,
        locked: false,
    }
}

fn locked(idle: Duration) -> Event {
    Event::Sample { idle, locked: true }
}

/// A runtime read time, as seconds since the epoch.
fn at(seconds: u64) -> Duration {
    Duration::from_secs(1_760_000_000 + seconds)
}

/// The feature on and agents working, at the desk.
fn working(lock_available: bool) -> Machine {
    let mut machine = Machine::new(lock_available);
    machine.step(Event::Config(enabled()));
    machine.step(Event::Working(true));
    machine.step(unlocked(secs(1)));
    machine
}

/// The dashboard up over a locked screen, past its input grace.
fn covering_the_lock_screen() -> Machine {
    let mut machine = working(true);
    machine.step(locked(secs(1)));
    assert_eq!(
        machine.step(locked(SHOW_AFTER)),
        vec![Action::ShowDashboard]
    );
    for n in 1..=u64::from(LIVE_GRACE_SAMPLES) {
        assert_eq!(machine.step(locked(SHOW_AFTER + ms(250 * n))), vec![]);
    }
    machine
}

#[test]
fn nothing_happens_until_the_feature_is_on() {
    let mut machine = Machine::new(true);
    assert_eq!(machine.step(Event::Working(true)), vec![]);
    assert_eq!(machine.step(Event::Saver(true)), vec![]);
    assert_eq!(machine.step(locked(minutes(10))), vec![]);
    assert_eq!(machine.poll_interval(), None);
}

#[test]
fn work_keeps_the_system_awake_and_leaves_the_display_to_macos() {
    let mut machine = Machine::new(true);
    assert_eq!(machine.step(Event::Config(enabled())), vec![]);
    assert_eq!(machine.step(Event::Working(true)), vec![Action::HoldAwake]);
    // No display hold at the desk: the macOS screen saver and its lock start
    // on their own schedule.
    assert_eq!(machine.step(unlocked(minutes(30))), vec![]);
    assert_eq!(machine.poll_interval(), Some(IDLE_POLL));
    assert_eq!(
        machine.step(Event::Working(false)),
        vec![Action::ReleaseAwake]
    );
    assert_eq!(machine.poll_interval(), None);
}

#[test]
fn turning_the_feature_off_releases_at_once() {
    let mut machine = Machine::new(true);
    machine.step(Event::Working(true));
    assert_eq!(
        machine.step(Event::Config(enabled())),
        vec![Action::HoldAwake]
    );
    assert_eq!(
        machine.step(Event::Config(Config::default())),
        vec![Action::ReleaseAwake]
    );
}

#[test]
fn the_screen_saver_gets_the_dashboard_on_top_and_a_lock_behind_it() {
    let mut machine = working(true);
    assert_eq!(machine.step(Event::Saver(true)), vec![Action::HoldDisplay]);
    // The screen saver starts only after a long pause: the dashboard covers
    // it on the next reading, and the session locks at once even when macOS
    // would wait before asking for the password.
    assert_eq!(
        machine.step(unlocked(minutes(5))),
        vec![Action::ShowDashboard, Action::LockScreen]
    );
    assert_eq!(machine.poll_interval(), Some(INPUT_POLL));
    assert_eq!(machine.step(locked(minutes(5) + ms(250))), vec![]);
    // The screen saver stopping behind the lock changes nothing.
    assert_eq!(machine.step(Event::Saver(false)), vec![]);
    assert!(machine.showing());
}

#[test]
fn a_lock_shows_the_dashboard_once_input_pauses() {
    let mut machine = working(true);
    // Locked by hand (Ctrl-Cmd-Q): the display stays on and the dashboard
    // waits until the hand leaves the keyboard.
    assert_eq!(machine.step(locked(secs(1))), vec![Action::HoldDisplay]);
    assert_eq!(machine.step(locked(secs(10))), vec![]);
    assert_eq!(
        machine.step(locked(SHOW_AFTER)),
        vec![Action::ShowDashboard]
    );
}

#[test]
fn input_uncovers_the_lock_screen_and_a_pause_brings_the_dashboard_back() {
    let mut machine = covering_the_lock_screen();
    assert_eq!(machine.step(locked(ms(100))), vec![Action::HideDashboard]);
    // The lock screen stays lit for its owner to sign in.
    assert_eq!(machine.poll_interval(), Some(IDLE_POLL));
    assert_eq!(machine.step(locked(secs(5))), vec![]);
    assert_eq!(
        machine.step(locked(SHOW_AFTER)),
        vec![Action::ShowDashboard]
    );
}

#[test]
fn input_right_after_the_dashboard_shows_is_ignored_over_the_lock() {
    let mut machine = working(true);
    machine.step(locked(secs(1)));
    machine.step(locked(SHOW_AFTER));
    for _ in 0..LIVE_GRACE_SAMPLES {
        assert_eq!(machine.step(locked(ms(10))), vec![]);
    }
    assert_eq!(machine.step(locked(ms(5))), vec![Action::HideDashboard]);
}

#[test]
fn signing_in_hands_the_screen_and_the_display_back() {
    let mut machine = working(true);
    machine.step(Event::Saver(true));
    machine.step(unlocked(minutes(5)));
    machine.step(locked(minutes(5) + ms(250)));
    assert_eq!(
        machine.step(unlocked(ms(100))),
        vec![Action::HideDashboard, Action::ReleaseDisplay]
    );
    // The screen saver's stop notification never came: signing in still
    // means it is gone.
    assert_eq!(machine.step(unlocked(SHOW_AFTER)), vec![]);
    assert!(!machine.showing());
}

#[test]
fn work_ending_under_the_dashboard_hands_everything_back_to_macos() {
    let mut machine = covering_the_lock_screen();
    assert_eq!(
        machine.step(Event::Working(false)),
        vec![
            Action::HideDashboard,
            Action::ReleaseAwake,
            Action::ReleaseDisplay
        ]
    );
    assert_eq!(machine.poll_interval(), None);
}

#[test]
fn work_starting_behind_the_lock_screen_brings_the_dashboard() {
    let mut machine = Machine::new(true);
    machine.step(Event::Config(enabled()));
    assert_eq!(machine.step(locked(minutes(3))), vec![]);
    assert_eq!(
        machine.step(Event::Working(true)),
        vec![Action::HoldAwake, Action::HoldDisplay]
    );
    assert_eq!(
        machine.step(locked(minutes(3))),
        vec![Action::ShowDashboard]
    );
}

#[test]
fn input_ends_a_screen_saver_with_no_lock_behind_it() {
    let mut machine = working(false);
    machine.step(Event::Saver(true));
    // Without a lock the dashboard still covers the screen saver.
    assert_eq!(
        machine.step(unlocked(minutes(5))),
        vec![Action::ShowDashboard]
    );
    // Input stops the screen saver, even if its stop notification is lost.
    assert_eq!(
        machine.step(unlocked(ms(100))),
        vec![Action::HideDashboard, Action::ReleaseDisplay]
    );
    assert_eq!(machine.step(unlocked(SHOW_AFTER)), vec![]);
}

#[test]
fn a_screen_saver_stopping_with_no_lock_uncovers_the_desktop() {
    let mut machine = working(false);
    machine.step(Event::Saver(true));
    machine.step(unlocked(minutes(5)));
    assert_eq!(
        machine.step(Event::Saver(false)),
        vec![Action::HideDashboard, Action::ReleaseDisplay]
    );
}

#[test]
fn a_desk_in_use_never_gets_the_dashboard() {
    let mut machine = working(true);
    for idle in [secs(2), secs(9), secs(1), secs(14), secs(3)] {
        assert_eq!(machine.step(unlocked(idle)), vec![]);
    }
    // Even locked, input that keeps coming keeps the dashboard away.
    machine.step(locked(secs(1)));
    for idle in [secs(4), secs(1), secs(14), secs(2)] {
        assert_eq!(machine.step(locked(idle)), vec![]);
    }
    assert!(!machine.showing());
}

#[test]
fn a_failed_read_keeps_the_last_reading_for_a_while() {
    let mut machine = covering_the_lock_screen();
    // A timeout or a CLI mid-upgrade: the dashboard and the holds stay.
    assert_eq!(machine.step(Event::Unreadable(at(0))), vec![]);
    assert_eq!(
        machine.step(Event::Unreadable(at(UNREADABLE_GRACE.as_secs() - 1))),
        vec![]
    );
    assert!(machine.showing());
}

#[test]
fn reads_that_keep_failing_never_pin_the_mac_awake() {
    let mut machine = covering_the_lock_screen();
    machine.step(Event::Unreadable(at(0)));
    assert_eq!(
        machine.step(Event::Unreadable(at(UNREADABLE_GRACE.as_secs()))),
        vec![
            Action::HideDashboard,
            Action::ReleaseAwake,
            Action::ReleaseDisplay
        ]
    );
}

#[test]
fn a_good_read_ends_the_grace() {
    let mut machine = working(true);
    machine.step(Event::Unreadable(at(0)));
    machine.step(Event::Working(true));
    // A new run of failures starts its own grace.
    assert_eq!(
        machine.step(Event::Unreadable(at(UNREADABLE_GRACE.as_secs()))),
        vec![]
    );
}

#[test]
fn a_failed_read_never_starts_work() {
    let mut machine = Machine::new(true);
    machine.step(Event::Config(enabled()));
    assert_eq!(machine.step(Event::Unreadable(at(0))), vec![]);
    assert_eq!(machine.poll_interval(), None);
}

#[test]
fn a_reading_from_before_work_started_never_counts() {
    let mut machine = Machine::new(true);
    machine.step(Event::Config(enabled()));
    machine.step(Event::Working(true));
    machine.step(locked(minutes(9)));
    machine.step(Event::Working(false));
    // Nothing is read while no agent works, so the old baseline is gone.
    machine.step(Event::Working(true));
    assert_eq!(machine.step(locked(secs(3))), vec![]);
    assert!(!machine.showing());
}

#[test]
fn the_session_is_read_while_agents_work_and_faster_under_the_dashboard() {
    let mut machine = Machine::new(true);
    assert_eq!(machine.poll_interval(), None);
    machine.step(Event::Config(enabled()));
    machine.step(Event::Working(true));
    assert_eq!(machine.poll_interval(), Some(IDLE_POLL));
    machine.step(locked(SHOW_AFTER));
    assert_eq!(machine.poll_interval(), Some(INPUT_POLL));
    machine.step(Event::Working(false));
    assert_eq!(machine.poll_interval(), None);
}

#[test]
fn a_preview_shows_at_once_even_with_the_feature_off_and_no_work() {
    let mut machine = Machine::new(true);
    assert_eq!(machine.step(Event::Preview), vec![Action::ShowPreview]);
    assert!(machine.showing());
    assert!(machine.previewing());
    assert_eq!(machine.poll_interval(), Some(INPUT_POLL));
}

#[test]
fn a_preview_ignores_input_for_its_grace_then_closes_without_locking() {
    let mut machine = Machine::new(true);
    machine.step(Event::Preview);
    // The hand still on the mouse after the click: every sample is input.
    let mut idle = 5_000;
    for _ in 0..PREVIEW_GRACE_SAMPLES {
        idle -= 100;
        assert_eq!(machine.step(unlocked(ms(idle))), vec![]);
    }
    assert_eq!(
        machine.step(unlocked(ms(idle - 100))),
        vec![Action::HideDashboard]
    );
    assert!(!machine.showing());
}

#[test]
fn a_preview_never_holds_the_mac_awake() {
    let mut machine = Machine::new(true);
    let actions = machine.step(Event::Preview);
    assert!(!actions.contains(&Action::HoldAwake));
    assert!(!actions.contains(&Action::HoldDisplay));
    assert_eq!(machine.step(Event::Working(false)), vec![]);
    assert!(machine.showing());
}

#[test]
fn a_preview_closes_when_the_screen_locks() {
    let mut machine = Machine::new(true);
    machine.step(Event::Preview);
    assert_eq!(machine.step(locked(secs(1))), vec![Action::HideDashboard]);
}

#[test]
fn a_preview_is_ignored_while_the_dashboard_shows() {
    let mut machine = covering_the_lock_screen();
    assert_eq!(machine.step(Event::Preview), vec![]);
    assert!(!machine.previewing());
}
