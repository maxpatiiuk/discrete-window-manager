## Aerospace

This is an attempt at implementing a "discrete window manager" using Aerospace.

Read [Behavior spec](WORKSPACE_BEHAVIOR_SPEC.md) for what a discrete window manager is.

Impressions about Aerospace:

- Doesn't require System Integrity Protection disabling, unlike yabai
- Has a nice architecture - the author really thought through it and improved upon i3.

Issues:

- Still in alpha. Doesn't handle macos finder tabs well. Doesn't handle full screen youtube well
- It is written for a workflow of using a single screen, with multiple apps visible at once. There is a big impedance mismatch from trying to make it work "with one app per workspace" and "workspace is always owned by the same display" workflow.
- Config is limited to declarative things. When a monitor disconnects or an app starts, all windows get reset back to a single workspace and shrunk - disruptive.

On this branch I used Copilot to write a companion Rust CLI that is called by the Aerospace config.
It gets complex fast due to the need to work around for the impedance mismatch and keep track of state. The state can be mutated by macOS, user, Aerospace, and the Rust CLI (including separate process of it) - complex and fragile.
