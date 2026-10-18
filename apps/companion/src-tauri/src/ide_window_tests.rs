use std::cell::RefCell;
use std::collections::HashSet;
use std::time::Duration;

use super::*;

fn frame(x: f64, y: f64, width: f64, height: f64) -> Frame {
    Frame {
        x,
        y,
        width,
        height,
    }
}

/// A laptop's area below the menu bar, at the global origin.
const LAPTOP: Frame = Frame {
    x: 0.0,
    y: 33.0,
    width: 1512.0,
    height: 949.0,
};
/// A larger display arranged to the laptop's left and higher up.
const EXTERNAL: Frame = Frame {
    x: -2560.0,
    y: -400.0,
    width: 2560.0,
    height: 1415.0,
};

#[derive(Default)]
struct FakeDesktop {
    windows: RefCell<Vec<(u32, Frame)>>,
    moves: RefCell<Vec<(u32, Frame)>>,
}

impl FakeDesktop {
    fn open(&self, id: u32, frame: Frame) {
        self.windows.borrow_mut().push((id, frame));
    }

    fn moves(&self) -> Vec<(u32, Frame)> {
        self.moves.borrow().clone()
    }
}

impl Desktop for FakeDesktop {
    type Handle = u32;

    fn ide_windows(&self) -> Vec<OpenWindow<u32>> {
        self.windows
            .borrow()
            .iter()
            .map(|&(id, frame)| OpenWindow {
                id,
                frame,
                handle: id,
            })
            .collect()
    }

    fn move_window(&self, handle: &u32, frame: Frame) {
        self.moves.borrow_mut().push((*handle, frame));
    }
}

#[test]
fn window_already_on_the_screen_stays() {
    let window = frame(100.0, 100.0, 1200.0, 800.0);

    assert_eq!(placement(window, LAPTOP), None);
}

#[test]
fn window_on_another_screen_moves_to_the_center_at_its_size() {
    let window = frame(-2400.0, -300.0, 1200.0, 800.0);

    assert_eq!(
        placement(window, LAPTOP),
        Some(frame(156.0, 108.0, 1200.0, 800.0))
    );
}

#[test]
fn window_reaching_into_the_screen_moves_when_its_center_is_elsewhere() {
    // The window's left part overlaps the laptop, but its center does not.
    let window = frame(-1000.0, 100.0, 1600.0, 800.0);

    assert_eq!(
        placement(window, LAPTOP),
        Some(frame(0.0, 108.0, 1512.0, 800.0))
    );
}

#[test]
fn window_larger_than_the_screen_shrinks_to_fit() {
    let window = frame(-2560.0, -400.0, 2560.0, 1415.0);

    assert_eq!(placement(window, LAPTOP), Some(LAPTOP));
}

#[test]
fn window_moves_onto_a_screen_left_of_and_above_the_main_display() {
    let window = frame(100.0, 100.0, 1200.0, 800.0);

    assert_eq!(
        placement(window, EXTERNAL),
        Some(frame(-1880.0, -93.0, 1200.0, 800.0))
    );
}

#[test]
fn screen_frame_turns_scaled_pixels_back_into_points() {
    // A Retina display at twice its point size, left of the main display.
    assert_eq!(screen_frame(-5120, -800, 5120, 2830, 2.0), Some(EXTERNAL));
    assert_eq!(screen_frame(0, 33, 1512, 949, 1.0), Some(LAPTOP));
}

#[test]
fn screen_frame_rejects_an_empty_area_or_scale() {
    assert_eq!(screen_frame(0, 0, 1512, 949, 0.0), None);
    assert_eq!(screen_frame(0, 0, 0, 949, 2.0), None);
}

#[test]
fn follower_leaves_windows_that_existed_before_the_command() {
    let desktop = FakeDesktop::default();
    desktop.open(7, frame(-2400.0, -300.0, 1200.0, 800.0));
    let mut follower = Follower::new(LAPTOP, HashSet::from([7]));

    assert_eq!(follower.step(&desktop), 0);
    assert_eq!(desktop.moves(), Vec::new());
}

