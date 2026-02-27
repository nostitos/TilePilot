<p align="center">
  <img src="assets/icon/tilepilot-icon-1024.png" alt="TilePilot icon" width="140" height="140">
</p>

# TilePilot

TilePilot is a native macOS menu bar app that makes `yabai` + `skhd` practical for everyday use.

## What You Can Do

- Tile or float windows without touching terminal commands
- Control default behavior (`Manual Tiling`, `Hover Focus`, `Cursor Follows Focus`)
- Set per-app rules (`Never Tile`, `Always Tile`)
- Learn and run shortcuts from a GUI
- Edit `yabairc`, `skhdrc`, and helper scripts in one place
- Recover quickly when setup or services drift

## Requirements

- macOS 13+

## Main UI Areas

- `TilePilot` (main view): windows/desktops overview + focused window controls
- `Window Behavior`: global default tiling mode, hover focus, app rules
- `Actions & Shortcuts`: unified controls list with shortcut learning + quick actions
- `Config Files`: raw editing for `yabairc`, `skhdrc`, and referenced scripts
- `System`: essentials checklist + direct fix actions
  - Advanced sections (collapsed by default): managed `skhdrc` editor, diagnostics logs

## Install (Binary)

1. Download the latest DMG from [Releases](https://github.com/nostitos/TilePilot/releases/latest).
2. Drag `TilePilot.app` into `Applications`.
3. Open TilePilot and use the `System` tab for first-time setup checks.

## Dependencies

TilePilot can bootstrap common dependencies on a fresh Mac:

- `Homebrew`
- `yabai`
- `skhd`

Manual approvals still required:

- Accessibility permissions (macOS)
- Some Mission Control settings
- Optional scripting-addition setup for advanced desktop/window controls

## Scripting Addition + SIP (Advanced)

Some advanced desktop actions (especially moving windows between desktops) depend on yabai’s scripting addition, which may require partial SIP changes depending on macOS version/hardware; TilePilot can launch repair/install helpers, but it cannot change SIP or bypass Recovery Mode/security constraints. Review official guidance before enabling it: <https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection>.

## Notes

- TilePilot preserves your existing `yabairc` and `skhdrc` content outside the app-managed blocks.
- TilePilot-managed config blocks use `TILEPILOT ...` markers.

## Developers

Build, packaging, and signing details are in:

- `/Users/t/Documents/KLODE/YabaiUI/docs/DEVELOPMENT.md`
