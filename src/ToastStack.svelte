<script lang="ts">
  import { Layers } from "@lucide/svelte";

  const toasts = [
    { title: "Stack Test 1", message: "This toast verifies stacked placement." },
    { title: "Stack Test 2", message: "This toast verifies stacked placement." },
    { title: "Stack Test 3", message: "This toast verifies stacked placement." }
  ];
</script>

<main class="toast-preview-frame" aria-label="Toast stack preview">
  {#each toasts as toast}
    <article class="preview-toast">
      <header><Layers size={14} />{toast.title}</header>
      <p>{toast.message}</p>
    </article>
  {/each}
</main>
