# window-manager

Minimal macOS window-manager app built with Swift and Xcode.

The app currently:

- runs as an accessory app, so it does not appear in the Dock or Cmd-Tab
- requests Accessibility permission on launch
- can show temporary non-interactive indicator windows in the center of the screen

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
- Homebrew plus `xcode-build-server` if you want Swift navigation in VS Code for this Xcode project

Verify the active Xcode toolchain:

```bash
xcode-select -p
xcrun --find sourcekit-lsp
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

### 3. Set up VS Code Swift support for this Xcode project

Swift Package Manager projects usually work directly in VS Code. Xcode projects usually need an extra adapter so `sourcekit-lsp` can understand the project build settings.

Install the adapter:

```bash
brew install xcode-build-server
```

Generate the workspace config:

```bash
xcode-build-server config -project window-manager.xcodeproj -scheme window-manager
```

That creates `buildServer.json` in the repository root.

Then in VS Code:

- run `Swift: Select Toolchain` and choose the Xcode toolchain if needed
- run `Swift: Restart SourceKit-LSP`
- run `Developer: Reload Window`

After that, features like Go to Definition should work.

## Running the App

Run from Xcode with the `window-manager` scheme.

On first launch, macOS should prompt for Accessibility permission. If it does not, open:

- System Settings
- Privacy & Security
- Accessibility

Then enable the app manually.

## Logging

The app uses Apple Unified Logging via `OSLog`.

- `debug` logs are emitted only in Debug builds
- `info` and `error` logs are emitted in Debug and Release builds

You can inspect logs in Console.app or from the terminal.

Example live stream:

```bash
log stream --predicate 'subsystem == "uk.patii.max.window-manager"'
```

## Development Notes

- this is an accessory app, so no normal main window is expected
- Accessibility APIs generally require the app to be unsandboxed for real window-management behavior
- if editor navigation breaks in VS Code, first rebuild once and restart SourceKit-LSP before changing code or project structure
