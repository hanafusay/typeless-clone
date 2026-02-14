import SwiftUI

@main
struct KoeApp: App {
    private static var didScheduleHotkeySetup = false

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var speechManager = SpeechManager.shared
    @StateObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var config = Config.shared
    @StateObject private var coordinator = DictationCoordinator()
    @State private var settingsWindow: NSWindow?

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
        return NSImage(systemSymbolName: "mic", accessibilityDescription: "koe!")!
    }()

    @ViewBuilder
    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("koe!")
                .font(.headline)
            Text(coordinator.statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)

        Divider()

        Text("🎤 \(config.triggerKey.displayName)キーを押しながら話す")
            .font(.caption)

        Button(speechManager.isRecording ? "⏹ 録音停止" : "🎙 手動で録音開始") {
            if speechManager.isRecording {
                coordinator.stopRecording()
            } else {
                coordinator.startRecording()
            }
        }
        .disabled(coordinator.isProcessing)

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
                coordinator.startRecording()
            },
            onRecordStop: { [self] in
                Log.d("[KoeApp] onRecordStop callback")
                coordinator.stopRecording()
            }
        )
    }

    init() {
        guard !Self.didScheduleHotkeySetup else { return }
        Self.didScheduleHotkeySetup = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            setupHotkey()
        }
    }
}
