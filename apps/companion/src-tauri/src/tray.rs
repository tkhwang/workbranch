use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::image::Image;
use tauri::tray::{MouseButton, TrayIconBuilder, TrayIconEvent};
use tauri::{App, AppHandle, Manager, WindowEvent};
use tauri_plugin_positioner::{Position, WindowExt};

const TRAY_TEMPLATE_ICON: &[u8] = include_bytes!("../icons/tray-template.png");

pub(crate) fn install(app: &mut App) -> tauri::Result<()> {
    #[cfg(target_os = "macos")]
    app.set_activation_policy(tauri::ActivationPolicy::Accessory);

    if let Some(window) = app.get_webview_window("main") {
        let _ = window.hide();
        let event_window = window.clone();
        window.on_window_event(move |event| match event {
            WindowEvent::Focused(false) => {
                let _ = event_window.hide();
            }
            WindowEvent::CloseRequested { api, .. } => {
                api.prevent_close();
                let _ = event_window.hide();
            }
            _ => {}
        });
    }

    let icon = Image::from_bytes(TRAY_TEMPLATE_ICON)?;
    let click_gate = Arc::new(Mutex::new(TrayClickGate::default()));
    TrayIconBuilder::with_id("workbranch-companion")
        .icon(icon)
        .icon_as_template(true)
        .show_menu_on_left_click(false)
        .on_tray_icon_event(move |tray, event| {
            tauri_plugin_positioner::on_tray_event(tray.app_handle(), &event);
            match click_action_from_tray_event(&click_gate, &event) {
                Some(ClickAction::Toggle) => toggle_main_window(tray.app_handle()),
                Some(ClickAction::Show) => show_main_window(tray.app_handle()),
                None => {}
            }
        })
        .build(app)?;
    Ok(())
}

const CLICK_PAIR_SUPPRESSION: Duration = Duration::from_millis(250);

#[derive(Default)]
struct TrayClickGate {
    last_accepted_click: Option<Instant>,
}

impl TrayClickGate {
    fn accept(&mut self, now: Instant) -> bool {
        if self
            .last_accepted_click
            .is_some_and(|last| now.duration_since(last) < CLICK_PAIR_SUPPRESSION)
        {
            return false;
        }

        self.last_accepted_click = Some(now);
        true
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ClickAction {
    Toggle,
    Show,
}

fn click_action_for_button(button: MouseButton) -> Option<ClickAction> {
    match button {
        MouseButton::Left => Some(ClickAction::Toggle),
        MouseButton::Right => Some(ClickAction::Show),
        MouseButton::Middle => None,
    }
}

fn click_action_from_tray_event(
    gate: &Mutex<TrayClickGate>,
    event: &TrayIconEvent,
) -> Option<ClickAction> {
    let TrayIconEvent::Click { button, .. } = event else {
        return None;
    };

    let mut gate = gate.lock().ok()?;
    if gate.accept(Instant::now()) {
        click_action_for_button(*button)
    } else {
        None
    }
}

fn toggle_main_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
        } else {
            show_main_window(app);
        }
    }
}

fn show_main_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.move_window_constrained(Position::TrayCenter);
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

#[cfg(test)]
mod tests {
    use super::{CLICK_PAIR_SUPPRESSION, ClickAction, TrayClickGate, click_action_for_button};
    use std::time::{Duration, Instant};
    use tauri::tray::MouseButton;

    #[test]
    fn accept_suppresses_paired_click_phase_when_inside_window() {
        let mut gate = TrayClickGate::default();
        let first_click = Instant::now();
        let paired_phase = first_click + Duration::from_millis(10);

        assert!(gate.accept(first_click));
        assert!(!gate.accept(paired_phase));
    }

    #[test]
    fn accept_allows_next_user_click_after_suppression_window() {
        let mut gate = TrayClickGate::default();
        let first_click = Instant::now();
        let next_click = first_click + CLICK_PAIR_SUPPRESSION + Duration::from_millis(1);

        assert!(gate.accept(first_click));
        assert!(gate.accept(next_click));
    }

    #[test]
    fn right_click_shows_main_window_without_menu_action() {
        assert_eq!(
            click_action_for_button(MouseButton::Right),
            Some(ClickAction::Show)
        );
    }
}
