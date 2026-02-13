import Cocoa
import Carbon.HIToolbox

enum TriggerKey: String, CaseIterable, Identifiable {
    case fn
    case rightOption
    case rightCommand
    case control

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fn: return "fn"
        case .rightOption: return "右 Option (⌥)"
        case .rightCommand: return "右 Command (⌘)"
        case .control: return "Control (⌃)"
        }
    }

    var flagMask: CGEventFlags {
        switch self {
        case .fn: return .maskSecondaryFn
        case .rightOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .control: return .maskControl
        }
    }

    /// Key codes used to distinguish left/right variants.
    /// fn has no specific keyCode in flagsChanged events, so empty set means "skip keyCode check".
    var keyCodes: Set<CGKeyCode> {
        switch self {
        case .fn: return []
        case .rightOption: return [61]
        case .rightCommand: return [54]
        case .control: return [59, 62]
        }
    }
}

@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    @Published var isKeyHeld = false
    @Published var isAccessibilityGranted = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var eventTapRefcon: UnsafeMutableRawPointer?
    private var lastKeyPressed = false
    private var releaseWatchdog: Timer?
    private var pendingStopWorkItem: DispatchWorkItem?
    private var pendingStartWorkItem: DispatchWorkItem?
    private var comboKeyDetected = false
    private var thresholdKeyMonitor: Any?
    private let releaseDebounceSeconds: TimeInterval = 0.18
    private let pressThresholdSeconds: TimeInterval = 0.3
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
        lastKeyPressed = currentTriggerKeyPressed()

        setupEventTap()
        setupEventMonitors()
    }

    private func currentTriggerKeyPressed() -> Bool {
        let triggerKey = Config.shared.triggerKey
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return flags.contains(triggerKey.flagMask)
    }

    private func setupEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
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
                        manager.handleKeySignal(keyCode: keyCode, source: "tap")
                    }
                }

                if type == .keyDown {
                    Task { @MainActor in
                        manager.handleComboKeyDetected(source: "tap-keyDown")
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
            Log.d("[HotkeyManager] CGEvent tap OK (\(Config.shared.triggerKey.displayName) = push to talk)")
        } else {
            retainedSelf.release()
            eventTapRefcon = nil
            Log.d("[HotkeyManager] CGEvent tap FAILED → fallback to NSEvent monitor")
        }
    }

    private func setupEventMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleKeySignal(keyCode: CGKeyCode(event.keyCode), source: "global")
            }
        }
    }

    private func handleKeySignal(keyCode: CGKeyCode, source: String) {
        let triggerKey = Config.shared.triggerKey
        let keyPressed = currentTriggerKeyPressed()

        // For keys that distinguish left/right, verify keyCode matches.
        // When flag is released while recording, always allow stop (safety).
        if !triggerKey.keyCodes.isEmpty && keyPressed {
            guard triggerKey.keyCodes.contains(keyCode) else { return }
        }

        let keyChanged = keyPressed != lastKeyPressed
        if !keyChanged {
            if keyPressed {
                pendingStopWorkItem?.cancel()
                pendingStopWorkItem = nil
            }
            return
        }

        lastKeyPressed = keyPressed
        Log.d("[HotkeyManager] Key state changed (\(source)) keyCode=\(keyCode) key=\(triggerKey.rawValue) pressed=\(keyPressed)")

        if keyPressed && !isKeyHeld {
            pendingStopWorkItem?.cancel()
            pendingStopWorkItem = nil

            guard pendingStartWorkItem == nil else { return }

            comboKeyDetected = false
            Log.d("[HotkeyManager] Key DOWN → waiting \(pressThresholdSeconds)s threshold")
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingStartWorkItem = nil
                self.stopThresholdKeyMonitor()

                guard self.currentTriggerKeyPressed(), !self.comboKeyDetected else {
                    Log.d("[HotkeyManager] Key released or combo detected before threshold → ignored")
                    return
                }

                Log.d("[HotkeyManager] Threshold met → start")
                self.isKeyHeld = true
                self.onRecordStartHandler()
                self.startReleaseWatchdog()
            }
            pendingStartWorkItem = workItem
            startThresholdKeyMonitor()
            DispatchQueue.main.asyncAfter(deadline: .now() + pressThresholdSeconds, execute: workItem)
        } else if !keyPressed {
            if let pending = pendingStartWorkItem {
                pending.cancel()
                pendingStartWorkItem = nil
                stopThresholdKeyMonitor()
                Log.d("[HotkeyManager] Key released before threshold → cancelled")
            }
            if isKeyHeld {
                requestDebouncedStop(source: source)
            }
        }
    }

    @discardableResult
    private func requestAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    private func startReleaseWatchdog() {
        releaseWatchdog?.invalidate()
        releaseWatchdog = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            let capturedTimer = timer
            Task { @MainActor [weak self] in
                guard let self else {
                    capturedTimer.invalidate()
                    return
                }
                let keyPressed = self.currentTriggerKeyPressed()
                if !keyPressed && self.isKeyHeld {
                    self.lastKeyPressed = false
                    self.requestDebouncedStop(source: "watchdog")
                } else if !self.isKeyHeld {
                    self.stopReleaseWatchdog()
                }
            }
        }
    }

    private func stopReleaseWatchdog() {
        releaseWatchdog?.invalidate()
        releaseWatchdog = nil
    }

    private func handleComboKeyDetected(source: String) {
        guard pendingStartWorkItem != nil else { return }
        Log.d("[HotkeyManager] Combo key detected (\(source)) → cancelling pending start")
        comboKeyDetected = true
        pendingStartWorkItem?.cancel()
        pendingStartWorkItem = nil
        stopThresholdKeyMonitor()
    }

    private func startThresholdKeyMonitor() {
        stopThresholdKeyMonitor()
        thresholdKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            // subtype 8 = メディアキー (音量・輝度など)
            if event.subtype.rawValue == 8 {
                Task { @MainActor [weak self] in
                    self?.handleComboKeyDetected(source: "systemDefined-media")
                }
            }
        }
    }

    private func stopThresholdKeyMonitor() {
        if let m = thresholdKeyMonitor {
            NSEvent.removeMonitor(m)
            thresholdKeyMonitor = nil
        }
    }

    private func requestDebouncedStop(source: String) {
        guard pendingStopWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingStopWorkItem = nil

            let stillReleased = !self.currentTriggerKeyPressed()
            guard stillReleased, self.isKeyHeld else {
                Log.d("[HotkeyManager] Ignored transient key UP (\(source))")
                return
            }

            Log.d("[HotkeyManager] Key UP confirmed (\(source)) → stop")
            self.lastKeyPressed = false
            self.isKeyHeld = false
            Log.d("[HotkeyManager] Dispatching onRecordStop")
            self.onRecordStopHandler()
            self.stopReleaseWatchdog()
        }

        pendingStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + releaseDebounceSeconds, execute: workItem)
    }

    func resetState() {
        pendingStartWorkItem?.cancel()
        pendingStartWorkItem = nil
        pendingStopWorkItem?.cancel()
        pendingStopWorkItem = nil
        stopReleaseWatchdog()
        stopThresholdKeyMonitor()
        comboKeyDetected = false
        lastKeyPressed = false
        isKeyHeld = false
        Log.d("[HotkeyManager] State reset (triggerKey=\(Config.shared.triggerKey.rawValue))")
    }

    func stop() {
        resetState()
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
    }
}
