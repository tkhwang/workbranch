//! The text beside the tray icon, composed from the items picked in Settings.
//!
//! A background thread re-reads usage every minute so the menu bar stays
//! current while the window is hidden. A limit reading past its staleness
//! window shows as `–` instead of a number that only looks live.

use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde::Deserialize;
use tauri::{AppHandle, Runtime, State};
use tauri_plugin_store::StoreExt;

use crate::usage::{self, LimitWindow, ProviderLimits, ProviderUsage, UsageSnapshot};

pub(crate) const TRAY_ID: &str = "workbranch-companion";
const PREFERENCES_STORE_FILE: &str = "companion-preferences.json";
const CONFIG_KEY: &str = "menuBar";
const REFRESH_INTERVAL: Duration = Duration::from_secs(60);

// Mirrors domain/usage.ts: a 5h window moves too fast to trust an hour-old
// reading; weekly ones drift slowly.
const FIVE_HOUR_MINUTES: u64 = 5 * 60;
const SHORT_WINDOW_STALE_SECONDS: u64 = 60 * 60;
const LONG_WINDOW_STALE_SECONDS: u64 = 6 * 60 * 60;
const STALE_MARK: &str = "–";

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum PercentBasis {
    #[default]
    Used,
    Remaining,
}

/// Mirrors `MenuBarConfig` in application/preferences.ts. Every item off
/// leaves the icon alone.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase", default)]
pub(crate) struct MenuBarConfig {
    pub(crate) claude_5h: bool,
    pub(crate) claude_weekly: bool,
    pub(crate) codex_weekly: bool,
    pub(crate) today_tokens: bool,
    pub(crate) percent: PercentBasis,
}

impl Default for MenuBarConfig {
    fn default() -> Self {
        Self {
            claude_5h: true,
            claude_weekly: true,
            codex_weekly: true,
            today_tokens: true,
            percent: PercentBasis::Used,
        }
    }
}

impl MenuBarConfig {
    fn from_store_value(value: Option<serde_json::Value>) -> Self {
        value
            .and_then(|value| serde_json::from_value(value).ok())
            .unwrap_or_default()
    }

