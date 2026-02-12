import Cocoa
import Carbon.HIToolbox

@MainActor
final class HotkeyManager: ObservableObject {
    @Published var isKeyHeld = false
    @Published var isAccessibilityGranted = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?

    func start() {
        isAccessibilityGranted = requestAccessibility()
        Log.d("[HotkeyManager] Accessibility trusted: \(isAccessibilityGranted)")

        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passRetained(self)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                if type == .flagsChanged {
                    let rawFlags = event.flags.rawValue
                    let hasCmd = event.flags.contains(.maskCommand)
                    let deviceFlags = rawFlags & 0xFF
                    let isRightCmd = hasCmd && (deviceFlags & 0x10) != 0

                    Log.d("[HotkeyManager] flags: raw=\(rawFlags) dev=0x\(String(deviceFlags, radix: 16)) cmd=\(hasCmd) rightCmd=\(isRightCmd)")

                    Task { @MainActor in
                        if isRightCmd && !manager.isKeyHeld {
                            Log.d("[HotkeyManager] Right ⌘ DOWN → start")
                            manager.isKeyHeld = true
                            manager.onRecordStart?()
                        } else if !isRightCmd && manager.isKeyHeld {
                            Log.d("[HotkeyManager] Right ⌘ UP → stop")
                            manager.isKeyHeld = false
                            manager.onRecordStop?()
                        }
                    }
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr.toOpaque()
        )

        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            Log.d("[HotkeyManager] CGEvent tap OK (Right ⌘ = push to talk)")
        } else {
            selfPtr.release()
            Log.d("[HotkeyManager] CGEvent tap FAILED → fallback to NSEvent monitor")
            setupFallbackMonitor()
        }
    }

    private func setupFallbackMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Log.d("[HotkeyManager] NSEvent flags: raw=\(event.modifierFlags.rawValue)")
        }
    }

    @discardableResult
    private func requestAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }
}
