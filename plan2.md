# plan2.md — Auto Layout Rename + Grid Behavior

## What changed

1. Replaced `readable-current-space.sh` behavior with a grid-first implementation under:
   - `~/.config/yabai/scripts/auto-layout-current-desktop.sh`
2. Updated `Shift + Option + M` in `skhdrc` to call the new script.
3. Kept backward compatibility:
   - `~/.config/yabai/scripts/readable-current-space.sh` is now a wrapper alias to the new script.
4. Updated TilePilot shortcut title mapping:
   - `Auto Layout (Current Desktop)`

## Behavior contract

- Uses visible, non-minimized, non-hidden windows from current desktop.
- Filters to packable windows (`can-move`, `can-resize`, non-native-fullscreen).
- Applies deterministic near-square grid placement.
- Leaves packed windows floating.
- Never switches to stack layout.

## Rationale

The previous `>4 => stack` behavior is not appropriate for large displays and produces low-utility single-window emphasis. The new behavior is density-oriented and monitor-size friendly.
