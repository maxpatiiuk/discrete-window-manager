use crate::aerospace_cli::{focus_workspace, list_focused_workspace, list_workspaces_all};
use crate::workspace_utils::{workspace_group, workspace_index};

pub fn run_switch_tail(group: char) -> Result<(), String> {
    let group = normalize_group(group)?;
    let all_workspaces = list_workspaces_all()?;

    let tail = tail_workspaces(&all_workspaces, group);
    if tail.is_empty() {
        return Ok(());
    }

    let focused_workspace = match list_focused_workspace()? {
        Some(workspace) => workspace,
        None => {
            focus_workspace(&tail[0])?;
            return Ok(());
        }
    };

    if let Some(position) = tail
        .iter()
        .position(|workspace| workspace == &focused_workspace)
    {
        let next = (position + 1) % tail.len();
        focus_workspace(&tail[next])?;
    } else {
        focus_workspace(&tail[0])?;
    }

    Ok(())
}

pub fn run_move_tail(group: char) -> Result<String, String> {
    let group = normalize_group(group)?;
    let all_workspaces = list_workspaces_all()?;
    let max_index = all_workspaces
        .iter()
        .filter(|workspace| workspace_group(workspace) == Some(group))
        .filter_map(|workspace| workspace_index(workspace))
        .max()
        .unwrap_or(0);

    let next_index = (max_index + 1).max(5);
    Ok(format!("{group}{next_index}"))
}

fn tail_workspaces(all_workspaces: &[String], group: char) -> Vec<String> {
    let mut tail: Vec<(i32, String)> = all_workspaces
        .iter()
        .filter(|workspace| workspace_group(workspace) == Some(group))
        .filter_map(|workspace| {
            let index = workspace_index(workspace)?;
            if index >= 5 {
                Some((index, workspace.clone()))
            } else {
                None
            }
        })
        .collect();

    tail.sort_by(|left, right| left.0.cmp(&right.0).then_with(|| left.1.cmp(&right.1)));
    tail.into_iter().map(|entry| entry.1).collect()
}

fn normalize_group(group: char) -> Result<char, String> {
    let upper = group.to_ascii_uppercase();
    if matches!(upper, 'L' | 'R' | 'M') {
        Ok(upper)
    } else {
        Err(format!("invalid workspace group: {group}"))
    }
}
