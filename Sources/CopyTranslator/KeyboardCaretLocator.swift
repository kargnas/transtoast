import AppKit
import ApplicationServices

enum KeyboardCaretLocator {
    private static let maxTextSearchNodes = 700
    private static let maxTextSearchDepth = 9

    static func focusedTextBounds(for copiedText: String?) -> CGRect? {
        if let copiedText,
           !copiedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let frontmostApplication = NSWorkspace.shared.frontmostApplication {
            var remainingNodes = maxTextSearchNodes
            if let copiedTextBounds = copiedTextBounds(
                for: copiedText,
                in: AXUIElementCreateApplication(frontmostApplication.processIdentifier),
                depth: 0,
                remainingNodes: &remainingNodes
            ) {
                return copiedTextBounds
            }
        }

        return focusedTextCaretBounds()
    }

    static func focusedTextCaretBounds() -> CGRect? {
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           let accessibilityRect = focusedTextCaretBounds(
            in: AXUIElementCreateApplication(frontmostApplication.processIdentifier)
           ),
           let screenRect = screenRect(fromAccessibilityRect: accessibilityRect) {
            return screenRect
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        ) == .success,
            let focusedObject,
            let accessibilityRect = focusedTextCaretBounds(inFocusedElement: focusedObject as! AXUIElement),
            let screenRect = screenRect(fromAccessibilityRect: accessibilityRect)
        else {
            return nil
        }

        return screenRect
    }

    static func frontmostWindowAnchorBounds() -> CGRect? {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              let windowBounds = frontmostWindowBounds(for: frontmostApplication.processIdentifier) else {
            return nil
        }

        return CGRect(
            x: windowBounds.midX,
            y: max(windowBounds.minY, windowBounds.maxY - 130),
            width: 1,
            height: 1
        )
    }

    private static func focusedTextCaretBounds(in applicationElement: AXUIElement) -> CGRect? {
        var focusedObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        ) == .success,
            let focusedObject
        else {
            return nil
        }

