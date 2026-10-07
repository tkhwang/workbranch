use super::*;
use std::io::Write;
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_TEMP_DIR: AtomicU64 = AtomicU64::new(0);

fn temp_dir() -> Result<PathBuf, Box<dyn std::error::Error>> {
    let suffix = NEXT_TEMP_DIR.fetch_add(1, Ordering::Relaxed);
    let path = std::env::temp_dir().join(format!(
        "wb-usage-test-{}-{suffix}-{}",
        std::process::id(),
        now_epoch()
    ));
    fs::create_dir_all(&path)?;
    Ok(path)
}

fn write_lines(path: &Path, lines: &[&str]) -> Result<(), Box<dyn std::error::Error>> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut file = File::create(path)?;
    for line in lines {
        writeln!(file, "{line}")?;
    }
    Ok(())
}

fn codex_sum(usage: &FileUsage) -> TokenCounts {
    let mut sum = TokenCounts::default();
    for event in &usage.codex_events {
        sum.add(event.counts);
    }
    sum
}

fn codex_event(at: &str, total: (u64, u64, u64), last: Option<(u64, u64, u64)>) -> String {
    let tokens = |(input, cached, output): (u64, u64, u64)| {
        format!(
            r#"{{"input_tokens":{input},"cached_input_tokens":{cached},"output_tokens":{output},"total_tokens":{}}}"#,
            input + output
        )
    };
    let last = last.map_or_else(|| "null".to_string(), tokens);
    format!(
        r#"{{"timestamp":"{at}","type":"event_msg","payload":{{"type":"token_count","info":{{"total_token_usage":{},"last_token_usage":{last}}},"rate_limits":null}}}}"#,
        tokens(total)
    )
}

fn paths(root: &Path) -> UsagePaths {
    UsagePaths {
        claude_config: root.join(".claude.json"),
        claude_dir: root.join(".claude"),
        codex_dir: root.join(".codex"),
    }
}

// 2026-10-06T21:32:40Z
const AT: u64 = 1_791_322_360;

#[test]
fn parses_rfc3339_with_fraction_and_offsets() {
    assert_eq!(parse_rfc3339("2026-10-06T21:32:40.149Z"), Some(AT));
    assert_eq!(parse_rfc3339("2026-10-06T21:32:40Z"), Some(AT));
    assert_eq!(parse_rfc3339("2026-10-07T06:32:40+09:00"), Some(AT));
    assert_eq!(parse_rfc3339("2026-10-06T16:02:40.195331-05:30"), Some(AT));
    assert_eq!(parse_rfc3339("1970-01-01T00:00:00Z"), Some(0));
    assert_eq!(parse_rfc3339("2026-10-06"), None);
    assert_eq!(parse_rfc3339("2026-13-06T21:32:40Z"), None);
    assert_eq!(parse_rfc3339("2026-10-06T21:32:40+0900"), None);
}

#[test]
fn claude_counts_each_streamed_response_once_with_its_last_usage()
-> Result<(), Box<dyn std::error::Error>> {
    let lines = [
        r#"{"type":"user","timestamp":"2026-10-06T21:32:00Z","message":{"role":"user","content":"usage"}}"#,
        r#"{"type":"assistant","timestamp":"2026-10-06T21:32:40Z","requestId":"r1","message":{"id":"m1","usage":{"input_tokens":2,"output_tokens":10,"cache_read_input_tokens":100,"cache_creation_input_tokens":50}}}"#,
        r#"{"type":"assistant","timestamp":"2026-10-06T21:32:41Z","requestId":"r1","message":{"id":"m1","usage":{"input_tokens":2,"output_tokens":180,"cache_read_input_tokens":100,"cache_creation_input_tokens":50}}}"#,
        r#"{"type":"assistant","timestamp":"2026-10-06T21:50:00Z","requestId":"r2","message":{"id":"m2","usage":{"input_tokens":1,"output_tokens":5,"cache_creation_input_tokens":7,"cache_creation":{"ephemeral_5m_input_tokens":4,"ephemeral_1h_input_tokens":9}}}}"#,
        // The last line of a response that crosses a bucket edge stays with its first line.
        r#"{"type":"assistant","timestamp":"2026-10-06T21:44:59Z","requestId":"r3","message":{"id":"m3","usage":{"input_tokens":1,"output_tokens":1}}}"#,
        r#"{"type":"assistant","timestamp":"2026-10-06T21:45:01Z","requestId":"r3","message":{"id":"m3","usage":{"input_tokens":1,"output_tokens":3}}}"#,
        "not json \"usage\"",
    ];
    let joined = lines.join("\n");
    let usage = parse_claude_transcript(joined.as_bytes())?;

    let first = bucket_start(AT);
    assert_eq!(
        usage.buckets.get(&first),
        Some(&TokenCounts {
            input: 3,
            output: 183,
            cache_read: 100,
            cache_write: 50,
        })
    );
    let second = bucket_start(AT + 17 * 60 + 20);
    let second_tokens = usage.buckets.get(&second);
    assert_eq!(second_tokens.map(|t| t.output), Some(5));
    assert_eq!(second_tokens.map(|t| t.cache_write), Some(13));
    // m3 starts at 21:44:59, inside the 21:30 bucket that also holds m1.
    assert_eq!(usage.buckets.get(&first).map(|t| t.output), Some(183));
    assert_eq!(usage.buckets.len(), 2);
    Ok(())
}

