<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import { onMount } from "svelte";
  import { Accessibility, Keyboard, Monitor, MousePointer2, RefreshCw, ShieldCheck } from "@lucide/svelte";
  import { cloneFallbackState, type ActionResult, type SettingsState } from "./lib/settings";

  let settingsState = $state<SettingsState | null>(null);
  let result = $state<ActionResult | null>(null);

  onMount(load);

  async function load() {
    try {
      settingsState = await invoke<SettingsState>("load_settings");
    } catch {
      settingsState = cloneFallbackState();
    }
  }

  async function action(action: string) {
    if (!settingsState) return;
    result = await invoke<ActionResult>("perform_settings_action", {
      action,
      settings: settingsState.settings
    });
    await load();
  }
</script>

{#if settingsState}
  <main class="utility-frame permission-frame">
    <header class="surface-header">
      <div>
        <h1>Permission Helper</h1>
        <p>Grant keyboard permissions for Cmd+C detection, Accessibility for caret popovers, and screen permissions for screenshot translation.</p>
      </div>
      <button onclick={load}><RefreshCw size={14} />Refresh</button>
    </header>

    <section class="permission-grid">
      <article class="app-card">
        <ShieldCheck size={58} />
        <strong>CopyTranslator.app</strong>
        <span>Use the actions on the right to add the app in macOS privacy settings. Windows support will use the same status/action contract here.</span>
      </article>

      <div class="permission-column">
        <section class="setting-group standalone">
          <div class="setting-row">
            <span class="setting-copy"><strong>Keyboard</strong></span>
            <span class:ready={settingsState.permissions.keyboard} class="status-pill">
              {settingsState.permissions.keyboard ? "Ready" : "Not granted"}
            </span>
            <span class="reset-row spacer"></span>
          </div>
          <div class="setting-row">
            <span class="setting-copy">
              <strong>Keyboard Cursor</strong>
              <span>Required for popovers near the text caret</span>
            </span>
            <span class:ready={settingsState.permissions.accessibility} class="status-pill">
              {settingsState.permissions.accessibility ? "Ready" : "Not granted"}
            </span>
            <span class="reset-row spacer"></span>
          </div>
          <div class="setting-row">
            <span class="setting-copy"><strong>Screen Recording</strong></span>
            <span class:ready={settingsState.permissions.screen} class="status-pill">
              {settingsState.permissions.screen ? "Ready" : "Not granted"}
            </span>
            <span class="reset-row spacer"></span>
          </div>
        </section>

        <section class="action-list">
          <button onclick={() => action("openInputMonitoring")}><Keyboard size={14} />Open Input Monitoring Settings</button>
          <button onclick={() => action("openAccessibility")}><Accessibility size={14} />Open Accessibility Settings</button>
          <button onclick={() => action("openScreenRecording")}><Monitor size={14} />Open Screen Recording Settings</button>
          <button onclick={() => action("requestKeyboardPrompt")}><MousePointer2 size={14} />Request Keyboard Prompt</button>
        </section>

        {#if result}
          <p class:ok={result.ok} class="action-result">{result.title}: {result.message}</p>
        {/if}
      </div>
    </section>
  </main>
{:else}
  <div class="loading">Loading permissions...</div>
{/if}
