use std::process::Command;

use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct WorkspaceEntry {
    workspace: String,
}

#[derive(Debug, Deserialize, Clone)]
pub struct Window {
    #[serde(rename = "window-id")]
    pub window_id: i64,
    #[serde(rename = "app-name")]
    pub app_name: String,
}

#[derive(Debug, Deserialize)]
pub struct Monitor {
    #[serde(rename = "monitor-id")]
    pub monitor_id: i64,
}

pub fn list_windows_all() -> Result<Vec<Window>, String> {
    run_aerospace_json(&["list-windows", "--all", "--json"])
}

pub fn list_windows_in_workspace(workspace: &str) -> Result<Vec<Window>, String> {
    run_aerospace_json(&["list-windows", "--workspace", workspace, "--json"])
}

pub fn list_monitors() -> Result<Vec<Monitor>, String> {
    run_aerospace_json(&["list-monitors", "--json"])
}

pub fn list_visible_workspaces() -> Result<Vec<String>, String> {
    let mut visible = Vec::new();
    for monitor in list_monitors()? {
        let args = [
            "list-workspaces",
            "--monitor",
            &monitor.monitor_id.to_string(),
            "--visible",
            "--json",
        ];

        let workspaces: Vec<WorkspaceEntry> = run_aerospace_json(&args)?;
        for workspace in workspaces {
            if !visible
                .iter()
                .any(|existing| existing == &workspace.workspace)
            {
                visible.push(workspace.workspace);
            }
        }
    }

    Ok(visible)
}

pub fn list_workspaces_all() -> Result<Vec<String>, String> {
    let output = run_aerospace_stdout(&["list-workspaces", "--all"])?;
    Ok(output
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect())
}

pub fn list_focused_workspace() -> Result<Option<String>, String> {
    let output = run_aerospace_stdout(&["list-workspaces", "--focused"])?;
    let workspace = output.lines().map(str::trim).find(|line| !line.is_empty());
    Ok(workspace.map(ToOwned::to_owned))
}

pub fn focused_window_id() -> Result<Option<i64>, String> {
    let windows: Vec<Window> = run_aerospace_json(&["list-windows", "--focused", "--json"])?;
    Ok(windows.first().map(|window| window.window_id))
}

pub fn workspace_window_count(workspace: &str) -> Result<usize, String> {
    let output = run_aerospace_stdout(&["list-windows", "--workspace", workspace, "--count"])?;
    let value = output
        .trim()
        .parse::<usize>()
        .map_err(|error| format!("failed to parse window count for {workspace}: {error}"))?;
    Ok(value)
}

pub fn move_window_to_workspace(window_id: i64, workspace: &str) -> Result<(), String> {
    run_aerospace_no_output(&[
        "move-node-to-workspace",
        "--window-id",
        &window_id.to_string(),
        workspace,
    ])
}

pub fn focus_workspace(workspace: &str) -> Result<(), String> {
    run_aerospace_no_output(&["workspace", workspace])
}

pub fn focus_window(window_id: i64) -> Result<(), String> {
    run_aerospace_no_output(&["focus", "--window-id", &window_id.to_string()])
}

fn run_aerospace_no_output(args: &[&str]) -> Result<(), String> {
    let output = Command::new("aerospace")
        .args(args)
        .output()
        .map_err(|error| format!("failed to execute aerospace {}: {error}", args.join(" ")))?;

    if output.status.success() {
        return Ok(());
    }

    let stderr = String::from_utf8_lossy(&output.stderr);
    Err(format!(
        "aerospace {} failed: {}",
        args.join(" "),
        stderr.trim()
    ))
}

fn run_aerospace_stdout(args: &[&str]) -> Result<String, String> {
    let output = Command::new("aerospace")
        .args(args)
        .output()
        .map_err(|error| format!("failed to execute aerospace {}: {error}", args.join(" ")))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!(
            "aerospace {} failed: {}",
            args.join(" "),
            stderr.trim()
        ));
    }

    String::from_utf8(output.stdout).map_err(|error| {
        format!(
            "aerospace {} produced non-utf8 output: {error}",
            args.join(" ")
        )
    })
}

fn run_aerospace_json<T>(args: &[&str]) -> Result<T, String>
where
    T: for<'de> Deserialize<'de>,
{
    let output = Command::new("aerospace")
        .args(args)
        .output()
        .map_err(|error| format!("failed to execute aerospace {}: {error}", args.join(" ")))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!(
            "aerospace {} failed: {}",
            args.join(" "),
            stderr.trim()
        ));
    }

    serde_json::from_slice(&output.stdout).map_err(|error| {
        format!(
            "failed to parse JSON from aerospace {}: {error}",
            args.join(" ")
        )
    })
}
