#!/bin/bash
# generate-icon.sh — アプリアイコン (.icns) + メニューバーアイコン (template PNG) を生成
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESOURCES_DIR="${PROJECT_DIR}/Resources"
ICONSET_DIR="${PROJECT_DIR}/.build/AppIcon.iconset"
BASE_PNG="${PROJECT_DIR}/.build/AppIcon_1024.png"

mkdir -p "${PROJECT_DIR}/.build"

# -------------------------------------------------------
# 1. Generate base 1024x1024 PNG using Swift script
# -------------------------------------------------------
echo "=== Generating app icon ==="
swift "${SCRIPT_DIR}/generate-icon.swift" app "${BASE_PNG}"

# -------------------------------------------------------
# 2. Create iconset with all required sizes
# -------------------------------------------------------
echo "=== Creating iconset ==="
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

declare -a SIZES=(
    "16:icon_16x16.png"
    "32:icon_16x16@2x.png"
    "32:icon_32x32.png"
    "64:icon_32x32@2x.png"
    "128:icon_128x128.png"
    "256:icon_128x128@2x.png"
    "256:icon_256x256.png"
    "512:icon_256x256@2x.png"
    "512:icon_512x512.png"
    "1024:icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
    px="${entry%%:*}"
    name="${entry##*:}"
    sips -z "${px}" "${px}" "${BASE_PNG}" --out "${ICONSET_DIR}/${name}" >/dev/null 2>&1
    echo "  ${name} (${px}x${px})"
done

# -------------------------------------------------------
# 3. Convert iconset to icns
# -------------------------------------------------------
echo "=== Converting to icns ==="
iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"
echo "  Created: ${RESOURCES_DIR}/AppIcon.icns"

# -------------------------------------------------------
# 4. Generate menu bar template icons
# -------------------------------------------------------
echo "=== Generating menu bar icons ==="
swift "${SCRIPT_DIR}/generate-icon.swift" menu1x "${RESOURCES_DIR}/MenuBarIcon.png"
swift "${SCRIPT_DIR}/generate-icon.swift" menu   "${RESOURCES_DIR}/MenuBarIcon@2x.png"

# -------------------------------------------------------
# Clean up
# -------------------------------------------------------
rm -rf "${ICONSET_DIR}" "${BASE_PNG}"

echo ""
echo "=== Done ==="
echo "  App icon:     ${RESOURCES_DIR}/AppIcon.icns"
echo "  Menu bar 1x:  ${RESOURCES_DIR}/MenuBarIcon.png"
echo "  Menu bar 2x:  ${RESOURCES_DIR}/MenuBarIcon@2x.png"
