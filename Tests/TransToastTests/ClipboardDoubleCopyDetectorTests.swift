import TransToastCore
import Testing

@Test func detectsSameTextCopiedTwiceInsideInterval() {
    var detector = ClipboardDoubleCopyDetector()

    #expect(detector.registerCopy(of: "hello", at: 10.0) == false)
    #expect(detector.registerCopy(of: "hello", at: 10.8) == true)
}

@Test func ignoresDifferentTextInsideInterval() {
    var detector = ClipboardDoubleCopyDetector()

    // Repeated Cmd+X in an editor yields different lines each time; must never fire.
    #expect(detector.registerCopy(of: "line one", at: 10.0) == false)
    #expect(detector.registerCopy(of: "line two", at: 10.3) == false)
    #expect(detector.registerCopy(of: "line three", at: 10.6) == false)
}

@Test func sameTextAfterDifferentTextStillFires() {
    var detector = ClipboardDoubleCopyDetector()

    #expect(detector.registerCopy(of: "old", at: 10.0) == false)
    #expect(detector.registerCopy(of: "new", at: 10.3) == false)
    #expect(detector.registerCopy(of: "new", at: 10.6) == true)
}

@Test func treatsLateSameTextAsNewFirstCopy() {
    var detector = ClipboardDoubleCopyDetector()

    #expect(detector.registerCopy(of: "hello", at: 10.0) == false)
    #expect(detector.registerCopy(of: "hello", at: 11.1) == false)
    #expect(detector.registerCopy(of: "hello", at: 11.9) == true)
}

@Test func resetsAfterSuccessfulDoubleCopy() {
    var detector = ClipboardDoubleCopyDetector()

    #expect(detector.registerCopy(of: "hello", at: 10.0) == false)
    #expect(detector.registerCopy(of: "hello", at: 10.4) == true)
    // Triple-copy creates one request, not two.
    #expect(detector.registerCopy(of: "hello", at: 10.6) == false)
}

@Test func resetClearsPendingState() {
    var detector = ClipboardDoubleCopyDetector()

    #expect(detector.registerCopy(of: "hello", at: 10.0) == false)
    detector.reset()
    #expect(detector.registerCopy(of: "hello", at: 10.4) == false)
}
