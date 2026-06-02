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