        return focusedTextCaretBounds(inFocusedElement: focusedObject as! AXUIElement)
    }

    private static func focusedTextCaretBounds(inFocusedElement focusedElement: AXUIElement) -> CGRect? {
        var selectedRangeObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeObject
        ) == .success,
            let selectedRange = selectedRangeObject
        else {
            return nil
        }

        var boundsObject: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange,
            &boundsObject
        ) == .success,
            let boundsObject,
            CFGetTypeID(boundsObject) == AXValueGetTypeID()
        else {
            return nil
        }

        let boundsValue = boundsObject as! AXValue
        guard AXValueGetType(boundsValue) == .cgRect else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue, .cgRect, &rect),
              rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.width.isFinite,
              rect.height.isFinite,
              rect.width >= 0,
              rect.height > 0 else {
            return nil
        }

        return rect.standardized
    }

    private static func copiedTextBounds(
        for copiedText: String,
        in element: AXUIElement,
        depth: Int,
        remainingNodes: inout Int
    ) -> CGRect? {
        guard depth <= maxTextSearchDepth, remainingNodes > 0 else {
            return nil
        }
        remainingNodes -= 1

        if selectedText(in: element).map({ normalized($0) == normalized(copiedText) }) == true,
           let selectedRangeBounds = selectedRangeBounds(in: element) {
            return selectedRangeBounds
        }

        if let textBounds = textBounds(for: copiedText, in: element) {
            return textBounds
        }

        for child in children(of: element) {
            if let bounds = copiedTextBounds(
                for: copiedText,
                in: child,
                depth: depth + 1,
                remainingNodes: &remainingNodes
            ) {
                return bounds
            }
        }

        return nil
    }

    private static func selectedText(in element: AXUIElement) -> String? {
        stringAttribute(kAXSelectedTextAttribute as CFString, in: element)
    }

    private static func selectedRangeBounds(in element: AXUIElement) -> CGRect? {
        var selectedRangeObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeObject
        ) == .success,
            let selectedRangeObject,
            let accessibilityRect = bounds(forRange: selectedRangeObject, in: element),
            let screenRect = screenRect(fromAccessibilityRect: accessibilityRect) else {
            return elementFrameBounds(element)
        }

        return screenRect
    }

    private static func textBounds(for copiedText: String, in element: AXUIElement) -> CGRect? {
        for attribute in [
            kAXValueAttribute as CFString,
            kAXTitleAttribute as CFString,
            kAXDescriptionAttribute as CFString,
        ] {
            guard let text = stringAttribute(attribute, in: element) else {
                continue
            }

            let range = (text as NSString).range(of: copiedText)
            guard range.location != NSNotFound else {
                continue
            }

            var cfRange = CFRange(location: range.location, length: range.length)
            if let rangeValue = AXValueCreate(.cfRange, &cfRange),
               let accessibilityRect = bounds(forRange: rangeValue, in: element),
               let screenRect = screenRect(fromAccessibilityRect: accessibilityRect) {
                return screenRect
            }

            return elementFrameBounds(element)
        }

        return nil
    }

    private static func bounds(forRange range: CFTypeRef, in element: AXUIElement) -> CGRect? {
        var boundsObject: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &boundsObject
        ) == .success,
            let boundsObject,
            CFGetTypeID(boundsObject) == AXValueGetTypeID() else {
            return nil
        }

        let boundsValue = boundsObject as! AXValue
        guard AXValueGetType(boundsValue) == .cgRect else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue, .cgRect, &rect),
              rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.width.isFinite,
              rect.height.isFinite,
              rect.width >= 0,
              rect.height > 0 else {
            return nil
        }

        return rect.standardized
    }

    private static func elementFrameBounds(_ element: AXUIElement) -> CGRect? {
        var positionObject: CFTypeRef?
        var sizeObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionObject
        ) == .success,
            AXUIElementCopyAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                &sizeObject
            ) == .success,
            let positionObject,
            let sizeObject,
            CFGetTypeID(positionObject) == AXValueGetTypeID(),
            CFGetTypeID(sizeObject) == AXValueGetTypeID() else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionObject as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeObject as! AXValue, .cgSize, &size),
              size.width > 1,
              size.height > 1 else {
            return nil
        }

        return screenRect(fromAccessibilityRect: CGRect(origin: position, size: size))
    }

    private static func stringAttribute(_ attribute: CFString, in element: AXUIElement) -> String? {
        var object: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &object) == .success,
              let object else {
            return nil
        }

        return object as? String
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []

        for attribute in [kAXVisibleChildrenAttribute as CFString, kAXChildrenAttribute as CFString] {
            var object: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute, &object) == .success,
                  let object else {
                continue
            }

            if let children = object as? [AXUIElement] {
                result.append(contentsOf: children)
            }
        }

        return result
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func frontmostWindowBounds(for processIdentifier: pid_t) -> CGRect? {
        guard let windowInfos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for windowInfo in windowInfos {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == processIdentifier,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
                  let topLeftBounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  topLeftBounds.width > 1,
                  topLeftBounds.height > 1 else {
                continue
            }

            return screenRect(fromTopLeftRect: topLeftBounds)
        }

        return nil
    }

    private static func screenRect(fromAccessibilityRect rect: CGRect) -> CGRect? {
        guard rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.width.isFinite,
              rect.height.isFinite,
              rect.width >= 0,
              rect.height > 0 else {
            return nil
        }

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return nil
        }

        for screen in screens {
            let converted = convertTopLeftRect(rect, in: screen.frame)
            if screen.frame.contains(CGPoint(x: converted.midX, y: converted.midY)) {
                return converted
            }
        }

        let mainFrame = (NSScreen.main ?? screens[0]).frame
        return convertTopLeftRect(rect, in: mainFrame)
    }

    private static func screenRect(fromTopLeftRect rect: CGRect) -> CGRect? {
        screenRect(fromAccessibilityRect: rect)
    }

    private static func convertTopLeftRect(_ rect: CGRect, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: screenFrame.maxY - rect.maxY + screenFrame.minY,
            width: rect.width,
            height: rect.height
        )
    }
}
