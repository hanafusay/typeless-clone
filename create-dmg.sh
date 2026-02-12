#!/bin/bash
# ============================================================
# create-dmg.sh — Koe の配布用 DMG を作成する
#
# 使い方:
#   ./create-dmg.sh            # ビルド + DMG 作成
#   ./create-dmg.sh --skip-build   # ビルド済み .app から DMG だけ作成
#
# 前提:
#   - macOS 14+, Swift 5.9+, Xcode Command Line Tools
#   - hdiutil（macOS 標準搭載）
#
# 出力:
#   ./dist/Koe-<version>.dmg
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/scripts/lib.sh"

DIST_DIR="dist"
SKIP_BUILD=0

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=1 ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# Read version from Info.plist
VERSION=$(defaults read "$(pwd)/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null || true)
if [ -z "${VERSION}" ]; then
    echo "Warning: Could not read version from Info.plist, falling back to 0.0.0" >&2
    VERSION="0.0.0"
fi
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

echo "=== Koe DMG Builder ==="
echo "  Version: ${VERSION}"
echo ""

# -------------------------------------------------------
# 1. Build (unless --skip-build)
# -------------------------------------------------------
if [ "${SKIP_BUILD}" = "0" ]; then
    build_release
    echo ""
fi

# -------------------------------------------------------
# 2. Create .app bundle
# -------------------------------------------------------
create_app_bundle

# -------------------------------------------------------
# 3. Code-sign (ad-hoc)
# -------------------------------------------------------
echo ""
codesign_app

# Verify
echo ""
verify_signature

# -------------------------------------------------------
# 4. Create DMG
# -------------------------------------------------------
echo "=== Creating DMG ==="

mkdir -p "${DIST_DIR}"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"

# Remove old DMG if exists
rm -f "${DMG_PATH}"

# Create temporary staging directory for DMG contents
DMG_STAGE=$(mktemp -d)
trap 'rm -rf "${DMG_STAGE}"' EXIT

# Copy .app bundle into staging directory
cp -R "${APP_BUNDLE}" "${DMG_STAGE}/"

# Create symlink to /Applications for drag-and-drop install
ln -s /Applications "${DMG_STAGE}/Applications"

# Create a README inside the DMG
cat > "${DMG_STAGE}/はじめにお読みください.txt" << 'READMETXT'
koe! — インストール手順

1. インストール
   Koe.app を Applications フォルダにドラッグ＆ドロップしてください。

2. 初回起動
   - /Applications/Koe.app をダブルクリック
   - Gatekeeper にブロックされたら「完了」を押す
   - システム設定 > プライバシーとセキュリティ を開く
   - 画面下部の「このまま開く」をクリック
   - 確認ダイアログで「開く」をクリック（以降はダブルクリックで起動可能）

3. 権限を許可
   初回起動時に以下の権限を許可してください：
   - マイク
   - 音声認識
   - アクセシビリティ（システム設定 > プライバシーとセキュリティ > アクセシビリティ）
   - 入力監視（システム設定 > プライバシーとセキュリティ > 入力監視）

4. APIキーの設定
   メニューバーのアイコン →「設定」から Gemini API キーを入力してください。
   （https://aistudio.google.com/apikey で取得できます）

5. 使い方
   - fn キーを押しながら話す
   - fn キーを離すとテキストに変換してペースト

注意:
  - macOS 14 (Sonoma) 以上が必要です
  - fn キーが絵文字ピッカーを起動する場合は、
    システム設定 → キーボード →「🌐キーを押して」を「何もしない」に変更してください
READMETXT

echo "  Staging directory prepared"

# Create DMG using hdiutil
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGE}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

echo ""
echo "  Created: ${DMG_PATH}"

# Show file size
DMG_SIZE=$(du -h "${DMG_PATH}" | cut -f1)
echo "  Size: ${DMG_SIZE}"

# Clean up app bundle
rm -rf "${APP_BUNDLE}"

# -------------------------------------------------------
# 5. Done
# -------------------------------------------------------
echo ""
echo "=== Done ==="
echo ""
echo "配布用 DMG が作成されました: ${DMG_PATH}"
echo ""
echo "配布の注意点:"
echo "  - このDMGはアドホック署名（Developer ID なし）です"
echo "  - 受け取った人は初回起動時に右クリック →「開く」が必要です"
echo "  - Developer ID で署名 + notarize すれば、ダブルクリックで起動できます"
echo ""
echo "Developer ID 署名で作成するには:"
echo "  1. Apple Developer Program に登録（年額 \$99）"
echo "  2. create-dmg.sh 内の --sign を Developer ID に変更"
echo "  3. notarytool で notarize を実行"
