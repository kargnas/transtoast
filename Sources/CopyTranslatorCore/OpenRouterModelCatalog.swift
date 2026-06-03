import Foundation

public struct OpenRouterModelSpec: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var promptPricePerMillion: Double
    public var completionPricePerMillion: Double
    public var inputModalities: [String]
    public var isFree: Bool
    public var isRecommended: Bool

    public init(
        id: String,
        title: String,
        promptPricePerMillion: Double,
        completionPricePerMillion: Double,
        inputModalities: [String],
        isFree: Bool = false,
        isRecommended: Bool = false
    ) {
        self.id = id
        self.title = title
        self.promptPricePerMillion = promptPricePerMillion
        self.completionPricePerMillion = completionPricePerMillion
        self.inputModalities = inputModalities
        self.isFree = isFree
        self.isRecommended = isRecommended
    }

    public var supportsVision: Bool {
        inputModalities.contains("image")
    }

    public var modalityTitle: String {
        supportsVision ? "Text + Image" : "Text"
    }

    public var pricingTitle: String {
        if isFree {
            return "Free"
        }
        return "$\(Self.formatPrice(promptPricePerMillion)) input / $\(Self.formatPrice(completionPricePerMillion)) output per 1M"
    }

    private static func formatPrice(_ value: Double) -> String {
        let formatted = String(format: value < 1 ? "%.2f" : "%.1f", value)
        var trimmed = formatted
        while trimmed.contains(".") && trimmed.last == "0" {
            trimmed.removeLast()
        }
        if trimmed.last == "." {
            trimmed.removeLast()
        }
        return trimmed
    }
}

public enum OpenRouterModelCatalog {
    public static let defaultModelID = TranslatorSettings.defaultOpenRouterModel

    public static let models: [OpenRouterModelSpec] = [
        OpenRouterModelSpec(
            id: "google/gemini-2.5-flash-lite",
            title: "Google Gemini 2.5 Flash Lite",
            promptPricePerMillion: 0.10,
            completionPricePerMillion: 0.40,
            inputModalities: ["text", "image", "file", "audio", "video"],
            isRecommended: true
        ),
        OpenRouterModelSpec(
            id: "google/gemini-2.5-flash",
            title: "Google Gemini 2.5 Flash",
            promptPricePerMillion: 0.30,
            completionPricePerMillion: 2.50,
            inputModalities: ["text", "image", "file", "audio", "video"]
        ),
        OpenRouterModelSpec(
            id: "openai/gpt-4o-mini",
            title: "OpenAI GPT-4o mini",
            promptPricePerMillion: 0.15,
            completionPricePerMillion: 0.60,
            inputModalities: ["text", "image", "file"]
        ),
        OpenRouterModelSpec(
            id: "anthropic/claude-3.5-haiku",
            title: "Anthropic Claude 3.5 Haiku",
            promptPricePerMillion: 0.80,
            completionPricePerMillion: 4.00,
            inputModalities: ["text", "image"]
        ),
        OpenRouterModelSpec(
            id: "qwen/qwen3-vl-8b-instruct",
            title: "Qwen3 VL 8B Instruct",
            promptPricePerMillion: 0.08,
            completionPricePerMillion: 0.50,
            inputModalities: ["text", "image"]
        ),
        OpenRouterModelSpec(
            id: "openrouter/free",
            title: "OpenRouter Free Models Router",
            promptPricePerMillion: 0,
            completionPricePerMillion: 0,
            inputModalities: ["text", "image"],
            isFree: true
        ),
        OpenRouterModelSpec(
            id: "openai/gpt-oss-20b:free",
            title: "OpenAI gpt-oss-20b (free)",
            promptPricePerMillion: 0,
            completionPricePerMillion: 0,
            inputModalities: ["text"],
            isFree: true
        ),
        OpenRouterModelSpec(
            id: "meta-llama/llama-3.3-70b-instruct:free",
            title: "Meta Llama 3.3 70B Instruct (free)",
            promptPricePerMillion: 0,
            completionPricePerMillion: 0,
            inputModalities: ["text"],
            isFree: true
        ),
    ]

    public static func model(id: String) -> OpenRouterModelSpec? {
        models.first { $0.id == id }
    }

    public static func title(for id: String) -> String {
        model(id: id)?.title ?? id
    }
}
