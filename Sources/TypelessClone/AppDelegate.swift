import Cocoa
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum PermissionItem {
        case accessibility

        var title: String {
            switch self {
            case .accessibility:
                return "アクセシビリティ"
            }
        }

        var description: String {
            switch self {
            case .accessibility:
                return "キー監視とCmd+V送信に必要"
            }
        }

        var settingsAnchor: String {
            switch self {
            case .accessibility:
                return "Privacy_Accessibility"
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.d("[AppDelegate] Launch started")
        checkAllPermissions()
    }

    private func checkAllPermissions() {
        // 1. Accessibility
        let axOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let accessibilityGranted = AXIsProcessTrustedWithOptions(axOptions)
        Log.d("[AppDelegate] Accessibility: \(accessibilityGranted)")
        if !accessibilityGranted {
            DispatchQueue.main.async {
                self.showPermissionAlert(for: .accessibility)
            }
        }

        // 2. Microphone
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        Log.d("[AppDelegate] Microphone: \(micStatus.rawValue)")
        if micStatus != .authorized {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Log.d("[AppDelegate] Microphone granted: \(granted)")
            }
        }

        // 3. Speech Recognition
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        Log.d("[AppDelegate] SpeechRecognition: \(speechStatus.rawValue)")
        if speechStatus != .authorized {
            SFSpeechRecognizer.requestAuthorization { status in
                Log.d("[AppDelegate] SpeechRecognition granted: \(status.rawValue)")
            }
        }
    }

    private func showPermissionAlert(for item: PermissionItem) {
        let alert = NSAlert()
        alert.messageText = "TypelessClone に権限が必要です"
        alert.informativeText = """
        以下の権限を許可してください：

        ・\(item.title)（\(item.description)）

        「\(item.title)を開く」を押して、TypelessClone を追加・許可してください。
        許可後、アプリを再起動してください。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "\(item.title)を開く")
        alert.addButton(withTitle: "後で")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            openPrivacyPane(anchor: item.settingsAnchor)
        }
    }

    private func openPrivacyPane(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
