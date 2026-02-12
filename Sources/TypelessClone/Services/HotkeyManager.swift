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
    private var eventTapRefcon: UnsafeMutableRawPointer?
    private var lastFnPressed = false
    private var fnReleaseWatchdog: Timer?

    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?

    func start() {
        stop()
        isAccessibilityGranted = requestAccessibility()
        Log.d("[HotkeyManager] Accessibility trusted: \(isAccessibilityGranted)")
        Log.d("[HotkeyManager] Input Monitoring must be enabled for global key capture")

        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        let retainedSelf = Unmanaged.passRetained(self)
        let refcon = retainedSelf.toOpaque()
        eventTapRefcon = refcon

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
                        Log.d("[HotkeyManager] CGEvent tap re-enabled")
                    }
                    return Unmanaged.passUnretained(event)
                }

                if type == .flagsChanged {
                    let rawFlags = event.flags.rawValue
                    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                    let fnPressed = event.flags.contains(.maskSecondaryFn)
                    let fnChanged = fnPressed != manager.lastFnPressed

                    Log.d("[HotkeyManager] flags: raw=\(rawFlags) keyCode=\(keyCode) fn=\(fnPressed) fnChanged=\(fnChanged)")

                    Task { @MainActor in
                        guard fnChanged else { return }
                        manager.lastFnPressed = fnPressed

                        if fnPressed && !manager.isKeyHeld {
                            Log.d("[HotkeyManager] Fn DOWN → start")
                            manager.isKeyHeld = true
                            manager.onRecordStart?()
                            manager.startFnReleaseWatchdog()
                        } else if !fnPressed && manager.isKeyHeld {
                            Log.d("[HotkeyManager] Fn UP → stop")
                            manager.isKeyHeld = false
                            manager.onRecordStop?()
                            manager.stopFnReleaseWatchdog()
                        }
                    }
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        )

        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            Log.d("[HotkeyManager] CGEvent tap OK (Fn = push to talk)")
        } else {
            retainedSelf.release()
            eventTapRefcon = nil
            Log.d("[HotkeyManager] CGEvent tap FAILED → fallback to NSEvent monitor")
            setupFallbackMonitor()
        }
    }

    private func setupFallbackMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            Log.d("[HotkeyManager] NSEvent flags: raw=\(event.modifierFlags.rawValue)")
        }
    }

    @discardableResult
    private func requestAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    private func startFnReleaseWatchdog() {
        fnReleaseWatchdog?.invalidate()
        fnReleaseWatchdog = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else {
                    timer.invalidate()
                    return
                }
                let flags = CGEventSource.flagsState(.combinedSessionState)
                let fnPressed = flags.contains(.maskSecondaryFn)
                if !fnPressed && self.isKeyHeld {
                    Log.d("[HotkeyManager] Fn watchdog detected UP → stop")
                    self.lastFnPressed = false
                    self.isKeyHeld = false
                    self.onRecordStop?()
                    self.stopFnReleaseWatchdog()
                } else if !self.isKeyHeld {
                    self.stopFnReleaseWatchdog()
                }
            }
        }
    }

    private func stopFnReleaseWatchdog() {
        fnReleaseWatchdog?.invalidate()
        fnReleaseWatchdog = nil
    }

    func stop() {
        stopFnReleaseWatchdog()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        if let refcon = eventTapRefcon {
            Unmanaged<HotkeyManager>.fromOpaque(refcon).release()
            eventTapRefcon = nil
        }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        lastFnPressed = false
        isKeyHeld = false
    }
}
