use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::image::Image;
use tauri::tray::{MouseButton, TrayIconBuilder, TrayIconEvent};
use tauri::{App, AppHandle, Manager, PhysicalPosition, WebviewWindow, WindowEvent};
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
            let tray_point = tray_point_from_event(&event);
            match click_action_from_tray_event(&click_gate, &event) {
                Some(ClickAction::Toggle) => toggle_main_window(tray.app_handle(), tray_point),
                Some(ClickAction::Show) => show_main_window(tray.app_handle(), tray_point),
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
    let action = click_action_for_button(*button)?;

    let mut gate = gate.lock().ok()?;
    if gate.accept(Instant::now()) {
        Some(action)
    } else {
        None
    }
}

fn tray_point_from_event(event: &TrayIconEvent) -> Option<PhysicalPosition<f64>> {
    let TrayIconEvent::Click { rect, .. } = event else {
        return None;
    };
    // tray-icon reports physical coordinates, matching tauri-plugin-positioner.
    Some(rect.position.to_physical(1.0))
}

fn toggle_main_window(app: &AppHandle, tray_point: Option<PhysicalPosition<f64>>) {
    if let Some(window) = app.get_webview_window("main") {
        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
        } else {
            show_main_window(app, tray_point);
        }
    }
}

fn show_main_window(app: &AppHandle, tray_point: Option<PhysicalPosition<f64>>) {
    if let Some(window) = app.get_webview_window("main") {
        if ensure_window_on_monitor(app, &window, tray_point) {
            let _ = window.move_window_constrained(Position::TrayCenter);
        }
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

/// tauri-plugin-positioner unwraps `current_monitor()`, which is `None` when
/// the hidden window's frame no longer intersects any screen (an external
/// display was unplugged or re-enumerated on wake). That panic exits the app,
/// so park the window on a live monitor first and skip positioning if that
/// still leaves it off-screen.
fn ensure_window_on_monitor(
    app: &AppHandle,
    window: &WebviewWindow,
    tray_point: Option<PhysicalPosition<f64>>,
) -> bool {
    if matches!(window.current_monitor(), Ok(Some(_))) {
        return true;
    }
    let tray_monitor = tray_point
        .and_then(|point| app.monitor_from_point(point.x, point.y).ok().flatten())
        .map(|monitor| *monitor.position());
    let primary_monitor = app
        .primary_monitor()
        .ok()
        .flatten()
        .map(|monitor| *monitor.position());
    let Some(origin) = parking_origin(tray_monitor, primary_monitor) else {
        return false;
    };
    if window.set_position(origin).is_err() {
        return false;
    }
    matches!(window.current_monitor(), Ok(Some(_)))
}

fn parking_origin(
    tray_monitor: Option<PhysicalPosition<i32>>,
    primary_monitor: Option<PhysicalPosition<i32>>,
) -> Option<PhysicalPosition<i32>> {
    tray_monitor.or(primary_monitor)
}

#[cfg(test)]
mod tests {
    use super::{
        CLICK_PAIR_SUPPRESSION, ClickAction, TrayClickGate, click_action_for_button,
        click_action_from_tray_event, parking_origin, tray_point_from_event,
    };
    use std::sync::Mutex;
    use std::time::{Duration, Instant};
    use tauri::tray::{MouseButton, MouseButtonState, TrayIconEvent, TrayIconId};
    use tauri::{PhysicalPosition, Rect};

    fn click_event(button: MouseButton) -> TrayIconEvent {
        TrayIconEvent::Click {
            id: TrayIconId::new("workbranch-companion"),
            position: PhysicalPosition::default(),
            rect: Rect::default(),
            button,
            button_state: MouseButtonState::Down,
        }
    }

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

    #[test]
    fn middle_click_does_not_consume_click_gate() {
        let gate = Mutex::new(TrayClickGate::default());
        let middle_click = click_event(MouseButton::Middle);
        let right_click = click_event(MouseButton::Right);

        assert_eq!(click_action_from_tray_event(&gate, &middle_click), None);
        assert_eq!(
            click_action_from_tray_event(&gate, &right_click),
            Some(ClickAction::Show)
        );
    }

    #[test]
    fn parking_origin_prefers_tray_monitor() {
        let tray = PhysicalPosition::new(3456, -200);
        let primary = PhysicalPosition::new(0, 0);

        assert_eq!(parking_origin(Some(tray), Some(primary)), Some(tray));
    }

    #[test]
    fn parking_origin_falls_back_to_primary_monitor() {
        let primary = PhysicalPosition::new(0, 0);

        assert_eq!(parking_origin(None, Some(primary)), Some(primary));
    }

    #[test]
    fn parking_origin_is_none_without_any_monitor() {
        assert_eq!(parking_origin(None, None), None);
    }

    #[test]
    fn tray_point_comes_from_click_rect() {
        let mut event = click_event(MouseButton::Left);
        if let TrayIconEvent::Click { rect, .. } = &mut event {
            rect.position = PhysicalPosition::new(1200.0, 0.0).into();
        }

        assert_eq!(
            tray_point_from_event(&event),
            Some(PhysicalPosition::new(1200.0, 0.0))
        );
    }
}
