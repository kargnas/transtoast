import AppKit
import CopyTranslatorCore
import CoreGraphics
import UserNotifications

struct TranslationPreviewPayload: Encodable {
    var mode: String
    var sourceLanguage: String
    var targetLanguage: String
    var originalText: String
    var translatedText: String
    var errorText: String?
    var providerTitle: String
    var model: String
    var costCredits: Double?
    var permissionAction: String? = nil
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let credentialsProvider = CredentialsProvider()
    private let translationService = TranslationService()
    private let requestLogStore = RequestLogStore()
    private let localModelWarmupNotifier = LocalModelWarmupNotifier()
    private var statusItem: NSStatusItem?
    private var keyboardMonitor: KeyboardMonitor?
    private var pasteboardMonitor: PasteboardMonitor?
    private var screenshotHotKey: ScreenshotHotKey?
    private var keepAliveWindow: NSWindow?
    private var lastClipboardTriggerAt: Date?
    private var lastTranslationCaretBounds: CGRect?
    private var currentTextTranslationTask: Task<Void, Never>?
    private var currentScreenshotTranslationTask: Task<Void, Never>?
    private var currentTextTranslationUsesLocalBackend = false
    private var lastReadyLocalModelID: String?
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
        // The Tauri toast writes the global target language to the shared override
        // file; rebuild the menu when that happens so both surfaces stay in sync.
        settingsStore.onExternalChange = { [weak self] in
            self?.rebuildMenu()
        }
        configureStatusItem()
        localModelWarmupNotifier.requestAuthorization()
        startKeyboardMonitor()
        startScreenshotHotKey()
        startPasteboardMonitor()
        print("CopyTranslator ready. Press Cmd+C twice to translate clipboard text.")
        reportKeyboardPermissionStatus(requestIfMissing: false)
        let runsPopoverSmoke = CommandLine.arguments.contains("--show-popover-smoke")
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
        if runsPopoverSmoke {
            showTranslationPopoverSmoke()
        } else if !settingsStore.settings.hasCompletedLocalModelSelection {
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

        menu.addItem(submenuItem(title: "Translation Model", submenu: translationModelMenu()))

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
        currentTextTranslationTask?.cancel()
        currentScreenshotTranslationTask?.cancel()
        showTranslationLoading(originalText: "[screen screenshot]", sourceTitle: "Screenshot")
        let task = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let data = try await ScreenshotCapture.captureMainDisplayPNG()
                guard !Task.isCancelled else {
                    return
                }
                let imageInfo = Self.imageInfo(for: data)
                let result = try await translationService.translateImage(
                    pngData: data,
                    settings: settingsStore.settings,
                    credentials: credentialsProvider.credentials()
                )
                guard !Task.isCancelled else {
                    return
                }
                show(result: result, title: "Screenshot", inputText: "[screen screenshot]", imageInfo: imageInfo)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                show(error: error, title: "Screenshot", inputText: "[screen screenshot]")
            }
        }
        currentScreenshotTranslationTask = task
    }

    private func performTextTranslation(
        _ text: String,
        sourceTitle: String,
        settings overrideSettings: TranslatorSettings? = nil
    ) {
        let settings = overrideSettings ?? settingsStore.settings
        let previousTask = currentTextTranslationTask
        let previousUsesLocalBackend = currentTextTranslationUsesLocalBackend
        let usesLocalBackend = settings.provider == .localHyMT2
        let warmupModel = localWarmupModel(settings: settings)
        let shouldAnnounceWarmup = warmupModel.map { $0.id != lastReadyLocalModelID } ?? false

        previousTask?.cancel()
        currentScreenshotTranslationTask?.cancel()
        currentTextTranslationUsesLocalBackend = usesLocalBackend
        if shouldAnnounceWarmup, let warmupModel {
            localModelWarmupNotifier.warmingUp(modelTitle: warmupModel.title)
        }
        showTranslationLoading(originalText: text, sourceTitle: sourceTitle, settings: settings)
        let task = Task { [weak self] in
            if usesLocalBackend && previousUsesLocalBackend {
                await previousTask?.value
            }
            guard let self else {
                return
            }
            guard !Task.isCancelled else {
                return
            }

            do {
                let screenContext = await contextImagePNGDataIfNeeded(settings: settings)
                guard !Task.isCancelled else {
                    return
                }
                let imageInfo = Self.imageInfo(for: screenContext.pngData, diagnostic: screenContext.diagnostic)
                let result = try await translationService.translateText(
                    text,
                    settings: settings,
                    credentials: credentialsProvider.credentials(),
                    contextImagePNGData: screenContext.pngData
                )
                guard !Task.isCancelled else {
                    return
                }
                if shouldAnnounceWarmup, let warmupModel {
                    lastReadyLocalModelID = warmupModel.id
                    localModelWarmupNotifier.completed(modelTitle: warmupModel.title)
                }
                show(result: result, title: sourceTitle, inputText: text, imageInfo: imageInfo, settings: settings)
            } catch is CancellationError {
                return
            } catch {
                if shouldAnnounceWarmup, let warmupModel {
                    localModelWarmupNotifier.failed(modelTitle: warmupModel.title, error: error)
                }
                show(error: error, title: sourceTitle, inputText: text, settings: settings)
            }
        }
        currentTextTranslationTask = task
    }

    private func contextImagePNGDataIfNeeded(settings: TranslatorSettings) async -> ScreenContextCaptureResult {
        guard settings.provider == .openRouter else {
            return ScreenContextCaptureResult(pngData: nil, diagnostic: nil)
        }

        return await ScreenshotCapture.captureMainDisplayContextPNGIfAvailable()
    }

    @MainActor
    private func show(
        result: TranslationResult,
        title: String,
        inputText: String,
        imageInfo: String?,
        settings: TranslatorSettings? = nil
    ) {
        requestLogStore.add(source: title, input: inputText, result: result, imageInfo: imageInfo)
        showTranslationResult(result, inputText: inputText, settings: settings ?? settingsStore.settings)
    }

    @MainActor
    private func show(
        error: Error,
        title: String,
        inputText: String? = nil,
        settings: TranslatorSettings? = nil
    ) {
        showTranslationError(
            error,
            sourceTitle: title,
            originalText: inputText ?? title,
            settings: settings ?? settingsStore.settings
        )
    }

    private func translationModelMenu() -> NSMenu {
        let menu = NSMenu()
        let localMenu = NSMenu()
        let openRouterMenu = NSMenu()
        let settings = settingsStore.settings
        let defaults = TranslatorSettings()

        localMenu.addItem(checkableItem(
            title: "Default (\(LocalModelRegistry.defaultModel().title))",
            checked: settings.provider == .localHyMT2 && settings.localModelID == defaults.localModelID,
            action: #selector(setTranslationModel(_:)),
            representedObject: "localHyMT2:\(defaults.localModelID)"
        ))
        localMenu.addItem(NSMenuItem.separator())
        for model in prioritizedLocalModels(settings: settings) {
            localMenu.addItem(checkableItem(
                title: model.title,
                checked: settings.provider == .localHyMT2 && settings.localModelID == model.id,
                action: #selector(setTranslationModel(_:)),
                representedObject: "localHyMT2:\(model.id)"
            ))
        }

        openRouterMenu.addItem(checkableItem(
            title: "Default (\(OpenRouterModelCatalog.title(for: defaults.openRouterTextModel)))",
            checked: settings.provider == .openRouter && settings.openRouterTextModel == defaults.openRouterTextModel,
            action: #selector(setTranslationModel(_:)),
            representedObject: "openRouter:\(defaults.openRouterTextModel)"
        ))
        openRouterMenu.addItem(NSMenuItem.separator())
        for model in prioritizedOpenRouterModels(settings: settings) {
            openRouterMenu.addItem(checkableItem(
                title: "\(model.title) · \(model.pricingTitle) · \(model.modalityTitle)",
                checked: settings.provider == .openRouter && settings.openRouterTextModel == model.id,
                action: #selector(setTranslationModel(_:)),
                representedObject: "openRouter:\(model.id)"
            ))
        }

        menu.addItem(submenuItem(title: "Local Model", submenu: localMenu))
        menu.addItem(submenuItem(title: "OpenRouter LLM", submenu: openRouterMenu))
        return menu
    }

    private func prioritizedLocalModels(settings: TranslatorSettings) -> [LocalModelSpec] {
        let models = LocalModelRegistry.models(customModelsPath: settings.customLocalModelsPath)
        return prioritize(models, favorites: settings.favoriteLocalModelIDs, id: \.id)
    }

    private func prioritizedOpenRouterModels(settings: TranslatorSettings) -> [OpenRouterModelSpec] {
        prioritize(OpenRouterModelCatalog.models, favorites: settings.favoriteOpenRouterModels, id: \.id)
    }

    private func prioritize<T>(_ values: [T], favorites: [String], id: KeyPath<T, String>) -> [T] {
        values.sorted { left, right in
            let leftID = left[keyPath: id]
            let rightID = right[keyPath: id]
            let leftFavorite = favorites.firstIndex(of: leftID)
            let rightFavorite = favorites.firstIndex(of: rightID)
            switch (leftFavorite, rightFavorite) {
            case let (left?, right?):
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return leftID < rightID
            }
        }
    }

    @objc private func setTranslationModel(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else {
            return
        }
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let provider = TranslationProvider(rawValue: parts[0]) else {
            return
        }

        var settings = settingsStore.settings
        settings.provider = provider
        switch provider {
        case .localHyMT2:
            settings.localModelID = parts[1]
        case .openRouter:
            settings.openRouterTextModel = parts[1]
        }
        settingsStore.settings = settings
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
        var settings = settingsStore.settings
        settings.toastPosition = position
        if position != .custom {
            settings.toastCustomPosition = nil
        }
        settingsStore.settings = settings
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

    private func showTranslationLoading(
        originalText: String,
        sourceTitle: String,
        settings: TranslatorSettings? = nil
    ) {
        let settings = settings ?? settingsStore.settings
        let languages = resolvedLanguages(for: originalText, settings: settings)
        showTranslationPopover(TranslationPreviewPayload(
            mode: "loading",
            sourceLanguage: languages.sourceLanguage,
            targetLanguage: languages.targetLanguage,
            originalText: originalText,
            translatedText: "",
            errorText: nil,
            providerTitle: settings.provider.title,
            model: activeModelTitle(settings: settings),
            costCredits: nil
        ), sourceTitle: sourceTitle, settings: settings)
    }

    private func showTranslationResult(
        _ result: TranslationResult,
        inputText: String,
        settings: TranslatorSettings? = nil
    ) {
        let settings = settings ?? settingsStore.settings
        let languages = resolvedLanguages(for: inputText, settings: settings)
        showTranslationPopover(TranslationPreviewPayload(
            mode: "translated",
            sourceLanguage: result.sourceLanguage ?? result.detectedSourceLanguage ?? languages.sourceLanguage,
            targetLanguage: result.targetLanguage ?? languages.targetLanguage,
            originalText: inputText,
            translatedText: result.text,
            errorText: nil,
            providerTitle: result.providerTitle,
            model: result.model,
            costCredits: result.usage?.costCredits
        ), sourceTitle: result.providerTitle, settings: settings)
    }

    private func showTranslationError(
        _ error: Error,
        sourceTitle: String,
        originalText: String,
        settings: TranslatorSettings? = nil
    ) {
        let settings = settings ?? settingsStore.settings
        showTranslationPopover(TranslationPreviewPayload(
            mode: "error",
            sourceLanguage: settings.sourceLanguage,
            targetLanguage: settings.targetLanguage,
            originalText: originalText,
            translatedText: "",
            errorText: error.localizedDescription,
            providerTitle: settings.provider.title,
            model: activeModelTitle(settings: settings),
            costCredits: nil,
            permissionAction: permissionAction(for: error)
        ), sourceTitle: sourceTitle, settings: settings)
    }

    private func showTranslationPopoverSmoke() {
        showTranslationPopover(
            TranslationPreviewPayload(
                mode: "loading",
                sourceLanguage: "English",
                targetLanguage: "Korean",
                originalText: "Hover smoke text",
                translatedText: "",
                providerTitle: "Smoke",
                model: "Smoke"
            ),
            sourceTitle: "Smoke"
        )
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            showTranslationPopover(
                TranslationPreviewPayload(
                    mode: "translated",
                    sourceLanguage: "English",
                    targetLanguage: "Korean",
                    originalText: "Hover smoke text",
                    translatedText: "마우스 오버 테스트가 제자리에서 갱신되었습니다.",
                    providerTitle: "Smoke",
                    model: "Smoke"
                ),
                sourceTitle: "Smoke"
            )
        }
    }

    private func showTranslationPopover(
        _ payload: TranslationPreviewPayload,
        sourceTitle: String,
        settings displaySettings: TranslatorSettings? = nil
    ) {
        let caretBounds: CGRect?
        if payload.mode == "loading" {
            caretBounds = KeyboardCaretLocator.focusedTextBounds(for: payload.originalText)
            lastTranslationCaretBounds = caretBounds
        } else {
            caretBounds = lastTranslationCaretBounds
                ?? KeyboardCaretLocator.focusedTextBounds(for: payload.originalText)
        }

        writeTranslationPreviewState(payload)
        // Only the loading frame launches the helper window; the result/error frame just rewrites
        // the file and the helper, which polls while loading, swaps to it in place.
        if payload.mode == "loading" {
            launchTranslationToast(caretBounds: caretBounds)
        }
    }

    private func writeTranslationPreviewState(_ payload: TranslationPreviewPayload) {
        do {
            try SharedAppStorage.ensureDirectoryExists()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: SharedAppStorage.fileURL("translation-preview.json"), options: .atomic)
        } catch {
            print("Could not write translation preview state: \(error.localizedDescription)")
        }
    }

    private func launchTranslationToast(caretBounds: CGRect?) {
        var arguments = ["--translation-preview", "--translation-preview-state=loading"]
        if let caret = translationCaretArgument(for: caretBounds) {
            arguments.append("--translation-preview-caret=\(caret)")
        }
        // A live toast helper polls the state file, so a retry during cold start is absorbed by it.
        // Relaunching here would pkill that still-visible toast and flash-kill it, so reuse instead.
        if isTranslationHelperRunning() {
            return
        }
        _ = launchTauriHelper(
            arguments: arguments,
            activate: false,
            replaceExistingMatching: "--translation-preview"
        )
    }

    private func isTranslationHelperRunning() -> Bool {
        guard let appURL = resolveTauriHelperAppURL() else {
            return false
        }
        let executablePath = appURL
            .appendingPathComponent("Contents/MacOS/copy-translator-tauri")
            .path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "\(executablePath).*--translation-preview"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return !data.isEmpty
    }

    // KeyboardCaretLocator returns AppKit screen coordinates (bottom-left origin). The Rust
    // placement logic works in global Quartz coordinates (top-left origin), so flip Y against the
    // primary display height before handing the caret rect to the Tauri helper.
    private func translationCaretArgument(for caretBounds: CGRect?) -> String? {
        guard let caret = caretBounds,
              let primaryHeight = (NSScreen.screens.first ?? NSScreen.main)?.frame.height else {
            return nil
        }
        let topLeftY = primaryHeight - caret.maxY
        return "\(caret.minX),\(topLeftY),\(caret.width),\(caret.height)"
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
            OpenRouterModelCatalog.title(for: settings.openRouterTextModel)
        }
    }

    private func permissionAction(for error: Error) -> String? {
        guard let screenshotError = error as? ScreenshotCaptureError,
              case .permissionDenied = screenshotError else {
            return nil
        }
        return "screenRecording"
    }

    private func localWarmupModel(settings: TranslatorSettings) -> LocalModelSpec? {
        guard settings.provider == .localHyMT2 else {
            return nil
        }
        return LocalModelRegistry.model(
            id: settings.localModelID,
            customModelsPath: settings.customLocalModelsPath
        ) ?? LocalModelRegistry.defaultModel(customModelsPath: settings.customLocalModelsPath)
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
        return true
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
