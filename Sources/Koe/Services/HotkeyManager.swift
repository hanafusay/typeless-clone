import Cocoa
import Carbon.HIToolbox

@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    @Published var isKeyHeld = false
    @Published var isAccessibilityGranted = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var eventTapRefcon: UnsafeMutableRawPointer?
    private var lastFnPressed = false
    private var fnReleaseWatchdog: Timer?
    private var pendingStopWorkItem: DispatchWorkItem?
    private let releaseDebounceSeconds: TimeInterval = 0.18
    private var onRecordStartHandler: () -> Void = {}
    private var onRecordStopHandler: () -> Void = {}

    private init() {}

    func start(onRecordStart: @escaping () -> Void, onRecordStop: @escaping () -> Void) {
        stop()
        onRecordStartHandler = onRecordStart
        onRecordStopHandler = onRecordStop
        isAccessibilityGranted = requestAccessibility()
        Log.d("[HotkeyManager] Accessibility trusted: \(isAccessibilityGranted)")
        Log.d("[HotkeyManager] Input Monitoring must be enabled for global key capture")
        lastFnPressed = currentFnPressed()

        setupEventTap()
        setupEventMonitors()
    }

    private func currentFnPressed() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn)
    }

    private func setupEventTap() {
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
                    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                    Task { @MainActor in
                        manager.handleFnSignal(keyCode: keyCode, source: "tap")
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
        }
    }

    private func setupEventMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFnSignal(keyCode: CGKeyCode(event.keyCode), source: "global")
            }
        }
    }

    private func handleFnSignal(keyCode: CGKeyCode, source: String) {
        let fnPressed = currentFnPressed()
        let fnChanged = fnPressed != lastFnPressed
        if !fnChanged {
            if fnPressed {
                pendingStopWorkItem?.cancel()
                pendingStopWorkItem = nil
            }
            return
        }

        lastFnPressed = fnPressed
        Log.d("[HotkeyManager] Fn state changed (\(source)) keyCode=\(keyCode) fn=\(fnPressed)")

        if fnPressed && !isKeyHeld {
            pendingStopWorkItem?.cancel()
            pendingStopWorkItem = nil
            Log.d("[HotkeyManager] Fn DOWN → start")
            isKeyHeld = true
            Log.d("[HotkeyManager] Dispatching onRecordStart")
            onRecordStartHandler()
            startFnReleaseWatchdog()
        } else if !fnPressed && isKeyHeld {
            requestDebouncedStop(source: source)
        }
    }

    @discardableResult
    private func requestAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    private func startFnReleaseWatchdog() {
        fnReleaseWatchdog?.invalidate()
        fnReleaseWatchdog = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            let capturedTimer = timer
            Task { @MainActor [weak self] in
                guard let self else {
                    capturedTimer.invalidate()
                    return
                }
                let fnPressed = self.currentFnPressed()
                if !fnPressed && self.isKeyHeld {
                    self.lastFnPressed = false
                    self.requestDebouncedStop(source: "watchdog")
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

    private func requestDebouncedStop(source: String) {
        guard pendingStopWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingStopWorkItem = nil

            let stillReleased = !self.currentFnPressed()
            guard stillReleased, self.isKeyHeld else {
                Log.d("[HotkeyManager] Ignored transient Fn UP (\(source))")
                return
            }

            Log.d("[HotkeyManager] Fn UP confirmed (\(source)) → stop")
            self.lastFnPressed = false
            self.isKeyHeld = false
            Log.d("[HotkeyManager] Dispatching onRecordStop")
            self.onRecordStopHandler()
            self.stopFnReleaseWatchdog()
        }

        pendingStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + releaseDebounceSeconds, execute: workItem)
    }

    func stop() {
        pendingStopWorkItem?.cancel()
        pendingStopWorkItem = nil
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
        lastFnPressed = false
        isKeyHeld = false
    }
}
