import AppKit
import CopyTranslatorCore

func argumentValue(after flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag) else {
        return nil
    }
    let valueIndex = CommandLine.arguments.index(after: index)
    guard CommandLine.arguments.indices.contains(valueIndex) else {
        return nil
    }
    return CommandLine.arguments[valueIndex]
}

func oneShotSettings(defaultProvider: TranslationProvider) -> TranslatorSettings {
    var settings = TranslatorSettings(provider: defaultProvider)

    if let provider = argumentValue(after: "--provider") {
        switch provider {
        case "local-hymt2":
            settings.provider = .localHyMT2
        case "openrouter":
            settings.provider = .openRouter
        default:
            break
        }
    }

    if let modelID = argumentValue(after: "--hy-mt2-model"),
       let model = HyMT2Model(rawValue: modelID) {
        settings.hyMT2Model = model
    }

    if let modelID = argumentValue(after: "--openrouter-text-model") {
        settings.openRouterTextModel = modelID
    }

    if let modelID = argumentValue(after: "--openrouter-vision-model") {
        settings.openRouterVisionModel = modelID
    }

    if let language = argumentValue(after: "--target-language") {
        settings.targetLanguage = language
    }

    return settings
}

if CommandLine.arguments.contains("--translate-text-once") {
    let text = argumentValue(after: "--translate-text-once") ?? ""
    let settings = oneShotSettings(defaultProvider: .localHyMT2)
    let credentials = CredentialsProvider().credentials()
    let result = try await TranslationService().translateText(text, settings: settings, credentials: credentials)
    print(result.text)
    exit(0)
}

if CommandLine.arguments.contains("--screenshot-once") {
    let settings = oneShotSettings(defaultProvider: .openRouter)
    let credentials = CredentialsProvider().credentials()
    let data = try await ScreenshotCapture.captureMainDisplayPNG()
    let result = try await TranslationService().translateImage(pngData: data, settings: settings, credentials: credentials)
    print(result.text)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
