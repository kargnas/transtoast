import AppKit
import CopyTranslatorCore

@MainActor
final class TranslationPopoverController {
    private let margin: CGFloat = 24
    private let caretGap: CGFloat = 8
    private let windowWidth: CGFloat = 356
    private let compactHeight: CGFloat = 150
    private let tallHeight: CGFloat = 176
    private let maxHeight: CGFloat = 560
    private let automaticDismissDuration: TimeInterval = 2

    private var panel: TranslationPopoverPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private var clickMonitorTokens: [Any] = []
    private var currentMode: String?

    func show(
        payload: TranslationPreviewPayload,
        settings: TranslatorSettings,
        caretBounds: CGRect?
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
        let contentView = TranslationPopoverContentView(
            frame: CGRect(origin: .zero, size: size),
            payload: payload,
            arrowEdge: placement.arrowEdge,
            arrowX: placement.arrowX,
            onClose: { [weak self] in
                self?.close()
            },
            onMouseEntered: { [weak self] in
                self?.pauseDismissTimer()
            },
            onMouseExited: { [weak self] in
                self?.resumeDismissTimer()
            }
        )
        panel.contentView = contentView

        self.panel = panel
        currentMode = payload.mode
        installClickMonitors(for: panel)
        panel.orderFrontRegardless()
        scheduleDismissIfNeeded(mode: payload.mode)
    }

    func close() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        removeClickMonitors()
        contentView?.stopDismissCountdown()
        panel?.orderOut(nil)
        panel = nil
        currentMode = nil
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
        DispatchQueue.main.asyncAfter(deadline: .now() + automaticDismissDuration, execute: workItem)
        contentView?.startDismissCountdown(duration: automaticDismissDuration)
    }

    private func pauseDismissTimer() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        contentView?.pauseDismissCountdown(duration: automaticDismissDuration)
    }

    private func resumeDismissTimer() {
        guard let currentMode else {
            return
        }
        scheduleDismissIfNeeded(mode: currentMode)
    }

    private func installClickMonitors(for panel: NSPanel) {
        removeClickMonitors()

        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self, weak panel] event in
            guard let self,
                  let panel,
                  event.window !== panel else {
                return event
            }
            self.close()
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
                self.close()
            }
        }) {
            clickMonitorTokens.append(globalMonitor)
        }
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

    private func size(for payload: TranslationPreviewPayload) -> CGSize {
        let height: CGFloat
        switch payload.mode {
        case "loading":
            height = tallHeight
        case "error":
            height = textPanelHeight(for: payload.errorText ?? "번역에 실패했습니다.", minimum: tallHeight)
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
        let bottomControlsHeight: CGFloat = 50
        let verticalPadding: CGFloat = 32
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
        }
    }
}

final class TranslationPopoverPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TranslationPopoverContentView: NSView {
    private let payload: TranslationPreviewPayload
    private let arrowEdge: PopoverArrowEdge
    private let arrowX: CGFloat
    private let onClose: () -> Void
    private let onMouseEntered: () -> Void
    private let onMouseExited: () -> Void

    private var visibleMode: String
    private var hoverTrackingArea: NSTrackingArea?
    private var countdownTimer: Timer?
    private var countdownEndDate: Date?
    private var countdownDuration: TimeInterval = 2
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    private let countdownPill = NSView()
    private let countdownFill = NSView()
    private let countdownLabel = NSTextField(labelWithString: "")
    private let originalButton = NSButton(title: "", target: nil, action: nil)
    private let copyButton = NSButton(title: "", target: nil, action: nil)
    private let moreButton = NSButton(title: "", target: nil, action: nil)
    private let closeButton = NSButton(title: "", target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()
    private var isHovering = false

    init(
        frame: CGRect,
        payload: TranslationPreviewPayload,
        arrowEdge: PopoverArrowEdge,
        arrowX: CGFloat,
        onClose: @escaping () -> Void,
        onMouseEntered: @escaping () -> Void,
        onMouseExited: @escaping () -> Void
    ) {
        self.payload = payload
        self.arrowEdge = arrowEdge
        self.arrowX = arrowX
        self.onClose = onClose
        self.onMouseEntered = onMouseEntered
        self.onMouseExited = onMouseExited
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
        let fillColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94)
        let strokeColor = isHovering
            ? NSColor.controlAccentColor.withAlphaComponent(0.45)
            : NSColor.separatorColor.withAlphaComponent(0.9)
        let bubblePath = NSBezierPath(roundedRect: bubble, xRadius: 16, yRadius: 16)
        fillColor.setFill()
        bubblePath.fill()
        strokeColor.setStroke()
        bubblePath.lineWidth = 1
        bubblePath.stroke()

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
        isHovering = true
        needsDisplay = true
        animateHoverPulse()
        onMouseEntered()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
        needsDisplay = true
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

        for label in [titleLabel, bodyLabel, languageLabel] {
            label.drawsBackground = false
            label.isBordered = false
            label.isEditable = false
            label.isSelectable = false
            addSubview(label)
        }

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .labelColor
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.textColor = .labelColor
        bodyLabel.maximumNumberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        languageLabel.font = .preferredFont(forTextStyle: .caption1)
        languageLabel.textColor = .secondaryLabelColor

        countdownPill.wantsLayer = true
        countdownPill.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.82).cgColor
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
        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        countdownLabel.textColor = .secondaryLabelColor
        countdownPill.addSubview(countdownLabel)

