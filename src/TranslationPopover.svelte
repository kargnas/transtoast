<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import { getCurrentWindow } from "@tauri-apps/api/window";
  import { onMount } from "svelte";
  import { Check, Copy, Eye, Languages, ShieldCheck, X } from "@lucide/svelte";
  import { fallbackTranslationState, type TranslationMode, type TranslationPreviewState } from "./lib/translation";
  import { fallbackState, type SettingsState } from "./lib/settings";

  const params = new URLSearchParams(window.location.search);
  const debugMode = params.get("debug") === "1";
  const requestedMode = modeFromQuery(params.get("mode"));
  const arrowAbove = params.get("placement") === "above";

  let isTauri = $state(false);
  let preview = $state<TranslationPreviewState>(fallbackTranslationState);
  let visibleMode = $state<TranslationMode>(requestedMode ?? fallbackTranslationState.mode);
  let copied = $state(false);
  let modelOptions = $state<PreviewModelOption[]>([]);
  let selectedModelValue = $state("");
  let copyResetTimer: number | undefined;
  let dismissTimer: number | undefined;
  let countdownInterval: number | undefined;
  let countdownStartedAt = $state(0);
  let countdownDuration = $state(fallbackTranslationState.toastDuration);
  let countdownRemaining = $state(fallbackTranslationState.toastDuration);
  let countdownPaused = $state(false);

  const uiStrings = {
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
    copied: "Copied",
    requestPermission: "Request Permission"
  };
  const targetLanguage = $derived(preview.targetLanguage);
  const modelName = $derived(preview.model.trim());
  const costLabel = $derived(formatCostCredits(preview.costCredits));
  const modelMetadata = $derived([modelName, costLabel].filter(Boolean).join(" · "));
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
  const screenRecordingPermissionError = $derived(
    preview.permissionAction === "screenRecording" ||
      (preview.errorText ?? "").toLowerCase().includes("screen recording permission")
  );

  type PreviewModelOption = {
    label: string;
    value: string;
  };

  onMount(() => {
    isTauri = "__TAURI_INTERNALS__" in window;
    applyModelOptions(fallbackState);
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
    if (isTauri) {
      await loadModelOptions();
    } else {
      syncSelectedModel();
    }
    scheduleAutoDismiss();
  }

  async function loadModelOptions() {
    try {
      applyModelOptions(await invoke<SettingsState>("load_settings"));
    } catch {
      applyModelOptions(fallbackState);
    }
  }

  function applyModelOptions(state: SettingsState) {
    modelOptions = [
      ...state.options.localModels.map((option) => ({
        label: option.label,
        value: `localHyMT2:${option.value}`
      })),
      {
        label: state.settings.openRouterTextModel,
        value: `openRouter:${state.settings.openRouterTextModel}`
      }
    ];
    syncSelectedModel();
  }

  function syncSelectedModel() {
    selectedModelValue = modelOptions.find((option) => option.label === preview.model)?.value ?? modelOptions[0]?.value ?? "";
  }

  function modeFromQuery(value: string | null): TranslationMode | null {
    if (value === "loading" || value === "translated" || value === "original" || value === "error") {
      return value;
    }
    return null;
  }

  function formatCostCredits(value: number | null | undefined) {
    if (value === null || value === undefined) return "";
    const fixed = value < 0.0001 ? value.toFixed(8) : value.toFixed(6);
    const trimmed = fixed.replace(/\.?0+$/, "");
    return `Cost ${trimmed || "0"} credits`;
  }

  async function copyText() {
    await navigator.clipboard?.writeText(bodyText);
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
  }

  function selectModel(event: Event) {
    const value = event.currentTarget instanceof HTMLSelectElement ? event.currentTarget.value : "";
    const option = modelOptions.find((candidate) => candidate.value === value);
    if (!option) return;
    selectedModelValue = value;
    preview = {
      ...preview,
      model: option.label
    };
    visibleMode = "translated";
    scheduleAutoDismiss();
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

  async function requestScreenRecordingPermission() {
    if (!isTauri) return;
    try {
      await invoke("open_screen_recording_settings");
    } finally {
      await closePopover();
    }
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
      {#if visibleMode === "loading"}
        <div class="top-controls">
          <button class="icon-button" aria-label={uiStrings.cancel} onclick={cancelLoading}><X size={16} /></button>
        </div>
        <div class="loading-title">
          <span class="status-dot"></span>
          <span>{uiStrings.translating}</span>
        </div>
        <p class="copying">{loadingMessage}</p>
        <div class="progress-track" aria-hidden="true"><span class="progress-fill"></span></div>
        <footer class="bubble-footer">
          <div class="footer-meta">
            <span class="language"><Languages size={14} /><span class="language-text">{targetLanguage}</span></span>
            {#if modelMetadata}<span class="model-label">{modelMetadata}</span>{/if}
          </div>
        </footer>
      {:else if visibleMode === "error"}
        <div class="loading-title error-title">
          <span class="status-dot"></span>
          <span>{uiStrings.error}</span>
        </div>
        <p class="copying">{preview.errorText ?? uiStrings.translationFailed}</p>
        <div class="top-controls">
          {#if showCountdown}
            <div class="dismiss-countdown" aria-label={`Auto hide in ${countdownLabel}`}>
              <span class="dismiss-countdown-fill"></span>
              <span class="dismiss-countdown-label">{countdownLabel}</span>
            </div>
          {/if}
          {#if modelOptions.length > 1}
            <select class="model-select" aria-label="Model" value={selectedModelValue} onchange={selectModel}>
              {#each modelOptions as option}
                <option value={option.value}>{option.label}</option>
              {/each}
            </select>
          {/if}
          <button class="icon-button" aria-label={uiStrings.close} onclick={closePopover}><X size={16} /></button>
        </div>
        <footer class="bubble-footer error-footer">
          <div class="footer-meta">
            <span class="language"><Languages size={14} /><span class="language-text">{targetLanguage}</span></span>
            {#if modelMetadata}<span class="model-label">{modelMetadata}</span>{/if}
          </div>
          {#if screenRecordingPermissionError}
            <button class="small-button permission-request-button" onclick={requestScreenRecordingPermission}>
              <ShieldCheck size={14} />{uiStrings.requestPermission}
            </button>
          {/if}
        </footer>
      {:else}
        <div class="top-controls">
          {#if showCountdown}
            <div class="dismiss-countdown" aria-label={`Auto hide in ${countdownLabel}`}>
              <span class="dismiss-countdown-fill"></span>
              <span class="dismiss-countdown-label">{countdownLabel}</span>
            </div>
          {/if}
          {#if modelOptions.length > 1}
            <select class="model-select" aria-label="Model" value={selectedModelValue} onchange={selectModel}>
              {#each modelOptions as option}
                <option value={option.value}>{option.label}</option>
              {/each}
            </select>
          {/if}
          <button class="icon-button" aria-label={visibleMode === "original" ? uiStrings.showTranslation : uiStrings.showOriginal} onclick={toggleOriginal}>
            {#if visibleMode === "original"}<Languages size={16} />{:else}<Eye size={16} />{/if}
          </button>
          <button class="icon-button" aria-label={copied ? uiStrings.copied : uiStrings.copyCurrent} onclick={copyText}>
            {#if copied}<Check size={16} />{:else}<Copy size={16} />{/if}
          </button>
          <button class="icon-button" aria-label={uiStrings.close} onclick={closePopover}><X size={16} /></button>
        </div>
        <p class:original={visibleMode === "original"} class="translation-text">{bodyText}</p>
        <footer class="bubble-footer">
          <div class="footer-meta">
            <span class="language"><Languages size={14} /><span class="language-text">{targetLanguage}</span></span>
            {#if modelMetadata}<span class="model-label">{modelMetadata}</span>{/if}
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
