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
    Config {
        enabled: true,
        idle_minutes: 5,
    }
}

#[test]
fn config_defaults_to_off_and_five_minutes() {
    assert_eq!(
        Config::from_store_value(None),
        Config {
            enabled: false,
            idle_minutes: 5
        }
    );
}

#[test]
fn config_falls_back_to_defaults_for_a_broken_value() {
    assert_eq!(
        Config::from_store_value(Some(serde_json::json!("on"))),
        Config::default()
    );
}

#[test]
fn config_reads_the_preference_shape() {
    assert_eq!(
        Config::from_store_value(Some(
            serde_json::json!({ "enabled": true, "idleMinutes": 12 })
        )),
        Config {
            enabled: true,
            idle_minutes: 12
        }
    );
}

#[test]
fn config_reads_each_field_on_its_own_as_settings_does() {
    // A damaged minutes value keeps the switch the user turned on, as
    // sanitizeScreensaverConfig() keeps it in Settings.
    assert_eq!(
        Config::from_store_value(Some(
            serde_json::json!({ "enabled": true, "idleMinutes": "5" })
        )),
        Config {
            enabled: true,
            idle_minutes: 5
        }
    );
    assert_eq!(
        Config::from_store_value(Some(
            serde_json::json!({ "enabled": "yes", "idleMinutes": 9 })
        )),
        Config {
            enabled: false,
            idle_minutes: 9
        }
    );
}

#[test]
fn config_rounds_fractional_minutes_like_settings() {
    let config = Config::from_store_value(Some(
        serde_json::json!({ "enabled": true, "idleMinutes": 2.6 }),
    ));
    assert_eq!(config.idle_minutes, 3);
}

