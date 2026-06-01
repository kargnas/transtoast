import AppKit
import ApplicationServices
import CopyTranslatorCore
import CoreGraphics

@MainActor
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private enum Layout {
        static let groupSpacing: CGFloat = 16
        static let rowSpacing: CGFloat = 8
        static let groupInset: CGFloat = 12
        static let windowInset: CGFloat = 20
        static let labelColumnWidth: CGFloat = 150
        static let controlMinWidth: CGFloat = 220
        static let controlPreferredWidth: CGFloat = 300
        static let resetButtonMinWidth: CGFloat = 132
        static let actionButtonMinWidth: CGFloat = 132
        static let formMaxWidth: CGFloat = 540
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
    private let keyboardPermissionStatusField = NSTextField(wrappingLabelWithString: "")
    private let screenPermissionStatusField = NSTextField(wrappingLabelWithString: "")
    private let lastResultField = NSTextField(wrappingLabelWithString: "No translation yet.")
    private var resetButtons: [SettingRow: NSButton] = [:]
    private var resetButtonWidths: [SettingRow: NSLayoutConstraint] = [:]

    init(
        settingsStore: SettingsStore,
        onSettingsChanged: @escaping () -> Void,
        onTestTranslation: @escaping () -> Void,
        onStackedToasts: @escaping () -> Void,
        onRequestLogs: @escaping () -> Void,
        onScreenshotTranslation: @escaping () -> Void,
        onLocalModelSetup: @escaping () -> Void,
        onPermissionOverlayRequest: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.onSettingsChanged = onSettingsChanged
        self.onTestTranslation = onTestTranslation
        self.onStackedToasts = onStackedToasts
        self.onRequestLogs = onRequestLogs
        self.onScreenshotTranslation = onScreenshotTranslation
        self.onLocalModelSetup = onLocalModelSetup
        self.onPermissionOverlayRequest = onPermissionOverlayRequest

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CopyTranslator Settings"
        window.minSize = NSSize(width: 580, height: 620)
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

        root.addArrangedSubview(groupBox(
            title: "General",
            views: [
                row(label: "Text Provider", control: providerPopup, setting: .provider),
                row(label: "Source Language", control: sourceLanguagePopup, setting: .sourceLanguage),
                row(label: "Target Language", control: targetLanguagePopup, setting: .targetLanguage),
                row(label: "Toast Position", control: toastPositionPopup, setting: .toastPosition),
            ]
        ))

        root.addArrangedSubview(groupBox(
            title: "Models",
            views: [
                row(label: "Local Model", control: localModelPopup, setting: .localModel),
                row(label: "Local Backend Path", control: localBackendField, setting: .localBackendPath),
                row(label: "Custom Models JSON", control: customLocalModelsField, setting: .customLocalModelsPath),
                row(label: "Text Model", control: openRouterTextModelField, setting: .openRouterTextModel),
                row(label: "Vision Model", control: openRouterVisionModelField, setting: .openRouterVisionModel),
                actionRow(buttons: [button(title: "Model Setup", action: #selector(showLocalModelSetup))]),
            ]
        ))

        root.addArrangedSubview(groupBox(
            title: "Permissions",
            views: [
                row(label: "Keyboard", control: keyboardPermissionStatusField),
                row(label: "Screen Recording", control: screenPermissionStatusField),
                actionRow(buttons: [button(title: "Permission Helper", action: #selector(showPermissionOverlay))]),
            ]
        ))

        root.addArrangedSubview(groupBox(
            title: "Diagnostics",
            views: [
                row(label: "Last Result", control: lastResultField),
                actionRow(buttons: [
                    button(title: "Run Text Test", action: #selector(runTextTest)),
                    button(title: "Translate Screenshot", action: #selector(translateScreenshot)),
                ]),
                actionRow(buttons: [
                    button(title: "Request Logs", action: #selector(showRequestLogs)),
                    button(title: "Show Stacked Toasts", action: #selector(showStackedToasts)),
                ]),
            ]
        ))

        configureControls()
        return contentView
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

        for popup in [providerPopup, localModelPopup, sourceLanguagePopup, targetLanguagePopup, toastPositionPopup] {
            popup.font = .preferredFont(forTextStyle: .body)
        }

        for field in [localBackendField, customLocalModelsField, openRouterTextModelField, openRouterVisionModelField] {
            field.delegate = self
            field.target = self
            field.action = #selector(textFieldSubmitted)
            field.font = .preferredFont(forTextStyle: .body)
            field.lineBreakMode = .byTruncatingMiddle
        }

        for field in [keyboardPermissionStatusField, screenPermissionStatusField, lastResultField] {
            field.font = .preferredFont(forTextStyle: .body)
            field.lineBreakMode = .byWordWrapping
            field.isSelectable = true
        }
        keyboardPermissionStatusField.maximumNumberOfLines = 2
        screenPermissionStatusField.maximumNumberOfLines = 2
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
        refreshPermissionStatusFields()
        refreshDefaultButtons()
    }

    private func refreshPermissionStatusFields() {
        let keyboardReady = CGPreflightListenEventAccess() || AXIsProcessTrusted()
        let screenReady = CGPreflightScreenCaptureAccess()
        keyboardPermissionStatusField.stringValue = keyboardReady ? "Ready" : "Not granted"
        screenPermissionStatusField.stringValue = screenReady ? "Ready" : "Not granted"
        keyboardPermissionStatusField.textColor = keyboardReady ? .labelColor : .secondaryLabelColor
        screenPermissionStatusField.textColor = screenReady ? .labelColor : .secondaryLabelColor
    }

    private func select(_ popup: NSPopUpButton, value: String) {
        for item in popup.itemArray where item.representedObject as? String == value {
            popup.select(item)
            return
        }
    }

    private func groupBox(title: String, views: [NSView]) -> NSBox {
        let box = NSBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.title = title
        box.titlePosition = .atTop
        box.boxType = .primary
        box.contentViewMargins = NSSize(width: Layout.groupInset, height: Layout.groupInset)

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

    private func row(label: String, control: NSControl, setting: SettingRow? = nil) -> NSView {
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.controlMinWidth).isActive = true
        let preferredWidth = control.widthAnchor.constraint(equalToConstant: Layout.controlPreferredWidth)
        preferredWidth.priority = .defaultHigh
        preferredWidth.isActive = true
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [
            rowLabel(label),
            control,
            resetButtonContainer(for: setting),
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = Layout.rowSpacing
        return stack
    }

    private func actionRow(buttons: [NSButton]) -> NSView {
        let buttonStack = NSStackView(views: buttons)
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fill
        buttonStack.spacing = Layout.rowSpacing

        let controlContainer = NSView()
        controlContainer.translatesAutoresizingMaskIntoConstraints = false
        controlContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.controlMinWidth).isActive = true
        let preferredWidth = controlContainer.widthAnchor.constraint(equalToConstant: Layout.controlPreferredWidth)
        preferredWidth.priority = .defaultHigh
        preferredWidth.isActive = true
        controlContainer.addSubview(buttonStack)
        NSLayoutConstraint.activate([
            buttonStack.leadingAnchor.constraint(equalTo: controlContainer.leadingAnchor),
            buttonStack.topAnchor.constraint(equalTo: controlContainer.topAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: controlContainer.bottomAnchor),
            buttonStack.trailingAnchor.constraint(lessThanOrEqualTo: controlContainer.trailingAnchor),
        ])

        let stack = NSStackView(views: [rowLabel(""), controlContainer])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = Layout.rowSpacing
        return stack
    }

    private func rowLabel(_ text: String) -> NSTextField {
        let labelView = NSTextField(labelWithString: text)
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.alignment = .right
        labelView.font = .preferredFont(forTextStyle: .body)
        labelView.lineBreakMode = .byTruncatingTail
        labelView.widthAnchor.constraint(equalToConstant: Layout.labelColumnWidth).isActive = true
        labelView.setContentHuggingPriority(.required, for: .horizontal)
        labelView.setContentCompressionResistancePriority(.required, for: .horizontal)
        return labelView
    }

    private func resetButtonContainer(for setting: SettingRow?) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        guard let setting else {
            return container
        }

        let width = container.widthAnchor.constraint(equalToConstant: 0)
        width.isActive = true
        resetButtonWidths[setting] = width

        let button = NSButton(title: "Reset to Default", target: self, action: #selector(resetSettingToDefault))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.font = .preferredFont(forTextStyle: .body)
        button.tag = setting.rawValue
        button.isHidden = true
        resetButtons[setting] = button
        container.addSubview(button)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    private func button(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.font = .preferredFont(forTextStyle: .body)
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
        setResetVisible(settings.provider != defaults.provider, for: .provider)
        setResetVisible(settings.localModelID != defaults.localModelID, for: .localModel)
        setResetVisible(settings.sourceLanguage != defaults.sourceLanguage, for: .sourceLanguage)
        setResetVisible(settings.targetLanguage != defaults.targetLanguage, for: .targetLanguage)
        setResetVisible(settings.toastPosition != defaults.toastPosition, for: .toastPosition)
        setResetVisible(settings.localHyMT2BackendPath != defaults.localHyMT2BackendPath, for: .localBackendPath)
        setResetVisible(settings.customLocalModelsPath != defaults.customLocalModelsPath, for: .customLocalModelsPath)
        setResetVisible(settings.openRouterTextModel != defaults.openRouterTextModel, for: .openRouterTextModel)
        setResetVisible(settings.openRouterVisionModel != defaults.openRouterVisionModel, for: .openRouterVisionModel)
    }

    private func setResetVisible(_ visible: Bool, for row: SettingRow) {
        resetButtons[row]?.isHidden = !visible
        resetButtonWidths[row]?.constant = visible ? Layout.resetButtonMinWidth : 0
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

    @objc private func showPermissionOverlay() {
        onPermissionOverlayRequest()
    }
}
