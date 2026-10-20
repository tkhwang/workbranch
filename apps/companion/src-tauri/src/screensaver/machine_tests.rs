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

/// A reading where macOS cannot be asked about its screen saver, so its
/// notifications alone tell. Readings default to the clock's start; tests
/// that measure `COVER_WITHOUT_WORK` pass their own time.
fn unlocked(idle: Duration) -> Event {
    Event::Sample {
        at: Duration::ZERO,
        idle,
        locked: false,
        saver: None,
    }
}

fn locked(idle: Duration) -> Event {
    locked_at(Duration::ZERO, idle)
}

/// A locked reading taken `at` on the service's clock.
fn locked_at(at: Duration, idle: Duration) -> Event {
    Event::Sample {
        at,
        idle,
        locked: true,
        saver: None,
    }
}

/// A reading that also asks whether the screen saver runs.
fn read(idle: Duration, locked: bool, saver: bool) -> Event {
    read_at(Duration::ZERO, idle, locked, saver)
}

fn read_at(at: Duration, idle: Duration, locked: bool, saver: bool) -> Event {
    Event::Sample {
        at,
        idle,
        locked,
        saver: Some(saver),
    }
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
fn the_screen_saver_gets_a_lock_behind_it_then_the_dashboard_on_top() {
    let mut machine = working(true);
    assert_eq!(machine.step(Event::Saver(true)), vec![Action::HoldDisplay]);
    // The screen saver starts only after a long pause, and macOS may wait
    // before asking for the password: the session locks first.
    assert_eq!(machine.step(unlocked(minutes(5))), vec![Action::LockScreen]);
    assert!(!machine.showing());
    assert_eq!(machine.poll_interval(), Some(INPUT_POLL));
    // The dashboard shows once the lock reads as landed.
    assert_eq!(
        machine.step(locked(minutes(5) + ms(250))),
        vec![Action::ShowDashboard]
    );
    // The screen saver stopping behind the lock changes nothing.
    assert_eq!(machine.step(Event::Saver(false)), vec![]);
    assert!(machine.showing());
}

/// Steps unlocked readings under a running screen saver until something
/// happens, returning how many readings it took and the actions.
fn until_action(machine: &mut Machine, from: Duration) -> (u8, Vec<Action>) {
    for sample in 1..=LOCK_WAIT_SAMPLES {
        let actions = machine.step(unlocked(from + ms(250 * u64::from(sample))));
        if !actions.is_empty() {
            return (sample, actions);
        }
    }
    (LOCK_WAIT_SAMPLES + 1, vec![])
}

#[test]
fn a_lock_that_has_not_landed_is_asked_for_again_without_the_dashboard() {
    let mut machine = working(true);
    machine.step(Event::Saver(true));
    machine.step(unlocked(minutes(5)));
    for attempt in 1..LOCK_ATTEMPTS {
        assert_eq!(
            until_action(&mut machine, minutes(5) + secs(u64::from(attempt) * 2)),
            (LOCK_WAIT_SAMPLES, vec![Action::LockScreen])
        );
        // Nothing claims a lock that is not there.
        assert!(!machine.showing());
    }
}

#[test]
fn a_lock_that_never_lands_leaves_the_screen_saver_to_macos() {
    let mut machine = working(true);
    machine.step(Event::Saver(true));
    machine.step(unlocked(minutes(5)));
    for attempt in 1..LOCK_ATTEMPTS {
        until_action(&mut machine, minutes(5) + secs(u64::from(attempt) * 2));
    }
    // Given up: no more requests and no dashboard over an unlocked screen,
    // but the display stays on for macOS to lock after its password delay.
    assert_eq!(
        until_action(&mut machine, minutes(6)),
        (LOCK_WAIT_SAMPLES + 1, vec![])
    );
    assert_eq!(machine.step(unlocked(minutes(7))), vec![]);
    assert!(!machine.showing());
    assert_eq!(machine.poll_interval(), Some(IDLE_POLL));
    // macOS locks on its own: the dashboard comes.
    assert_eq!(
        machine.step(locked(minutes(10))),
        vec![Action::ShowDashboard]
    );
}

#[test]
fn signing_in_never_locks_again_on_a_late_screen_saver_reading() {
    let mut machine = working(true);
    machine.step(read(minutes(5), false, true));
    machine.step(read(minutes(5) + ms(250), true, true));
    assert!(machine.showing());
    // Touch ID: the session unlocks with no keyboard or mouse input, and the
    // screen saver still reads as running for a moment.
    assert_eq!(
        machine.step(read(minutes(5) + ms(500), false, true)),
        vec![Action::HideDashboard, Action::ReleaseDisplay]
    );
    assert_eq!(
        machine.step(read(minutes(5) + secs(1), false, true)),
        vec![]
    );
    assert_eq!(
        machine.step(read(minutes(5) + secs(2), false, false)),
        vec![]
    );
    // A screen saver that starts afterwards is a new one.
    assert_eq!(
        machine.step(read(minutes(15), false, true)),
        vec![Action::LockScreen, Action::HoldDisplay]
    );
}

#[test]
fn a_new_screen_saver_after_signing_in_is_believed_from_its_notification() {
    let mut machine = working(true);
    machine.step(read(minutes(5), false, true));
    machine.step(read(minutes(5) + ms(250), true, true));
    machine.step(read(minutes(5) + ms(500), false, true));
    assert_eq!(machine.step(Event::Saver(true)), vec![Action::HoldDisplay]);
}

#[test]
fn a_screen_saver_already_running_is_read_from_the_session() {
    // Started (or restarted) mid screen saver: no notification will come.
    let mut machine = working(true);
    assert_eq!(
        machine.step(read(minutes(5), false, true)),
        vec![Action::LockScreen, Action::HoldDisplay]
    );
    assert_eq!(
        machine.step(read(minutes(5) + ms(250), true, true)),
        vec![Action::ShowDashboard]
    );
}

#[test]
fn the_session_corrects_a_screen_saver_notification() {
    let mut machine = working(true);
    machine.step(Event::Saver(true));
    // The session says no screen saver runs: nothing is held or shown.
    assert_eq!(
        machine.step(read(minutes(5), false, false)),
        vec![Action::ReleaseDisplay]
    );
    assert!(!machine.showing());
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
    assert!(machine.showing());
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
fn work_ending_under_the_dashboard_keeps_it_up_for_the_cover_time() {
    let mut machine = covering_the_lock_screen();
    // The results stay in view: nothing is taken down or released.
    assert_eq!(machine.step(Event::Working(false)), vec![]);
    assert!(machine.showing());
    // The clock starts on the next reading, not at the service's start.
    let ended = minutes(40);
    assert_eq!(machine.step(locked_at(ended, minutes(20))), vec![]);
    assert_eq!(
        machine.step(locked_at(ended + COVER_WITHOUT_WORK - secs(1), minutes(50))),
        vec![]
    );
    assert!(machine.showing());
    assert_eq!(
        machine.step(locked_at(ended + COVER_WITHOUT_WORK, minutes(50))),
        vec![
            Action::HideDashboard,
            Action::ReleaseAwake,
            Action::ReleaseDisplay
        ]
    );
    assert_eq!(machine.poll_interval(), None);
}

#[test]
fn work_starting_behind_a_spent_cover_brings_the_dashboard_back() {
    let mut machine = Machine::new(true);
    machine.step(Event::Config(enabled()));
    machine.step(locked_at(minutes(1), minutes(3)));
    machine.step(locked_at(minutes(1) + COVER_WITHOUT_WORK, minutes(33)));
    assert!(!machine.showing());
    assert_eq!(
        machine.step(Event::Working(true)),
        vec![Action::HoldAwake, Action::HoldDisplay]
    );
    assert_eq!(
        machine.step(locked_at(minutes(32), minutes(34))),
        vec![Action::ShowDashboard]
    );
}

#[test]
fn a_screen_saver_with_no_work_still_gets_the_lock_and_the_dashboard() {
    let mut machine = Machine::new(true);
    machine.step(Event::Config(enabled()));
    assert_eq!(machine.poll_interval(), None);
    // The screen saver's notification brings a reading.
    assert_eq!(
        machine.step(read_at(minutes(1), minutes(5), false, true)),
        vec![Action::LockScreen, Action::HoldAwake, Action::HoldDisplay]
    );
    assert_eq!(
        machine.step(read_at(minutes(1) + ms(250), minutes(5), true, true)),
        vec![Action::ShowDashboard]
    );
    assert_eq!(machine.poll_interval(), Some(INPUT_POLL));
}

#[test]
fn a_cover_with_no_work_gives_way_to_macos_and_stays_down() {
    let mut machine = Machine::new(true);
    machine.step(Event::Config(enabled()));
    let start = minutes(1);
    machine.step(locked_at(start, minutes(5)));
    assert!(machine.showing());
    assert_eq!(
        machine.step(locked_at(start + COVER_WITHOUT_WORK, minutes(35))),
        vec![
            Action::HideDashboard,
            Action::ReleaseAwake,
            Action::ReleaseDisplay
        ]
    );
    // Nothing is read until macOS says something changed, and a reading
    // under the same lock covers nothing again.
    assert_eq!(machine.poll_interval(), None);
    assert_eq!(
        machine.step(read_at(start + minutes(40), minutes(45), true, true)),
        vec![]
    );
    assert!(!machine.showing());
}

#[test]
fn switching_off_and_on_under_the_same_lock_keeps_a_spent_cover_down() {
    let mut machine = Machine::new(true);
    machine.step(Event::Config(enabled()));
    let start = minutes(1);
    machine.step(locked_at(start, minutes(5)));
    machine.step(locked_at(start + COVER_WITHOUT_WORK, minutes(35)));
    assert!(!machine.showing());
    machine.step(Event::Config(Config::default()));
    assert_eq!(machine.step(Event::Config(enabled())), vec![]);
    assert_eq!(
        machine.step(read_at(start + minutes(40), minutes(45), true, true)),
        vec![]
    );
    assert!(!machine.showing());
}

#[test]
fn signing_in_starts_a_new_cover_time() {
    let mut machine = Machine::new(true);
    machine.step(Event::Config(enabled()));
    machine.step(locked_at(minutes(1), minutes(5)));
    machine.step(locked_at(minutes(1) + COVER_WITHOUT_WORK, minutes(35)));
    machine.step(unlocked(ms(100)));
    // Locked again later: covered again, with the whole cover time ahead.
    assert_eq!(
        machine.step(locked_at(minutes(60), minutes(5))),
        vec![
            Action::ShowDashboard,
            Action::HoldAwake,
            Action::HoldDisplay
        ]
    );
    assert_eq!(
        machine.step(locked_at(
            minutes(60) + COVER_WITHOUT_WORK - secs(1),
            minutes(35)
        )),
        vec![]
    );
}

#[test]
fn work_resuming_and_ending_again_under_a_cover_restarts_its_time() {
    let mut machine = Machine::new(true);
    machine.step(Event::Config(enabled()));
    machine.step(locked_at(minutes(1), minutes(5)));
    machine.step(locked_at(minutes(20), minutes(24)));
    machine.step(Event::Working(true));
    machine.step(Event::Working(false));
    // The time counts from this reading, not from the cover's start.
    machine.step(locked_at(minutes(25), minutes(29)));
    assert_eq!(
        machine.step(locked_at(
            minutes(25) + COVER_WITHOUT_WORK - secs(1),
            minutes(59)
        )),
        vec![]
    );
    assert!(machine.showing());
    assert_eq!(
        machine.step(locked_at(minutes(25) + COVER_WITHOUT_WORK, minutes(60))),
        vec![
            Action::HideDashboard,
            Action::ReleaseAwake,
            Action::ReleaseDisplay
        ]
    );
}

#[test]
fn the_desk_with_no_work_is_left_to_macos() {
    let mut machine = Machine::new(true);
    machine.step(Event::Config(enabled()));
    assert_eq!(machine.step(unlocked(minutes(30))), vec![]);
    assert_eq!(machine.poll_interval(), None);
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
    // No longer working: the cover runs on its own time, then gives way.
    assert_eq!(
        machine.step(Event::Unreadable(at(UNREADABLE_GRACE.as_secs()))),
        vec![]
    );
    machine.step(locked_at(minutes(3), minutes(3)));
    assert_eq!(
        machine.step(locked_at(minutes(3) + COVER_WITHOUT_WORK, minutes(33))),
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
    machine.step(unlocked(minutes(9)));
    machine.step(Event::Working(false));
    // Nothing is read at the desk while no agent works, so the old baseline
    // is gone and the next reading is not taken for input.
    assert_eq!(machine.poll_interval(), None);
    machine.step(Event::Working(true));
    assert_eq!(machine.step(locked(secs(3))), vec![Action::HoldDisplay]);
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
    // Work ended, the cover has not: its time is read off the readings.
    machine.step(Event::Working(false));
    assert_eq!(machine.poll_interval(), Some(INPUT_POLL));
    machine.step(locked_at(minutes(1), minutes(1)));
    machine.step(locked_at(minutes(1) + COVER_WITHOUT_WORK, minutes(31)));
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
