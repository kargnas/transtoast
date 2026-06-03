import AppKit
import CopyTranslatorCore

@MainActor
final class TranslationPopoverController {
    private let margin: CGFloat = 24
    private let caretGap: CGFloat = 8
    private let windowWidth: CGFloat = 356
    private let compactHeight: CGFloat = 118
    private let tallHeight: CGFloat = 160
    private let maxHeight: CGFloat = 560
    private let minimumDismissDuration: TimeInterval = 4
    private let maximumDismissDuration: TimeInterval = 10

    private var panel: TranslationPopoverPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private var hoverPollTimer: Timer?
    private var positionSaveWorkItem: DispatchWorkItem?
    private var pendingPositionSave: (() -> Void)?
    private var clickMonitorTokens: [Any] = []
    private var currentMode: String?
    private var onUserClose: (() -> Void)?
    private var isPointerInsidePanel = false

    func show(
        payload: TranslationPreviewPayload,
        settings: TranslatorSettings,
        caretBounds: CGRect?,
        modelOptions: [TranslationModelOption] = [],
        selectedModelOptionID: String? = nil,
        onUserClose: (() -> Void)? = nil,
        onPermissionRequested: (() -> Void)? = nil,
        onModelSelected: ((TranslationModelOption) -> Void)? = nil,
        onTargetLanguageSelected: ((String) -> Void)? = nil,
        onPositionChanged: ((CGPoint) -> Void)? = nil
    ) {
        close()

        let size = size(for: payload)
        let placement = placement(for: size, caretBounds: caretBounds, settings: settings)
        let panel = TranslationPopoverPanel(
            contentRect: CGRect(origin: placement.origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.level = .floating
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.onMoved = { [weak self] origin in
            self?.schedulePositionSave(origin, onPositionChanged: onPositionChanged)
        }
        let contentView = TranslationPopoverContentView(
            frame: CGRect(origin: .zero, size: size),
            payload: payload,
            arrowEdge: placement.arrowEdge,
            arrowX: placement.arrowX,
            onClose: { [weak self] in
                self?.closeFromUser()
            },
            onMouseEntered: { [weak self] in
                self?.pauseDismissTimer()
            },
            onMouseExited: { [weak self] in
                self?.resumeDismissTimer()
            },
            modelOptions: modelOptions,
            selectedModelOptionID: selectedModelOptionID,
            onPermissionRequested: onPermissionRequested,
            onModelSelected: onModelSelected,
            onTargetLanguageSelected: onTargetLanguageSelected
        )
        panel.contentView = contentView

        self.panel = panel
        self.onUserClose = onUserClose
        currentMode = payload.mode
        isPointerInsidePanel = false
        installClickMonitors(for: panel)
        startHoverPolling(for: panel)
        panel.orderFrontRegardless()
        scheduleDismissIfNeeded(mode: payload.mode)
    }

    func close() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        flushPendingPositionSave()
        hoverPollTimer?.invalidate()
        hoverPollTimer = nil
        removeClickMonitors()
        contentView?.stopDismissCountdown()
        panel?.orderOut(nil)
        panel = nil
        currentMode = nil
        onUserClose = nil
        isPointerInsidePanel = false
    }

    private func scheduleDismissIfNeeded(mode: String) {
        guard mode != "loading" else {
            return
        }

        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.close()
            }
        }
        dismissWorkItem = workItem
        let duration = contentView?.dismissDuration(
            minimum: minimumDismissDuration,
            maximum: maximumDismissDuration
        ) ?? minimumDismissDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
        contentView?.startDismissCountdown(duration: duration)
    }

    private func pauseDismissTimer() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        let duration = contentView?.dismissDuration(
            minimum: minimumDismissDuration,
            maximum: maximumDismissDuration
        ) ?? minimumDismissDuration
        contentView?.pauseDismissCountdown(duration: duration)
    }

    private func resumeDismissTimer() {
        guard let currentMode else {
            return
        }
        scheduleDismissIfNeeded(mode: currentMode)
    }

    private func schedulePositionSave(
        _ origin: CGPoint,
        onPositionChanged: ((CGPoint) -> Void)?
    ) {
        guard let onPositionChanged else {
            return
        }

        positionSaveWorkItem?.cancel()
        pendingPositionSave = {
            onPositionChanged(origin)
        }
        let workItem = DispatchWorkItem {
            self.pendingPositionSave?()
            self.pendingPositionSave = nil
            self.positionSaveWorkItem = nil
        }
        positionSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func flushPendingPositionSave() {
        positionSaveWorkItem?.cancel()
        positionSaveWorkItem = nil
        pendingPositionSave?()
        pendingPositionSave = nil
    }

    private func installClickMonitors(for panel: NSPanel) {
        removeClickMonitors()

        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self, weak panel] event in
            guard let self,
                  let panel,
                  event.window !== panel else {
                return event
            }
            self.closeFromUser()
            return event
        }) {
            clickMonitorTokens.append(localMonitor)
        }

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self, weak panel] _ in
            Task { @MainActor in
                guard let self,
                      let panel,
                      !panel.frame.contains(NSEvent.mouseLocation) else {
                    return
                }
                self.closeFromUser()
            }
        }) {
            clickMonitorTokens.append(globalMonitor)
        }
    }

    private func startHoverPolling(for panel: NSPanel) {
        hoverPollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self, weak panel] _ in
            Task { @MainActor in
                guard let self,
                      let panel else {
                    return
                }
                let isInside = panel.frame.contains(NSEvent.mouseLocation)
                guard isInside != self.isPointerInsidePanel else {
                    return
                }
                self.isPointerInsidePanel = isInside
                self.contentView?.setHovering(isInside)
                if isInside {
                    self.pauseDismissTimer()
                } else {
                    self.resumeDismissTimer()
                }
            }
        }
        hoverPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func removeClickMonitors() {
        for token in clickMonitorTokens {
            NSEvent.removeMonitor(token)
        }
        clickMonitorTokens.removeAll()
    }

    private var contentView: TranslationPopoverContentView? {
        panel?.contentView as? TranslationPopoverContentView
    }

    private func closeFromUser() {
        onUserClose?()
        close()
    }

    private func size(for payload: TranslationPreviewPayload) -> CGSize {
        let height: CGFloat
        switch payload.mode {
        case "loading":
            height = tallHeight
        case "error":
            height = textPanelHeight(for: payload.errorText ?? "Translation failed.", minimum: tallHeight)
        default:
            height = textPanelHeight(
                for: [payload.originalText, payload.translatedText].max(by: { $0.count < $1.count }) ?? payload.translatedText,
                minimum: compactHeight
            )
        }

        return CGSize(width: windowWidth, height: height)
    }

    private func textPanelHeight(for text: String, minimum: CGFloat) -> CGFloat {
        let horizontalInset: CGFloat = 24
        let contentInset: CGFloat = 22
        let arrowHeight: CGFloat = 18
        let bottomControlsHeight: CGFloat = 18
        let verticalPadding: CGFloat = 22
        let bodyWidth = windowWidth - horizontalInset * 2 - contentInset * 2
        let font = NSFont.preferredFont(forTextStyle: .body)
        let bodyHeight = ceil(
            (text as NSString).boundingRect(
                with: CGSize(width: bodyWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            ).height
        )

        return min(max(minimum, bodyHeight + bottomControlsHeight + verticalPadding + arrowHeight), maxHeight)
    }

    private func placement(
        for size: CGSize,
        caretBounds: CGRect?,
        settings: TranslatorSettings
    ) -> (origin: CGPoint, arrowEdge: PopoverArrowEdge, arrowX: CGFloat) {
        if settings.toastPosition == .custom,
           let toastCustomPosition = settings.toastCustomPosition {
            let origin = customOrigin(
                toastCustomPosition,
                size: size,
                screen: screen(containing: CGPoint(x: toastCustomPosition.x, y: toastCustomPosition.y))
            )
            return (origin, .none, size.width / 2)
        }

        let screen = caretBounds.flatMap(screen(containing:)) ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let result = PopoverPlacementCalculator.place(
            size: PopoverSize(width: Double(size.width), height: Double(size.height)),
            anchor: caretBounds.map {
                PopoverRect(
                    x: Double($0.minX),
                    y: Double($0.minY),
                    width: Double($0.width),
                    height: Double($0.height)
                )
            },
            workArea: PopoverRect(
                x: Double(visibleFrame.minX),
                y: Double(visibleFrame.minY),
                width: Double(visibleFrame.width),
                height: Double(visibleFrame.height)
            ),
            fallbackPosition: fallbackPosition(for: settings.toastPosition),
            margin: Double(margin),
            gap: Double(caretGap)
        )

        return (
            CGPoint(x: result.originX, y: result.originY),
            result.arrowEdge,
            CGFloat(result.arrowX)
        )
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private func customOrigin(
        _ position: ToastCustomPosition,
        size: CGSize,
        screen: NSScreen?
    ) -> CGPoint {
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1_440, height: 900)
        return CGPoint(
            x: clamp(CGFloat(position.x), visibleFrame.minX + margin, visibleFrame.maxX - size.width - margin),
            y: clamp(CGFloat(position.y), visibleFrame.minY + margin, visibleFrame.maxY - size.height - margin)
        )
    }

    private func fallbackPosition(for position: ToastPosition) -> PopoverFallbackPosition {
        switch position {
        case .bottomRight:
            .bottomRight
        case .bottomLeft:
            .bottomLeft
        case .topRight:
            .topRight
        case .topLeft:
            .topLeft
        case .custom:
            .bottomRight
        }
    }

    private func clamp(_ value: CGFloat, _ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        if minValue > maxValue {
            return minValue
        }
        return min(max(value, minValue), maxValue)
    }
}

