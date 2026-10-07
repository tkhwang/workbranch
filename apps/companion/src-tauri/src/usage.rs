//! Local token usage and subscription limits for Claude Code and Codex.
//!
//! Everything here reads files the agent CLIs already write. It never presents
//! a credential, never touches the network, and never writes into the agents'
//! directories, so the figures can lag: each limit carries the time it was
//! observed and the UI must show that age instead of treating it as live.

use std::collections::hash_map::DefaultHasher;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs::{self, File};
use std::hash::{Hash, Hasher};
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Buckets are 15 minutes so every real UTC offset still splits days exactly.
pub(crate) const BUCKET_SECONDS: u64 = 15 * 60;
const FIVE_HOUR_MINUTES: u64 = 5 * 60;
const WEEKLY_MINUTES: u64 = 7 * 24 * 60;
const MAX_ERRORS: usize = 5;

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct TokenCounts {
    pub(crate) input: u64,
    pub(crate) output: u64,
    pub(crate) cache_read: u64,
    pub(crate) cache_write: u64,
}

impl TokenCounts {
    fn add(&mut self, other: TokenCounts) {
        self.input += other.input;
        self.output += other.output;
        self.cache_read += other.cache_read;
        self.cache_write += other.cache_write;
    }

    fn is_empty(self) -> bool {
        self == TokenCounts::default()
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct UsageBucket {
    pub(crate) start: u64,
    #[serde(flatten)]
    pub(crate) tokens: TokenCounts,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct LimitWindow {
    pub(crate) window_minutes: u64,
    pub(crate) used_percent: f64,
    pub(crate) resets_at: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ProviderLimits {
    pub(crate) observed_at: u64,
    pub(crate) plan: Option<String>,
    pub(crate) windows: Vec<LimitWindow>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ProviderUsage {
    pub(crate) available: bool,
    pub(crate) limits: Option<ProviderLimits>,
    pub(crate) buckets: Vec<UsageBucket>,
    pub(crate) errors: Vec<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct UsageSnapshot {
    pub(crate) generated_at: u64,
    pub(crate) since: u64,
    pub(crate) claude: ProviderUsage,
    pub(crate) codex: ProviderUsage,
}

/// Where each provider keeps its files. Tests point these at temp dirs.
pub(crate) struct UsagePaths {
    pub(crate) claude_config: PathBuf,
    pub(crate) claude_dir: PathBuf,
    pub(crate) codex_dir: PathBuf,
}

impl UsagePaths {
    pub(crate) fn from_env() -> Option<Self> {
        let home = std::env::var_os("HOME").map(PathBuf::from)?;
        let (claude_dir, claude_config) = match std::env::var_os("CLAUDE_CONFIG_DIR") {
            Some(dir) => {
                let dir = PathBuf::from(dir);
                (dir.clone(), dir.join(".claude.json"))
            }
            None => (home.join(".claude"), home.join(".claude.json")),
        };
        let codex_dir = std::env::var_os("CODEX_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".codex"));
        Some(Self {
            claude_config,
            claude_dir,
            codex_dir,
        })
    }
}

#[derive(Debug, Default, Clone)]
struct FileUsage {
    buckets: BTreeMap<u64, TokenCounts>,
    /// Codex token deltas, kept per event so copies shared across rollouts
    /// (a forked child carrying its parent's history) are counted once.
    codex_events: Vec<CodexEvent>,
    /// Latest Codex rate-limit snapshot per limit bucket id.
    limits: HashMap<String, ProviderLimits>,
}

struct CachedFile {
    len: u64,
    modified: SystemTime,
    usage: FileUsage,
}

/// Parsed transcripts keyed by path. A file is re-read only when its size or
/// mtime changes, so steady-state refreshes touch just the active sessions.
#[derive(Default)]
pub(crate) struct UsageCache {
    files: HashMap<PathBuf, CachedFile>,
}

#[derive(Debug, Clone, Copy)]
struct CodexEvent {
    /// Identity of the cumulative counters at this event; equal across copies.
    key: u64,
    at: u64,
    counts: TokenCounts,
}

#[derive(Clone, Copy)]
enum Provider {
    Claude,
    Codex,
}

pub(crate) fn snapshot(
    cache: &mut UsageCache,
    paths: &UsagePaths,
    now: u64,
    since: u64,
) -> UsageSnapshot {
    let mut seen = Vec::new();
    let claude = collect(
        cache,
        Provider::Claude,
        &[paths.claude_dir.join("projects")],
        since,
        &mut seen,
    );
    let codex = collect(
        cache,
        Provider::Codex,
        &[
            paths.codex_dir.join("sessions"),
            paths.codex_dir.join("archived_sessions"),
        ],
        since,
        &mut seen,
    );
    cache.files.retain(|path, _| seen.contains(path));

    let mut claude_errors = claude.errors;
    let claude_limits = match read_claude_limits(&paths.claude_config) {
        Ok(limits) => limits,
        Err(error) => {
            push_error(&mut claude_errors, &paths.claude_config, &error);
            None
        }
    };
    UsageSnapshot {
        generated_at: now,
        since,
        claude: ProviderUsage {
            available: claude.available || paths.claude_config.is_file(),
            limits: claude_limits,
            buckets: claude.buckets,
            errors: claude_errors,
        },
        codex: ProviderUsage {
            available: codex.available,
            limits: pick_codex_limits(codex.limits),
            buckets: codex.buckets,
            errors: codex.errors,
        },
    }
}

pub(crate) fn now_epoch() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_secs())
}

struct Collected {
    available: bool,
    buckets: Vec<UsageBucket>,
    limits: Vec<(String, ProviderLimits)>,
    errors: Vec<String>,
}

fn collect(
    cache: &mut UsageCache,
    provider: Provider,
    roots: &[PathBuf],
    since: u64,
    seen: &mut Vec<PathBuf>,
) -> Collected {
    let mut errors = Vec::new();
    let mut files = Vec::new();
    let mut available = false;
    for root in roots {
        if root.is_dir() {
            available = true;
            walk_jsonl(root, &mut files, &mut errors);
        }
    }
    // A stable order decides which copy of a shared Codex event is counted.
    files.sort();
    let mut counted_events = HashSet::new();

    let cutoff = UNIX_EPOCH + std::time::Duration::from_secs(since);
    let mut totals: BTreeMap<u64, TokenCounts> = BTreeMap::new();
    let mut limits = Vec::new();
    for path in files {
        let Ok(meta) = fs::metadata(&path) else {
            continue;
        };
        let Ok(modified) = meta.modified() else {
            continue;
        };
        // A transcript last written before the window has nothing inside it.
        if modified < cutoff {
            continue;
        }
        let fresh = cache
            .files
            .get(&path)
            .is_some_and(|entry| entry.len == meta.len() && entry.modified == modified);
        if !fresh {
            match parse_file(provider, &path) {
                Ok(usage) => {
                    cache.files.insert(
                        path.clone(),
                        CachedFile {
                            len: meta.len(),
                            modified,
                            usage,
                        },
                    );
                }
                Err(error) => {
                    push_error(&mut errors, &path, &error);
                    continue;
                }
            }
        }
        if let Some(entry) = cache.files.get(&path) {
            for (start, tokens) in entry.usage.buckets.range(since - since % BUCKET_SECONDS..) {
                totals.entry(*start).or_default().add(*tokens);
            }
            for event in &entry.usage.codex_events {
                if event.at >= since && counted_events.insert(event.key) {
                    totals
                        .entry(bucket_start(event.at))
                        .or_default()
                        .add(event.counts);
                }
            }
            limits.extend(
                entry
                    .usage
                    .limits
                    .iter()
                    .map(|(id, limits)| (id.clone(), limits.clone())),
            );
        }
        seen.push(path);
    }
    Collected {
        available,
        buckets: totals
            .into_iter()
            .map(|(start, tokens)| UsageBucket { start, tokens })
            .collect(),
        limits,
        errors,
    }
}

fn walk_jsonl(dir: &Path, files: &mut Vec<PathBuf>, errors: &mut Vec<String>) {
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(error) => {
            push_error(errors, dir, &error);
            return;
        }
    };
    for entry in entries.flatten() {
        let Ok(kind) = entry.file_type() else {
            continue;
        };
        let path = entry.path();
        // Symlinks are skipped so a loop or a link out of the agent dir is never followed.
        if kind.is_dir() {
            walk_jsonl(&path, files, errors);
        } else if kind.is_file() && path.extension().is_some_and(|ext| ext == "jsonl") {
            files.push(path);
        }
    }
}

fn push_error(errors: &mut Vec<String>, path: &Path, error: &dyn std::fmt::Display) {
    if errors.len() < MAX_ERRORS {
        errors.push(format!("{}: {error}", path.display()));
    }
}

fn parse_file(provider: Provider, path: &Path) -> std::io::Result<FileUsage> {
    let reader = BufReader::new(File::open(path)?);
    match provider {
        Provider::Claude => parse_claude_transcript(reader),
        Provider::Codex => parse_codex_rollout(reader),
    }
}

/// Calls `visit` with each line containing `needle`; the substring check skips
/// JSON parsing for the tool output and prompts that make up most bytes.
fn for_each_matching_line(
    mut reader: impl BufRead,
    needle: &[u8],
    mut visit: impl FnMut(&[u8]),
) -> std::io::Result<()> {
    let finder = memchr::memmem::Finder::new(needle);
    let mut line = Vec::new();
    loop {
        line.clear();
        if reader.read_until(b'\n', &mut line)? == 0 {
            return Ok(());
        }
        if finder.find(&line).is_some() {
            visit(&line);
        }
    }
}

fn bucket_start(epoch: u64) -> u64 {
    epoch - epoch % BUCKET_SECONDS
}

// --- Claude Code -----------------------------------------------------------

#[derive(Deserialize)]
struct ClaudeLine {
    #[serde(rename = "type")]
    kind: Option<String>,
    timestamp: Option<String>,
    #[serde(rename = "requestId")]
    request_id: Option<String>,
    message: Option<ClaudeMessage>,
}

#[derive(Deserialize)]
struct ClaudeMessage {
    id: Option<String>,
    usage: Option<ClaudeUsage>,
}

#[derive(Deserialize)]
struct ClaudeUsage {
    #[serde(default)]
    input_tokens: u64,
    #[serde(default)]
    output_tokens: u64,
    #[serde(default)]
    cache_creation_input_tokens: u64,
    #[serde(default)]
    cache_read_input_tokens: u64,
    cache_creation: Option<ClaudeCacheCreation>,
}

#[derive(Deserialize)]
struct ClaudeCacheCreation {
    #[serde(default)]
    ephemeral_5m_input_tokens: u64,
    #[serde(default)]
    ephemeral_1h_input_tokens: u64,
}

impl ClaudeUsage {
    /// The per-TTL breakdown can exceed the flat total; the larger figure is
    /// what was billed (ccusage counts the breakdown too).
    fn counts(&self) -> TokenCounts {
        let breakdown = self.cache_creation.as_ref().map_or(0, |cache| {
            cache.ephemeral_5m_input_tokens + cache.ephemeral_1h_input_tokens
        });
        TokenCounts {
            input: self.input_tokens,
            output: self.output_tokens,
            cache_read: self.cache_read_input_tokens,
            cache_write: self.cache_creation_input_tokens.max(breakdown),
        }
    }
}

/// One assistant response is written as several lines (one per content block)
/// that repeat the same `message.id` + `requestId`. It is counted once: dated
/// by its first line, like ccusage, with the usage of its last line, which
/// carries the final streamed output count.
fn parse_claude_transcript(reader: impl BufRead) -> std::io::Result<FileUsage> {
    let mut by_response: HashMap<String, (u64, TokenCounts)> = HashMap::new();
    let mut unkeyed: Vec<(u64, TokenCounts)> = Vec::new();
    for_each_matching_line(reader, br#""usage""#, |line| {
        let Ok(entry) = serde_json::from_slice::<ClaudeLine>(line) else {
            return;
        };
        if entry.kind.as_deref() != Some("assistant") {
            return;
        }
        let Some(message) = entry.message else {
            return;
        };
        let Some(usage) = message.usage else {
            return;
        };
        let Some(at) = entry.timestamp.as_deref().and_then(parse_rfc3339) else {
            return;
        };
        let tokens = usage.counts();
        match message.id {
            Some(id) => {
                let key = format!("{id}\u{0}{}", entry.request_id.unwrap_or_default());
                by_response
                    .entry(key)
                    .and_modify(|response| response.1 = tokens)
                    .or_insert((at, tokens));
            }
            None => unkeyed.push((at, tokens)),
        }
    })?;

    let mut usage = FileUsage::default();
    for (at, tokens) in by_response.into_values().chain(unkeyed) {
        if !tokens.is_empty() {
            usage
                .buckets
                .entry(bucket_start(at))
                .or_default()
                .add(tokens);
        }
    }
    Ok(usage)
}

#[derive(Deserialize)]
struct ClaudeConfig {
    #[serde(rename = "cachedUsageUtilization")]
    cached_usage: Option<ClaudeCachedUsage>,
    #[serde(rename = "oauthAccount")]
    oauth_account: Option<ClaudeAccount>,
}

#[derive(Deserialize)]
struct ClaudeCachedUsage {
    #[serde(rename = "fetchedAtMs")]
    fetched_at_ms: Option<f64>,
    utilization: Option<ClaudeUtilization>,
}

#[derive(Deserialize)]
struct ClaudeUtilization {
    five_hour: Option<ClaudeWindow>,
    seven_day: Option<ClaudeWindow>,
}

#[derive(Deserialize)]
struct ClaudeWindow {
    utilization: Option<f64>,
    resets_at: Option<String>,
}

#[derive(Deserialize)]
struct ClaudeAccount {
    #[serde(rename = "userRateLimitTier")]
    user_tier: Option<String>,
    #[serde(rename = "organizationRateLimitTier")]
    organization_tier: Option<String>,
}

/// Claude Code caches its last `/usage` answer in `.claude.json`. The snapshot
/// only moves when Claude Code itself refreshes it, so `observedAt` is the
/// cache's own fetch time, never the time this function ran.
fn read_claude_limits(path: &Path) -> std::io::Result<Option<ProviderLimits>> {
    let raw = match fs::read(path) {
        Ok(raw) => raw,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error),
    };
    let config: ClaudeConfig = serde_json::from_slice(&raw).map_err(std::io::Error::other)?;
    Ok(claude_limits_from_config(config))
}

fn claude_limits_from_config(config: ClaudeConfig) -> Option<ProviderLimits> {
    let cached = config.cached_usage?;
    let observed_at = cached
        .fetched_at_ms
        .filter(|ms| ms.is_finite() && *ms > 0.0)
        .map(|ms| (ms / 1000.0) as u64)?;
    let utilization = cached.utilization?;
    let windows: Vec<LimitWindow> = [
        (FIVE_HOUR_MINUTES, utilization.five_hour),
        (WEEKLY_MINUTES, utilization.seven_day),
    ]
    .into_iter()
    .filter_map(|(window_minutes, window)| {
        let window = window?;
        Some(LimitWindow {
            window_minutes,
            used_percent: window.utilization?,
            resets_at: window.resets_at.as_deref().and_then(parse_rfc3339),
        })
    })
    .collect();
    if windows.is_empty() {
        return None;
    }
    let plan = config
        .oauth_account
        .and_then(|account| account.user_tier.or(account.organization_tier));
    Some(ProviderLimits {
        observed_at,
        plan,
        windows,
    })
}

// --- Codex -------------------------------------------------------------------

#[derive(Deserialize)]
struct CodexLine {
    timestamp: Option<String>,
    payload: Option<CodexPayload>,
}

#[derive(Deserialize)]
struct CodexPayload {
    #[serde(rename = "type")]
    kind: Option<String>,
    info: Option<CodexInfo>,
    /// Read loosely: older rollouts store some fields (`resets_at`) as RFC3339
    /// strings, and a strict shape would drop the whole event with its tokens.
    rate_limits: Option<Value>,
}

#[derive(Deserialize)]
struct CodexInfo {
    total_token_usage: Option<CodexTokens>,
    last_token_usage: Option<CodexTokens>,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, Hash, Deserialize)]
struct CodexTokens {
    #[serde(default)]
    input_tokens: u64,
    #[serde(default)]
    cached_input_tokens: u64,
    #[serde(default)]
    cache_write_input_tokens: u64,
    #[serde(default)]
    output_tokens: u64,
}

impl CodexTokens {
    fn total(self) -> u64 {
        self.input_tokens + self.output_tokens
    }

