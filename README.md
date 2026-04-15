# Discrete window manager

A "one-app-per-screen" macOS window manager designed for focus and speed.

[Blog post about how it was built](https://max.patii.uk/articles/discrete-window-manager/).

## Key features

- Instant switch between apps (bypasses 500ms macOS Spaces animation).
- Full multi-monitor support. Restores window positions on display reconnection.
- Automatically full-screens productivity apps (Chrome, VS Code, Terminal).
- Does not touch what it doesn't understand: macOS tabs, dialogs, Music mini player.

## Core concepts

A "workspace" is what you see at a given time.
Workspaces belong to monitors.
Full-screen apps occupy an entire workspace.

You can jump instantly to a specific workspace with a single keystroke:

- `Alt + Z X C V B` for the left-most/first monitor
- `Alt + Q W E R T` for the middle/second monitor
- `Alt + N M < > 0` for the right-most/third monitor

https://github.com/user-attachments/assets/d6aa0e2c-0e89-4e1e-b1e2-fb3b03337074

Key feature: an app that is opened on the `Alt+Z` workspace stays there unless you move it. This way you can build strong muscle memory for rapid switching between apps.

If you switch workspaces, the focus and mouse position move with you.

To move things, you can move the workspace left/right between its siblings using `Alt + H / L`.
You can move an app to a different monitor using `Alt + Shift + Z / Q / N`.

Press `Alt + S` to toggle the indicator of open workspaces and their apps. The indicator is off by default to minimize distractions.
Use `Alt + A` for debug view.

## Configuration

Window manager operates on a strict "don't break things you don't understand" principle.

See [Configuration.swift](./window-manager/Configuration.swift) for configurable options. Update the configuration to explicitly allowlist the apps you want to be automatically resized and managed.

Run the following to get a list of currently open app bundle IDs:

```sh
osascript <<'APPLESCRIPT'
tell application "System Events"
set appIDs to bundle identifier of (application processes where background only is false)
end tell
set AppleScript's text item delimiters to linefeed
return appIDs as text
APPLESCRIPT
```

You can press `Alt + U` to toggle the "managed mode" for any currently focused app.

## Prerequisites

Window managing is extremely specific to your preferences and workflows.

This project is tailored to my workflow. You can fork it, and update the config, or use Agents to modify functionality.

[Blog post about how you can build your own window manager](https://max.patii.uk/articles/discrete-window-manager/).

To build the project locally, you need:

- Xcode installed from the App Store
- Xcode Command Line Tools selected
- VS Code with the Swift extension if you want to work in VS Code

Verify the active Xcode toolchain:

```bash
xcode-select -p
xcrun --find sourcekit-lsp
```

Install `xcode-build-server` for use by the Swift VS Code extension:

```bash
brew install xcode-build-server
```

## Develop, Build, Run

Daily development does not require running Xcode.

Do a debug build and restart the app:

```bash
./run.js
```

Do a production build:

```bash
./run.js --release
```

See `./run.js --help` for all flags.

On first launch, the app attempts to register itself as a login item so it starts automatically in future login sessions. It also asks for Accessibility permission.

## Structure

- [Configuration](./window-manager/Configuration.swift): Allowlist the apps window manager can touch, and keybindings.
- [WindowManagerRuntime](./window-manager/WindowManagerRuntime.swift): Central orchestrator. Handles keystrokes.
- [WorkspaceManager](./window-manager/WorkspaceManager.swift): Creates workspaces for windows and manages state.
- [WindowStateStore](./window-manager/WindowStateStore.swift): Polls and stores macOS window information.
- [MonitorStateStore](./window-manager/MonitorStateStore.swift): Monitors display configurations and screen frame changes.
- [Actuator](./window-manager/Actuator.swift): Remembers last known layout to minimize redundant window operations.
- [AXWindowUtility](./window-manager/AXWindowUtility.swift): Low-level Accessibility API wrapper for interacting with `AXUIElement` objects (Move, Resize, Focus).
- [AXObserverManager](./window-manager/AXObserverManager.swift): Same, but at the application level rather than the window level.
- [GlobalHotKeyMonitor](./window-manager/GlobalHotKeyMonitor.swift): Listens for hotkeys.
- [IndicatorWindowController](./window-manager/IndicatorWindowController.swift): A simple non-interactive state overlay.

## Prior art

1. See [Aerospace implementation](https://github.com/maxpatiiuk/discrete-window-manager/tree/aerospace#readme) of a discrete window manager.

2. See [Phoenix attempt](https://github.com/maxpatiiuk/discrete-window-manager/tree/phoenix#readme).
