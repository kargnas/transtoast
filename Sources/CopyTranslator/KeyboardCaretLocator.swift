import AppKit
import ApplicationServices

enum KeyboardCaretLocator {
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
