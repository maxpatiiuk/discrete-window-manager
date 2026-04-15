use std::collections::HashSet;

use crate::aerospace_cli::{
    focus_window, focus_workspace, focused_window_id, list_focused_workspace,
    list_visible_workspaces, list_windows_in_workspace, list_workspaces_all,
    move_window_to_workspace, workspace_window_count,
};
use crate::workspace_utils::{workspace_group, workspace_index};

#[derive(Debug)]
struct PlannedMove {
    window_id: i64,
    from_workspace: String,
    to_workspace: String,
}

pub fn run(requested_workspace: &str) -> Result<(), String> {
    run_internal(requested_workspace, false)
}

pub fn run_allow_create_if_missing(requested_workspace: &str) -> Result<(), String> {
    run_internal(requested_workspace, true)
}

fn run_internal(requested_workspace: &str, allow_create_if_missing: bool) -> Result<(), String> {
    let requested_workspace = requested_workspace.trim();
    if requested_workspace.is_empty() {
        return Err("target workspace is empty".to_string());
    }

    let focused_window_id = match focused_window_id()? {
        Some(window_id) => window_id,
        None => return Ok(()),
    };
    let source_workspace = match list_focused_workspace()? {
        Some(workspace) => workspace,
        None => return Ok(()),
    };

    let all_workspaces = list_workspaces_all()?;
    let visible_workspaces: HashSet<String> = list_visible_workspaces()?.into_iter().collect();
    let requested_exists = all_workspaces
        .iter()
        .any(|workspace| workspace == requested_workspace);

    let source_group = workspace_group(&source_workspace);
    let source_index = workspace_index(&source_workspace);
    let requested_group = workspace_group(requested_workspace);
    let requested_index = workspace_index(requested_workspace);

    let effective_target = if requested_exists {
        requested_workspace.to_string()
    } else if !allow_create_if_missing
        && source_group == requested_group
        && requested_index.is_some()
    {
        // For same-group moves, treat requested index as positional target even if
        // that workspace isn't currently instantiated.
        requested_workspace.to_string()
    } else {
        normalize_requested_workspace(
            requested_workspace,
            &all_workspaces,
            allow_create_if_missing,
        )
        .unwrap_or_else(|| requested_workspace.to_string())
    };

    if source_workspace == effective_target {
        return Ok(());
    }

    let target_group = workspace_group(&effective_target);
    let target_index = workspace_index(&effective_target);

    if let (Some(source_group), Some(source_index), Some(target_group), Some(target_index)) =
        (source_group, source_index, target_group, target_index)
    {
        if source_group == target_group {
            let planned = if source_index < target_index {
                plan_shift_backward(source_group, source_index + 1, target_index)?
            } else {
                plan_shift_forward(source_group, target_index, source_index - 1)?
            };

            execute_planned_moves(planned, &visible_workspaces)?;
            move_window_to_workspace(focused_window_id, &effective_target)?;
            focus_window(focused_window_id)?;
            return Ok(());
        }
    }

    // If this move would leave the source screen blank, switch it to a non-empty workspace first.
    if source_group != target_group && workspace_window_count(&source_workspace)? == 1 {
        if let Some(group) = source_group {
            if let Some(replacement) =
                nearest_non_empty_workspace_in_group(group, &source_workspace)?
            {
                focus_workspace(&replacement)?;
            }
        }
    }

    if let (Some(group), Some(target_index)) = (target_group, target_index) {
        if let Some(highest_occupied) =
            highest_occupied_index(group, target_index, &all_workspaces)?
        {
            let planned = plan_shift_forward(group, target_index, highest_occupied)?;
            execute_planned_moves(planned, &visible_workspaces)?;
        }
    }

    move_window_to_workspace(focused_window_id, &effective_target)?;

    // After cross-group move, compact source group so no holes remain.
    if let Some(group) = source_group {
        if Some(group) != target_group {
            let planned = plan_group_compaction(group)?;
            execute_planned_moves(planned, &visible_workspaces)?;
        }
    }

    focus_window(focused_window_id)?;

    Ok(())
}

fn normalize_requested_workspace(
    requested_workspace: &str,
    all_workspaces: &[String],
    allow_create_if_missing: bool,
) -> Option<String> {
    let group = workspace_group(requested_workspace)?;
    let requested_index = workspace_index(requested_workspace)?;

    let mut existing_indexes: Vec<i32> = all_workspaces
        .iter()
        .filter(|workspace| workspace_group(workspace) == Some(group))
        .filter_map(|workspace| workspace_index(workspace))
        .collect();

    if existing_indexes.is_empty() {
        return Some(format!("{group}{requested_index}"));
    }

    existing_indexes.sort_unstable();

    if allow_create_if_missing {
        let max_index = *existing_indexes.last()?;
        return Some(format!("{group}{}", max_index + 1));
    }

    let mut occupied_indexes = Vec::new();
    for index in &existing_indexes {
        let workspace = format!("{group}{index}");
        if workspace_window_count(&workspace).ok()? > 0 {
            occupied_indexes.push(*index);
        }
    }

    let candidate_indexes = if occupied_indexes.is_empty() {
        existing_indexes
    } else {
        occupied_indexes
    };

    let nearest = candidate_indexes.into_iter().min_by(|left, right| {
        let left_distance = (left - requested_index).abs();
        let right_distance = (right - requested_index).abs();
        left_distance
            .cmp(&right_distance)
            .then_with(|| left.cmp(right))
    })?;

    Some(format!("{group}{nearest}"))
}

