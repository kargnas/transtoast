import CCTransCore
import Foundation
import Testing

// Echoes its inputs so tests can assert the resolved language codes without
// shared mutable state (the protocol requires Sendable).
private struct EchoBackend: AppleTranslationBacking {
    func translate(text: String, sourceLanguageCode: String?, targetLanguageCode: String) async throws -> String {
        "[\(sourceLanguageCode ?? "auto")->\(targetLanguageCode)] \(text)"
    }
}

private func appleSettings(source: String = TranslationLanguage.auto, target: String = "Korean") -> TranslatorSettings {
    var settings = TranslatorSettings()
    settings.provider = .appleTranslation
    settings.sourceLanguage = source
    settings.targetLanguage = target
    return settings
}

private let noCredentials = TranslatorCredentials(openRouterAPIKey: nil, huggingFaceToken: nil)

@Test func appleProviderMapsLanguageNamesToBCP47Codes() async throws {
    let service = TranslationService(appleBackend: EchoBackend())
    let result = try await service.translateText(
        "Hello there",
        settings: appleSettings(source: "English", target: "Korean"),
        credentials: noCredentials
    )

    #expect(result.text == "[en->ko] Hello there")
    #expect(result.providerTitle == "Apple Translation")
    #expect(result.model == "apple/translation")
}

@Test func appleProviderReversesTargetWhenSourceMatches() async throws {
    let service = TranslationService(appleBackend: EchoBackend())
    // Korean input with a Korean target must flip to English, mirroring the
    // resolver behavior the other providers rely on.
    let result = try await service.translateText(
        "안녕하세요 반갑습니다",
        settings: appleSettings(target: "Korean"),
        credentials: noCredentials
    )

    #expect(result.text == "[ko->en] 안녕하세요 반갑습니다")
    #expect(result.detectedSourceLanguage == "Korean")
}

@Test func appleProviderFailsClearlyWithoutBackend() async {
    let service = TranslationService()
    await #expect(throws: TranslationError.self) {
        try await service.translateText(
            "Hello there",
            settings: appleSettings(source: "English"),
            credentials: noCredentials
        )
    }
}

@Test func appleProviderRejectsUnsupportedTargetName() async {
    let service = TranslationService(appleBackend: EchoBackend())
    await #expect(throws: TranslationError.self) {
        try await service.translateText(
            "Hello there",
            settings: appleSettings(source: "English", target: "Klingon"),
            credentials: noCredentials
        )
    }
}
