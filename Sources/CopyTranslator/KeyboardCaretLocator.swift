import AppKit
import ApplicationServices

enum KeyboardCaretLocator {
    private static let maxTextSearchNodes = 700
    private static let maxTextSearchDepth = 9

    static func focusedTextBounds(for copiedText: String?) -> CGRect? {
        if let copiedText,
           !copiedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let frontmostApplication = NSWorkspace.shared.frontmostApplication {
            let applicationElement = AXUIElementCreateApplication(frontmostApplication.processIdentifier)
            if let focusedElement = focusedElement(in: applicationElement) {
                var remainingFocusedNodes = maxTextSearchNodes
                if let focusedTextBounds = copiedTextBounds(
                    for: copiedText,
                    in: focusedElement,
                    depth: 0,
                    remainingNodes: &remainingFocusedNodes
                ) {
                    return focusedTextBounds
                }
            }

            var remainingApplicationNodes = maxTextSearchNodes
            if let copiedTextBounds = copiedTextBounds(
                for: copiedText,
                in: applicationElement,
                depth: 0,
                remainingNodes: &remainingApplicationNodes
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

    private static func focusedTextCaretBounds(in applicationElement: AXUIElement) -> CGRect? {
        guard let focusedObject = focusedElement(in: applicationElement) else {
            return nil
        }

        return focusedTextCaretBounds(inFocusedElement: focusedObject)
    }

    private static func focusedElement(in applicationElement: AXUIElement) -> AXUIElement? {
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

        return (focusedObject as! AXUIElement)
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
            return nil
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

    private static func convertTopLeftRect(_ rect: CGRect, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: screenFrame.maxY - rect.maxY + screenFrame.minY,
            width: rect.width,
            height: rect.height
        )
    }
}