#[test]
fn codex_counts_total_usage_deltas_and_survives_counter_resets()
-> Result<(), Box<dyn std::error::Error>> {
    let event = |at: &str, input: u64, cached: u64, output: u64| {
        format!(
            r#"{{"timestamp":"{at}","type":"event_msg","payload":{{"type":"token_count","info":{{"total_token_usage":{{"input_tokens":{input},"cached_input_tokens":{cached},"output_tokens":{output},"total_tokens":{}}}}},"rate_limits":null}}}}"#,
            input + output
        )
    };
    let lines = [
        event("2026-10-06T21:32:40Z", 100, 40, 10),
        // A repeated event with an unchanged total adds nothing.
        event("2026-10-06T21:32:41Z", 100, 40, 10),
        event("2026-10-06T21:33:00Z", 250, 140, 30),
        // The counter restarted (resumed session): count the new total itself.
        event("2026-10-06T21:34:00Z", 20, 0, 5),
        r#"{"timestamp":"2026-10-06T21:34:30Z","type":"event_msg","payload":{"type":"token_count","info":null}}"#.to_string(),
    ];
    let usage = parse_codex_rollout(lines.join("\n").as_bytes())?;

    assert_eq!(
        codex_sum(&usage),
        TokenCounts {
            input: 60 + 50 + 20,
            output: 10 + 20 + 5,
            cache_read: 40 + 100,
            cache_write: 0,
        }
    );
    assert!(usage.buckets.is_empty());
    Ok(())
}

#[test]
fn codex_counts_only_the_first_request_of_a_rollout_that_inherits_totals()
-> Result<(), Box<dyn std::error::Error>> {
    // A forked child starts from its parent's cumulative total (1000 in, 100
    // out); only its own request (50 in, 5 out) is new.
    let lines = [
        codex_event("2026-10-06T21:32:40Z", (1_000, 0, 100), Some((50, 0, 5))),
        codex_event("2026-10-06T21:33:00Z", (1_070, 0, 110), Some((70, 0, 10))),
    ];
    let usage = parse_codex_rollout(lines.join("\n").as_bytes())?;

    let sum = codex_sum(&usage);
    assert_eq!((sum.input, sum.output), (50 + 70, 5 + 10));
    Ok(())
}

#[test]
fn codex_splits_cache_writes_out_of_input() -> Result<(), Box<dyn std::error::Error>> {
    let line = r#"{"timestamp":"2026-10-06T21:32:40Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":60,"cache_write_input_tokens":30,"output_tokens":7}},"rate_limits":null}}"#;
    let usage = parse_codex_rollout(line.as_bytes())?;

    assert_eq!(
        codex_sum(&usage),
        TokenCounts {
            input: 10,
            output: 7,
            cache_read: 60,
            cache_write: 30,
        }
    );
    Ok(())
}

