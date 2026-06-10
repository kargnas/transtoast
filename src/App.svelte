<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import { onMount } from "svelte";
  import {
    ArrowUpDown,
    Ban,
    Camera,
    Check,
    CheckCircle2,
    ChevronDown,
    ChevronRight,
    Cloud,
    Cpu,
    KeyRound,
    Info,
    Keyboard,
    Languages,
    Play,
    RotateCcw,
    ScrollText,
    Settings as SettingsIcon,
    ShieldCheck,
    SlidersHorizontal,
    Star
  } from "@lucide/svelte";
  import {
    cloneFallbackState,
    type ActionResult,
    type OpenRouterModelOption,
    type SettingField,
    type Settings,
    type SettingsState,
    type ToastPosition,
    type TranslationProvider
  } from "./lib/settings";

  type Section = "general" | "models" | "shortcuts" | "excluded" | "advanced" | "info";
  type OpenRouterSortKey = "model" | "inputPrice" | "outputPrice" | "context";
  type SortDirection = "asc" | "desc";
  type OpenRouterAPIKeyState = {
    configured: boolean;
    path: string;
  };

  let settingsState = $state<SettingsState | null>(null);
  let activeSection = $state<Section>("general");
  let isSaving = $state(false);
  let isTauri = $state(false);
  let lastResult = $state("No translation yet.");
  let notices = $state<ActionResult[]>([]);
  let openRouterAPIKeyState = $state<OpenRouterAPIKeyState>({ configured: false, path: "~/.config/cctrans/.env" });
  let openRouterAPIKeyInput = $state("");
  let openTranslationModelMenu = $state<"general" | "models" | null>(null);
  let activeTranslationModelProvider = $state<TranslationProvider>("localHyMT2");
  let openRouterSort = $state<{ key: OpenRouterSortKey; direction: SortDirection }>({
    key: "inputPrice",
    direction: "asc"
  });

  const sectionTitles: Record<Section, string> = {
    general: "General",
    models: "Models",
    shortcuts: "Shortcuts",
    excluded: "Excluded Apps",
    advanced: "Advanced",
    info: "Info"
  };

  onMount(async () => {
    isTauri = "__TAURI_INTERNALS__" in window;
    await loadSettings();
    await loadOpenRouterAPIKeyState();
  });

  async function loadSettings() {
    try {
      settingsState = isTauri
        ? await invoke<SettingsState>("load_settings")
        : cloneFallbackState();
    } catch (error) {
      settingsState = cloneFallbackState();
      pushNotice({
        title: "Settings",
        message: `Loaded browser preview. ${formatError(error)}`,
        ok: false
      });
    }
  }

  async function saveSettings(next: Settings) {
    if (!settingsState) return;

    isSaving = true;
    try {
      settingsState = isTauri
        ? await invoke<SettingsState>("save_settings", { settings: next })
        : withBrowserOverrides(settingsState, next);
    } catch (error) {
      pushNotice({
        title: "Save failed",
        message: formatError(error),
        ok: false
      });
    } finally {
      isSaving = false;
    }
  }

  async function updateField<K extends SettingField>(field: K, value: Settings[K]) {
    if (!settingsState) return;
    const next = {
      ...settingsState.settings,
      [field]: value
    };
    await saveSettings(next);
  }

  async function updateNullableField(field: "localHyMT2BackendPath" | "customLocalModelsPath", value: string) {
    const trimmed = value.trim();
    await updateField(field, (trimmed.length > 0 ? trimmed : null) as Settings[typeof field]);
  }

  async function updateModelField(field: "openRouterTextModel" | "openRouterVisionModel", value: string) {
    const trimmed = value.trim();
    await updateField(field, trimmed === "default" ? settingsState?.defaults[field] ?? trimmed : trimmed);
  }

  async function selectTranslationModel(value: string) {
    if (!settingsState) return;
    const [provider, model] = value.split(/:(.*)/s).filter(Boolean);
    if (provider !== "localHyMT2" && provider !== "openRouter") return;

    const next: Settings = { ...settingsState.settings, provider };
    if (provider === "localHyMT2") {
      next.localModelID = model === "default" ? settingsState.defaults.localModelID : model;
    } else {
      next.openRouterTextModel = model === "default" ? settingsState.defaults.openRouterTextModel : model;
    }
    await saveSettings(next);
  }

  async function chooseTranslationModel(value: string) {
    await selectTranslationModel(value);
    closeTranslationModelMenu();
  }

  function toggleTranslationModelMenu(scope: "general" | "models") {
    if (!settingsState) return;
    if (openTranslationModelMenu === scope) {
      closeTranslationModelMenu();
      return;
    }
    activeTranslationModelProvider = settingsState.settings.provider;
    openTranslationModelMenu = scope;
  }

  function closeTranslationModelMenu() {
    openTranslationModelMenu = null;
  }

  function handleSettingsKeydown(event: KeyboardEvent) {
    const isClose = event.key === "Escape" || (event.metaKey && event.key.toLowerCase() === "w");
    if (!isClose) return;
    // Esc first dismisses an open model menu; only an already-closed menu lets Esc close the window.
    if (event.key === "Escape" && openTranslationModelMenu) {
      closeTranslationModelMenu();
      return;
    }
    if (!isTauri) return;
    event.preventDefault();
    void invoke("close_settings_window");
  }

  async function toggleFavorite(field: "favoriteLocalModelIDs" | "favoriteOpenRouterModels", modelID: string) {
    if (!settingsState) return;
    const current = settingsState.settings[field];
    const nextValue = current.includes(modelID)
      ? current.filter((value) => value !== modelID)
      : [...current, modelID];
    await updateField(field, nextValue);
  }

  async function useLocalModel(modelID: string) {
    if (!settingsState) return;
    await saveSettings({ ...settingsState.settings, provider: "localHyMT2", localModelID: modelID });
  }

  async function useOpenRouterTextModel(modelID: string) {
    if (!settingsState) return;
    await saveSettings({ ...settingsState.settings, provider: "openRouter", openRouterTextModel: modelID });
  }

  async function useOpenRouterVisionModel(modelID: string) {
    if (!settingsState) return;
    await saveSettings({ ...settingsState.settings, openRouterVisionModel: modelID });
  }

  async function loadOpenRouterAPIKeyState() {
    if (!isTauri) {
      openRouterAPIKeyState = { configured: false, path: "~/.config/cctrans/.env" };
      return;
    }
    try {
      openRouterAPIKeyState = await invoke<OpenRouterAPIKeyState>("load_openrouter_api_key_state");
    } catch (error) {
      pushNotice({ title: "OpenRouter API Key", message: formatError(error), ok: false });
    }
  }

  async function saveOpenRouterAPIKey() {
    if (!openRouterAPIKeyInput.trim()) {
      pushNotice({ title: "OpenRouter API Key", message: "Enter a key before saving.", ok: false });
      return;
    }
    try {
      openRouterAPIKeyState = isTauri
        ? await invoke<OpenRouterAPIKeyState>("save_openrouter_api_key", { value: openRouterAPIKeyInput })
        : { configured: true, path: "~/.config/cctrans/.env" };
      openRouterAPIKeyInput = "";
      pushNotice({ title: "OpenRouter API Key", message: "Saved.", ok: true });
    } catch (error) {
      pushNotice({ title: "OpenRouter API Key", message: formatError(error), ok: false });
    }
  }

  async function clearOpenRouterAPIKey() {
    try {
      openRouterAPIKeyState = isTauri
        ? await invoke<OpenRouterAPIKeyState>("clear_openrouter_api_key")
        : { configured: false, path: "~/.config/cctrans/.env" };
      openRouterAPIKeyInput = "";
      pushNotice({ title: "OpenRouter API Key", message: "Cleared.", ok: true });
    } catch (error) {
      pushNotice({ title: "OpenRouter API Key", message: formatError(error), ok: false });
    }
  }

  async function resetField(field: SettingField) {
    if (!settingsState) return;

    isSaving = true;
    try {
      settingsState = isTauri
        ? await invoke<SettingsState>("reset_setting", { field })
        : withBrowserOverrides(settingsState, {
            ...settingsState.settings,
            [field]: settingsState.defaults[field]
          });
    } catch (error) {
      pushNotice({
        title: "Reset failed",
        message: formatError(error),
        ok: false
      });
    } finally {
      isSaving = false;
    }
  }

  async function resetAll() {
    if (!settingsState) return;
    await saveSettings({ ...settingsState.defaults });
  }

  async function runAction(action: string) {
    if (!settingsState) return;

    const fallback: ActionResult = {
      title: actionTitle(action),
      message: "Preview action recorded.",
      ok: true
    };

    try {
      const result = isTauri
        ? await invoke<ActionResult>("perform_settings_action", {
            action,
            settings: settingsState.settings
          })
        : fallback;
      lastResult = `${result.title}: ${result.message}`;
      pushNotice(result);
    } catch (error) {
      const result = {
        title: actionTitle(action),
        message: formatError(error),
        ok: false
      };
      lastResult = `${result.title}: ${result.message}`;
      pushNotice(result);
    }
  }

  function withBrowserOverrides(current: SettingsState, settings: Settings): SettingsState {
    const overrides = Object.fromEntries(
      (Object.keys(current.overrides) as SettingField[]).map((field) => [field, isOverride(settings, current.defaults, field)])
    ) as Record<SettingField, boolean>;

    return {
      ...current,
      settings,
      overrides
    };
  }

  function pushNotice(result: ActionResult) {
    notices = [result, ...notices].slice(0, 3);
  }

  function formatError(error: unknown) {
    return error instanceof Error ? error.message : String(error);
  }

  function actionTitle(action: string) {
    const titles: Record<string, string> = {
      runTextTest: "Text Test",
      translateScreenshot: "Screenshot Translation",
      showRequestLogs: "Request Logs",
      showLocalModelSetup: "Model Setup",
      openInputMonitoring: "Input Monitoring",
      openAccessibility: "Accessibility",
      openScreenRecording: "Screen Recording",
      requestKeyboardPrompt: "Keyboard Prompt",
      openPermissionHelper: "Permission Helper"
    };
    return titles[action] ?? "Action";
  }

  function toastPositionValue(value: string): ToastPosition {
    if (value === "bottomLeft" || value === "topRight" || value === "topLeft" || value === "custom") return value;
    return "bottomRight";
  }

  async function updateToastPosition(value: string) {
    if (!settingsState) return;
    const toastPosition = toastPositionValue(value);
    await saveSettings({
      ...settingsState.settings,
      toastPosition,
      toastCustomPosition: toastPosition === "custom" ? settingsState.settings.toastCustomPosition : null
    });
  }

  function isOverride(settings: Settings, defaults: Settings, field: SettingField) {
    const value = settings[field];
    const defaultValue = defaults[field];
    return Array.isArray(value) && Array.isArray(defaultValue)
      ? JSON.stringify(value) !== JSON.stringify(defaultValue)
      : value !== defaultValue;
  }

  function translationModelValue(settings: Settings, defaults: Settings) {
    if (settings.provider === "localHyMT2") {
      return settings.localModelID === defaults.localModelID ? "localHyMT2:default" : `localHyMT2:${settings.localModelID}`;
    }
    return settings.openRouterTextModel === defaults.openRouterTextModel
      ? "openRouter:default"
      : `openRouter:${settings.openRouterTextModel}`;
  }

  function localModelLabel(value: string) {
    return settingsState?.options.localModels.find((option) => option.value === value)?.label ?? value;
  }

  function openRouterModelLabel(value: string) {
    return settingsState?.options.openRouterModels.find((option) => option.value === value)?.label ?? value;
  }

  function translationModelProviderLabel(provider: TranslationProvider) {
    return provider === "localHyMT2" ? "Local Model" : "OpenRouter LLM";
  }

  function translationModelProviderDetail(settings: Settings) {
    return settings.provider === "localHyMT2" ? "Local runtime active" : "OpenRouter API active";
  }

  function translationModelName(settings: Settings) {
    return settings.provider === "localHyMT2"
      ? localModelLabel(settings.localModelID)
      : openRouterModelLabel(settings.openRouterTextModel);
  }

  function formatPrice(model: OpenRouterModelOption) {
    if (model.isFree) return "Free";
    return `$${formatCompactPrice(model.promptPricePerMillion)} in / $${formatCompactPrice(model.completionPricePerMillion)} out per 1M`;
  }

  function formatUnitPrice(value: number) {
    if (value === 0) return "Free";
    return `$${formatCompactPrice(value)}`;
  }

  function formatCompactPrice(value: number) {
    return value.toFixed(value < 1 ? 2 : 1).replace(/\.?0+$/, "");
  }

  function modalityText(model: OpenRouterModelOption) {
    return model.modalities.map((value) => value.charAt(0).toUpperCase() + value.slice(1)).join(" + ");
  }

  function modelMetaText(model: OpenRouterModelOption) {
    const parts = [
      modalityText(model),
      model.releaseDate,
      `${formatContextWindow(model.contextWindow)} context`
    ];
    if (model.isReasoning) parts.push("Reasoning");
    if (model.isRecommended) parts.push("Recommended");
    return parts.join(" · ");
  }

  function formatContextWindow(value: number) {
    if (value >= 1_000_000) return `${formatCompactPrice(value / 1_000_000)}M`;
    if (value >= 1_000) return `${formatCompactPrice(value / 1_000)}K`;
    return String(value);
  }

  function sortOpenRouterModels(models: OpenRouterModelOption[]) {
    const sorted = [...models];
    sorted.sort((left, right) => {
      const multiplier = openRouterSort.direction === "asc" ? 1 : -1;
      if (openRouterSort.key === "model") {
        return left.label.localeCompare(right.label) * multiplier;
      }
      if (openRouterSort.key === "inputPrice") {
        return (
          left.promptPricePerMillion - right.promptPricePerMillion ||
          left.completionPricePerMillion - right.completionPricePerMillion ||
          left.label.localeCompare(right.label)
        ) * multiplier;
      }
      if (openRouterSort.key === "outputPrice") {
        return (
          left.completionPricePerMillion - right.completionPricePerMillion ||
          left.promptPricePerMillion - right.promptPricePerMillion ||
          left.label.localeCompare(right.label)
        ) * multiplier;
      }
      return (left.contextWindow - right.contextWindow || left.label.localeCompare(right.label)) * multiplier;
    });
    return sorted;
  }

  function updateOpenRouterSort(key: OpenRouterSortKey) {
    openRouterSort = {
      key,
      direction: openRouterSort.key === key && openRouterSort.direction === "asc" ? "desc" : "asc"
    };
  }

  function sortLabel(key: OpenRouterSortKey) {
    if (openRouterSort.key !== key) return "Sort";
    return openRouterSort.direction === "asc" ? "Asc" : "Desc";
  }

