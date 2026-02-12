import Cocoa
import SwiftUI

/// カーソル付近に表示されるフローティングオーバーレイ
final class OverlayPanel: NSPanel {
    private let hostingView: NSHostingView<OverlayView>
    let overlayState: OverlayState

    init() {
        let state = OverlayState()
        self.overlayState = state
        self.hostingView = NSHostingView(rootView: OverlayView(state: state))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 56),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
        self.animationBehavior = .utilityWindow

        self.contentView = hostingView
    }

    /// Show the overlay near the text caret or mouse cursor
    func showNearCursor() {
        let position = getCaretPosition() ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(position, $0.frame, false) }) ?? NSScreen.main!
        let visibleFrame = screen.visibleFrame

        let panelWidth: CGFloat = 340
        let panelHeight: CGFloat = 56

        // Position below the caret/cursor
        var x = position.x
        var y = position.y - panelHeight - 8

        // Keep within screen bounds
        if x + panelWidth > visibleFrame.maxX {
            x = visibleFrame.maxX - panelWidth - 8
        }
        if x < visibleFrame.minX {
            x = visibleFrame.minX + 8
        }
        if y < visibleFrame.minY {
            y = position.y + 24
        }

        self.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        self.orderFrontRegardless()
    }

    func updateStatus(_ status: OverlayStatus, text: String = "") {
        overlayState.status = status
        overlayState.text = text

        let baseHeight: CGFloat = 40
        let textHeight: CGFloat = text.isEmpty ? 0 : min(60, CGFloat((text.count / 25) + 1) * 16 + 4)
        let totalHeight = baseHeight + textHeight + 16

        var frame = self.frame
        frame.size.height = totalHeight
        self.setFrame(frame, display: true)
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.alphaValue = 1
        })
    }

    /// Try to get the text caret position via Accessibility API
    private func getCaretPosition() -> NSPoint? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return nil
        }

        var selectedRange: AnyObject?
        guard AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success else {
            return nil
        }

        var bounds: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(focusedElement as! AXUIElement, kAXBoundsForRangeParameterizedAttribute as CFString, selectedRange!, &bounds) == .success else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else {
            return nil
        }

        // AX coordinates are top-left origin, convert to NSScreen bottom-left origin
        let screenHeight = NSScreen.main?.frame.height ?? 0
        return NSPoint(x: rect.origin.x, y: screenHeight - rect.origin.y - rect.height)
    }
}

enum OverlayStatus {
    case recording
    case recognizing
    case rewriting
    case done
    case error
}

@MainActor
final class OverlayState: ObservableObject {
    @Published var status: OverlayStatus = .recording
    @Published var text: String = ""
}

struct OverlayView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .font(.system(size: 18))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                if !state.text.isEmpty {
                    Text(state.text)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(statusColor.opacity(0.5), lineWidth: 1.5)
        )
        .padding(4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state.status {
        case .recording:
            Image(systemName: "mic.fill")
                .foregroundColor(.red)
        case .recognizing:
            ProgressView()
                .scaleEffect(0.7)
        case .rewriting:
            Image(systemName: "sparkles")
                .foregroundColor(.purple)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        }
    }

    private var statusLabel: String {
        switch state.status {
        case .recording: return "録音中... fn を離すと確定"
        case .recognizing: return "認識中..."
        case .rewriting: return "リライト中..."
        case .done: return "完了"
        case .error: return "エラー"
        }
    }

    private var statusColor: Color {
        switch state.status {
        case .recording: return .red
        case .recognizing: return .blue
        case .rewriting: return .purple
        case .done: return .green
        case .error: return .orange
        }
    }
}