final class TranslationPopoverPanel: NSPanel, NSWindowDelegate {
    var onMoved: ((CGPoint) -> Void)?

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        delegate = self
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func windowDidMove(_ notification: Notification) {
        onMoved?(frame.origin)
    }
}

private struct PopoverStrings {
    var translating: String
    var translatingClipboard: String
    var translatingScreenshot: String
    var errorTitle: String
    var translationFailed: String
    var showOriginal: String
    var showTranslation: String
    var cancel: String
    var copied: String
    var close: String
    var requestPermission: String

    static let current = Self(
        translating: "Translating...",
        translatingClipboard: "Translating clipboard text.",
        translatingScreenshot: "Capturing and translating the screenshot.",
        errorTitle: "Error",
        translationFailed: "Translation failed.",
        showOriginal: "Original",
        showTranslation: "Translation",
        cancel: "Cancel",
        copied: "Copied",
        close: "Close",
        requestPermission: "Request Permission"
    )
}

private final class TranslationPopoverContentView: NSView {
    private let payload: TranslationPreviewPayload
    private let arrowEdge: PopoverArrowEdge
    private let arrowX: CGFloat
    private let onClose: () -> Void
    private let onMouseEntered: () -> Void
    private let onMouseExited: () -> Void
    private let modelOptions: [TranslationModelOption]
    private let selectedModelOptionID: String?
    private let onPermissionRequested: (() -> Void)?
    private let onModelSelected: ((TranslationModelOption) -> Void)?
    private let onTargetLanguageSelected: ((String) -> Void)?
    private let strings = PopoverStrings.current