    fn saturating_sub(self, other: CodexTokens) -> CodexTokens {
        CodexTokens {
            input_tokens: self.input_tokens.saturating_sub(other.input_tokens),
            cached_input_tokens: self
                .cached_input_tokens
                .saturating_sub(other.cached_input_tokens),
            cache_write_input_tokens: self
                .cache_write_input_tokens
                .saturating_sub(other.cache_write_input_tokens),
            output_tokens: self.output_tokens.saturating_sub(other.output_tokens),
        }
    }

    /// Codex `input_tokens` already includes cache reads and writes; they are
    /// split out so the four counts never overlap and still sum to the total.
    fn counts(self) -> TokenCounts {
        let cache_read = self.cached_input_tokens.min(self.input_tokens);
        let cache_write = self
            .cache_write_input_tokens
            .min(self.input_tokens - cache_read);
        TokenCounts {
            input: self.input_tokens - cache_read - cache_write,
            output: self.output_tokens,
            cache_read,
            cache_write,
        }
    }
}

fn event_key(total: CodexTokens, last: Option<CodexTokens>) -> u64 {
    let mut hasher = DefaultHasher::new();
    (total, last).hash(&mut hasher);
    hasher.finish()
}

/// Usage comes from the running `total_token_usage`, so a repeated
/// `token_count` event adds nothing. Without a baseline in this file (its
/// first event, or a counter that restarted) only `last_token_usage` is new:
/// a forked rollout's first total also carries the parent's tokens, which the
/// parent's own file already counts.
fn parse_codex_rollout(reader: impl BufRead) -> std::io::Result<FileUsage> {
    let mut usage = FileUsage::default();
    let mut previous: Option<CodexTokens> = None;
    for_each_matching_line(reader, br#""token_count""#, |line| {
        let Ok(entry) = serde_json::from_slice::<CodexLine>(line) else {
            return;
        };
        let Some(payload) = entry.payload else {
            return;
        };
        if payload.kind.as_deref() != Some("token_count") {
            return;
        }
        let Some(at) = entry.timestamp.as_deref().and_then(parse_rfc3339) else {
            return;
        };
        if let Some(info) = payload.info
            && let Some(total) = info.total_token_usage
        {
            let delta = match previous {
                Some(prior) if total.total() >= prior.total() => total.saturating_sub(prior),
                _ => info.last_token_usage.unwrap_or(total),
            };
            previous = Some(total);
            let counts = delta.counts();
            if !counts.is_empty() {
                usage.codex_events.push(CodexEvent {
                    key: event_key(total, info.last_token_usage),
                    at,
                    counts,
                });
            }
        }
        if let Some(limits) = payload
            .rate_limits
            .as_ref()
            .and_then(|limits| codex_limits(limits, at))
        {
            usage.limits.insert(limits.0, limits.1);
        }
    })?;
    Ok(usage)
}

