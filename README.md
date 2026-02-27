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
- `yabai` scripting-addition setup (and SIP configuration) for desktop switching / move-window desktop shortcuts and other advanced window/desktop control features

## Scripting Addition + SIP

Some desktop actions (especially moving windows between desktops and some desktop-focus workflows) depend on yabai’s scripting addition, which may require partial SIP changes depending on macOS version and hardware; TilePilot can launch repair/install helpers, but it cannot change SIP or bypass Recovery Mode and system security constraints. Treat this as an explicit security tradeoff, keep your stack updated, and use the official yabai SIP guide for current requirements: <https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection>.

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

## Build Release DMG

Build a release `.app` and package a drag-and-drop DMG with a custom background:

```bash
scripts/build_release_dmg.sh --version v0.1.0
```

Output:

- `dist/TilePilot-v0.1.0.dmg`

DMG background asset:

- `assets/dmg/dmg-background.png`

Regenerate background design:

```bash
scripts/generate_dmg_background.sh
```

Create a GitHub release and upload the DMG:

```bash
gh release create v0.1.0 dist/TilePilot-v0.1.0.dmg \
  --title "TilePilot v0.1.0" \
  --notes "Release build with signed app bundle and drag-and-drop DMG installer."
```

## Code Signing (Developer ID)

The project supports signing the packaged app with a local Developer ID Application identity.

The packaging script will sign automatically when configured (see `scripts/package_dev_app.sh`).

## Main UI Areas

- `TilePilot` (main view): windows/desktops overview + focused window controls
- `Window Behavior`: global default tiling mode, hover focus, app rules
- `Actions & Shortcuts`: unified controls list with shortcut learning + quick actions
- `Config Files`: raw editing for `yabairc`, `skhdrc`, and referenced scripts
- `System`: essentials checklist + direct fix actions
  - Advanced sections (collapsed by default): managed `skhdrc` editor, diagnostics logs

## Shortcut Row Copy Style

Shortcut rows are phrased as actions, not shell internals.

- Line 1 (title): derived from the script filename and cleaned for display.
  - Example: `disable-tiling-all-visible.sh` -> `Disable Tiling All Visible`
- Line 2 (description): first comment header line (`# ...`) from the script, when available.
- Duplicate copy is collapsed automatically:
  - if normalized title and description match, TilePilot hides the second line.

### Script Header Description Convention

For TilePilot-managed scripts, add one plain-English comment line right after the shebang:

```bash
#!/usr/bin/env bash
# Disable tiling for all visible windows on the current desktop.
set -euo pipefail
```

Fallback behavior:
- if a script is missing, unreadable, or has no usable header comment, TilePilot falls back to a cleaned filename-based sentence.

## Notes

- TilePilot preserves your existing `yabairc` and `skhdrc` content outside the app-managed blocks.
- TilePilot-managed config blocks use `TILEPILOT ...` markers.
- See the official yabai SIP guide before changing SIP settings: <https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection>
- See Apple’s security documentation for what SIP protects: <https://support.apple.com/guide/security/system-integrity-protection-secb7ea06b49/web>
