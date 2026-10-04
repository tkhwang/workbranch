use crate::{
    Result,
    store::{self, Session},
};
use rusqlite::{Connection, TransactionBehavior};
use serde_json::Value;
use sha2::{Digest, Sha256};

fn string<'a>(v: &'a Value, key: &str) -> &'a str {
    v.get(key).and_then(Value::as_str).unwrap_or("")
}
fn clipped(text: &str, limit: usize) -> String {
    let clean = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let lower = clean.to_lowercase();
    // Conservatively omit the whole excerpt when credential syntax is present.
    // Token-wise replacement can expose quoted or multi-word header values.
    if [
        "authorization",
        "bearer ",
        "password",
        "--token",
        "token=",
        "api_key",
        "api-key",
        "secret",
        "token",
        "sk-",
        "ghp_",
    ]
    .iter()
    .any(|key| lower.contains(key))
    {
        return "[sensitive content omitted]".into();
    }
    let mut out: String = clean.chars().take(limit).collect();
    if clean.chars().count() > limit {
        out.push('…');
    }
    out
}

fn signature(v: &Value) -> String {
    let input = v.get("tool_input").unwrap_or(&Value::Null);
    format!(
        "{:x}",
        Sha256::digest(format!("{}:{}", string(v, "tool_name"), input))
    )
}
fn activity(v: &Value) -> String {
    let tool = string(v, "tool_name");
    let input = &v["tool_input"];
    let detail = [
        "description",
        "file_path",
        "path",
        "pattern",
        "query",
        "command",
    ]
    .iter()
    .find_map(|key| input.get(key).and_then(Value::as_str))
    .map(str::to_owned)
    .or_else(|| {
        input.get("command").and_then(Value::as_array).map(|parts| {
            parts
                .iter()
                .take(16)
                .filter_map(Value::as_str)
                .collect::<Vec<_>>()
                .join(" ")
        })
    })
    .or_else(|| {
        input
            .get("questions")
            .and_then(Value::as_array)
            .and_then(|rows| rows.first())
            .and_then(|q| q.get("question"))
            .and_then(Value::as_str)
            .map(str::to_owned)
    })
    .unwrap_or_default();
    // Never retain entire apply_patch contents, env objects, tool results, or arbitrary args.
    let detail = if tool == "apply_patch" {
        "file changes"
    } else {
        &detail
    };
    clipped(&format!("{tool}: {detail}"), 240)
}
fn bound(v: &mut Vec<String>) {
    if v.len() > 64 {
        v.drain(..v.len() - 64);
    }
}
fn grok_payload(v: &Value) -> Value {
    let mut normalized = v.clone();
    if let Some(object) = normalized.as_object_mut() {
        for (from, to) in [
            ("sessionId", "session_id"),
            ("promptId", "turn_id"),
            ("toolName", "tool_name"),
            ("toolUseId", "tool_use_id"),
            ("toolInput", "tool_input"),
            ("notificationType", "notification_type"),
            ("lastAssistantMessage", "last_assistant_message"),
            ("agentId", "agent_id"),
            ("userPrompt", "prompt"),
        ] {
            if !object.contains_key(to)
                && let Some(value) = v.get(from)
            {
                object.insert(to.into(), value.clone());
            }
        }
        let event = string(v, "hook_event_name");
        let event = if event.is_empty() {
            match string(v, "hookEventName") {
                "session_start" => "SessionStart",
                "session_end" => "SessionEnd",
                "user_prompt_submit" => "UserPromptSubmit",
                "pre_tool_use" => "PreToolUse",
                "post_tool_use" => "PostToolUse",
                "post_tool_use_failure" => "PostToolUseFailure",
                "notification" => "Notification",
                "stop" => "Stop",
                "stop_failure" => "StopFailure",
                "stop_cancelled" => "Interrupt",
                _ => "",
            }
        } else if event == "StopCancelled" {
            "Interrupt"
        } else {
            event
        };
        object.insert("hook_event_name".into(), Value::String(event.into()));
    }
    normalized
}

