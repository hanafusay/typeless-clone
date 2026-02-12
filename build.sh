#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/scripts/lib.sh"

INSTALL_DIR="/Applications"
RESET_TCC="${RESET_TCC:-0}"

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
build_release

# -------------------------------------------------------
# 3. Create .app bundle
# -------------------------------------------------------
echo ""
create_app_bundle

# Copy .env if it exists (into Resources, not MacOS — MacOS is for code only)
if [ -f ".env" ]; then
    cp ".env" "${RESOURCES_DIR}/.env"
    echo "  .env copied to Resources"
fi

# -------------------------------------------------------
# 4. Code-sign the app bundle
# -------------------------------------------------------
echo ""
codesign_app

# Verify
echo ""
verify_signature

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
echo "     and enable Koe in BOTH:"
echo "       System Settings > Privacy & Security > Accessibility"
echo "       System Settings > Privacy & Security > Input Monitoring"
echo ""
echo "  3. After enabling, restart the app:"
echo "       pkill -x ${APP_NAME}; open /Applications/${APP_BUNDLE}"
echo ""
echo "Or search 'Koe' in Spotlight (Cmd+Space)"
