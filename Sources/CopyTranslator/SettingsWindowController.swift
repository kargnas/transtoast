import AppKit
import ApplicationServices
import CopyTranslatorCore
import CoreGraphics

@MainActor
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private let settingsStore: SettingsStore
    private let onSettingsChanged: () -> Void
    private let onTestTranslation: () -> Void
    private let onStackedToasts: () -> Void
    private let onRequestLogs: () -> Void
    private let onScreenshotTranslation: () -> Void
    private let onKeyboardPermissionRequest: () -> Void
    private let onScreenRecordingPermissionRequest: () -> Void
    private let onPermissionOverlayRequest: () -> Void

    private let providerPopup = NSPopUpButton()
    private let hyMT2ModelPopup = NSPopUpButton()
    private let languagePopup = NSPopUpButton()
    private let toastPositionPopup = NSPopUpButton()
    private let localBackendField = NSTextField()
    private let openRouterTextModelField = NSTextField()
    private let openRouterVisionModelField = NSTextField()
    private let permissionStatusField = NSTextField(wrappingLabelWithString: "")
    private let lastResultField = NSTextField(wrappingLabelWithString: "No translation yet.")

    init(
        settingsStore: SettingsStore,
        onSettingsChanged: @escaping () -> Void,
        onTestTranslation: @escaping () -> Void,
        onStackedToasts: @escaping () -> Void,
        onRequestLogs: @escaping () -> Void,
        onScreenshotTranslation: @escaping () -> Void,
        onKeyboardPermissionRequest: @escaping () -> Void,
        onScreenRecordingPermissionRequest: @escaping () -> Void,
        onPermissionOverlayRequest: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.onSettingsChanged = onSettingsChanged
        self.onTestTranslation = onTestTranslation
        self.onStackedToasts = onStackedToasts
        self.onRequestLogs = onRequestLogs
        self.onScreenshotTranslation = onScreenshotTranslation
        self.onKeyboardPermissionRequest = onKeyboardPermissionRequest
        self.onScreenRecordingPermissionRequest = onScreenRecordingPermissionRequest
        self.onPermissionOverlayRequest = onPermissionOverlayRequest

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 550),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CopyTranslator Settings"
        window.center()
        super.init(window: window)
        window.contentView = makeContentView()
        refreshControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        refreshControls()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        applyTextFields()
    }

    private func makeContentView() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let title = NSTextField(labelWithString: "CopyTranslator Settings")
        title.font = .boldSystemFont(ofSize: 17)
        root.addArrangedSubview(title)

        root.addArrangedSubview(row(label: "Text Provider", control: providerPopup))
        root.addArrangedSubview(row(label: "Local Hy-MT2 Model", control: hyMT2ModelPopup))
        root.addArrangedSubview(row(label: "Target Language", control: languagePopup))
        root.addArrangedSubview(row(label: "Toast Position", control: toastPositionPopup))
        root.addArrangedSubview(row(label: "Local Backend Path", control: localBackendField))
        root.addArrangedSubview(row(label: "OpenRouter Text Model", control: openRouterTextModelField))
        root.addArrangedSubview(row(label: "OpenRouter Vision Model", control: openRouterVisionModelField))
        root.addArrangedSubview(row(label: "Permissions", control: permissionStatusField))
        root.addArrangedSubview(row(label: "Last Result", control: lastResultField))

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.addArrangedSubview(button(title: "Run Text Test", action: #selector(runTextTest)))
        buttonRow.addArrangedSubview(button(title: "Show Stacked Toasts", action: #selector(showStackedToasts)))
        buttonRow.addArrangedSubview(button(title: "Request Logs", action: #selector(showRequestLogs)))
        buttonRow.addArrangedSubview(button(title: "Translate Screenshot", action: #selector(translateScreenshot)))
        root.addArrangedSubview(buttonRow)

        let permissionRow = NSStackView()
        permissionRow.orientation = .horizontal
        permissionRow.spacing = 10
        permissionRow.addArrangedSubview(button(title: "Permission Helper", action: #selector(showPermissionOverlay)))
        permissionRow.addArrangedSubview(button(title: "Keyboard Prompt", action: #selector(requestKeyboardPermission)))
        permissionRow.addArrangedSubview(button(title: "Screen Settings", action: #selector(requestScreenRecordingPermission)))
        root.addArrangedSubview(permissionRow)

        configureControls()
        return root
    }

    func updateLastResult(_ text: String) {
        lastResultField.stringValue = text
    }

    private func configureControls() {
        configurePopup(providerPopup, cases: TranslationProvider.allCases.map { ($0.title, $0.rawValue) }, action: #selector(providerChanged))
        configurePopup(hyMT2ModelPopup, cases: HyMT2Model.allCases.map { ($0.title, $0.rawValue) }, action: #selector(hyMT2ModelChanged))
        configurePopup(
            languagePopup,
            cases: ["English", "Korean", "Simplified Chinese", "Japanese", "Spanish", "German", "French"].map { ($0, $0) },
            action: #selector(languageChanged)
        )
        configurePopup(toastPositionPopup, cases: ToastPosition.allCases.map { ($0.title, $0.rawValue) }, action: #selector(toastPositionChanged))

        for field in [localBackendField, openRouterTextModelField, openRouterVisionModelField] {
            field.delegate = self
            field.target = self
            field.action = #selector(textFieldSubmitted)
            field.lineBreakMode = .byTruncatingMiddle
        }
        permissionStatusField.lineBreakMode = .byWordWrapping
        permissionStatusField.maximumNumberOfLines = 3
        lastResultField.lineBreakMode = .byWordWrapping
        lastResultField.maximumNumberOfLines = 4
    }

    private func configurePopup(_ popup: NSPopUpButton, cases: [(String, String)], action: Selector) {
        popup.removeAllItems()
        for item in cases {
            popup.addItem(withTitle: item.0)
            popup.lastItem?.representedObject = item.1
        }
        popup.target = self
        popup.action = action
    }

    private func refreshControls() {
        select(providerPopup, value: settingsStore.settings.provider.rawValue)
        select(hyMT2ModelPopup, value: settingsStore.settings.hyMT2Model.rawValue)
        select(languagePopup, value: settingsStore.settings.targetLanguage)
        select(toastPositionPopup, value: settingsStore.settings.toastPosition.rawValue)
        localBackendField.stringValue = settingsStore.settings.localHyMT2BackendPath ?? ""
        openRouterTextModelField.stringValue = settingsStore.settings.openRouterTextModel
        openRouterVisionModelField.stringValue = settingsStore.settings.openRouterVisionModel
        permissionStatusField.stringValue = permissionStatusText()
    }

    private func permissionStatusText() -> String {
        let keyboardReady = CGPreflightListenEventAccess() || AXIsProcessTrusted()
        let screenReady = CGPreflightScreenCaptureAccess()
        let keyboard = keyboardReady ? "Keyboard ready" : "Clipboard fallback ready; keyboard permission recommended"
        let screen = screenReady ? "Screen ready" : "Screen trust is not active for this signed app"
        return "\(keyboard). \(screen)."
    }

    private func select(_ popup: NSPopUpButton, value: String) {
        for item in popup.itemArray where item.representedObject as? String == value {
            popup.select(item)
            return
        }
    }

    private func row(label: String, control: NSControl) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.alignment = .right
        labelView.widthAnchor.constraint(equalToConstant: 150).isActive = true

        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: 310).isActive = true

        let stack = NSStackView(views: [labelView, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        return stack
    }

    private func button(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.sendAction(on: [.leftMouseDown, .leftMouseUp])
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 120).isActive = true
        return button
    }

    @objc private func providerChanged() {
        guard let value = providerPopup.selectedItem?.representedObject as? String,
              let provider = TranslationProvider(rawValue: value) else {
            return
        }
        settingsStore.settings.provider = provider
        onSettingsChanged()
    }

    @objc private func hyMT2ModelChanged() {
        guard let value = hyMT2ModelPopup.selectedItem?.representedObject as? String,
              let model = HyMT2Model(rawValue: value) else {
            return
        }
        settingsStore.settings.hyMT2Model = model
        onSettingsChanged()
    }

    @objc private func languageChanged() {
        guard let value = languagePopup.selectedItem?.representedObject as? String else {
            return
        }
        settingsStore.settings.targetLanguage = value
        onSettingsChanged()
    }

    @objc private func toastPositionChanged() {
        guard let value = toastPositionPopup.selectedItem?.representedObject as? String,
              let position = ToastPosition(rawValue: value) else {
            return
        }
        settingsStore.settings.toastPosition = position
        onSettingsChanged()
    }

    @objc private func textFieldSubmitted() {
        applyTextFields()
    }

    private func applyTextFields() {
        let backendPath = localBackendField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsStore.settings.localHyMT2BackendPath = backendPath.isEmpty ? nil : backendPath
        settingsStore.settings.openRouterTextModel = openRouterTextModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsStore.settings.openRouterVisionModel = openRouterVisionModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        onSettingsChanged()
    }

    @objc private func runTextTest() {
        applyTextFields()
        onTestTranslation()
    }

    @objc private func showStackedToasts() {
        onStackedToasts()
    }

    @objc private func showRequestLogs() {
        onRequestLogs()
    }

    @objc private func translateScreenshot() {
        applyTextFields()
        onScreenshotTranslation()
    }

    @objc private func requestKeyboardPermission() {
        onKeyboardPermissionRequest()
    }

    @objc private func requestScreenRecordingPermission() {
        onScreenRecordingPermissionRequest()
    }

    @objc private func showPermissionOverlay() {
        onPermissionOverlayRequest()
    }
}
