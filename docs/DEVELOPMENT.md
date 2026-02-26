# TilePilot Development Notes

## Build

```bash
swift build
```

## Run (SwiftPM executable)

```bash
swift run TilePilot
```

Note: for Accessibility/TCC behavior, prefer running the packaged app from `/Applications/TilePilot.app`.

## Package / Install / Relaunch

```bash
scripts/package_dev_app.sh
```

Default behavior:
- installs to `/Applications/TilePilot.app`
- removes legacy `/Applications/Yabai Coach.app` if present (migration cleanup)
- relaunches the installed app

## Signing

Use a local `Developer ID Application` certificate installed in your keychain.

Verify identities:

```bash
security find-identity -v -p codesigning
```

## Config Compatibility

TilePilot intentionally preserves legacy managed marker names:
- `YABAI_COACH MANAGED ...` in `skhdrc`
- `YABAI_COACH YABAI CONFIG ...` in `yabairc`

This avoids breaking existing installations and previously saved rules.