pub fn ingest(
    db: &mut Connection,
    workspace: &str,
    provider: &str,
    v: &Value,
    now: u64,
) -> Result<()> {
    if provider != "grok" && v.get("sessionId").is_some() && v.get("hookEventName").is_some() {
        return Err("Grok compatibility event requires its own adapter".into());
    }
    let normalized;
    let v = if provider == "grok" {
        normalized = grok_payload(v);
        &normalized
    } else {
        v
    };
    if !matches!(provider, "claude" | "codex" | "grok") {
        return Err("unsupported provider".into());
    }
    let sid = string(v, "session_id");
    if sid.is_empty() || sid.len() > 256 {
        return Err("invalid session id".into());
    }
    let event = string(v, "hook_event_name");
    if !matches!(
        event,
        "SessionStart"
            | "SessionEnd"
            | "UserPromptSubmit"
            | "PreToolUse"
            | "PostToolUse"
            | "PostToolUseFailure"
            | "PermissionRequest"
            | "Notification"
            | "Elicitation"
            | "ElicitationResult"
            | "Stop"
            | "Interrupt"
            | "StopFailure"
    ) {
        return Ok(());
    }
    let agent = string(v, "agent_id");
    let tx = db.transaction_with_behavior(TransactionBehavior::Immediate)?;
    let stamp = store::workspace_stamp(std::path::Path::new(workspace));
    let mut s = store::load(&tx, workspace, provider, sid, agent)?
        .filter(|s| s.workspace_stamp == stamp)
        .unwrap_or_else(|| Session {
            workspace: workspace.into(),
            workspace_stamp: stamp,
            provider: provider.into(),
            session_id: sid.into(),
            agent_id: agent.into(),
            state: "idle".into(),
            observation: "observed".into(),
            ..Session::default()
        });
    if s.closed && !matches!(event, "SessionStart" | "UserPromptSubmit") {
        return Ok(());
    }
    let turn = string(v, "turn_id");
    if !turn.is_empty() && s.retired_turns.iter().any(|t| t == turn) {
        return Ok(());
    }
    if !turn.is_empty() && turn != s.turn_id && event != "UserPromptSubmit" && !s.turn_id.is_empty()
    {
        return Ok(());
    }
    if s.state == "finished"
        && !(provider == "grok" && s.outcome == "turn-ended" && event == "PreToolUse")
        && !(provider == "grok"
            && event == "Notification"
            && string(v, "notification_type") == "idle_prompt")
        && event != "UserPromptSubmit"
        && event != "SessionStart"
        && event != "SessionEnd"
        && !matches!(event, "Stop" | "StopFailure" | "Interrupt")
    {
        return Ok(());
    }
    let before = s.state.clone();
    let id = string(v, "tool_use_id");
    let tool = string(v, "tool_name");
    match event {
        "SessionStart" => {
            s.closed = false;
            s.state = "idle".into();
            s.waits.clear();
            s.active_tools.clear();
        }
        "SessionEnd" => {
            s.closed = true;
            s.state = "idle".into();
            s.waits.clear();
            s.active_tools.clear();
        }
        "UserPromptSubmit" => {
            s.closed = false;
            if !s.turn_id.is_empty() && s.turn_id != turn {
                s.retired_turns.push(s.turn_id.clone());
                bound(&mut s.retired_turns);
            }
            s.turn_id = turn.into();
            s.state = "running".into();
            s.observation = "observed".into();
            s.waits.clear();
            s.active_tools.clear();
            s.completed_tools.clear();
            s.response.clear();
            s.activity.clear();
            s.reason.clear();
            s.outcome.clear();
            s.prompt = clipped(
                v.get("prompt")
                    .or_else(|| v.get("user_prompt"))
                    .and_then(Value::as_str)
                    .unwrap_or(""),
                500,
            );
        }
        "PreToolUse" => {
            if s.completed_tools.iter().any(|k| k == id) && !id.is_empty() {
                return Ok(());
            }
            if s.turn_id.is_empty() {
                s.turn_id = turn.into();
            }
            if !id.is_empty() {
                s.active_tools.insert(id.into(), signature(v));
            }
            s.activity = activity(v);
            let reason = match tool {
                "AskUserQuestion" | "request_user_input" => "question",
                "ExitPlanMode" => "plan",
                _ => "",
            };
            if !reason.is_empty() {
                s.waits.insert(
                    if id.is_empty() { "unresolved" } else { id }.into(),
                    reason.into(),
                );
            }
            s.state = if s.waits.is_empty() {
                "running"
            } else {
                "waiting"
            }
            .into();
        }
        "PermissionRequest" => {
            if !id.is_empty() && s.completed_tools.iter().any(|key| key == id) {
                return Ok(());
            }
            let sig = signature(v);
            let ids: Vec<_> = s
                .active_tools
                .iter()
                .filter(|(_, value)| **value == sig)
                .map(|(key, _)| key.clone())
                .collect();
            let key = if !id.is_empty() {
                id.into()
            } else if ids.len() == 1 {
                ids[0].clone()
            } else {
                s.observation = "uncertain".into();
                "unresolved".into()
            };
            s.waits.insert(key, "permission".into());
            s.state = "waiting".into();
            s.activity = activity(v);
        }
        "Notification" => {
            if provider == "grok" && string(v, "notification_type") == "idle_prompt" {
                s.state = "finished".into();
                s.waits.clear();
                s.active_tools.clear();
                if s.outcome.is_empty() {
                    s.outcome = "turn-ended".into();
                }
            } else {
                let reason = match string(v, "notification_type") {
                    "permission_prompt" => "permission",
                    "elicitation_dialog" | "elicitation_url_dialog" => "elicitation",
                    _ => return Ok(()),
                };
                if s.waits.is_empty() {
                    s.waits.insert("unresolved".into(), reason.into());
                    s.observation = "uncertain".into();
                }
                s.state = "waiting".into();
            }
        }
        "Elicitation" => {
            s.waits.insert(
                format!("elicitation:{}", string(v, "elicitation_id")),
                "elicitation".into(),
            );
            s.state = "waiting".into();
        }
        "ElicitationResult" => {
            if s.waits
                .remove(&format!("elicitation:{}", string(v, "elicitation_id")))
                .is_none()
            {
                return Ok(());
            }
            if s.waits.is_empty() {
                s.state = "running".into();
            }
        }
        "PostToolUse" | "PostToolUseFailure" => {
            if id.is_empty() {
                return Ok(());
            }
            s.active_tools.remove(id);
            s.waits.remove(id);
            s.completed_tools.push(id.into());
            bound(&mut s.completed_tools);
            if s.state != "finished" && s.state != "idle" {
                s.state = if s.waits.is_empty() {
                    "running"
                } else {
                    "waiting"
                }
                .into();
            }
            if event == "PostToolUseFailure" {
                s.outcome = "tool-error".into();
            }
        }
        "Stop" | "Interrupt" | "StopFailure" => {
            s.state = "finished".into();
            s.waits.clear();
            s.active_tools.clear();
            s.response = clipped(string(v, "last_assistant_message"), 2000);
            s.outcome = match event {
                "Interrupt" => "interrupted",
                "StopFailure" => "error",
                _ => "turn-ended",
            }
            .into();
        }
        _ => {}
    }
    s.reason = s.waits.values().next().cloned().unwrap_or_default();
    if s.waits.is_empty() {
        s.observation = "observed".into();
    }
    if s.active_tools.len() > 128 {
        s.active_tools.clear();
        s.observation = "uncertain".into();
    }
    if provider == "grok" && event == "Stop" {
        s.observation = "uncertain".into();
    }
    s.updated_at = now;
    if s.state != before {
        s.state_changed_at = now;
    }
    store::save(&tx, &s)?;
    tx.commit()?;
    Ok(())
}
