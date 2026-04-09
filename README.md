<p align="center">
  <img src="assets/icon/tilepilot-icon-1024.png" alt="TilePilot icon" width="140" height="140">
</p>

# TilePilot

TilePilot is a native macOS productivity tool inspired by i3.

It helps regular Mac users move toward a predictable, keyboard-driven window workflow without starting from a terminal-first setup. Under the hood it uses `yabai` and `skhd`, but the product goal is broader than “make the helpers run”: TilePilot is meant to make an i3-style way of working feel learnable on macOS.

## What That Means

TilePilot is built around a few ideas that come directly from the kind of workflow i3 is known for:

- stable desktops that stay predictable instead of constantly reordering themselves
- a small set of repeatable actions for focus, movement, tiling, and recovery
- tiled windows as the normal working state
- floating windows as an explicit exception when an app does not tile well
- keyboard shortcuts as the long-term path, with the GUI acting as scaffolding

TilePilot is not trying to be a literal i3 clone on macOS. It is a practical transition layer for people who want the focus and speed of an i3-style workflow without giving up native macOS setup, visibility, and recovery tools.

## What TilePilot Helps You Do

- learn and run keyboard actions from a GUI before fully relying on memory
- keep desktops and window state understandable through `Overview`, badges, and `MegaMap`
- scrub between desktops with the mouse by holding a trigger and moving left or right
- switch windows between floating and tiled states without losing track of what happened
- rebuild a messy desktop into a usable tiled layout quickly
- set app-level exceptions such as `Never Auto-Tile App` or `Keep App on Top`
- create reusable floating layout templates for a display and apply them to the current desktop
- import the current desktop layout into a template and constrain slots to specific apps
- manage `yabairc` and `skhdrc` safely without overwriting the rest of your config
- recover from drifted permissions, helpers, or services through Guided Setup and `System`

## Core Workflow

If you want to use TilePilot the way it is intended, the path looks like this:

1. Use `Overview` to understand what desktops and windows exist right now.
2. Learn the core actions in `Actions & Shortcuts`.
3. Let `Behaviors` define the defaults: which desktops tile, which apps never auto-tile, how focus behaves.
4. Use `Templates` when you want an exact floating layout for a display instead of a general tiled layout.
5. Use `Appearance`, `MegaMap`, badges, and the right-click menu as visibility and recovery tools, not as the primary workflow.
6. Gradually rely more on the keyboard and less on the GUI.

## Main UI Areas

- `Overview`
  - the daily command center
  - shows displays, desktops, windows, focused state, and recovery when live state is degraded
- `Behaviors`
  - sets the rules behind the workflow
  - desktop tiling, desktop scrub, app rules, focus behavior, cursor behavior, and yabai mouse controls
- `Actions & Shortcuts`
  - the action catalog and shortcut learning surface
  - record shortcuts, edit them, and pin frequent ones to the right-click menu
- `Appearance`
  - controls visual feedback and tiling spacing
  - badges, outline overlay, outline width, screen edge padding, and gap between tiled windows
- `Templates`
  - manages exact floating layouts for the current display shape
  - draw slots, split and duplicate them, import the current desktop layout, and constrain slots to specific apps
- `Config Files`
  - raw editing for managed config files and scripts
  - includes backups and restore flows
- `How It Works`
  - visual explanations of the main concepts so settings tabs can stay focused on changing behavior
- `System`
  - setup, health, update checks, diagnostics, and Guided Setup reopen paths

## Main Layout Actions

TilePilot now names layout actions by their outcome:

- `Float All Windows on This Desktop`
  - stops tiling the eligible windows on the current desktop so you can move and overlap them freely
- `Tile All Windows on This Desktop`
  - tiles the eligible windows on the current desktop and leaves `Never Auto-Tile` apps floating
- `Arrange Windows into a Floating Grid`
  - places windows into a grid-like arrangement and leaves them floating
- `Retile Windows into a Balanced Tiled Layout`
  - rebuilds the current desktop into a more even tiled layout
- `Rebalance Tiled Window Sizes`
  - redistributes space across the tiled windows that are already on the current desktop

This naming is deliberate: the app should tell you where windows will end up, not force you to guess.

## Desktop Scrub

TilePilot also supports mouse-driven desktop scrubbing:

- hold the selected trigger keys
- move the mouse left or right to scrub between desktops
- let go of the trigger keys and macOS settles on the desktop you scrubbed to

You can enable it and change the trigger keys in `Behaviors`.

## Setup

### Requirements

- macOS 13+

### Install

1. Download the latest DMG from [Releases](https://github.com/nostitos/TilePilot/releases/latest).
2. Drag `TilePilot.app` into `Applications`.
3. Open TilePilot.
4. Follow Guided Setup if helpers, permissions, or services still need attention.

### First-Time Setup

TilePilot ships with bundled `yabai` and `skhd` helpers and installs/manages them for you.

You may still need to approve:

- Accessibility for `TilePilot`, `yabai`, and `skhd`
- Screen Recording if you want real `MegaMap` screenshots
- Start at Login if you want TilePilot available after sign-in

For the most predictable desktop behavior on macOS, TilePilot expects these Mission Control settings:

- `Automatically rearrange Spaces based on most recent use`: `Off`
- `Displays have separate Spaces`: `On`

Path in macOS Settings:

- `Desktop & Dock` -> `Mission Control`

## Supported Scope

TilePilot currently focuses on the everyday supported path:

- bundled helper install and recovery
- keyboard actions, shortcut learning, and right-click menu pinning
- tiled and floating window control
- exact floating layout templates with app-aware slot rules
- live desktop visibility through `Overview`, overlays, and `MegaMap`
- safe config management for TilePilot-managed sections

Advanced scripting-addition / SIP-dependent desktop-control workflows are intentionally out of scope for now.

## Privacy and Safety

- `MegaMap` screenshots stay in memory only for the current app session and are never written to disk.
- TilePilot preserves your existing `yabairc` and `skhdrc` content outside the app-managed blocks.
- TilePilot-managed config uses `TILEPILOT ...` markers so the app only edits what it owns.
- Each release ships a versioned defaults profile for fresh installs and explicit reset flows.

## Updates

- TilePilot can check GitHub Releases for newer stable versions.
- The app links you to the release page rather than silently downloading or installing anything.

## For Power Users

TilePilot still exposes the underlying tools when you want them:

- `Config Files` lets you edit `yabairc`, `skhdrc`, and referenced scripts directly.
- Legacy aliases are kept where compatibility matters, but the product surfaces use clearer outcome-based names.
- `bootstrap.sh` is treated as a legacy reset helper, not a normal day-to-day layout action.

## Developers

Build, packaging, signing, and UI context details are in:

- [Development Notes](docs/DEVELOPMENT.md)
- [GUI And Design Context](docs/GUI_DESIGN_CONTEXT.md)
