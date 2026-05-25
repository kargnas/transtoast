import Foundation

public struct DoublePressDetector: Sendable {
    public let interval: TimeInterval
    private var lastPressAt: TimeInterval?

    public init(interval: TimeInterval = 1.0) {
        self.interval = interval
        lastPressAt = nil
    }

    public mutating func registerPress(at timestamp: TimeInterval) -> Bool {
        guard let previous = lastPressAt else {
            lastPressAt = timestamp
            return false
        }

        let isDoublePress = timestamp - previous <= interval
        // Reset after a successful match so a triple-press creates one request, not two.
        lastPressAt = isDoublePress ? nil : timestamp
        return isDoublePress
    }

    public mutating func reset() {
        lastPressAt = nil
    }
}
