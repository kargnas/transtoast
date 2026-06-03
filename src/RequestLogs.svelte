<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import { onMount } from "svelte";
  import { RefreshCw, Trash2 } from "@lucide/svelte";
  import type { RequestLogsState } from "./lib/settings";

  let state = $state<RequestLogsState | null>(null);

  onMount(load);

  async function load() {
    state = await invoke<RequestLogsState>("load_request_logs");
  }

  async function clearLogs() {
    state = await invoke<RequestLogsState>("clear_request_logs");
  }

  function formatTimestamp(value: string) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return value;
    return date.toLocaleTimeString();
  }

  function formatCostCredits(value: number | null | undefined) {
    if (value === null || value === undefined) return "none";
    const fixed = value < 0.0001 ? value.toFixed(8) : value.toFixed(6);
    const trimmed = fixed.replace(/\.?0+$/, "");
    return `${trimmed || "0"} credits`;
  }
</script>

{#if state}
  <main class="utility-frame request-log-frame">
    <header class="surface-header">
      <div>
        <h1>Request Logs</h1>
        <p>{state.storagePath}</p>
      </div>
      <div class="toolbar">
        <button onclick={load}><RefreshCw size={14} />Refresh</button>
        <button onclick={clearLogs}><Trash2 size={14} />Clear</button>
      </div>
    </header>

    <section class="summary-strip">
      <span>Requests <strong>{state.summary.requestCount}</strong></span>
      <span>Duplicate suspects <strong>{state.summary.duplicateSuspectCount}</strong></span>
      <span>Input tokens <strong>{state.summary.promptTokens}</strong></span>
      <span>Output tokens <strong>{state.summary.completionTokens}</strong></span>
      <span>Total tokens <strong>{state.summary.totalTokens}</strong></span>
      <span>Cost <strong>{formatCostCredits(state.summary.costCredits)}</strong></span>
    </section>

    <section class="log-list">
      {#if state.entries.length === 0}
        <div class="empty-state">No translation requests have been logged yet.</div>
      {:else}
        {#each [...state.entries].reverse() as entry}
          <article class="log-entry">
            <header>
              <strong>{formatTimestamp(entry.timestamp)} | {entry.source} | {entry.providerTitle} | {entry.model}</strong>
              <span>
                tokens {entry.promptTokens}/{entry.completionTokens}/{entry.totalTokens} ({entry.usageSource})
                | cost: {formatCostCredits(entry.costCredits)}
                | duplicate suspect: {entry.isDuplicateSuspect ? "yes" : "no"}
                | image: {entry.imageInfo ?? "none"}
              </span>
            </header>
            <p><b>input:</b> {entry.inputPreview}</p>
            <p><b>output:</b> {entry.outputPreview}</p>
          </article>
        {/each}
      {/if}
    </section>
  </main>
{:else}
  <div class="loading">Loading request logs...</div>
{/if}
