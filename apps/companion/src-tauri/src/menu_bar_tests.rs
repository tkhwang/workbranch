use super::*;
use crate::usage::{LimitWindow, TokenCounts, UsageBucket};

const NOW: u64 = 1_800_000_000;
const TODAY: u64 = NOW - 10 * 3_600;

fn window(window_minutes: u64, used_percent: f64, resets_at: Option<u64>) -> LimitWindow {
    LimitWindow {
        window_minutes,
        used_percent,
        resets_at,
    }
}

fn limits(age: u64, windows: Vec<LimitWindow>) -> Option<ProviderLimits> {
    Some(ProviderLimits {
        observed_at: NOW - age,
        plan: None,
        windows,
    })
}

fn provider(limits: Option<ProviderLimits>, buckets: Vec<(u64, u64)>) -> ProviderUsage {
    ProviderUsage {
        available: limits.is_some() || !buckets.is_empty(),
        limits,
        buckets: buckets
            .into_iter()
            .map(|(start, input)| UsageBucket {
                start,
                tokens: TokenCounts {
                    input,
                    output: 0,
                    cache_read: 0,
                    cache_write: 0,
                },
            })
            .collect(),
        errors: Vec::new(),
    }
}

fn snapshot(claude: ProviderUsage, codex: ProviderUsage) -> UsageSnapshot {
    UsageSnapshot {
        generated_at: NOW,
        since: NOW - 15 * 86_400,
        claude,
        codex,
    }
}

fn all() -> MenuBarConfig {
    MenuBarConfig::default()
}

fn title(config: MenuBarConfig, snapshot: &UsageSnapshot) -> Option<String> {
    menu_bar_title(config, snapshot, NOW, TODAY)
}

fn fresh_pair() -> UsageSnapshot {
    snapshot(
        provider(
            limits(
                60,
                vec![
                    window(300, 42.4, Some(NOW + 3_600)),
                    window(10_080, 63.0, Some(NOW + 86_400)),
                ],
            ),
            vec![(TODAY - 900, 5_000_000), (TODAY, 20_000_000)],
        ),
        provider(
            limits(60, vec![window(10_080, 18.0, Some(NOW + 86_400))]),
            vec![(TODAY + 900, 11_000_000)],
        ),
    )
}

#[test]
fn every_item_shows_used_percent_and_todays_tokens_by_default() {
    assert_eq!(
        title(all(), &fresh_pair()),
        Some("CL 42·63  CO 18 · 31.0M".to_owned())
    );
}

#[test]
fn remaining_basis_subtracts_from_one_hundred() {
    let config = MenuBarConfig {
        percent: PercentBasis::Remaining,
        ..all()
    };
    assert_eq!(
        title(config, &fresh_pair()),
        Some("CL 58·37  CO 82 · 31.0M".to_owned())
    );
}

#[test]
fn every_item_off_shows_icon_only() {
    let config = MenuBarConfig {
        claude_5h: false,
        claude_weekly: false,
        codex_weekly: false,
        today_tokens: false,
        percent: PercentBasis::Used,
    };
    assert!(config.is_icon_only());
    assert_eq!(title(config, &fresh_pair()), None);
}

#[test]
fn single_items_stand_alone() {
    let none = MenuBarConfig {
        claude_5h: false,
        claude_weekly: false,
        codex_weekly: false,
        today_tokens: false,
        ..all()
    };
    let claude_5h = MenuBarConfig {
        claude_5h: true,
        ..none
    };
    let tokens = MenuBarConfig {
        today_tokens: true,
        ..none
    };
    let codex = MenuBarConfig {
        codex_weekly: true,
        ..none
    };
    assert_eq!(title(claude_5h, &fresh_pair()), Some("CL 42".to_owned()));
    assert_eq!(title(tokens, &fresh_pair()), Some("31.0M".to_owned()));
    assert_eq!(title(codex, &fresh_pair()), Some("CO 18".to_owned()));
}

