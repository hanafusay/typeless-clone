import SwiftUI

@main
struct KoeApp: App {
    private static var didScheduleHotkeySetup = false

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var speechManager = SpeechManager.shared
    @StateObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var config = Config.shared

    @State private var statusText = "待機中"
    @State private var isProcessing = false
    @State private var settingsWindow: NSWindow?

    /// Stored outside @State to avoid SwiftUI async update issues in hotkey callbacks.
    private static var selectedTextForCorrection: String?

    private let geminiService = GeminiService()
    private let overlay = OverlayPanel()

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            if speechManager.isRecording {
                Label("録音中", systemImage: "mic.fill")
            } else {
                Image(nsImage: Self.menuBarIcon)
            }
        }
    }

    /// Template image for the menu bar (loaded from bundle Resources)
    private static let menuBarIcon: NSImage = {
        let bundleResourcePath = Bundle.main.resourcePath ?? ""
        let candidates = [
            bundleResourcePath + "/MenuBarIcon@2x.png",
            bundleResourcePath + "/MenuBarIcon.png",
        ]
        for path in candidates {
            if let img = NSImage(contentsOfFile: path) {
                img.isTemplate = true
                img.size = NSSize(width: 18, height: 18)
                return img
            }
        }
        // Fallback to SF Symbol
        return NSImage(systemSymbolName: "mic", accessibilityDescription: "koe!")!
    }()

    @ViewBuilder
    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("koe!")
                .font(.headline)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)

        Divider()

        Text("🎤 \(config.triggerKey.displayName)キーを押しながら話す")
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
            Text("⚠️ アクセシビリティを許可してください")
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
        window.title = "koe! 設定"
        window.setContentSize(NSSize(width: 480, height: 600))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    private func setupHotkey() {
        Log.d("[KoeApp] setupHotkey")
        hotkeyManager.start(
            onRecordStart: { [self] in
                Log.d("[KoeApp] onRecordStart callback")
                handleStartRecording()
            },
            onRecordStop: { [self] in
                Log.d("[KoeApp] onRecordStop callback")
                handleStopRecording()
            }
        )
    }

    private func handleStartRecording() {
        Log.d("[KoeApp] handleStartRecording called (isProcessing=\(isProcessing), isRecording=\(speechManager.isRecording))")
        guard !isProcessing else { return }
        guard !speechManager.isRecording else {
            Log.d("[KoeApp] Ignored start because recording is already active")
            return
        }

        // Check for selected text BEFORE recording starts (before overlay could affect focus)
        let selected = PasteService.getSelectedText()
        Self.selectedTextForCorrection = selected
        Log.d("[KoeApp] Selected text for correction: \(selected != nil ? "\(selected!.count) chars" : "none")")

        do {
            speechManager.updateRecognizer(language: config.recognitionLanguage)
            try speechManager.startRecording()
            Log.d("[KoeApp] Recording started via hotkey/manual")

            let isCorrection = selected != nil
            statusText = isCorrection ? "修正モード: 録音中..." : "録音中..."
            overlay.updateStatus(isCorrection ? .recordingCorrection : .recording)
            overlay.showNearCursor()

            startPartialTextUpdates()
        } catch {
            Log.d("[KoeApp] handleStartRecording error: \(error.localizedDescription)")
            statusText = "エラー: \(error.localizedDescription)"
            overlay.updateStatus(.error, text: error.localizedDescription)
            Self.selectedTextForCorrection = nil
            dismissOverlayAfterDelay()
        }
    }

    private func startPartialTextUpdates() {
        let isCorrection = Self.selectedTextForCorrection != nil
        Task { @MainActor in
            while speechManager.isRecording {
                let partial = speechManager.partialText
                if !partial.isEmpty {
                    overlay.updateStatus(isCorrection ? .recordingCorrection : .recording, text: partial)
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func handleStopRecording() {
        Log.d("[KoeApp] handleStopRecording called (isRecording=\(speechManager.isRecording))")
        guard speechManager.isRecording else {
            Log.d("[KoeApp] No active recording. Dismissing overlay for safety.")
            statusText = "待機中"
            overlay.dismiss()
            return
        }
        speechManager.stopRecording()
        overlay.updateStatus(.recognizing)

        // Capture and clear the correction state
        let correctionText = Self.selectedTextForCorrection
        Self.selectedTextForCorrection = nil
        Log.d("[KoeApp] handleStopRecording correctionText=\(correctionText != nil ? "\(correctionText!.count) chars" : "nil")")

        Task { @MainActor in
            let recognizedText = await speechManager.waitForResult(timeout: 2.0)

            guard !recognizedText.isEmpty else {
                statusText = "テキストが認識されませんでした"
                overlay.updateStatus(.error, text: "音声が認識できませんでした。もう少し長く話してみてください。")
                dismissOverlayAfterDelay(seconds: 2.0)
                return
            }

            statusText = "認識完了"

            if let selectedText = correctionText {
                // --- Correction mode: voice = instruction, selected text = target ---
                Log.d("[KoeApp] Entering CORRECTION mode (selected=\(selectedText.count) chars, instruction=\(recognizedText))")
                guard !config.geminiAPIKey.isEmpty else {
                    statusText = "API キーが未設定"
                    overlay.updateStatus(.error, text: "修正機能にはGemini APIキーが必要です。設定から追加してください。")
                    dismissOverlayAfterDelay(seconds: 2.0)
                    return
                }

                isProcessing = true
                statusText = "修正中..."
                overlay.updateStatus(.correcting, text: recognizedText)

                do {
                    var systemPrompt = Config.defaultCorrectionPrompt
                    let userContext = config.rewriteUserContext.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !userContext.isEmpty {
                        systemPrompt += "\n\n【ユーザーコンテキスト】\n" + userContext
                    }
                    let corrected = try await geminiService.correct(
                        selectedText: selectedText,
                        instruction: recognizedText,
                        systemPrompt: systemPrompt,
                        apiKey: config.geminiAPIKey
                    )
                    PasteService.paste(text: corrected)
                    statusText = "完了"
                    overlay.updateStatus(.done, text: corrected)
                } catch {
                    statusText = "修正エラー"
                    overlay.updateStatus(.error, text: error.localizedDescription)
                    // Do NOT paste on error — preserve the original selected text
                }
                isProcessing = false
            } else if config.rewriteEnabled && !config.geminiAPIKey.isEmpty {
                // --- Normal rewrite mode ---
                Log.d("[KoeApp] Entering REWRITE mode")
                isProcessing = true
                statusText = "リライト中..."
                overlay.updateStatus(.rewriting, text: recognizedText)

                do {
                    var systemPrompt = config.rewritePrompt
                    let userContext = config.rewriteUserContext.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !userContext.isEmpty {
                        systemPrompt += "\n\n【ユーザーコンテキスト】\n" + userContext
                    }
                    let rewritten = try await geminiService.rewrite(
                        text: recognizedText,
                        systemPrompt: systemPrompt,
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
                // --- Plain dictation mode ---
                Log.d("[KoeApp] Entering PLAIN DICTATION mode")
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
        guard !Self.didScheduleHotkeySetup else { return }
        Self.didScheduleHotkeySetup = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            setupHotkey()
        }
    }
}