    private var visibleMode: String
    private var hoverTrackingArea: NSTrackingArea?
    private var countdownTimer: Timer?
    private var countdownEndDate: Date?
    private var countdownDuration: TimeInterval = 2
    private var copyResetWorkItem: DispatchWorkItem?
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyScrollView = NSScrollView()
    private let bodyTextView = NSTextView(frame: .zero)
    private let languagePill = NSView()
    private let languageIconLabel = NSTextField(labelWithString: "◎")
    private let languageTextLabel = NSTextField(labelWithString: "")
    private let languageButton = NSButton(title: "", target: nil, action: nil)
    private let modelLabel = NSTextField(labelWithString: "")
    private let countdownPill = NSView()
    private let countdownFill = NSView()
    private let countdownLabel = NSTextField(labelWithString: "")
    private let modelButton = NSButton(title: "", target: nil, action: nil)
    private let originalButton = NSButton(title: "", target: nil, action: nil)
    private let copyButton = NSButton(title: "", target: nil, action: nil)
    private let closeButton = NSButton(title: "", target: nil, action: nil)
    private let permissionButton = NSButton(title: "", target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()
    private var isHovering = false

    init(
        frame: CGRect,
        payload: TranslationPreviewPayload,
        arrowEdge: PopoverArrowEdge,
        arrowX: CGFloat,
        onClose: @escaping () -> Void,
        onMouseEntered: @escaping () -> Void,
        onMouseExited: @escaping () -> Void,
        modelOptions: [TranslationModelOption],
        selectedModelOptionID: String?,
        onPermissionRequested: (() -> Void)?,
        onModelSelected: ((TranslationModelOption) -> Void)?,
        onTargetLanguageSelected: ((String) -> Void)?
    ) {
        self.payload = payload
        self.arrowEdge = arrowEdge
        self.arrowX = arrowX
        self.onClose = onClose
        self.onMouseEntered = onMouseEntered
        self.onMouseExited = onMouseExited
        self.modelOptions = modelOptions
        self.selectedModelOptionID = selectedModelOptionID
        self.onPermissionRequested = onPermissionRequested
        self.onModelSelected = onModelSelected
        self.onTargetLanguageSelected = onTargetLanguageSelected
        visibleMode = payload.mode
        super.init(frame: frame)
        setup()
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bubble = bubbleRect
        let fillColor = NSColor.white.withAlphaComponent(0.94)
        let strokeColor = NSColor.black.withAlphaComponent(isHovering ? 0.42 : 0.34)
        let bubblePath = NSBezierPath(roundedRect: bubble, xRadius: 16, yRadius: 16)
        fillColor.setFill()
        bubblePath.fill()
        strokeColor.setStroke()
        bubblePath.lineWidth = 0.5
        bubblePath.stroke()
        let insetPath = NSBezierPath(roundedRect: bubble.insetBy(dx: 1, dy: 1), xRadius: 15, yRadius: 15)
        NSColor.white.withAlphaComponent(0.88).setStroke()
        insetPath.lineWidth = 1
        insetPath.stroke()

        guard arrowEdge != .none else {
            return
        }

        let midX = arrowX
        let arrowWidth: CGFloat = 28
        let arrowHeight: CGFloat = 18
        let path = NSBezierPath()
        switch arrowEdge {
        case .top:
            path.move(to: CGPoint(x: midX - arrowWidth / 2, y: bubble.maxY - 1))
            path.line(to: CGPoint(x: midX, y: bubble.maxY + arrowHeight - 1))
            path.line(to: CGPoint(x: midX + arrowWidth / 2, y: bubble.maxY - 1))
        case .bottom:
            path.move(to: CGPoint(x: midX - arrowWidth / 2, y: bubble.minY + 1))
            path.line(to: CGPoint(x: midX, y: bubble.minY - arrowHeight + 1))
            path.line(to: CGPoint(x: midX + arrowWidth / 2, y: bubble.minY + 1))
        case .none:
            return
        }
        path.close()
        fillColor.setFill()
        path.fill()
        strokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func layout() {
        super.layout()
        layoutContent()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        hoverTrackingArea = trackingArea
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setHovering(true)
        onMouseEntered()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovering(false)
        onMouseExited()
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard canDrag(from: location) else {
            super.mouseDown(with: event)
            return
        }
        window?.performDrag(with: event)
    }

    func startDismissCountdown(duration: TimeInterval) {
        guard visibleMode != "loading" else {
            hideCountdown()
            return
        }

        alphaValue = 1.0
        countdownDuration = duration
        countdownEndDate = Date().addingTimeInterval(duration)
        countdownTimer?.invalidate()
        countdownPill.isHidden = false
        countdownFill.isHidden = false
        countdownLabel.isHidden = false
        updateCountdown(remaining: duration, label: "\(String(format: "%.1f", duration))s")

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickCountdown()
            }
        }
        countdownTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func pauseDismissCountdown(duration: TimeInterval) {
        guard visibleMode != "loading" else {
            return
        }

        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownEndDate = nil
        countdownDuration = duration
        alphaValue = 1.0
        countdownPill.isHidden = false
        countdownFill.isHidden = false
        countdownLabel.isHidden = false
        updateCountdown(remaining: duration, label: "\(String(format: "%.1f", duration))s")
        animateCountdownPulse()
    }

    func stopDismissCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownEndDate = nil
        copyResetWorkItem?.cancel()
        copyResetWorkItem = nil
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.contentTintColor = nil
    }

