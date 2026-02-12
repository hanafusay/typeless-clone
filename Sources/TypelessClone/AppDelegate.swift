import Cocoa
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.d("[AppDelegate] Launch started")
        checkAllPermissions()
    }

    private func checkAllPermissions() {
        var missing: [String] = []

        // 1. Accessibility (for event tap + simulated paste)
        let axOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let accessibilityGranted = AXIsProcessTrustedWithOptions(axOptions)
        Log.d("[AppDelegate] Accessibility: \(accessibilityGranted)")
        if !accessibilityGranted {
            missing.append("アクセシビリティ（キー監視とCmd+V送信に必要）")
            missing.append("入力監視（グローバルキー監視に必要）")
        }

        // 2. Microphone
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        Log.d("[AppDelegate] Microphone: \(micStatus.rawValue)")
        if micStatus != .authorized {
            missing.append("マイク（録音に必要）")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Log.d("[AppDelegate] Microphone granted: \(granted)")
            }
        }

        // 3. Speech Recognition
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        Log.d("[AppDelegate] SpeechRecognition: \(speechStatus.rawValue)")
        if speechStatus != .authorized {
            missing.append("音声認識（文字起こしに必要）")
            SFSpeechRecognizer.requestAuthorization { status in
                Log.d("[AppDelegate] SpeechRecognition granted: \(status.rawValue)")
            }
        }

        // Input Monitoring cannot be prompted from app, so we explain it with Accessibility.
        if !accessibilityGranted {
            DispatchQueue.main.async {
                self.showPermissionAlert(missing: missing)
            }
        }
    }

    private func showPermissionAlert(missing: [String]) {
        let alert = NSAlert()
        alert.messageText = "TypelessClone に権限が必要です"
        alert.informativeText = """
        以下の権限を許可してください：

        \(missing.map { "・\($0)" }.joined(separator: "\n"))

        「システム設定を開く」を押して、TypelessClone を追加・許可してください。
        許可後、アプリを再起動してください。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "アクセシビリティを開く")
        alert.addButton(withTitle: "入力監視を開く")
        alert.addButton(withTitle: "後で")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            openPrivacyPane(anchor: "Privacy_Accessibility")
        } else if response == .alertSecondButtonReturn {
            openPrivacyPane(anchor: "Privacy_ListenEvent")
        }
    }

    private func openPrivacyPane(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
