#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="TilePilot"
DIST_DIR="$ROOT_DIR/dist"
VERSION="${TILEPILOT_RELEASE_VERSION:-v0.1.0}"
VOL_NAME="$APP_NAME"
DMG_NAME="${APP_NAME}-${VERSION}"
FINAL_DMG="$DIST_DIR/${DMG_NAME}.dmg"
TEMP_DMG="$DIST_DIR/${DMG_NAME}-temp.dmg"
BACKGROUND_IMG="$ROOT_DIR/assets/dmg/dmg-background.png"

usage() {
  cat <<EOF
Usage: scripts/build_release_dmg.sh [options]

Builds a signed release app bundle and packages a drag-and-drop DMG.

Options:
  --version <v>     Release version label in dmg filename (default: ${VERSION})
  --no-sign-dmg     Skip code-signing the DMG artifact
  --help            Show this help

Examples:
  scripts/build_release_dmg.sh
  scripts/build_release_dmg.sh --version v0.2.0
EOF
}

SIGN_DMG=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      shift
      VERSION="${1:-}"
      if [[ -z "$VERSION" ]]; then
        echo "--version requires a value" >&2
        exit 1
      fi
      DMG_NAME="${APP_NAME}-${VERSION}"
      FINAL_DMG="$DIST_DIR/${DMG_NAME}.dmg"
      TEMP_DMG="$DIST_DIR/${DMG_NAME}-temp.dmg"
      ;;
    --no-sign-dmg)
      SIGN_DMG=0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

resolve_sign_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application: / {print $2}' \
    | head -n 1
}

echo "Building signed release app..."
"$ROOT_DIR/scripts/package_dev_app.sh" --release --no-install --no-open

APP_PATH="$DIST_DIR/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app not found at: $APP_PATH" >&2
  exit 1
fi

if [[ ! -f "$BACKGROUND_IMG" ]]; then
  echo "Generating DMG background..."
  "$ROOT_DIR/scripts/generate_dmg_background.sh" "$BACKGROUND_IMG"
fi

mkdir -p "$DIST_DIR"
rm -f "$FINAL_DMG" "$TEMP_DMG"

if [[ -d "/Volumes/$VOL_NAME" ]]; then
  hdiutil detach "/Volumes/$VOL_NAME" -force >/dev/null 2>&1 || true
fi

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tilepilot-dmg-stage.XXXXXX")"
trap 'hdiutil detach "/Volumes/'"$VOL_NAME"'" -force >/dev/null 2>&1 || true; rm -rf "$STAGE_DIR"' EXIT

cp -R "$APP_PATH" "$STAGE_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGE_DIR/Applications"
mkdir -p "$STAGE_DIR/.background"
cp "$BACKGROUND_IMG" "$STAGE_DIR/.background/background.png"

echo "Creating read/write DMG..."
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE_DIR" \
  -fs APFS \
  -format UDRW \
  -ov \
  "$TEMP_DMG" >/dev/null

echo "Applying Finder layout..."
ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG")"
DEVICE="$(echo "$ATTACH_OUTPUT" | awk '/\/Volumes\// {print $1; exit}')"
MOUNT_POINT="$(echo "$ATTACH_OUTPUT" | awk '/\/Volumes\// {print $NF; exit}')"

if [[ -z "$DEVICE" || -z "$MOUNT_POINT" ]]; then
  echo "Failed to mount temporary DMG." >&2
  exit 1
fi

/usr/bin/SetFile -a V "$MOUNT_POINT/.background" || true

/usr/bin/osascript <<EOF
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 1180, 760}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 14
    set background picture of opts to file ".background:background.png"
    set position of item "${APP_NAME}.app" of container window to {320, 420}
    set position of item "Applications" of container window to {920, 420}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF

sync
hdiutil detach "$DEVICE" >/dev/null

echo "Creating compressed DMG..."
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$FINAL_DMG" >/dev/null
rm -f "$TEMP_DMG"

if [[ $SIGN_DMG -eq 1 ]]; then
  SIGN_IDENTITY="$(resolve_sign_identity)"
  if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "Signing DMG with: $SIGN_IDENTITY"
    /usr/bin/codesign --force --timestamp --sign "$SIGN_IDENTITY" "$FINAL_DMG"
    /usr/bin/codesign --verify --verbose "$FINAL_DMG"
  else
    echo "No Developer ID Application identity found; leaving DMG unsigned."
  fi
fi

echo
echo "Release DMG ready:"
echo "  $FINAL_DMG"
