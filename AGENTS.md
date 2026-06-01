# CopyTranslator Agent Notes

## Project Shape

- This is a SwiftPM-first macOS menu bar app (`LSUIElement`, macOS 15+, Swift 6.2 tools).
- The app bundle identifier must stay `as.kargn.copy-translator`.
- Keep secrets in local environment files only. Do not commit `.env.local`, token caches, or generated logs that contain credentials.

### Layout

- `Sources/CopyTranslatorCore/` — platform-free logic: `TranslationService`, `TranslatorSettings`, `EnvLoader`, `DoublePressDetector`.
- `Sources/CopyTranslator/` — AppKit shell: `main.swift` (entry + one-shot CLI modes), `AppDelegate`, monitors, windows, `CredentialsProvider`.
- `Tests/CopyTranslatorTests/` — `swift test` target.
- `scripts/` — `run-dev` / `build-app` / `install-app` / `package-app` (.zsh), `hy_mt2_translate.py` (uv backend), benchmark + probe tools.

### Stack

- Frameworks: AppKit, Carbon, CoreGraphics, ScreenCaptureKit.
- Local text translation: `tencent/Hy-MT2-*` via `uv run scripts/hy_mt2_translate.py`.
- OpenRouter for non-Hy-MT2 LLM text + screenshot vision translation.
- `CredentialsProvider` reads `.env.local` from the working directory, so launches with `cwd` = workspace root pick up `OPENROUTER_API_KEY` / `HF_TOKEN` without sourcing.

## Commands

```zsh
swift test
swift build
./scripts/run-dev.zsh
./scripts/build-app.zsh
```

## VS Code Workflow

- **Run/Debug (`.vscode/launch.json`)** — daemons and debug modes; `cwd` loads `.env.local` automatically:
  - `🚀 Run Dev (Debug)` — menu bar app with debugger attached.
  - `⚙️ Settings Window (Debug)` — launches straight into the settings window (`--show-settings`).
  - `Run Release` — release build run.
  - `Translate Text Once (Debug)` / `Screenshot Translate Once (Debug)` — one-shot pipeline checks that print and exit.
- **Tasks (`.vscode/tasks.json`, status bar via `actboy168.tasks`)** — occasional chores only:
  `📦 Setup: Create .env.local`, `🧪 Run Tests`, `🧹 Clean Build Artifacts`, `🛠️ Build & Install to /Applications`, `📮 Package App (.zip)`.
- `.vscode/settings.json` enforces swift-format on save and hides `.build` / `dist` / `models`. `.vscode/extensions.json` recommends `swiftlang.swift-vscode` + `actboy168.tasks`.

## Implementation Rules

- Keep the default UI language English.
- Keep the default translation target Korean unless the user asks for another default.
- Keep Hugging Face Hy-MT2 as the default text translation provider.
- Use OpenRouter for non-Hy-MT2 LLM translation and screenshot translation.
- Preserve the `Cmd+C` double-press and `Shift+Cmd+2` shortcuts when changing shortcut code.
- Design every setting as a code-default plus user override. Persist only values that differ from the current code default, show a `기본값으로 변경` reset button beside overridden settings, and remove the stored override when the user returns to the default so future default changes apply automatically.