    func dismissDuration(minimum: TimeInterval, maximum: TimeInterval) -> TimeInterval {
        guard visibleMode != "loading" else {
            return minimum
        }

        let font = bodyTextView.font ?? NSFont.preferredFont(forTextStyle: .body)
        let lineHeight = max(1, font.ascender - font.descender + font.leading)
        let bodyWidth = max(1, bodyScrollView.frame.width)
        let bodyHeight = ceil(
            (bodyTextView.string as NSString).boundingRect(
                with: CGSize(width: bodyWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            ).height
        )
        let bodyLineCount = max(1, Int(ceil(bodyHeight / lineHeight)))
        guard bodyLineCount >= 5 else {
            return minimum
        }

        let extraLines = min(6, bodyLineCount - 4)
        return min(maximum, minimum + TimeInterval(extraLines))
    }

    func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else {
            return
        }
        isHovering = hovering
        needsDisplay = true
        if hovering {
            animateHoverPulse()
        }
    }

    private var bubbleRect: CGRect {
        let horizontalInset: CGFloat = 24
        let arrowHeight: CGFloat = arrowEdge == .none ? 0 : 18
        switch arrowEdge {
        case .top:
            return CGRect(
                x: horizontalInset,
                y: 0,
                width: bounds.width - horizontalInset * 2,
                height: bounds.height - arrowHeight
            )
        case .bottom:
            return CGRect(
                x: horizontalInset,
                y: arrowHeight,
                width: bounds.width - horizontalInset * 2,
                height: bounds.height - arrowHeight
            )
        case .none:
            return bounds.insetBy(dx: horizontalInset, dy: 0)
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        for label in [titleLabel, modelLabel] {
            label.drawsBackground = false
            label.isBordered = false
            label.isEditable = false
            label.isSelectable = false
            addSubview(label)
        }

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .labelColor
        modelLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        modelLabel.textColor = .tertiaryLabelColor
        modelLabel.lineBreakMode = .byTruncatingMiddle

        languagePill.wantsLayer = true
        languagePill.layer?.backgroundColor = NSColor.white.cgColor
        languagePill.layer?.borderColor = NSColor.systemGray.withAlphaComponent(0.38).cgColor
        languagePill.layer?.borderWidth = 1
        languagePill.layer?.cornerRadius = 8
        languagePill.layer?.masksToBounds = true
        addSubview(languagePill)

        for label in [languageIconLabel, languageTextLabel] {
            label.drawsBackground = false
            label.isBordered = false
            label.isEditable = false
            label.isSelectable = false
            label.textColor = .labelColor
            languagePill.addSubview(label)
        }
        languageIconLabel.alignment = .center
        languageIconLabel.font = .systemFont(ofSize: 13, weight: .regular)
        languageTextLabel.alignment = .left
        languageTextLabel.font = .preferredFont(forTextStyle: .caption1)

        languageButton.target = self
        languageButton.action = #selector(showLanguageMenu)
        languageButton.bezelStyle = .regularSquare
        languageButton.isBordered = false
        languageButton.focusRingType = .none
        languageButton.title = ""
        languageButton.wantsLayer = true
        languageButton.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(languageButton)

        bodyScrollView.drawsBackground = false
        bodyScrollView.borderType = .noBorder
        bodyScrollView.hasHorizontalScroller = false
        bodyScrollView.hasVerticalScroller = true
        bodyScrollView.autohidesScrollers = true
        bodyScrollView.scrollerStyle = .overlay
        bodyScrollView.documentView = bodyTextView
        addSubview(bodyScrollView)

        bodyTextView.drawsBackground = false
        bodyTextView.backgroundColor = .clear
        bodyTextView.isEditable = false
        bodyTextView.isSelectable = false
        bodyTextView.font = .preferredFont(forTextStyle: .body)
        bodyTextView.textColor = .labelColor
        bodyTextView.textContainerInset = .zero
        bodyTextView.textContainer?.lineFragmentPadding = 0
        bodyTextView.textContainer?.widthTracksTextView = true
        bodyTextView.textContainer?.heightTracksTextView = false
        bodyTextView.isHorizontallyResizable = false
        bodyTextView.isVerticallyResizable = true
        bodyTextView.autoresizingMask = [.width]

        countdownPill.wantsLayer = true
        countdownPill.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.84).cgColor
        countdownPill.layer?.cornerRadius = 8
        countdownPill.layer?.masksToBounds = true
        countdownPill.isHidden = true
        addSubview(countdownPill)

        countdownFill.wantsLayer = true
        countdownFill.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
        countdownFill.layer?.cornerRadius = 8
        countdownFill.layer?.masksToBounds = true
        countdownPill.addSubview(countdownFill)

        countdownLabel.drawsBackground = false
        countdownLabel.isBordered = false
        countdownLabel.isEditable = false
        countdownLabel.isSelectable = false
        countdownLabel.alignment = .center
        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        countdownLabel.textColor = .secondaryLabelColor
        countdownPill.addSubview(countdownLabel)

        configureButton(modelButton, imageName: "cpu", action: #selector(showModelMenu))
        modelButton.toolTip = "Change model"
        configureButton(originalButton, imageName: "eye", action: #selector(toggleOriginal))
        configureButton(copyButton, imageName: "doc.on.doc", action: #selector(copyText))
        configureButton(closeButton, imageName: "xmark", action: #selector(close))
        configureButton(permissionButton, title: strings.requestPermission, action: #selector(requestPermission))
        permissionButton.toolTip = "Open Screen Recording settings"

        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = true
        progressIndicator.controlSize = .small
        progressIndicator.startAnimation(nil)
        addSubview(progressIndicator)
    }

    private func configureButton(
        _ button: NSButton,
        title: String? = nil,
        imageName: String? = nil,
        action: Selector
    ) {
        button.target = self
        button.action = action
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.controlSize = .regular
        button.font = .preferredFont(forTextStyle: .body)
        button.focusRingType = .none
        if let title {
            button.title = title
        }
        if let imageName {
            button.title = ""
            button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
            button.imagePosition = .imageOnly
        }
        if imageName != nil {
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.layer?.borderColor = NSColor.systemGray.withAlphaComponent(0.36).cgColor
            button.layer?.borderWidth = 1
            button.layer?.cornerRadius = 8
            button.layer?.masksToBounds = true
            button.contentTintColor = .labelColor
        }
        addSubview(button)
    }

    private func render() {
        languageTextLabel.stringValue = payload.targetLanguage
        modelLabel.stringValue = modelMetadataText()

        switch visibleMode {
        case "loading":
            hideCountdown()
            titleLabel.stringValue = strings.translating
            titleLabel.textColor = .controlAccentColor
            bodyTextView.string = payload.originalText == "[screen screenshot]"
                ? strings.translatingScreenshot
                : strings.translatingClipboard
        case "error":
            titleLabel.stringValue = strings.errorTitle
            titleLabel.textColor = .systemRed
            bodyTextView.string = payload.errorText ?? strings.translationFailed
        default:
            titleLabel.stringValue = ""
            bodyTextView.string = visibleMode == "original" ? payload.originalText : payload.translatedText
            originalButton.title = ""
            originalButton.image = NSImage(
                systemSymbolName: visibleMode == "original" ? "arrow.left.arrow.right" : "eye",
                accessibilityDescription: visibleMode == "original" ? strings.showTranslation : strings.showOriginal
            )
            originalButton.imagePosition = .imageOnly
        }

        needsLayout = true
        needsDisplay = true
    }

    private func modelMetadataText() -> String {
        let model = payload.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let costText = formatCostCredits(payload.costCredits) else {
            return model
        }
        if model.isEmpty {
            return costText
        }
        return "\(model) · \(costText)"
    }

    private func formatCostCredits(_ value: Double?) -> String? {
        guard let value else {
            return nil
        }
        let formatted = trimTrailingZeros(String(format: value < 0.0001 ? "%.8f" : "%.6f", value))
        return "Cost \(formatted.isEmpty ? "0" : formatted) credits"
    }

    private func trimTrailingZeros(_ value: String) -> String {
        var result = value
        while result.contains(".") && result.last == "0" {
            result.removeLast()
        }
        if result.last == "." {
            result.removeLast()
        }
        return result
    }

    private func layoutContent() {
        let bubble = bubbleRect
        let content = bubble.insetBy(dx: 20, dy: 14)

        switch visibleMode {
        case "loading":
            titleLabel.isHidden = false
            bodyScrollView.isHidden = false
            languagePill.isHidden = true
            languageButton.isHidden = true
            modelLabel.isHidden = modelLabel.stringValue.isEmpty
            progressIndicator.isHidden = false
            modelButton.isHidden = true
            originalButton.isHidden = true
            copyButton.isHidden = true
            closeButton.isHidden = false
            permissionButton.isHidden = true
            countdownPill.isHidden = true

            titleLabel.frame = CGRect(x: content.minX, y: content.maxY - 28, width: content.width - 72, height: 24)
            closeButton.frame = CGRect(x: content.maxX - 28, y: content.maxY - 28, width: 28, height: 28)
            closeButton.title = ""
            closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: strings.cancel)
            closeButton.imagePosition = .imageOnly
            layoutBodyScrollView(CGRect(x: content.minX, y: content.maxY - 80, width: content.width, height: 42))
            progressIndicator.frame = CGRect(x: content.minX, y: content.minY + 31, width: content.width, height: 8)
            modelLabel.frame = CGRect(x: content.minX, y: content.minY, width: content.width, height: 20)

        case "error":
            titleLabel.isHidden = false
            bodyScrollView.isHidden = false
            languagePill.isHidden = false
            languageButton.isHidden = false
            modelLabel.isHidden = true
            progressIndicator.isHidden = true
            modelButton.isHidden = modelOptions.count < 2
            originalButton.isHidden = true
            copyButton.isHidden = true
            closeButton.isHidden = false
            permissionButton.isHidden = !showsScreenRecordingPermissionAction
            countdownPill.isHidden = false

            layoutLanguagePill(CGRect(x: content.minX, y: content.maxY - 28, width: 128, height: 28))
            titleLabel.frame = CGRect(x: content.minX, y: content.maxY - 64, width: content.width, height: 24)
            closeButton.frame = CGRect(x: content.maxX - 28, y: content.maxY - 28, width: 28, height: 28)
            closeButton.title = ""
            closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
            closeButton.imagePosition = .imageOnly
            modelButton.frame = CGRect(x: closeButton.frame.minX - 34, y: content.maxY - 28, width: 28, height: 28)
            layoutCountdownPill(x: content.maxX - 40, y: content.minY + 4)
            layoutBodyScrollView(CGRect(x: content.minX, y: content.minY + 28, width: content.width, height: content.height - 90))
            if permissionButton.isHidden {
                modelLabel.frame = .zero
            } else {
                permissionButton.frame = CGRect(x: content.maxX - 140, y: content.minY - 3, width: 140, height: 28)
            }

        default:
            titleLabel.isHidden = true
            bodyScrollView.isHidden = false
            languagePill.isHidden = false
            languageButton.isHidden = false
            modelLabel.isHidden = true
            progressIndicator.isHidden = true
            modelButton.isHidden = modelOptions.count < 2
            originalButton.isHidden = false
            copyButton.isHidden = false
            closeButton.isHidden = false
            permissionButton.isHidden = true
            countdownPill.isHidden = false

            closeButton.title = ""
            closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: strings.close)
            closeButton.imagePosition = .imageOnly
            layoutLanguagePill(CGRect(x: content.minX, y: content.maxY - 28, width: 128, height: 28))
            closeButton.frame = CGRect(x: content.maxX - 28, y: content.maxY - 28, width: 28, height: 28)
            copyButton.frame = CGRect(x: closeButton.frame.minX - 34, y: content.maxY - 28, width: 28, height: 28)
            originalButton.frame = CGRect(x: copyButton.frame.minX - 34, y: content.maxY - 28, width: 28, height: 28)
            modelButton.frame = CGRect(x: originalButton.frame.minX - 34, y: content.maxY - 28, width: 28, height: 28)
            layoutCountdownPill(x: content.maxX - 40, y: content.minY + 4)
            layoutBodyScrollView(CGRect(x: content.minX, y: content.minY + 28, width: content.width, height: content.height - 60))
            modelLabel.frame = .zero
        }
    }

    private func layoutBodyScrollView(_ frame: CGRect) {
        bodyScrollView.frame = frame
        let documentWidth = max(1, frame.width - bodyScrollView.contentInsets.left - bodyScrollView.contentInsets.right)
        let documentHeight = max(frame.height, bodyTextHeight(width: documentWidth))
        bodyTextView.minSize = CGSize(width: documentWidth, height: 0)
        bodyTextView.maxSize = CGSize(width: documentWidth, height: .greatestFiniteMagnitude)
        bodyTextView.textContainer?.containerSize = CGSize(width: documentWidth, height: .greatestFiniteMagnitude)
        bodyTextView.frame = CGRect(x: 0, y: 0, width: documentWidth, height: documentHeight)
        bodyScrollView.contentView.scroll(to: .zero)
        bodyScrollView.reflectScrolledClipView(bodyScrollView.contentView)
    }

    private func bodyTextHeight(width: CGFloat) -> CGFloat {
        let font = bodyTextView.font ?? NSFont.preferredFont(forTextStyle: .body)
        return ceil(
            (bodyTextView.string as NSString).boundingRect(
                with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            ).height
        ) + 4
    }

    private func layoutLanguagePill(_ frame: CGRect) {
        languagePill.frame = frame
        languageIconLabel.frame = CGRect(x: 12, y: 5, width: 16, height: 18)
        languageTextLabel.frame = CGRect(x: 36, y: 4, width: max(1, frame.width - 48), height: 20)
        languageButton.frame = frame
    }

    private func layoutCountdownPill(x: CGFloat, y: CGFloat) {
        countdownPill.frame = CGRect(x: x, y: y, width: 40, height: 20)
        countdownFill.frame = countdownPill.bounds
        countdownLabel.frame = countdownPill.bounds
    }

    private func tickCountdown() {
        guard let countdownEndDate else {
            return
        }

        let remaining = max(0, countdownEndDate.timeIntervalSinceNow)
        updateCountdown(remaining: remaining, label: "\(String(format: "%.1f", remaining))s")
        if remaining <= 0 {
            countdownTimer?.invalidate()
            countdownTimer = nil
        }
    }

    private func updateCountdown(remaining: TimeInterval, label: String) {
        let progress = countdownDuration > 0 ? max(0, min(1, remaining / countdownDuration)) : 0
        countdownLabel.stringValue = label
        alphaValue = 0.62 + 0.38 * CGFloat(progress)
        var fillFrame = countdownPill.bounds
        fillFrame.size.width = max(0, countdownPill.bounds.width * CGFloat(progress))
        countdownFill.frame = fillFrame
    }

    private func hideCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        alphaValue = 1.0
        countdownPill.isHidden = true
        countdownFill.isHidden = true
        countdownLabel.isHidden = true
    }

    private func canDrag(from location: CGPoint) -> Bool {
        let controlViews: [NSView] = [
            originalButton,
            copyButton,
            modelButton,
            languageButton,
            closeButton,
            permissionButton,
            countdownPill,
        ]

        return controlViews.allSatisfy { view in
            view.isHidden || !view.frame.contains(location)
        }
    }

    private func animateHoverPulse() {
        guard let layer else {
            return
        }

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.86
        animation.toValue = 1.0
        animation.duration = 0.16
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "hoverPulse")
    }

    private func animateCountdownPulse() {
        guard let layer = countdownPill.layer else {
            return
        }

        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 1.0
        animation.toValue = 1.08
        animation.duration = 0.16
        animation.autoreverses = true
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "countdownPulse")
    }

