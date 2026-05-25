import AppKit

@MainActor
final class RequestLogWindowController: NSWindowController {
    private let logStore: RequestLogStore
    private let summaryField = NSTextField(labelWithString: "")
    private let textView = NSTextView()

    init(logStore: RequestLogStore) {
        self.logStore = logStore

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CopyTranslator Request Logs"
        window.center()
        super.init(window: window)
        window.contentView = makeContentView()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        reload()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    func reload() {
        let summary = logStore.summary
        summaryField.stringValue = """
        Requests: \(summary.requestCount)   Duplicate suspects: \(summary.duplicateSuspectCount)   Input tokens: \(summary.promptTokens)   Output tokens: \(summary.completionTokens)   Total tokens: \(summary.totalTokens)
        """

        guard !logStore.entries.isEmpty else {
            textView.string = "No translation requests have been logged yet."
            return
        }

        textView.string = logStore.entries.reversed().map(format).joined(separator: "\n\n")
    }

    private func makeContentView() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 10

        let title = NSTextField(labelWithString: "Request Logs")
        title.font = .boldSystemFont(ofSize: 17)
        headerRow.addArrangedSubview(title)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerRow.addArrangedSubview(spacer)

        headerRow.addArrangedSubview(button(title: "Refresh", action: #selector(refreshClicked)))
        headerRow.addArrangedSubview(button(title: "Clear", action: #selector(clearClicked)))
        root.addArrangedSubview(headerRow)

        summaryField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        root.addArrangedSubview(summaryField)

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 700).isActive = true
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 390).isActive = true
        root.addArrangedSubview(scrollView)

        return root
    }

    private func button(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        return button
    }

    private func format(_ entry: RequestLogEntry) -> String {
        let duplicate = entry.isDuplicateSuspect ? "yes" : "no"
        let image = entry.imageInfo ?? "none"
        return """
        [\(Self.timeFormatter.string(from: entry.timestamp))] \(entry.source) | \(entry.providerTitle) | \(entry.model)
        tokens input/output/total: \(entry.promptTokens)/\(entry.completionTokens)/\(entry.totalTokens) (\(entry.usageSource)) | duplicate suspect: \(duplicate) | image: \(image)
        input: \(entry.inputPreview)
        output: \(entry.outputPreview)
        """
    }

    @objc private func refreshClicked() {
        reload()
    }

    @objc private func clearClicked() {
        logStore.clear()
        reload()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