/// Epoch seconds from a number, a numeric string, or an RFC3339 string.
fn json_epoch(value: &Value) -> Option<u64> {
    match value {
        Value::Number(number) => number.as_u64().or_else(|| {
            number
                .as_f64()
                .filter(|seconds| seconds.is_finite() && *seconds >= 0.0)
                .map(|seconds| seconds as u64)
        }),
        Value::String(text) => text.trim().parse().ok().or_else(|| parse_rfc3339(text)),
        _ => None,
    }
}

fn json_number(value: &Value) -> Option<f64> {
    match value {
        Value::Number(number) => number.as_f64(),
        Value::String(text) => text.trim().parse().ok(),
        _ => None,
    }
    .filter(|number: &f64| number.is_finite())
}

fn codex_limits(limits: &Value, at: u64) -> Option<(String, ProviderLimits)> {
    let windows: Vec<LimitWindow> = ["primary", "secondary"]
        .into_iter()
        .filter_map(|name| limits.get(name).filter(|window| window.is_object()))
        .filter_map(|window| {
            let minutes = window.get("window_minutes").and_then(json_number)?;
            Some(LimitWindow {
                window_minutes: minutes as u64,
                used_percent: window.get("used_percent").and_then(json_number)?,
                resets_at: window.get("resets_at").and_then(json_epoch).or_else(|| {
                    window
                        .get("resets_in_seconds")
                        .and_then(json_epoch)
                        .map(|seconds| at + seconds)
                }),
            })
        })
        .collect();
    if windows.is_empty() {
        return None;
    }
    let text = |key: &str| limits.get(key).and_then(Value::as_str).map(str::to_owned);
    Some((
        text("limit_id").unwrap_or_default(),
        ProviderLimits {
            observed_at: at,
            plan: text("plan_type"),
            windows,
        },
    ))
}

