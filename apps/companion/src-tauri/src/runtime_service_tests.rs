use super::*;
use std::ffi::OsString;

fn at(start: Instant, millis: u64) -> Instant {
    start + Duration::from_millis(millis)
}

#[test]
fn first_read_is_due_immediately() {
    let start = Instant::now();
    let schedule = Schedule::default();
    assert_eq!(schedule.due(start), start);
}

#[test]
fn quiet_store_is_read_again_after_the_fallback_interval() {
    let start = Instant::now();
    let mut schedule = Schedule::default();
    schedule.read_done(start);
    assert_eq!(schedule.due(at(start, 10)), start + FALLBACK_INTERVAL);
}

#[test]
fn a_change_is_read_after_the_store_settles() {
    let start = Instant::now();
    let mut schedule = Schedule::default();
    schedule.read_done(start);
    schedule.change(at(start, 1_000));
    schedule.change(at(start, 1_100));
    assert_eq!(schedule.due(at(start, 1_100)), at(start, 1_100) + DEBOUNCE);
}

#[test]
fn a_steady_stream_of_changes_still_reads_within_the_max_delay() {
    let start = Instant::now();
    let mut schedule = Schedule::default();
    schedule.read_done(start);
    for step in 0..20 {
        schedule.change(at(start, 1_000 + step * 100));
    }
    assert_eq!(schedule.due(at(start, 2_900)), at(start, 1_000) + MAX_DELAY);
}

#[test]
fn a_read_clears_pending_changes() {
    let start = Instant::now();
    let mut schedule = Schedule::default();
    schedule.read_done(start);
    schedule.change(at(start, 1_000));
    schedule.read_done(at(start, 1_300));
    assert_eq!(
        schedule.due(at(start, 1_400)),
        at(start, 1_300) + FALLBACK_INTERVAL
    );
}

#[test]
fn runtime_dir_prefers_the_collector_override() {
    assert_eq!(
        runtime_dir(
            Some(OsString::from("/tmp/wb-runtime")),
            Some(OsString::from("/Users/me"))
        ),
        Some(PathBuf::from("/tmp/wb-runtime"))
    );
}

#[test]
fn runtime_dir_ignores_an_empty_override() {
    assert_eq!(
        runtime_dir(Some(OsString::new()), Some(OsString::from("/Users/me"))),
        Some(PathBuf::from("/Users/me/.workbranch/runtime"))
    );
}

#[test]
fn runtime_dir_needs_home_without_an_override() {
    assert_eq!(runtime_dir(None, None), None);
}

#[test]
fn snapshot_carries_the_document_or_the_error() {
    let ok = snapshot_from(7, 1_000, Ok("{\"schemaVersion\":1}".into()));
    assert_eq!(ok.sequence, 7);
    assert_eq!(ok.read_at_ms, 1_000);
    assert_eq!(ok.document.as_deref(), Some("{\"schemaVersion\":1}"));
    assert_eq!(ok.error, None);

    let failed = snapshot_from(8, 2_000, Err("collector missing".into()));
    assert_eq!(failed.document, None);
    assert_eq!(failed.error.as_deref(), Some("collector missing"));
}

#[test]
fn snapshot_serializes_for_the_webview_contract() -> Result<(), serde_json::Error> {
    let value = serde_json::to_value(snapshot_from(1, 5, Ok("{}".into())))?;
    assert_eq!(
        value,
        serde_json::json!({ "sequence": 1, "readAtMs": 5, "document": "{}", "error": null })
    );
    Ok(())
}

#[test]
fn hub_keeps_the_latest_snapshot() {
    let hub = Hub::default();
    assert_eq!(hub.latest(), None);
    hub.publish(&snapshot_from(1, 10, Ok("a".into())));
    hub.publish(&snapshot_from(2, 20, Ok("b".into())));
    assert_eq!(hub.latest().map(|s| s.sequence), Some(2));
}

#[test]
fn a_new_subscriber_gets_the_latest_snapshot_then_updates() {
    let hub = Hub::default();
    hub.publish(&snapshot_from(1, 10, Ok("a".into())));
    let receiver = hub.subscribe();
    hub.publish(&snapshot_from(2, 20, Ok("b".into())));
    let sequences: Vec<u64> = receiver.try_iter().map(|s| s.sequence).collect();
    assert_eq!(sequences, vec![1, 2]);
}

#[test]
fn closed_subscribers_are_dropped() {
    let hub = Hub::default();
    drop(hub.subscribe());
    let live = hub.subscribe();
    hub.publish(&snapshot_from(1, 10, Ok("a".into())));
    assert_eq!(hub.subscriber_count(), 1);
    assert_eq!(live.try_iter().count(), 1);
}
