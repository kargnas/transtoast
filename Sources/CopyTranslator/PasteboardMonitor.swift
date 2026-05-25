import AppKit
import CopyTranslatorCore

@MainActor
final class PasteboardMonitor {
    private let onDoubleCopy: () -> Void
    private var detector = DoublePressDetector()
    private var lastChangeCount: Int
    private var timer: DispatchSourceTimer?

    init(onDoubleCopy: @escaping () -> Void) {
        self.onDoubleCopy = onDoubleCopy
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else {
            return
        }

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + 0.15, repeating: 0.15)
        source.setEventHandler { [weak self] in
            self?.poll()
        }
        source.resume()
        timer = source
    }

    func stop() {
        timer?.cancel()
        timer = nil
        detector.reset()
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = changeCount
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            detector.reset()
            return
        }

        // Pasteboard polling keeps double-copy translation usable before macOS grants Input Monitoring.
        if detector.registerPress(at: Date.timeIntervalSinceReferenceDate) {
            onDoubleCopy()
        }
    }
}
