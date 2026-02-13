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
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 100),
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
        let position = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(position, $0.frame, false) }) ?? NSScreen.main!
        let visibleFrame = screen.visibleFrame

        let panelWidth: CGFloat = 340
        let panelHeight: CGFloat = 100

        // Position above the caret/cursor
        var x = position.x
        var y = position.y + 8

        // Keep within screen bounds
        if x + panelWidth > visibleFrame.maxX {
            x = visibleFrame.maxX - panelWidth - 8
        }
        if x < visibleFrame.minX {
            x = visibleFrame.minX + 8
        }
        if y + panelHeight > visibleFrame.maxY {
            y = position.y - panelHeight - 8
        }

        self.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        self.orderFrontRegardless()
    }

    func updateStatus(_ status: OverlayStatus, text: String = "") {
        overlayState.status = status
        overlayState.text = text
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
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focusedElement,
              CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            return nil
        }
        let focused = unsafeBitCast(focusedElement, to: AXUIElement.self)

        var selectedRange: CFTypeRef?
        var bounds: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success,
           let selectedRange,
           AXUIElementCopyParameterizedAttributeValue(focused, kAXBoundsForRangeParameterizedAttribute as CFString, selectedRange, &bounds) == .success,
           let bounds,
           CFGetTypeID(bounds) == AXValueGetTypeID() {
            let boundsValue = unsafeBitCast(bounds, to: AXValue.self)
            var rect = CGRect.zero
            if AXValueGetValue(boundsValue, .cgRect, &rect) {
                return convertAXToAppKit(point: NSPoint(x: rect.origin.x, y: rect.origin.y + rect.height))
            }
        }

        // Fallback: some apps do not expose selected range bounds.
        var position: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, kAXPositionAttribute as CFString, &position) == .success,
           let position,
           CFGetTypeID(position) == AXValueGetTypeID() {
            let posValue = unsafeBitCast(position, to: AXValue.self)
            var point = CGPoint.zero
            if AXValueGetValue(posValue, .cgPoint, &point) {
                return convertAXToAppKit(point: NSPoint(x: point.x, y: point.y))
            }
        }

        return nil
    }

    private func convertAXToAppKit(point: NSPoint) -> NSPoint {
        let allScreens = NSScreen.screens
        let screen = allScreens.first(where: { point.x >= $0.frame.minX && point.x <= $0.frame.maxX }) ?? NSScreen.main
        guard let screen else { return point }

        // AX is top-left origin in global screen coordinates.
        let yFromBottom = screen.frame.maxY - point.y
        return NSPoint(x: point.x, y: yFromBottom)
    }
}

enum OverlayStatus {
    case recording
    case recordingCorrection
    case recognizing
    case rewriting
    case correcting
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
                        .truncationMode(.head)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state.status {
        case .recording:
            Image(systemName: "mic.fill")
                .foregroundColor(.red)
        case .recordingCorrection:
            Image(systemName: "mic.fill")
                .foregroundColor(.purple)
        case .recognizing:
            ProgressView()
                .scaleEffect(0.7)
        case .rewriting:
            Image(systemName: "sparkles")
                .foregroundColor(.secondary)
        case .correcting:
            Image(systemName: "pencil.and.outline")
                .foregroundColor(.secondary)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.secondary)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        }
    }

    private var statusLabel: String {
        let keyName = Config.shared.triggerKey.displayName
        switch state.status {
        case .recording: return "録音中... \(keyName) を離すと確定"
        case .recordingCorrection: return "修正モード: \(keyName) を離すと確定"
        case .recognizing: return "認識中..."
        case .rewriting: return "リライト中..."
        case .correcting: return "修正中..."
        case .done: return "完了"
        case .error: return "エラー"
        }
    }

    private var statusColor: Color {
        switch state.status {
        case .recording: return .red
        case .recordingCorrection: return .purple
        case .recognizing: return .blue
        case .rewriting: return .purple
        case .correcting: return .purple
        case .done: return .green
        case .error: return .orange
        }
    }
}