#[test]
fn codex_keeps_tokens_and_limits_when_resets_at_is_a_string()
-> Result<(), Box<dyn std::error::Error>> {
    let line = r#"{"timestamp":"2026-10-06T21:32:40Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":5,"cached_input_tokens":0,"output_tokens":1}},"rate_limits":{"primary":{"used_percent":"12.5","window_minutes":300,"resets_at":"2026-10-06T23:00:00Z"},"secondary":{"used_percent":40,"window_minutes":10080,"resets_at":"1791604768"}}}}"#;
    let usage = parse_codex_rollout(line.as_bytes())?;

    assert_eq!(codex_sum(&usage).input, 5);
    let windows = usage.limits.get("").map(|limits| limits.windows.clone());
    assert_eq!(
        windows,
        Some(vec![
            LimitWindow {
                window_minutes: 300,
                used_percent: 12.5,
                resets_at: Some(AT + 87 * 60 + 20),
            },
            LimitWindow {
                window_minutes: 10080,
                used_percent: 40.0,
                resets_at: Some(1_791_604_768),
            },
        ])
    );
    Ok(())
}

#[test]
fn codex_reads_rate_limits_by_window_length_and_prefers_the_account_bucket()
-> Result<(), Box<dyn std::error::Error>> {
    let lines = [
        r#"{"timestamp":"2026-10-06T21:00:00Z","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","primary":{"used_percent":32.0,"window_minutes":10080,"resets_at":1791604768},"secondary":null,"plan_type":"pro"}}}"#,
        r#"{"timestamp":"2026-10-06T21:30:00Z","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex_other","primary":{"used_percent":90.0,"window_minutes":300,"resets_in_seconds":600},"secondary":null}}}"#,
    ];
    let usage = parse_codex_rollout(lines.join("\n").as_bytes())?;
    assert_eq!(usage.limits.len(), 2);
    let other = usage.limits.get("codex_other").map(|l| l.windows.clone());
    assert_eq!(
        other,
        Some(vec![LimitWindow {
            window_minutes: 300,
            used_percent: 90.0,
            resets_at: Some(AT - 2 * 60 - 40 + 600),
        }])
    );

    let picked = pick_codex_limits(usage.limits);
    assert_eq!(
        picked,
        Some(ProviderLimits {
            observed_at: AT - 32 * 60 - 40,
            plan: Some("pro".to_string()),
            windows: vec![LimitWindow {
                window_minutes: 10080,
                used_percent: 32.0,
                resets_at: Some(1_791_604_768),
            }],
        })
    );
    Ok(())
}

#[test]
fn claude_limits_come_from_the_cached_usage_snapshot() -> Result<(), Box<dyn std::error::Error>> {
    let config: ClaudeConfig = serde_json::from_str(
        r#"{
            "numStartups": 3,
            "oauthAccount": {"userRateLimitTier": null, "organizationRateLimitTier": "default_claude_max_20x"},
            "cachedUsageUtilization": {
                "fetchedAtMs": 1791247988818,
                "utilization": {
                    "five_hour": {"utilization": 0, "resets_at": null},
                    "seven_day": {"utilization": 6, "resets_at": "2026-10-11T14:00:00.195331+00:00"},
                    "seven_day_opus": null
                }
            }
        }"#,
    )?;

    assert_eq!(
        claude_limits_from_config(config),
        Some(ProviderLimits {
            observed_at: 1_791_247_988,
            plan: Some("default_claude_max_20x".to_string()),
            windows: vec![
                LimitWindow {
                    window_minutes: 300,
                    used_percent: 0.0,
                    resets_at: None,
                },
                LimitWindow {
                    window_minutes: 10080,
                    used_percent: 6.0,
                    resets_at: Some(1_791_727_200),
                },
            ],
        })
    );
    Ok(())
}

