# Window Manager Implementation Plan

## Core Principles
- **One App per Workspace**: Encourage single-task focus.
- **Zero Animation**: Avoid macOS Spaces; move windows off-screen to hide them.
- **Reconciliation Engine**: Pure logic determines the layout; an actuator applies it.
- **Manual Control**: Allow-list defaults, but provide a manual "managed" toggle.

## Phase 1: Foundation & Visibility (Priority)
- [x] **State Visualization (`alt+s`)**:
    - Implement a status window on each screen.
    - Display a vertical list of workspaces (App Name + Title).
    - Highlight the active workspace.
- [x] **Debug View (`alt+d`)**:
    - Migrate current debug text to this shortcut.
- [ ] **Logging & Performance**:
    - Add structured logging for every "Reconciliation" pass.
    - Measure and log the time spent in AX calls to identify bottlenecks.
- [ ] **Testing Strategy**:
    - **Unit Tests**: Focus on the `Planner` (pure function: `CurrentState -> TargetState`).
    - **Mocks**: Create a mockable `WindowActuator` protocol for AX operations.

## Phase 2: Workspace Management
- [x] **Window Classifier**:
    - Bundle ID allow-list (Chrome, VS Code).
    - Manual toggle for "Managed" status (stored per Window ID).
    - Distinguish Chrome DevTools from Chrome via title.
- [ ] **The "Stage" (Hiding Mechanism)**:
    - Implement moving windows to `(+30,000, +30,000)` to hide them.
- [ ] **Reconciliation Logic**:
    - Assign new windows to new workspaces automatically.
    - **Separation Rule**: Prefer keeping Chrome and VS Code on different physical screens.
    - **Display Persistence**: Remember `lastAssociatedDisplayID` to restore layout on re-connect.

## Phase 3: Interaction & Movement
- [ ] **Workspace Switching**:
    - Implement `alt + [keys]` for Left, Middle, and Right screens.
    - Warp mouse and focus to the center of the newly activated window.
- [ ] **Window Movement**:
    - Implement two keys per screen for "Move to Screen / Cycle Workspace."
- [ ] **Mouse Warping**:
    - Logic to move the cursor only when switching to a different monitor or a non-visible workspace.

## Phase 4: Refinement & Edge Cases
- [ ] **Unmanaged App Support**: Ensure they can be moved via shortcuts without being auto-resized.
- [ ] **Display Disconnect Handling**: Re-allocate workspaces to remaining screens while preserving "home" display metadata.
- [ ] **Staggered Placement**: Improve balancing logic for multiple windows of the same app type.

---

## Technical Notes
- **Actuator Throttling**: AX calls can be slow; ensure we only move windows that *actually* need to move.
- **Window ID Stability**: Use `CGWindowNumber` but be aware of how apps handle tab splitting/merging.
- **Mouse Warping API**: Use `CGWarpMouseCursorPosition` to avoid triggering events.
