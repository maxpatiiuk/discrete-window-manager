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

### 2. Build the app once

You can build in Xcode, or from the repository root with:

```bash
./run.js --no-log
```

This helps Xcode and SourceKit understand the target configuration.

## Running the App

On launch, the app attempts to register itself as a login item so it starts automatically in future login sessions.

On first launch, macOS should prompt for Accessibility permission. If it does not, open:

- System Settings
- Privacy & Security
- Accessibility

Once the app is running, press `Option+S` to toggle the center-screen indicator.

### Develop, Build, Run

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
