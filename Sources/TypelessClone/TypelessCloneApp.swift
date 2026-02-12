import SwiftUI

@main
struct TypelessCloneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var speechManager = SpeechManager()
    @StateObject private var hotkeyManager = HotkeyManager()
    @ObservedObject private var config = Config.shared

    @State private var statusText = "待機中"
    @State private var isProcessing = false
    @State private var settingsWindow: NSWindow?

    private let geminiService = GeminiService()
    private let overlay = OverlayPanel()

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            Label(
                speechManager.isRecording ? "録音中" : "TypelessClone",
                systemImage: speechManager.isRecording ? "mic.fill" : "mic"
            )
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TypelessClone")
                .font(.headline)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)

        Divider()

        Text("🎤 右⌘キーを押しながら話す")
            .font(.caption)

        Button(speechManager.isRecording ? "⏹ 録音停止" : "🎙 手動で録音開始") {
            if speechManager.isRecording {
                handleStopRecording()
            } else {
                handleStartRecording()
            }
        }
        .disabled(isProcessing)

        if !hotkeyManager.isAccessibilityGranted {
            Text("⚠️ アクセシビリティ/入力監視を許可してください")
                .font(.caption)
                .foregroundColor(.red)
        }

        Divider()

        Button("設定...") {
            openSettings()
        }

        Button("終了") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "TypelessClone 設定"
        window.setContentSize(NSSize(width: 480, height: 560))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    private func setupHotkey() {
        hotkeyManager.onRecordStart = { [self] in
            handleStartRecording()
        }
        hotkeyManager.onRecordStop = { [self] in
            handleStopRecording()
        }
        hotkeyManager.start()
    }

    private func handleStartRecording() {
        guard !isProcessing else { return }
        do {
            speechManager.updateRecognizer(language: config.recognitionLanguage)
            try speechManager.startRecording()
            statusText = "録音中..."

            overlay.updateStatus(.recording)
            overlay.showNearCursor()

            startPartialTextUpdates()
        } catch {
            statusText = "エラー: \(error.localizedDescription)"
            overlay.updateStatus(.error, text: error.localizedDescription)
            dismissOverlayAfterDelay()
        }
    }

    private func startPartialTextUpdates() {
        Task { @MainActor in
            while speechManager.isRecording {
                let partial = speechManager.partialText
                if !partial.isEmpty {
                    overlay.updateStatus(.recording, text: partial)
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func handleStopRecording() {
        guard speechManager.isRecording else { return }
        speechManager.stopRecording()
        overlay.updateStatus(.recognizing)

        Task { @MainActor in
            let recognizedText = await speechManager.waitForResult(timeout: 2.0)

            guard !recognizedText.isEmpty else {
                statusText = "テキストが認識されませんでした"
                overlay.updateStatus(.error, text: "音声が認識できませんでした。もう少し長く話してみてください。")
                dismissOverlayAfterDelay(seconds: 2.0)
                return
            }

            statusText = "認識完了"

            if config.rewriteEnabled && !config.geminiAPIKey.isEmpty {
                isProcessing = true
                statusText = "リライト中..."
                overlay.updateStatus(.rewriting, text: recognizedText)

                do {
                    let rewritten = try await geminiService.rewrite(
                        text: recognizedText,
                        systemPrompt: config.rewritePrompt,
                        apiKey: config.geminiAPIKey
                    )
                    PasteService.paste(text: rewritten)
                    statusText = "完了"
                    overlay.updateStatus(.done, text: rewritten)
                } catch {
                    statusText = "リライトエラー"
                    overlay.updateStatus(.error, text: error.localizedDescription)
                    PasteService.paste(text: recognizedText)
                }
                isProcessing = false
            } else {
                PasteService.paste(text: recognizedText)
                statusText = "完了"
                overlay.updateStatus(.done, text: recognizedText)
            }

            dismissOverlayAfterDelay()
        }
    }

    private func dismissOverlayAfterDelay(seconds: Double = 1.5) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            overlay.dismiss()
        }
    }

    init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            setupHotkey()
        }
    }
}
