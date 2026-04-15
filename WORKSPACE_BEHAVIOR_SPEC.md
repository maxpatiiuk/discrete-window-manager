# Discrete window manager

## Purpose

Define deterministic workspace behavior so that:

- each screen uses a consistent workspace group,
- windows are distributed predictably,
- moves and switches avoid gaps (holes),
- focus ends on the intended window/workspace,
- UI artifacts during transitions are minimized.

This document describes behavior implemented by the companion binary and keybindings in this repository.

## Scope

Applies to:

- startup window arrangement,
- smart workspace switching,
- smart window moves,
- tail workspace cycling and tail move creation,
- empty-workspace fallback behavior after close/move events,
- monitor-group workspace mapping.

Implementation sources:

- [src/main.rs](src/main.rs)
- [src/tasks/smart_arrange_windows.rs](src/tasks/smart_arrange_windows.rs)
- [src/tasks/smart_switch_workspace.rs](src/tasks/smart_switch_workspace.rs)
- [src/tasks/smart_move_node_to_workspace.rs](src/tasks/smart_move_node_to_workspace.rs)
- [src/tasks/group_tail_actions.rs](src/tasks/group_tail_actions.rs)
- [src/tasks/workspace_change.rs](src/tasks/workspace_change.rs)
- [aerospace.toml](aerospace.toml)

## Naming Model

Workspace groups:

- Left group: L1..L15
- Right group: R1..R15
- Middle group: M0..M15

Index model:

- L and R groups are 1-based.
- M group is 0-based.

Monitor assignment model:

- L\* pinned to left/home monitor set.
- R\* pinned to right monitor set.
- M\* pinned to built-in monitor and only used when there are 3 monitors.

Configured in [aerospace.toml](aerospace.toml).

## Core Invariants

1. Group consistency

- Switching or moving by shortcut always targets the requested group (L, R, M).

2. Gap minimization

- Smart moves compact/shift group workspaces to avoid persistent holes after operations.

3. Focus correctness

- After smart move, focus is restored to the moved window.
- After empty-workspace events, focus falls back to nearest non-empty workspace in the same group, else any non-empty workspace.

4. Minimal transition artifacts

- Planned move batches execute off-screen workspaces first, then visible workspaces.
- Forward shifts execute from high index to low index to reduce collision-like intermediate layouts.

5. One thing per view intent

- Startup arrangement spreads windows across workspace slots so windows are not intentionally piled into one workspace.
- Runtime operations preserve continuity and avoid leaving empty holes between occupied workspaces.

## Companion Commands

Declared in [src/main.rs](src/main.rs):

- smart-arrange-windows
- on-workspace-change
- smart-switch-workspace <target>
- smart-move-node-to-workspace <target>
- smart-switch-workspace-tail <group>
- smart-move-node-to-workspace-tail <group>

## Startup Arrangement Policy

Command: smart-arrange-windows

Defined in [src/tasks/smart_arrange_windows.rs](src/tasks/smart_arrange_windows.rs).

Classification:

- Browser: app name contains "chrome" (case-insensitive).
- Code: app name contains one of "code", "cursor", "zed".
- Other: everything else.

Placement:

- Browser windows -> L1.
- Code windows -> primary R1..Rk, fallback:
  - if 3+ monitors: M0..Mk
  - else: L2..L(k+1)
- Other windows -> primary:
  - if 3+ monitors: M0..Mk
  - else: L2..L(k+1)
    fallback: R3..R(k+1), then L2..L(k+1), then R1..R2

Where k = max(window_count_in_class, 5).

Distribution details:

- windows are sorted by window id,
- assigned round-robin across unique workspace pool (primary + fallback deduplicated).

## Smart Switch Policy

Command: smart-switch-workspace <target>

Defined in [src/tasks/smart_switch_workspace.rs](src/tasks/smart_switch_workspace.rs).

Behavior:

- If target exists, focus it.
- If target does not exist, select nearest existing workspace in the same target group by absolute index distance (tie -> lower index).
- If no candidate exists, no-op.

Result:

- direct key shortcuts always resolve to a valid, nearest in-group destination without jumping across groups.

## Smart Move Policy

Command: smart-move-node-to-workspace <target>

Defined in [src/tasks/smart_move_node_to_workspace.rs](src/tasks/smart_move_node_to_workspace.rs).

