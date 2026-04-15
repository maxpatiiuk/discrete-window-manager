use std::collections::HashSet;

use crate::aerospace_cli::{list_monitors, list_windows_all, move_window_to_workspace, Window};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AppClass {
    Browser,
    Code,
    Other,
}

pub fn run() -> Result<(), String> {
    let windows = list_windows_all()?;
    if windows.is_empty() {
        return Ok(());
    }

    let monitor_count = list_monitors()?.len();
    let has_middle_workspaces = monitor_count >= 3;

    let browser_windows: Vec<Window> = windows
        .iter()
        .filter(|window| classify_app(&window.app_name) == AppClass::Browser)
        .cloned()
        .collect();
    let code_windows: Vec<Window> = windows
        .iter()
        .filter(|window| classify_app(&window.app_name) == AppClass::Code)
        .cloned()
        .collect();
    let other_windows: Vec<Window> = windows
        .into_iter()
        .filter(|window| classify_app(&window.app_name) == AppClass::Other)
        .collect();

    for window in browser_windows {
        move_window_to_workspace(window.window_id, "L1")?;
    }

    let code_slots = code_windows.len().max(5);
    let code_primary: Vec<String> = (1..=code_slots).map(|n| format!("R{n}")).collect();
    let code_fallback: Vec<String> = if has_middle_workspaces {
        (0..=code_slots).map(|n| format!("M{n}")).collect()
    } else {
        (2..=(code_slots + 1)).map(|n| format!("L{n}")).collect()
    };
    assign_windows_to_workspaces(code_windows, &code_primary, &code_fallback)?;

    let other_slots = other_windows.len().max(5);
    let other_primary: Vec<String> = if has_middle_workspaces {
        (0..=other_slots).map(|n| format!("M{n}")).collect()
    } else {
        (2..=(other_slots + 1)).map(|n| format!("L{n}")).collect()
    };
    let other_fallback: Vec<String> = (3..=(other_slots + 1))
        .map(|n| format!("R{n}"))
        .chain((2..=(other_slots + 1)).map(|n| format!("L{n}")))
        .chain((1..=2).map(|n| format!("R{n}")))
        .collect();
    assign_windows_to_workspaces(other_windows, &other_primary, &other_fallback)?;

    Ok(())
}

fn assign_windows_to_workspaces(
    mut windows: Vec<Window>,
    primary: &[String],
    fallback: &[String],
) -> Result<(), String> {
    if windows.is_empty() {
        return Ok(());
    }

    let mut pool: Vec<String> = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();

    for workspace in primary.iter().chain(fallback.iter()) {
        if seen.insert(workspace.clone()) {
            pool.push(workspace.clone());
        }
    }

    if pool.is_empty() {
        return Err("workspace pool is empty".to_string());
    }

    windows.sort_by_key(|window| window.window_id);
    for (index, window) in windows.iter().enumerate() {
        let workspace = &pool[index % pool.len()];
        move_window_to_workspace(window.window_id, workspace)?;
    }

    Ok(())
}

fn classify_app(app_name: &str) -> AppClass {
    let normalized = app_name.to_ascii_lowercase();

    if normalized.contains("chrome") {
        return AppClass::Browser;
    }

    if normalized.contains("code") || normalized.contains("cursor") || normalized.contains("zed") {
        return AppClass::Code;
    }

    AppClass::Other
}
