import "./app.css";
import App from "./App.svelte";
import LocalModelSetup from "./LocalModelSetup.svelte";
import PermissionHelper from "./PermissionHelper.svelte";
import RequestLogs from "./RequestLogs.svelte";
import ToastStack from "./ToastStack.svelte";
import TranslationPopover from "./TranslationPopover.svelte";
import { currentSurface, type AppSurface } from "./lib/surfaces";
import { mount } from "svelte";

const surfaceComponents: Record<AppSurface, typeof App> = {
  settings: App,
  translation: TranslationPopover as typeof App,
  "local-model-setup": LocalModelSetup as typeof App,
  "request-logs": RequestLogs as typeof App,
  "permission-helper": PermissionHelper as typeof App,
  "toast-stack": ToastStack as typeof App
};

const Component = surfaceComponents[currentSurface()];

const app = mount(Component, {
  target: document.getElementById("app")!
});

export default app;
