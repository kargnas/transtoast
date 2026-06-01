export type AppSurface =
  | "settings"
  | "translation"
  | "local-model-setup"
  | "request-logs"
  | "permission-helper"
  | "toast-stack";

export function currentSurface(): AppSurface {
  const surface = new URLSearchParams(window.location.search).get("surface");
  if (
    surface === "translation" ||
    surface === "local-model-setup" ||
    surface === "request-logs" ||
    surface === "permission-helper" ||
    surface === "toast-stack"
  ) {
    return surface;
  }
  return "settings";
}
