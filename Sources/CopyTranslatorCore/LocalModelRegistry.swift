import Foundation

public enum LocalRuntimeKind: String, CaseIterable, Codable, Sendable {
    case transformers
    case mlxLM = "mlx-lm"
    case ctranslate2
    case llamaCPP = "llama.cpp"
    case madladSwift = "madlad-swift"
    case customProcess = "custom-process"

    public var title: String {
        switch self {
        case .transformers: "Transformers"
        case .mlxLM: "MLX LM"
        case .ctranslate2: "CTranslate2"
        case .llamaCPP: "llama.cpp"
        case .madladSwift: "MADLAD Swift"
        case .customProcess: "Custom Process"
        }
    }

    public var bundledBackendScript: String? {
        switch self {
        case .transformers:
            "hy_mt2_translate.py"
        case .mlxLM:
            "runtimes/mlx_lm_translate.py"
        case .ctranslate2, .llamaCPP, .madladSwift, .customProcess:
            nil
        }
    }
}

public struct LocalModelSpec: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var runtime: LocalRuntimeKind
    public var modelID: String
    public var artifactName: String?
    public var supportedSourceLanguages: [String]
    public var supportedTargetLanguages: [String]
    public var qualityNote: String
    public var licenseNote: String?
    public var isRecommended: Bool
    public var includeInFirstRunBenchmark: Bool
    public var customBackendPath: String?
    public var setupCommand: [String]?

    public init(
        id: String,
        title: String,
        runtime: LocalRuntimeKind,
        modelID: String,
        artifactName: String? = nil,
        supportedSourceLanguages: [String],
        supportedTargetLanguages: [String],
        qualityNote: String,
        licenseNote: String? = nil,
        isRecommended: Bool = false,
        includeInFirstRunBenchmark: Bool = false,
        customBackendPath: String? = nil,
        setupCommand: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.runtime = runtime
        self.modelID = modelID
        self.artifactName = artifactName
        self.supportedSourceLanguages = supportedSourceLanguages
        self.supportedTargetLanguages = supportedTargetLanguages
        self.qualityNote = qualityNote
        self.licenseNote = licenseNote
        self.isRecommended = isRecommended
        self.includeInFirstRunBenchmark = includeInFirstRunBenchmark
        self.customBackendPath = customBackendPath
        self.setupCommand = setupCommand
    }

    public func supports(sourceLanguage: String, targetLanguage: String) -> Bool {
        languageList(supportedSourceLanguages, contains: sourceLanguage)
            && languageList(supportedTargetLanguages, contains: targetLanguage)
    }

    public var backendScriptName: String? {
        customBackendPath ?? runtime.bundledBackendScript
    }
}

public enum LocalModelRegistry {
    public static let defaultModelID = "hymt2-mlx-1.8b-4bit"

