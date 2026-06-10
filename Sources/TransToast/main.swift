import AppKit
import TransToastCore

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
        case "local", "local-hymt2":
            settings.provider = .localHyMT2
        case "openrouter":
            settings.provider = .openRouter
        default:
            break
        }
    }

    if let modelID = argumentValue(after: "--local-model") {
        settings.localModelID = modelID
    }

    if let modelID = argumentValue(after: "--hy-mt2-model"),
       let model = HyMT2Model(rawValue: modelID) {
        settings.hyMT2Model = model
        settings.localModelID = LocalModelRegistry.legacyModelID(for: model)
    }

    if let backendPath = argumentValue(after: "--local-backend") {
        settings.localHyMT2BackendPath = backendPath
    }

    if let customModelsPath = argumentValue(after: "--custom-local-models") {
        settings.customLocalModelsPath = customModelsPath
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

    if let language = argumentValue(after: "--source-language") {
        settings.sourceLanguage = language
    }

    return settings
}

if CommandLine.arguments.contains("--list-local-models") {
    let settings = oneShotSettings(defaultProvider: .localHyMT2)
    let models = LocalModelRegistry.models(customModelsPath: settings.customLocalModelsPath)
    let data = try JSONEncoder().encode(models)
    print(String(data: data, encoding: .utf8) ?? "[]")
    exit(0)
}

if CommandLine.arguments.contains("--benchmark-local-models") {
    let baseSettings = oneShotSettings(defaultProvider: .localHyMT2)
    let requestedSource = argumentValue(after: "--source-language") ?? "English"
    let requestedTarget = argumentValue(after: "--target-language") ?? baseSettings.targetLanguage
    let sourceLanguage = TranslationLanguage.normalizedName(requestedSource)
    let targetLanguage = TranslationLanguage.normalizedName(requestedTarget)
    let sampleLimit = Int(argumentValue(after: "--sample-limit") ?? "") ?? 9
    let selectedModelIDs = argumentValue(after: "--local-models")?
        .split(separator: ",")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    let models = if let selectedModelIDs, !selectedModelIDs.isEmpty {
        selectedModelIDs.compactMap { LocalModelRegistry.model(id: $0, customModelsPath: baseSettings.customLocalModelsPath) }
    } else {
        LocalModelRegistry.benchmarkModels(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            customModelsPath: baseSettings.customLocalModelsPath
        )
    }
    let samples = Array(TranslationBenchmarkSamples.samples(sourceLanguage: sourceLanguage).prefix(sampleLimit))
    let credentials = CredentialsProvider().credentials()
    let service = TranslationService()

    for model in models {
        print("## \(model.title) [\(model.id)]")
        for sample in samples {
            var settings = baseSettings
            settings.provider = .localHyMT2
            settings.localModelID = model.id
            settings.sourceLanguage = sourceLanguage
            settings.targetLanguage = targetLanguage
            do {
                let result = try await service.translateText(sample.text, settings: settings, credentials: credentials)
                print("### \(sample.title)")
                print(result.text)
            } catch {
                print("### \(sample.title)")
                print("ERROR: \(error.localizedDescription)")
            }
        }
    }
    exit(0)
}

if CommandLine.arguments.contains("--translate-text-once") {
    let text = argumentValue(after: "--translate-text-once") ?? ""
    let settings = oneShotSettings(defaultProvider: .localHyMT2)
    let credentials = CredentialsProvider().credentials()
    let contextImagePNGData: Data? = if CommandLine.arguments.contains("--with-screen-context") {
        try await ScreenshotCapture.captureMainDisplayContextPNG()
    } else {
        nil
    }
    let result = try await TranslationService().translateText(
        text,
        settings: settings,
        credentials: credentials,
        contextImagePNGData: contextImagePNGData
    )
    print(result.text)
    if let description = result.description {
        print(description)
    }
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
