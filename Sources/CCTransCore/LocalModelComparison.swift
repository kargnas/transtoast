import Foundation

public enum LocalModelSampleLength: String, CaseIterable, Sendable {
    case short = "Short"
    case medium = "Medium"
    case long = "Long"
}

public struct LocalModelSamplePreview: Equatable, Sendable {
    public let title: String
    public let source: String
    public let translation: String

    public init(title: String, source: String, translation: String) {
        self.title = title
        self.source = source
        self.translation = translation
    }
}

public struct LocalModelComparisonRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let localModelID: String?
    public let model: String
    public let runtime: String
    public let quality: String
    public let speedMemory: String
    public let coverage: String
    public let status: String
    public let notes: String
    public let detail: String
    public let licenseNote: String?
    public let isRecommended: Bool
    public let samples: [LocalModelSampleLength: [LocalModelSamplePreview]]

    public init(
        id: String,
        localModelID: String?,
        model: String,
        runtime: String,
        quality: String,
        speedMemory: String,
        coverage: String,
        status: String,
        notes: String,
        detail: String,
        licenseNote: String? = nil,
        isRecommended: Bool = false,
        samples: [LocalModelSampleLength: [LocalModelSamplePreview]] = [:]
    ) {
        self.id = id
        self.localModelID = localModelID
        self.model = model
        self.runtime = runtime
        self.quality = quality
        self.speedMemory = speedMemory
        self.coverage = coverage
        self.status = status
        self.notes = notes
        self.detail = detail
        self.licenseNote = licenseNote
        self.isRecommended = isRecommended
        self.samples = samples
    }
}

