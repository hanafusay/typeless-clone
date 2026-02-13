# Project Rules

## ブランチ運用

- mainブランチへの直接コミットは禁止。必ずフィーチャーブランチを作成してから作業すること
- フィーチャーブランチをマージしたら、リモートのブランチを削除すること

## コミットメッセージ

- コミットメッセージは日本語で書くこと
- Conventional Commits 形式を使用する。プレフィックス後のメッセージはユーザー向けのわかりやすい表現にすること
  - `feat:` — 新機能（例: `feat: 設定画面にマイク選択機能を追加`）
  - `fix:` — バグ修正（例: `fix: AirPods切り替え時にアプリが落ちる問題を修正`）
  - `docs:` — ドキュメントのみの変更
  - `chore:` — ビルド・CI・設定などコードに影響しない変更
  - `refactor:` — 機能変更を伴わないリファクタリング
- `feat:` と `fix:` はリリースノートに自動掲載されるため、エンドユーザーに伝わる内容で書く

## リリース

- PRに `feat:` または `fix:` コミットが含まれる場合、マージ後にリリースタグを打つこと
- タグは semver 形式（`v1.x.x`）。`feat:` はマイナーバージョン、`fix:` はパッチバージョンを上げる
- タグを push すると GitHub Actions（`.github/workflows/release.yml`）が DMG ビルド → GitHub Release 作成まで自動実行される

```bash
# 例: 現在 v1.4.0 で fix: を含むPRをマージした場合
git checkout main && git pull
git tag v1.4.1
git push origin v1.4.1
```

## ローカル動作確認手順

Koe はメニューバー常駐アプリ（`.app` バンドル必須）のため、デバッグバイナリの直接実行は不可。
`/Applications/Koe.app` のバイナリを差し替えて確認する。

```bash
# 1. ビルド
swift build

# 2. 既存アプリを終了
killall Koe

# 3. バイナリを差し替え（.app 内に .bak 等の余計なファイルを置かないこと）
cp .build/debug/Koe /Applications/Koe.app/Contents/MacOS/Koe

# 4. コード署名し直す（署名が壊れるとアクセシビリティ権限が無効になる）
codesign --force --sign - /Applications/Koe.app

# 5. アプリを起動
open /Applications/Koe.app
```

- 署名が変わった場合、**システム設定 → プライバシーとセキュリティ → アクセシビリティ** で Koe を再許可する必要がある
- アクセシビリティ権限がないと Cmd+V によるペースト操作が動作しない

## Swift開発ガイドライン参照ドキュメント

### デザイン（UI/UX）

- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) — Appleプラットフォーム全体のUIデザイン原則・パターン・コンポーネント

### コード設計・命名規則

- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) — 命名規則、APIの設計原則
- [Swift Documentation](https://www.swift.org/documentation/) — Swift言語公式ドキュメント（Standard Library、Package Manager、DocC等）

### フレームワークリファレンス

- [SwiftUI](https://developer.apple.com/documentation/SwiftUI) — SwiftUI公式リファレンス
- [Swift (Apple Developer)](https://developer.apple.com/documentation/swift) — Apple Developer上のSwiftリファレンス
