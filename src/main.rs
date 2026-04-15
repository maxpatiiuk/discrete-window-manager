mod aerospace_cli;
mod tasks;
mod workspace_utils;

use tasks::{smart_arrange_windows, workspace_change};

fn main() {
    if let Err(error) = run() {
        eprintln!("aerospace-companion error: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let args: Vec<String> = std::env::args().collect();
    let command = args.get(1).map(String::as_str);

    match command {
        Some("smart-arrange-windows") | None => smart_arrange_windows::run(),
        Some("on-workspace-change") => workspace_change::run(),
        Some("smart-switch-workspace") => {
            let target = args
                .get(2)
                .ok_or_else(|| "smart-switch-workspace requires a target workspace".to_string())?;
            tasks::smart_switch_workspace::run(target)
        }
        Some("smart-move-node-to-workspace") => {
            let target = args.get(2).ok_or_else(|| {
                "smart-move-node-to-workspace requires a target workspace".to_string()
            })?;
            tasks::smart_move_node_to_workspace::run(target)
        }
        Some("smart-switch-workspace-tail") => {
            let group = args
                .get(2)
                .and_then(|value| value.chars().next())
                .ok_or_else(|| "smart-switch-workspace-tail requires a group (L/R/M)".to_string())?;
            tasks::group_tail_actions::run_switch_tail(group)
        }
        Some("smart-move-node-to-workspace-tail") => {
            let group = args
                .get(2)
                .and_then(|value| value.chars().next())
                .ok_or_else(|| {
                    "smart-move-node-to-workspace-tail requires a group (L/R/M)".to_string()
                })?;
            let target = tasks::group_tail_actions::run_move_tail(group)?;
            tasks::smart_move_node_to_workspace::run_allow_create_if_missing(&target)
        }
        Some("help") | Some("--help") | Some("-h") => {
            print_help();
            Ok(())
        }
        Some(other) => Err(format!(
            "unknown command: {other}. expected one of: smart-arrange-windows, on-workspace-change, smart-switch-workspace, smart-move-node-to-workspace, smart-switch-workspace-tail, smart-move-node-to-workspace-tail"
        )),
    }
}

fn print_help() {
    println!("aerospace-companion <command>");
    println!();
    println!("Commands:");
    println!("  smart-arrange-windows   Arrange windows across L/R/M workspaces");
    println!("  on-workspace-change     Focus fallback workspace after last-window close");
    println!("  smart-switch-workspace  Smart focus behavior for direct workspace shortcuts");
    println!("  smart-move-node-to-workspace  Smart move behavior for moving focused window");
    println!("  smart-switch-workspace-tail  Cycle through group workspaces with index >= 5");
    println!("  smart-move-node-to-workspace-tail  Move focused window to new tail workspace");
}
