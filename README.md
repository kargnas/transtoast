# TransToast

TransToast is a macOS menu-bar app that translates copied text after pressing `Cmd+C` twice, similar to DeepL's quick translation workflow. It also captures the screen with `Shift+Cmd+2` and sends the image to an OpenRouter vision model for translation.

## Features

- `Cmd+C` twice: reads the clipboard text and translates it.
- `Shift+Cmd+2`: captures the current screen and translates visible text in the image.
- Toast results appear in the configured screen corner and stack when multiple translations finish close together.
- Translation Model selection is model-first:
  - **Local Model** choices run local Hy-MT2 inference. The default is the app-recommended local model.
  - **OpenRouter LLM** choices use OpenRouter chat models. Selecting a model also selects the OpenRouter provider.
  - Every model selector includes **Default** to return to the app recommendation.
- Screenshot translation uses an OpenRouter multimodal model. The default is `~google/gemini-flash-latest`.
- OpenRouter text translation automatically attaches the current screen as 1x visual context through the configured vision model when Screen Recording is already trusted.
- OpenRouter text translation keeps the copied selection as the only translation target and may show a small contextual description for ambiguous short selections.
- Request logs show request count, token usage, duplicate suspects, selected model, attached image dimensions, or the screen-context skip reason.

## Requirements

- macOS 15 or later.
- Xcode 26 or later.
- Swift 6.2 or later.
- `uv` for the local Hy-MT2 Python backend.
- Accessibility/Input Monitoring permission for global keyboard detection.
- Screen Recording permission for screenshot translation.

Local Hy-MT2 inference downloads and runs the selected Hugging Face model on this Mac. The 30B-A3B model is large and may require substantial memory, disk, and accelerator support. If the machine cannot load it, select the 1.8B model or use OpenRouter.

## Setup

Create a local environment file:

```sh
cp .env.example .env.local
```

Fill in:

```sh
OPENROUTER_API_KEY=...
HF_TOKEN=...
```

The `.env.local` file is ignored by Git.

## macOS Permissions

TransToast needs these macOS privacy permissions for the global shortcuts:

- **Input Monitoring** or **Accessibility** for `Cmd+C` twice from other apps.
- **Screen Recording** for `Shift+Cmd+2` screenshot translation.

Open the settings window and use **Permission Helper**. It opens the privacy pane and shows a draggable `TransToast.app` icon. Drag that icon into the permission list, turn the toggle on if macOS adds it disabled, then relaunch TransToast.

You can also open System Settings manually:

```sh
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
```

After changing either keyboard or screen permissions, quit and relaunch TransToast so macOS applies the new trust state.

Development builds are signed with a stable local Apple Development identity when one is available. If a previous ad-hoc build was already listed in Screen Recording, remove that old `TransToast` entry or toggle it off and on once after rebuilding. macOS can show the same app name for a stale code identity, but TransToast will report **Screen ready** only when the current signed bundle is actually trusted.

## Run

```sh
./scripts/run-dev.zsh
```

Use the menu-bar icon to open options, request logs, the **Translation Model** selector, permission helpers, and Quit. For local UI verification, you can launch the settings window directly:

```sh
./scripts/run-dev.zsh --show-settings
```

Development app runs intentionally use the signed `dist/TransToast.app` bundle. This keeps Screen Recording, Accessibility, and Input Monitoring permissions tied to the stable `as.kargn.transtoast` bundle id instead of SwiftPM's ad-hoc debug executable identity.

To build and install the app on this Mac:

```sh
./scripts/install-app.zsh --open
```

For another Mac, follow [docs/other-mac-setup.md](docs/other-mac-setup.md).

When the selected **Translation Model** is an **OpenRouter LLM**, TransToast automatically attaches the current screen as downscaled 1x visual context if macOS already reports Screen Recording as trusted. This context capture does not open a Screen Recording prompt during `Cmd+C` double-copy. Local model translation remains text-only. Explicit screenshot translation through `Shift+Cmd+2`, the settings window's **Translate Screenshot** button, or `--screenshot-once` can still request Screen Recording when it is missing.

In Settings, **General** shows the active **Translation Model** directly. **Models** manages favorite local/OpenRouter models, default model selections, OpenRouter text/vision models, model pricing, free model status, modality support, and the local OpenRouter API key entry stored in `~/.config/transtoast/.env`.

Open **Request Logs...** from the menu-bar icon to inspect recent translation requests. The log keeps the last 200 requests and shows whether token usage came from the provider response or an app-side estimate. OpenRouter requests report provider token usage when the response includes it; local model requests use an estimate.

## Local Model Backend

The default local model is `hymt2-mlx-1.8b-4bit`, which calls:

```sh
uv run scripts/runtimes/mlx_lm_translate.py
```

Legacy Hy-MT2 Transformers models still use:

```sh
uv run scripts/hy_mt2_translate.py
```

All local backends accept JSON on standard input:

```json
{
  "text": "The deployment failed.",
  "source_language": "English",
  "target_language": "Korean",
  "model_id": "mlx-community/Hy-MT2-1.8B-4bit"
}
```

It prints:

```json
{
  "translation": "배포가 실패했습니다."
}
```

See [docs/local-runtimes.md](docs/local-runtimes.md) for custom model JSON and backend protocol details.

On first launch, **Local Model Setup** opens with a benchmark-based comparison table before it asks the user to run any fresh test. The table summarizes the models already tested on this project, including recommended, supported, heavy, planned-adapter, fragile-dependency, runtime-issue, and rejected candidates.

## Verification

Useful checks:

```sh
swift build
printf '{"text":"Hello world","source_language":"English","target_language":"Korean","model_id":"mlx-community/Hy-MT2-1.8B-4bit"}' | uv run scripts/runtimes/mlx_lm_translate.py
./scripts/build-app.zsh
./scripts/install-app.zsh --install-dir "$HOME/Applications"
./scripts/package-app.zsh
dist/TransToast.app/Contents/MacOS/TransToast --translate-text-once "Hello world"
dist/TransToast.app/Contents/MacOS/TransToast --translate-text-once "Hello world" --local-model hymt2-mlx-1.8b-4bit
dist/TransToast.app/Contents/MacOS/TransToast --list-local-models
dist/TransToast.app/Contents/MacOS/TransToast --translate-text-once "Hello world" --provider openrouter
dist/TransToast.app/Contents/MacOS/TransToast --screenshot-once
node scripts/openrouter_prompt_probe.mjs --capture
```

For UI verification, run the app, open TextEdit or another text field, copy text twice with `Cmd+C`, and confirm that a translation toast appears. Then use `Shift+Cmd+2` and confirm that a screenshot translation toast appears.
