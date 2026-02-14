import AVFoundation
import SwiftUI

struct AudioInputDevice: Identifiable {
    let id: String  // uniqueID（空文字 = システムデフォルト）
    let name: String
}

struct SettingsView: View {
    @ObservedObject var config = Config.shared

    @State private var showAPIKey = false
    @State private var audioInputDevices: [AudioInputDevice] = []

    var body: some View {
        Form {
            Section("一般") {
                Toggle("ログイン時に起動", isOn: $config.launchAtLogin)
            }

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

                Picker("マイク", selection: $config.audioInputDeviceUID) {
                    Text("システムデフォルト").tag("")
                    ForEach(audioInputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .onAppear { refreshAudioDevices() }
            }

            Section("校正") {
                Toggle("Gemini 校正を有効にする", isOn: $config.rewriteEnabled)

                if config.rewriteEnabled {
                    VStack(alignment: .leading) {
                        Text("校正プロンプト:")
                            .font(.caption)
                        TextEditor(text: $config.rewritePrompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 100)
                            .border(Color.gray.opacity(0.3))
                    }

                    Button("校正プロンプトをリセット") {
                        config.rewritePrompt = Config.defaultRewritePrompt
                    }

                    VStack(alignment: .leading) {
                        Text("マイ指示書:")
                            .font(.caption)
                        Text("校正時に考慮してほしい個人的な指示（専門用語、文体の好みなど）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $config.userContext)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 60)
                            .border(Color.gray.opacity(0.3))
                            .onChange(of: config.userContext) { _, newValue in
                                if newValue.count > Config.maxUserContextLength {
                                    config.userContext = String(newValue.prefix(Config.maxUserContextLength))
                                }
                            }
                        Text("\(config.userContext.count) / \(Config.maxUserContextLength)")
                            .font(.caption)
                            .foregroundColor(
                                config.userContext.count > Config.maxUserContextLength - 20
                                    ? .orange : .secondary
                            )
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }

            Section("操作方法") {
                Picker("録音キー", selection: $config.triggerKey) {
                    ForEach(TriggerKey.allCases) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .onChange(of: config.triggerKey) { _, _ in
                    HotkeyManager.shared.resetState()
                }

                HStack {
                    Spacer()
                    Text("押しながら話す → 離すとペースト")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                HStack {
                    Text("テキスト修正:")
                    Spacer()
                    Text("テキストを選択 → \(config.triggerKey.displayName) 押しながら指示 → 修正")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                if config.triggerKey == .fn {
                    Text("⚠️ fn キーが絵文字ピッカーや音声入力を起動する場合は、\nシステム設定 → キーボード → 「🌐キーを押して」を「何もしない」に変更してください")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
        .frame(width: 480, height: 600)
        .padding()
    }

    private func refreshAudioDevices() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        audioInputDevices = session.devices.map {
            AudioInputDevice(id: $0.uniqueID, name: $0.localizedName)
        }
    }
}