#[test]
fn claude_without_a_cached_snapshot_has_no_limits() -> Result<(), Box<dyn std::error::Error>> {
    let config: ClaudeConfig = serde_json::from_str(r#"{"oauthAccount": null}"#)?;
    assert_eq!(claude_limits_from_config(config), None);
    Ok(())
}

#[test]
fn snapshot_merges_files_reuses_unchanged_ones_and_drops_deleted_ones()
-> Result<(), Box<dyn std::error::Error>> {
    let root = temp_dir()?;
    let paths = paths(&root);
    let claude_file = paths.claude_dir.join("projects/-p/s1.jsonl");
    write_lines(
        &claude_file,
        &[
            r#"{"type":"assistant","timestamp":"2026-10-06T21:32:40Z","requestId":"r","message":{"id":"m","usage":{"input_tokens":1,"output_tokens":2}}}"#,
        ],
    )?;
    let subagent = paths.claude_dir.join("projects/-p/s1/subagents/a.jsonl");
    write_lines(
        &subagent,
        &[
            r#"{"type":"assistant","timestamp":"2026-10-06T21:33:00Z","requestId":"r9","message":{"id":"m9","usage":{"input_tokens":10,"output_tokens":20}}}"#,
        ],
    )?;
    let codex_file = paths.codex_dir.join("sessions/2026/10/06/rollout-a.jsonl");
    write_lines(
        &codex_file,
        &[
            r#"{"timestamp":"2026-10-06T21:32:40Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":5,"cached_input_tokens":0,"output_tokens":1}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":10.0,"window_minutes":10080,"resets_at":1791604768}}}}"#,
        ],
    )?;
    // A forked child that copied its parent's event counts it only once.
    let child_file = paths.codex_dir.join("sessions/2026/10/06/rollout-b.jsonl");
    write_lines(
        &child_file,
        &[
            r#"{"timestamp":"2026-10-06T21:32:40Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":5,"cached_input_tokens":0,"output_tokens":1}},"rate_limits":null}}"#,
            r#"{"timestamp":"2026-10-06T21:40:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":9,"cached_input_tokens":0,"output_tokens":2}},"rate_limits":null}}"#,
        ],
    )?;
    write_lines(
        &paths.claude_config,
        &[
            r#"{"cachedUsageUtilization":{"fetchedAtMs":1791247988818,"utilization":{"five_hour":{"utilization":12,"resets_at":"2026-10-06T23:00:00Z"}}}}"#,
        ],
    )?;

    let mut cache = UsageCache::default();
    let first = snapshot(&mut cache, &paths, AT + 60, AT - 86_400);
    assert!(first.claude.available && first.codex.available);
    assert_eq!(first.claude.buckets.len(), 1);
    assert_eq!(first.claude.buckets[0].tokens.output, 22);
    assert_eq!(first.codex.buckets.len(), 1);
    assert_eq!(first.codex.buckets[0].tokens.input, 5 + 4);
    assert_eq!(first.codex.buckets[0].tokens.output, 1 + 1);
    assert_eq!(
        first.claude.limits.map(|l| l.windows[0].used_percent),
        Some(12.0)
    );
    assert_eq!(first.codex.limits.map(|l| l.observed_at), Some(AT));
    assert_eq!(cache.files.len(), 4);

    fs::remove_file(&subagent)?;
    let second = snapshot(&mut cache, &paths, AT + 120, AT - 86_400);
    assert_eq!(second.claude.buckets[0].tokens.output, 2);
    assert_eq!(cache.files.len(), 3);

    // Buckets before the window are left out even when their file is fresh.
    let later = snapshot(&mut cache, &paths, AT + 86_400, AT + 3_600);
    assert!(later.claude.buckets.is_empty());

    fs::remove_dir_all(&root)?;
    Ok(())
}

#[test]
fn missing_agent_directories_are_reported_as_unavailable() -> Result<(), Box<dyn std::error::Error>>
{
    let root = temp_dir()?;
    let mut cache = UsageCache::default();
    let result = snapshot(&mut cache, &paths(&root), AT, AT - 86_400);
    assert!(!result.claude.available);
    assert!(!result.codex.available);
    assert!(result.claude.limits.is_none());
    assert!(result.claude.errors.is_empty());
    fs::remove_dir_all(&root)?;
    Ok(())
}

#[test]
#[ignore = "manual: reads the real agent directories"]
fn manual_real_home_snapshot() -> Result<(), Box<dyn std::error::Error>> {
    let paths = UsagePaths::from_env().ok_or("HOME")?;
    let now = now_epoch();
    let mut cache = UsageCache::default();
    for round in 0..2 {
        let started = std::time::Instant::now();
        let result = snapshot(&mut cache, &paths, now, now - 15 * 86_400);
        let total = |p: &ProviderUsage| {
            p.buckets
                .iter()
                .map(|b| {
                    b.tokens.input + b.tokens.output + b.tokens.cache_read + b.tokens.cache_write
                })
                .sum::<u64>()
        };
        println!(
            "round {round}: {:?} claude={} codex={} files={} claude_limits={:?} codex_limits={:?} errors={:?}{:?}",
            started.elapsed(),
            total(&result.claude),
            total(&result.codex),
            cache.files.len(),
            result.claude.limits,
            result.codex.limits,
            result.claude.errors,
            result.codex.errors
        );
    }
    Ok(())
}
