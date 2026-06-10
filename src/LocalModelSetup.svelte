<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import { onMount } from "svelte";
  import { FlaskConical, FolderPlus, RotateCcw, Settings, ShieldCheck } from "@lucide/svelte";
  import {
    localModelRows,
    recommendedLocalModelRow,
    rowForLocalModelID,
    sampleLengths,
    type LocalModelComparisonRow,
    type LocalModelSampleLength
  } from "./lib/localModels";
  import { cloneFallbackState, type BenchmarkResult, type SettingsState } from "./lib/settings";

  let settingsState = $state<SettingsState | null>(null);
  let selectedRow = $state<LocalModelComparisonRow>(recommendedLocalModelRow());
  let sampleLength = $state<LocalModelSampleLength>("Short");
  let output = $state(
    "Prior benchmark results are shown above. Run a fresh test only when you want to validate the selected language pair on this machine."
  );
  let running = $state(false);

  const sourceLanguage = $derived(settingsState?.settings.sourceLanguage ?? "Auto");
  const targetLanguage = $derived(settingsState?.settings.targetLanguage ?? "Korean");
  const benchmarkSourceLanguage = $derived(sourceLanguage === "Auto" ? (targetLanguage === "Korean" ? "English" : "Korean") : sourceLanguage);
  const samples = $derived(selectedRow.samples[sampleLength] ?? []);

  onMount(async () => {
    await load();
  });

  async function load() {
    try {
      settingsState = await invoke<SettingsState>("load_settings");
    } catch {
      settingsState = cloneFallbackState();
    }
    selectedRow = rowForLocalModelID(settingsState.settings.localModelID) ?? recommendedLocalModelRow();
  }

  async function updateLanguage(field: "sourceLanguage" | "targetLanguage", value: string) {
    if (!settingsState) return;
    settingsState = await invoke<SettingsState>("save_settings", {
      settings: {
        ...settingsState.settings,
        [field]: value
      }
    });
    output = `Prior benchmark results are shown above. Run a fresh test to validate ${benchmarkSourceLanguage} -> ${targetLanguage} on this machine.`;
  }

  async function useSelectedModel() {
    if (!settingsState) return;
    if (!selectedRow.localModelID) {
      output = `${selectedRow.model} is not runnable yet. Choose a supported model or add a custom backend.`;
      return;
    }
    settingsState = await invoke<SettingsState>("complete_local_model_setup", {
      settings: {
        ...settingsState.settings,
        localModelID: selectedRow.localModelID,
        sourceLanguage,
        targetLanguage
      }
    });
    output = `Saved selected model: ${selectedRow.model}`;
  }

  async function addCustomModel() {
    settingsState = await invoke<SettingsState>("prepare_custom_local_models");
    output = `Custom model JSON path:
${settingsState.settings.customLocalModelsPath ?? "~/.config/transtoast/local-models.json"}

Create a template with:
uv run scripts/local_model_setup.py --write-template

Then set customBackendPath to a backend that follows docs/local-runtimes.md.`;
  }

  async function runFreshTest() {
    if (!settingsState || running) return;
    running = true;
    output = "Running fresh local test...\n";
    try {
      const result = await invoke<BenchmarkResult>("run_local_model_benchmark", {
        settings: settingsState.settings,
        sourceLanguage: benchmarkSourceLanguage,
        targetLanguage
      });
      output = result.output || "No benchmark output.";
    } catch (error) {
      output = `ERROR: ${error instanceof Error ? error.message : String(error)}`;
    } finally {
      running = false;
    }
  }
</script>

{#if settingsState}
  <main class="utility-frame model-setup-frame">
    <header class="surface-header">
      <div>
        <h1>Tested Local Models</h1>
        <p>Compare bundled local model choices and save the runtime used by clipboard translation.</p>
      </div>
      <div class="toolbar">
        <label>
          Source
          <select value={sourceLanguage} onchange={(event) => updateLanguage("sourceLanguage", event.currentTarget.value)}>
            {#each settingsState.options.sourceLanguages as option}
              <option value={option.value}>{option.label}</option>
            {/each}
          </select>
        </label>
        <label>
          Target
          <select value={targetLanguage} onchange={(event) => updateLanguage("targetLanguage", event.currentTarget.value)}>
            {#each settingsState.options.targetLanguages as option}
              <option value={option.value}>{option.label}</option>
            {/each}
          </select>
        </label>
        <button onclick={runFreshTest} disabled={running}><FlaskConical size={14} />{running ? "Running..." : "Run Fresh Test"}</button>
        <button onclick={addCustomModel}><FolderPlus size={14} />Add Custom</button>
      </div>
    </header>

    <section class="model-grid">
      <div class="table-panel">
        <table>
          <thead>
            <tr>
              <th>Model</th>
              <th>Runtime</th>
              <th>Quality</th>
              <th>Speed / Memory</th>
              <th>Coverage</th>
              <th>Status</th>
              <th>Notes</th>
            </tr>
          </thead>
          <tbody>
            {#each localModelRows as row}
              <tr class:active={row.id === selectedRow.id} onclick={() => (selectedRow = row)}>
                <td>{row.model}{row.isRecommended ? " Recommended" : ""}</td>
                <td>{row.runtime}</td>
                <td>{row.quality}</td>
                <td>{row.speedMemory}</td>
                <td>{row.coverage}</td>
                <td>{row.status}</td>
                <td>{row.notes}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>

      <aside class="detail-panel">
        <span class="eyebrow">Current Choice</span>
        <h2>{selectedRow.model}</h2>
        <strong>{selectedRow.status} | {selectedRow.runtime}</strong>
        <p>{selectedRow.detail}</p>
        {#if selectedRow.licenseNote}<p>{selectedRow.licenseNote}</p>{/if}
      </aside>
    </section>

    <section class="split-panels">
      <article>
        <header>
          <h2>Sample Outputs From Prior Tests</h2>
          <div class="segmented">
            {#each sampleLengths as length}
              <button class:active={sampleLength === length} onclick={() => (sampleLength = length)}>{length}</button>
            {/each}
          </div>
        </header>
        <pre>{samples.length > 0
            ? samples.map((sample) => `[${sample.title}]\nSource: ${sample.source}\nOutput: ${sample.translation}`).join("\n\n")
            : `No saved ${sampleLength.toLowerCase()} sample output for ${selectedRow.model}. Run a fresh test to collect current outputs.`}</pre>
      </article>

      <article>
        <header><h2>Fresh Test Output</h2></header>
        <pre>{output}</pre>
      </article>
    </section>

    <footer class="surface-footer">
      <button class="primary" onclick={useSelectedModel}><ShieldCheck size={14} />{selectedRow.isRecommended ? "Use Recommended" : "Use Selected"}</button>
      <button onclick={load}><RotateCcw size={14} />Reload</button>
      <button onclick={() => invoke("open_app_surface", { surface: "settings" })}><Settings size={14} />Open Settings</button>
    </footer>
  </main>
{:else}
  <div class="loading">Loading local model setup...</div>
{/if}
