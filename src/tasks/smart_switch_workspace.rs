use crate::aerospace_cli::{focus_workspace, list_focused_workspace, list_workspaces_all};
use crate::workspace_utils::{workspace_group, workspace_index};

pub fn run(target_workspace: &str) -> Result<(), String> {
    let target_workspace = target_workspace.trim();
    if target_workspace.is_empty() {
        return Err("target workspace is empty".to_string());
    }

    let all_workspaces = list_workspaces_all()?;
    if all_workspaces
        .iter()
        .any(|workspace| workspace == target_workspace)
    {
        return focus_workspace(target_workspace);
    }

    let focused_workspace = match list_focused_workspace()? {
        Some(workspace) => workspace,
        None => return Ok(()),
    };

    let target_group = match workspace_group(target_workspace) {
        Some(group) => group,
        None => return Ok(()),
    };

    if let Some(nearest) =
        nearest_workspace_in_group(&all_workspaces, target_workspace, target_group)
    {
        if nearest != focused_workspace {
            focus_workspace(&nearest)?;
        }
    }

    Ok(())
}

fn nearest_workspace_in_group(
    all_workspaces: &[String],
    target_workspace: &str,
    target_group: char,
) -> Option<String> {
    let target_index = workspace_index(target_workspace)?;

    let mut candidates: Vec<(i32, i32, String)> = all_workspaces
        .iter()
        .filter(|workspace| workspace_group(workspace) == Some(target_group))
        .filter_map(|workspace| {
            let index = workspace_index(workspace)?;
            let distance = (index - target_index).abs();
            Some((distance, index, workspace.clone()))
        })
        .collect();

    candidates.sort_by(|left, right| {
        left.0
            .cmp(&right.0)
            .then_with(|| left.1.cmp(&right.1))
            .then_with(|| left.2.cmp(&right.2))
    });

    candidates.into_iter().next().map(|entry| entry.2)
}
