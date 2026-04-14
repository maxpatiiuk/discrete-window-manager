Context:
This project is a simple macOS window manager.
For personal use - don't need customization.
Encourages only one visible window at a time (entire screen of chrome, or vscode).
What are the best ways to hide a window? Move it the screen edge? This is what aerospace does
Avoid using macos spaces - they have a 500ms non-disableable animation

Principles:

- should not touch the non-full-size windows (music, dialogs, settings). if it helps simplify the implementation, we can hardcode app ids of windows we support controlling.
- anything we don't support should be left alone to avoid breaking the system or interfering with user workflows. the goal is to automate some workflows for most commonly used apps, not force macos to behave like a super strict tiling window manager.

Suggested concepts:

- Have workspaces (that are conceptually like aerospace's workspaces). Each display has its own workspaces and workspaces are always tied to the screen. Workspaces are just an abstraction concept - the actual api calls to apple would just be moving or hiding a single visible app, with the rest being internal state housekeeing.
- Only manage things in the main space per screen - ignore all other spaces. I won't be using native macos fullscreen mode to avoid the spaces animation, but if I do (eg youtube fullscreen), it shouldn't freak out

Actions:

- A hotkey to organize my windows into workspaces. Permit running this often so that we can run it when a new program is opened. Ideas:
  - When a new code window opens, open it full size. collapse all other windows on this screen. under the hood allocate a new workspace for this app (the last workspace on that screen).
  - Try to keep chrome on one workspace, vscode on another, all misc apps on the workspace that has chrome, and any extra code windows staggered between the two.
- A way to move windows between screens
- A way to move window to next/prev workspace on the screen
- A way to jump to an exact workspace on a given screen (alt+ many spare letters)

Prior implementation:
I tried to make this work in Aerospace.
my impressions:
doesn't require sip disabling. nice architecture
still alpha. doesn't handle macos finder tabs well. doesn't handle full screen youtube well
main issue: it is written for a single screen multi workspace very split screen workflows. big impedance mismatch trying to make it work with one app per workspace and workspace always tied to display workflow
config is limited to declarative things. when monitor disconnects or app starts all windows get reset back to single workspace and shrunk - disruptive
used copilot to write a companion rust cli that is called by the config. gets complex fast to workaount for the impedance mismatch and keep track of state (mutated by apple, user, aerospace and rust)
See /Users/maxpatiiuk/g/dotfiles/aerospace/WORKSPACE_BEHAVIOR_SPEC.md and /Users/maxpatiiuk/g/dotfiles/aerospace/aerospace.toml for more details on the workspace behavior I was trying to do (some of it was overly complicated due to need to workaround aerospace's limitations).

What is completed:
Swift app that requests the permissions, observes monitor and window changes, watches keyboard keystroke, and renders the state in a debug dialog.
