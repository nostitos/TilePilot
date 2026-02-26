<p align="center">
  <img src="assets/icon/tilepilot-icon-1024.png" alt="TilePilot icon" width="140" height="140">
</p>

# TilePilot

TilePilot is a native macOS menu bar app that makes the `yabai` + `skhd` stack usable for normal people without giving up the power users rely on.

`yabai` is a tiling window manager for macOS with a strong command-line interface for querying and controlling windows, desktops, and displays. `skhd` is a fast hotkey daemon for macOS with a simple config DSL and live config reloading. Together they are extremely powerful, but they can be opaque, fragile, and intimidating when something goes wrong.

TilePilot is the third layer in that trio: a click-first control surface for layout control, recovery, app-specific tiling rules, and day-to-day window workflows.

It is designed for normal use, not just debugging:
- quick window controls (tile/float/toggle focused window)
- window behavior rules (per-app `Never Tile` / `Always Tile`)
- hover-focus recovery (`focus_follows_mouse`)
- setup and diagnostics tools (kept out of the main quick menu)

## Why TilePilot Exists

- `yabai` gives you powerful tiling and layout automation.
- `skhd` gives you responsive, scriptable hotkeys.
- TilePilot gives you a visible, understandable control layer when you do not want to memorize commands or chase config issues.

## Current Focus

TilePilot is currently optimized for:
- regaining control when `yabai` behavior is disruptive
- making tiling optional/app-specific
- exposing frequent actions in a minimal menu bar quick menu

## Requirements

- macOS 13+

## Dependencies (TilePilot can install these for you)

TilePilot includes a setup flow that can bootstrap the common dependency stack on a fresh Mac:
- `Homebrew`
- `yabai`
- `skhd`

So `yabai` and `skhd` are not strict prerequisites to launch TilePilot.

What still requires manual user approval:
- Accessibility permissions (macOS)
- Some Mission Control settings
- Optional advanced `yabai` features that depend on SIP / scripting-addition setup

## Run (Development)

```bash
swift build
swift run TilePilot
```

## Package Dev App (Recommended)

This builds a real `.app`, installs it to `/Applications`, and relaunches it:

```bash
scripts/package_dev_app.sh
```

Useful options:

```bash
scripts/package_dev_app.sh --no-open
scripts/package_dev_app.sh --release
scripts/package_dev_app.sh --no-install
```

## Code Signing (Developer ID)

The project supports signing the packaged app with a local Developer ID Application identity.

The packaging script will sign automatically when configured (see `scripts/package_dev_app.sh`).

## Main UI Areas

- `TilePilot` (main view): windows/desktops overview + focused window controls
- `Window Behavior`: global default tiling mode, hover focus, app rules
- `Actions`: quick layout/window commands
- `Shortcuts`: parses and shows `skhdrc`
- `Config`: managed `skhdrc` section editor
- `Setup & Health`: setup checks and diagnostics

## Notes

- TilePilot preserves your existing `yabairc` and `skhdrc` content outside the app-managed blocks.
- For compatibility, existing managed marker names (`YABAI_COACH ...`) are intentionally preserved.
