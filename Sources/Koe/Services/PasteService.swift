import Cocoa

final class PasteService {
    static let shared = PasteService()

    private init() {}

    /// Retrieve the currently selected text from the focused application via Accessibility API.
    static func getSelectedText() -> String? {
        guard AXIsProcessTrusted() else {
            Log.d("[PasteService] Accessibility not trusted. Cannot get selected text.")
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success,
        let focusedElement,
        CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            Log.d("[PasteService] Could not get focused element")
            return nil
        }

        let focused = unsafeBitCast(focusedElement, to: AXUIElement.self)

        var selectedText: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        ) == .success,
        let selectedText,
        let text = selectedText as? String,
        !text.isEmpty else {
            Log.d("[PasteService] No selected text found")
            return nil
        }

        Log.d("[PasteService] Selected text found (\(text.count) chars)")
        return text
    }

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

@MainActor
extension PasteService: PasteServing {
    func getSelectedText() -> String? {
        Self.getSelectedText()
    }

    func paste(text: String) {
        Self.paste(text: text)
    }
}