/// The account-wide `codex` bucket is preferred; a session pinned to a
/// model-specific bucket only fills in when no account-wide snapshot exists.
fn pick_codex_limits(
    candidates: impl IntoIterator<Item = (String, ProviderLimits)>,
) -> Option<ProviderLimits> {
    let mut account_wide: Option<ProviderLimits> = None;
    let mut other: Option<ProviderLimits> = None;
    for (id, limits) in candidates {
        let slot = if id.is_empty() || id == "codex" {
            &mut account_wide
        } else {
            &mut other
        };
        if slot
            .as_ref()
            .is_none_or(|current| current.observed_at < limits.observed_at)
        {
            *slot = Some(limits);
        }
    }
    account_wide.or(other)
}

// --- Time ----------------------------------------------------------------------

/// Parses `YYYY-MM-DDTHH:MM:SS[.fraction](Z|±HH:MM)` into epoch seconds.
pub(crate) fn parse_rfc3339(text: &str) -> Option<u64> {
    let bytes = text.as_bytes();
    if bytes.len() < 19
        || bytes[4] != b'-'
        || bytes[7] != b'-'
        || !matches!(bytes[10], b'T' | b't' | b' ')
        || bytes[13] != b':'
        || bytes[16] != b':'
    {
        return None;
    }
    let number = |from: usize, to: usize| -> Option<i64> {
        let digits = text.get(from..to)?;
        if !digits.bytes().all(|byte| byte.is_ascii_digit()) {
            return None;
        }
        digits.parse().ok()
    };
    let (year, month, day) = (number(0, 4)?, number(5, 7)?, number(8, 10)?);
    let (hour, minute, second) = (number(11, 13)?, number(14, 16)?, number(17, 19)?);
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) || hour > 23 || minute > 59 {
        return None;
    }
    let mut rest = &text[19..];
    if let Some(fraction) = rest.strip_prefix('.') {
        let digits = fraction
            .bytes()
            .take_while(|byte| byte.is_ascii_digit())
            .count();
        rest = &fraction[digits..];
    }
    let offset = match rest {
        "" | "Z" | "z" => 0,
        _ => {
            let sign = match rest.as_bytes().first() {
                Some(b'+') => 1,
                Some(b'-') => -1,
                _ => return None,
            };
            let zone = &rest[1..];
            if zone.len() != 5 || zone.as_bytes()[2] != b':' {
                return None;
            }
            let hours: i64 = zone.get(0..2)?.parse().ok()?;
            let minutes: i64 = zone.get(3..5)?.parse().ok()?;
            sign * (hours * 3600 + minutes * 60)
        }
    };
    let seconds =
        days_from_civil(year, month, day) * 86_400 + hour * 3600 + minute * 60 + second - offset;
    u64::try_from(seconds).ok()
}

/// Days since 1970-01-01 for a proleptic Gregorian date (Howard Hinnant).
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = year.div_euclid(400);
    let year_of_era = year - era * 400;
    let month_index = (month + 9) % 12;
    let day_of_year = (153 * month_index + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

#[cfg(test)]
#[path = "usage_tests.rs"]
mod tests;
