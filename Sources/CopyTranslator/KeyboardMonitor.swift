import AppKit
import CopyTranslatorCore

@MainActor
final class KeyboardMonitor {
    private struct KeySnapshot: Sendable {
        let keyCode: UInt16
        let modifierFlags: UInt
        let timestamp: TimeInterval
        let isRepeat: Bool

        init(event: NSEvent) {
            keyCode = event.keyCode
            modifierFlags = event.modifierFlags.rawValue
            timestamp = event.timestamp
            isRepeat = event.isARepeat
        }
    }

    private let onDoubleCopy: () -> Void
    private let onScreenshot: () -> Void
    private var detector = DoublePressDetector()
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(onDoubleCopy: @escaping () -> Void, onScreenshot: @escaping () -> Void) {
        self.onDoubleCopy = onDoubleCopy
        self.onScreenshot = onScreenshot
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else {
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let snapshot = KeySnapshot(event: event)
            Task { @MainActor [weak self] in
                self?.handle(snapshot)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(KeySnapshot(event: event), monitorsCopyShortcut: false)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        detector.reset()
    }

    private func handle(_ event: KeySnapshot) {
        handle(event, monitorsCopyShortcut: true)
    }

    private func handle(_ event: KeySnapshot, monitorsCopyShortcut: Bool) {
        guard !event.isRepeat else {
            return
        }

        let flags = NSEvent.ModifierFlags(rawValue: event.modifierFlags)
            .intersection(.deviceIndependentFlagsMask)
        let commandOnly = flags.contains(.command)
            && !flags.contains(.shift)
            && !flags.contains(.option)
            && !flags.contains(.control)

        if monitorsCopyShortcut, commandOnly, event.keyCode == 8 {
            if detector.registerPress(at: event.timestamp) {
                onDoubleCopy()
            }
            return
        }

        let screenshotShortcut = flags.contains(.command)
            && flags.contains(.shift)
            && !flags.contains(.option)
            && !flags.contains(.control)

        if screenshotShortcut, event.keyCode == 19 {
            onScreenshot()
        }
    }
}
