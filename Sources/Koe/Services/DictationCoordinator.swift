import Foundation

protocol GeminiTextTransforming {
    func rewrite(text: String, systemPrompt: String, apiKey: String) async throws -> String
    func correct(selectedText: String, instruction: String, systemPrompt: String, apiKey: String) async throws -> String
}

@MainActor
final class DictationCoordinator: ObservableObject {
    @Published private(set) var statusText: String = "待機中"
    @Published private(set) var isProcessing: Bool = false

    private let speechManager: SpeechManager
    private let config: Config
    private let geminiService: GeminiTextTransforming
    private let overlay: OverlayPanel

    private var selectedTextForCorrection: String?
    private var partialTextTask: Task<Void, Never>?
    private var overlayDismissTask: Task<Void, Never>?

    init(
        speechManager: SpeechManager = .shared,
        config: Config = .shared,
        geminiService: GeminiTextTransforming = GeminiService(),
        overlay: OverlayPanel = OverlayPanel()
    ) {
        self.speechManager = speechManager
        self.config = config
        self.geminiService = geminiService
        self.overlay = overlay
    }

    func startRecording() {
        Log.d("[DictationCoordinator] startRecording called (isProcessing=\(isProcessing), isRecording=\(speechManager.isRecording))")
        guard !isProcessing else { return }
        guard !speechManager.isRecording else {
            Log.d("[DictationCoordinator] Ignored start because recording is already active")
            return
        }
        overlayDismissTask?.cancel()
        overlayDismissTask = nil
        stopPartialTextUpdates()

        let selected = PasteService.getSelectedText()
        selectedTextForCorrection = selected
        Log.d("[DictationCoordinator] Selected text for correction: \(selected != nil ? "\(selected!.count) chars" : "none")")

        do {
            speechManager.updateRecognizer(language: config.recognitionLanguage)
            try speechManager.startRecording()
            Log.d("[DictationCoordinator] Recording started")

            let isCorrection = selected != nil
            statusText = isCorrection ? "修正モード: 録音中..." : "録音中..."
            overlay.updateStatus(isCorrection ? .recordingCorrection : .recording)
            overlay.showNearCursor()

            startPartialTextUpdates(isCorrection: isCorrection)
        } catch {
            Log.d("[DictationCoordinator] startRecording error: \(error.localizedDescription)")
            statusText = "エラー: \(error.localizedDescription)"
            overlay.updateStatus(.error, text: error.localizedDescription)
            selectedTextForCorrection = nil
            dismissOverlayAfterDelay()
        }
    }

    func stopRecording() {
        Log.d("[DictationCoordinator] stopRecording called (isRecording=\(speechManager.isRecording))")
        guard speechManager.isRecording else {
            Log.d("[DictationCoordinator] No active recording. Dismissing overlay for safety.")
            statusText = "待機中"
            overlay.dismiss()
            return
        }

        speechManager.stopRecording()
        stopPartialTextUpdates()
        overlay.updateStatus(.recognizing)

        let correctionText = selectedTextForCorrection
        selectedTextForCorrection = nil
        Log.d("[DictationCoordinator] stopRecording correctionText=\(correctionText != nil ? "\(correctionText!.count) chars" : "nil")")

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.completeRecognition(correctionText: correctionText)
        }
    }

    private func completeRecognition(correctionText: String?) async {
        let recognizedText = await speechManager.waitForResult(timeout: 2.0)

        guard !recognizedText.isEmpty else {
            statusText = "テキストが認識されませんでした"
            overlay.updateStatus(.error, text: "音声が認識できませんでした。もう少し長く話してみてください。")
            dismissOverlayAfterDelay(seconds: 2.0)
            return
        }

        statusText = "認識完了"
        let dismissDelay: Double

        if let selectedText = correctionText {
            dismissDelay = await applyCorrectionMode(selectedText: selectedText, instruction: recognizedText)
        } else if config.rewriteEnabled && !config.geminiAPIKey.isEmpty {
            dismissDelay = await applyRewriteMode(recognizedText: recognizedText)
        } else {
            dismissDelay = applyPlainMode(recognizedText: recognizedText)
        }

        dismissOverlayAfterDelay(seconds: dismissDelay)
    }

    private func applyCorrectionMode(selectedText: String, instruction: String) async -> Double {
        Log.d("[DictationCoordinator] Entering CORRECTION mode (selected=\(selectedText.count) chars)")

        guard !config.geminiAPIKey.isEmpty else {
            statusText = "API キーが未設定"
            overlay.updateStatus(.error, text: "修正機能にはGemini APIキーが必要です。設定から追加してください。")
            return 2.0
        }

        isProcessing = true
        defer { isProcessing = false }

        statusText = "修正中..."
        overlay.updateStatus(.correcting, text: instruction)

        do {
            let corrected = try await geminiService.correct(
                selectedText: selectedText,
                instruction: instruction,
                systemPrompt: buildSystemPrompt(basePrompt: Config.defaultCorrectionPrompt),
                apiKey: config.geminiAPIKey
            )
            PasteService.paste(text: corrected)
            statusText = "完了"
            overlay.updateStatus(.done, text: corrected)
        } catch {
            statusText = "修正エラー"
            overlay.updateStatus(.error, text: error.localizedDescription)
        }

        return 1.5
    }

    private func applyRewriteMode(recognizedText: String) async -> Double {
        Log.d("[DictationCoordinator] Entering REWRITE mode")
        isProcessing = true
        defer { isProcessing = false }

        statusText = "リライト中..."
        overlay.updateStatus(.rewriting, text: recognizedText)

        do {
            let rewritten = try await geminiService.rewrite(
                text: recognizedText,
                systemPrompt: buildSystemPrompt(basePrompt: config.rewritePrompt),
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

        return 1.5
    }

    private func applyPlainMode(recognizedText: String) -> Double {
        Log.d("[DictationCoordinator] Entering PLAIN DICTATION mode")
        PasteService.paste(text: recognizedText)
        statusText = "完了"
        overlay.updateStatus(.done, text: recognizedText)
        return 1.5
    }

    private func buildSystemPrompt(basePrompt: String) -> String {
        let userContext = config.rewriteUserContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userContext.isEmpty else {
            return basePrompt
        }
        return basePrompt + "\n\n【ユーザーコンテキスト】\n" + userContext
    }

    private func startPartialTextUpdates(isCorrection: Bool) {
        stopPartialTextUpdates()
        partialTextTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.speechManager.isRecording && !Task.isCancelled {
                let partial = self.speechManager.partialText
                if !partial.isEmpty {
                    self.overlay.updateStatus(isCorrection ? .recordingCorrection : .recording, text: partial)
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func stopPartialTextUpdates() {
        partialTextTask?.cancel()
        partialTextTask = nil
    }

    private func dismissOverlayAfterDelay(seconds: Double = 1.5) {
        overlayDismissTask?.cancel()
        overlayDismissTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled {
                self.overlay.dismiss()
            }
        }
    }
}
