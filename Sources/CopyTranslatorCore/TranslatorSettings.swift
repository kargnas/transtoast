import Foundation

public enum TranslationProvider: String, CaseIterable, Codable, Sendable {
    case localHyMT2
    case openRouter

    public var title: String {
        switch self {
        case .localHyMT2: "Local Hy-MT2"
        case .openRouter: "OpenRouter LLM"
        }
    }
}

public enum HyMT2Model: String, CaseIterable, Codable, Sendable {
    case hyMT2_30B = "tencent/Hy-MT2-30B-A3B"
    case hyMT2_18B = "tencent/Hy-MT2-1.8B"

    public var title: String {
        switch self {
        case .hyMT2_30B: "Hy-MT2 30B-A3B"
        case .hyMT2_18B: "Hy-MT2 1.8B"
        }
    }

    public var temperature: Double {
        switch self {
        case .hyMT2_30B, .hyMT2_18B:
            0.7
        }
    }

    public var topP: Double {
        switch self {
        case .hyMT2_30B:
            1.0
        case .hyMT2_18B:
            0.6
        }
    }
}

public enum ToastPosition: String, CaseIterable, Codable, Sendable {
    case bottomRight
    case bottomLeft
    case topRight
    case topLeft

    public var title: String {
        switch self {
        case .bottomRight: "Bottom Right"
        case .bottomLeft: "Bottom Left"
        case .topRight: "Top Right"
        case .topLeft: "Top Left"
        }
    }
}

public struct TranslatorSettings: Codable, Equatable, Sendable {
    public static let defaultOpenRouterModel = "google/gemini-3.1-flash-lite"
    public static let legacyDefaultOpenRouterModels: Set<String> = [
        "~google/gemini-flash-latest",
        "google/gemini-2.5-flash-lite",
    ]

    public var provider: TranslationProvider
    public var hyMT2Model: HyMT2Model
    public var localHyMT2BackendPath: String?
    public var openRouterTextModel: String
    public var openRouterVisionModel: String
    // Kept so older saved settings decode cleanly; the app now attaches OpenRouter screen context automatically when trusted.
    public var includeScreenContextForLLM: Bool
    public var targetLanguage: String
    public var toastPosition: ToastPosition
    public var toastDuration: TimeInterval

    public init(
        provider: TranslationProvider = .localHyMT2,
        hyMT2Model: HyMT2Model = .hyMT2_30B,
        localHyMT2BackendPath: String? = nil,
        openRouterTextModel: String = Self.defaultOpenRouterModel,
        openRouterVisionModel: String = Self.defaultOpenRouterModel,
        includeScreenContextForLLM: Bool = false,
        targetLanguage: String = "Korean",
        toastPosition: ToastPosition = .bottomRight,
        toastDuration: TimeInterval = 6
    ) {
        self.provider = provider
        self.hyMT2Model = hyMT2Model
        self.localHyMT2BackendPath = localHyMT2BackendPath
        self.openRouterTextModel = openRouterTextModel
        self.openRouterVisionModel = openRouterVisionModel
        self.includeScreenContextForLLM = includeScreenContextForLLM
        self.targetLanguage = targetLanguage
        self.toastPosition = toastPosition
        self.toastDuration = toastDuration
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case hyMT2Model
        case localHyMT2BackendPath
        case openRouterTextModel
        case openRouterVisionModel
        case includeScreenContextForLLM
        case targetLanguage
        case toastPosition
        case toastDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(TranslationProvider.self, forKey: .provider) ?? .localHyMT2
        hyMT2Model = try container.decodeIfPresent(HyMT2Model.self, forKey: .hyMT2Model) ?? .hyMT2_30B
        localHyMT2BackendPath = try container.decodeIfPresent(String.self, forKey: .localHyMT2BackendPath)
        openRouterTextModel = try container.decodeIfPresent(String.self, forKey: .openRouterTextModel) ?? Self.defaultOpenRouterModel
        openRouterVisionModel = try container.decodeIfPresent(String.self, forKey: .openRouterVisionModel) ?? Self.defaultOpenRouterModel
        includeScreenContextForLLM = try container.decodeIfPresent(Bool.self, forKey: .includeScreenContextForLLM) ?? false
        targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "Korean"
        toastPosition = try container.decodeIfPresent(ToastPosition.self, forKey: .toastPosition) ?? .bottomRight
        toastDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .toastDuration) ?? 6
    }

    public mutating func migrateLegacyDefaultOpenRouterModels() -> Bool {
        var changed = false
        if Self.legacyDefaultOpenRouterModels.contains(openRouterTextModel) {
            openRouterTextModel = Self.defaultOpenRouterModel
            changed = true
        }
        if Self.legacyDefaultOpenRouterModels.contains(openRouterVisionModel) {
            openRouterVisionModel = Self.defaultOpenRouterModel
            changed = true
        }
        return changed
    }
}

public struct TranslatorCredentials: Equatable, Sendable {
    public var openRouterAPIKey: String?
    public var huggingFaceToken: String?

    public init(openRouterAPIKey: String?, huggingFaceToken: String?) {
        self.openRouterAPIKey = openRouterAPIKey?.nilIfBlank
        self.huggingFaceToken = huggingFaceToken?.nilIfBlank
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
