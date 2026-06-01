import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class PermissionOverlayWindowController: NSWindowController {
    private enum Layout {
        static let groupSpacing: CGFloat = 16
        static let rowSpacing: CGFloat = 8
        static let groupInset: CGFloat = 12
        static let windowInset: CGFloat = 20
        static let labelColumnWidth: CGFloat = 150
        static let actionButtonMinWidth: CGFloat = 220
        static let appCardWidth: CGFloat = 220
        static let appCardHeight: CGFloat = 240
        static let formMaxWidth: CGFloat = 620
    }

    private let appURL: URL
    private let openInputMonitoring: () -> Void
    private let openAccessibility: () -> Void
    private let openScreenRecording: () -> Void
    private let requestKeyboardPrompt: () -> Void
    private let keyboardStatusField = NSTextField(wrappingLabelWithString: "")
    private let screenStatusField = NSTextField(wrappingLabelWithString: "")

    init(
        appURL: URL,
        openInputMonitoring: @escaping () -> Void,
        openAccessibility: @escaping () -> Void,
        openScreenRecording: @escaping () -> Void,
        requestKeyboardPrompt: @escaping () -> Void
    ) {
        self.appURL = appURL
        self.openInputMonitoring = openInputMonitoring
        self.openAccessibility = openAccessibility
        self.openScreenRecording = openScreenRecording
        self.requestKeyboardPrompt = requestKeyboardPrompt

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 360),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = "CopyTranslator Permission Helper"
        window.minSize = NSSize(width: 620, height: 340)
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()

        super.init(window: window)
        window.contentView = makeContentView()
        refreshStatus()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        refreshStatus()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    private func makeContentView() -> NSView {
        let contentView = NSView()

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .width
        root.distribution = .fill
        root.spacing = Layout.groupSpacing
        contentView.addSubview(root)

        let preferredWidth = root.widthAnchor.constraint(equalToConstant: Layout.formMaxWidth)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            root.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.windowInset),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Layout.windowInset),
            root.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: Layout.windowInset),
            root.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -Layout.windowInset),
            preferredWidth,
        ])

        let description = NSTextField(wrappingLabelWithString: "Grant keyboard permissions for Cmd+C detection and Screen Recording for screenshot translation. Drag the app card into a Privacy app list if macOS does not add it from a prompt.")
        description.translatesAutoresizingMaskIntoConstraints = false
        description.font = .preferredFont(forTextStyle: .body)
        description.textColor = .secondaryLabelColor
        description.maximumNumberOfLines = 3
        root.addArrangedSubview(description)

        let rightColumn = NSStackView(views: [statusBox(), actionsBox()])
        rightColumn.translatesAutoresizingMaskIntoConstraints = false
        rightColumn.orientation = .vertical
        rightColumn.alignment = .width
        rightColumn.distribution = .fill
        rightColumn.spacing = Layout.groupSpacing
        rightColumn.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let contentRow = NSStackView(views: [appCard(), rightColumn])
        contentRow.translatesAutoresizingMaskIntoConstraints = false
        contentRow.orientation = .horizontal
        contentRow.alignment = .top
        contentRow.distribution = .fill
        contentRow.spacing = Layout.groupSpacing
        root.addArrangedSubview(contentRow)

        return contentView
    }

    private func refreshStatus() {
        let keyboardReady = CGPreflightListenEventAccess() || AXIsProcessTrusted()
        let screenReady = CGPreflightScreenCaptureAccess()
        keyboardStatusField.stringValue = keyboardReady
            ? "Ready"
            : "Not granted"
        screenStatusField.stringValue = screenReady
            ? "Ready"
            : "Not granted"
        keyboardStatusField.textColor = keyboardReady ? .labelColor : .secondaryLabelColor
        screenStatusField.textColor = screenReady ? .labelColor : .secondaryLabelColor
    }

    private func appCard() -> NSView {
        let icon = DraggableAppIconView(appURL: appURL)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: Layout.appCardWidth).isActive = true
        icon.heightAnchor.constraint(equalToConstant: Layout.appCardHeight).isActive = true
        icon.setContentHuggingPriority(.required, for: .horizontal)
        return icon
    }

    private func statusBox() -> NSBox {
        groupBox(
            title: "Current Status",
            views: [
                statusRow(label: "Keyboard", control: keyboardStatusField),
                statusRow(label: "Screen Recording", control: screenStatusField),
            ]
        )
    }

    private func actionsBox() -> NSBox {
        groupBox(
            title: "Actions",
            views: [
                button("Open Input Monitoring Settings", action: #selector(openInputMonitoringClicked)),
                button("Open Accessibility Settings", action: #selector(openAccessibilityClicked)),
                button("Open Screen Recording Settings", action: #selector(openScreenRecordingClicked)),
                button("Request Keyboard Prompt", action: #selector(requestKeyboardPromptClicked)),
            ]
        )
    }

    private func groupBox(title: String, views: [NSView]) -> NSBox {
        let box = NSBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.title = title
        box.titlePosition = .atTop
        box.boxType = .primary
        box.contentViewMargins = NSSize(width: Layout.groupInset, height: Layout.groupInset)
        box.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: views)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = Layout.rowSpacing

        if let contentView = box.contentView {
            contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                stack.topAnchor.constraint(equalTo: contentView.topAnchor),
                stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }

        return box
    }

    private func statusRow(label: String, control: NSTextField) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.alignment = .right
        labelView.font = .preferredFont(forTextStyle: .body)
        labelView.widthAnchor.constraint(equalToConstant: Layout.labelColumnWidth).isActive = true
        labelView.setContentHuggingPriority(.required, for: .horizontal)

        control.translatesAutoresizingMaskIntoConstraints = false
        control.font = .preferredFont(forTextStyle: .body)
        control.lineBreakMode = .byWordWrapping
        control.maximumNumberOfLines = 2
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [labelView, control])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.distribution = .fill
        stack.spacing = Layout.rowSpacing
        return stack
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.font = .preferredFont(forTextStyle: .body)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.actionButtonMinWidth).isActive = true
        return button
    }

    @objc private func openInputMonitoringClicked() {
        openInputMonitoring()
        refreshStatus()
    }

    @objc private func openAccessibilityClicked() {
        openAccessibility()
        refreshStatus()
    }

    @objc private func openScreenRecordingClicked() {
        openScreenRecording()
        refreshStatus()
    }

    @objc private func requestKeyboardPromptClicked() {
        requestKeyboardPrompt()
        refreshStatus()
    }
}