    @objc private func toggleOriginal() {
        visibleMode = visibleMode == "original" ? "translated" : "original"
        render()
    }

    @objc private func copyText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(visibleMode == "original" ? payload.originalText : payload.translatedText, forType: .string)
        showCopiedState()
    }

    @objc private func showModelMenu() {
        guard modelOptions.count >= 2 else {
            return
        }

        let menu = NSMenu()
        for option in modelOptions {
            let item = NSMenuItem(title: option.title, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.id
            item.state = option.id == selectedModelOptionID ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: CGPoint(x: modelButton.frame.minX, y: modelButton.frame.maxY + 4), in: self)
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              id != selectedModelOptionID,
              let option = modelOptions.first(where: { $0.id == id }) else {
            return
        }
        onModelSelected?(option)
    }

    @objc private func showLanguageMenu() {
        guard visibleMode != "loading" else {
            return
        }

        let menu = NSMenu()
        for language in TranslationLanguage.targetLanguageNames {
            let item = NSMenuItem(title: language, action: #selector(selectTargetLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language
            item.state = language == payload.targetLanguage ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: CGPoint(x: languageButton.frame.minX, y: languageButton.frame.maxY + 4), in: self)
    }

    @objc private func selectTargetLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? String,
              language != payload.targetLanguage else {
            return
        }
        onTargetLanguageSelected?(language)
    }

    @objc private func close() {
        onClose()
    }

    @objc private func requestPermission() {
        onPermissionRequested?()
        onClose()
    }

    private var showsScreenRecordingPermissionAction: Bool {
        guard visibleMode == "error",
              onPermissionRequested != nil else {
            return false
        }
        if payload.permissionAction == "screenRecording" {
            return true
        }
        return payload.errorText?.lowercased().contains("screen recording permission") ?? false
    }

    private func footerLeadingWidth(content: CGRect) -> CGFloat {
        if !permissionButton.isHidden {
            return max(72, permissionButton.frame.minX - content.minX - 8)
        }
        return modelLabel.isHidden ? content.width - 40 : max(72, modelLabel.frame.minX - content.minX - 8)
    }

    private func showCopiedState() {
        copyResetWorkItem?.cancel()
        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: strings.copied)
        copyButton.contentTintColor = .systemGreen

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
                self?.copyButton.contentTintColor = nil
            }
        }
        copyResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

}
