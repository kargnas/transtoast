import Foundation

/// Detects "the same text copied twice in a row" from clipboard change events.
///
/// `DoublePressDetector` only checks timing, which made pasteboard polling fire on
/// any two clipboard mutations within the interval (e.g. repeated Cmd+X cuts of
/// different lines in VS Code). Clipboard-driven triggering must additionally
/// require identical text so only an intentional double copy starts translation.
public struct ClipboardDoubleCopyDetector: Sendable {
    public let interval: TimeInterval
    private var lastText: String?
    private var lastCopyAt: TimeInterval?

    public init(interval: TimeInterval = 1.0) {
        self.interval = interval
        lastText = nil
        lastCopyAt = nil
    }

    public mutating func registerCopy(of text: String, at timestamp: TimeInterval) -> Bool {
        if let previousText = lastText,
           let previousAt = lastCopyAt,
           previousText == text,
           timestamp - previousAt <= interval {
            // Reset after a successful match so a triple-copy creates one request, not two.
            reset()
            return true
        }

        lastText = text
        lastCopyAt = timestamp
        return false
    }

    public mutating func reset() {
        lastText = nil
        lastCopyAt = nil
    }
}
