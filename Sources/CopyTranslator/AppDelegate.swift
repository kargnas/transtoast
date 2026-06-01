import AppKit
import ApplicationServices
import CopyTranslatorCore
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let credentialsProvider = CredentialsProvider()
    private let translationService = TranslationService()
    private let toastManager = ToastManager()
    private let requestLogStore = RequestLogStore()
    private var statusItem: NSStatusItem?
    private var keyboardMonitor: KeyboardMonitor?
    private var pasteboardMonitor: PasteboardMonitor?
    private var screenshotHotKey: ScreenshotHotKey?
    private var keepAliveWindow: NSWindow?
    private var settingsWindowController: SettingsWindowController?
    private var localModelSetupWindowController: LocalModelSetupWindowController?
    private var requestLogWindowController: RequestLogWindowController?
    private var permissionOverlayWindowController: PermissionOverlayWindowController?
    private var lastClipboardTriggerAt: Date?
    private var isUserQuitting = false
    private var hasStarted = false
    private var lifetimeActivity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        start()
    }

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        lifetimeActivity = ProcessInfo.processInfo.beginActivity(
            options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "CopyTranslator must keep monitoring clipboard and shortcuts without a regular window."
        )
        ProcessInfo.processInfo.disableAutomaticTermination("CopyTranslator must keep monitoring clipboard and shortcuts without a regular window.")
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        createKeepAliveWindow()
        configureStatusItem()
        startKeyboardMonitor()
        startScreenshotHotKey()
        startPasteboardMonitor()
        toastManager.show(
            title: "CopyTranslator",
            message: "Ready. Press Cmd+C twice to translate clipboard text.",
            settings: settingsStore.settings
        )
        reportKeyboardPermissionStatus(requestIfMissing: false)
        if CommandLine.arguments.contains("--show-settings") {
            showSettingsWindow()
        }
        if CommandLine.arguments.contains("--show-permission-helper") {
            showPermissionOverlay()
        }
        if !settingsStore.settings.hasCompletedLocalModelSelection {
            showLocalModelSetupWindow()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isUserQuitting ? .terminateNow : .terminateCancel
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 48)
        item.button?.image = Self.makeStatusIcon()
        item.button?.title = "CT"
        item.button?.imagePosition = .imageLeft
        item.button?.toolTip = "CopyTranslator"
        statusItem = item
        rebuildMenu()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "CopyTranslator")
        appMenu.addItem(menuItem(title: "Quit CopyTranslator", action: #selector(quit), key: "q", target: self))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(menuItem(title: "Cut", action: #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(menuItem(title: "Copy", action: #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(menuItem(title: "Paste", action: #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(menuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), key: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private static func makeStatusIcon() -> NSImage {
        if let image = NSImage(systemSymbolName: "translate", accessibilityDescription: "CopyTranslator") {
            image.isTemplate = true
            return image
        }

        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        NSColor.black.setStroke()
        let backBubble = NSBezierPath(roundedRect: NSRect(x: 3, y: 7, width: 9, height: 7), xRadius: 2, yRadius: 2)
        backBubble.lineWidth = 1.4
        backBubble.stroke()

        let frontBubble = NSBezierPath(roundedRect: NSRect(x: 6, y: 3, width: 9, height: 8), xRadius: 2, yRadius: 2)
        frontBubble.lineWidth = 1.6
        frontBubble.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        "T".draw(in: NSRect(x: 8.1, y: 3.5, width: 7, height: 8), withAttributes: attributes)

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func imageInfo(for data: Data?) -> String? {
        guard let data,
              let bitmap = NSBitmapImageRep(data: data) else {
            return nil
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(bitmap.pixelsWide)x\(bitmap.pixelsHigh) px, \(formatter.string(fromByteCount: Int64(data.count)))"
    }

    private static func imageInfo(for data: Data?, diagnostic: String?) -> String? {
        guard let data else {
            if let diagnostic, !diagnostic.isEmpty {
                return "none (\(diagnostic))"
            }
            return nil
        }

        let info = imageInfo(for: data) ?? "attached"
        guard let diagnostic, !diagnostic.isEmpty else {
            return info
        }
        return "\(info), \(diagnostic)"
    }

    private func startKeyboardMonitor() {
        keyboardMonitor = KeyboardMonitor(
            onDoubleCopy: { [weak self] in
                self?.triggerClipboardTranslation()
            },
            onScreenshot: { [weak self] in
                self?.translateScreenshot()
            }
        )
        keyboardMonitor?.start()
    }

    private func startScreenshotHotKey() {
        screenshotHotKey = ScreenshotHotKey { [weak self] in
            self?.translateScreenshot()
        }
        let status = screenshotHotKey?.start() ?? OSStatus(-1)
        if status != noErr {
            toastManager.show(
                title: "Screenshot Shortcut",
                message: "Could not register Shift+Cmd+2. Carbon status: \(status)",
                settings: settingsStore.settings
            )
        }
    }

    private func createKeepAliveWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 1
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces]
        // LSUIElement apps with only transient toast windows can be auto-terminated after the toast closes.
        window.orderFront(nil)
        keepAliveWindow = window
    }

    private func startPasteboardMonitor() {
        pasteboardMonitor = PasteboardMonitor { [weak self] in
            self?.triggerClipboardTranslation()
        }
        pasteboardMonitor?.start()
    }

    private func triggerClipboardTranslation() {
        let now = Date()
        if let previous = lastClipboardTriggerAt,
           now.timeIntervalSince(previous) < 0.6 {
            return
        }

        lastClipboardTriggerAt = now
        translateClipboard()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        menu.addItem(disabledTitle("CopyTranslator"))
        menu.addItem(NSMenuItem.separator())

        let providerMenu = NSMenu()
        for provider in TranslationProvider.allCases {
            providerMenu.addItem(checkableItem(
                title: provider.title,
                checked: settingsStore.settings.provider == provider,
                action: #selector(setProvider(_:)),
                representedObject: provider.rawValue
            ))
        }
        menu.addItem(submenuItem(title: "Text Provider", submenu: providerMenu))

        let localModelMenu = NSMenu()
        for model in LocalModelRegistry.models(customModelsPath: settingsStore.settings.customLocalModelsPath) {
            localModelMenu.addItem(checkableItem(
                title: model.title,
                checked: settingsStore.settings.localModelID == model.id,
                action: #selector(setLocalModel(_:)),
                representedObject: model.id
            ))
        }
        menu.addItem(submenuItem(title: "Local Model", submenu: localModelMenu))

        let sourceLanguageMenu = NSMenu()
        for language in TranslationLanguage.sourceLanguageNames {
            sourceLanguageMenu.addItem(checkableItem(
                title: language,
                checked: settingsStore.settings.sourceLanguage == language,
                action: #selector(setSourceLanguage(_:)),
                representedObject: language
            ))
        }
        menu.addItem(submenuItem(title: "Source Language", submenu: sourceLanguageMenu))

        let languageMenu = NSMenu()
        for language in TranslationLanguage.targetLanguageNames {
            languageMenu.addItem(checkableItem(
                title: language,
                checked: settingsStore.settings.targetLanguage == language,
                action: #selector(setTargetLanguage(_:)),
                representedObject: language
            ))
        }
        menu.addItem(submenuItem(title: "Target Language", submenu: languageMenu))

        let positionMenu = NSMenu()
        for position in ToastPosition.allCases {
            positionMenu.addItem(checkableItem(
                title: position.title,
                checked: settingsStore.settings.toastPosition == position,
                action: #selector(setToastPosition(_:)),
                representedObject: position.rawValue
            ))
        }
        menu.addItem(submenuItem(title: "Toast Position", submenu: positionMenu))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem(title: "Settings...", action: #selector(showSettingsWindow)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem(title: "Quit", action: #selector(quit)))

        statusItem?.menu = menu
    }

    private func translateClipboard() {
        // Clipboard updates usually land just after the key event, so a short delay avoids reading stale text.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else {
                return
            }
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            performTextTranslation(text, sourceTitle: "Clipboard")
        }
    }

    private func translateScreenshot() {
        toastManager.show(title: "Screenshot", message: "Capturing and translating screenshot...", settings: settingsStore.settings)
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let data = try await ScreenshotCapture.captureMainDisplayPNG()
                let imageInfo = Self.imageInfo(for: data)
                let result = try await translationService.translateImage(
                    pngData: data,
                    settings: settingsStore.settings,
                    credentials: credentialsProvider.credentials()
                )
                show(result: result, title: "Screenshot", inputText: "[screen screenshot]", imageInfo: imageInfo)
            } catch {
                show(error: error, title: "Screenshot")
            }
        }
    }

    private func performTextTranslation(
        _ text: String,
        sourceTitle: String
    ) {
        toastManager.show(title: sourceTitle, message: "Translating...", settings: settingsStore.settings)
        settingsWindowController?.updateLastResult("\(sourceTitle): Translating...")
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let settings = settingsStore.settings
                let screenContext = await contextImagePNGDataIfNeeded(settings: settings)
                let imageInfo = Self.imageInfo(for: screenContext.pngData, diagnostic: screenContext.diagnostic)
                let result = try await translationService.translateText(
                    text,
                    settings: settings,
                    credentials: credentialsProvider.credentials(),
                    contextImagePNGData: screenContext.pngData
                )
                show(result: result, title: sourceTitle, inputText: text, imageInfo: imageInfo)
            } catch {
                show(error: error, title: sourceTitle)
            }
        }
    }

    private func contextImagePNGDataIfNeeded(settings: TranslatorSettings) async -> ScreenContextCaptureResult {
        guard settings.provider == .openRouter else {
            return ScreenContextCaptureResult(pngData: nil, diagnostic: nil)
        }

        return await ScreenshotCapture.captureMainDisplayContextPNGIfAvailable()
    }

    @MainActor
    private func show(result: TranslationResult, title: String, inputText: String, imageInfo: String?) {
        requestLogStore.add(source: title, input: inputText, result: result, imageInfo: imageInfo)
        requestLogWindowController?.reload()
        let resultSummary = if let description = result.description {
            "\(title): \(result.text)\n\(description)"
        } else {
            "\(title): \(result.text)"
        }
        toastManager.show(
            title: "\(title) · \(result.model)",
            message: result.text,
            description: result.description,
            settings: settingsStore.settings
        )
        settingsWindowController?.updateLastResult(resultSummary)
    }

    @MainActor
    private func show(error: Error, title: String) {
        settingsWindowController?.updateLastResult("\(title) Error: \(error.localizedDescription)")
        toastManager.show(
            title: "\(title) Error",
            message: error.localizedDescription,
            settings: settingsStore.settings
        )
    }

    @objc private func setProvider(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let provider = TranslationProvider(rawValue: rawValue) else {
            return
        }
        settingsStore.settings.provider = provider
        rebuildMenu()
    }

    @objc private func setLocalModel(_ sender: NSMenuItem) {
        guard let modelID = sender.representedObject as? String else {
            return
        }
        settingsStore.settings.localModelID = modelID
        rebuildMenu()
    }

    @objc private func setSourceLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? String else {
            return
        }
        settingsStore.settings.sourceLanguage = language
        rebuildMenu()
    }

    @objc private func setTargetLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? String else {
            return
        }
        settingsStore.settings.targetLanguage = language
        rebuildMenu()
    }

    @objc private func setToastPosition(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let position = ToastPosition(rawValue: rawValue) else {
            return
        }
        settingsStore.settings.toastPosition = position
        rebuildMenu()
    }

    @objc private func promptLocalHyMT2Backend() {
        promptModel(
            title: "Local Backend",
            informativeText: "Enter the local backend script path. Leave the default empty to auto-detect the backend for the selected local model.",
            currentValue: settingsStore.settings.localHyMT2BackendPath ?? ""
        ) { [weak self] value in
            self?.settingsStore.settings.localHyMT2BackendPath = value
            self?.rebuildMenu()
        }
    }

    @objc private func promptOpenRouterTextModel() {
        promptModel(
            title: "OpenRouter Text Model",
            informativeText: "Enter an OpenRouter model id.",
            currentValue: settingsStore.settings.openRouterTextModel
        ) { [weak self] value in
            self?.settingsStore.settings.openRouterTextModel = value
            self?.rebuildMenu()
        }
    }

    @objc private func promptOpenRouterVisionModel() {
        promptModel(
            title: "OpenRouter Vision Model",
            informativeText: "Enter an OpenRouter multimodal model id.",
            currentValue: settingsStore.settings.openRouterVisionModel
        ) { [weak self] value in
            self?.settingsStore.settings.openRouterVisionModel = value
            self?.rebuildMenu()
        }
    }

    @objc private func runTestTranslation() {
        performTextTranslation("The quick brown fox jumps over the lazy dog.", sourceTitle: "Test")
    }

    @objc private func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settingsStore: settingsStore,
                onSettingsChanged: { [weak self] in
                    self?.rebuildMenu()
                },
                onTestTranslation: { [weak self] in
                    self?.runTestTranslation()
                },
                onStackedToasts: { [weak self] in
                    self?.showStackedTestToasts()
                },
                onRequestLogs: { [weak self] in
                    self?.showRequestLogsWindow()
                },
                onScreenshotTranslation: { [weak self] in
                    self?.translateScreenshot()
                },
                onLocalModelSetup: { [weak self] in
                    self?.showLocalModelSetupWindow()
                },
                onPermissionOverlayRequest: { [weak self] in
                    self?.showPermissionOverlay()
                }
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
    }

    @objc private func showLocalModelSetupWindow() {
        if localModelSetupWindowController == nil {
            localModelSetupWindowController = LocalModelSetupWindowController(
                settingsStore: settingsStore,
                credentialsProvider: credentialsProvider,
                translationService: translationService,
                onSettingsChanged: { [weak self] in
                    self?.rebuildMenu()
                }
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        localModelSetupWindowController?.showWindow(nil)
    }

    @objc private func showRequestLogsWindow() {
        if requestLogWindowController == nil {
            requestLogWindowController = RequestLogWindowController(logStore: requestLogStore)
        }
        NSApp.activate(ignoringOtherApps: true)
        requestLogWindowController?.showWindow(nil)
    }

    private func showStackedTestToasts() {
        for index in 1...3 {
            toastManager.show(
                title: "Stack Test \(index)",
                message: "This toast verifies stacked placement.",
                settings: settingsStore.settings
            )
        }
    }

    @objc private func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
        toastManager.show(
            title: "Input Monitoring Settings",
            message: "Enable Input Monitoring for this app if Cmd+C detection does not fire.",
            settings: settingsStore.settings
        )
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        toastManager.show(
            title: "Accessibility Settings",
            message: "Enable Accessibility for this app if Input Monitoring is not enough for Cmd+C detection.",
            settings: settingsStore.settings
        )
    }

    @objc private func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
        toastManager.show(
            title: "Screen Recording Settings",
            message: "Enable Screen Recording for this app to translate screenshots.",
            settings: settingsStore.settings
        )
    }

    @objc private func requestKeyboardPermission() {
        reportKeyboardPermissionStatus(requestIfMissing: true)
    }

    @objc private func showPermissionOverlay() {
        if permissionOverlayWindowController == nil {
            permissionOverlayWindowController = PermissionOverlayWindowController(
                appURL: resolveAppBundleURL(),
                openInputMonitoring: { [weak self] in
                    self?.openInputMonitoringSettings()
                },
                openAccessibility: { [weak self] in
                    self?.openAccessibilitySettings()
                },
                openScreenRecording: { [weak self] in
                    self?.openScreenRecordingSettings()
                },
                requestKeyboardPrompt: { [weak self] in
                    self?.requestKeyboardPermission()
                }
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        permissionOverlayWindowController?.showWindow(nil)
    }

    private func resolveAppBundleURL() -> URL {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL
        }

        let distURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("dist/CopyTranslator.app")
        if FileManager.default.fileExists(atPath: distURL.path) {
            return distURL
        }

        return bundleURL
    }

    private func reportKeyboardPermissionStatus(requestIfMissing: Bool) {
        let canListenToEvents = CGPreflightListenEventAccess()
        let isAccessibilityTrusted = AXIsProcessTrusted()

        if canListenToEvents || isAccessibilityTrusted {
            toastManager.show(
                title: "Keyboard Permission",
                message: "Global keyboard monitoring is available.",
                settings: settingsStore.settings
            )
            return
        }

        if requestIfMissing {
            _ = CGRequestListenEventAccess()
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        toastManager.show(
            title: "Keyboard Permission Needed",
            message: "Enable Input Monitoring or Accessibility for CopyTranslator, then relaunch the app. Without it, Cmd+C twice cannot be observed from other apps.",
            settings: settingsStore.settings
        )
    }

    @objc private func quit() {
        isUserQuitting = true
        NSApp.terminate(nil)
    }

    private func promptModel(
        title: String,
        informativeText: String,
        currentValue: String,
        onSave: @escaping (String) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = informativeText
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.stringValue = currentValue
        alert.accessoryView = input

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return
        }

        onSave(value)
    }

    private func disabledTitle(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func menuItem(title: String, action: Selector, key: String, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.command]
        item.target = target
        return item
    }

    private func checkableItem(
        title: String,
        checked: Bool,
        action: Selector,
        representedObject: Any
    ) -> NSMenuItem {
        let item = actionItem(title: title, action: action)
        item.state = checked ? .on : .off
        item.representedObject = representedObject
        return item
    }

    private func submenuItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}
