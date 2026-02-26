# TilePilot

TilePilot is a native macOS menu bar app for controlling `yabai` (and optionally `skhd`) with a click-first UI.

It is designed for normal use, not just debugging:
- quick window controls (tile/float/toggle focused window)
- window behavior rules (per-app `Never Tile` / `Always Tile`)
- hover-focus recovery (`focus_follows_mouse`)
- setup and diagnostics tools (kept out of the main quick menu)

## Current Focus

TilePilot is currently optimized for:
- regaining control when `yabai` behavior is disruptive
- making tiling optional/app-specific
- exposing frequent actions in a minimal menu bar quick menu

## Requirements

- macOS 13+
- `yabai` (required for tiling/window control features)
- `skhd` (optional, for shortcut management)

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

