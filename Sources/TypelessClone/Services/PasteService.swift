import Cocoa

final class PasteService {
    static func paste(text: String) {
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V after a brief delay to ensure clipboard is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulateCmdV()
        }
    }

    private static func simulateCmdV() {
        guard AXIsProcessTrusted() else {
            Log.d("[PasteService] Accessibility not trusted. Skip Cmd+V simulation.")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9
        let commandKey: CGKeyCode = 55

        // Emit as a full chord to improve compatibility across apps.
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cgAnnotatedSessionEventTap)

        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cgAnnotatedSessionEventTap)

        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cgAnnotatedSessionEventTap)

        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: false)
        cmdUp?.post(tap: .cgAnnotatedSessionEventTap)
        Log.d("[PasteService] Cmd+V posted")
    }
}
