# Technical Specification: Window Manager

## 1. Core Architecture: The Reconciliation Loop

The system operates on a "Desired State" model. Instead of reacting to events with individual moves, every change triggers a global reconciliation.

### Flow:

1. **Snapshot**: `WindowStateStore` and `MonitorStateStore` provide the current OS state.
2. **Reclassification**:
   - Identify windows as `Managed` (allow-listed) or `Unmanaged`.
   - Update `Managed` status based on user overrides (stored in a `Set<CGWindowID>`).
3. **Plan (Pure Function)**:
   - **Input**: Current Windows, Current Monitors, Internal Workspace Map.
   - **Output**: `[WindowID: TargetRect]`, `ActiveWorkspacePerScreen`, `MouseWarpTarget?`.
   - **Rules**: Apply Separation Rules (Chrome/Code) and Balancing.
4. **Actuate**:
   - Compare `TargetRect` with `CurrentRect`.
   - Execute `AXUIElement` calls _only_ for delta changes.
   - Move hidden windows to "The Stage" (`+30,000, +30,000`).

## 2. Window Classification Rules

### Allow-list (Managed by default)

- `com.google.Chrome`
- `com.microsoft.VSCode`
- **Exception**: If Title contains "DevTools", treat as a separate "App Type" for the Separation Rule.

### Behavior Types

- **Managed**: Resized to `screen.visibleFrame`.
- **Unmanaged**: Position/Size preserved, but assigned to a workspace and hidden/shown as a unit.
- **Ignored**: System overlays, menus, or windows with `AXRole != AXWindow`.

## 3. Keyboard Shortcuts & Workspace Mapping

Workspaces are **relative to the physical screen** (sorted by X-coordinate).

| Screen Position | Workspace Keys                           | Movement Keys       |
| :-------------- | :--------------------------------------- | :------------------ |
| **Left-most**   | `Alt + Z, X, C, V` (1-4), `B` (Cycle 5+) | `Alt + Shift + Z/V` |
| **Middle**      | `Alt + Q, W, E, R` (1-4), `T` (Cycle 5+) | `Alt + Shift + Q/T` |
| **Right-most**  | `Alt + N, M, ,, .` (1-4), `0` (Cycle 5+) | `Alt + Shift + N/0` |

### Movement Logic:

- If Window is on Screen A and "Move to Screen B" is pressed:
  - Assign Window to a new workspace on Screen B.

## 4. Performance & API Guidelines

- **AX UI Element Throttling**: AX calls are synchronous and can hang.
  - Never call AX on the Main Thread if possible, or use a short timeout.
  - **Actuator** must maintain a local cache of "Last Set Position" to avoid redundant IPC calls to `WindowServer`.
- **Mouse Warping**: Use `CGWarpMouseCursorPosition`. This moves the cursor without generating mouse-move events, preventing focus-theft loops.
- **Off-screen Hiding**: Use a coordinate far enough that macOS doesn't try to "snap" it back or include it in Mission Control thumbnails (30k is standard).

## 5. Persistence & Display Reconnection

- **State Store**: A simple JSON or memory-resident `[WindowIdentifier: Metadata]` map.
- **Identifier**: `BundleID + WindowTitle` (best effort) since `CGWindowNumber` is not persistent across app restarts.
- **Reconnection**:
  - When a monitor is disconnected, store the monitor id in the `lastAssociatedDisplayID` field for any app that was on that monitor.
  - When `MonitorStateStore` detects a new `DisplayID`:
  - Search `Metadata` for windows whose `lastAssociatedDisplayID == NewID`.
  - Trigger a Reconciliation to pull them back.
