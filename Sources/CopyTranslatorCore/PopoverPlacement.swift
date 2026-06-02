import Foundation

public struct PopoverRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var midX: Double { x + width / 2 }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
}

public struct PopoverSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public enum PopoverArrowEdge: Equatable, Sendable {
    case top
    case bottom
    case none
}

public enum PopoverFallbackPosition: Equatable, Sendable {
    case bottomRight
    case bottomLeft
    case topRight
    case topLeft
}

public struct PopoverPlacement: Equatable, Sendable {
    public var originX: Double
    public var originY: Double
    public var arrowEdge: PopoverArrowEdge
    public var arrowX: Double

    public init(originX: Double, originY: Double, arrowEdge: PopoverArrowEdge, arrowX: Double) {
        self.originX = originX
        self.originY = originY
        self.arrowEdge = arrowEdge
        self.arrowX = arrowX
    }
}

public enum PopoverPlacementCalculator {
    public static func place(
        size: PopoverSize,
        anchor: PopoverRect?,
        workArea: PopoverRect,
        fallbackPosition: PopoverFallbackPosition,
        margin: Double = 24,
        gap: Double = 8,
        arrowMinimumX: Double = 42
    ) -> PopoverPlacement {
        if let anchor {
            return anchoredPlacement(
                size: size,
                anchor: anchor,
                workArea: workArea,
                margin: margin,
                gap: gap,
                arrowMinimumX: arrowMinimumX
            )
        }

        let left = workArea.minX + margin
        let right = workArea.maxX - size.width - margin
        let bottom = workArea.minY + margin
        let top = workArea.maxY - size.height - margin

        switch fallbackPosition {
        case .bottomRight:
            return PopoverPlacement(originX: right, originY: bottom, arrowEdge: .none, arrowX: size.width / 2)
        case .bottomLeft:
            return PopoverPlacement(originX: left, originY: bottom, arrowEdge: .none, arrowX: size.width / 2)
        case .topRight:
            return PopoverPlacement(originX: right, originY: top, arrowEdge: .none, arrowX: size.width / 2)
        case .topLeft:
            return PopoverPlacement(originX: left, originY: top, arrowEdge: .none, arrowX: size.width / 2)
        }
    }

    private static func anchoredPlacement(
        size: PopoverSize,
        anchor: PopoverRect,
        workArea: PopoverRect,
        margin: Double,
        gap: Double,
        arrowMinimumX: Double
    ) -> PopoverPlacement {
        let originX = clamp(
            anchor.midX - size.width / 2,
            workArea.minX + margin,
            workArea.maxX - size.width - margin
        )
        let arrowX = clamp(anchor.midX - originX, arrowMinimumX, size.width - arrowMinimumX)

        let belowY = anchor.minY - gap - size.height
        if belowY >= workArea.minY + margin {
            return PopoverPlacement(originX: originX, originY: belowY, arrowEdge: .top, arrowX: arrowX)
        }

        let aboveY = anchor.maxY + gap
        if aboveY + size.height <= workArea.maxY - margin {
            return PopoverPlacement(originX: originX, originY: aboveY, arrowEdge: .bottom, arrowX: arrowX)
        }

        let originY = clamp(
            belowY,
            workArea.minY + margin,
            workArea.maxY - size.height - margin
        )
        let edge: PopoverArrowEdge = originY < anchor.minY ? .top : .bottom
        return PopoverPlacement(originX: originX, originY: originY, arrowEdge: edge, arrowX: arrowX)
    }

    private static func clamp(_ value: Double, _ minValue: Double, _ maxValue: Double) -> Double {
        if minValue > maxValue {
            return minValue
        }
        return min(max(value, minValue), maxValue)
    }
}