@MainActor
private final class DraggableAppIconView: NSView, NSDraggingSource {
    private enum Layout {
        static let spacing: CGFloat = 8
        static let inset: CGFloat = 16
        static let iconSize: CGFloat = 88
        static let cornerRadius: CGFloat = 8
    }

    private let appURL: URL
    private let icon: NSImage

    init(appURL: URL) {
        self.appURL = appURL
        icon = NSWorkspace.shared.icon(forFile: appURL.path)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Layout.cornerRadius
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        setAccessibilityLabel("Draggable CopyTranslator app icon")
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        item.setDraggingFrame(bounds, contents: draggingImage())
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    private func buildContent() {
        let iconView = NSImageView(image: icon)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.widthAnchor.constraint(equalToConstant: Layout.iconSize).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: Layout.iconSize).isActive = true

        let title = NSTextField(labelWithString: "CopyTranslator.app")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.alignment = .center
        title.font = .preferredFont(forTextStyle: .headline)

        let subtitle = NSTextField(wrappingLabelWithString: "Drag this into the Privacy app list")
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.alignment = .center
        subtitle.font = .preferredFont(forTextStyle: .body)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2

        let stack = NSStackView(views: [iconView, title, subtitle])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.distribution = .gravityAreas
        stack.spacing = Layout.spacing
        stack.edgeInsets = NSEdgeInsets(
            top: Layout.inset,
            left: Layout.inset,
            bottom: Layout.inset,
            right: Layout.inset
        )
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func draggingImage() -> NSImage {
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else {
            return icon
        }
        cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
}
