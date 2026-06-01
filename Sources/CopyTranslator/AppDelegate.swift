import AppKit
import ApplicationServices
import CopyTranslatorCore
import CoreGraphics

private struct TranslationPreviewPayload: Encodable {
    var mode: String
    var sourceLanguage: String
    var targetLanguage: String
    var originalText: String
    var translatedText: String
    var errorText: String?
    var providerTitle: String
    var model: String
}

private struct ScreenRectArgument {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var value: String {
        [x, y, width, height]
            .map { String(format: "%.3f", Double($0)) }
            .joined(separator: ",")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let credentialsProvider = CredentialsProvider()
    private let translationService = TranslationService()
    private let requestLogStore = RequestLogStore()
    private var statusItem: NSStatusItem?
    private var keyboardMonitor: KeyboardMonitor?
    private var pasteboardMonitor: PasteboardMonitor?
    private var screenshotHotKey: ScreenshotHotKey?
    private var keepAliveWindow: NSWindow?
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
        print("CopyTranslator ready. Press Cmd+C twice to translate clipboard text.")
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
            print("Could not register Shift+Cmd+2. Carbon status: \(status)")
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
        showTranslationLoading(originalText: "[screen screenshot]", sourceTitle: "Screenshot")
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
        showTranslationLoading(originalText: text, sourceTitle: sourceTitle)
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
        showTranslationResult(result, inputText: inputText)
    }

    @MainActor
    private func show(error: Error, title: String) {
        showTranslationError(error, sourceTitle: title)
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
        launchTauriHelper(
            arguments: ["--surface", surface],
            activate: true,
            replaceExistingMatching: "--surface \(surface)"
        )
    }

    private func showTranslationLoading(originalText: String, sourceTitle: String) {
        let settings = settingsStore.settings
        let languages = resolvedLanguages(for: originalText, settings: settings)
        showTranslationPopover(TranslationPreviewPayload(
            mode: "loading",
            sourceLanguage: languages.sourceLanguage,
            targetLanguage: languages.targetLanguage,
            originalText: originalText,
            translatedText: "",
            errorText: nil,
            providerTitle: settings.provider.title,
            model: activeModelTitle(settings: settings)
        ), sourceTitle: sourceTitle)
    }

    private func showTranslationResult(_ result: TranslationResult, inputText: String) {
        let settings = settingsStore.settings
        let languages = resolvedLanguages(for: inputText, settings: settings)
        showTranslationPopover(TranslationPreviewPayload(
            mode: "translated",
            sourceLanguage: result.sourceLanguage ?? result.detectedSourceLanguage ?? languages.sourceLanguage,
            targetLanguage: result.targetLanguage ?? languages.targetLanguage,
            originalText: inputText,
            translatedText: result.text,
            errorText: nil,
            providerTitle: result.providerTitle,
            model: result.model
        ), sourceTitle: result.providerTitle)
    }

    private func showTranslationError(_ error: Error, sourceTitle: String) {
        let settings = settingsStore.settings
        showTranslationPopover(TranslationPreviewPayload(
            mode: "error",
            sourceLanguage: settings.sourceLanguage,
            targetLanguage: settings.targetLanguage,
            originalText: sourceTitle,
            translatedText: "",
            errorText: error.localizedDescription,
            providerTitle: settings.provider.title,
            model: activeModelTitle(settings: settings)
        ), sourceTitle: sourceTitle)
    }

    private func showTranslationPopover(_ payload: TranslationPreviewPayload, sourceTitle: String) {
        do {
            try writeTranslationPreviewPayload(payload)
        } catch {
            print("Could not write translation preview for \(sourceTitle): \(error.localizedDescription)")
            return
        }

        guard launchTranslationPopover(mode: payload.mode) else {
            print("Could not launch Tauri translation popover for \(sourceTitle).")
            return
        }
    }

    private func writeTranslationPreviewPayload(_ payload: TranslationPreviewPayload) throws {
        try SharedAppStorage.ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(payload).write(
            to: SharedAppStorage.fileURL("translation-preview.json"),
            options: [.atomic]
        )
    }

    private func launchTranslationPopover(mode: String) -> Bool {
        var arguments = [
            "--translation-preview",
            "--translation-preview-state=\(mode)",
        ]
        if let caretBounds = focusedTextCaretBounds() {
            arguments.append("--translation-preview-caret=\(ScreenRectArgument(caretBounds).value)")
        }

        return launchTauriHelper(
            arguments: arguments,
            activate: false,
            replaceExistingMatching: "--translation-preview"
        )
    }

