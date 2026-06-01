<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import { getCurrentWindow } from "@tauri-apps/api/window";
  import { onMount } from "svelte";
  import { Check, Copy, Languages, MoreHorizontal, X } from "@lucide/svelte";
  import { fallbackTranslationState, type TranslationMode, type TranslationPreviewState } from "./lib/translation";

  const params = new URLSearchParams(window.location.search);
  const debugMode = params.get("debug") === "1";
  const requestedMode = modeFromQuery(params.get("mode"));
  const arrowAbove = params.get("placement") === "above";

  let isTauri = $state(false);
  let preview = $state<TranslationPreviewState>(fallbackTranslationState);
  let visibleMode = $state<TranslationMode>(requestedMode ?? fallbackTranslationState.mode);
  let copied = $state(false);
  let dismissTimer: number | undefined;

  const languagePair = $derived(`${shortLanguage(preview.sourceLanguage)} → ${shortLanguage(preview.targetLanguage)}`);
  const bodyText = $derived(visibleMode === "original" ? preview.originalText : preview.translatedText);
  const loadingMessage = $derived(
    preview.originalText === "[screen screenshot]"
      ? "스크린샷을 캡처하고 번역하고 있어요."
      : "클립보드의 텍스트를 번역하고 있어요."
  );
  const compactMode = $derived(visibleMode === "translated" || visibleMode === "original");
  const tallMode = $derived(debugMode || visibleMode === "loading" || visibleMode === "error");

  onMount(() => {
    isTauri = "__TAURI_INTERNALS__" in window;
    if (isTauri) {
      void loadPreview();
    }
    return () => clearAutoDismiss();
  });

  async function loadPreview() {
    try {
      preview = await invoke<TranslationPreviewState>("load_translation_preview");
      visibleMode = requestedMode ?? preview.mode;
    } catch {
      preview = fallbackTranslationState;
      visibleMode = requestedMode ?? "translated";
    }
    scheduleAutoDismiss();
  }

  function modeFromQuery(value: string | null): TranslationMode | null {
    if (value === "loading" || value === "translated" || value === "original" || value === "error") {
      return value;
    }
    return null;
  }

  function shortLanguage(language: string) {
    const names: Record<string, string> = {
      English: "영어",
      Korean: "한국어",
      "Simplified Chinese": "중국어",
      Japanese: "일본어",
      Spanish: "스페인어",
      German: "독일어",
      French: "프랑스어",
      Indonesian: "인도네시아어",
      Arabic: "아랍어",
      Auto: "자동"
    };
    return names[language] ?? language;
  }

  async function copyText() {
    await navigator.clipboard?.writeText(bodyText);
    copied = true;
    window.setTimeout(() => (copied = false), 1200);
  }

  function toggleOriginal() {
    visibleMode = visibleMode === "original" ? "translated" : "original";
  }

  async function closePopover() {
    if (!isTauri) return;
    try {
      await invoke("close_translation_preview");
    } catch {
      await getCurrentWindow().close();
    }
  }

  async function cancelLoading() {
    if (debugMode) {
      visibleMode = "translated";
      return;
    }
    await closePopover();
  }

  function scheduleAutoDismiss() {
    clearAutoDismiss();
    if (debugMode || visibleMode === "loading") return;

    const seconds = Number.isFinite(preview.toastDuration) ? preview.toastDuration : fallbackTranslationState.toastDuration;
    dismissTimer = window.setTimeout(() => {
      void closePopover();
    }, Math.max(1, seconds) * 1000);
  }

  function clearAutoDismiss() {
    if (dismissTimer !== undefined) {
      window.clearTimeout(dismissTimer);
      dismissTimer = undefined;
    }
  }
</script>

<main class="translation-stage" class:debug={debugMode} class:tall={tallMode} aria-label="Translation popup">
  <section
    class="translation-bubble"
    class:above={arrowAbove}
    class:compact={compactMode}
    class:error={visibleMode === "error"}
  >
    <div class="translation-bubble-inner">
      {#if visibleMode === "loading"}
        <div class="loading-title">
          <span class="status-dot"></span>
          <span>번역 중...</span>
        </div>
        <p class="copying">{loadingMessage}</p>
        <div class="progress-track" aria-hidden="true"><span class="progress-fill"></span></div>
        <footer class="bubble-footer">
          <span class="language"><Languages size={14} />{languagePair}</span>
          <button class="small-button" onclick={cancelLoading}>취소</button>
        </footer>
      {:else if visibleMode === "error"}
        <div class="loading-title error-title">
          <span class="status-dot"></span>
          <span>오류</span>
        </div>
        <p class="copying">{preview.errorText ?? "번역에 실패했습니다."}</p>
        <footer class="bubble-footer">
          <span class="language"><Languages size={14} />{languagePair}</span>
          <button class="icon-button" aria-label="Close" onclick={closePopover}><X size={16} /></button>
        </footer>
      {:else}
        <p class:original={visibleMode === "original"} class="translation-text">{bodyText}</p>
        <footer class="bubble-footer">
          <span class="language"><Languages size={14} />{languagePair}</span>
          <div class="action-row">
            <button class="small-button" onclick={toggleOriginal}>
              {visibleMode === "original" ? "번역 보기" : "원본 보기"}
            </button>
            <button class="icon-button" aria-label="Copy translation" onclick={copyText}>
              {#if copied}<Check size={16} />{:else}<Copy size={16} />{/if}
            </button>
            <button class="icon-button" aria-label="More actions"><MoreHorizontal size={17} /></button>
          </div>
        </footer>
      {/if}
    </div>
  </section>

  {#if debugMode}
    <nav class="preview-switcher" aria-label="Preview state">
      <button class:active={visibleMode === "loading"} onclick={() => (visibleMode = "loading")}>Loading</button>
      <button class:active={visibleMode === "translated"} onclick={() => (visibleMode = "translated")}>Done</button>
      <button class:active={visibleMode === "original"} onclick={() => (visibleMode = "original")}>Original</button>
      <button class:active={visibleMode === "error"} onclick={() => (visibleMode = "error")}>Error</button>
    </nav>
  {/if}
</main>
