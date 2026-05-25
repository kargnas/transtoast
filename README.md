# Copy Translator

Copy Translator is a macOS menu-bar app that translates copied text after pressing `Cmd+C` twice, similar to DeepL's quick translation workflow. It also captures the screen with `Shift+Cmd+2` and sends the image to an OpenRouter vision model for translation.

## Features

- `Cmd+C` twice: reads the clipboard text and translates it.
- `Shift+Cmd+2`: captures the current screen and translates visible text in the image.
- Toast results appear in the configured screen corner and stack when multiple translations finish close together.
- Text translation providers:
  - `tencent/Hy-MT2-30B-A3B` local inference by default.
  - `tencent/Hy-MT2-1.8B` local inference.
  - Any OpenRouter chat model ID.
- Screenshot translation uses an OpenRouter multimodal model. The default is `google/gemini-2.5-flash-lite`.
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

Copy Translator needs these macOS privacy permissions for the global shortcuts:

- **Input Monitoring** or **Accessibility** for `Cmd+C` twice from other apps.
- **Screen Recording** for `Shift+Cmd+2` screenshot translation.

Open the settings window and use **Permission Helper**. It opens the privacy pane and shows a draggable `CopyTranslator.app` icon. Drag that icon into the permission list, turn the toggle on if macOS adds it disabled, then relaunch Copy Translator.

You can also open System Settings manually:

```sh
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
```

After changing either keyboard or screen permissions, quit and relaunch Copy Translator so macOS applies the new trust state.

Development builds are signed with a stable local Apple Development identity when one is available. If a previous ad-hoc build was already listed in Screen Recording, remove that old `CopyTranslator` entry or toggle it off and on once after rebuilding. macOS can show the same app name for a stale code identity, but Copy Translator will report **Screen ready** only when the current signed bundle is actually trusted.

## Run

```sh
swift run CopyTranslator
```

Use the menu-bar icon to open options, request logs, provider/model selectors, permission helpers, and Quit. For local UI verification, you can launch the settings window directly:

```sh
open dist/CopyTranslator.app --args --show-settings
```

To build and install the app on this Mac:

```sh
./scripts/install-app.zsh --open
```

For another Mac, follow [docs/other-mac-setup.md](docs/other-mac-setup.md).

When **Text Provider** is **OpenRouter LLM**, Copy Translator automatically attaches the current screen as downscaled 1x visual context if macOS already reports Screen Recording as trusted. This context capture does not open a Screen Recording prompt during `Cmd+C` double-copy. Local Hy-MT2 translation remains text-only. Explicit screenshot translation through `Shift+Cmd+2`, the settings window's **Translate Screenshot** button, or `--screenshot-once` can still request Screen Recording when it is missing.

Open **Request Logs...** from the menu-bar icon to inspect recent translation requests. The log keeps the last 200 requests and shows whether token usage came from the provider response or an app-side estimate. OpenRouter requests report provider token usage when the response includes it; local Hy-MT2 requests use an estimate.

## Local Model Backend

The app calls a bundled copy of this local backend:

```sh
uv run scripts/hy_mt2_translate.py
```

The backend accepts JSON on standard input:

```json
{
  "text": "今天天气真好。",
  "target_language": "English",
  "model_id": "tencent/Hy-MT2-1.8B"
}
```

It prints:

```json
{
  "translation": "The weather is really nice today."
}
```

## Verification

Useful checks:

```sh
swift build
printf '{"text":"Hello world","target_language":"Korean","model_id":"tencent/Hy-MT2-1.8B"}' | uv run scripts/hy_mt2_translate.py
./scripts/build-app.zsh
./scripts/install-app.zsh --install-dir "$HOME/Applications"
./scripts/package-app.zsh
dist/CopyTranslator.app/Contents/MacOS/CopyTranslator --translate-text-once "Hello world"
dist/CopyTranslator.app/Contents/MacOS/CopyTranslator --translate-text-once "Hello world" --hy-mt2-model tencent/Hy-MT2-1.8B
dist/CopyTranslator.app/Contents/MacOS/CopyTranslator --translate-text-once "Hello world" --provider openrouter
dist/CopyTranslator.app/Contents/MacOS/CopyTranslator --screenshot-once
node scripts/openrouter_prompt_probe.mjs --capture
```

For UI verification, run the app, open TextEdit or another text field, copy text twice with `Cmd+C`, and confirm that a translation toast appears. Then use `Shift+Cmd+2` and confirm that a screenshot translation toast appears.
