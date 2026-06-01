export type LocalModelSampleLength = "Short" | "Medium" | "Long";

export type LocalModelSamplePreview = {
  title: string;
  source: string;
  translation: string;
};

export type LocalModelComparisonRow = {
  id: string;
  localModelID: string | null;
  model: string;
  runtime: string;
  quality: string;
  speedMemory: string;
  coverage: string;
  status: string;
  notes: string;
  detail: string;
  licenseNote?: string;
  isRecommended: boolean;
  samples: Partial<Record<LocalModelSampleLength, LocalModelSamplePreview[]>>;
};

export const sampleLengths: LocalModelSampleLength[] = ["Short", "Medium", "Long"];

export const localModelRows: LocalModelComparisonRow[] = [
  {
    id: "hymt2-mlx-tested",
    localModelID: "hymt2-mlx-1.8b-4bit",
    model: "Hy-MT2 1.8B 4-bit",
    runtime: "MLX LM",
    quality: "High",
    speedMemory: "0.08-0.57s warm / 1.3-2.4 GB",
    coverage: "Broad multilingual",
    status: "Recommended",
    notes: "Best tested default.",
    detail:
      "Best overall result from the prior local benchmark. It handled English, Korean, Japanese, Chinese, Spanish, French, Indonesian, and Arabic samples with good speed after model load. Fresh testing remains useful for a user's actual language pair.",
    licenseNote: "Tencent Hy-MT2 terms apply.",
    isRecommended: true,
    samples: {
      Short: [
        { title: "Word", source: "twice", translation: "두 번" },
        { title: "UI", source: "Retry download", translation: "다시 다운로드 시도" },
        {
          title: "Japanese",
          source: "ネットワークが不安定なため、翻訳を一時的に保存しました。",
          translation: "네트워크가 불안정하기 때문에, 번역을 일시적으로 저장했습니다."
        }
      ],
      Medium: [
        {
          title: "Deployment",
          source: "The deployment failed because the database URL was missing.",
          translation: "데이터베이스 URL이 누락되어 배포가 실패했습니다."
        },
        {
          title: "Release notes",
          source: "Please summarize the release notes before the meeting.",
          translation: "회의 전에 릴리스 노트를 요약해 주세요."
        }
      ],
      Long: [
        {
          title: "Offline mode",
          source:
            "The new offline mode keeps a local cache of recent translations so users can keep working while the network is unstable.",
          translation:
            "새로운 오프라인 모드는 네트워크가 불안정한 상태에서도 사용자가 작업을 계속할 수 있도록 최근 번역본의 로컬 캐시를 유지합니다."
        }
      ]
    }
  },
  {
    id: "hymt2-transformers-tested",
    localModelID: "hymt2-transformers-1.8b",
    model: "Hy-MT2 1.8B",
    runtime: "Transformers",
    quality: "High",
    speedMemory: "Slower load / CPU-PyTorch path",
    coverage: "Broad multilingual",
    status: "Supported",
    notes: "Legacy fallback backend.",
    detail:
      "Same model family as the recommended MLX path, but uses the Transformers backend. Useful when MLX is unavailable, with less smooth first-load and dependency behavior.",
    licenseNote: "Tencent Hy-MT2 terms apply.",
    isRecommended: false,
    samples: {
      Short: [{ title: "Word", source: "twice", translation: "두 번" }]
    }
  },
  {
    id: "hymt2-30b-tested",
    localModelID: "hymt2-transformers-30b",
    model: "Hy-MT2 30B-A3B",
    runtime: "Transformers",
    quality: "High",
    speedMemory: "Very heavy",
    coverage: "Broad multilingual",
    status: "Heavy",
    notes: "Not suitable for first-run default.",
    detail:
      "Kept as a supported advanced option, but excluded from first-run comparison because local memory and load cost are too high for a menu-bar translator default.",
    licenseNote: "Tencent Hy-MT2 terms apply.",
    isRecommended: false,
    samples: {}
  },
  {
    id: "nllb-ct2-tested",
    localModelID: "nllb-ct2-int8",
    model: "NLLB 600M int8",
    runtime: "CTranslate2",
    quality: "Medium",
    speedMemory: "0.05-1.05s / ~1.5 GB",
    coverage: "Broad multilingual",
    status: "Planned adapter",
    notes: "Fast fallback candidate.",
    detail:
      "Very fast and broad, but Korean wording was more awkward than Hy-MT2. Good future fallback once the CTranslate2 adapter is wired into the app.",
    isRecommended: false,
    samples: {
      Short: [
        { title: "Word", source: "twice", translation: "두 번" },
        { title: "UI", source: "Retry download", translation: "다시 다운로드 시도" }
      ]
    }
  },
  {
    id: "lfm2-gguf-tested",
    localModelID: "lfm2-koen-q4-k-m",
    model: "LFM2 Ko-En Q4_K_M",
    runtime: "llama.cpp",
    quality: "Medium-high",
    speedMemory: "0.24-1.12s / ~1.6 GB",
    coverage: "Korean-English",
    status: "Planned adapter",
    notes: "Good Ko-En candidate.",
    detail:
      "Good Korean-English result and reasonable memory. It is narrower than Hy-MT2 and needs llama.cpp integration and license review before becoming a built-in runnable option.",
    isRecommended: false,
    samples: {}
  },
  {
    id: "kanana-tested",
    localModelID: "kanana-lora-koen",
    model: "Kanana LoRA",
    runtime: "Custom Transformers/PEFT",
    quality: "Medium-high",
    speedMemory: "0.4-1.7s after load / ~814 MB",
    coverage: "Korean-English",
    status: "Fragile deps",
    notes: "Retry succeeded with pinned deps.",
    detail:
      "Retest succeeded with pinned Transformers and PEFT, but dependency patching and CC-BY-NC licensing make it a non-default custom-model candidate.",
    licenseNote: "CC-BY-NC.",
    isRecommended: false,
    samples: {}
  },
  {
    id: "madlad-tested",
    localModelID: "madlad-swift-int4",
    model: "MADLAD-400 Swift",
    runtime: "MLX Swift",
    quality: "Unknown",
    speedMemory: "Could not run",
    coverage: "Broad multilingual",
    status: "Runtime issue",
    notes: "Swift runtime built, metallib failed.",
    detail:
      "The official Swift package built successfully, but failed at runtime on this host with an MLX Swift metallib loading error.",
    isRecommended: false,
    samples: {}
  },
  {
    id: "opus-marian-tested",
    localModelID: null,
    model: "OPUS/Marian En-Ko",
    runtime: "Transformers / CTranslate2",
    quality: "Failed",
    speedMemory: "N/A",
    coverage: "English-Korean",
    status: "Rejected",
    notes: "Unusable output after retry.",
    detail:
      "Retried original Transformers, CT2 float16 export, CT2 int8 package, and target-prefix variants. All produced corrupted Korean-like output on the tested samples.",
    isRecommended: false,
    samples: {}
  }
];

export function recommendedLocalModelRow() {
  return localModelRows.find((row) => row.isRecommended) ?? localModelRows[0];
}

export function rowForLocalModelID(localModelID: string) {
  return localModelRows.find((row) => row.localModelID === localModelID) ?? null;
}
