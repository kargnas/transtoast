<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import { onMount } from "svelte";
  import {
    Ban,
    Camera,
    CheckCircle2,
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
  let openRouterAPIKeyState = $state<OpenRouterAPIKeyState>({ configured: false, path: "~/.config/copy-translator/.env" });
  let openRouterAPIKeyInput = $state("");

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
      openRouterAPIKeyState = { configured: false, path: "~/.config/copy-translator/.env" };
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
        : { configured: true, path: "~/.config/copy-translator/.env" };
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
        : { configured: false, path: "~/.config/copy-translator/.env" };
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

  function providerValue(value: string): TranslationProvider {
    return value === "openRouter" ? "openRouter" : "localHyMT2";
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

  function formatPrice(model: OpenRouterModelOption) {
    if (model.isFree) return "Free";
    return `$${formatCompactPrice(model.promptPricePerMillion)} in / $${formatCompactPrice(model.completionPricePerMillion)} out per 1M`;
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
</script>

{#if settingsState}
  <div class="app-frame">
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
          <div class="setting-group">
            <label class="setting-row">
              <span class="setting-copy">
                <strong>Translation Model</strong>
              </span>
              <select
                value={translationModelValue(settingsState.settings, settingsState.defaults)}
                onchange={(event) => selectTranslationModel(event.currentTarget.value)}
              >
                <optgroup label="Local Model">
                  <option value="localHyMT2:default">Default ({localModelLabel(settingsState.defaults.localModelID)})</option>
                  {#each settingsState.options.localModels as option}
                    <option value={`localHyMT2:${option.value}`}>{option.label}</option>
                  {/each}
                </optgroup>
                <optgroup label="OpenRouter LLM">
                  <option value="openRouter:default">Default ({openRouterModelLabel(settingsState.defaults.openRouterTextModel)})</option>
                  {#each settingsState.options.openRouterModels as option}
                    <option value={`openRouter:${option.value}`}>{option.label}</option>
                  {/each}
                </optgroup>
              </select>
              <button
                class="reset-row"
                class:visible={settingsState.overrides.provider || settingsState.overrides.localModelID || settingsState.overrides.openRouterTextModel}
                disabled={!settingsState.overrides.provider && !settingsState.overrides.localModelID && !settingsState.overrides.openRouterTextModel}
                title="Reset Translation Model"
                onclick={async () => {
                  await resetField("provider");
                  await resetField("localModelID");
                  await resetField("openRouterTextModel");
                }}
              >
                <RotateCcw size={13} />
              </button>
            </label>

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
          <div class="setting-group">
            <label class="setting-row">
              <span class="setting-copy">
                <strong>Translation Model</strong>
              </span>
              <select
                value={translationModelValue(settingsState.settings, settingsState.defaults)}
                onchange={(event) => selectTranslationModel(event.currentTarget.value)}
              >
                <optgroup label="Local Model">
                  <option value="localHyMT2:default">Default ({localModelLabel(settingsState.defaults.localModelID)})</option>
                  {#each settingsState.options.localModels as option}
                    <option value={`localHyMT2:${option.value}`}>{option.label}</option>
                  {/each}
                </optgroup>
                <optgroup label="OpenRouter LLM">
                  <option value="openRouter:default">Default ({openRouterModelLabel(settingsState.defaults.openRouterTextModel)})</option>
                  {#each settingsState.options.openRouterModels as option}
                    <option value={`openRouter:${option.value}`}>{option.label}</option>
                  {/each}
                </optgroup>
              </select>
              <button
                class="reset-row"
                class:visible={settingsState.overrides.provider || settingsState.overrides.localModelID || settingsState.overrides.openRouterTextModel}
                disabled={!settingsState.overrides.provider && !settingsState.overrides.localModelID && !settingsState.overrides.openRouterTextModel}
                title="Reset Translation Model"
                onclick={async () => {
                  await resetField("provider");
                  await resetField("localModelID");
                  await resetField("openRouterTextModel");
                }}
              >
                <RotateCcw size={13} />
              </button>
            </label>
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
            {#each settingsState.options.openRouterModels as model}
              <div class="model-row">
                <button
                  class="favorite-button"
                  class:active={settingsState.settings.favoriteOpenRouterModels.includes(model.value)}
                  title="Toggle favorite"
                  onclick={() => toggleFavorite("favoriteOpenRouterModels", model.value)}
                >
                  <Star size={14} />
                </button>
                <div class="model-copy">
                  <strong>{model.label}</strong>
                  <span>
                    {formatPrice(model)} · {modelMetaText(model)}
                  </span>
                </div>
                <div class="model-actions">
                  <button class="inline-action" onclick={() => useOpenRouterTextModel(model.value)}><Cloud size={13} />Text</button>
                  {#if model.modalities.includes("image")}
                    <button class="inline-action" onclick={() => useOpenRouterVisionModel(model.value)}>Vision</button>
                  {/if}
                </div>
              </div>
            {/each}
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
            <div class="action-grid">
              <button onclick={() => runAction("openInputMonitoring")}>Input Monitoring</button>
              <button onclick={() => runAction("openAccessibility")}>Accessibility</button>
              <button onclick={() => runAction("openScreenRecording")}>Screen Recording</button>
              <button onclick={() => runAction("requestKeyboardPrompt")}>Keyboard Prompt</button>
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
                <strong>Backend Path</strong>
              </span>
              <input
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
                <strong>Custom Models JSON</strong>
              </span>
              <input
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
