#!/bin/bash
# scripts/lib.sh — build.sh / create-dmg.sh 共通処理
#
# Usage:
#   source scripts/lib.sh

set -euo pipefail

# -------------------------------------------------------
# 共通変数
# -------------------------------------------------------
APP_NAME="TypelessClone"
BUNDLE_ID="com.typelessclone.app"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ENTITLEMENTS="Resources/TypelessClone.entitlements"
DESIGNATED_REQUIREMENT="designated => identifier \"${BUNDLE_ID}\""

# -------------------------------------------------------
# build_release — swift build -c release
# -------------------------------------------------------
build_release() {
    echo "=== Building ${APP_NAME} (release) ==="
    swift build -c release
}

# -------------------------------------------------------
# create_app_bundle — .app バンドルを作成
# -------------------------------------------------------
create_app_bundle() {
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

    # Copy app icon
    if [ -f "Resources/AppIcon.icns" ]; then
        cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
        echo "  AppIcon.icns copied"
    fi

    # Copy menu bar icons
    for f in Resources/MenuBarIcon*.png; do
        [ -f "$f" ] && cp "$f" "${RESOURCES_DIR}/" && echo "  $(basename "$f") copied"
    done
}

# -------------------------------------------------------
# codesign_app — ad-hoc コード署名
# -------------------------------------------------------
codesign_app() {
    echo "=== Code signing (ad-hoc) ==="

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
}

# -------------------------------------------------------
# verify_signature — 署名の検証
# -------------------------------------------------------
verify_signature() {
    echo "=== Verifying signature ==="
    codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}" 2>&1
    echo ""
    codesign -dvvv "${APP_BUNDLE}" 2>&1 | grep -E "^(Identifier|Info\.plist|Sealed|TeamIdentifier|Signature|Format)"
    echo ""
    codesign -d --entitlements :- "${APP_BUNDLE}" 2>/dev/null || true
    echo ""
}
