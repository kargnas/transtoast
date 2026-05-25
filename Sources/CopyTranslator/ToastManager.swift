import AppKit
import CopyTranslatorCore
import Darwin

@MainActor
final class ToastManager {
    private struct ToastEntry {
        let id: UUID
        let view: NSView
        let height: CGFloat
    }

    private var entries: [ToastEntry] = []
    private var window: NSWindow?
    private let stackView = NSStackView()
    private let width: CGFloat = 420
    private let minHeight: CGFloat = 52
    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 12
    private let contentSpacing: CGFloat = 6
    private let margin: CGFloat = 24
    private let gap: CGFloat = 12

    func show(title: String, message: String, settings: TranslatorSettings) {
        print("TOAST [\(title)] \(message)")
        fflush(stdout)
        let entry = makeEntry(title: title, message: message)
        entries.append(entry)
        stackView.addArrangedSubview(entry.view)
        refresh(position: settings.toastPosition)

        DispatchQueue.main.asyncAfter(deadline: .now() + settings.toastDuration) { [weak self] in
            self?.dismiss(id: entry.id, position: settings.toastPosition)
        }
    }

    private func dismiss(id: UUID, position: ToastPosition) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }

        let entry = entries.remove(at: index)
        stackView.removeArrangedSubview(entry.view)
        entry.view.removeFromSuperview()
        refresh(position: position)
    }

    private func refresh(position: ToastPosition) {
        guard !entries.isEmpty else {
            // Keeping the reusable window alive avoids LSUIElement apps being terminated after the last toast closes.
            window?.orderOut(nil)
            return
        }

        let window = ensureWindow()
        let totalHeight = entries.reduce(CGFloat(0)) { $0 + $1.height }
            + CGFloat(max(0, entries.count - 1)) * gap
        window.setFrame(frame(for: position, height: totalHeight), display: true)
        window.orderFrontRegardless()
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = gap
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: minHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "CopyTranslator Toast Stack"
        window.contentView = contentView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.hasShadow = false
        self.window = window
        return window
    }

    private func makeEntry(title: String, message: String) -> ToastEntry {
        let id = UUID()
        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 8
        card.layer?.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail

        let messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.textColor = .white
        messageLabel.maximumNumberOfLines = 5
        messageLabel.lineBreakMode = .byWordWrapping

        let content = NSStackView(views: [titleLabel, messageLabel])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = contentSpacing
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: width),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: horizontalPadding),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -horizontalPadding),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: verticalPadding),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -verticalPadding),
        ])

        // Toast height follows the actual text instead of reserving the old roomy fixed card height.
        let contentWidth = width - (horizontalPadding * 2)
        let titleHeight = title.height(constrainedTo: contentWidth, font: .boldSystemFont(ofSize: 13))
        let messageHeight = message.height(constrainedTo: contentWidth, font: .systemFont(ofSize: 14), maximumLines: 5)
        let height = max(minHeight, titleHeight + messageHeight + contentSpacing + (verticalPadding * 2))
        card.heightAnchor.constraint(equalToConstant: height).isActive = true
        return ToastEntry(id: id, view: card, height: height)
    }

    private func frame(for position: ToastPosition, height: CGFloat) -> NSRect {
        guard let screenFrame = NSScreen.main?.visibleFrame else {
            return NSRect(x: margin, y: margin, width: width, height: height)
        }

        let origin: NSPoint
        switch position {
        case .bottomRight:
            origin = NSPoint(x: screenFrame.maxX - width - margin, y: screenFrame.minY + margin)
        case .bottomLeft:
            origin = NSPoint(x: screenFrame.minX + margin, y: screenFrame.minY + margin)
        case .topRight:
            origin = NSPoint(x: screenFrame.maxX - width - margin, y: screenFrame.maxY - margin - height)
        case .topLeft:
            origin = NSPoint(x: screenFrame.minX + margin, y: screenFrame.maxY - margin - height)
        }

        return NSRect(origin: origin, size: NSSize(width: width, height: height))
    }
}

private extension String {
    func height(constrainedTo width: CGFloat, font: NSFont, maximumLines: Int? = nil) -> CGFloat {
        let rect = (self as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let measured = ceil(rect.height)
        guard let maximumLines else {
            return measured
        }

        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        return min(measured, lineHeight * CGFloat(maximumLines))
    }
}