    public static let builtInModels: [LocalModelSpec] = [
        LocalModelSpec(
            id: "hymt2-mlx-1.8b-4bit",
            title: "Hy-MT2 1.8B 4-bit (MLX)",
            runtime: .mlxLM,
            modelID: "mlx-community/Hy-MT2-1.8B-4bit",
            supportedSourceLanguages: ["Any"],
            supportedTargetLanguages: TranslationLanguage.targetLanguageNames,
            qualityNote: "Best tested local default: good quality, Apple Silicon friendly.",
            licenseNote: "Tencent Hy-MT2 terms apply.",
            isRecommended: true,
            includeInFirstRunBenchmark: true
        ),
        LocalModelSpec(
            id: "hymt2-transformers-1.8b",
            title: "Hy-MT2 1.8B (Transformers)",
            runtime: .transformers,
            modelID: "tencent/Hy-MT2-1.8B",
            supportedSourceLanguages: ["Any"],
            supportedTargetLanguages: TranslationLanguage.targetLanguageNames,
            qualityNote: "Works through the legacy Python backend; slower than MLX on this Mac.",
            licenseNote: "Tencent Hy-MT2 terms apply.",
            includeInFirstRunBenchmark: true
        ),
        LocalModelSpec(
            id: "hymt2-transformers-30b",
            title: "Hy-MT2 30B-A3B (Transformers)",
            runtime: .transformers,
            modelID: "tencent/Hy-MT2-30B-A3B",
            supportedSourceLanguages: ["Any"],
            supportedTargetLanguages: TranslationLanguage.targetLanguageNames,
            qualityNote: "High quality but too heavy for most local first-run tests.",
            licenseNote: "Tencent Hy-MT2 terms apply."
        ),
        LocalModelSpec(
            id: "hymt2-gguf-iq4-xs",
            title: "Hy-MT2 1.8B IQ4_XS (GGUF)",
            runtime: .llamaCPP,
            modelID: "lmstudio-community/Hy-MT2-1.8B-GGUF",
            artifactName: "Hy-MT2-1.8B-IQ4_XS.gguf",
            supportedSourceLanguages: ["Any"],
            supportedTargetLanguages: TranslationLanguage.targetLanguageNames,
            qualityNote: "Good candidate for future llama.cpp support; not bundled yet.",
            licenseNote: "Tencent Hy-MT2 terms apply."
        ),
        LocalModelSpec(
            id: "lfm2-koen-q4-k-m",
            title: "LFM2 Ko-En Q4_K_M (GGUF)",
            runtime: .llamaCPP,
            modelID: "jhj0517/lfm2-700m-ko-en-translation-gguf",
            artifactName: "lfm2-ko-en-Q4_K_M.gguf",
            supportedSourceLanguages: ["Korean", "English"],
            supportedTargetLanguages: ["English", "Korean"],
            qualityNote: "Fast Korean-English candidate; needs license and llama.cpp integration review."
        ),
        LocalModelSpec(
            id: "nllb-ct2-int8",
            title: "NLLB CTranslate2 int8",
            runtime: .ctranslate2,
            modelID: "facebook/nllb-200-distilled-600M",
            supportedSourceLanguages: ["Any"],
            supportedTargetLanguages: TranslationLanguage.targetLanguageNames,
            qualityNote: "Broad language coverage candidate; adapter is planned, not bundled."
        ),
        LocalModelSpec(
            id: "quickmt-en-ko",
            title: "QuickMT En-Ko",
            runtime: .transformers,
            modelID: "quickmt/quickmt-en-ko",
            supportedSourceLanguages: ["English", "Korean"],
            supportedTargetLanguages: ["Korean", "English"],
            qualityNote: "Sentence-level candidate only; benchmark showed weak fragment behavior."
        ),
        LocalModelSpec(
            id: "kanana-lora-koen",
            title: "Kanana 1.5 2.1B AIHub Ko-En LoRA",
            runtime: .customProcess,
            modelID: "harveykim/kanana-1.5-2.1b-aihub-ko-en-lora",
            supportedSourceLanguages: ["English", "Korean"],
            supportedTargetLanguages: ["Korean", "English"],
            qualityNote: "Retry succeeded with pinned Transformers/PEFT; dependency fragile.",
            licenseNote: "CC-BY-NC; disabled by default for commercial ambiguity."
        ),
        LocalModelSpec(
            id: "madlad-swift-int4",
            title: "MADLAD-400 Swift int4",
            runtime: .madladSwift,
            modelID: "soniqo/speech-swift-madlad400",
            supportedSourceLanguages: ["Any"],
            supportedTargetLanguages: TranslationLanguage.targetLanguageNames,
            qualityNote: "Official Swift runtime built, but MLX Swift metallib loading failed on this host."
        ),
    ]

    public static func model(id: String, customModelsPath: String? = nil) -> LocalModelSpec? {
        models(customModelsPath: customModelsPath).first { $0.id == id }
    }

    public static func models(customModelsPath: String? = nil) -> [LocalModelSpec] {
        builtInModels + loadCustomModels(path: customModelsPath)
    }

    public static func defaultModel(customModelsPath: String? = nil) -> LocalModelSpec {
        model(id: defaultModelID, customModelsPath: customModelsPath) ?? builtInModels[0]
    }

    public static func legacyModelID(for hyMT2Model: HyMT2Model) -> String {
        switch hyMT2Model {
        case .hyMT2_30B:
            "hymt2-transformers-30b"
        case .hyMT2_18B:
            "hymt2-transformers-1.8b"
        }
    }

    public static func benchmarkModels(
        sourceLanguage: String,
        targetLanguage: String,
        customModelsPath: String? = nil
    ) -> [LocalModelSpec] {
        models(customModelsPath: customModelsPath)
            .filter { $0.includeInFirstRunBenchmark && $0.backendScriptName != nil }
            .filter { $0.supports(sourceLanguage: sourceLanguage, targetLanguage: targetLanguage) }
    }

    private static func loadCustomModels(path: String?) -> [LocalModelSpec] {
        let paths = customModelConfigPaths(explicitPath: path)
        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else {
                continue
            }
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                return try JSONDecoder().decode([LocalModelSpec].self, from: data)
            } catch {
                return []
            }
        }
        return []
    }

    private static func customModelConfigPaths(explicitPath: String?) -> [String] {
        if let explicitPath = explicitPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitPath.isEmpty {
            return [expandedHomePath(explicitPath)]
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.config/copy-translator/local-models.json"]
    }

    private static func expandedHomePath(_ path: String) -> String {
        if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2)))
                .path
        }
        return path
    }
}

private func languageList(_ languages: [String], contains language: String) -> Bool {
    languages.contains("Any") || languages.contains(language)
}