    private func focusedTextCaretBounds() -> CGRect? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        ) == .success,
            let focusedObject
        else {
            return nil
        }
        let focusedElement = focusedObject as! AXUIElement

        var selectedRangeObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeObject
        ) == .success,
            let selectedRange = selectedRangeObject
        else {
            return nil
        }

        var boundsObject: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange,
            &boundsObject
        ) == .success,
            let boundsObject,
            CFGetTypeID(boundsObject) == AXValueGetTypeID()
        else {
            return nil
        }
        let boundsValue = boundsObject as! AXValue
        guard AXValueGetType(boundsValue) == .cgRect else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue, .cgRect, &rect),
              rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.width.isFinite,
              rect.height.isFinite,
              rect.width >= 0,
              rect.height > 0
        else {
            return nil
        }

        return tauriScreenRect(fromAccessibilityRect: rect)
    }

    private func tauriScreenRect(fromAccessibilityRect rect: CGRect) -> CGRect {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            return rect
        }

        let displayBounds = CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
        let x = displayBounds.minX + (rect.minX - screen.frame.minX)
        let y = displayBounds.maxY - (rect.minY - screen.frame.minY) - rect.height
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    private func resolvedLanguages(
        for text: String,
        settings: TranslatorSettings
    ) -> ResolvedTranslationLanguages {
        TranslationLanguageResolver.resolve(
            text: text,
            sourceLanguage: settings.sourceLanguage,
            targetLanguage: settings.targetLanguage
        )
    }

    private func activeModelTitle(settings: TranslatorSettings) -> String {
        switch settings.provider {
        case .localHyMT2:
            LocalModelRegistry.model(
                id: settings.localModelID,
                customModelsPath: settings.customLocalModelsPath
            )?.title ?? settings.localModelID
        case .openRouter:
            settings.openRouterTextModel
        }
    }

    private func launchTauriHelper(
        arguments: [String],
        activate: Bool,
        replaceExistingMatching match: String
    ) -> Bool {
        guard let appURL = resolveTauriHelperAppURL() else {
            return false
        }

        terminateTauriHelper(appURL: appURL, matching: match)

        let previousFrontmostApplication = activate ? nil : NSWorkspace.shared.frontmostApplication
        let helperBundleIdentifier = Bundle(url: appURL)?.bundleIdentifier
        var launchArguments = arguments
        if let workspaceRootURL = resolveWorkspaceRootURL() {
            launchArguments.append(contentsOf: ["--workspace-root", workspaceRootURL.path])
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        configuration.createsNewApplicationInstance = true
        configuration.arguments = launchArguments
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                print("Could not open Tauri helper app: \(error.localizedDescription)")
            }
        }
        if !activate {
            restoreFrontmostApplication(
                previousFrontmostApplication,
                helperBundleIdentifier: helperBundleIdentifier
            )
        }
        return true
    }

    private func restoreFrontmostApplication(
        _ application: NSRunningApplication?,
        helperBundleIdentifier: String?
    ) {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let guardedBundleIdentifiers = Set(
            [helperBundleIdentifier, ownBundleIdentifier].compactMap { $0 }
        )
        let guardedNames = Set(["CopyTranslator", "CopyTranslatorTauri", "copy-translator-tauri"])

        for delay in [0.05, 0.15, 0.35, 0.75] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
                    return
                }

                let frontmostBundleIdentifier = frontmostApplication.bundleIdentifier
                let frontmostName = frontmostApplication.localizedName
                let didHelperTakeFocus = frontmostBundleIdentifier.map(guardedBundleIdentifiers.contains) ?? false
                    || frontmostName.map(guardedNames.contains) ?? false

                guard didHelperTakeFocus else {
                    return
                }

                application?.activate(options: [])
            }
        }
    }

    private func terminateTauriHelper(appURL: URL, matching match: String) {
        let executablePath = appURL
            .appendingPathComponent("Contents/MacOS/copy-translator-tauri")
            .path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-f", "\(executablePath).*\(match)"]
        try? process.run()
    }

    private func resolveTauriHelperAppURL() -> URL? {
        let explicitAppPath = argumentValue(after: "--tauri-helper-app")
        var candidates: [URL] = []
        if let explicitAppPath, !explicitAppPath.isEmpty {
            candidates.append(URL(fileURLWithPath: explicitAppPath))
        }
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("CopyTranslatorTauri.app", isDirectory: true))
            candidates.append(resourceURL.appendingPathComponent("CopyTranslator.app", isDirectory: true))
        }
        if let workspaceRootURL = resolveWorkspaceRootURL() {
            candidates.append(workspaceRootURL.appendingPathComponent("src-tauri/target/debug/bundle/macos/CopyTranslator.app", isDirectory: true))
            candidates.append(workspaceRootURL.appendingPathComponent("src-tauri/target/release/bundle/macos/CopyTranslator.app", isDirectory: true))
        }

        return candidates.first { candidate in
            FileManager.default.isExecutableFile(
                atPath: candidate.appendingPathComponent("Contents/MacOS/copy-translator-tauri").path
            )
        }
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
        print("Opened Input Monitoring settings.")
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        print("Opened Accessibility settings.")
    }

    @objc private func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
        print("Opened Screen Recording settings.")
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
            print("Global keyboard monitoring is available.")
            return
        }

        if requestIfMissing {
            _ = CGRequestListenEventAccess()
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        print("Keyboard permission needed. Enable Input Monitoring or Accessibility for CopyTranslator, then relaunch the app.")
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
