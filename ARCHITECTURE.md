# アーキテクチャ概要

## 目的

`koe!` は「録音開始・停止」「音声認識」「テキスト補正（Gemini）」「貼り付け」の一連処理を、メニューバー UI から低遅延で実行する macOS 常駐アプリです。

## レイヤ構成

### 1. UI レイヤ

- `KoeApp.swift`
- `Views/SettingsView.swift`
- `Views/OverlayPanel.swift`

役割:

- メニュー表示、設定画面表示、オーバーレイ表示
- ユーザー入力（ボタン、ホットキー）を受け取る
- 業務ロジックは持たず、Coordinator を呼び出す

### 2. アプリケーションレイヤ

- `Services/DictationCoordinator.swift`

役割:

- 録音開始〜停止〜結果確定のユースケースを統括
- モード判定（通常入力 / リライト / 選択テキスト修正）
- UI 状態（`statusText`, `isProcessing`）の管理
- サービス間連携（Speech / Gemini / Paste / Overlay）

### 3. インフラレイヤ

- `Services/SpeechManager.swift`
- `Services/GeminiService.swift`
- `Services/PasteService.swift`
- `Services/HotkeyManager.swift`
- `Config.swift`

役割:

- 音声入力、外部 API 通信、クリップボード制御、グローバルキー監視、永続設定
- プラットフォーム API や外部 API との境界を担当

## 設計方針

1. **UI から業務ロジックを分離する**
   - `KoeApp` は表示とイベント配線に限定し、ユースケース処理は `DictationCoordinator` に集約する。
2. **依存方向を固定する**
   - UI → Coordinator → サービスの一方向依存を基本とする。
3. **外部境界の重複を作らない**
   - Gemini リクエスト処理は `GeminiService` 内で共通化し、エラーハンドリングを一元化する。
4. **非同期処理のライフサイクルを明示する**
   - 部分認識更新タスク・オーバーレイ遅延タスクは Coordinator が明示的に開始/停止する。

## 今後の改善候補

- `Config.shared` への直接依存を減らし、設定インターフェース経由に寄せる
- `PasteService` の静的 API をインスタンス化し、テストしやすい境界にする
- `DictationCoordinator` のモード判定ロジックを純粋関数として分離し、ユニットテストを追加する