Preconditions:

- requires a focused window and focused source workspace.

Effective target resolution:

- If target exists, use it.
- If target missing and this is same-group move in non-create mode, keep requested positional target (do not remap to nearest existing).
- Otherwise, normalize:
  - non-create mode: nearest occupied (or nearest existing) workspace in target group,
  - create mode (tail): next index after current max in target group.

Same-group move behavior:

- source index < target index:
  - shift `source+1 .. target` backward by 1 (left compaction).
- source index > target index:
  - shift `target .. source-1` forward by 1.
  - forward shift executes high -> low index to reduce temporary collisions.
- move focused window to effective target.
- refocus moved window.

Cross-group move behavior:

- If source workspace would become empty and source screen could blank, focus nearest non-empty source-group workspace first.
- If target slot/index is occupied, shift target group forward starting at target index.
- Move focused window to effective target.
- Compact source group to remove holes after departure.
- Refocus moved window.

Move execution order:

- partition planned moves into off-screen and visible origins,
- execute off-screen first, then visible.

Goal:

- avoid holes and reduce visible jitter while preserving final intent.

## Tail Actions Policy

Defined in [src/tasks/group_tail_actions.rs](src/tasks/group_tail_actions.rs).

Switch tail:

- smart-switch-workspace-tail <group>
- cycles only through existing workspaces in that group with index >= 5.
- if currently outside tail, jumps to first tail workspace.

Move tail:

- smart-move-node-to-workspace-tail <group>
- computes next target index as max(existing_index + 1, 5),
- then calls smart move in create-if-missing mode,
- guarantees append-style growth for tail workflows.

## Empty Workspace Fallback Policy

Command: on-workspace-change

Defined in [src/tasks/workspace_change.rs](src/tasks/workspace_change.rs).

When triggered by workspace-change callback:

- uses env vars AEROSPACE_FOCUSED_WORKSPACE and AEROSPACE_PREV_WORKSPACE when available.
- if previous workspace is not empty, treats event as normal switch and does nothing.
- if previous workspace is empty and current focus already has windows, does nothing.
- otherwise, considers emptied workspace as source for fallback.

When triggered by focus-change callback path:

- validates focused workspace is still empty across repeated checks to avoid races during user switching.
- if not stably empty, no-op.

Fallback selection:

- nearest non-empty workspace in same group,
- else first non-empty workspace outside source.

## Keybinding Contract

Configured in [aerospace.toml](aerospace.toml).

Switch bindings:

- Alt + Z/X/C/V -> L1/L2/L3/L4
- Alt + N/M/,/. -> R1/R2/R3/R4
- Alt + E/R/T/Y/U -> M0/M1/M2/M3/M4
- Alt + B -> tail cycle L
- Alt + / -> tail cycle R
- Alt + I -> tail cycle M

Move bindings:

- Alt+Shift + Z/X/C/V -> move to L1/L2/L3/L4
- Alt+Shift + N/M/,/. -> move to R1/R2/R3/R4
- Alt+Shift + E/R/T/Y/U -> move to M0/M1/M2/M3/M4
- Alt+Shift + B -> move to new L tail
- Alt+Shift + / -> move to new R tail
- Alt+Shift + I -> move to new M tail

## Non-Goals and Caveats

- This policy does not guarantee strict single-window occupancy if external/manual actions place multiple windows in one workspace.
- AeroSpace callback timing can still produce transient visual movement under heavy concurrent events, but current sequencing is designed to minimize this.
- The companion does not currently persist custom state; behavior is derived from live AeroSpace queries each invocation.

## Acceptance Checks

1. Same-group positional move into missing earlier index

- Example: L4 -> L1 with L1 missing should place moved window at L1 (not L2).

2. Same-group forward shift stability

- Example: L4 -> L1 should shift intermediate workspaces in high-to-low order and avoid obvious side-by-side collision flashes.

3. Cross-group no-hole behavior

- Example: L1..L3 and R1..R2, move L1 -> R1 should compact L group so no persistent L1 hole remains.

4. Focus correctness after move

- After any smart move, focused window id equals moved window id.

5. Smart switch missing target

- Requesting non-existing target focuses nearest existing workspace in requested group.

6. Tail operations

- Tail switch cycles existing 5+ workspaces.
- Tail move appends to next index >= 5.
