pub fn workspace_group(name: &str) -> Option<char> {
    let group = name.chars().next()?;
    if matches!(group, 'L' | 'R' | 'M') {
        Some(group)
    } else {
        None
    }
}

pub fn workspace_index(name: &str) -> Option<i32> {
    let suffix = name.get(1..)?;
    suffix.parse::<i32>().ok()
}

pub fn sort_group_workspaces(workspaces: &mut [String]) {
    workspaces.sort_by(|left, right| {
        let li = workspace_index(left);
        let ri = workspace_index(right);
        li.cmp(&ri).then_with(|| left.cmp(right))
    });
}
