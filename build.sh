#!/bin/bash
set -euo pipefail

APP_NAME="TypelessClone"
BUNDLE_ID="com.typelessclone.app"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
INSTALL_DIR="/Applications"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ENTITLEMENTS="Resources/TypelessClone.entitlements"
RESET_TCC="${RESET_TCC:-0}"
DESIGNATED_REQUIREMENT='designated => identifier "com.typelessclone.app"'

# -------------------------------------------------------
# 1. Stop running instance & clean up old installation
# -------------------------------------------------------
echo "=== Stopping existing ${APP_NAME} ==="
pkill -x "${APP_NAME}" 2>/dev/null && echo "  Killed running process" || echo "  No running process"
sleep 1

if [ "${RESET_TCC}" = "1" ]; then
    echo "=== Resetting TCC permissions for ${BUNDLE_ID} ==="
    for service in Accessibility ListenEvent PostEvent; do
        tccutil reset "${service}" "${BUNDLE_ID}" 2>/dev/null && \
            echo "  TCC reset done: ${service}" || \
            echo "  TCC reset skipped: ${service}"
    done
else
    echo "=== TCC reset skipped (set RESET_TCC=1 to reset Accessibility/Input Monitoring/PostEvent) ==="
fi

# -------------------------------------------------------
# 2. Build
# -------------------------------------------------------
echo ""
echo "=== Building ${APP_NAME} (release) ==="
swift build -c release

# -------------------------------------------------------
# 3. Create .app bundle
# -------------------------------------------------------
echo ""
echo "=== Creating app bundle ==="
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy executable
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/"
echo "  Executable copied"

# Copy Info.plist (must be at Contents/Info.plist)
cp "Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
echo "  Info.plist copied"

# Copy .env if it exists (into Resources, not MacOS — MacOS is for code only)
if [ -f ".env" ]; then
    cp ".env" "${RESOURCES_DIR}/.env"
    echo "  .env copied to Resources"
fi

# -------------------------------------------------------
# 4. Code-sign the app bundle
#    - Ad-hoc sign (-s -) is sufficient for local use
#    - --identifier ensures TCC uses the bundle ID
#    - entitlements are optional for this app, but included for consistency
#    - --deep signs nested frameworks/helpers if any
#    - --options runtime enables hardened runtime (optional
#      for local dev but good practice)
# -------------------------------------------------------
echo ""
echo "=== Code signing ==="

# Sign the executable first (inside the bundle)
codesign --force --sign - \
    --identifier "${BUNDLE_ID}" \
    -r="${DESIGNATED_REQUIREMENT}" \
    --entitlements "${ENTITLEMENTS}" \
    "${MACOS_DIR}/${APP_NAME}"
echo "  Signed executable"

# Sign the whole bundle (seals Info.plist & Resources)
codesign --force --sign - \
    --identifier "${BUNDLE_ID}" \
    -r="${DESIGNATED_REQUIREMENT}" \
    --entitlements "${ENTITLEMENTS}" \
    "${APP_BUNDLE}"
echo "  Signed app bundle"

# Verify
echo ""
echo "=== Verifying signature ==="
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}" 2>&1
echo ""
codesign -dvvv "${APP_BUNDLE}" 2>&1 | grep -E "^(Identifier|Info\.plist|Sealed|TeamIdentifier|Signature|Format)"
echo ""
codesign -d --entitlements :- "${APP_BUNDLE}" 2>/dev/null || true
echo ""

# -------------------------------------------------------
# 5. Install to /Applications
# -------------------------------------------------------
echo "=== Installing to ${INSTALL_DIR} ==="
ditto "${APP_BUNDLE}" "${INSTALL_DIR}/${APP_BUNDLE}"
echo "  Installed to ${INSTALL_DIR}/${APP_BUNDLE}"

# Keep /Applications as the only app location to avoid TCC confusion.
rm -rf "${APP_BUNDLE}"
echo "  Removed local ${APP_BUNDLE}"

# -------------------------------------------------------
# 6. Done
# -------------------------------------------------------
echo ""
echo "=== Done ==="
echo ""
echo "Next steps:"
echo "  1. Launch the app:"
echo "       open /Applications/${APP_BUNDLE}"
echo ""
echo "  2. When the accessibility dialog appears, click 'Open System Settings'"
echo "     and enable TypelessClone in BOTH:"
echo "       System Settings > Privacy & Security > Accessibility"
echo "       System Settings > Privacy & Security > Input Monitoring"
echo ""
echo "  3. After enabling, restart the app:"
echo "       pkill -x ${APP_NAME}; open /Applications/${APP_BUNDLE}"
echo ""
echo "Or search 'TypelessClone' in Spotlight (Cmd+Space)"
