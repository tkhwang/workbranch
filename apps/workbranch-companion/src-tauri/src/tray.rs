use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::image::Image;
use tauri::menu::{Menu, MenuItem};

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

    let show = MenuItem::with_id(app, "show", "Show Companion", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &quit])?;
    let icon = Image::from_bytes(TRAY_TEMPLATE_ICON)?;
    let click_gate = Arc::new(Mutex::new(TrayClickGate::default()));
    TrayIconBuilder::with_id("workbranch-companion")
        .icon(icon)
        .icon_as_template(true)
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "show" => show_main_window(app),
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(move |tray, event| {
            tauri_plugin_positioner::on_tray_event(tray.app_handle(), &event);
            if should_toggle_from_tray_event(&click_gate, &event) {
                toggle_main_window(tray.app_handle());
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

fn should_toggle_from_tray_event(gate: &Mutex<TrayClickGate>, event: &TrayIconEvent) -> bool {
    if !matches!(
        event,
        TrayIconEvent::Click {
            button: MouseButton::Left,
            ..
        }
    ) {
        return false;
    }

    if let Ok(mut gate) = gate.lock() {
        gate.accept(Instant::now())
    } else {
        false
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
    use super::{CLICK_PAIR_SUPPRESSION, TrayClickGate};
    use std::time::{Duration, Instant};

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
}
