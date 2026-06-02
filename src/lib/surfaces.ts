export type AppSurface =
  | "settings"
  | "translation"
  | "local-model-setup"
  | "request-logs"
  | "permission-helper";

export function currentSurface(): AppSurface {
  const surface = new URLSearchParams(window.location.search).get("surface");
  if (
    surface === "translation" ||
    surface === "local-model-setup" ||
    surface === "request-logs" ||
    surface === "permission-helper"
  ) {
    return surface;
  }
  return "settings";
}