        configureButton(originalButton, title: "원본 보기", action: #selector(toggleOriginal))
        configureButton(copyButton, imageName: "doc.on.doc", action: #selector(copyText))
        configureButton(moreButton, title: "...", action: #selector(noop))
        configureButton(closeButton, imageName: "xmark", action: #selector(close))

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
        button.bezelStyle = .rounded
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
        addSubview(button)
    }

    private func render() {
        languageLabel.stringValue = "⌘  \(shortLanguage(payload.sourceLanguage)) → \(shortLanguage(payload.targetLanguage))"

        switch visibleMode {
        case "loading":
            hideCountdown()
            titleLabel.stringValue = "번역 중..."
            titleLabel.textColor = .controlAccentColor
            bodyLabel.stringValue = payload.originalText == "[screen screenshot]"
                ? "스크린샷을 캡처하고 번역하고 있어요."
                : "클립보드의 텍스트를 번역하고 있어요."
        case "error":
            titleLabel.stringValue = "오류"
            titleLabel.textColor = .systemRed
            bodyLabel.stringValue = payload.errorText ?? "번역에 실패했습니다."
        default:
            titleLabel.stringValue = ""
            bodyLabel.stringValue = visibleMode == "original" ? payload.originalText : payload.translatedText
            originalButton.title = visibleMode == "original" ? "번역 보기" : "원본 보기"
        }

        needsLayout = true
        needsDisplay = true
    }

    private func layoutContent() {
        let bubble = bubbleRect
        let content = bubble.insetBy(dx: 22, dy: 16)

        switch visibleMode {
        case "loading":
            titleLabel.isHidden = false
            bodyLabel.isHidden = false
            languageLabel.isHidden = false
            progressIndicator.isHidden = false
            originalButton.isHidden = true
            copyButton.isHidden = true
            moreButton.isHidden = true
            closeButton.isHidden = false
            countdownPill.isHidden = true

            titleLabel.frame = CGRect(x: content.minX, y: content.maxY - 28, width: content.width - 72, height: 24)
            closeButton.frame = CGRect(x: content.maxX - 58, y: content.maxY - 30, width: 58, height: 28)
            closeButton.title = "취소"
            closeButton.image = nil
            closeButton.imagePosition = .noImage
            bodyLabel.frame = CGRect(x: content.minX, y: content.maxY - 80, width: content.width, height: 42)
            progressIndicator.frame = CGRect(x: content.minX, y: content.minY + 31, width: content.width, height: 8)
            languageLabel.frame = CGRect(x: content.minX, y: content.minY, width: content.width, height: 20)

        case "error":
            titleLabel.isHidden = false
            bodyLabel.isHidden = false
            languageLabel.isHidden = false
            progressIndicator.isHidden = true
            originalButton.isHidden = true
            copyButton.isHidden = true
            moreButton.isHidden = true
            closeButton.isHidden = false
            countdownPill.isHidden = false

            titleLabel.frame = CGRect(x: content.minX, y: content.maxY - 28, width: content.width - 40, height: 24)
            closeButton.frame = CGRect(x: content.maxX - 32, y: content.maxY - 31, width: 32, height: 30)
            closeButton.title = ""
            closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
            closeButton.imagePosition = .imageOnly
            layoutCountdownPill(x: closeButton.frame.minX - 48, y: content.maxY - 27)
            bodyLabel.frame = CGRect(x: content.minX, y: content.minY + 35, width: content.width, height: content.height - 68)
            languageLabel.frame = CGRect(x: content.minX, y: content.minY, width: content.width - 40, height: 20)

        default:
            titleLabel.isHidden = true
            bodyLabel.isHidden = false
            languageLabel.isHidden = false
            progressIndicator.isHidden = true
            originalButton.isHidden = false
            copyButton.isHidden = false
            moreButton.isHidden = false
            closeButton.isHidden = true
            countdownPill.isHidden = false

            layoutCountdownPill(x: content.maxX - 42, y: content.maxY - 21)
            bodyLabel.frame = CGRect(x: content.minX, y: content.minY + 50, width: content.width - 48, height: content.height - 50)
            languageLabel.frame = CGRect(x: content.minX, y: content.minY + 5, width: 105, height: 22)
            moreButton.frame = CGRect(x: content.maxX - 38, y: content.minY, width: 38, height: 30)
            copyButton.frame = CGRect(x: moreButton.frame.minX - 44, y: content.minY, width: 38, height: 30)
            originalButton.frame = CGRect(x: copyButton.frame.minX - 92, y: content.minY, width: 84, height: 30)
        }
    }

    private func layoutCountdownPill(x: CGFloat, y: CGFloat) {
        countdownPill.frame = CGRect(x: x, y: y, width: 42, height: 18)
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
        var fillFrame = countdownPill.bounds
        fillFrame.size.width = max(0, countdownPill.bounds.width * CGFloat(progress))
        countdownFill.frame = fillFrame
    }

    private func hideCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownPill.isHidden = true
        countdownFill.isHidden = true
        countdownLabel.isHidden = true
    }

    private func canDrag(from location: CGPoint) -> Bool {
        let controlViews: [NSView] = [
            originalButton,
            copyButton,
            moreButton,
            closeButton,
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
    }

    @objc private func close() {
        onClose()
    }

    @objc private func noop() {}

    private func shortLanguage(_ language: String) -> String {
        switch language {
        case "English": "영어"
        case "Korean": "한국어"
        case "Simplified Chinese": "중국어"
        case "Japanese": "일본어"
        case "Spanish": "스페인어"
        case "German": "독일어"
        case "French": "프랑스어"
        case "Indonesian": "인도네시아어"
        case "Arabic": "아랍어"
        case "Auto": "자동"
        default: language
        }
    }
}