</script>

{#snippet translationModelPicker(scope: "general" | "models", state: SettingsState)}
  <div class="nested-model-picker" class:open={openTranslationModelMenu === scope}>
    <button
      class="nested-model-trigger"
      type="button"
      aria-haspopup="menu"
      aria-expanded={openTranslationModelMenu === scope}
      onclick={() => toggleTranslationModelMenu(scope)}
    >
      <span class:open-router={state.settings.provider === "openRouter"} class="trigger-provider">
        {#if state.settings.provider === "localHyMT2"}<Cpu size={13} />{:else}<Cloud size={13} />{/if}
        {translationModelProviderLabel(state.settings.provider)}
      </span>
      <span class="trigger-model">{translationModelName(state.settings)}</span>
      <ChevronDown size={14} />
    </button>

    {#if openTranslationModelMenu === scope}
      <div class="nested-model-menu" role="menu" aria-label="Translation Model">
        <div class="nested-model-providers" role="group" aria-label="Model providers">
          <button
            type="button"
            class:active={activeTranslationModelProvider === "localHyMT2"}
            onmouseenter={() => (activeTranslationModelProvider = "localHyMT2")}
            onclick={() => (activeTranslationModelProvider = "localHyMT2")}
          >
            <Cpu size={14} />
            <span>Local Model</span>
            <ChevronRight size={13} />
          </button>
          <button
            type="button"
            class:active={activeTranslationModelProvider === "openRouter"}
            onmouseenter={() => (activeTranslationModelProvider = "openRouter")}
            onclick={() => (activeTranslationModelProvider = "openRouter")}
          >
            <Cloud size={14} />
            <span>OpenRouter LLM</span>
            <ChevronRight size={13} />
          </button>
        </div>

        <div class="nested-model-options" role="group" aria-label="Models">
          {#if activeTranslationModelProvider === "localHyMT2"}
            <button
              type="button"
              class:selected={translationModelValue(state.settings, state.defaults) === "localHyMT2:default"}
              onclick={() => chooseTranslationModel("localHyMT2:default")}
            >
              <span>
                <strong>Default</strong>
                <small>{localModelLabel(state.defaults.localModelID)}</small>
              </span>
              {#if translationModelValue(state.settings, state.defaults) === "localHyMT2:default"}<Check size={14} />{/if}
            </button>
            {#each state.options.localModels as option}
              <button
                type="button"
                class:selected={translationModelValue(state.settings, state.defaults) === `localHyMT2:${option.value}`}
                onclick={() => chooseTranslationModel(`localHyMT2:${option.value}`)}
              >
                <span>
                  <strong>{option.label}</strong>
                  <small>{option.note ?? "Local runtime"}</small>
                </span>
                {#if translationModelValue(state.settings, state.defaults) === `localHyMT2:${option.value}`}<Check size={14} />{/if}
              </button>
            {/each}
          {:else}
            <button
              type="button"
              class:selected={translationModelValue(state.settings, state.defaults) === "openRouter:default"}
              onclick={() => chooseTranslationModel("openRouter:default")}
            >
              <span>
                <strong>Default</strong>
                <small>{openRouterModelLabel(state.defaults.openRouterTextModel)}</small>
              </span>
              {#if translationModelValue(state.settings, state.defaults) === "openRouter:default"}<Check size={14} />{/if}
            </button>
            {#each state.options.openRouterModels as option}
              <button
                type="button"
                class:selected={translationModelValue(state.settings, state.defaults) === `openRouter:${option.value}`}
                onclick={() => chooseTranslationModel(`openRouter:${option.value}`)}
              >
                <span>
                  <strong>{option.label}</strong>
                  <small>{formatPrice(option)} · {modelMetaText(option)}</small>
                </span>
                {#if translationModelValue(state.settings, state.defaults) === `openRouter:${option.value}`}<Check size={14} />{/if}
              </button>
            {/each}
          {/if}
        </div>
      </div>
    {/if}
  </div>
{/snippet}

<svelte:window onkeydown={handleSettingsKeydown} />

{#if settingsState}
  <div class="app-frame">
    {#if openTranslationModelMenu}
      <button class="menu-scrim" type="button" aria-label="Close model menu" onclick={closeTranslationModelMenu}></button>
    {/if}
    <aside class="sidebar" aria-label="Settings sections">
      <button class:active={activeSection === "general"} onclick={() => (activeSection = "general")}>
        <SettingsIcon size={15} />
        <span>General</span>
      </button>
      <button class:active={activeSection === "models"} onclick={() => (activeSection = "models")}>
        <Cpu size={15} />
        <span>Models</span>
      </button>
      <button class:active={activeSection === "shortcuts"} onclick={() => (activeSection = "shortcuts")}>
        <Keyboard size={15} />
        <span>Shortcuts</span>
      </button>
      <button class:active={activeSection === "excluded"} onclick={() => (activeSection = "excluded")}>
        <Ban size={15} />
        <span>Excluded Apps</span>
      </button>
      <div class="sidebar-separator"></div>
      <button class:active={activeSection === "advanced"} onclick={() => (activeSection = "advanced")}>
        <SlidersHorizontal size={15} />
        <span>Advanced</span>
      </button>
      <button class:active={activeSection === "info"} onclick={() => (activeSection = "info")}>
        <Info size={15} />
        <span>Info</span>
      </button>
      <button class="reset-all" title="Reset every setting to current code defaults" onclick={resetAll}>
        <RotateCcw size={14} />
        <span>Reset Defaults</span>
      </button>
    </aside>

    <main class="content">
      <header class="content-header">
        <h1>{sectionTitles[activeSection]}</h1>
        <span class:muted={isSaving} class="save-state">{isSaving ? "Saving..." : "Saved"}</span>
      </header>

      {#if activeSection === "general"}
        <section class="pane">
          <h2>Default Behavior</h2>
          <div class="setting-group menu-setting-group">
            <div class="setting-row model-picker-row">
              <span class="setting-copy">
                <strong>Translation Model</strong>
                <span>{translationModelProviderDetail(settingsState.settings)}</span>
              </span>
              {@render translationModelPicker("general", settingsState)}
              <button
                class="reset-row"
                class:visible={settingsState.overrides.provider || settingsState.overrides.localModelID || settingsState.overrides.openRouterTextModel}
                disabled={!settingsState.overrides.provider && !settingsState.overrides.localModelID && !settingsState.overrides.openRouterTextModel}
                title="Reset Translation Model"
                onclick={async () => {
                  closeTranslationModelMenu();
                  await resetField("provider");
                  await resetField("localModelID");
                  await resetField("openRouterTextModel");
                }}
              >
                <RotateCcw size={13} />
              </button>
            </div>

            <label class="setting-row">
              <span class="setting-copy">
                <strong>Source Language</strong>
              </span>
              <select
                value={settingsState.settings.sourceLanguage}
                onchange={(event) => updateField("sourceLanguage", event.currentTarget.value)}
              >
                {#each settingsState.options.sourceLanguages as option}
                  <option value={option.value}>{option.label}</option>
                {/each}
              </select>
              <button
                class="reset-row"
                class:visible={settingsState.overrides.sourceLanguage}
                disabled={!settingsState.overrides.sourceLanguage}
                title="Reset Source Language"
                onclick={() => resetField("sourceLanguage")}
              >
                <RotateCcw size={13} />
              </button>
            </label>

            <label class="setting-row">
              <span class="setting-copy">
                <strong>Target Language</strong>
              </span>
              <select
                value={settingsState.settings.targetLanguage}
                onchange={(event) => updateField("targetLanguage", event.currentTarget.value)}
              >
                {#each settingsState.options.targetLanguages as option}
                  <option value={option.value}>{option.label}</option>
                {/each}
              </select>
              <button
                class="reset-row"
                class:visible={settingsState.overrides.targetLanguage}
                disabled={!settingsState.overrides.targetLanguage}
                title="Reset Target Language"
                onclick={() => resetField("targetLanguage")}
              >
                <RotateCcw size={13} />
              </button>
            </label>

            <label class="setting-row">
              <span class="setting-copy">
                <strong>Toast Position</strong>
              </span>
              <select
                value={settingsState.settings.toastPosition}
                onchange={(event) => updateToastPosition(event.currentTarget.value)}
              >
                {#each settingsState.options.toastPositions as option}
                  <option value={option.value}>{option.label}</option>
                {/each}
              </select>
              <button
                class="reset-row"
                class:visible={settingsState.overrides.toastPosition}
                disabled={!settingsState.overrides.toastPosition}
                title="Reset Toast Position"
                onclick={() => resetField("toastPosition")}
              >
                <RotateCcw size={13} />
              </button>
            </label>
          </div>

          <h2>Diagnostics</h2>
          <div class="setting-group">
            <div class="setting-row text-row">
              <span class="setting-copy">
                <strong>Last Result</strong>
              </span>
              <span class="last-result">{lastResult}</span>
              <span class="reset-row spacer"></span>
            </div>
            <div class="action-grid">
              <button onclick={() => runAction("runTextTest")}><Play size={14} />Run Text Test</button>
              <button onclick={() => runAction("translateScreenshot")}><Camera size={14} />Translate Screenshot</button>
              <button onclick={() => runAction("showRequestLogs")}><ScrollText size={14} />Request Logs</button>
            </div>
          </div>
        </section>
      {:else if activeSection === "models"}
        <section class="pane">
          <h2>Active Translation Model</h2>
          <div class="setting-group menu-setting-group">
            <div class="setting-row model-picker-row">
              <span class="setting-copy">
                <strong>Translation Model</strong>
                <span>{translationModelProviderDetail(settingsState.settings)}</span>
              </span>
              {@render translationModelPicker("models", settingsState)}
              <button
                class="reset-row"
                class:visible={settingsState.overrides.provider || settingsState.overrides.localModelID || settingsState.overrides.openRouterTextModel}
                disabled={!settingsState.overrides.provider && !settingsState.overrides.localModelID && !settingsState.overrides.openRouterTextModel}
                title="Reset Translation Model"
                onclick={async () => {
                  closeTranslationModelMenu();
                  await resetField("provider");
                  await resetField("localModelID");
                  await resetField("openRouterTextModel");
                }}
              >
                <RotateCcw size={13} />
              </button>
            </div>
          </div>

          <h2>Local Model Favorites</h2>
          <div class="setting-group">
            {#each settingsState.options.localModels as option}
              <div class="model-row">
                <button
                  class="favorite-button"
                  class:active={settingsState.settings.favoriteLocalModelIDs.includes(option.value)}
                  title="Toggle favorite"
                  onclick={() => toggleFavorite("favoriteLocalModelIDs", option.value)}
                >
                  <Star size={14} />
                </button>
                <div class="model-copy">
                  <strong>{option.label}</strong>
                  <span>{option.note ?? (option.value === settingsState.defaults.localModelID ? "Default" : "Local runtime")}</span>
                </div>
                <button class="inline-action" onclick={() => useLocalModel(option.value)}><Cpu size={13} />Use</button>
              </div>
            {/each}
            <div class="action-grid single">
              <button onclick={() => runAction("showLocalModelSetup")}><ShieldCheck size={14} />Model Setup</button>
            </div>
          </div>

          <h2>OpenRouter API Key</h2>
          <div class="setting-group">
            <div class="setting-row text-row">
              <span class="setting-copy">
                <strong>Status</strong>
                <span>{openRouterAPIKeyState.path}</span>
              </span>
              <span class:ready={openRouterAPIKeyState.configured} class="status-pill">
                <KeyRound size={13} />{openRouterAPIKeyState.configured ? "Configured" : "Not configured"}
              </span>
              <span class="reset-row spacer"></span>
            </div>
            <div class="api-key-row">
              <input
                type="password"
                placeholder={openRouterAPIKeyState.configured ? "Enter a new key to replace the saved key" : "OpenRouter API key"}
                value={openRouterAPIKeyInput}
                oninput={(event) => (openRouterAPIKeyInput = event.currentTarget.value)}
              />
              <button onclick={saveOpenRouterAPIKey}><KeyRound size={13} />Save</button>
              <button onclick={clearOpenRouterAPIKey}>Clear</button>
            </div>
          </div>

          <h2>OpenRouter Models</h2>
          <div class="setting-group">
            <label class="setting-row">
              <span class="setting-copy">
                <strong>Text Model</strong>
              </span>
              <select
                value={settingsState.settings.openRouterTextModel === settingsState.defaults.openRouterTextModel ? "default" : settingsState.settings.openRouterTextModel}
                onchange={(event) => updateModelField("openRouterTextModel", event.currentTarget.value)}
              >
                <option value="default">Default ({openRouterModelLabel(settingsState.defaults.openRouterTextModel)})</option>
                {#each settingsState.options.openRouterModels as option}
                  <option value={option.value}>{option.label}</option>
                {/each}
              </select>
              <button
                class="reset-row"
                class:visible={settingsState.overrides.openRouterTextModel}
                disabled={!settingsState.overrides.openRouterTextModel}
                title="Reset Text Model"
                onclick={() => resetField("openRouterTextModel")}
              >
                <RotateCcw size={13} />
              </button>
            </label>
            <label class="setting-row">
              <span class="setting-copy">
                <strong>Vision Model</strong>
              </span>
              <select
                value={settingsState.settings.openRouterVisionModel === settingsState.defaults.openRouterVisionModel ? "default" : settingsState.settings.openRouterVisionModel}
                onchange={(event) => updateModelField("openRouterVisionModel", event.currentTarget.value)}
              >
                <option value="default">Default ({openRouterModelLabel(settingsState.defaults.openRouterVisionModel)})</option>
                {#each settingsState.options.openRouterModels.filter((option) => option.modalities.includes("image")) as option}
                  <option value={option.value}>{option.label}</option>
                {/each}
              </select>
              <button
                class="reset-row"
                class:visible={settingsState.overrides.openRouterVisionModel}
                disabled={!settingsState.overrides.openRouterVisionModel}
                title="Reset Vision Model"
                onclick={() => resetField("openRouterVisionModel")}
              >
                <RotateCcw size={13} />
              </button>
            </label>
            <div class="openrouter-table-wrap">
              <table class="openrouter-table">
                <thead>
                  <tr>
                    <th class="favorite-column" aria-label="Favorite"></th>
                    <th>
                      <button type="button" class:active={openRouterSort.key === "model"} onclick={() => updateOpenRouterSort("model")}>
                        Model <ArrowUpDown size={12} /><span class="sort-state">{sortLabel("model")}</span>
                      </button>
                    </th>
                    <th>
                      <button type="button" class:active={openRouterSort.key === "inputPrice"} onclick={() => updateOpenRouterSort("inputPrice")}>
                        Input <ArrowUpDown size={12} /><span class="sort-state">{sortLabel("inputPrice")}</span>
                      </button>
                    </th>
                    <th>
                      <button type="button" class:active={openRouterSort.key === "outputPrice"} onclick={() => updateOpenRouterSort("outputPrice")}>
                        Output <ArrowUpDown size={12} /><span class="sort-state">{sortLabel("outputPrice")}</span>
                      </button>
                    </th>
                    <th>Modalities</th>
                    <th>
                      <button type="button" class:active={openRouterSort.key === "context"} onclick={() => updateOpenRouterSort("context")}>
                        Context <ArrowUpDown size={12} /><span class="sort-state">{sortLabel("context")}</span>
                      </button>
                    </th>
                    <th>Release</th>
                    <th>Use</th>
                  </tr>
                </thead>
                <tbody>
                  {#each sortOpenRouterModels(settingsState.options.openRouterModels) as model}
                    <tr class={settingsState.settings.provider === "openRouter" && settingsState.settings.openRouterTextModel === model.value ? "selected-model" : ""}>
                      <td class="favorite-column">
                        <button
                          class="favorite-button"
                          class:active={settingsState.settings.favoriteOpenRouterModels.includes(model.value)}
                          title="Toggle favorite"
                          onclick={() => toggleFavorite("favoriteOpenRouterModels", model.value)}
                        >
                          <Star size={14} />
                        </button>
                      </td>
                      <td class="model-name-cell">
                        <strong>{model.label}</strong>
                        <span>{model.value}</span>
                        <div class="model-badges">
                          {#if model.isRecommended}<em>Recommended</em>{/if}
                          {#if model.isFree}<em>Free</em>{/if}
                          {#if model.isReasoning}<em>Reasoning</em>{/if}
                        </div>
                      </td>
                      <td class="price-cell">{formatUnitPrice(model.promptPricePerMillion)}</td>
                      <td class="price-cell">{formatUnitPrice(model.completionPricePerMillion)}</td>
                      <td>{modalityText(model)}</td>
                      <td>{formatContextWindow(model.contextWindow)}</td>
                      <td>{model.releaseDate}</td>
                      <td>
                        <div class="model-actions">
                          <button class="inline-action" onclick={() => useOpenRouterTextModel(model.value)}><Cloud size={13} />Text</button>
                          {#if model.modalities.includes("image")}
                            <button class="inline-action" onclick={() => useOpenRouterVisionModel(model.value)}>Vision</button>
                          {/if}
                        </div>
                      </td>
                    </tr>
                  {/each}
                </tbody>
              </table>
            </div>
          </div>
        </section>
      {:else if activeSection === "shortcuts"}
        <section class="pane">
          <h2>Global Shortcuts</h2>
          <div class="setting-group">
            <div class="setting-row">
              <span class="setting-copy">
                <strong>Clipboard Translation</strong>
                <span>Cmd+C twice</span>
              </span>
              <kbd>⌘ C ×2</kbd>
              <span class="reset-row spacer"></span>
            </div>
            <div class="setting-row">
              <span class="setting-copy">
                <strong>Screenshot Translation</strong>
                <span>Shift+Cmd+2</span>
              </span>
              <kbd>⇧ ⌘ 2</kbd>
              <span class="reset-row spacer"></span>
            </div>
          </div>

          <h2>Permissions</h2>
          <div class="setting-group">
            <div class="setting-row">
              <span class="setting-copy">
                <strong>Keyboard</strong>
              </span>
              <span class:ready={settingsState.permissions.keyboard} class="status-pill">
                {settingsState.permissions.keyboard ? "Ready" : "Not granted"}
              </span>
              <span class="reset-row spacer"></span>
            </div>
            <div class="setting-row">
              <span class="setting-copy">
                <strong>Keyboard Cursor</strong>
                <span>Accessibility permission for caret-anchored popovers</span>
              </span>
              <span class:ready={settingsState.permissions.accessibility} class="status-pill">
                {settingsState.permissions.accessibility ? "Ready" : "Not granted"}
              </span>
              <span class="reset-row spacer"></span>
            </div>
            <div class="setting-row">
              <span class="setting-copy">
                <strong>Screen Recording</strong>
              </span>
              <span class:ready={settingsState.permissions.screen} class="status-pill">
                {settingsState.permissions.screen ? "Ready" : "Not granted"}
              </span>
              <span class="reset-row spacer"></span>
            </div>
            <div class="action-grid single">
              <button onclick={() => runAction("openPermissionHelper")}><ShieldCheck size={14} />Permission Helper</button>
            </div>
          </div>
        </section>
      {:else if activeSection === "excluded"}
        <section class="pane">
          <h2>Current App Contract</h2>
          <div class="setting-group">
            <div class="setting-row text-row">
              <span class="setting-copy">
                <strong>Excluded Apps</strong>
                <span>No persisted exclusion setting exists in the Swift app.</span>
              </span>
              <span class="last-result">None</span>
              <span class="reset-row spacer"></span>
            </div>
          </div>
        </section>
      {:else if activeSection === "advanced"}
        <section class="pane">
          <h2>Local Runtime</h2>
          <div class="setting-group">
            <label class="setting-row">
              <span class="setting-copy">
                <strong>Local Backend Script</strong>
                <span class="setting-note">Optional override for the local translation runner. Leave blank to use the bundled script or the selected model's backend.</span>
              </span>
              <input
                placeholder="Automatic"
                value={settingsState.settings.localHyMT2BackendPath ?? ""}
                onblur={(event) => updateNullableField("localHyMT2BackendPath", event.currentTarget.value)}
              />
              <button
                class="reset-row"
                class:visible={settingsState.overrides.localHyMT2BackendPath}
                disabled={!settingsState.overrides.localHyMT2BackendPath}
                title="Reset Backend Path"
                onclick={() => resetField("localHyMT2BackendPath")}
              >
                <RotateCcw size={13} />
              </button>
            </label>
            <label class="setting-row">
              <span class="setting-copy">
                <strong>Custom Model Catalog</strong>
                <span class="setting-note">JSON file that adds local model choices. Blank uses ~/.config/cctrans/local-models.json when present.</span>
              </span>
              <input
                placeholder="~/.config/cctrans/local-models.json"
                value={settingsState.settings.customLocalModelsPath ?? ""}
                onblur={(event) => updateNullableField("customLocalModelsPath", event.currentTarget.value)}
              />
              <button
                class="reset-row"
                class:visible={settingsState.overrides.customLocalModelsPath}
                disabled={!settingsState.overrides.customLocalModelsPath}
                title="Reset Custom Models JSON"
                onclick={() => resetField("customLocalModelsPath")}
              >
                <RotateCcw size={13} />
              </button>
            </label>
          </div>
        </section>
      {:else}
        <section class="pane">
          <h2>Storage</h2>
          <div class="setting-group">
            <div class="setting-row text-row">
              <span class="setting-copy">
                <strong>Override Store</strong>
                <span>{settingsState.storagePath}</span>
              </span>
              <span class="last-result">Code defaults apply when no override exists.</span>
              <span class="reset-row spacer"></span>
            </div>
          </div>

          <h2>Provider Status</h2>
          <div class="setting-group">
            <div class="setting-row">
              <span class="setting-copy">
                <strong>API</strong>
              </span>
              <span class="api-status"><CheckCircle2 size={14} />Configured externally</span>
              <span class="reset-row spacer"></span>
            </div>
          </div>
        </section>
      {/if}
    </main>

    {#if notices.length > 0}
      <div class="toast-stack" aria-live="polite">
        {#each notices as notice}
          <article class:ok={notice.ok} class="toast">
            <strong>{notice.title}</strong>
            <span>{notice.message}</span>
          </article>
        {/each}
      </div>
    {/if}
  </div>
{:else}
  <div class="loading">Loading settings...</div>
{/if}
