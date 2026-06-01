export type TranslationProvider = "localHyMT2" | "openRouter";
export type ToastPosition = "bottomRight" | "bottomLeft" | "topRight" | "topLeft";

export type SettingField =
  | "provider"
  | "localModelID"
  | "sourceLanguage"
  | "targetLanguage"
  | "toastPosition"
  | "localHyMT2BackendPath"
  | "customLocalModelsPath"
  | "openRouterTextModel"
  | "openRouterVisionModel";

export type Settings = {
  provider: TranslationProvider;
  localModelID: string;
  localHyMT2BackendPath: string | null;
  customLocalModelsPath: string | null;
  openRouterTextModel: string;
  openRouterVisionModel: string;
  includeScreenContextForLLM: boolean;
  sourceLanguage: string;
  targetLanguage: string;
  hasCompletedLocalModelSelection: boolean;
  toastPosition: ToastPosition;
  toastDuration: number;
};

export type SettingOption = {
  label: string;
  value: string;
  note?: string;
};

export type PermissionStatus = {
  keyboard: boolean;
  screen: boolean;
};

export type SettingsOptions = {
  providers: SettingOption[];
  localModels: SettingOption[];
  sourceLanguages: SettingOption[];
  targetLanguages: SettingOption[];
  toastPositions: SettingOption[];
};

export type SettingsState = {
  settings: Settings;
  defaults: Settings;
  overrides: Record<SettingField, boolean>;
  options: SettingsOptions;
  permissions: PermissionStatus;
  storagePath: string;
};

export type ActionResult = {
  title: string;
  message: string;
  ok: boolean;
};

export const fallbackState: SettingsState = {
  settings: {
    provider: "localHyMT2",
    localModelID: "hymt2-mlx-1.8b-4bit",
    localHyMT2BackendPath: null,
    customLocalModelsPath: null,
    openRouterTextModel: "google/gemini-2.5-flash-lite",
    openRouterVisionModel: "google/gemini-2.5-flash-lite",
    includeScreenContextForLLM: false,
    sourceLanguage: "Auto",
    targetLanguage: "Korean",
    hasCompletedLocalModelSelection: false,
    toastPosition: "bottomRight",
    toastDuration: 6
  },
  defaults: {
    provider: "localHyMT2",
    localModelID: "hymt2-mlx-1.8b-4bit",
    localHyMT2BackendPath: null,
    customLocalModelsPath: null,
    openRouterTextModel: "google/gemini-2.5-flash-lite",
    openRouterVisionModel: "google/gemini-2.5-flash-lite",
    includeScreenContextForLLM: false,
    sourceLanguage: "Auto",
    targetLanguage: "Korean",
    hasCompletedLocalModelSelection: false,
    toastPosition: "bottomRight",
    toastDuration: 6
  },
  overrides: {
    provider: false,
    localModelID: false,
    sourceLanguage: false,
    targetLanguage: false,
    toastPosition: false,
    localHyMT2BackendPath: false,
    customLocalModelsPath: false,
    openRouterTextModel: false,
    openRouterVisionModel: false
  },
  options: {
    providers: [
      { label: "Local Model", value: "localHyMT2" },
      { label: "OpenRouter LLM", value: "openRouter" }
    ],
    localModels: [
      { label: "Hy-MT2 1.8B 4-bit (MLX)", value: "hymt2-mlx-1.8b-4bit", note: "Recommended" },
      { label: "Hy-MT2 1.8B (Transformers)", value: "hymt2-transformers-1.8b" },
      { label: "Hy-MT2 30B-A3B (Transformers)", value: "hymt2-transformers-30b" },
      { label: "Hy-MT2 1.8B IQ4_XS (GGUF)", value: "hymt2-gguf-iq4-xs" },
      { label: "LFM2 Ko-En Q4_K_M (GGUF)", value: "lfm2-koen-q4-k-m" },
      { label: "NLLB CTranslate2 int8", value: "nllb-ct2-int8" },
      { label: "QuickMT En-Ko", value: "quickmt-en-ko" },
      { label: "Kanana 1.5 2.1B AIHub Ko-En LoRA", value: "kanana-lora-koen" },
      { label: "MADLAD-400 Swift int4", value: "madlad-swift-int4" }
    ],
    sourceLanguages: [
      "Auto",
      "English",
      "Korean",
      "Simplified Chinese",
      "Japanese",
      "Spanish",
      "German",
      "French",
      "Indonesian",
      "Arabic"
    ].map((value) => ({ label: value, value })),
    targetLanguages: [
      "English",
      "Korean",
      "Simplified Chinese",
      "Japanese",
      "Spanish",
      "German",
      "French",
      "Indonesian",
      "Arabic"
    ].map((value) => ({ label: value, value })),
    toastPositions: [
      { label: "Bottom Right", value: "bottomRight" },
      { label: "Bottom Left", value: "bottomLeft" },
      { label: "Top Right", value: "topRight" },
      { label: "Top Left", value: "topLeft" }
    ]
  },
  permissions: {
    keyboard: false,
    screen: false
  },
  storagePath: "Browser preview"
};

export function cloneFallbackState(): SettingsState {
  return structuredClone(fallbackState);
}

export type RequestLogEntry = {
  id: string;
  timestamp: string;
  source: string;
  providerTitle: string;
  model: string;
  inputPreview: string;
  outputPreview: string;
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  usageSource: string;
  isDuplicateSuspect: boolean;
  imageInfo: string | null;
  fingerprint: string;
};

export type RequestLogSummary = {
  requestCount: number;
  duplicateSuspectCount: number;
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
};

export type RequestLogsState = {
  entries: RequestLogEntry[];
  summary: RequestLogSummary;
  storagePath: string;
};

export type BenchmarkResult = {
  output: string;
  ok: boolean;
};
