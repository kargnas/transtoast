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

    private var panel: TranslationPopoverPanel?
    private var dismissWorkItem: DispatchWorkItem?

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
        panel.contentView = TranslationPopoverContentView(
            frame: CGRect(origin: .zero, size: size),
            payload: payload,
            arrowEdge: placement.arrowEdge,
            arrowX: placement.arrowX,
            onClose: { [weak self] in
                self?.close()
            }
        )

        self.panel = panel
        panel.orderFrontRegardless()
        scheduleDismissIfNeeded(mode: payload.mode, duration: settings.toastDuration)
    }

    func close() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func scheduleDismissIfNeeded(mode: String, duration: TimeInterval) {
        guard mode != "loading" else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.close()
            }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, duration), execute: workItem)
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

    private var visibleMode: String
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    private let originalButton = NSButton(title: "", target: nil, action: nil)
    private let copyButton = NSButton(title: "", target: nil, action: nil)
    private let moreButton = NSButton(title: "", target: nil, action: nil)
    private let closeButton = NSButton(title: "", target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()

    init(
        frame: CGRect,
        payload: TranslationPreviewPayload,
        arrowEdge: PopoverArrowEdge,
        arrowX: CGFloat,
        onClose: @escaping () -> Void
    ) {
        self.payload = payload
        self.arrowEdge = arrowEdge
        self.arrowX = arrowX
        self.onClose = onClose
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
        let strokeColor = NSColor.separatorColor.withAlphaComponent(0.9)
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

            titleLabel.frame = CGRect(x: content.minX, y: content.maxY - 28, width: content.width - 72, height: 24)
            closeButton.frame = CGRect(x: content.maxX - 58, y: content.maxY - 30, width: 58, height: 28)
            closeButton.title = "취소"
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

            titleLabel.frame = CGRect(x: content.minX, y: content.maxY - 28, width: content.width - 40, height: 24)
            closeButton.frame = CGRect(x: content.maxX - 32, y: content.maxY - 31, width: 32, height: 30)
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

            bodyLabel.frame = CGRect(x: content.minX, y: content.minY + 50, width: content.width, height: content.height - 50)
            languageLabel.frame = CGRect(x: content.minX, y: content.minY + 5, width: 105, height: 22)
            moreButton.frame = CGRect(x: content.maxX - 38, y: content.minY, width: 38, height: 30)
            copyButton.frame = CGRect(x: moreButton.frame.minX - 44, y: content.minY, width: 38, height: 30)
            originalButton.frame = CGRect(x: copyButton.frame.minX - 92, y: content.minY, width: 84, height: 30)
        }
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