#[test]
fn config_clamps_idle_minutes_to_one_through_sixty() {
    let low = Config::from_store_value(Some(
        serde_json::json!({ "enabled": true, "idleMinutes": 0 }),
    ));
    let high = Config::from_store_value(Some(
        serde_json::json!({ "enabled": true, "idleMinutes": 600 }),
    ));
    assert_eq!(low.idle_minutes, 1);
    assert_eq!(high.idle_minutes, 60);
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

#[test]
fn nothing_happens_until_the_feature_is_on() {
    let mut machine = Machine::default();
    assert_eq!(machine.step(Event::Working(true)), vec![]);
    assert_eq!(machine.step(Event::Locked(false)), vec![]);
}

#[test]
fn working_with_the_feature_on_keeps_the_mac_awake() {
    let mut machine = Machine::default();
    assert_eq!(machine.step(Event::Config(enabled())), vec![]);
    assert_eq!(machine.step(Event::Working(true)), vec![Action::HoldAwake]);
    assert_eq!(machine.step(Event::Working(true)), vec![]);
    assert_eq!(
        machine.step(Event::Working(false)),
        vec![Action::ReleaseAwake]
    );
}

#[test]
fn turning_the_feature_off_releases_at_once() {
    let mut machine = Machine::default();
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
fn a_locked_screen_follows_the_os() {
    let mut machine = Machine::default();
    machine.step(Event::Config(enabled()));
    machine.step(Event::Working(true));
    assert_eq!(
        machine.step(Event::Locked(true)),
        vec![Action::ReleaseAwake]
    );
    assert_eq!(machine.step(Event::Working(true)), vec![]);
    assert_eq!(machine.step(Event::Locked(false)), vec![Action::HoldAwake]);
}

fn minutes(n: u64) -> Duration {
    Duration::from_secs(n * 60)
}

fn armed() -> Machine {
    let mut machine = Machine::default();
    machine.step(Event::Config(enabled()));
    machine.step(Event::Working(true));
    machine
}

#[test]
fn the_dashboard_shows_once_input_paused_for_the_configured_minutes() {
    let mut machine = armed();
    assert_eq!(machine.step(Event::Idle(minutes(4))), vec![]);
    assert_eq!(
        machine.step(Event::Idle(minutes(5))),
        vec![Action::ShowDashboard]
    );
    assert_eq!(machine.step(Event::Idle(minutes(6))), vec![]);
}

#[test]
fn no_dashboard_without_work_without_the_feature_or_while_locked() {
    let mut idle_only = Machine::default();
    idle_only.step(Event::Config(enabled()));
    assert_eq!(idle_only.step(Event::Idle(minutes(30))), vec![]);

    let mut off = Machine::default();
    off.step(Event::Working(true));
    assert_eq!(off.step(Event::Idle(minutes(30))), vec![]);

    let mut locked = armed();
    locked.step(Event::Locked(true));
    assert_eq!(locked.step(Event::Idle(minutes(30))), vec![]);
}

#[test]
fn the_dashboard_comes_down_when_work_ends() {
    let mut machine = armed();
    machine.step(Event::Idle(minutes(5)));
    assert_eq!(
        machine.step(Event::Working(false)),
        vec![Action::HideDashboard, Action::ReleaseAwake]
    );
}

#[test]
fn the_dashboard_comes_down_when_the_screen_locks_or_the_feature_turns_off() {
    let mut locked = armed();
    locked.step(Event::Idle(minutes(5)));
    assert_eq!(
        locked.step(Event::Locked(true)),
        vec![Action::HideDashboard, Action::ReleaseAwake]
    );

    let mut off = armed();
    off.step(Event::Idle(minutes(5)));
    assert_eq!(
        off.step(Event::Config(Config::default())),
        vec![Action::HideDashboard, Action::ReleaseAwake]
    );
}

#[test]
fn input_takes_the_dashboard_down_and_it_returns_after_another_pause() {
    let mut machine = armed();
    machine.step(Event::Idle(minutes(5)));
    assert_eq!(
        machine.step(Event::Idle(Duration::from_millis(200))),
        vec![Action::HideDashboard]
    );
    assert_eq!(machine.step(Event::Idle(minutes(1))), vec![]);
    assert_eq!(
        machine.step(Event::Idle(minutes(5))),
        vec![Action::ShowDashboard]
    );
}

#[test]
fn a_reading_from_before_work_started_never_shows_the_dashboard() {
    let mut machine = Machine::default();
    machine.step(Event::Config(enabled()));
    machine.step(Event::Working(true));
    machine.step(Event::Idle(minutes(9)));
    machine.step(Event::Working(false));
    // The user came back meanwhile; nothing sampled while work was off.
    assert_eq!(machine.step(Event::Working(true)), vec![Action::HoldAwake]);
    assert_eq!(machine.step(Event::Idle(Duration::from_secs(3))), vec![]);
}

#[test]
fn idle_is_sampled_only_while_armed_and_faster_while_showing() {
    let mut machine = Machine::default();
    assert_eq!(machine.poll_interval(), None);
    machine.step(Event::Config(enabled()));
    machine.step(Event::Working(true));
    assert_eq!(machine.poll_interval(), Some(IDLE_POLL));
    machine.step(Event::Idle(minutes(5)));
    assert_eq!(machine.poll_interval(), Some(INPUT_POLL));
    machine.step(Event::Locked(true));
    assert_eq!(machine.poll_interval(), None);
}

fn showing_with_lock(lock_available: bool) -> Machine {
    let mut machine = Machine::new(lock_available);
    machine.step(Event::Config(enabled()));
    machine.step(Event::Working(true));
    machine.step(Event::Idle(minutes(5)));
    assert!(machine.showing());
    machine
}

#[test]
fn input_locks_the_mac_and_the_dashboard_stays_until_the_lock_lands() {
    let mut machine = showing_with_lock(true);
    assert_eq!(
        machine.step(Event::Idle(Duration::from_millis(100))),
        vec![Action::LockScreen]
    );
    assert!(machine.showing());
    assert!(machine.awaiting_lock());
    // The lock screen is not up yet: nothing more is asked for.
    assert_eq!(machine.step(Event::LockSample(false)), vec![]);
    assert_eq!(
        machine.step(Event::Locked(true)),
        vec![Action::HideDashboard, Action::ReleaseAwake]
    );
    assert!(!machine.awaiting_lock());
}

#[test]
fn a_lock_read_from_the_session_counts_without_its_notification() {
    let mut machine = showing_with_lock(true);
    machine.step(Event::Idle(Duration::from_millis(100)));
    assert_eq!(
        machine.step(Event::LockSample(true)),
        vec![Action::HideDashboard, Action::ReleaseAwake]
    );
}

#[test]
fn without_a_lock_input_only_closes_the_dashboard() {
    let mut machine = showing_with_lock(false);
    assert_eq!(
        machine.step(Event::Idle(Duration::from_millis(100))),
        vec![Action::HideDashboard]
    );
}

/// Steps unconfirmed lock samples until something happens, returning the
/// sample number and the actions.
fn until_action(machine: &mut Machine) -> (u8, Vec<Action>) {
    for sample in 1..=LOCK_WAIT_SAMPLES {
        let actions = machine.step(Event::LockSample(false));
        if !actions.is_empty() {
            return (sample, actions);
        }
    }
    (LOCK_WAIT_SAMPLES + 1, vec![])
}

#[test]
fn a_lock_that_has_not_landed_is_asked_for_again_with_the_dashboard_up() {
    let mut machine = showing_with_lock(true);
    machine.step(Event::Idle(Duration::from_millis(100)));
    for _ in 1..LOCK_ATTEMPTS {
        assert_eq!(
            until_action(&mut machine),
            (LOCK_WAIT_SAMPLES, vec![Action::LockScreen])
        );
        assert!(machine.showing());
    }
}

#[test]
fn a_lock_that_never_lands_counts_as_no_lock_and_closes_the_dashboard() {
    let mut machine = showing_with_lock(true);
    machine.step(Event::Idle(Duration::from_millis(100)));
    for _ in 1..LOCK_ATTEMPTS {
        until_action(&mut machine);
    }
    assert_eq!(
        until_action(&mut machine),
        (LOCK_WAIT_SAMPLES, vec![Action::HideDashboard])
    );
    assert!(!machine.showing());
    assert!(!machine.awaiting_lock());
}

#[test]
fn idle_samples_never_end_the_wait_for_the_lock() {
    let mut machine = showing_with_lock(true);
    machine.step(Event::Idle(Duration::from_millis(100)));
    for _ in 0..u32::from(LOCK_WAIT_SAMPLES) * u32::from(LOCK_ATTEMPTS) {
        assert_eq!(machine.step(Event::Idle(Duration::from_millis(10))), vec![]);
    }
    assert!(machine.showing());
}

#[test]
fn the_dashboard_keeps_sampling_quickly_while_the_lock_comes_up() {
    let mut machine = showing_with_lock(true);
    machine.step(Event::Idle(Duration::from_millis(100)));
    assert_eq!(machine.poll_interval(), Some(INPUT_POLL));
}

fn ms(n: u64) -> Duration {
    Duration::from_millis(n)
}

#[test]
fn a_preview_shows_at_once_even_with_the_feature_off_and_no_work() {
    let mut machine = Machine::new(true);
    assert_eq!(machine.step(Event::Preview), vec![Action::ShowPreview]);
    assert!(machine.showing());
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
        assert_eq!(machine.step(Event::Idle(ms(idle))), vec![]);
    }
    assert_eq!(
        machine.step(Event::Idle(ms(idle - 100))),
        vec![Action::HideDashboard]
    );
    assert!(!machine.showing());
}

#[test]
fn a_preview_never_holds_the_mac_awake() {
    let mut machine = Machine::new(true);
    let actions = machine.step(Event::Preview);
    assert!(!actions.contains(&Action::HoldAwake));
    assert_eq!(machine.step(Event::Working(false)), vec![]);
    assert!(machine.showing());
}

#[test]
fn a_preview_closes_when_the_screen_locks() {
    let mut machine = Machine::new(true);
    machine.step(Event::Preview);
    assert_eq!(
        machine.step(Event::Locked(true)),
        vec![Action::HideDashboard]
    );
}

#[test]
fn a_preview_is_ignored_while_the_real_dashboard_shows() {
    let mut machine = showing_with_lock(true);
    assert_eq!(machine.step(Event::Preview), vec![]);
}
