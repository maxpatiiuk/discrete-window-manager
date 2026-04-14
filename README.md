# window-manager

Minimal macOS window-manager app built with Swift and Xcode.

The app currently:

- runs as an accessory app, so it does not appear in the Dock or Cmd-Tab
- registers itself to launch at login
- requests Accessibility permission on launch
- can show non-interactive indicator windows in the center of the screen
- toggles a persistent indicator with `Option+S`

## Project Layout

- `window-manager/`: app source files
- `window-manager.xcodeproj/`: Xcode project and build settings
- `window-managerTests/`: unit tests
- `window-managerUITests/`: UI tests
- `buildServer.json`: VS Code build-server config for Swift language features

## Prerequisites

You need:

- Xcode installed from the App Store
- Xcode Command Line Tools selected
- VS Code with the Swift extension if you want to work in VS Code

Verify the active Xcode toolchain:

```bash
xcode-select -p
xcrun --find sourcekit-lsp
```

Install xcode-build-server for usage by Swift VSCode extension:

```bash
brew install xcode-build-server
```

## First-Time Setup

### 1. Open the project once in Xcode

Open `window-manager.xcodeproj` in Xcode so Xcode can finish any first-run setup such as signing, simulator/device metadata, and derived data.

### 2. Build the app once

You can build in Xcode, or from the terminal:

```bash
xcodebuild -project window-manager.xcodeproj -scheme window-manager -destination 'platform=macOS' build
```

This helps Xcode and SourceKit understand the target configuration.

## Running the App

Run from Xcode with the `window-manager` scheme.

On launch, the app attempts to register itself as a login item so it starts automatically in future login sessions.

On first launch, macOS should prompt for Accessibility permission. If it does not, open:

- System Settings
- Privacy & Security
- Accessibility

Then enable the app manually.

Once the app is running, press `Option+S` to toggle the center-screen indicator.

### Command-Line Control

Because this is an accessory app, it does not have a Dock icon or normal app window. These commands are useful for starting and stopping it manually.

Build the app from the command line:

```bash
xcodebuild -project window-manager.xcodeproj -scheme window-manager -destination 'platform=macOS' build
```

Start the latest Debug build:

```bash
open "$(ls -1dt ~/Library/Developer/Xcode/DerivedData/window-manager-* | head -n1)/Build/Products/Debug/window-manager.app"
```

Build a production-style Release build:

```bash
xcodebuild -project window-manager.xcodeproj -scheme window-manager -configuration Release -destination 'platform=macOS' build
```

Start the latest Release build:

```bash
open "$(ls -1dt ~/Library/Developer/Xcode/DerivedData/window-manager-* | head -n1)/Build/Products/Release/window-manager.app"
```

Check whether it is running:

```bash
pgrep -x window-manager
```

Show matching processes with command information:

```bash
ps -p "$(pgrep -x window-manager | paste -sd ' ' -)" -o pid=,etime=,command=
```

Stop all running instances:

```bash
pkill -x window-manager
```

Stop a specific instance:

```bash
kill <pid>
```

## Logging

The app uses Apple Unified Logging via `OSLog`.

- `debug` logs are emitted only in Debug builds
- `info` and `error` logs are emitted in Debug and Release builds

You can inspect logs in Console.app or from the terminal.

Example live stream:

```bash
log stream --style compact --type log --level debug --predicate 'subsystem == "uk.patii.max.window-manager"'
```

## Development Notes

- this is an accessory app, so no normal main window is expected
- Accessibility APIs generally require the app to be unsandboxed for real window-management behavior
- if editor navigation breaks in VS Code, first rebuild once and restart SourceKit-LSP before changing code or project structure