#[test]
fn stale_short_window_shows_a_dash_beside_fresh_weekly() {
    let usage = snapshot(
        provider(
            limits(
                2 * 3_600,
                vec![
                    window(300, 90.0, Some(NOW + 3_600)),
                    window(10_080, 40.0, Some(NOW + 86_400)),
                ],
            ),
            Vec::new(),
        ),
        provider(None, Vec::new()),
    );
    assert_eq!(title(all(), &usage), Some("CL –·40 · 0".to_owned()));
}

#[test]
fn stale_weekly_shows_a_dash_too() {
    let usage = snapshot(
        provider(
            limits(7 * 3_600, vec![window(10_080, 63.0, Some(NOW + 86_400))]),
            vec![(TODAY, 1_500)],
        ),
        provider(
            limits(60, vec![window(10_080, 18.0, Some(NOW + 86_400))]),
            Vec::new(),
        ),
    );
    assert_eq!(
        title(all(), &usage),
        Some("CL –·–  CO 18 · 1.5k".to_owned())
    );
}

#[test]
fn passed_reset_reads_as_zero_even_when_old() {
    let usage = snapshot(
        provider(
            limits(10 * 3_600, vec![window(300, 95.0, Some(NOW - 60))]),
            Vec::new(),
        ),
        provider(None, Vec::new()),
    );
    let config = MenuBarConfig {
        claude_weekly: false,
        today_tokens: false,
        ..all()
    };
    assert_eq!(title(config, &usage), Some("CL 0".to_owned()));
}

#[test]
fn codex_weekly_is_its_longest_window() {
    let usage = snapshot(
        provider(None, Vec::new()),
        provider(
            limits(
                60,
                vec![
                    window(300, 70.0, Some(NOW + 3_600)),
                    window(10_080, 18.0, Some(NOW + 86_400)),
                ],
            ),
            Vec::new(),
        ),
    );
    let config = MenuBarConfig {
        today_tokens: false,
        ..all()
    };
    assert_eq!(title(config, &usage), Some("CO 18".to_owned()));
}

#[test]
fn missing_agent_is_left_out() {
    let usage = snapshot(
        provider(None, Vec::new()),
        provider(
            limits(60, vec![window(10_080, 18.0, Some(NOW + 86_400))]),
            vec![(TODAY, 2_000_000)],
        ),
    );
    assert_eq!(title(all(), &usage), Some("CO 18 · 2.0M".to_owned()));
}

#[test]
fn no_data_shows_icon_only() {
    let usage = snapshot(provider(None, Vec::new()), provider(None, Vec::new()));
    assert_eq!(title(all(), &usage), None);
}

#[test]
fn format_tokens_matches_usage_view_steps() {
    assert_eq!(format_tokens(0), "0");
    assert_eq!(format_tokens(999), "999");
    assert_eq!(format_tokens(1_500), "1.5k");
    assert_eq!(format_tokens(42_400), "42k");
    assert_eq!(format_tokens(31_000_000), "31.0M");
    assert_eq!(format_tokens(250_400_000), "250M");
    assert_eq!(format_tokens(1_234_000_000), "1.23B");
}

#[test]
fn store_value_fills_missing_or_invalid_fields_with_defaults() {
    assert_eq!(
        MenuBarConfig::from_store_value(Some(serde_json::json!({
            "claude5h": false,
            "percent": "remaining",
        }))),
        MenuBarConfig {
            claude_5h: false,
            percent: PercentBasis::Remaining,
            ..all()
        }
    );
    assert_eq!(
        MenuBarConfig::from_store_value(Some(serde_json::json!({ "percent": "left" }))),
        all()
    );
    assert_eq!(MenuBarConfig::from_store_value(None), all());
}

#[test]
fn local_midnight_is_within_the_last_day() {
    let midnight = local_midnight(NOW);
    assert!(midnight <= NOW);
    // 25h covers a DST fall-back day.
    assert!(NOW - midnight < 25 * 3_600);
}