fn nearest_non_empty_workspace_in_group(
    group: char,
    source_workspace: &str,
) -> Result<Option<String>, String> {
    let source_index = match workspace_index(source_workspace) {
        Some(index) => index,
        None => return Ok(None),
    };

    let all_workspaces = list_workspaces_all()?;
    let mut candidates: Vec<(i32, i32, String)> = Vec::new();

    for workspace in all_workspaces
        .iter()
        .filter(|workspace| workspace_group(workspace) == Some(group))
    {
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

fn highest_occupied_index(
    group: char,
    target_index: i32,
    all_workspaces: &[String],
) -> Result<Option<i32>, String> {
    let max_existing_index = all_workspaces
        .iter()
        .filter(|workspace| workspace_group(workspace) == Some(group))
        .filter_map(|workspace| workspace_index(workspace))
        .max()
        .unwrap_or(target_index);

    let mut highest_occupied = None;
    for index in target_index..=max_existing_index {
        let workspace = format!("{group}{index}");
        if workspace_window_count(&workspace)? > 0 {
            highest_occupied = Some(index);
        }
    }

    Ok(highest_occupied)
}

fn plan_shift_forward(
    group: char,
    from_index: i32,
    to_index: i32,
) -> Result<Vec<PlannedMove>, String> {
    if from_index > to_index {
        return Ok(Vec::new());
    }

    let mut planned = Vec::new();
    for index in (from_index..=to_index).rev() {
        let from_workspace = format!("{group}{index}");
        let to_workspace = format!("{group}{}", index + 1);
        let windows = list_windows_in_workspace(&from_workspace)?;
        for window in windows {
            planned.push(PlannedMove {
                window_id: window.window_id,
                from_workspace: from_workspace.clone(),
                to_workspace: to_workspace.clone(),
            });
        }
    }

    Ok(planned)
}

fn plan_shift_backward(
    group: char,
    from_index: i32,
    to_index: i32,
) -> Result<Vec<PlannedMove>, String> {
    if from_index > to_index {
        return Ok(Vec::new());
    }

    let mut planned = Vec::new();
    for index in from_index..=to_index {
        let from_workspace = format!("{group}{index}");
        let to_workspace = format!("{group}{}", index - 1);
        let windows = list_windows_in_workspace(&from_workspace)?;
        for window in windows {
            planned.push(PlannedMove {
                window_id: window.window_id,
                from_workspace: from_workspace.clone(),
                to_workspace: to_workspace.clone(),
            });
        }
    }

    Ok(planned)
}

fn execute_planned_moves(
    planned: Vec<PlannedMove>,
    visible_workspaces: &HashSet<String>,
) -> Result<(), String> {
    let (offscreen, onscreen): (Vec<PlannedMove>, Vec<PlannedMove>) = planned
        .into_iter()
        .partition(|entry| !visible_workspaces.contains(&entry.from_workspace));

    for entry in offscreen.into_iter().chain(onscreen.into_iter()) {
        move_window_to_workspace(entry.window_id, &entry.to_workspace)?;
    }

    Ok(())
}

fn plan_group_compaction(group: char) -> Result<Vec<PlannedMove>, String> {
    let base_index = if group == 'M' { 0 } else { 1 };
    let all_workspaces = list_workspaces_all()?;

    let mut occupied: Vec<(i32, Vec<i64>)> = Vec::new();
    for workspace in all_workspaces
        .iter()
        .filter(|workspace| workspace_group(workspace) == Some(group))
    {
        let Some(index) = workspace_index(workspace) else {
            continue;
        };

        let windows = list_windows_in_workspace(workspace)?;
        if windows.is_empty() {
            continue;
        }

        occupied.push((
            index,
            windows.into_iter().map(|window| window.window_id).collect(),
        ));
    }

    occupied.sort_by(|left, right| left.0.cmp(&right.0));

    let mut planned = Vec::new();
    for (offset, (from_index, window_ids)) in occupied.into_iter().enumerate() {
        let to_index = base_index + offset as i32;
        if from_index == to_index {
            continue;
        }

        let from_workspace = format!("{group}{from_index}");
        let to_workspace = format!("{group}{to_index}");
        for window_id in window_ids {
            planned.push(PlannedMove {
                window_id,
                from_workspace: from_workspace.clone(),
                to_workspace: to_workspace.clone(),
            });
        }
    }

    Ok(planned)
}
