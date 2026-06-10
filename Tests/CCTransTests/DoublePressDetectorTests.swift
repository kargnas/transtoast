import CCTransCore
import Testing

@Test func detectsTwoPressesInsideInterval() {
    var detector = DoublePressDetector()

    #expect(detector.registerPress(at: 10.0) == false)
    #expect(detector.registerPress(at: 11.0) == true)
}

@Test func resetsAfterSuccessfulDoublePress() {
    var detector = DoublePressDetector()

    #expect(detector.registerPress(at: 10.0) == false)
    #expect(detector.registerPress(at: 10.4) == true)
    #expect(detector.registerPress(at: 10.6) == false)
}

@Test func treatsLateSecondPressAsNewFirstPress() {
    var detector = DoublePressDetector()

    #expect(detector.registerPress(at: 10.0) == false)
    #expect(detector.registerPress(at: 11.1) == false)
    #expect(detector.registerPress(at: 11.9) == true)
}