    fn is_icon_only(self) -> bool {
        !(self.claude_5h || self.claude_weekly || self.codex_weekly || self.today_tokens)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Reading {
    Missing,
    Stale,
    Fresh(u8),
}

impl Reading {
    fn label(self, basis: PercentBasis) -> String {
        match (self, basis) {
            (Reading::Missing | Reading::Stale, _) => STALE_MARK.to_owned(),
            (Reading::Fresh(used), PercentBasis::Used) => format!("{used}%"),
            (Reading::Fresh(used), PercentBasis::Remaining) => format!("{}%", 100 - used),
        }
    }
}

#[derive(Clone, Copy)]
enum Span {
    FiveHour,
    Weekly,
}

impl Span {
    /// Names the window beside its number, since an agent can show both.
    fn label(self) -> &'static str {
        match self {
            Span::FiveHour => "5h",
            Span::Weekly => "W",
        }
    }
}

/// The 5h window, or the longest window past 5h as "weekly", since Codex
/// reports its own window lengths.
fn find_window(limits: &ProviderLimits, span: Span) -> Option<&LimitWindow> {
    match span {
        Span::FiveHour => limits
            .windows
            .iter()
            .find(|window| window.window_minutes <= FIVE_HOUR_MINUTES),
        Span::Weekly => limits
            .windows
            .iter()
            .filter(|window| window.window_minutes > FIVE_HOUR_MINUTES)
            .max_by_key(|window| window.window_minutes),
    }
}

/// An old observation is stale even when its reset has passed: the agent may
/// have used the new window since, so only a recent reading may claim 0%.
fn window_reading(limits: Option<&ProviderLimits>, span: Span, now: u64) -> Reading {
    let Some(limits) = limits else {
        return Reading::Missing;
    };
    let Some(window) = find_window(limits, span) else {
        return Reading::Missing;
    };
    let stale_after = if window.window_minutes <= FIVE_HOUR_MINUTES {
        SHORT_WINDOW_STALE_SECONDS
    } else {
        LONG_WINDOW_STALE_SECONDS
    };
    if now.saturating_sub(limits.observed_at) > stale_after {
        return Reading::Stale;
    }
    if window.resets_at.is_some_and(|resets_at| resets_at <= now) {
        return Reading::Fresh(0);
    }
    // Clamped to 0..=100 first, so the cast cannot truncate.
    Reading::Fresh(window.used_percent.clamp(0.0, 100.0).round() as u8)
}

/// `CL 5h 42% · W 63%`: the agent's enabled windows in 5h → weekly order. An
/// agent with no reading at all is left out rather than shown as dashes.
fn agent_part(name: &str, readings: &[(Span, Reading)], basis: PercentBasis) -> Option<String> {
    if readings.is_empty()
        || readings
            .iter()
            .all(|(_, reading)| *reading == Reading::Missing)
    {
        return None;
    }
    let values: Vec<String> = readings
        .iter()
        .map(|(span, reading)| format!("{} {}", span.label(), reading.label(basis)))
        .collect();
    Some(format!("{name} {}", values.join(" · ")))
}

fn today_tokens(usage: &ProviderUsage, today_start: u64) -> u64 {
    usage
        .buckets
        .iter()
        .filter(|bucket| bucket.start >= today_start)
        .map(|bucket| {
            let tokens = bucket.tokens;
            tokens.input + tokens.output + tokens.cache_read + tokens.cache_write
        })
        .sum()
}

/// Same steps as `formatTokens` in domain/usage.ts.
fn format_tokens(count: u64) -> String {
    let value = count as f64;
    match count {
        0 => "0".to_owned(),
        1..1_000 => count.to_string(),
        1_000..10_000 => format!("{:.1}k", value / 1_000.0),
        10_000..1_000_000 => format!("{}k", (value / 1_000.0).round()),
        1_000_000..100_000_000 => format!("{:.1}M", value / 1_000_000.0),
        100_000_000..1_000_000_000 => format!("{}M", (value / 1_000_000.0).round()),
        _ => format!("{:.2}B", value / 1_000_000_000.0),
    }
}

/// `CL 5h 42% · W 63%  CO W 18% · 31.0M`; `None` leaves the icon alone in the menu bar.
pub(crate) fn menu_bar_title(
    config: MenuBarConfig,
    snapshot: &UsageSnapshot,
    now: u64,
    today_start: u64,
) -> Option<String> {
    let claude = snapshot.claude.limits.as_ref();
    let codex = snapshot.codex.limits.as_ref();
    let mut claude_readings = Vec::new();
    if config.claude_5h {
        claude_readings.push((Span::FiveHour, window_reading(claude, Span::FiveHour, now)));
    }
    if config.claude_weekly {
        claude_readings.push((Span::Weekly, window_reading(claude, Span::Weekly, now)));
    }
    let mut codex_readings = Vec::new();
    if config.codex_weekly {
        codex_readings.push((Span::Weekly, window_reading(codex, Span::Weekly, now)));
    }
    let limits: Vec<String> = [
        agent_part("CL", &claude_readings, config.percent),
        agent_part("CO", &codex_readings, config.percent),
    ]
    .into_iter()
    .flatten()
    .collect();
    let limits = (!limits.is_empty()).then(|| limits.join("  "));

    let has_tokens = snapshot.claude.available || snapshot.codex.available;
    let tokens = (config.today_tokens && has_tokens).then(|| {
        format_tokens(
            today_tokens(&snapshot.claude, today_start)
                + today_tokens(&snapshot.codex, today_start),
        )
    });
    match (limits, tokens) {
        (Some(limits), Some(tokens)) => Some(format!("{limits} · {tokens}")),
        (limits, tokens) => limits.or(tokens),
    }
}

/// Start of the local calendar day, so "today" matches the Usage view.
fn local_midnight(now: u64) -> u64 {
    let fallback = now - now % 86_400;
    let Ok(time) = libc::time_t::try_from(now) else {
        return fallback;
    };
    // SAFETY: `tm` is plain data, so zeroed is a valid value; localtime_r and
    // mktime only touch the two locals passed by reference.
    let midnight = unsafe {
        let mut tm: libc::tm = std::mem::zeroed();
        if libc::localtime_r(&time, &mut tm).is_null() {
            return fallback;
        }
        tm.tm_hour = 0;
        tm.tm_min = 0;
        tm.tm_sec = 0;
        // Let mktime decide DST for midnight itself, not for `now`.
        tm.tm_isdst = -1;
        libc::mktime(&mut tm)
    };
    u64::try_from(midnight).unwrap_or(fallback)
}

/// Wakes the refresh thread early, e.g. right after Settings changes.
pub(crate) struct MenuBarRefresher(Mutex<Sender<()>>);

pub(crate) fn start<R: Runtime>(
    app: &AppHandle<R>,
    cache: Arc<Mutex<usage::UsageCache>>,
) -> MenuBarRefresher {
    let (sender, receiver) = mpsc::channel();
    let app = app.clone();
    std::thread::spawn(move || run(&app, &cache, &receiver));
    MenuBarRefresher(Mutex::new(sender))
}

fn run<R: Runtime>(app: &AppHandle<R>, cache: &Mutex<usage::UsageCache>, wake: &Receiver<()>) {
    loop {
        refresh(app, cache);
        match wake.recv_timeout(REFRESH_INTERVAL) {
            Ok(()) | Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => return,
        }
    }
}

fn refresh<R: Runtime>(app: &AppHandle<R>, cache: &Mutex<usage::UsageCache>) {
    let config = app.store(PREFERENCES_STORE_FILE).map_or_else(
        |_| MenuBarConfig::default(),
        |store| MenuBarConfig::from_store_value(store.get(CONFIG_KEY)),
    );
    let title = if config.is_icon_only() {
        None
    } else {
        current_title(config, cache)
    };
    if let Some(tray) = app.tray_by_id(TRAY_ID) {
        // macOS ignores `set_title(None)` and keeps the previous text, so an
        // empty title is what actually clears it.
        let _ = tray.set_title(Some(title.unwrap_or_default()));
    }
}

fn current_title(config: MenuBarConfig, cache: &Mutex<usage::UsageCache>) -> Option<String> {
    let paths = usage::UsagePaths::from_env()?;
    let now = usage::now_epoch();
    // The Usage view's span, so both readers keep the same files cached.
    let since = usage::since_for_days(now, usage::USAGE_DAYS);
    let snapshot = {
        let mut guard = cache.lock().ok()?;
        usage::snapshot(&mut guard, &paths, now, since)
    };
    menu_bar_title(config, &snapshot, now, local_midnight(now))
}

#[tauri::command]
pub(crate) fn menu_bar_refresh(refresher: State<'_, MenuBarRefresher>) {
    if let Ok(sender) = refresher.0.lock() {
        let _ = sender.send(());
    }
}

#[cfg(test)]
#[path = "menu_bar_tests.rs"]
mod tests;
