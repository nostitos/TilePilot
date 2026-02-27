<p align="center">
  <img src="assets/icon/tilepilot-icon-1024.png" alt="TilePilot icon" width="140" height="140">
</p>

# TilePilot

> Breaking change (2026-02-26): default directional keyboard navigation examples and recommended bindings use an `IJKL` layout instead of `HJKL`. If you rely on older `HJKL` muscle memory, update your `skhdrc` or keep your existing bindings intentionally.

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

## Scripting Addition + SIP (Why It Is Needed)

Some core-feeling desktop actions in TilePilot (such as:
- switching to another desktop with shortcuts like `Option + 1`
- moving the focused window to another desktop and following it
) depend on `yabai`'s **scripting addition**.

### Why this exists (technical reason)

`yabai` can do a lot through normal APIs and its message socket, but macOS desktop/space control is not fully exposed through public APIs in a way that allows all of the window/desktop operations power users expect.

For many desktop/space/window operations, `yabai` relies on a scripting addition loaded into `Dock.app` (the system process that owns the primary connection to the macOS WindowServer for these behaviors). That is why commands such as desktop focus/move can fail with errors mentioning the scripting addition.

Because `Dock.app` is a protected Apple system process, macOS **System Integrity Protection (SIP)** blocks the file/runtime operations needed to install/load this scripting addition unless SIP is **partially** disabled in a way compatible with your Mac model and macOS version.

### Why TilePilot can’t fully automate this

TilePilot can help by generating the Terminal repair/install flow (`Fix Scripting Addition`), but it cannot:
- change SIP settings for you from a normal GUI app
- bypass Recovery Mode requirements
- bypass macOS compatibility limitations after OS updates

## SIP Tradeoffs / Risks (Read This Before Enabling SA)

Disabling SIP protections (even partially) is a real security tradeoff.

### What changes

The exact required SIP changes vary by macOS version and Apple Silicon vs Intel, but the yabai documentation generally requires some combination of:
- filesystem protections disabled (partial SIP change)
- debugging restrictions disabled
- sometimes additional protections depending on macOS version/architecture (for example NVRAM-related requirements on some Apple Silicon setups)

### Side risks involved

- Reduced protection for Apple system processes/files against modification or injection on your machine
- Increased blast radius if malicious software runs with elevated privileges
- Lower alignment with macOS default security posture (important for work-managed devices / compliance-sensitive machines)
- Future macOS updates may break scripting-addition compatibility and require rework
- Apple service/repair workflows may re-enable SIP settings, which can break these features until reconfigured

### Practical recommendation

- Only enable the scripting addition if you want the desktop/space features that require it
- Keep `yabai`, `TilePilot`, and macOS updated
- Prefer a conservative setup on machines with stricter security needs
- Re-enable full SIP if you stop using scripting-addition-dependent features

### Version note (important)

Different `yabai` versions expose different scripting-addition commands.

For example:
- some versions use `--load-sa` (install + load)
- others expose separate `--install-sa` / `--load-sa`

TilePilot now detects this automatically in its repair script, but manual guides online may use command variants that do not match your installed version.

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
