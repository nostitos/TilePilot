#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="${1:-$ROOT_DIR/assets/dmg/dmg-background.png}"
ICON_PATH="$ROOT_DIR/assets/icon/tilepilot-icon-1024.png"

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick (magick) is required to generate the DMG background." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

magick -size 1280x800 gradient:'#0B1220-#1C2E50' \
  \( -size 1280x800 radial-gradient:'#6BA4FF66-#0B122000' \) -compose screen -composite \
  \( -size 1280x800 radial-gradient:'#3B82F622-#0B122000' \) -gravity southeast -composite \
  -fill '#FFFFFF15' -draw "circle 340,410 340,580" \
  -fill '#FFFFFF14' -draw "circle 940,410 940,580" \
  -stroke '#E2E8F0C0' -strokewidth 8 -fill none -draw "path 'M 510,410 C 640,300 780,300 840,410'" \
  -fill '#E2E8F0C0' -stroke none -draw "polygon 840,410 805,392 811,428" \
  -fill '#F8FAFC' -font 'Helvetica-Bold' -pointsize 62 -gravity north -annotate +0+78 'Install TilePilot' \
  -fill '#CBD5E1' -font 'Helvetica' -pointsize 30 -gravity north -annotate +0+164 'Drag TilePilot to Applications' \
  -fill '#BFDBFE' -font 'Helvetica-Bold' -pointsize 26 -draw "text 250,640 'TilePilot.app'" \
  -fill '#BFDBFE' -font 'Helvetica-Bold' -pointsize 26 -draw "text 862,640 'Applications'" \
  \( "$ICON_PATH" -resize 138x138 \) -gravity northwest -geometry +38+34 -composite \
  "$OUTPUT_PATH"

echo "Generated DMG background:"
echo "  $OUTPUT_PATH"
