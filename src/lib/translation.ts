export type TranslationMode = "loading" | "translated" | "original" | "error";

export type TranslationPreviewState = {
  mode: TranslationMode;
  sourceLanguage: string;
  targetLanguage: string;
  originalText: string;
  translatedText: string;
  errorText: string | null;
  providerTitle: string;
  model: string;
  costCredits: number | null;
  permissionAction?: "screenRecording" | null;
  toastDuration: number;
};

export const fallbackTranslationState: TranslationPreviewState = {
  mode: "translated",
  sourceLanguage: "English",
  targetLanguage: "Korean",
  originalText: "The future belongs to those who believe in the beauty of their dreams.",
  translatedText: "미래는 자신의 꿈의 아름다움을 믿는 사람들의 것이다.",
  errorText: null,
  providerTitle: "Local Model",
  model: "Hy-MT2 1.8B 4-bit",
  costCredits: null,
  toastDuration: 4
};
