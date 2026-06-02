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
  let moreOpen = $state(false);
  let copyResetTimer: number | undefined;
  let dismissTimer: number | undefined;
  let countdownInterval: number | undefined;
  let countdownStartedAt = $state(0);
  let countdownDuration = $state(fallbackTranslationState.toastDuration);
  let countdownRemaining = $state(fallbackTranslationState.toastDuration);
  let countdownPaused = $state(false);

  const uiStrings = localeStrings();
  const languagePair = $derived(`${shortLanguage(preview.sourceLanguage)} → ${shortLanguage(preview.targetLanguage)}`);
  const modelName = $derived(preview.model.trim());
  const bodyText = $derived(visibleMode === "original" ? preview.originalText : preview.translatedText);
  const loadingMessage = $derived(
    preview.originalText === "[screen screenshot]"
      ? uiStrings.translatingScreenshot
      : uiStrings.translatingClipboard
  );
  const compactMode = $derived(visibleMode === "translated" || visibleMode === "original");
  const tallMode = $derived(debugMode || visibleMode === "loading" || visibleMode === "error");
  const showCountdown = $derived(!debugMode && visibleMode !== "loading");
  const countdownLabel = $derived(`${countdownRemaining.toFixed(1)}s`);
  const countdownProgressValue = $derived(Math.max(0, Math.min(1, countdownRemaining / countdownDuration)));
  const countdownProgress = $derived(`${countdownProgressValue * 100}%`);
  const dismissOpacity = $derived((0.62 + countdownProgressValue * 0.38).toFixed(3));

  onMount(() => {
    isTauri = "__TAURI_INTERNALS__" in window;
    if (isTauri) {
      void loadPreview();
    }
    return () => {
      clearAutoDismiss();
      clearCountdown();
      clearCopyReset();
    };
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

  function localeStrings() {
    if (params.get("ui") === "ko") {
      return {
        translating: "번역 중...",
        translatingClipboard: "클립보드의 텍스트를 번역하고 있어요.",
        translatingScreenshot: "스크린샷을 캡처하고 번역하고 있어요.",
        error: "오류",
        translationFailed: "번역에 실패했습니다.",
        showOriginal: "원본 보기",
        showTranslation: "번역 보기",
        cancel: "취소",
        close: "닫기",
        copyCurrent: "복사",
        copyOriginal: "원본 복사",
        copyTranslation: "번역 복사",
        moreActions: "추가 작업",
        copied: "복사됨",
        usesKoreanLanguageNames: true
      };
    }

    return {
      translating: "Translating...",
      translatingClipboard: "Translating clipboard text.",
      translatingScreenshot: "Capturing and translating the screenshot.",
      error: "Error",
      translationFailed: "Translation failed.",
      showOriginal: "Original",
      showTranslation: "Translation",
      cancel: "Cancel",
      close: "Close",
      copyCurrent: "Copy",
      copyOriginal: "Copy Original",
      copyTranslation: "Copy Translation",
      moreActions: "More actions",
      copied: "Copied",
      usesKoreanLanguageNames: false
    };
  }

  function modeFromQuery(value: string | null): TranslationMode | null {
    if (value === "loading" || value === "translated" || value === "original" || value === "error") {
      return value;
    }
    return null;
  }

  function shortLanguage(language: string) {
    if (!uiStrings.usesKoreanLanguageNames) {
      return language;
    }

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
    moreOpen = false;
    markCopied();
  }

  async function copyOriginal() {
    await navigator.clipboard?.writeText(preview.originalText);
    moreOpen = false;
    markCopied();
  }

  async function copyTranslation() {
    await navigator.clipboard?.writeText(preview.translatedText);
    moreOpen = false;
    markCopied();
  }

  function markCopied() {
    clearCopyReset();
    copied = true;
    copyResetTimer = window.setTimeout(() => {
      copied = false;
      copyResetTimer = undefined;
    }, 1200);
  }

  function clearCopyReset() {
    if (copyResetTimer !== undefined) {
      window.clearTimeout(copyResetTimer);
      copyResetTimer = undefined;
    }
  }

  function toggleOriginal() {
    visibleMode = visibleMode === "original" ? "translated" : "original";
    moreOpen = false;
  }

  async function startDragging(event: MouseEvent) {
    const target = event.target instanceof Element ? event.target : null;
    if (!isTauri || event.button !== 0 || target?.closest("button")) return;
    try {
      await getCurrentWindow().startDragging();
    } catch {
      // Dragging is best-effort in browser preview and unsupported shells.
    }
  }

  async function closePopover() {
    moreOpen = false;
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
    clearCountdown();
    if (debugMode || visibleMode === "loading") return;

    countdownDuration = dismissDurationForText(bodyText);
    countdownRemaining = countdownDuration;
    countdownPaused = false;
    countdownStartedAt = performance.now();
    countdownInterval = window.setInterval(updateCountdown, 100);
    dismissTimer = window.setTimeout(() => {
      void closePopover();
    }, countdownDuration * 1000);
  }

  function clearAutoDismiss() {
    if (dismissTimer !== undefined) {
      window.clearTimeout(dismissTimer);
      dismissTimer = undefined;
    }
  }

  function pauseAutoDismiss() {
    clearAutoDismiss();
    clearCountdown();
    if (debugMode || visibleMode === "loading") return;
    countdownDuration = dismissDurationForText(bodyText);
    countdownRemaining = countdownDuration;
    countdownPaused = true;
  }

  function dismissDurationForText(text: string) {
    const estimatedLines = Math.max(1, Math.ceil(text.length / 28));
    if (estimatedLines < 5) return 4;
    return Math.min(10, 4 + estimatedLines - 4);
  }

  function clearCountdown() {
    if (countdownInterval !== undefined) {
      window.clearInterval(countdownInterval);
      countdownInterval = undefined;
    }
  }

  function updateCountdown() {
    const elapsed = (performance.now() - countdownStartedAt) / 1000;
    countdownRemaining = Math.max(0, countdownDuration - elapsed);
    if (countdownRemaining <= 0) {
      clearCountdown();
    }
  }

  function toggleMore(event: MouseEvent) {
    event.stopPropagation();
    moreOpen = !moreOpen;
  }

</script>

<main class="translation-stage" class:debug={debugMode} class:tall={tallMode} aria-label="Translation popup">
  <div
    class="translation-bubble"
    class:above={arrowAbove}
    class:compact={compactMode}
    class:error={visibleMode === "error"}
    role="dialog"
    aria-label="Translation result"
    tabindex="-1"
    onmousedown={startDragging}
    class:hover-paused={countdownPaused}
    style={`--countdown-progress: ${countdownProgress}; --dismiss-opacity: ${dismissOpacity}`}
    onmouseenter={pauseAutoDismiss}
    onmouseleave={scheduleAutoDismiss}
  >
    <div class="translation-bubble-inner">
      {#if showCountdown}
        <div class="dismiss-countdown" aria-label={`Auto hide in ${countdownLabel}`}>
          <span class="dismiss-countdown-fill"></span>
          <span class="dismiss-countdown-label">{countdownLabel}</span>
        </div>
      {/if}
      {#if visibleMode === "loading"}
        <div class="loading-title">
          <span class="status-dot"></span>
          <span>{uiStrings.translating}</span>
        </div>
        <p class="copying">{loadingMessage}</p>
        <div class="progress-track" aria-hidden="true"><span class="progress-fill"></span></div>
        <footer class="bubble-footer">
          <div class="footer-meta">
            <span class="language"><Languages size={14} /><span class="language-text">{languagePair}</span></span>
            {#if modelName}<span class="model-label">{modelName}</span>{/if}
          </div>
          <button class="small-button" onclick={cancelLoading}>{uiStrings.cancel}</button>
        </footer>
      {:else if visibleMode === "error"}
        <div class="loading-title error-title">
          <span class="status-dot"></span>
          <span>{uiStrings.error}</span>
        </div>
        <p class="copying">{preview.errorText ?? uiStrings.translationFailed}</p>
        <footer class="bubble-footer">
          <div class="footer-meta">
            <span class="language"><Languages size={14} /><span class="language-text">{languagePair}</span></span>
            {#if modelName}<span class="model-label">{modelName}</span>{/if}
          </div>
          <button class="icon-button" aria-label={uiStrings.close} onclick={closePopover}><X size={16} /></button>
        </footer>
      {:else}
        <p class:original={visibleMode === "original"} class="translation-text">{bodyText}</p>
        <footer class="bubble-footer">
          <div class="footer-meta">
            <span class="language"><Languages size={14} /><span class="language-text">{languagePair}</span></span>
            {#if modelName}<span class="model-label">{modelName}</span>{/if}
          </div>
          <div class="action-row">
            <button class="small-button" onclick={toggleOriginal}>
              {visibleMode === "original" ? uiStrings.showTranslation : uiStrings.showOriginal}
            </button>
            <button class="icon-button" aria-label={copied ? uiStrings.copied : uiStrings.copyCurrent} onclick={copyText}>
              {#if copied}<Check size={16} />{:else}<Copy size={16} />{/if}
            </button>
            <div class="more-anchor">
              <button class="icon-button more-button" aria-label={uiStrings.moreActions} aria-expanded={moreOpen} onclick={toggleMore}>
                <MoreHorizontal size={17} />
              </button>
              {#if moreOpen}
                <div class="more-menu" role="menu">
                  <button role="menuitem" onclick={copyOriginal}>{uiStrings.copyOriginal}</button>
                  <button role="menuitem" onclick={copyTranslation}>{uiStrings.copyTranslation}</button>
                  <span class="menu-separator"></span>
                  <button role="menuitem" onclick={closePopover}>{uiStrings.close}</button>
                </div>
              {/if}
            </div>
          </div>
        </footer>
      {/if}
    </div>
  </div>

  {#if debugMode}
    <nav class="preview-switcher" aria-label="Preview state">
      <button class:active={visibleMode === "loading"} onclick={() => (visibleMode = "loading")}>Loading</button>
      <button class:active={visibleMode === "translated"} onclick={() => (visibleMode = "translated")}>Done</button>
      <button class:active={visibleMode === "original"} onclick={() => (visibleMode = "original")}>Original</button>
      <button class:active={visibleMode === "error"} onclick={() => (visibleMode = "error")}>Error</button>
    </nav>
  {/if}
</main>