#[test]
fn follower_moves_a_new_window_once() {
    let desktop = FakeDesktop::default();
    desktop.open(7, frame(-2400.0, -300.0, 1200.0, 800.0));
    let mut follower = Follower::new(LAPTOP, HashSet::new());

    assert_eq!(follower.step(&desktop), 1);
    // The fake keeps reporting the old frame, as if the user dragged the
    // window back; it is not moved a second time.
    assert_eq!(follower.step(&desktop), 0);
    assert_eq!(
        desktop.moves(),
        vec![(7, frame(156.0, 108.0, 1200.0, 800.0))]
    );
}

#[test]
fn follower_counts_a_new_window_already_on_the_screen_without_moving_it() {
    let desktop = FakeDesktop::default();
    desktop.open(8, frame(100.0, 100.0, 1200.0, 800.0));
    let mut follower = Follower::new(LAPTOP, HashSet::new());

    assert_eq!(follower.step(&desktop), 1);
    assert_eq!(desktop.moves(), Vec::new());
}

#[test]
fn follower_moves_each_window_of_a_task_as_it_appears() {
    let desktop = FakeDesktop::default();
    desktop.open(1, frame(100.0, 100.0, 1200.0, 800.0));
    let mut follower = Follower::new(LAPTOP, HashSet::from([1]));
    desktop.open(2, frame(-2400.0, -300.0, 1200.0, 800.0));

    assert_eq!(follower.step(&desktop), 1);
    desktop.open(3, frame(-1200.0, -300.0, 1000.0, 700.0));
    assert_eq!(follower.step(&desktop), 1);

    assert_eq!(
        desktop.moves(),
        vec![
            (2, frame(156.0, 108.0, 1200.0, 800.0)),
            (3, frame(256.0, 158.0, 1000.0, 700.0)),
        ]
    );
}

fn seconds(value: f64) -> Duration {
    Duration::from_secs_f64(value)
}

#[test]
fn following_continues_while_the_command_runs() {
    assert!(keep_following(None, None));
    assert!(keep_following(None, Some(seconds(30.0))));
}

#[test]
fn following_waits_for_a_starting_ide_until_the_limit() {
    assert!(keep_following(Some(seconds(9.9)), None));
    assert!(!keep_following(Some(seconds(10.0)), None));
}

#[test]
fn following_stops_once_new_windows_stop_arriving() {
    assert!(keep_following(Some(seconds(5.0)), Some(seconds(2.9))));
    assert!(!keep_following(Some(seconds(5.0)), Some(seconds(3.0))));
}

#[test]
fn quiet_time_counts_from_the_end_of_the_command() {
    // A window opened long before a multi-repo command finished; the other
    // repos' windows still get time after it.
    assert!(keep_following(Some(seconds(1.0)), Some(seconds(20.0))));
    assert!(!keep_following(Some(seconds(3.0)), Some(seconds(20.0))));
}

#[test]
fn every_supported_ide_is_listed_once() {
    let unique: HashSet<_> = IDE_BUNDLE_IDS.iter().collect();

    assert_eq!(unique.len(), IDE_BUNDLE_IDS.len());
    for bundle_id in [
        "dev.zed.Zed",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
        "com.google.antigravity-ide",
    ] {
        assert!(IDE_BUNDLE_IDS.contains(&bundle_id), "{bundle_id}");
    }
}

#[test]
fn the_settings_switch_is_on_only_when_stored_as_true() {
    let on = serde_json::json!({ "enabled": true });
    assert!(enabled_in_store_value(Some(&on)));

    for off in [
        serde_json::json!({ "enabled": false }),
        serde_json::json!({ "enabled": "yes" }),
        serde_json::json!({}),
        serde_json::json!(true),
    ] {
        assert!(!enabled_in_store_value(Some(&off)), "{off}");
    }
    // Stores from before the switch existed have no key at all.
    assert!(!enabled_in_store_value(None));
}
