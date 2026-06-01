import "./app.css";
import App from "./App.svelte";
import TranslationPopover from "./TranslationPopover.svelte";
import { mount } from "svelte";

const params = new URLSearchParams(window.location.search);
const Component = params.get("surface") === "translation" ? TranslationPopover : App;

const app = mount(Component, {
  target: document.getElementById("app")!
});

export default app;
