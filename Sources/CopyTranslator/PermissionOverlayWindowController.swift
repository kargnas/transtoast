import AppKit

@MainActor
final class PermissionOverlayWindowController: NSWindowController {
    private let appURL: URL
    private let openInputMonitoring: () -> Void
    private let openAccessibility: () -> Void
    private let openScreenRecording: () -> Void
    private let requestKeyboardPrompt: () -> Void

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
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = "CopyTranslator Permission Helper"
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()

        super.init(window: window)
        window.contentView = makeContentView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    private func makeContentView() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)

        let title = NSTextField(labelWithString: "Drop CopyTranslator into Privacy settings")
        title.font = .boldSystemFont(ofSize: 18)
        root.addArrangedSubview(title)

        let description = NSTextField(wrappingLabelWithString: "Open the needed permission pane, then drag the app icon below into the app list. Turn the toggle on if macOS adds it disabled, then relaunch CopyTranslator.")
        description.textColor = .secondaryLabelColor
        description.maximumNumberOfLines = 3
        root.addArrangedSubview(description)

        let contentRow = NSStackView()
        contentRow.orientation = .horizontal
        contentRow.alignment = .top
        contentRow.spacing = 22
        contentRow.addArrangedSubview(appCard())
        contentRow.addArrangedSubview(actionsCard())
        root.addArrangedSubview(contentRow)

        let pathLabel = NSTextField(wrappingLabelWithString: appURL.path)
        pathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.maximumNumberOfLines = 2
        pathLabel.widthAnchor.constraint(equalToConstant: 620).isActive = true
        root.addArrangedSubview(pathLabel)

        return root
    }

    private func appCard() -> NSView {
        let icon = DraggableAppIconView(appURL: appURL)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 220).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 240).isActive = true
        return icon
    }

    private func actionsCard() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.widthAnchor.constraint(equalToConstant: 380).isActive = true

        stack.addArrangedSubview(sectionLabel("Open a permission pane"))
        stack.addArrangedSubview(button("Input Monitoring", action: #selector(openInputMonitoringClicked)))
        stack.addArrangedSubview(button("Accessibility", action: #selector(openAccessibilityClicked)))
        stack.addArrangedSubview(button("Screen Recording", action: #selector(openScreenRecordingClicked)))

        let spacer = NSView()
        spacer.heightAnchor.constraint(equalToConstant: 4).isActive = true
        stack.addArrangedSubview(spacer)

        stack.addArrangedSubview(sectionLabel("Prompt again"))
        stack.addArrangedSubview(button("Request Keyboard Prompt", action: #selector(requestKeyboardPromptClicked)))

        let hint = NSTextField(wrappingLabelWithString: "For Cmd+C twice, add CopyTranslator to Input Monitoring or Accessibility. For screenshots, add it to Screen Recording.")
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 4
        hint.widthAnchor.constraint(equalToConstant: 360).isActive = true
        stack.addArrangedSubview(hint)

        return stack
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return button
    }

    @objc private func openInputMonitoringClicked() {
        openInputMonitoring()
    }

    @objc private func openAccessibilityClicked() {
        openAccessibility()
    }

    @objc private func openScreenRecordingClicked() {
        openScreenRecording()
    }

    @objc private func requestKeyboardPromptClicked() {
        requestKeyboardPrompt()
    }
}

@MainActor
private final class DraggableAppIconView: NSView, NSDraggingSource {
    private let appURL: URL
    private let icon: NSImage

    init(appURL: URL) {
        self.appURL = appURL
        icon = NSWorkspace.shared.icon(forFile: appURL.path)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        setAccessibilityLabel("Draggable CopyTranslator app icon")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let iconRect = NSRect(x: bounds.midX - 44, y: bounds.maxY - 116, width: 88, height: 88)
        icon.draw(in: iconRect)

        let title = "CopyTranslator.app" as NSString
        title.draw(
            in: NSRect(x: 18, y: 72, width: bounds.width - 36, height: 24),
            withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 14),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: centeredParagraphStyle(),
            ]
        )

        let subtitle = "Drag this into the Privacy app list" as NSString
        subtitle.draw(
            in: NSRect(x: 18, y: 42, width: bounds.width - 36, height: 36),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: centeredParagraphStyle(),
            ]
        )
    }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        item.setDraggingFrame(bounds, contents: draggingImage())
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    private func draggingImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 96, height: 110))
        image.lockFocus()
        icon.draw(in: NSRect(x: 4, y: 18, width: 88, height: 88))
        ("CopyTranslator" as NSString).draw(
            in: NSRect(x: 0, y: 0, width: 96, height: 18),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: centeredParagraphStyle(),
            ]
        )
        image.unlockFocus()
        return image
    }

    private func centeredParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }
}
