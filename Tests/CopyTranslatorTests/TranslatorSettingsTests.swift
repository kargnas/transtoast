import CopyTranslatorCore
import Foundation
import Testing

@Test func defaultsToLocalHyMT230BAndKorean() {
    let settings = TranslatorSettings()

    #expect(settings.provider == .localHyMT2)
    #expect(settings.hyMT2Model == .hyMT2_30B)
    #expect(settings.openRouterTextModel == "google/gemini-2.5-flash-lite")
    #expect(settings.openRouterVisionModel == "google/gemini-2.5-flash-lite")
    #expect(settings.includeScreenContextForLLM == false)
    #expect(settings.targetLanguage == "Korean")
    #expect(settings.toastPosition == .bottomRight)
}

@Test func decodesLegacySettingsWithScreenContextKey() throws {
    let json = """
    {
      "provider": "openRouter",
      "hyMT2Model": "tencent/Hy-MT2-1.8B",
      "openRouterTextModel": "~google/gemini-flash-latest",
      "openRouterVisionModel": "~google/gemini-flash-latest",
      "includeScreenContextForLLM": true,
      "targetLanguage": "Korean",
      "toastPosition": "bottomRight",
      "toastDuration": 6
    }
    """
    let settings = try JSONDecoder().decode(TranslatorSettings.self, from: Data(json.utf8))

    #expect(settings.provider == .openRouter)
    #expect(settings.hyMT2Model == .hyMT2_18B)
    #expect(settings.includeScreenContextForLLM == true)
}

@Test func encodingOmitsDefaultSettings() throws {
    let data = try JSONEncoder().encode(TranslatorSettings())
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object.isEmpty)
}

@Test func encodingPersistsOnlyUserOverrides() throws {
    let settings = TranslatorSettings(
        provider: .openRouter,
        openRouterTextModel: "custom/text-model"
    )
    let data = try JSONEncoder().encode(settings)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["provider"] as? String == "openRouter")
    #expect(object["openRouterTextModel"] as? String == "custom/text-model")
    #expect(object["openRouterVisionModel"] == nil)
    #expect(object["targetLanguage"] == nil)
}

@Test func explicitModelValuesAreNotMigratedOnDecode() throws {
    let json = """
    {
      "openRouterTextModel": "~google/gemini-flash-latest",
      "openRouterVisionModel": "google/gemini-3.1-flash-lite"
    }
    """
    let settings = try JSONDecoder().decode(TranslatorSettings.self, from: Data(json.utf8))

    #expect(settings.openRouterTextModel == "~google/gemini-flash-latest")
    #expect(settings.openRouterVisionModel == "google/gemini-3.1-flash-lite")
}
