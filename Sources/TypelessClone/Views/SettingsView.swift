import SwiftUI

struct SettingsView: View {
    @ObservedObject var config = Config.shared

    @State private var showAPIKey = false

    var body: some View {
        Form {
            Section("Gemini API") {
                HStack {
                    if showAPIKey {
                        TextField("API キー", text: $config.geminiAPIKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API キー", text: $config.geminiAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(showAPIKey ? "隠す" : "表示") {
                        showAPIKey.toggle()
                    }
                    .frame(width: 50)
                }
            }

            Section("音声認識") {
                Picker("認識言語", selection: $config.recognitionLanguage) {
                    Text("日本語").tag("ja-JP")
                    Text("英語 (US)").tag("en-US")
                    Text("英語 (UK)").tag("en-GB")
                    Text("中国語 (簡体)").tag("zh-CN")
                    Text("韓国語").tag("ko-KR")
                }
            }

            Section("リライト") {
                Toggle("Gemini リライトを有効にする", isOn: $config.rewriteEnabled)

                if config.rewriteEnabled {
                    VStack(alignment: .leading) {
                        Text("リライトプロンプト:")
                            .font(.caption)
                        TextEditor(text: $config.rewritePrompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 100)
                            .border(Color.gray.opacity(0.3))
                    }

                    Button("プロンプトをリセット") {
                        config.rewritePrompt = Config.defaultRewritePrompt
                    }
                }
            }

            Section("操作方法") {
                HStack {
                    Text("録音キー:")
                    Text("fn")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(4)
                    Spacer()
                    Text("押しながら話す → 離すとペースト")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                Text("⚠️ fn キーが絵文字ピッカーや音声入力を起動する場合は、\nシステム設定 → キーボード → 「🌐キーを押して」を「何もしない」に変更してください")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("権限") {
                Text("このアプリは以下の権限が必要です:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Label("マイク", systemImage: "mic")
                    Label("音声認識", systemImage: "waveform")
                    Label("アクセシビリティ（キー入力）", systemImage: "keyboard")
                }
                .font(.caption)

                Button("システム設定を開く") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
        .padding()
    }
}
