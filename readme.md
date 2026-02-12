# TypelessClone

macOS メニューバー常駐の音声入力アプリです。
`fn` を押している間だけ録音し、離したら文字起こししてアクティブアプリに貼り付けます。

![デモ](screenshots/demo.gif)

## ダウンロード

[GitHub Releases](../../releases/latest) から最新の DMG をダウンロードできます。

1. `TypelessClone-*.dmg` をダウンロード
2. DMG を開いて `TypelessClone.app` を `Applications` にドラッグ
3. **初回起動:** Finder で右クリック →「開く」（署名なしアプリのため）
4. 権限を許可（マイク・音声認識・アクセシビリティ・入力監視）
5. メニューバーのアイコン →「設定」から Gemini API キーを入力

> 開発環境不要。macOS 14 以上で動作します。

## Quick Start（ソースからビルド）

```bash
cp .env.example .env
# .env に GEMINI_API_KEY=... を設定
./build.sh
open /Applications/TypelessClone.app
```

初回起動時に以下を許可してください。
- マイク
- 音声認識
- アクセシビリティ
- 入力監視

使い方:
- `fn` を押しながら話す
- `fn` を離すと確定して貼り付け

## 前提環境

- macOS 14 以上
- Xcode Command Line Tools
- Swift 5.9+（`swift build` が動くこと）

## 初回セットアップ

1. `.env` を作成して Gemini API キーを設定

```bash
cp .env.example .env
```

`.env`:

```env
GEMINI_API_KEY=your_api_key_here
```

2. ビルドとインストール

```bash
./build.sh
```

`/Applications/TypelessClone.app` にインストールされます。

## 詳細な使い方

1. アプリ起動

```bash
open /Applications/TypelessClone.app
```

2. 必要な権限を許可
- マイク
- 音声認識
- アクセシビリティ
- 入力監視

3. 文字入力
- `fn` を押しながら話す
- `fn` を離すと確定して貼り付け
- メニューから手動録音も可能

## スクリーンショット

### メニューバーUI

待機中のメニュー表示です。`fn` 押下で録音開始、メニューから手動録音もできます。

![メニューバーUI](screenshots/menubar.png)

### 設定画面（Gemini校正）

API キー、認識言語、校正プロンプトを設定できます。

![設定画面（Gemini校正）](screenshots/settings-gemini.png)

### 設定画面（権限と操作）

録音キーの案内、権限ガイド、システム設定への導線です。

![設定画面（権限と操作）](screenshots/settings-permissions.png)

## DMG で配布する

開発環境がない人向けに、ビルド済みの DMG を作成して配布できます。

### DMG の作成（ビルドできる Mac で実行）

```bash
./create-dmg.sh
```

`dist/TypelessClone-1.0.dmg` が作成されます。
この DMG をメール・チャット・ファイル共有などで配布してください。

### DMG からのインストール（受け取った人が実行）

1. DMG をダブルクリックしてマウント
2. `TypelessClone.app` を `Applications` フォルダにドラッグ＆ドロップ
3. **初回起動:** Finder で `/Applications/TypelessClone.app` を **右クリック →「開く」**
   - 署名なしアプリのため、ダブルクリックでは開けません。右クリックが必要です
   - 2回目以降はダブルクリックで起動できます
4. 権限を許可（マイク・音声認識・アクセシビリティ・入力監視）
5. メニューバーのアイコン →「設定」から **Gemini API キーを入力**

> **注意:** このDMGはアドホック署名です。Gatekeeper の警告が出るため、
> 受け取った人は初回に右クリック →「開く」が必要です。
> Apple Developer Program（年額 $99）に登録して Developer ID 署名 + notarize すれば、
> ダブルクリックだけで起動できるようになります。

## 他の Mac で起動する（ソースから）

リポジトリを clone してビルドする方法です。

1. アプリをビルド＆インストール

```bash
git clone <repository-url>
cd typeless-clone
cp .env.example .env
# .env に GEMINI_API_KEY=... を設定
./build.sh
```

2. 初回起動

```bash
open /Applications/TypelessClone.app
```

警告が出る場合は Finder でアプリを右クリックして「開く」を 1 回実行してください。

3. 権限付与（Mac ごとに必要）
- `プライバシーとセキュリティ > アクセシビリティ`
- `プライバシーとセキュリティ > 入力監視`
- 両方で `TypelessClone.app` を ON

4. 権限付与後に再起動

```bash
pkill -x TypelessClone; open /Applications/TypelessClone.app
```

## トラブルシュート

- `アクセシビリティを許可してください` が消えない
  - 許可対象が `/Applications/TypelessClone.app` か確認
  - アプリ再起動を実施

- `fn` で起動しない
  - `入力監視` が ON か確認
  - システム設定 > キーボード > `🌐キーを押して` を `何もしない` に変更

- 設定をやり直したい

```bash
tccutil reset Accessibility com.typelessclone.app
tccutil reset ListenEvent com.typelessclone.app
tccutil reset PostEvent com.typelessclone.app
```

## リリースの作り方（メンテナー向け）

### GitHub Actions の自動リリース

タグを push すると GitHub Actions が自動で DMG を作成し、GitHub Releases に公開します。

#### 初回セットアップ

`.github/workflows/release.yml` を作成してください:

```yaml
name: Release DMG

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  build-and-release:
    runs-on: macos-14
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build release binary
        run: swift build -c release

      - name: Create app bundle and DMG
        run: ./create-dmg.sh --skip-build

      - name: Get version from tag
        id: version
        run: echo "tag=${GITHUB_REF_NAME}" >> "$GITHUB_OUTPUT"

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          name: TypelessClone ${{ steps.version.outputs.tag }}
          body: |
            ## インストール方法

            1. `TypelessClone-*.dmg` をダウンロード
            2. DMG を開いて `TypelessClone.app` を `Applications` にドラッグ
            3. **初回起動:** Finder で右クリック →「開く」
            4. 権限を許可（マイク・音声認識・アクセシビリティ・入力監視）
            5. メニューバーのアイコン →「設定」から Gemini API キーを入力

            > macOS 14 (Sonoma) 以上が必要です。
            > 署名なしアプリのため初回は右クリック →「開く」が必要です。
          files: dist/*.dmg
          draft: false
          prerelease: false
```

#### リリースの実行

```bash
# Info.plist のバージョンを更新してからコミット
git tag v1.0.0
git push origin v1.0.0
```

### 手動で DMG を作る場合

```bash
./create-dmg.sh
# dist/TypelessClone-1.0.dmg が生成される
```
