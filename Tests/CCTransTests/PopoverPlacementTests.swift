import CCTransCore
import Testing

struct PopoverPlacementTests {
    private let workArea = PopoverRect(x: 0, y: 0, width: 1_000, height: 800)
    private let size = PopoverSize(width: 356, height: 150)

    @Test func centersBubbleOnMiddleAnchorAndPointsArrowAtAnchor() {
        let placement = PopoverPlacementCalculator.place(
            size: size,
            anchor: PopoverRect(x: 492, y: 500, width: 16, height: 18),
            workArea: workArea,
            fallbackPosition: .bottomRight
        )

        #expect(placement.originX == 322)
        #expect(placement.originY == 342)
        #expect(placement.arrowEdge == .top)
        #expect(placement.arrowX == 178)
    }

    @Test func flipsAboveAnchorNearBottomOfScreen() {
        let placement = PopoverPlacementCalculator.place(
            size: size,
            anchor: PopoverRect(x: 492, y: 40, width: 16, height: 18),
            workArea: workArea,
            fallbackPosition: .bottomRight
        )

        #expect(placement.originY == 66)
        #expect(placement.arrowEdge == .bottom)
        #expect(placement.arrowX == 178)
    }

    @Test func clampsLeftEdgeButKeepsArrowNearAnchor() {
        let placement = PopoverPlacementCalculator.place(
            size: size,
            anchor: PopoverRect(x: 18, y: 500, width: 10, height: 18),
            workArea: workArea,
            fallbackPosition: .bottomRight
        )

        #expect(placement.originX == 24)
        #expect(placement.arrowEdge == .top)
        #expect(placement.arrowX == 42)
    }

    @Test func clampsRightEdgeButKeepsArrowNearAnchor() {
        let placement = PopoverPlacementCalculator.place(
            size: size,
            anchor: PopoverRect(x: 970, y: 500, width: 10, height: 18),
            workArea: workArea,
            fallbackPosition: .bottomRight
        )

        #expect(placement.originX == 620)
        #expect(placement.arrowEdge == .top)
        #expect(placement.arrowX == 314)
    }

    @Test func pointsArrowAtCaretAcrossMultipleScreenPositions() {
        for x in [80.0, 250.0, 500.0, 750.0, 920.0] {
            for y in [80.0, 250.0, 500.0, 720.0] {
                let anchor = PopoverRect(x: x, y: y, width: 16, height: 18)
                let placement = PopoverPlacementCalculator.place(
                    size: size,
                    anchor: anchor,
                    workArea: workArea,
                    fallbackPosition: .bottomRight
                )
                let expectedArrowTarget = clamp(anchor.midX, placement.originX + 42, placement.originX + size.width - 42)

                #expect(abs((placement.originX + placement.arrowX) - expectedArrowTarget) < 0.001)
                #expect(placement.originX >= 24)
                #expect(placement.originX + size.width <= workArea.width - 24)
                #expect(placement.originY >= 24)
                #expect(placement.originY + size.height <= workArea.height - 24)
            }
        }
    }

    @Test func clampsVerticallyWhenAnchorHasNoClearSide() {
        let placement = PopoverPlacementCalculator.place(
            size: PopoverSize(width: 356, height: 760),
            anchor: PopoverRect(x: 492, y: 380, width: 16, height: 18),
            workArea: workArea,
            fallbackPosition: .bottomRight
        )

        #expect(placement.originY == 24)
        #expect(placement.arrowEdge == .top)
    }

    @Test func fallbackUsesConfiguredCornerOnlyWithoutAnchor() {
        let placement = PopoverPlacementCalculator.place(
            size: size,
            anchor: nil,
            workArea: workArea,
            fallbackPosition: .topLeft
        )

        #expect(placement.originX == 24)
        #expect(placement.originY == 626)
        #expect(placement.arrowEdge == .none)
    }

    private func clamp(_ value: Double, _ minValue: Double, _ maxValue: Double) -> Double {
        min(max(value, minValue), maxValue)
    }
}