public enum LocalModelComparisonData {
    public static let rows: [LocalModelComparisonRow] = [
        LocalModelComparisonRow(
            id: "hymt2-mlx-tested",
            localModelID: "hymt2-mlx-1.8b-4bit",
            model: "Hy-MT2 1.8B 4-bit",
            runtime: "MLX LM",
            quality: "High",
            speedMemory: "0.08-0.57s warm / 1.3-2.4 GB",
            coverage: "Broad multilingual",
            status: "Recommended",
            notes: "Best tested default.",
            detail: "Best overall result from the prior local benchmark. It handled English, Korean, Japanese, Chinese, Spanish, French, Indonesian, and Arabic samples with good speed after model load. Some medium English-to-Korean output still had one mixed Chinese token in a multilingual stress sample, so fresh testing remains useful for a user's actual language pair.",
            licenseNote: "Tencent Hy-MT2 terms apply.",
            isRecommended: true,
            samples: [
                .short: [
                    LocalModelSamplePreview(title: "Word", source: "twice", translation: "두 번"),
                    LocalModelSamplePreview(title: "UI", source: "Retry download", translation: "다시 다운로드 시도"),
                    LocalModelSamplePreview(title: "Japanese", source: "ネットワークが不安定なため、翻訳を一時的に保存しました。", translation: "네트워크가 불안정하기 때문에, 번역을 일시적으로 저장했습니다."),
                ],
                .medium: [
                    LocalModelSamplePreview(title: "Deployment", source: "The deployment failed because the database URL was missing.", translation: "데이터베이스 URL이 누락되어 배포가 실패했습니다."),
                    LocalModelSamplePreview(title: "Release notes", source: "Please summarize the release notes before the meeting.", translation: "회의 전에 릴리스 노트를 요약해 주세요."),
                    LocalModelSamplePreview(title: "Spanish", source: "Guarda los cambios antes de cerrar la ventana de configuración.", translation: "설정 창을 닫기 전에 변경 사항을 저장하세요."),
                ],
                .long: [
                    LocalModelSamplePreview(title: "Offline mode", source: "The new offline mode keeps a local cache of recent translations so users can keep working while the network is unstable.", translation: "새로운 오프라인 모드는 네트워크가 불안정한 상태에서도 사용자가 작업을 계속할 수 있도록 최근 번역본의 로컬 캐시를 유지합니다."),
                    LocalModelSamplePreview(title: "Korean to English", source: "새로운 오프라인 모드는 최근 번역 기록을 로컬 캐시에 저장해서 네트워크가 불안정한 상황에서도 사용자가 작업을 계속할 수 있게 합니다.", translation: "The new offline mode saves recent translation records to the local cache, allowing users to continue working even in unstable network conditions."),
                    LocalModelSamplePreview(title: "Context rule", source: "If the user copies a short fragment from a larger sentence, translate only the copied fragment.", translation: "사용자가 긴 문장에서 짧은 조각만 복사했다면 복사한 조각만 번역하세요."),
                ],
            ]
        ),
        LocalModelComparisonRow(
            id: "hymt2-transformers-tested",
            localModelID: "hymt2-transformers-1.8b",
            model: "Hy-MT2 1.8B",
            runtime: "Transformers",
            quality: "High",
            speedMemory: "Slower load / CPU-PyTorch path",
            coverage: "Broad multilingual",
            status: "Supported",
            notes: "Legacy fallback backend.",
            detail: "Same model family as the recommended MLX path, but uses the legacy Transformers backend. It is useful when MLX is unavailable, but first load and Python dependency behavior are less smooth than the MLX runtime.",
            licenseNote: "Tencent Hy-MT2 terms apply.",
            samples: [
                .short: [
                    LocalModelSamplePreview(title: "Word", source: "twice", translation: "두 번"),
                ],
                .medium: [
                    LocalModelSamplePreview(title: "Deployment", source: "The deployment failed because the database URL was missing.", translation: "데이터베이스 URL이 누락되어 배포가 실패했습니다."),
                ],
            ]
        ),
        LocalModelComparisonRow(
            id: "hymt2-30b-tested",
            localModelID: "hymt2-transformers-30b",
            model: "Hy-MT2 30B-A3B",
            runtime: "Transformers",
            quality: "High",
            speedMemory: "Very heavy",
            coverage: "Broad multilingual",
            status: "Heavy",
            notes: "Not suitable for first-run default.",
            detail: "Kept as a supported advanced option, but excluded from first-run comparison because local memory and load cost are too high for a menu-bar translator default.",
            licenseNote: "Tencent Hy-MT2 terms apply."
        ),
        LocalModelComparisonRow(
            id: "nllb-ct2-tested",
            localModelID: "nllb-ct2-int8",
            model: "NLLB 600M int8",
            runtime: "CTranslate2",
            quality: "Medium",
            speedMemory: "0.05-1.05s / ~1.5 GB",
            coverage: "Broad multilingual",
            status: "Planned adapter",
            notes: "Fast fallback candidate.",
            detail: "Very fast and broad, but Korean wording was consistently more awkward than Hy-MT2. Good future fallback once the CTranslate2 adapter is wired into the app.",
            samples: [
                .short: [
                    LocalModelSamplePreview(title: "Word", source: "twice", translation: "두 번"),
                    LocalModelSamplePreview(title: "UI", source: "Retry download", translation: "다시 다운로드 시도"),
                ],
                .medium: [
                    LocalModelSamplePreview(title: "Deployment", source: "The deployment failed because the database URL was missing.", translation: "배포는 데이터베이스 URL가 없어서 실패했습니다."),
                    LocalModelSamplePreview(title: "Release notes", source: "Please summarize the release notes before the meeting.", translation: "회의 전에 발표 메모를 요약해 주세요."),
                ],
                .long: [
                    LocalModelSamplePreview(title: "Offline mode", source: "The new offline mode keeps a local cache of recent translations so users can keep working while the network is unstable.", translation: "새로운 오프라인 모드는 최신 번역의 로컬 캐시를 유지하므로 사용자가 네트워크가 불안정할 때 계속 작동할 수 있습니다."),
                ],
            ]
        ),
        LocalModelComparisonRow(
            id: "lfm2-gguf-tested",
            localModelID: "lfm2-koen-q4-k-m",
            model: "LFM2 Ko-En Q4_K_M",
            runtime: "llama.cpp",
            quality: "Medium-high",
            speedMemory: "0.24-1.12s / ~1.6 GB",
            coverage: "Korean-English",
            status: "Planned adapter",
            notes: "Good Ko-En candidate.",
            detail: "Good Korean-English result and reasonable memory. It is narrower than Hy-MT2 and needs llama.cpp integration and license review before becoming a built-in runnable option.",
            samples: [
                .short: [
                    LocalModelSamplePreview(title: "Word", source: "twice", translation: "두 번"),
                ],
                .medium: [
                    LocalModelSamplePreview(title: "Deployment", source: "The deployment failed because the database URL was missing.", translation: "데이터베이스 URL이 누락되어 배포가 실패했습니다."),
                ],
                .long: [
                    LocalModelSamplePreview(title: "Korean to English", source: "새로운 오프라인 모드는 최근 번역 기록을 로컬 캐시에 저장해서 네트워크가 불안정한 상황에서도 사용자가 작업을 계속할 수 있게 합니다.", translation: "The new offline mode saves the recent translation record to the local cache, allowing users to continue working even when the network is unstable."),
                ],
            ]
        ),
        LocalModelComparisonRow(
            id: "kanana-tested",
            localModelID: "kanana-lora-koen",
            model: "Kanana LoRA",
            runtime: "Custom Transformers/PEFT",
            quality: "Medium-high",
            speedMemory: "0.4-1.7s after load / ~814 MB",
            coverage: "Korean-English",
            status: "Fragile deps",
            notes: "Retry succeeded with pinned deps.",
            detail: "The initial failure was our dependency/prompt setup, not a model or Mac hardware issue. Retest succeeded with pinned Transformers 4.46.3 and PEFT 0.19.1, but dependency monkey-patching and CC-BY-NC licensing make it a non-default custom-model candidate.",
            licenseNote: "CC-BY-NC.",
            samples: [
                .short: [
                    LocalModelSamplePreview(title: "Word", source: "twice", translation: "두 번이나 그랬어요."),
                ],
                .medium: [
                    LocalModelSamplePreview(title: "Deployment", source: "The deployment failed because the database URL was missing.", translation: "데이터베이스 URL이 누락되어 배포가 실패했습니다."),
                    LocalModelSamplePreview(title: "Release notes", source: "Please summarize the release notes before the meeting.", translation: "회의 전에 출시 노트를 요약해 주세요."),
                ],
            ]
        ),
        LocalModelComparisonRow(
            id: "madlad-tested",
            localModelID: "madlad-swift-int4",
            model: "MADLAD-400 Swift",
            runtime: "MLX Swift",
            quality: "Unknown",
            speedMemory: "Could not run",
            coverage: "Broad multilingual",
            status: "Runtime issue",
            notes: "Swift runtime built, metallib failed.",
            detail: "The official Swift package built successfully, but failed at runtime on this host with an MLX Swift metallib loading error. This is a runtime packaging/environment issue, not a translation quality verdict."
        ),
        LocalModelComparisonRow(
            id: "opus-marian-tested",
            localModelID: nil,
            model: "OPUS/Marian En-Ko",
            runtime: "Transformers / CTranslate2",
            quality: "Failed",
            speedMemory: "N/A",
            coverage: "English-Korean",
            status: "Rejected",
            notes: "Unusable output after retry.",
            detail: "Retried original Transformers, CT2 float16 export, CT2 int8 package, and target-prefix variants. All produced corrupted Korean-like output on the tested samples, so this is treated as upstream model/tokenizer failure rather than an app bug.",
            samples: [
                .short: [
                    LocalModelSamplePreview(title: "Word", source: "twice", translation: "킹 / 칫"),
                ],
                .medium: [
                    LocalModelSamplePreview(title: "Deployment", source: "The deployment failed because the database URL was missing.", translation: "프로세스、403 well2.8:46ther。"),
                    LocalModelSamplePreview(title: "Release notes", source: "Please summarize the release notes before the meeting.", translation: "☆ 좋은 오염 물질☆ 해충 ☆."),
                ],
            ]
        ),
    ]

    public static var recommendedRow: LocalModelComparisonRow {
        rows.first(where: \.isRecommended) ?? rows[0]
    }

    public static func row(forLocalModelID localModelID: String) -> LocalModelComparisonRow? {
        rows.first { $0.localModelID == localModelID }
    }
}
