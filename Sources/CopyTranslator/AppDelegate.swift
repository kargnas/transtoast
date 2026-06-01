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
    private var tauriSurfaceProcesses: [String: Process] = [:]
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
            showPermissionHelper()
        }
        if CommandLine.arguments.contains("--show-local-model-setup") {
            showLocalModelSetup()
        }
        if CommandLine.arguments.contains("--show-request-logs") {
            showRequestLogs()
        }
        if CommandLine.arguments.contains("--show-stacked-toasts") {
            showStackedTestToasts()
        }
        if !settingsStore.settings.hasCompletedLocalModelSelection {
            showLocalModelSetup()
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
        toastManager.show(
            title: "\(title) · \(result.model)",
            message: result.text,
            description: result.description,
            settings: settingsStore.settings
        )
    }

    @MainActor
    private func show(error: Error, title: String) {
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

    @objc private func showSettingsWindow() {
        _ = openTauriSurface("settings")
    }

    private func openTauriSurface(_ surface: String) -> Bool {
        if let process = tauriSurfaceProcesses[surface] {
            if process.isRunning {
                activateRunningApplication(processIdentifier: process.processIdentifier)
                return true
            }
            tauriSurfaceProcesses[surface] = nil
        }

        guard let executableURL = resolveTauriSettingsExecutableURL() else {
            return false
        }

        let process = Process()
        process.executableURL = executableURL
        if surface != "settings" {
            process.arguments = ["--surface", surface]
        }
        let workspaceRootURL = resolveWorkspaceRootURL()
        process.currentDirectoryURL = workspaceRootURL

        var environment = ProcessInfo.processInfo.environment
        if let workspaceRootURL {
            environment["COPY_TRANSLATOR_WORKSPACE_ROOT"] = workspaceRootURL.path
        }
        process.environment = environment
        process.terminationHandler = { [weak self] finishedProcess in
            Task { @MainActor in
                if self?.tauriSurfaceProcesses[surface] === finishedProcess {
                    self?.tauriSurfaceProcesses[surface] = nil
                }
            }
        }

        do {
            try process.run()
        } catch {
            toastManager.show(
                title: "Settings",
                message: "Could not open Tauri \(surface): \(error.localizedDescription)",
                settings: settingsStore.settings
            )
            return false
        }

        tauriSurfaceProcesses[surface] = process
        activateRunningApplication(processIdentifier: process.processIdentifier)
        return true
    }

    private func resolveTauriSettingsExecutableURL() -> URL? {
        let explicitExecutablePath = argumentValue(after: "--tauri-settings-executable")
        var candidates: [URL] = []
        if let explicitExecutablePath, !explicitExecutablePath.isEmpty {
            candidates.append(URL(fileURLWithPath: explicitExecutablePath))
        }
        if let workspaceRootURL = resolveWorkspaceRootURL() {
            candidates.append(workspaceRootURL.appendingPathComponent("src-tauri/target/debug/copy-translator-tauri"))
            candidates.append(workspaceRootURL.appendingPathComponent("src-tauri/target/release/copy-translator-tauri"))
        }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func resolveWorkspaceRootURL() -> URL? {
        var candidates: [URL] = []
        if let workspaceRootPath = argumentValue(after: "--workspace-root"),
           !workspaceRootPath.isEmpty {
            candidates.append(URL(fileURLWithPath: workspaceRootPath))
        }
        if let workspaceRootPath = ProcessInfo.processInfo.environment["COPY_TRANSLATOR_WORKSPACE_ROOT"],
           !workspaceRootPath.isEmpty {
            candidates.append(URL(fileURLWithPath: workspaceRootPath))
        }
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        candidates.append(Bundle.main.bundleURL)
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL)
        }

        for candidate in candidates {
            if let rootURL = firstAncestorWithPackageManifest(from: candidate) {
                return rootURL
            }
        }
        return nil
    }

    private func firstAncestorWithPackageManifest(from url: URL) -> URL? {
        var candidate = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
           !isDirectory.boolValue {
            candidate.deleteLastPathComponent()
        }

        while true {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) {
                return candidate
            }

            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return nil
            }
            candidate = parent
        }
    }

    private func activateRunningApplication(processIdentifier: pid_t) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSRunningApplication(processIdentifier: processIdentifier)?
                .activate(options: [])
        }
    }

    @objc private func showLocalModelSetup() {
        _ = openTauriSurface("local-model-setup")
    }

    @objc private func showRequestLogs() {
        _ = openTauriSurface("request-logs")
    }

    private func showStackedTestToasts() {
        _ = openTauriSurface("toast-stack")
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

    @objc private func showPermissionHelper() {
        _ = openTauriSurface("permission-helper")
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
