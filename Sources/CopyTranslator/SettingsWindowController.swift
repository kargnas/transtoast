import AppKit
import ApplicationServices
import CopyTranslatorCore
import CoreGraphics

@MainActor
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    // Single source for spacing/width tokens. Spacing values stay on the 4/8/12/16/20/24
    // scale so the window keeps consistent whitespace; widths live here so no magic number leaks into layout code.
    private enum Layout {
        static let groupSpacing: CGFloat = 16
        static let rowSpacing: CGFloat = 8
        static let windowInset: CGFloat = 20
        static let labelColumnWidth: CGFloat = 150
        static let controlMinWidth: CGFloat = 220
        static let resetButtonMinWidth: CGFloat = 120
        static let actionButtonMinWidth: CGFloat = 132
    }

    private enum SettingRow: Int, CaseIterable {
        case provider
        case localModel
        case sourceLanguage
        case targetLanguage
        case toastPosition
        case localBackendPath
        case customLocalModelsPath
        case openRouterTextModel
        case openRouterVisionModel
    }

    private let settingsStore: SettingsStore
    private let onSettingsChanged: () -> Void
    private let onTestTranslation: () -> Void
    private let onStackedToasts: () -> Void
    private let onRequestLogs: () -> Void
    private let onScreenshotTranslation: () -> Void
    private let onLocalModelSetup: () -> Void
    private let onKeyboardPermissionRequest: () -> Void
    private let onScreenRecordingPermissionRequest: () -> Void
    private let onPermissionOverlayRequest: () -> Void

    private let providerPopup = NSPopUpButton()
    private let localModelPopup = NSPopUpButton()
    private let sourceLanguagePopup = NSPopUpButton()
    private let targetLanguagePopup = NSPopUpButton()
    private let toastPositionPopup = NSPopUpButton()
    private let localBackendField = NSTextField()
    private let customLocalModelsField = NSTextField()
    private let openRouterTextModelField = NSTextField()
    private let openRouterVisionModelField = NSTextField()
    private let permissionStatusField = NSTextField(wrappingLabelWithString: "")
    private let lastResultField = NSTextField(wrappingLabelWithString: "No translation yet.")
    private var resetButtons: [SettingRow: NSButton] = [:]

    init(
        settingsStore: SettingsStore,
        onSettingsChanged: @escaping () -> Void,
        onTestTranslation: @escaping () -> Void,
        onStackedToasts: @escaping () -> Void,
        onRequestLogs: @escaping () -> Void,
        onScreenshotTranslation: @escaping () -> Void,
        onLocalModelSetup: @escaping () -> Void,
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
        self.onLocalModelSetup = onLocalModelSetup
        self.onKeyboardPermissionRequest = onKeyboardPermissionRequest
        self.onScreenRecordingPermissionRequest = onScreenRecordingPermissionRequest
        self.onPermissionOverlayRequest = onPermissionOverlayRequest

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CopyTranslator Settings"
        window.minSize = NSSize(width: 580, height: 460)
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

    func controlTextDidChange(_ notification: Notification) {
        applyTextFields()
    }

    private func makeContentView() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .width
        root.distribution = .fill
        root.spacing = Layout.groupSpacing
        root.edgeInsets = NSEdgeInsets(
            top: Layout.windowInset,
            left: Layout.windowInset,
            bottom: Layout.windowInset,
            right: Layout.windowInset
        )

        let title = NSTextField(labelWithString: "CopyTranslator Settings")
        // Dynamic Type style instead of a hardcoded point size so the title respects accessibility text scaling.
        title.font = .preferredFont(forTextStyle: .title2)
        root.addArrangedSubview(title)

        root.addArrangedSubview(row(label: "Text Provider", control: providerPopup, setting: .provider))
        root.addArrangedSubview(row(label: "Local Model", control: localModelPopup, setting: .localModel))
        root.addArrangedSubview(row(label: "Source Language", control: sourceLanguagePopup, setting: .sourceLanguage))
        root.addArrangedSubview(row(label: "Target Language", control: targetLanguagePopup, setting: .targetLanguage))
        root.addArrangedSubview(row(label: "Toast Position", control: toastPositionPopup, setting: .toastPosition))
        root.addArrangedSubview(row(label: "Local Backend Path", control: localBackendField, setting: .localBackendPath))
        root.addArrangedSubview(row(label: "Custom Models JSON", control: customLocalModelsField, setting: .customLocalModelsPath))
        root.addArrangedSubview(row(label: "OpenRouter Text Model", control: openRouterTextModelField, setting: .openRouterTextModel))
        root.addArrangedSubview(row(label: "OpenRouter Vision Model", control: openRouterVisionModelField, setting: .openRouterVisionModel))
        root.addArrangedSubview(row(label: "Permissions", control: permissionStatusField))
        root.addArrangedSubview(row(label: "Last Result", control: lastResultField))

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = Layout.rowSpacing
        buttonRow.addArrangedSubview(button(title: "Run Text Test", action: #selector(runTextTest)))
        buttonRow.addArrangedSubview(button(title: "Model Setup", action: #selector(showLocalModelSetup)))
        buttonRow.addArrangedSubview(button(title: "Request Logs", action: #selector(showRequestLogs)))
        root.addArrangedSubview(buttonRow)

        let testRow = NSStackView()
        testRow.orientation = .horizontal
        testRow.spacing = Layout.rowSpacing
        testRow.addArrangedSubview(button(title: "Show Stacked Toasts", action: #selector(showStackedToasts)))
        testRow.addArrangedSubview(button(title: "Translate Screenshot", action: #selector(translateScreenshot)))
        root.addArrangedSubview(testRow)

        let permissionRow = NSStackView()
        permissionRow.orientation = .horizontal
        permissionRow.spacing = Layout.rowSpacing
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
        configurePopup(
            localModelPopup,
            cases: LocalModelRegistry.models(customModelsPath: settingsStore.settings.customLocalModelsPath).map { ($0.title, $0.id) },
            action: #selector(localModelChanged)
        )
        configurePopup(
            sourceLanguagePopup,
            cases: TranslationLanguage.sourceLanguageNames.map { ($0, $0) },
            action: #selector(sourceLanguageChanged)
        )
        configurePopup(
            targetLanguagePopup,
            cases: TranslationLanguage.targetLanguageNames.map { ($0, $0) },
            action: #selector(targetLanguageChanged)
        )
        configurePopup(toastPositionPopup, cases: ToastPosition.allCases.map { ($0.title, $0.rawValue) }, action: #selector(toastPositionChanged))

        for field in [localBackendField, customLocalModelsField, openRouterTextModelField, openRouterVisionModelField] {
            field.delegate = self
            field.target = self
            field.action = #selector(textFieldSubmitted)
            field.lineBreakMode = .byTruncatingMiddle
        }
        permissionStatusField.lineBreakMode = .byWordWrapping
        permissionStatusField.maximumNumberOfLines = 3
        permissionStatusField.isSelectable = true
        lastResultField.lineBreakMode = .byWordWrapping
        lastResultField.maximumNumberOfLines = 4
        lastResultField.isSelectable = true
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
        configurePopup(
            localModelPopup,
            cases: LocalModelRegistry.models(customModelsPath: settingsStore.settings.customLocalModelsPath).map { ($0.title, $0.id) },
            action: #selector(localModelChanged)
        )
        select(providerPopup, value: settingsStore.settings.provider.rawValue)
        select(localModelPopup, value: settingsStore.settings.localModelID)
        select(sourceLanguagePopup, value: settingsStore.settings.sourceLanguage)
        select(targetLanguagePopup, value: settingsStore.settings.targetLanguage)
        select(toastPositionPopup, value: settingsStore.settings.toastPosition.rawValue)
        localBackendField.stringValue = settingsStore.settings.localHyMT2BackendPath ?? ""
        customLocalModelsField.stringValue = settingsStore.settings.customLocalModelsPath ?? ""
        openRouterTextModelField.stringValue = settingsStore.settings.openRouterTextModel
        openRouterVisionModelField.stringValue = settingsStore.settings.openRouterVisionModel
        permissionStatusField.stringValue = permissionStatusText()
        refreshDefaultButtons()
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

    private func row(label: String, control: NSControl, setting: SettingRow? = nil) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.alignment = .right
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.widthAnchor.constraint(equalToConstant: Layout.labelColumnWidth).isActive = true
        // Label column is fixed; the control flexes. High hugging on the label keeps the two-column grid aligned.
        labelView.setContentHuggingPriority(.required, for: .horizontal)

        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.controlMinWidth).isActive = true
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var views: [NSView] = [labelView, control]
        if let setting {
            views.append(resetButton(for: setting))
        }

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = Layout.rowSpacing
        return stack
    }

    private func resetButton(for setting: SettingRow) -> NSButton {
        let button = NSButton(title: "Reset to Default", target: self, action: #selector(resetSettingToDefault))
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.tag = setting.rawValue
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.resetButtonMinWidth).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        resetButtons[setting] = button
        return button
    }

    private func button(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.sendAction(on: [.leftMouseDown, .leftMouseUp])
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.actionButtonMinWidth).isActive = true
        return button
    }

    @objc private func providerChanged() {
        guard let value = providerPopup.selectedItem?.representedObject as? String,
              let provider = TranslationProvider(rawValue: value) else {
            return
        }
        settingsStore.settings.provider = provider
        settingsDidChange()
    }

    @objc private func localModelChanged() {
        guard let value = localModelPopup.selectedItem?.representedObject as? String else {
            return
        }
        settingsStore.settings.localModelID = value
        settingsDidChange()
    }

    @objc private func sourceLanguageChanged() {
        guard let value = sourceLanguagePopup.selectedItem?.representedObject as? String else {
            return
        }
        settingsStore.settings.sourceLanguage = value
        settingsDidChange()
    }

    @objc private func targetLanguageChanged() {
        guard let value = targetLanguagePopup.selectedItem?.representedObject as? String else {
            return
        }
        settingsStore.settings.targetLanguage = value
        settingsDidChange()
    }

    @objc private func toastPositionChanged() {
        guard let value = toastPositionPopup.selectedItem?.representedObject as? String,
              let position = ToastPosition(rawValue: value) else {
            return
        }
        settingsStore.settings.toastPosition = position
        settingsDidChange()
    }

    @objc private func textFieldSubmitted() {
        applyTextFields()
    }

    private func applyTextFields() {
        let backendPath = localBackendField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsStore.settings.localHyMT2BackendPath = backendPath.isEmpty ? nil : backendPath
        let customModelsPath = customLocalModelsField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsStore.settings.customLocalModelsPath = customModelsPath.isEmpty ? nil : customModelsPath
        settingsStore.settings.openRouterTextModel = openRouterTextModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsStore.settings.openRouterVisionModel = openRouterVisionModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsDidChange()
    }

    @objc private func resetSettingToDefault(_ sender: NSButton) {
        guard let row = SettingRow(rawValue: sender.tag) else {
            return
        }

        let defaults = TranslatorSettings()
        switch row {
        case .provider:
            settingsStore.settings.provider = defaults.provider
        case .localModel:
            settingsStore.settings.localModelID = defaults.localModelID
        case .sourceLanguage:
            settingsStore.settings.sourceLanguage = defaults.sourceLanguage
        case .targetLanguage:
            settingsStore.settings.targetLanguage = defaults.targetLanguage
        case .toastPosition:
            settingsStore.settings.toastPosition = defaults.toastPosition
        case .localBackendPath:
            settingsStore.settings.localHyMT2BackendPath = defaults.localHyMT2BackendPath
        case .customLocalModelsPath:
            settingsStore.settings.customLocalModelsPath = defaults.customLocalModelsPath
        case .openRouterTextModel:
            settingsStore.settings.openRouterTextModel = defaults.openRouterTextModel
        case .openRouterVisionModel:
            settingsStore.settings.openRouterVisionModel = defaults.openRouterVisionModel
        }

        refreshControls()
        onSettingsChanged()
    }

    private func settingsDidChange() {
        refreshDefaultButtons()
        onSettingsChanged()
    }

    private func refreshDefaultButtons() {
        let settings = settingsStore.settings
        let defaults = TranslatorSettings()
        resetButtons[.provider]?.isHidden = settings.provider == defaults.provider
        resetButtons[.localModel]?.isHidden = settings.localModelID == defaults.localModelID
        resetButtons[.sourceLanguage]?.isHidden = settings.sourceLanguage == defaults.sourceLanguage
        resetButtons[.targetLanguage]?.isHidden = settings.targetLanguage == defaults.targetLanguage
        resetButtons[.toastPosition]?.isHidden = settings.toastPosition == defaults.toastPosition
        resetButtons[.localBackendPath]?.isHidden = settings.localHyMT2BackendPath == defaults.localHyMT2BackendPath
        resetButtons[.customLocalModelsPath]?.isHidden = settings.customLocalModelsPath == defaults.customLocalModelsPath
        resetButtons[.openRouterTextModel]?.isHidden = settings.openRouterTextModel == defaults.openRouterTextModel
        resetButtons[.openRouterVisionModel]?.isHidden = settings.openRouterVisionModel == defaults.openRouterVisionModel
    }

    @objc private func runTextTest() {
        applyTextFields()
        onTestTranslation()
    }

    @objc private func showStackedToasts() {
        onStackedToasts()
    }

    @objc private func showLocalModelSetup() {
        applyTextFields()
        onLocalModelSetup()
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
