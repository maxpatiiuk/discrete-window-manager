use std::env;

use crate::aerospace_cli::{
    focus_workspace, list_focused_workspace, list_workspaces_all, workspace_window_count,
};
use crate::workspace_utils::{sort_group_workspaces, workspace_group, workspace_index};

pub fn run() -> Result<(), String> {
    let focused_from_env = env::var("AEROSPACE_FOCUSED_WORKSPACE").ok();
    let prev_from_env = env::var("AEROSPACE_PREV_WORKSPACE").ok();

    let focused_workspace = match focused_from_env {
        Some(value) if !value.trim().is_empty() => Some(value),
        _ => list_focused_workspace()?,
    };

    let focused_workspace = match focused_workspace {
        Some(workspace) => workspace,
        None => return Ok(()),
    };

    let prev_workspace = match prev_from_env {
        Some(value) if !value.trim().is_empty() => Some(value),
        _ => None,
    };

    // Prefer cleaning up the previous workspace in workspace-change callbacks.
    let source_workspace = if let Some(prev_workspace) = prev_workspace {
        if workspace_window_count(&prev_workspace)? == 0 {
            // If focus already moved to a non-empty workspace, respect that move.
            if workspace_window_count(&focused_workspace)? > 0 {
                return Ok(());
            }
            prev_workspace
        } else {
            // Previous workspace isn't empty, so this was a normal user switch.
            return Ok(());
        }
    } else {
        // Focus-change callbacks don't provide previous workspace env vars.
        // Double-check to avoid transient empty states while user is switching workspaces.
        if workspace_window_count(&focused_workspace)? != 0 {
            return Ok(());
        }

        let focused_workspace_again = list_focused_workspace()?;
        if focused_workspace_again.as_deref() != Some(focused_workspace.as_str()) {
            return Ok(());
        }

        if workspace_window_count(&focused_workspace)? != 0 {
            return Ok(());
        }

        focused_workspace.clone()
    };

    let all_workspaces = list_workspaces_all()?;

    if let Some(group) = workspace_group(&source_workspace) {
        let mut group_workspaces: Vec<String> = all_workspaces
            .iter()
            .filter(|workspace| workspace_group(workspace.as_str()) == Some(group))
            .cloned()
            .collect();
        sort_group_workspaces(&mut group_workspaces);

        if let Some(target) = nearest_non_empty_workspace(&group_workspaces, &source_workspace)? {
            if focused_workspace != target {
                focus_workspace(&target)?;
            }
            return Ok(());
        }
    }

    if let Some(target) = first_non_empty_workspace(&all_workspaces, Some(&source_workspace))? {
        if focused_workspace != target {
            focus_workspace(&target)?;
        }
    }

    Ok(())
}

fn first_non_empty_workspace(
    workspaces: &[String],
    exclude_workspace: Option<&str>,
) -> Result<Option<String>, String> {
    for workspace in workspaces {
        if exclude_workspace == Some(workspace.as_str()) {
            continue;
        }

        if workspace_window_count(workspace)? > 0 {
            return Ok(Some(workspace.clone()));
        }
    }

    Ok(None)
}

fn nearest_non_empty_workspace(
    workspaces: &[String],
    source_workspace: &str,
) -> Result<Option<String>, String> {
    let source_index = match workspace_index(source_workspace) {
        Some(index) => index,
        None => return first_non_empty_workspace(workspaces, Some(source_workspace)),
    };

    let mut candidates: Vec<(i32, i32, String)> = Vec::new();

    for workspace in workspaces {
        if workspace == source_workspace {
            continue;
        }

        if workspace_window_count(workspace)? == 0 {
            continue;
        }

        let index = workspace_index(workspace).unwrap_or(source_index);
        let distance = (index - source_index).abs();
        candidates.push((distance, index, workspace.clone()));
    }

    candidates.sort_by(|left, right| {
        left.0
            .cmp(&right.0)
            .then_with(|| left.1.cmp(&right.1))
            .then_with(|| left.2.cmp(&right.2))
    });

    Ok(candidates.into_iter().next().map(|candidate| candidate.2))
}
